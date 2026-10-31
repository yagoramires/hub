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
        icons()
        grafite()
        protocols()
        mealPlan()
        credentialsFolder(dir)
        oauth()
        hostedApp(dir)
        standaloneMigration(dir)
        appStop(dir)
        loginRoute()
    }

    /// hubmac:// no avulso: com o NeyHub rodando o Hub vai para o NeyHub (o login em andamento é de lá); senão fica aqui
    /// ou espera o HubApp nascer.
    private static func loginRoute() {
        let neyHub = URL(fileURLWithPath: "/Applications/NeyHub.app")
        precondition(LoginRoute.decide(hosted: true, neyHub: neyHub, started: false) == .neyHub(neyHub))
        precondition(LoginRoute.decide(hosted: true, neyHub: neyHub, started: true) == .neyHub(neyHub))
        precondition(LoginRoute.decide(hosted: false, neyHub: neyHub, started: true) == .here)
        precondition(LoginRoute.decide(hosted: false, neyHub: neyHub, started: false) == .wait)
        // NeyHub sumiu do disco: não dá para repassar, o avulso trata.
        precondition(LoginRoute.decide(hosted: true, neyHub: nil, started: true) == .here)
        precondition(LoginRoute.decide(hosted: true, neyHub: nil, started: false) == .wait)
    }

    /// Lucide do .app: todo ícone do mapa existe na fonte (código errado vira quadrado vazio), inclusive o house-wifi.
    private static func icons() {
        precondition(Theme.hasLucide)
        for (name, code) in Icon.lucideCodes { precondition(Theme.lucideHasGlyph(code), "sem glifo na Lucide: \(name)") }
        precondition(Icon.lucideCodes["house.wifi"] == 0xe63c)
        let image = Theme.menuBarImage(anyOn: false)
        precondition(image.isTemplate && image.size == NSSize(width: 18, height: 18))
    }

    /// Tema Grafite do NeyHub: TV e ração no verde do app, cantos e fundos do NeyKit; a cor que a pessoa escolhe para uma
    /// luz não muda (o "nada vermelho" é só das cores do app).
    private static func grafite() {
        precondition(Theme.accent(.tv) == Grafite.accent && Theme.accent(.feeder) == Grafite.accent, "TV e ração no verde do app")
        precondition(Theme.tileCorner == Grafite.cardRadius && Theme.room == Grafite.bg && Theme.matte == Grafite.card)
        let store = HubStore(sample: true)
        precondition(!store.televisions.isEmpty && store.televisions.allSatisfy { $0.tvLight(TVApps.load()) == Grafite.accent },
                     "o brilho da TV não segue a cor do app aberto")
        var red = store.tiles.first { $0.id == "light" }!
        red.status["work_mode"] = .string("colour")
        red.status["colour_data_v2"] = .string(#"{"h":0,"s":1000,"v":1000}"#)
        let c = NSColor(Theme.lightFill(red).glow).usingColorSpace(.sRGB)!
        precondition(c.redComponent > 0.9 && c.greenComponent < 0.3 && c.blueComponent < 0.3, "luz vermelha escolhida continua vermelha")
    }

    /// Recurso do Hub ausente no plugin (Review Focus 5): fonte do sistema, SF Symbol no lugar da Lucide, o nome no lugar
    /// do logo, e fica no registro.
    private static func missingResources() {
        Theme.registerFonts(from: nil)
        precondition(!Theme.hasLucide && Theme.resources == nil)
        precondition(Log.last?.hasPrefix("recursos: fontes ausentes") == true, "sem aviso no registro: \(Log.last ?? "-")")
        let youtube = TVApps.App(name: "YouTube", link: "https://www.youtube.com")
        precondition(youtube.logo == nil)
        // Pasta que existe mas veio sem nada (empacotamento pela metade): o mesmo.
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("hub-empty-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        Theme.registerFonts(from: empty)
        precondition(!Theme.hasLucide && youtube.logo == nil && Log.last?.hasPrefix("recursos: fontes ausentes") == true)
        precondition(Theme.menuBarImage(anyOn: true).isTemplate && Theme.menuBarImage(anyOn: false).isTemplate, "sem a Lucide: SF Symbol")
        // Os do .app (o build copia Resources/Bundle para Contents/Resources).
        Theme.registerFonts(from: Bundle.main.resourceURL)
        precondition(Theme.hasLucide, "fontes do .app")
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
        // Login esquecido no navegador: depois de ~10 min o retorno é recusado, mesmo com o state certo.
        var clock = Date()
        OAuthWindow.shared.now = { clock }
        defer { OAuthWindow.shared.now = Date.init }
        opened = []
        OAuthWindow.shared.start(url: URL(string: "https://api.smartthings.com/oauth/authorize?client_id=a")!) { codes.append($0) }
        let late = opened.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value }!
        clock += OAuthWindow.lifetime - 1
        precondition(OAuthWindow.lifetime <= 10 * 60 && app.handleURL(URL(string: "hubmac://callback?code=ok&state=\(late)")!), "dentro do prazo")
        OAuthWindow.shared.start(url: URL(string: "https://api.smartthings.com/oauth/authorize?client_id=a")!) { codes.append($0) }
        let expired = opened.last.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value }!
        clock += OAuthWindow.lifetime + 1
        precondition(!app.handleURL(URL(string: "hubmac://callback?code=velho&state=\(expired)")!) && codes == ["abc", "ok"], "login vencido aceito")
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

    /// `stop()` (desinstalar no NeyHub): timers de 10 s e 12 h parados, controles das TVs parados, busca de TVs parada, sem
    /// popover, sem monitor de cliques e sem ícone.
    private static func appStop(_ dir: URL) {
        // TV no próprio Mac (127.0.0.1, nada sai pela rede): o controle é criado e iniciado, mas a Task da conexão só rodaria
        // depois do selftest, e o guard do `stopped` não deixa conectar nem gerar certificado.
        let url = dir.appendingPathComponent("stop/credentials.json")
        Credentials.url = url
        Credentials(androidTVs: [AndroidTVConfig(name: "TV", host: "127.0.0.1")]).save()
        let app = HubApp(defaults: suite("stop"), hosted: true, version: "9.9.9", resources: nil, credentials: url)
        app.statusAutosaveName = autosave
        defer { forgetStatusItem() }
        let remotes = app.store.tvRemotes
        precondition(remotes.count == 1 && !remotes[0].stopped && app.store.tvDiscoveryIdle)
        app.start()
        app.setMenuBarVisible(true)
        precondition(app.hasStatusItem)
        // O caminho de verdade do clique no ícone: liga o monitor de cliques fora e o timer de 10 s. (Sem o run loop do app o
        // NSPopover não chega a aparecer, então `isShown` não é conferido.)
        app.showPopover()
        precondition(app.watchingClicks && app.store.polling, "popover aberto sem monitor ou sem timer")
        app.store.startPolling() // a tela aberta junto
        app.store.stopPolling()
        precondition(app.store.polling, "um só fechou: o timer de 10 s continua para o outro")
        app.stop()
        precondition(!app.store.timersRunning && app.store.tvConnections == 0 && remotes.allSatisfy(\.stopped))
        precondition(app.store.tvDiscoveryIdle && !app.hasStatusItem && !app.watchingClicks)
    }

    private static let autosave = "local.hub.selftest"

    /// O macOS grava a posição e a visibilidade do ícone pelo autosaveName: apaga as chaves do nome de teste.
    private static func forgetStatusItem() {
        for key in ["NSStatusItem Preferred Position \(autosave)", "NSStatusItem Visible \(autosave)", "NSStatusItem VisibleCC \(autosave)"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Domínio de padrões próprio do teste, limpo a cada rodada.
    private static func suite(_ name: String) -> UserDefaults {
        let id = "local.hub.selftest.\(name)"
        let defaults = UserDefaults(suiteName: id)!
        defaults.removePersistentDomain(forName: id)
        return defaults
    }
}
