import AppKit
import NeyKit

/// Testes sem XCTest (só CommandLineTools): `Hub --selftest` roda tudo e a casca imprime "selftest ok".
/// O selftest roda em release, por isso precondition e não assert.
@MainActor
enum SelfTest {
    static func run() {
        // Antes de tudo: nada no selftest chega ao credentials.json de verdade, nem se um teste esquecer de trocar o caminho.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hub-test-\(UUID().uuidString)")
        Credentials.url = dir.appendingPathComponent("credentials.json")
        Credentials.readKeychain = { preconditionFailure("selftest leu o Chaveiro de verdade") }
        Log.enabled = false
        defer { try? FileManager.default.removeItem(at: dir) }
        // Antes de qualquer fonte registrada no processo: sem recursos não pode quebrar.
        missingResources()
        protocols()
        mealPlan()
        credentialsFolder(dir)
        oauth()
        hostedApp(dir)
        standaloneMigration(dir)
        appStop(dir)
    }

    /// Recurso do Hub ausente no plugin (Review Focus 5): fonte do sistema, SF Symbol no lugar da Lucide, o nome no lugar
    /// do logo, e fica no registro.
    private static func missingResources() {
        Theme.registerFonts(from: nil)
        precondition(!Theme.hasLucide && Theme.resources == nil)
        precondition(Theme.outfit(13, weight: 400) == nil, "Outfit sem estar empacotada")
        precondition(Log.last?.hasPrefix("recursos: fontes ausentes") == true, "sem aviso no registro: \(Log.last ?? "-")")
        let youtube = TVApps.App(name: "YouTube", link: "https://www.youtube.com")
        precondition(youtube.logo == nil)
        // Pasta que existe mas veio sem nada (empacotamento pela metade): o mesmo.
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("hub-empty-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        Theme.registerFonts(from: empty)
        precondition(!Theme.hasLucide && youtube.logo == nil && Log.last?.hasPrefix("recursos: fontes ausentes") == true)
        // Os do .app (o build copia Resources/Bundle para Contents/Resources).
        Theme.registerFonts(from: Bundle.main.resourceURL)
        precondition(Theme.hasLucide && Theme.outfit(13, weight: 400) != nil, "fontes do .app")
        precondition(youtube.logo != nil, "logo do YouTube no .app")
    }

    /// Os testes de antes da 0.2.0 (ADB, protobuf, cifra da Tuya).
    private static func protocols() {
        precondition(ADB.inputText("Ação 2'") == "Acao%s2'\\''", ADB.inputText("Ação 2'"))
        precondition(ADB.inputText("Stranger Things") == "Stranger%sThings")
        // Campo 1 com tamanho 2^64-1: tem que ser recusado, não travar o app.
        precondition(PBMessage(Data([0x0a] + [UInt8](repeating: 0xff, count: 9) + [0x01])) == nil)
        let secret = "0123456789abcdef"
        let sealed = try! TuyaClient.encrypt("{\"a\":1}", secret: secret)
        precondition(String(data: try! TuyaClient.decrypt(sealed, secret: secret), encoding: .utf8) == "{\"a\":1}")
    }

    private static func mealPlan() {
        // O plano gravado no alimentador tem que sair igual ao que foi lido (senão apaga refeições).
        let stored = "fwYAAgF/DAABAAATAAIBfxUAAQA="
        precondition(Meal.encode(Meal.decode(stored)) == stored, "plano: \(Meal.encode(Meal.decode(stored)))")
        precondition(Meal.encode([]) == "AA==" && Meal.decode("AA==").isEmpty)
        // Sábado 24/10/2026 22:40; 06:00 todo dia e 19:00 só no domingo (bit 6).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 22, minute: 40))!
        let plan = [Meal(days: 0x7f, hour: 6, portions: 2), Meal(days: 0x40, hour: 19), Meal(hour: 12, enabled: false)]
        let schedule = Meal.schedule(plan, now: now, calendar: calendar)
        let next = schedule.next.map { calendar.dateComponents([.day, .hour], from: $0.date) }
        precondition(next?.day == 25 && next?.hour == 6, "próxima: \(String(describing: next))")
        let previous = schedule.previous.map { calendar.dateComponents([.day, .hour], from: $0) }
        precondition(previous?.day == 24 && previous?.hour == 6, "anterior: \(String(describing: previous))")
        let sunday = Meal.schedule([plan[1]], now: now, calendar: calendar).next.map { calendar.dateComponents([.day, .hour], from: $0.date) }
        precondition(sunday?.day == 25 && sunday?.hour == 19, "domingo: \(String(describing: sunday))")
    }

    /// O `Credentials` lê e grava na pasta injetada (0600), e o arquivo estragado vira `.bad` em vez de sumir.
    private static func credentialsFolder(_ dir: URL) {
        let url = dir.appendingPathComponent("folder/credentials.json")
        Credentials.url = url
        precondition(Credentials.load() == Credentials())
        let saved = Credentials(androidTVs: [AndroidTVConfig(name: "TV", host: "192.0.2.1")])
        saved.save()
        precondition(Credentials.load() == saved)
        let mode = (try! FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
        precondition(mode == 0o600, "permissão \(String(mode, radix: 8))")
        try! Data("{".utf8).write(to: url)
        precondition(Credentials.load() == Credentials() && FileManager.default.fileExists(atPath: url.path + ".bad"))
    }

    /// hubmac://callback só com o `state` do login em andamento; o resto devolve false (o NeyHub avisa).
    private static func oauth() {
        var opened: [URL] = []
        var codes: [String] = []
        OAuthWindow.shared.open = { opened.append($0) }
        defer { OAuthWindow.shared.open = { NSWorkspace.shared.open($0) } }
        precondition(!OAuthWindow.shared.handle(URL(string: "hubmac://callback?code=x&state=")!), "sem login em andamento")
        OAuthWindow.shared.start(url: URL(string: "https://api.smartthings.com/oauth/authorize?client_id=a")!) { codes.append($0) }
        let state = opened.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value }
        precondition(opened.count == 1 && state?.isEmpty == false, "login não abriu com state")
        let app = HubApp(defaults: suite("oauth"), hosted: true, version: "9.9.9", resources: nil, credentials: Credentials.url)
        precondition(!app.handleURL(URL(string: "https://example.com/callback?code=abc&state=\(state!)")!))
        precondition(!app.handleURL(URL(string: "hubmac://callback?code=abc&state=errado")!))
        precondition(codes.isEmpty)
        precondition(app.handleURL(URL(string: "hubmac://callback?code=abc&state=\(state!)")!))
        precondition(codes == ["abc"])
        // Usado uma vez: repetir a mesma URL não loga de novo.
        precondition(!app.handleURL(URL(string: "hubmac://callback?code=abc&state=\(state!)")!) && codes == ["abc"])
    }

    /// Hospedado: sem Sair, sem login, sem modos e sem atualização; nunca lê o Chaveiro; padrões pelo domínio injetado.
    private static func hostedApp(_ dir: URL) {
        let hosted = PopoverState(version: "1", hosted: true, updateReady: true)
        precondition(!hosted.showsQuit && !hosted.showsLogin && !hosted.showsPresence && !hosted.showsUpdate)
        let solo = PopoverState(version: "1", hosted: false)
        precondition(solo.showsQuit && solo.showsLogin && solo.showsPresence && !solo.showsUpdate)
        precondition(PopoverState(version: "1", hosted: false, updateReady: true).showsUpdate)

        let defaults = suite("hosted")
        let url = dir.appendingPathComponent("hosted/credentials.json")
        var reads = 0
        Credentials.readKeychain = { reads += 1; return nil }
        defer { Credentials.readKeychain = { preconditionFailure("selftest leu o Chaveiro de verdade") } }
        let app = HubApp(defaults: defaults, hosted: true, version: "9.9.9", resources: nil, credentials: url)
        precondition(Credentials.url == url && !Credentials.migratesKeychain && app.shell.presence == nil)
        precondition(app.shell.state == PopoverState(version: "9.9.9", hosted: true))
        _ = Credentials.load()
        precondition(reads == 0, "hospedado leu o Chaveiro")
        TVApps.save([TVApps.defaults[0]])
        precondition(defaults.data(forKey: "tvApps") != nil, "lista de apps fora do domínio injetado")
        TVApps.save(TVApps.defaults)
        app.applyPresence(Presence(screen: true, menuBar: true))
        precondition(!app.hasStatusItem, "hospedado aplicou o modo sozinho")
    }

    /// Avulso: a migração antiga do Chaveiro roda uma vez e grava o arquivo (pelo leitor falso).
    private static func standaloneMigration(_ dir: URL) {
        let url = dir.appendingPathComponent("solo/credentials.json")
        // Sem TV nem conta: o HubStore do init não cria cliente nenhum (nada conversa com a rede).
        let old = Credentials(smartThingsApp: SmartThingsApp(clientId: "id", clientSecret: "segredo"))
        var reads = 0
        Credentials.readKeychain = { reads += 1; return old }
        defer { Credentials.readKeychain = { preconditionFailure("selftest leu o Chaveiro de verdade") } }
        // Só o init: o start() criaria o ícone.
        let app = HubApp(defaults: suite("solo"), hosted: false, version: "9.9.9", resources: nil, credentials: url)
        precondition(Credentials.migratesKeychain && app.shell.presence == Presence(screen: false, menuBar: true))
        app.store.stop()
        precondition(reads == 1 && Credentials.load() == old && reads == 1, "migração do avulso: \(reads)")
        Credentials.migratesKeychain = false
    }

    /// `stop()` (desinstalar no NeyHub): timers de 10 s e 12 h parados, TVs desligadas, sem ícone, sem monitor de cliques.
    private static func appStop(_ dir: URL) {
        let app = HubApp(defaults: suite("stop"), hosted: true, version: "9.9.9", resources: nil,
                         credentials: dir.appendingPathComponent("stop/credentials.json"))
        app.start()
        app.setMenuBarVisible(true)
        precondition(app.hasStatusItem)
        app.store.startPolling()
        app.store.startPolling() // popover e tela ao mesmo tempo
        precondition(app.store.polling && app.store.timersRunning)
        app.store.stopPolling()
        precondition(app.store.polling, "um só fechou: o timer de 10 s continua para o outro")
        app.stop()
        precondition(!app.store.timersRunning && app.store.tvConnections == 0 && !app.hasStatusItem && !app.watchingClicks)
    }

    /// Domínio de padrões próprio do teste, limpo a cada rodada.
    private static func suite(_ name: String) -> UserDefaults {
        let id = "local.hub.selftest.\(name)"
        let defaults = UserDefaults(suiteName: id)!
        defaults.removePersistentDomain(forName: id)
        return defaults
    }
}
