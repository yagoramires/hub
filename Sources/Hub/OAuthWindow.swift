import AppKit
import WebKit

/// Janela com o login da Samsung. Quando a página tenta ir para o endereço de retorno, pega o
/// `code` da URL e fecha, sem precisar de servidor nenhum.
@MainActor
final class OAuthWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = OAuthWindow()

    private var window: NSWindow?
    private var redirect = ""
    private var completion: ((String) -> Void)?

    func start(url: URL, redirect: String, completion: @escaping (String) -> Void) {
        self.redirect = redirect
        self.completion = completion
        window?.close()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: configuration)
        webView.navigationDelegate = self

        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Conectar SmartThings"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.absoluteString.hasPrefix(redirect) else {
            return decisionHandler(.allow)
        }
        decisionHandler(.cancel)
        let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code" }?.value
        let done = completion
        completion = nil
        window?.close()
        if let code { done?(code) } else { debugLog("smartthings: retorno sem code: \(url.query ?? "")") }
    }

    func windowWillClose(_ notification: Notification) {
        completion = nil
    }
}
