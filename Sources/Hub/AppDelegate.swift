import AppKit
import HubCore
import NeyKitApp

/// Casca do avulso: o Hub em si mora no HubCore, o mesmo que o NeyHub carrega como plugin.
@MainActor
final class HubAppDelegate: NSObject, NSApplicationDelegate {
    private var hub: HubApp?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if HubCheck.isHosted(id: "local.hub") && HubCheck.leaveForHub(id: "local.hub", name: "Hub") { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let hub = HubApp(defaults: .standard, hosted: false, version: version, resources: Bundle.main.resourceURL)
        hub.start()
        setupMenu()
        hub.applyPresence(hub.presence)
        self.hub = hub

        let updater = Updater(name: "Hub", repo: "yagoramires/hub", id: "local.hub")
        hub.updateReady = updater.staged != nil
        updater.onChange = { [weak hub, weak updater] in hub?.updateReady = updater?.staged != nil }
        hub.onRelaunch = { [weak updater] in updater?.relaunchNow() }
        updater.start()
        self.updater = updater
        // Toda abertura: mostra as novidades uma vez e limpa um preparado velho.
        if let notes = Updater.notesAfterUpdate(id: "local.hub", current: version) {
            WhatsNew.show(name: "Hub", version: version, notes: notes)
        }
    }

    /// hubmac://callback, o retorno do login do SmartThings.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { _ = hub?.handleURL($0) }
        hub?.reveal()
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
        appMenu.addItem(withTitle: "Sair do Hub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
