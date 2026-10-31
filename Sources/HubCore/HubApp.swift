import AppKit
import Combine
import NeyKit
import SwiftUI

/// O Hub inteiro, sem a casca: o avulso (`Hub`) e o plugin do NeyHub (`HubPlugin`) usam o mesmo.
@MainActor
public final class HubApp: NSObject, NSPopoverDelegate {
    private let defaults: UserDefaults
    /// Dentro do NeyHub: sem item de login, sem modos, sem atualização, sem Sair e sem o Chaveiro.
    private let hosted: Bool
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    let store: HubStore
    let shell: Shell
    private var watch: AnyCancellable?
    /// Escuta cliques nos outros apps enquanto o popover está aberto.
    private var outsideClicks: Any?
    private var settingsWindow: NSWindow?
    private var screenWindow: NSWindow?

    /// Avulso: o Updater já preparou uma versão, que entra quando o app fechar.
    public var updateReady = false { didSet { shell.state.updateReady = updateReady } }
    /// Avulso: "Reiniciar agora" ao lado da linha de atualização; a casca liga ao `Updater.relaunchNow`.
    public var onRelaunch: (() -> Void)?

    /// `resources`: pasta com `Fonts/` e `AppLogos/` (a do .app no avulso, a do .neyplugin no NeyHub); nil cai na fonte do
    /// sistema e em ícones genéricos.
    public convenience init(defaults: UserDefaults, hosted: Bool, version: String, resources: URL?) {
        self.init(defaults: defaults, hosted: hosted, version: version, resources: resources, credentials: Credentials.real)
    }

    /// `credentials` só muda no selftest: uma pasta temporária, nunca a de verdade.
    init(defaults: UserDefaults, hosted: Bool, version: String, resources: URL?, credentials: URL) {
        self.defaults = defaults
        self.hosted = hosted
        // Um app por processo: o caminho das credenciais, o Chaveiro e os padrões valem para tudo do HubCore.
        Credentials.url = credentials
        Credentials.migratesKeychain = !hosted
        TVApps.userDefaults = defaults
        Theme.registerFonts(from: resources)
        store = HubStore()
        shell = Shell(state: PopoverState(version: version, hosted: hosted))
        super.init()
        shell.relaunch = { [weak self] in if self?.hosted == false { self?.onRelaunch?() } }
        shell.presence = hosted ? nil : presence
        shell.onPresence = { [weak self] presence in
            guard let self else { return }
            presence.save(defaults)
            shell.presence = presence
            applyPresence(presence)
        }
    }

