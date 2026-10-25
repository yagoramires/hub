import AppKit
import HubCore

/// Modos de terminal do avulso (usam os mesmos tokens do app). O `--render` e o `--selftest` moram no HubCore.
@MainActor
enum DebugCLI {
    static func run(_ arguments: [String]) async {
        if arguments.first == "--render" { return HubApp.render(arguments, resources: Bundle.main.resourceURL) }
        if arguments.first == "--atv-launch", arguments.count > 1, let tv = Credentials.load().androidTVs?.first {
            let remote = ATVRemote(host: tv.host)
            remote.start()
            remote.launch(arguments[1])
            try? await Task.sleep(for: .seconds(8))
            return print("app na TV: \(remote.app ?? "não informado")")
        }
        if arguments.first == "--atv-scan" {
            let found = await ATVDiscovery().scan()
            return print(found.isEmpty ? "nenhuma TV com a porta 6466" : found.map { "\($0.name) → \($0.host)" }.joined(separator: "\n"))
        }
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

    private static func describe(_ spec: DPSpec) -> String {
        if spec.isEnum { return spec.range.joined(separator: "|") }
        if spec.isInteger { return "\(spec.min.short)…\(spec.max.short) escala \(spec.scale) \(spec.unit)" }
        return ""
    }
}
