import CryptoKit
import Foundation
import Network
import Security

// Controle de TVs com Google TV / Android TV pelo mesmo protocolo do app "Google TV" do celular
// (Android TV Remote v2, portado do androidtvremote2). Tudo local, sem nuvem:
//   - porta 6467: pareamento, uma vez só, com o código de 6 caracteres que aparece na TV;
//   - porta 6466: controle (teclas, volume, abrir apps), mantido aberto para saber o estado.
// As duas usam TLS com um certificado do Hub; é por ele que a TV reconhece o Mac depois.

// MARK: Protobuf mínimo

struct PB {
    var data = Data()

    static func varint(_ value: UInt64) -> Data {
        var value = value
        var out = Data()
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    mutating func int(_ field: Int, _ value: Int) {
        data += PB.varint(UInt64(field << 3))
        data += PB.varint(UInt64(bitPattern: Int64(value)))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        data += PB.varint(UInt64(field << 3 | 2))
        data += PB.varint(UInt64(value.count))
        data += value
    }

    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }

    mutating func message(_ field: Int, _ build: (inout PB) -> Void) {
        var inner = PB()
        build(&inner)
        bytes(field, inner.data)
    }

    static func build(_ build: (inout PB) -> Void) -> PB {
        var pb = PB()
        build(&pb)
        return pb
    }
}

/// Mensagem recebida: número do campo → valor (varint ou bytes). Basta para o que a TV manda.
struct PBMessage {
    var varints: [Int: UInt64] = [:]
    var fields: [Int: Data] = [:]

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            guard let key = PBMessage.readVarint(bytes, &index) else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let value = PBMessage.readVarint(bytes, &index) else { return nil }
                varints[field] = value
            case 1:
                index += 8
            case 2:
                guard let length = PBMessage.readVarint(bytes, &index), index + Int(length) <= bytes.count else { return nil }
                fields[field] = Data(bytes[index..<index + Int(length)])
                index += Int(length)
            case 5:
                index += 4
            default:
                return nil
            }
        }
    }

    func has(_ field: Int) -> Bool { varints[field] != nil || fields[field] != nil }
    func message(_ field: Int) -> PBMessage? { fields[field].flatMap(PBMessage.init) }
    func int(_ field: Int) -> Int { Int(truncatingIfNeeded: varints[field] ?? 0) }
    func string(_ field: Int) -> String { fields[field].flatMap { String(data: $0, encoding: .utf8) } ?? "" }

    static func readVarint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}

enum ATVError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

// MARK: Certificado do Hub

/// Chave RSA e certificado autoassinado, gerados uma vez com o openssl do sistema e guardados ao
/// lado das credenciais. A identidade é importada só em memória (sem tocar no Keychain).
enum ATVIdentity {
    private static let dir = Credentials.url.deletingLastPathComponent()
    private static let p12 = dir.appendingPathComponent("androidtv.p12")
    private static let password = "hub"
    private static var cached: (identity: SecIdentity, modulus: Data, exponent: Data)?

    static func load() throws -> (identity: SecIdentity, modulus: Data, exponent: Data) {
        if let cached { return cached }
        if !FileManager.default.fileExists(atPath: p12.path) { try generate() }
        let data = try Data(contentsOf: p12)
        let options: [String: Any] = [kSecImportExportPassphrase as String: password,
                                      kSecImportToMemoryOnly as String: true]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let value = first[kSecImportItemIdentity as String]
        else { throw ATVError.message("não consegui abrir o certificado (\(status))") }
        let identity = value as! SecIdentity
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        guard let certificate, let key = rsaNumbers(of: certificate) else { throw ATVError.message("certificado sem chave RSA") }
        cached = (identity, key.modulus, key.exponent)
        return cached!
    }

