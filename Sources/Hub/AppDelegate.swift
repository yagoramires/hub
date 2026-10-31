import AppKit
import HubCore
import NeyKitApp

/// Casca do avulso: o Hub em si mora no HubCore, o mesmo que o NeyHub carrega como plugin.
@MainActor
final class HubAppDelegate: NSObject, NSApplicationDelegate {
    private var hub: HubApp?
    private var updater: Updater?
    /// hubmac:// que chegou antes do HubApp existir (o macOS abriu o avulso por causa do retorno do login).
    private var pending: [URL] = []

    /// Antes de terminar de abrir: o retorno do login que fez o macOS abrir o avulso chega já aqui, antes do HubCheck.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(getURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // O hubmac:// que veio na abertura já foi repassado ao NeyHub (getURL) antes deste aviso.
        if HubCheck.isHosted(id: "local.hub") && HubCheck.leaveForHub(id: "local.hub", name: "Domo") { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let hub = HubApp(defaults: .standard, hosted: false, version: version, resources: Bundle.main.resourceURL)
        hub.start()
        setupMenu()
        hub.applyPresence(hub.presence)
        self.hub = hub
        open(pending)
        pending = []

        // "Hub": nome do .app e do asset Hub-<v>.zip, que as versões já instaladas procuram.
        let updater = Updater(name: "Hub", repo: "yagoramires/hub", id: "local.hub")
        hub.updateReady = updater.staged != nil
        updater.onChange = { [weak hub, weak updater] in hub?.updateReady = updater?.staged != nil }
        hub.onRelaunch = { [weak updater] in updater?.relaunchNow() }
        updater.start()
        self.updater = updater
        // Toda abertura: mostra as novidades uma vez e limpa um preparado velho.
        if let notes = Updater.notesAfterUpdate(id: "local.hub", current: version) {
            WhatsNew.show(name: "Domo", version: version, notes: notes)
        }
    }

    /// hubmac://callback, o retorno do login do SmartThings. Com o NeyHub rodando o Hub, o login em andamento é o de lá:
    /// repassa ao NeyHub em vez de perder a URL quando o avulso sair.
    @objc private func getURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text) else { return }
        open([url])
    }

    private func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let neyHub = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "local.neyhub")
        switch LoginRoute.decide(hosted: HubCheck.isHosted(id: "local.hub"), neyHub: neyHub, started: hub != nil) {
        case .neyHub(let app):
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        case .here:
            urls.forEach { _ = hub?.handleURL($0) }
            hub?.reveal()
        case .wait:
            pending += urls
        }
    }

    /// Para os timers e as conexões com as TVs antes de sair; a versão preparada entra agora.
    func applicationWillTerminate(_ notification: Notification) {
        hub?.stop()
        _ = updater?.applyStaged()
    }

    /// Clique no Dock (modo Tela) ou aberto de novo pelo Finder: traz a janela de volta.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let hub, hub.presence.screen else { return true }
        hub.showScreen()
        return false
    }

    /// No modo Tela (com ícone no Dock) o menu do app é o caminho até os ajustes sem o ícone da barra.
    private func setupMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do Domo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        // Editar: sem ele ⌘C/⌘V/⌘Z não chegam aos campos de texto (código de usuário, Client ID, busca na TV).
        let edit = NSMenu(title: "Editar")
        for (title, action, key, mods) in [("Desfazer", "undo:", "z", NSEvent.ModifierFlags.command), ("Refazer", "redo:", "z", [.command, .shift]),
                                           ("Recortar", "cut:", "x", .command), ("Copiar", "copy:", "c", .command),
                                           ("Colar", "paste:", "v", .command), ("Selecionar tudo", "selectAll:", "a", .command)] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key).keyEquivalentModifierMask = mods
            if action == "redo:" { edit.addItem(.separator()) }
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(item)
        NSApp.mainMenu?.addItem(editItem)
    }

    @objc private func showSettings() { hub?.showSettings() }
}
