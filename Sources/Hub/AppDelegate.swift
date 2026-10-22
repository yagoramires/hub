import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private lazy var store = HubStore()
    private var watch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = icon(lit: false)
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        let host = NSHostingController(rootView: RootView().environmentObject(store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Ícone cheio quando tem alguma coisa ligada.
        watch = store.$devices.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            statusItem.button?.image = icon(lit: store.anyOn)
        }

        debugLog("iniciou · Hub \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        Task { @MainActor in await store.refresh() }
        if !store.hasAccounts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPopover()
                NotificationCenter.default.post(name: .hubOpenSettings, object: nil)
            }
        }
    }

    /// hubmac://callback, o retorno do login do SmartThings.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { OAuthWindow.shared.handle($0) }
        showPopover()
    }

    private func icon(lit: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: lit ? "house.fill" : "house", accessibilityDescription: "Hub")
        image?.isTemplate = true
        return image
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        store.startPolling()
    }

    func popoverDidClose(_ notification: Notification) {
        store.stopPolling()
        NotificationCenter.default.post(name: .hubPopoverClosed, object: nil)
    }
}
