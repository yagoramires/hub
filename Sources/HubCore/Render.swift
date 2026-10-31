import AppKit
import NeyKit
import SwiftUI

/// `Hub --render <tela> <arquivo.png> [light|dark]`: desenha uma tela com aparelhos de exemplo num PNG, sem abrir nada na
/// tela do usuário, sem rede e sem as credenciais de verdade.
/// Telas: home, device:ID, settings, settings:hosted (os ajustes dentro do NeyHub), screen (a tela do Hub, Casa),
/// screen:tv, screen:racao, screen:narrow (a janela padrão do NeyHub), screen:empty (nada escolhido no detalhe) e
/// screen@<largura> (a Casa numa largura qualquer).
/// Para ver com os aparelhos de verdade: open -n build/Hub.app --args --show e um print da janela.
@MainActor
enum Render {
    static func run(_ arguments: [String], resources: URL?) {
        guard arguments.count >= 3 else {
            return print("uso: Hub --render <home|device:ID|settings|settings:hosted|screen|screen:tv|screen:racao|screen:narrow|screen:empty|screen@<largura>> <arquivo.png> [light|dark]")
        }
        // Os ajustes leem as credenciais ao abrir: aponta para um arquivo que não existe, nunca o de verdade.
        Credentials.url = FileManager.default.temporaryDirectory.appendingPathComponent("hub-render-\(UUID().uuidString)/none.json")
        Log.enabled = false
        Theme.registerFonts(from: resources)
        let dark = !(arguments.count > 3 && arguments[3] == "light")
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let store = HubStore(sample: true)
        let screen = arguments[1]
        let shell = Shell(state: PopoverState(version: "0.2.0", hosted: screen == "settings:hosted", updateReady: true))
        shell.presence = Presence(screen: false, menuBar: true)

        let view: AnyView
        var size: CGSize?
        switch screen {
        case _ where screen.hasPrefix("screen@"):
            // screen@<largura>: a área que o NeyHub dá ao plugin (janela − 170 da barra lateral − 32 de margem).
            view = AnyView(ScreenView(selected: "light"))
            size = CGSize(width: Double(screen.dropFirst(7)) ?? 698, height: 700)
        case "screen", "screen:empty", "screen:narrow":
            view = AnyView(ScreenView(selected: screen == "screen" ? "light" : nil))
            size = screen == "screen:narrow" ? CGSize(width: 698, height: 760) : CGSize(width: 1060, height: 700)
        case "screen:tv":
            view = AnyView(ScreenView(tab: .tv))
            size = CGSize(width: 1060, height: 900)
        case "screen:racao":
            view = AnyView(ScreenView(tab: .racao))
            size = CGSize(width: 1060, height: 700)
        case "settings:hosted":
            view = AnyView(SettingsView(back: nil).frame(width: 380).font(Theme.font(13)).background(Theme.room))
        default:
            let route: RootView.Route = screen == "settings" ? .settings
                : screen.hasPrefix("device:") ? .device(String(screen.dropFirst(7))) : .home
            view = AnyView(RootView(route: route))
        }
        let root = view
            .environmentObject(store)
            .environmentObject(shell)
            .background(dark ? Theme.room : Color(white: 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
            // Telas com tamanho fixo rolam de verdade; o popover vira pilha (mostra tudo).
            .environment(\.hubSnapshot, size == nil)
        // NSHostingView (e não ImageRenderer): só ele desenha os controles nativos (seletor, campos, interruptores).
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return print("não renderizou") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return print("não renderizou") }
        do { try png.write(to: URL(fileURLWithPath: arguments[2])) } catch { return print("não gravou: \(error.localizedDescription)") }
        print("✓ \(arguments[2]) \(Int(host.frame.width))×\(Int(host.frame.height))")
    }
}