    private static func generate() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("hub-atv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let key = temp.appendingPathComponent("key.pem").path
        let cert = temp.appendingPathComponent("cert.pem").path
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                     "-days", "3650", "-subj", "/CN=atvremote"])
        try openssl(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12.path, "-passout", "pass:\(password)"])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p12.path)
        debugLog("androidtv: certificado do Hub criado")
    }

    private static func openssl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ATVError.message("openssl falhou: \(arguments.first ?? "")") }
    }

    /// Módulo e expoente da chave pública, sem zeros à esquerda (é assim que entram no hash do pareamento).
    static func rsaNumbers(of certificate: SecCertificate) -> (modulus: Data, exponent: Data)? {
        guard let key = SecCertificateCopyKey(certificate),
              let der = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else { return nil }
        // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
        let bytes = [UInt8](der)
        var index = 0
        func length() -> Int? {
            guard index < bytes.count else { return nil }
            let first = Int(bytes[index]); index += 1
            if first < 0x80 { return first }
            var value = 0
            for _ in 0..<(first & 0x7f) {
                guard index < bytes.count else { return nil }
                value = value << 8 | Int(bytes[index]); index += 1
            }
            return value
        }
        func integer() -> Data? {
            guard index < bytes.count, bytes[index] == 0x02 else { return nil }
            index += 1
            guard let count = length(), index + count <= bytes.count else { return nil }
            var value = Data(bytes[index..<index + count])
            index += count
            while value.count > 1, value.first == 0 { value.removeFirst() }
            return value
        }
        guard bytes.first == 0x30 else { return nil }
        index = 1
        _ = length()
        guard let modulus = integer(), let exponent = integer() else { return nil }
        return (modulus, exponent)
    }
}

// MARK: Conexão TLS com mensagens prefixadas pelo tamanho

final class ATVConnection {
    private let connection: NWConnection
    private var buffer = Data()
    private let peer = PeerBox()
    var onMessage: ((PBMessage) -> Void)?
    var onClose: ((String?) -> Void)?
    private var closed = false

    private final class PeerBox { var certificate: SecCertificate? }

    var serverCertificate: SecCertificate? { peer.certificate }

    init(host: String, port: UInt16, identity: SecIdentity) {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(options, sec_identity_create(identity)!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        let box = peer
        // A TV usa certificado autoassinado: aceita e guarda, porque o hash do pareamento usa a chave dela.
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            box.certificate = (SecTrustCopyCertificateChain(ref) as? [SecCertificate])?.first
            complete(true)
        }, .main)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
                                  using: NWParameters(tls: tls, tcp: tcp))
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; continuation.resume() }
                    self?.receive()
                case .failed(let error), .waiting(let error):
                    if !resumed { resumed = true; continuation.resume(throwing: error) }
                    self?.close(reason: "\(error)")
                case .cancelled:
                    if !resumed { resumed = true; continuation.resume(throwing: ATVError.message("conexão cancelada")) }
                    self?.close(reason: nil)
                default:
                    break
                }
            }
            connection.start(queue: .main)
        }
    }

    func send(_ pb: PB) {
        connection.send(content: PB.varint(UInt64(pb.data.count)) + pb.data, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                buffer += data
                drain()
            }
            if complete || error != nil {
                close(reason: error.map { "\($0)" })
                connection.cancel()
            } else {
                receive()
            }
        }
    }

    private func drain() {
        while true {
            let bytes = [UInt8](buffer)
            var index = 0
            guard let length = PBMessage.readVarint(bytes, &index), bytes.count >= index + Int(length) else { return }
            let body = Data(bytes[index..<index + Int(length)])
            buffer = Data(bytes[(index + Int(length))...])
            if let message = PBMessage(body) { onMessage?(message) }
        }
    }

    private func close(reason: String?) {
        guard !closed else { return }
        closed = true
        onClose?(reason)
    }
}

// MARK: Pareamento (porta 6467)

/// Pede o pareamento, a TV mostra um código hexadecimal de 6 caracteres, o usuário digita e o
/// Hub prova que viu o código com um hash das duas chaves públicas.
@MainActor
final class ATVPairing {
    let host: String
    private var connection: ATVConnection?
    private var waiting: CheckedContinuation<Void, Error>?
    private var waitingFor = 0

    init(host: String) {
        self.host = host
    }

    private static func outer(_ build: (inout PB) -> Void) -> PB {
        PB.build { pb in
            pb.int(1, 2)      // protocol_version
            pb.int(2, 200)    // STATUS_OK
            build(&pb)
        }
    }

    /// Até a TV mostrar o código na tela.
    func start(clientName: String) async throws {
        let identity = try ATVIdentity.load()
        let connection = ATVConnection(host: host, port: 6467, identity: identity.identity)
        self.connection = connection
        connection.onMessage = { [weak self] message in MainActor.assumeIsolated { self?.handle(message) } }
        connection.onClose = { [weak self] reason in
            MainActor.assumeIsolated { self?.fail("a TV fechou a conexão\(reason.map { " (\($0))" } ?? "")") }
        }
        try await connection.start()
        try await wait(for: 31) {
            connection.send(Self.outer { pb in
                pb.message(10) { request in
                    request.string(1, "atvremote")
                    request.string(2, clientName)
                }
            })
        }
    }

