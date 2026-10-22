import Foundation

/// API oficial do SmartThings (o ar-condicionado Samsung). O login é OAuth com um app próprio
/// criado pelo SmartThings CLI: o token vale 24 h e o refresh token 30 dias, renovado a cada uso.
@MainActor
final class SmartThingsClient {
    static let api = "https://api.smartthings.com/v1"
    static let authorizeURL = "https://api.smartthings.com/oauth/authorize"
    static let tokenURL = "https://auth-global.api.smartthings.com/oauth/token"
    /// Nunca chega a carregar: a janela de login pega o código antes do redirecionamento.
    static let redirectURI = "https://httpbin.org/get"
    static let scopes = "r:devices:* x:devices:* r:locations:*"

    private(set) var auth: SmartThingsAuth
    var onTokenChange: ((SmartThingsAuth) -> Void)?

    init(auth: SmartThingsAuth) {
        self.auth = auth
    }

    var canRefresh: Bool { !auth.clientId.isEmpty && !auth.refreshToken.isEmpty }

    // MARK: OAuth

    static func authorizationURL(clientId: String) -> URL {
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
        ]
        return components.url!
    }

    static func exchange(code: String, clientId: String, clientSecret: String) async throws -> SmartThingsAuth {
        try await token(form: [
            "grant_type": "authorization_code", "client_id": clientId,
            "code": code, "redirect_uri": redirectURI,
        ], clientId: clientId, clientSecret: clientSecret)
    }

    private static func token(form: [String: String], clientId: String, clientSecret: String) async throws -> SmartThingsAuth {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        let basic = Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let access = json["access_token"] as? String
        else {
            let message = json["error_description"] as? String ?? json["error"] as? String ?? "login recusado"
            debugLog("smartthings token: \(message)")
            throw SmartThingsError.server(message)
        }
        return SmartThingsAuth(
            clientId: clientId, clientSecret: clientSecret, accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? "",
            expiresAt: Date().addingTimeInterval((json["expires_in"] as? NSNumber)?.doubleValue ?? 86_400)
        )
    }

    /// Renova se faltar menos de 10 minutos, ou sempre quando `force` (o refresh token também
    /// vence se ficar 30 dias parado, então o app renova pelo menos uma vez por dia).
    func refreshIfNeeded(force: Bool = false) async throws {
        guard canRefresh, force || auth.expiresAt.timeIntervalSinceNow < 600 else { return }
        auth = try await Self.token(form: [
            "grant_type": "refresh_token", "client_id": auth.clientId, "refresh_token": auth.refreshToken,
        ], clientId: auth.clientId, clientSecret: auth.clientSecret)
        onTokenChange?(auth)
        debugLog("smartthings: token renovado")
    }

    // MARK: Aparelhos

    func devices() async throws -> [[String: Any]] {
        (try await request("GET", "/devices") as? [String: Any])?["items"] as? [[String: Any]] ?? []
    }

    /// Status do componente principal, achatado em "capability.atributo" → valor.
    func status(device: String) async throws -> [String: DPValue] {
        let json = try await request("GET", "/devices/\(device)/components/main/status") as? [String: Any] ?? [:]
        var flat: [String: DPValue] = [:]
        for (capability, attributes) in json {
            for (attribute, info) in attributes as? [String: Any] ?? [:] {
                flat["\(capability).\(attribute)"] = DPValue((info as? [String: Any])?["value"])
            }
        }
        return flat
    }

    func command(device: String, capability: String, command: String, arguments: [Any] = []) async throws {
        var item: [String: Any] = ["component": "main", "capability": capability, "command": command]
        if !arguments.isEmpty { item["arguments"] = arguments }
        _ = try await request("POST", "/devices/\(device)/commands", body: ["commands": [item]])
    }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Any? {
        try await refreshIfNeeded()
        var request = URLRequest(url: URL(string: Self.api + path)!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            debugLog("smartthings \(method) \(path): HTTP \(code) \(String(data: data.prefix(300), encoding: .utf8) ?? "")")
            throw SmartThingsError.server(code == 401 ? "login do SmartThings expirou" : "HTTP \(code)")
        }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

enum SmartThingsError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self { case .server(let message): message }
    }
}
