import AppKit
import SwiftUI

@MainActor
enum DebugCLI {
    static func run(_ arguments: [String]) async {
        if arguments.first == "--render" { return render(arguments) }
        if arguments.first == "--import-st-app", arguments.count > 1 {
            return print(HubStore().importSmartThingsApp(file: arguments[1]) ? "✓ app OAuth guardado" : "arquivo sem oauthClientId/oauthClientSecret")
        }
        let store = HubStore()
        if arguments.first == "--raw" {
            for device in await store.rawTuya() {
                var copy = device
                copy["local_key"] = "…"
                copy["status"] = nil
                if let data = try? JSONSerialization.data(withJSONObject: copy, options: [.prettyPrinted, .sortedKeys]) {
                    print(String(data: data, encoding: .utf8) ?? "")
                }
            }
            return
        }
        await store.refresh()
        if let error = store.error { print("ERRO:", error) }

        switch arguments.first {
        case "--dump":
            for device in store.devices {
                print("\n■ \(device.name) [\(device.kind)] \(device.category) id=\(device.id) online=\(device.online) room=\(device.room ?? "-")")
                if !device.capabilities.isEmpty { print("  capabilities:", device.capabilities.sorted().joined(separator: ", ")) }
                for (code, value) in device.status.sorted(by: { $0.key < $1.key }) {
                    let spec = device.functions[code].map { " ← \($0.type) \(describe($0))" } ?? ""
                    print("  \(code) = \(value)\(spec)")
                }
                for spec in device.functions.values.sorted(by: { $0.code < $1.code }) where device.status[spec.code] == nil {
                    print("  \(spec.code) (sem status) ← \(spec.type) \(describe(spec))")
                }
            }
        case "--tuya" where arguments.count >= 4:
            guard let device = store.devices.first(where: { $0.id == arguments[1] }) else { return print("aparelho não encontrado") }
            let value = (try? JSONSerialization.jsonObject(with: Data(arguments[3].utf8), options: .fragmentsAllowed)) ?? arguments[3]
            store.setTuya(device, arguments[2], value)
            try? await Task.sleep(for: .seconds(4))
            print(store.error ?? "ok · \(arguments[2]) = \(store.devices.first { $0.id == device.id }?.status[arguments[2]] ?? .other("?"))")
        case "--st" where arguments.count >= 4:
            guard let device = store.devices.first(where: { $0.id == arguments[1] }) else { return print("aparelho não encontrado") }
            let args = arguments.count > 4
                ? ((try? JSONSerialization.jsonObject(with: Data(arguments[4].utf8), options: .fragmentsAllowed)) as? [Any] ?? [])
                : []
            store.stCommand(device, capability: arguments[2], command: arguments[3], arguments: args)
            try? await Task.sleep(for: .seconds(4))
            print(store.error ?? "ok")
        default:
            print("uso: Hub --dump | --tuya <id> <código> <valor> | --st <id> <capability> <comando> [args]")
        }
    }

    /// Desenha uma tela com aparelhos de exemplo num PNG, sem abrir nada na tela do usuário.
    /// Hub --render <home|device:ID|settings> <arquivo.png> [light|dark]
    private static func render(_ arguments: [String]) {
        guard arguments.count >= 3 else { return print("uso: Hub --render <home|device:ID|settings> <arquivo.png> [light|dark]") }
        let dark = !(arguments.count > 3 && arguments[3] == "light")
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let store = HubStore(sample: true)
        let screen = arguments[1]
        let route: RootView.Route = screen == "settings" ? .settings
            : screen.hasPrefix("device:") ? .device(String(screen.dropFirst(7))) : .home
        let root = RootView(route: route)
            .environmentObject(store)
            .background(dark ? Color(white: 0.16) : Color(white: 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.hubSnapshot, true)
        let renderer = ImageRenderer(content: root)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return print("não renderizou") }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: arguments[2]))
        let frame = CGRect(x: 0, y: 0, width: image.width / 2, height: image.height / 2)
        print("✓ \(arguments[2]) \(Int(frame.width))×\(Int(frame.height))")
    }

    private static func describe(_ spec: DPSpec) -> String {
        if spec.isEnum { return spec.range.joined(separator: "|") }
        if spec.isInteger { return "\(spec.min.short)…\(spec.max.short) escala \(spec.scale) \(spec.unit)" }
        return ""
    }
}