    func finish(code: String) async throws {
        let code = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 6, let suffix = Data(hex: String(code.dropFirst(2))), let check = UInt8(code.prefix(2), radix: 16) else {
            throw ATVError.message("O código tem 6 caracteres (0–9 e A–F).")
        }
        guard let connection, let server = connection.serverCertificate,
              let serverKey = ATVIdentity.rsaNumbers(of: server) else { throw ATVError.message("perdi a conexão com a TV") }
        let client = try ATVIdentity.load()
        var hash = SHA256()
        hash.update(data: client.modulus)
        hash.update(data: client.exponent)
        hash.update(data: serverKey.modulus)
        hash.update(data: serverKey.exponent)
        hash.update(data: suffix)
        let secret = Data(hash.finalize())
        guard secret.first == check else { throw ATVError.message("Código errado. Confira o que está na tela da TV.") }
        try await wait(for: 41) {
            connection.send(Self.outer { pb in pb.message(40) { $0.bytes(1, secret) } })
        }
        connection.cancel()
    }

    func cancel() {
        connection?.onClose = nil
        connection?.cancel()
        fail("cancelado")
    }

    private func wait(for field: Int, send: () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiting = continuation
            waitingFor = field
            send()
        }
    }

    private func handle(_ message: PBMessage) {
        guard message.int(2) == 200 else {
            return fail(message.int(2) == 402 ? "Código errado." : "a TV recusou (status \(message.int(2)))")
        }
        if message.has(11) {
            // pairing_request_ack → nossas opções: código hexadecimal de 6, nós digitamos.
            connection?.send(Self.outer { pb in
                pb.message(20) { options in
                    options.message(1) { encoding in encoding.int(1, 3); encoding.int(2, 6) }
                    options.int(3, 1)
                }
            })
        } else if message.has(20) {
            connection?.send(Self.outer { pb in
                pb.message(30) { configuration in
                    configuration.message(1) { encoding in encoding.int(1, 3); encoding.int(2, 6) }
                    configuration.int(2, 1)
                }
            })
        } else if message.has(waitingFor) {
            let continuation = waiting
            waiting = nil
            continuation?.resume()
        }
    }

    private func fail(_ reason: String) {
        let continuation = waiting
        waiting = nil
        continuation?.resume(throwing: ATVError.message(reason))
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

// MARK: Controle (porta 6466)

@MainActor
final class ATVRemote {
    enum Key: Int {
        case home = 3, back = 4, up = 19, down = 20, left = 21, right = 22, center = 23
        case volumeUp = 24, volumeDown = 25, power = 26, menu = 82, playPause = 85, mute = 164
        case settings = 176, input = 178, delete = 67, enter = 66
    }

    let host: String
    private(set) var connected = false
    private(set) var isOn: Bool?
    private(set) var volume: (level: Int, max: Int, muted: Bool)?
    private(set) var app: String?
    /// A TV recusou nosso certificado: precisa parear de novo.
    private(set) var needsPairing = false
    var onChange: (() -> Void)?

    private var connection: ATVConnection?
    private var reconnect: Task<Void, Never>?
    private var failures = 0
    private var stopped = false
    /// PING | KEY | IME | POWER | VOLUME | APP_LINK. Sem IME a TV não conta qual app está aberto.
    private var features = 615
    /// Comandos dados enquanto a conexão estava caída; saem assim que ela volta.
    private var queued: [PB] = []

    init(host: String) {
        self.host = host
    }

    func start() {
        stopped = false
        guard connection == nil else { return }
        reconnect?.cancel()
        Task { await connect() }
    }

    func stop() {
        stopped = true
        reconnect?.cancel()
        connection?.onClose = nil
        connection?.cancel()
        connection = nil
        connected = false
    }

    func send(_ key: Key) {
        deliver(PB.build { pb in pb.message(10) { inject in inject.int(1, key.rawValue); inject.int(2, 3) } })
    }

    func launch(_ link: String) {
        deliver(PB.build { pb in pb.message(90) { $0.string(1, link) } })
    }

    private func deliver(_ message: PB) {
        guard let connection, connected else {
            queued.append(message)
            return start()
        }
        connection.send(message)
    }

    private func connect() async {
        do {
            let identity = try ATVIdentity.load()
            let connection = ATVConnection(host: host, port: 6466, identity: identity.identity)
            self.connection = connection
            connection.onMessage = { [weak self] message in MainActor.assumeIsolated { self?.handle(message) } }
            connection.onClose = { [weak self] reason in MainActor.assumeIsolated { self?.closed(reason) } }
            try await connection.start()
        } catch {
            closed("\(error)")
        }
    }

    private func closed(_ reason: String?) {
        let wasConnected = connected
        debugLog("androidtv: conexão caiu\(reason.map { " (\($0))" } ?? "")")
        connection = nil
        connected = false
        // TLS que cai antes da TV mandar a configuração = certificado não reconhecido.
        if !wasConnected, let reason, reason.contains("-9806") || reason.contains("-9825") || reason.lowercased().contains("certificate") {
            needsPairing = true
        }
        onChange?()
        guard !stopped else { return }
        failures += 1
        let delay = min(5.0 * Double(failures), 30)
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            await self.connect()
        }
    }

    private func handle(_ message: PBMessage) {
        guard let connection else { return }
        if let configure = message.message(1) {
            features &= configure.int(1) == 0 ? features : configure.int(1)
            connection.send(PB.build { pb in
                pb.message(1) { reply in
                    reply.int(1, features)
                    reply.message(2) { info in
                        info.int(3, 1)
                        info.string(4, "1")
                        info.string(5, "atvremote")
                        info.string(6, "1.0.0")
                    }
                }
            })
        } else if message.has(2) {
            connection.send(PB.build { pb in pb.message(2) { $0.int(1, features) } })
            connected = true
            needsPairing = false
            failures = 0
            debugLog("androidtv: conectado a \(host)")
            queued.forEach { connection.send($0) }
            queued = []
            onChange?()
        } else if let ping = message.message(8) {
            connection.send(PB.build { pb in pb.message(9) { $0.int(1, ping.int(1)) } })
        } else if let start = message.message(40) {
            isOn = start.varints[1] == 1
            onChange?()
        } else if let level = message.message(50) {
            volume = (level.int(7), level.int(6), level.varints[8] == 1)
            onChange?()
        } else if let ime = message.message(20), let info = ime.message(1) {
            let package = info.string(12)
            if !package.isEmpty, package != app { app = package; debugLog("androidtv: app aberto \(package)"); onChange?() }
        }
    }
}

