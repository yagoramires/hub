import AppKit
import HubCore
import NeyKit

/// Hub dentro do NeyHub. Linka só HubCore e NeyKit (nunca NeyKitApp). O NeyHub chama tudo na main.
final class HubEntry: NSObject, NeyPlugin {
    private var made: HubApp?

    @MainActor private var app: HubApp {
        if let made { return made }
        let app = HubApp(defaults: AppDefaults.forApp("local.hub"), hosted: true, version: PluginLocation.version(dso: #dsohandle),
                         resources: PluginLocation.resources(dso: #dsohandle))
        made = app
        return app
    }

    var contractVersion: Int { neyPluginContractVersion }

    func start(host: NeyHost) { MainActor.assumeIsolated { app.start() } }
    func stop() { MainActor.assumeIsolated { app.stop() } }
    func setMenuBarVisible(_ visible: Bool) { MainActor.assumeIsolated { app.setMenuBarVisible(visible) } }
    func makeScreen() -> NSViewController? { MainActor.assumeIsolated { app.makeScreen() } }
    func makeSettings() -> NSViewController { MainActor.assumeIsolated { app.makeSettings() } }
    /// hubmac://callback do login do SmartThings que o NeyHub recebeu; false com outro esquema ou `state` errado.
    func handleURL(_ url: URL) -> Bool { MainActor.assumeIsolated { app.handleURL(url) } }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(HubEntry()).toOpaque()
}
