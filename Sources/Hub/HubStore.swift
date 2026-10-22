import Foundation

/// Junta as nuvens numa lista só, mantém os tokens e manda os comandos.
@MainActor
final class HubStore: ObservableObject {
    @Published private(set) var devices: [HubDevice] = []
    @Published private(set) var loading = false
    @Published private(set) var loadedOnce = false
    @Published var error: String?
    @Published private(set) var credentials: Credentials
    @Published private(set) var pairing: Pairing?

    struct Pairing: Equatable {
        var userCode: String
        var app: String
        var qrPayload: String?
        var message: String?
    }

    private var tuya: [String: TuyaClient] = [:]
    private var smartThings: SmartThingsClient?
    private var homes: [String: [TuyaClient.Home]] = [:]
    private var specs: [String: (functions: [String: DPSpec], status: [String: DPSpec])] = [:]
    private var rooms: [String: String] = [:]
    /// Valor mandado há pouco: a nuvem demora a refletir, então ele vale por alguns segundos
    /// mesmo que a próxima leitura ainda traga o antigo. Evita o botão "voltar" sozinho.
    private var pending: [String: [String: (value: DPValue, until: Date)]] = [:]
    private var pairingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var followUp: Task<Void, Never>?

    init(sample: Bool = false) {
        credentials = Credentials()
        if sample { loadSample(); return }
        credentials = .load()
        if let app = credentials.smartThingsApp, credentials.smartThings == nil {
            debugLog("smartthings: app OAuth \(app.clientId.prefix(8))… pronto, falta o login")
        }
        rebuildClients()
        // O refresh token do SmartThings vence se ficar 30 dias sem uso.
        Timer.scheduledTimer(withTimeInterval: 12 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in try? await self?.smartThings?.refreshIfNeeded(force: true) }
        }
    }

    var hasAccounts: Bool { !credentials.tuya.isEmpty || credentials.smartThings != nil }
    var anyOn: Bool { devices.contains { $0.online && $0.isOn } }

    private func rebuildClients() {
        tuya = [:]
        for account in credentials.tuya {
            let client = TuyaClient(account: account)
            client.onTokenChange = { [weak self] updated in
                guard let self, let index = credentials.tuya.firstIndex(where: { $0.uid == updated.uid }) else { return }
                credentials.tuya[index] = updated
                credentials.save()
            }
            tuya[account.uid] = client
        }
        smartThings = credentials.smartThings.map { auth in
            let client = SmartThingsClient(auth: auth)
            client.onTokenChange = { [weak self] updated in
                self?.credentials.smartThings = updated
                self?.credentials.save()
            }
            return client
        }
    }

    // MARK: Atualização

    func startPolling() {
        Task { await refresh() }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        let task = Task { @MainActor in await load() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func load() async {
        loading = true
        defer { loading = false; loadedOnce = true }
        var found: [HubDevice] = []
        var failures: [String] = []

        for (uid, client) in tuya {
            do { found += try await loadTuya(uid: uid, client: client) } catch {
                failures.append("Smart Life: \(error.localizedDescription)")
                found += devices.filter { $0.source == .tuya(account: uid) }
            }
        }
        if let smartThings {
            do { found += try await loadSmartThings(smartThings) } catch {
                failures.append("SmartThings: \(error.localizedDescription)")
                found += devices.filter { $0.source == .smartThings }
            }
        }

        let now = Date()
        for index in found.indices {
            for (code, entry) in pending[found[index].id] ?? [:] where entry.until > now {
                found[index].status[code] = entry.value
            }
        }
        pending = pending.mapValues { $0.filter { $0.value.until > now } }.filter { !$0.value.isEmpty }

        devices = found.sorted { ($0.kind, $0.name.localizedLowercase) < ($1.kind, $1.name.localizedLowercase) }
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private func loadTuya(uid: String, client: TuyaClient) async throws -> [HubDevice] {
        if homes[uid] == nil { homes[uid] = try await client.homes() }
        var result: [HubDevice] = []
        for home in homes[uid] ?? [] {
            for json in try await client.devices(home: home.id) {
                guard let id = json["id"] as? String else { continue }
                let category = json["category"] as? String ?? ""
                var device = HubDevice(
                    id: id, name: json["name"] as? String ?? "Aparelho", source: .tuya(account: uid),
                    category: category, kind: HubDevice.tuyaKind(category: category),
                    online: json["online"] as? Bool ?? false
                )
                for item in json["status"] as? [[String: Any]] ?? [] {
                    if let code = item["code"] as? String { device.status[code] = DPValue(item["value"]) }
                }
                if specs[id] == nil, let spec = try? await client.specifications(device: id) {
                    specs[id] = (Dictionary(spec.functions.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a }),
                                 Dictionary(spec.status.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a }))
                    if let room = try? await client.room(device: id) { rooms[id] = room }
                }
                device.functions = specs[id]?.functions ?? [:]
                device.statusSpecs = specs[id]?.status ?? [:]
                device.room = rooms[id]
                result.append(device)
            }
        }
        return result
    }

    private func loadSmartThings(_ client: SmartThingsClient) async throws -> [HubDevice] {
        var result: [HubDevice] = []
        for json in try await client.devices() {
            guard let id = json["deviceId"] as? String else { continue }
            let components = json["components"] as? [[String: Any]] ?? []
            let main = components.first { $0["id"] as? String == "main" } ?? components.first ?? [:]
            let capabilities = Set((main["capabilities"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
            let isAC = capabilities.contains("airConditionerMode")
            var device = HubDevice(
                id: id, name: json["label"] as? String ?? json["name"] as? String ?? "Aparelho",
                source: .smartThings, category: (main["categories"] as? [[String: Any]])?.first?["name"] as? String ?? "",
                kind: isAC ? .airConditioner : capabilities.contains("switchLevel") ? .light
                    : capabilities.contains("switch") ? .plug : .other,
                online: true, capabilities: capabilities
            )
            device.status = (try? await client.status(device: id)) ?? [:]
            if let health = device.status["healthCheck.DeviceWatch-DeviceStatus"]?.string {
                device.online = health != "offline"
            }
            // Celulares, TVs desligadas e afins não interessam aqui.
            guard isAC || capabilities.contains("switch") else { continue }
            result.append(device)
        }
        return result
    }

    // MARK: Comandos

    func toggle(_ device: HubDevice) {
        switch device.source {
        case .smartThings:
            let on = !device.isOn
            stCommand(device, capability: "switch", command: on ? "on" : "off",
                      optimistic: ["switch.switch": .string(on ? "on" : "off")])
        case .tuya:
            guard let code = device.powerCode else { return }
            setTuya(device, code, !device.isOn)
        }
    }

    func setTuya(_ device: HubDevice, _ code: String, _ value: Any) {
        setTuya(device, [(code, value)])
    }

    func setTuya(_ device: HubDevice, _ commands: [(code: String, value: Any)]) {
        guard case .tuya(let uid) = device.source, let client = tuya[uid] else { return }
        apply(device.id, Dictionary(commands.map { ($0.code, DPValue($0.value)) }, uniquingKeysWith: { _, b in b }))
        debugLog("tuya: \(device.name) \(commands.map { "\($0.code)=\($0.value)" }.joined(separator: " "))")
        Task {
            do { try await client.send(device: device.id, commands: commands) } catch {
                self.error = "\(device.name): \(error.localizedDescription)"
                pending[device.id] = nil
            }
            scheduleFollowUp()
        }
    }

    func stCommand(_ device: HubDevice, capability: String, command: String, arguments: [Any] = [],
                   optimistic: [String: DPValue] = [:]) {
        guard let smartThings else { return }
        apply(device.id, optimistic)
        debugLog("smartthings: \(device.name) \(capability).\(command) \(arguments)")
        Task {
            do { try await smartThings.command(device: device.id, capability: capability, command: command, arguments: arguments) } catch {
                self.error = "\(device.name): \(error.localizedDescription)"
                pending[device.id] = nil
            }
            scheduleFollowUp()
        }
    }

    private func apply(_ id: String, _ values: [String: DPValue]) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let until = Date().addingTimeInterval(8)
        for (code, value) in values {
            devices[index].status[code] = value
            pending[id, default: [:]][code] = (value, until)
        }
    }

    /// Lê de novo um pouco depois de um comando, para pegar o que o aparelho confirmou.
    private func scheduleFollowUp() {
        followUp?.cancel()
        followUp = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// JSON cru da nuvem Tuya, para o `Hub --raw`.
    func rawTuya() async -> [[String: Any]] {
        var all: [[String: Any]] = []
        for client in tuya.values {
            for home in (try? await client.homes()) ?? [] {
                all += (try? await client.devices(home: home.id)) ?? []
            }
        }
        return all
    }

    /// Aparelhos de exemplo para o `Hub --render`.
    func loadSample() {
        func spec(_ code: String, _ type: String, _ values: [String: Any] = [:]) -> (String, DPSpec) {
            (code, DPSpec(json: ["code": code, "type": type, "values": values]))
        }
        var ac = HubDevice(id: "ac", name: "Ar do quarto", source: .smartThings, category: "AirConditioner",
                           kind: .airConditioner, online: true, capabilities: ["switch", "airConditionerMode"])
        ac.status = ["switch.switch": .string("on"), "airConditionerMode.airConditionerMode": .string("cool"),
                     "thermostatCoolingSetpoint.coolingSetpoint": .double(23), "temperatureMeasurement.temperature": .double(27),
                     "relativeHumidityMeasurement.humidity": .int(58), "airConditionerFanMode.fanMode": .string("auto"),
                     "custom.airConditionerOptionalMode.supportedAcOptionalMode": .other("[\"off\",\"windFree\",\"sleep\",\"speed\"]"),
                     "custom.airConditionerOptionalMode.acOptionalMode": .string("off")]
        var light = HubDevice(id: "light", name: "Luz da sala", source: .tuya(account: "x"), category: "dj", kind: .light, online: true)
        light.functions = Dictionary(uniqueKeysWithValues: [spec("switch_led", "Boolean"),
            spec("bright_value_v2", "Integer", ["min": 10, "max": 1000]), spec("temp_value_v2", "Integer", ["min": 0, "max": 1000]),
            spec("work_mode", "Enum", ["range": ["white", "colour", "scene"]]), spec("colour_data_v2", "Json")])
        light.status = ["switch_led": .bool(true), "bright_value_v2": .int(700), "temp_value_v2": .int(300), "work_mode": .string("white")]
        var plug = HubDevice(id: "plug", name: "Tomada do PC", source: .tuya(account: "x"), category: "cz", kind: .plug, online: true)
        plug.functions = Dictionary(uniqueKeysWithValues: [spec("switch_1", "Boolean"), spec("child_lock", "Boolean"),
            spec("relay_status", "Enum", ["range": ["power_off", "power_on", "last"]])])
        plug.statusSpecs = Dictionary(uniqueKeysWithValues: [spec("cur_power", "Integer", ["scale": 1, "unit": "W"]),
            spec("cur_voltage", "Integer", ["scale": 1, "unit": "V"])])
        plug.status = ["switch_1": .bool(true), "cur_power": .int(1254), "cur_voltage": .int(1271), "relay_status": .string("last")]
        var lamp = HubDevice(id: "lamp", name: "Abajur", source: .tuya(account: "x"), category: "dj", kind: .light, online: true)
        lamp.functions = light.functions
        lamp.status = ["switch_led": .bool(false)]
        var feeder = HubDevice(id: "feeder", name: "Ração dos gatos", source: .tuya(account: "x"), category: "cwwsq", kind: .feeder, online: true)
        feeder.functions = Dictionary(uniqueKeysWithValues: [spec("manual_feed", "Integer", ["min": 1, "max": 12]),
            spec("light", "Boolean"), spec("slow_feed", "Boolean")])
        feeder.status = ["feed_state": .string("standby"), "feed_report": .int(2), "light": .bool(true)]
        var tv = HubDevice(id: "tv", name: "TV da sala", source: .tuya(account: "x"), category: "infrared_tv", kind: .remote, online: true)
        tv.status = [:]
        var fan = HubDevice(id: "fan", name: "Ventilador", source: .tuya(account: "x"), category: "cz", kind: .plug, online: false)
        fan.functions = plug.functions
        devices = [ac, light, lamp, plug, fan, feeder, tv]
        credentials = Credentials(tuya: [TuyaAccount(userCode: "", uid: "x", username: "voce@email.com", endpoint: "",
                                                     terminalId: "", accessToken: "", refreshToken: "", expireTime: 0)])
        loadedOnce = true
    }

    // MARK: Contas

    func startPairing(userCode: String, app: String) {
        let code = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        pairingTask?.cancel()
        pairing = Pairing(userCode: code, app: app, message: "Gerando QR code…")
        pairingTask = Task {
            do {
                let qr = try await TuyaClient.requestQRCode(userCode: code)
                pairing = Pairing(userCode: code, app: app, qrPayload: qr.payload, message: "Aguardando o celular…")
                let deadline = Date().addingTimeInterval(5 * 60)
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(2))
                    if var account = try? await TuyaClient.pollLogin(qr: qr, userCode: code) {
                        account.app = app
                        credentials.tuya.removeAll { $0.uid == account.uid }
                        credentials.tuya.append(account)
                        credentials.save()
                        rebuildClients()
                        pairing = nil
                        debugLog("tuya: conta conectada (\(account.username))")
                        await refresh()
                        return
                    }
                }
                pairing?.message = "O QR code expirou. Gere outro."
                pairing?.qrPayload = nil
            } catch is CancellationError {
            } catch {
                pairing = Pairing(userCode: code, app: app, message: "Erro: \(error.localizedDescription)")
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairing = nil
    }

    func renameTuya(uid: String, app: String) {
        guard let index = credentials.tuya.firstIndex(where: { $0.uid == uid }) else { return }
        credentials.tuya[index].app = app
        credentials.save()
        tuya[uid].map { _ in rebuildClients() }
    }

    func removeTuya(uid: String) {
        credentials.tuya.removeAll { $0.uid == uid }
        credentials.save()
        homes[uid] = nil
        devices.removeAll { $0.source == .tuya(account: uid) }
        rebuildClients()
    }

    func connectSmartThings(clientId: String, clientSecret: String) {
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { return }
        OAuthWindow.shared.start(url: SmartThingsClient.authorizationURL(clientId: id)) { [weak self] code in
            Task { @MainActor in
                do {
                    let auth = try await SmartThingsClient.exchange(code: code, clientId: id, clientSecret: secret)
                    self?.saveSmartThings(auth)
                } catch {
                    self?.error = "SmartThings: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Lê a saída JSON do `smartthings apps:create` e guarda Client ID e Secret no Keychain.
    func importSmartThingsApp(file: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["oauthClientId"] as? String, let secret = json["oauthClientSecret"] as? String
        else { return false }
        credentials.smartThingsApp = SmartThingsApp(clientId: id, clientSecret: secret)
        credentials.save()
        return true
    }

    /// Token pessoal colado à mão: funciona na hora, mas vence em 24 h.
    func useSmartThingsToken(_ token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        saveSmartThings(SmartThingsAuth(clientId: "", clientSecret: "", accessToken: token, refreshToken: "",
                                        expiresAt: Date().addingTimeInterval(86_400)))
    }

    private func saveSmartThings(_ auth: SmartThingsAuth) {
        credentials.smartThings = auth
        if !auth.clientId.isEmpty { credentials.smartThingsApp = SmartThingsApp(clientId: auth.clientId, clientSecret: auth.clientSecret) }
        credentials.save()
        rebuildClients()
        debugLog("smartthings: conectado")
        Task { await refresh() }
    }

    func disconnectSmartThings() {
        credentials.smartThings = nil
        credentials.save()
        devices.removeAll { $0.source == .smartThings }
        rebuildClients()
    }
}