// MARK: Descoberta na rede

/// Procura TVs anunciando _androidtvremote2._tcp e resolve o IPv4 de cada uma.
@MainActor
final class ATVDiscovery {
    struct Found: Identifiable, Equatable {
        let name: String
        let host: String
        var id: String { host }
    }

    private var probes: [NWConnection] = []

    /// A TCL, por exemplo, não anuncia _androidtvremote2, só AirPlay, HomeKit e Cast. Então procura
    /// em todos e fica com quem tem a porta 6466 aberta.
    func scan(seconds: Double = 5) async -> [Found] {
        var candidates: [Found] = []
        var ranks: [String: Int] = [:]
        // Em ordem de preferência para o nome: o do AirPlay/HomeKit é o que o usuário escolheu.
        let types = ["_airplay._tcp", "_hap._tcp", "_androidtvremote2._tcp", "_googlecast._tcp"]
        let browsers = types.map { NWBrowser(for: .bonjour(type: $0, domain: nil), using: .tcp) }
        for browser in browsers {
            browser.browseResultsChangedHandler = { [weak self, browser] results, _ in
                MainActor.assumeIsolated {
                    for result in results {
                        guard case .service(let name, _, _, _) = result.endpoint else { continue }
                        let rank = types.firstIndex(of: browser.descriptor.bonjourType) ?? types.count
                        self?.resolve(result.endpoint) { host in
                            if let index = candidates.firstIndex(where: { $0.host == host }) {
                                guard rank < ranks[host] ?? .max else { return }
                                candidates[index] = Found(name: name, host: host)
                            } else {
                                candidates.append(Found(name: name, host: host))
                            }
                            ranks[host] = rank
                        }
                    }
                }
            }
            browser.start(queue: .main)
        }
        try? await Task.sleep(for: .seconds(seconds))
        browsers.forEach { $0.cancel() }
        probes.forEach { $0.cancel() }
        probes = []
        var found: [Found] = []
        for candidate in candidates where await Self.isOpen(host: candidate.host, port: 6466) {
            found.append(candidate)
        }
        return found
    }

    static func isOpen(host: String, port: UInt16) async -> Bool {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var done = false
            func finish(_ value: Bool) {
                guard !done else { return }
                done = true
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish(false) }
        }
    }

    private func resolve(_ endpoint: NWEndpoint, done: @escaping (String) -> Void) {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let probe = NWConnection(to: endpoint, using: parameters)
        probes.append(probe)
        probe.stateUpdateHandler = { [weak probe] state in
            guard case .ready = state, let probe else { return }
            if case .hostPort(let host, _)? = probe.currentPath?.remoteEndpoint {
                var text = "\(host)"
                if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                done(text)
            }
            probe.cancel()
        }
        probe.start(queue: .main)
    }
}

