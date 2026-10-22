import AppKit
import Network

/// Login OAuth no navegador padrão do usuário (onde ele já está logado no Google), com o
/// retorno numa porta local só do Mac. Janela embutida não serve: o Google bloqueia login em
/// WebView e o botão dele abre um popup que a WebView ignora.
@MainActor
final class OAuthWindow {
    static let shared = OAuthWindow()
    static let port: UInt16 = 53682
    static var redirectURI: String { "http://127.0.0.1:\(port)/callback" }

    private var listener: NWListener?
    private var state = ""
    private var completion: ((String) -> Void)?
    private var timeout: Task<Void, Never>?

    func start(url: URL, completion: @escaping (String) -> Void) {
        stop()
        self.completion = completion
        state = UUID().uuidString

        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.handle(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            debugLog("oauth: não abriu a porta \(Self.port): \(error)")
            return
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "state", value: state)]
        NSWorkspace.shared.open(components.url!)
        // Se o usuário desistir no meio, solta a porta depois de um tempo.
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return }
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                // Primeira linha: "GET /callback?code=…&state=… HTTP/1.1"
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let items = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems ?? []
                let code = items.first { $0.name == "code" }?.value
                let ok = path.hasPrefix("/callback") && code != nil && items.first { $0.name == "state" }?.value == self.state

                let body = ok ? Self.page(title: "Pronto!", text: "O Hub está conectado ao SmartThings. Pode fechar esta aba.")
                              : Self.page(title: "Não deu certo", text: "O login não voltou com autorização. Tente de novo pelo Hub.")
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })

                guard path.hasPrefix("/callback") else { return }
                if ok, let code {
                    let done = self.completion
                    self.stop()
                    done?(code)
                } else {
                    debugLog("oauth: retorno sem code ou com state errado")
                }
            }
        }
    }

    private func stop() {
        timeout?.cancel()
        listener?.cancel()
        listener = nil
        completion = nil
    }

    private static func page(title: String, text: String) -> String {
        """
        <!doctype html><meta charset="utf-8"><title>Hub</title>
        <body style="font-family:-apple-system,system-ui;display:grid;place-items:center;height:100vh;margin:0;background:#1c1c1e;color:#f2f2f7">
        <div style="text-align:center"><div style="font-size:48px">🏠</div><h2>\(title)</h2><p style="color:#a1a1a6">\(text)</p></div>
        """
    }
}
