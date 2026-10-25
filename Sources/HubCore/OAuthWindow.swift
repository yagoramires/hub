import AppKit

/// Login OAuth no navegador padrão do usuário (onde ele já está logado no Google). A Samsung
/// devolve para hubmac://callback, que o macOS entrega ao Hub. Janela embutida não serve (o
/// Google bloqueia login em WebView) e retorno em 127.0.0.1 também não (o firewall da Samsung
/// responde 403 a qualquer URL com localhost).
@MainActor
final class OAuthWindow {
    static let shared = OAuthWindow()
    static let redirectURI = "hubmac://callback"

    private var state = ""
    private var completion: ((String) -> Void)?
    /// Abre o login no navegador; o selftest troca por um gravador.
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }

    func start(url: URL, completion: @escaping (String) -> Void) {
        self.completion = completion
        state = UUID().uuidString
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "state", value: state)]
        open(components.url!)
    }

    /// hubmac://callback?code=…&state=…, do avulso ou do NeyHub. false = não é o login que o Hub espera (outro esquema,
    /// state errado ou nenhum login em andamento): o NeyHub avisa em vez de perder a URL em silêncio.
    func handle(_ url: URL) -> Bool {
        guard url.absoluteString.hasPrefix(Self.redirectURI) else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value,
              items.first(where: { $0.name == "state" })?.value == state, let done = completion
        else {
            debugLog("oauth: retorno sem code, com state errado ou sem login em andamento")
            return false
        }
        completion = nil
        done(code)
        return true
    }
}