private extension NWBrowser.Descriptor {
    var bonjourType: String {
        if case .bonjour(let type, _) = self { return type }
        return ""
    }
}

// MARK: ADB (opcional)

/// Abre apps pelo ADB da TV, igual à tela inicial. Precisa da depuração pela rede ligada na TV e do
/// Mac autorizado nela (a TV pergunta na primeira vez).
/// shortcut: usa o adb do Homebrew (brew install --cask android-platform-tools); sem ele, cai no link do controle.
enum ADB {
    static let path = "/opt/homebrew/bin/adb"

    static func launch(package: String, host: String) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        guard let target = await device(host: host) else {
            debugLog("adb: TV não encontrada (depuração desligada ou não pareada)")
            return false
        }
        // Apps de TV declaram LEANBACK_LAUNCHER; alguns só têm o LAUNCHER comum.
        for category in ["android.intent.category.LEANBACK_LAUNCHER", "android.intent.category.LAUNCHER"] {
            let output = await run(["-s", target, "shell", "monkey", "-p", package, "-c", category, "1"])
            if output.contains("Events injected") { return true }
            debugLog("adb: \(package) não abriu (\(output.split(separator: "\n").last ?? ""))")
            if output.contains("unauthorized") || output.contains("failed to connect") || output.contains("not found") { break }
        }
        return false
    }

    /// Depuração clássica (porta 5555) ou "depuração por Wi‑Fi" do Android 11+, que o adb acha
    /// sozinho pelo mDNS depois do pareamento (adb pair) e cuja porta muda a cada vez.
    private static func device(host: String) async -> String? {
        _ = await run(["connect", "\(host):5555"])
        let lines = await run(["devices"]).split(separator: "\n").map { $0.split(separator: "\t") }
        let ready = lines.filter { $0.count == 2 && $0[1] == "device" }.map { String($0[0]) }
        return ready.first { $0.hasPrefix(host) } ?? ready.first { $0.contains("_adb-tls-connect") }
    }

    /// Digita no campo selecionado na TV. O `input text` do Android só aceita ASCII, então tira
    /// os acentos; espaço vira %s e o resto vai entre aspas simples para o shell da TV.
    static func type(_ text: String, host: String) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path), let target = await device(host: host) else { return false }
        let safe = inputText(text)
        guard !safe.isEmpty else { return false }
        let output = await run(["-s", target, "shell", "input text '\(safe)'"])
        if !output.isEmpty { debugLog("adb: digitar falhou (\(output.prefix(120)))") }
        return output.isEmpty
    }

    /// "Ação 2'" → `Acao%s2'\''` (sem acento, espaço como %s, aspa simples escapada para o shell).
    static func inputText(_ text: String) -> String {
        (text.applyingTransform(.stripDiacritics, reverse: false) ?? text)
            .unicodeScalars.filter(\.isASCII).map(String.init).joined()
            .replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "'", with: "'\\''")
    }

    /// Tecla pelo ADB: no teclado da busca a TV ignora o apagar que chega pelo protocolo do controle.
    static func key(_ code: Int, host: String) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path), let target = await device(host: host) else { return false }
        return await run(["-s", target, "shell", "input keyevent \(code)"]).isEmpty
    }

    /// Espera o teclado da TV aparecer (até 4 s) e digita; mais rápido que uma espera fixa.
    static func typeWhenReady(_ text: String, host: String) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path), let target = await device(host: host) else { return false }
        for _ in 0..<16 {
            if await run(["-s", target, "shell", "dumpsys input_method | grep -c mInputShown=true"]).hasPrefix("1") { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return await type(text, host: host)
    }

    /// Busca do Globoplay, o único app da TV que declara ACTION_SEARCH.
    static func search(_ query: String, package: String, host: String) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path), let target = await device(host: host) else { return false }
        let quoted = "'" + query.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let output = await run(["-s", target, "shell", "am start -a android.intent.action.SEARCH -p \(package) --es query \(quoted)"])
        return output.contains("Starting") && !output.contains("Error")
    }

    static func pair(host: String, port: String, code: String) async -> String {
        await run(["pair", "\(host):\(port)", code])
    }

    private static func run(_ arguments: [String]) async -> String {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return "" }
            // A TV desligada ou sem depuração não pode travar o clique.
            let timer = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