    public func start() {
        // Ícone cheio quando tem alguma coisa ligada.
        watch = store.$devices.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateIcon() }
        debugLog("iniciou\(hosted ? " no NeyHub" : "") · Hub \(shell.state.version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        Task { @MainActor in
            await store.refresh()
            // open -n Hub.app --args --show: abre o popover sozinho, para conferir a interface com os aparelhos de verdade.
            if !hosted, CommandLine.arguments.contains("--show") { showPopover() }
        }
        // Sem contas o avulso abre os ajustes sozinho; no NeyHub a tela do Hub mostra "Conecte suas contas".
        if !hosted, !store.hasAccounts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.reveal()
                NotificationCenter.default.post(name: .hubOpenSettings, object: nil)
            }
        }
    }

    /// Desinstalar no NeyHub (e fechar o avulso): para os timers, a busca e as conexões com as TVs, o monitor de cliques,
    /// as janelas e o ícone.
    public func stop() {
        watch = nil
        store.stop()
        setMenuBarVisible(false)
        removeOutsideClicks()
        settingsWindow?.close()
        screenWindow?.close()
        debugLog("parou")
    }

    /// false REMOVE o ícone; true cria com autosaveName "local.hub" (a posição na barra é lembrada).
    public func setMenuBarVisible(_ visible: Bool) {
        if !visible, let statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = statusAutosaveName
            item.button?.target = self
            item.button?.action = #selector(togglePopover)
            statusItem = item
            updateIcon()
        }
    }

    public func makeScreen() -> NSViewController {
        NSHostingController(rootView: ScreenView().environmentObject(store).environmentObject(shell).environment(\.colorScheme, .dark))
    }

    public func makeSettings() -> NSViewController {
        NSHostingController(rootView: SettingsView(back: nil).environmentObject(store).environmentObject(shell)
            .frame(width: 380).font(Theme.font(13)).background(Theme.room.ignoresSafeArea()).environment(\.colorScheme, .dark))
    }

    /// hubmac://callback do login do SmartThings, do avulso ou do NeyHub. Só aceita o `state` do login em andamento.
    public func handleURL(_ url: URL) -> Bool { OAuthWindow.shared.handle(url) }

    /// Avulso: traz o Hub para a frente (popover na barra, ou a janela no modo Tela).
    public func reveal() {
        if statusItem != nil { showPopover() } else if !hosted { showScreen() }
    }

    // MARK: Avulso

    /// Modo do avulso. Sem escolha salva fica só na barra de menus, como na 0.1.0.
    public var presence: Presence {
        Presence.load(defaults, hasScreen: false).normalized(hasScreen: true)
    }

    /// Avulso: troca o modo na hora, sem reiniciar. Tela = ícone no Dock + janela; barra de menus = o ícone com o popover.
    public func applyPresence(_ presence: Presence) {
        guard !hosted else { return }
        setMenuBarVisible(presence.menuBar)
        NSApp.setActivationPolicy(presence.screen ? .regular : .accessory)
        if presence.screen { showScreen() } else { screenWindow?.close() }
    }

    public func showScreen() {
        if screenWindow == nil {
            screenWindow = window(makeScreen(), title: "Hub")
            screenWindow?.setContentSize(NSSize(width: 960, height: 700))
            screenWindow?.center()
        }
        bringToFront(screenWindow)
    }

    /// Janela de configurações do avulso: o menu do app (`⌘,`) no modo Tela.
    public func showSettings() {
        if settingsWindow == nil { settingsWindow = window(makeSettings(), title: "Ajustes do Hub") }
        bringToFront(settingsWindow)
    }

    private func window(_ controller: NSViewController, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func bringToFront(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Barra de menus

    private func updateIcon() {
        statusItem?.button?.image = Theme.menuBarImage(anyOn: store.anyOn)
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        if popover.contentViewController == nil {
            let host = NSHostingController(rootView: RootView().environmentObject(store).environmentObject(shell).environment(\.colorScheme, .dark))
            popover.appearance = NSAppearance(named: .darkAqua) // só escuro, como o NeyHub
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
        }
        // App de barra não é ativo: sem isso os campos de texto não recebem teclado.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // O .transient sozinho não fecha quando o clique cai em outro app; um monitor global pega esse clique.
        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
        popover.contentViewController?.view.window?.makeKey()
        store.startPolling()
    }

    public func popoverDidClose(_ notification: Notification) {
        removeOutsideClicks()
        store.stopPolling()
        NotificationCenter.default.post(name: .hubPopoverClosed, object: nil)
    }

    private func removeOutsideClicks() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    /// Onde o macOS lembra a posição do ícone. O selftest usa outro nome: nunca mexe na posição do Hub de verdade.
    var statusAutosaveName = "local.hub"
    var hasStatusItem: Bool { statusItem != nil }
    var watchingClicks: Bool { outsideClicks != nil }

    // MARK: Modos de terminal (a casca chama)

    public static func selfTest() { SelfTest.run() }

    /// `Hub --render <tela> <arquivo.png> [light|dark]`: desenha uma tela com aparelhos de exemplo.
    public static func render(_ arguments: [String], resources: URL?) { Render.run(arguments, resources: resources) }
}

/// Para onde vai um `hubmac://` que chegou ao avulso. Se o NeyHub roda o Hub, é dele (o avulso vai sair e o login
/// em andamento está lá); senão o próprio avulso trata, ou guarda até o HubApp existir.
public enum LoginRoute: Equatable {
    case neyHub(URL), here, wait

    public static func decide(hosted: Bool, neyHub: URL?, started: Bool) -> LoginRoute {
        if hosted, let neyHub { return .neyHub(neyHub) }
        return started ? .here : .wait
    }
}

/// O que muda no popover, na tela e nos ajustes entre o avulso e o NeyHub.
struct PopoverState: Equatable {
    var version: String
    var hosted: Bool
    var updateReady = false

    /// Hospedado fecharia o NeyHub inteiro.
    var showsQuit: Bool { !hosted }
    /// Hospedado o login é do NeyHub.
    var showsLogin: Bool { !hosted }
    /// Hospedado o modo (janela/barra) é escolhido no card do NeyHub.
    var showsPresence: Bool { !hosted }
    /// Hospedado quem atualiza é o NeyHub.
    var showsUpdate: Bool { updateReady && !hosted }
}

/// Ponte entre as telas (popover, tela, ajustes) e a casca.
final class Shell: ObservableObject {
    @Published var state: PopoverState
    /// Avulso: o modo atual; nil hospedado.
    @Published var presence: Presence?
    var onPresence: (Presence) -> Void = { _ in }
    var relaunch: () -> Void = {}

    init(state: PopoverState) { self.state = state }
}
