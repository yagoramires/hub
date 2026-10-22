import CryptoKit
import Foundation

/// Nuvem da Tuya (Smart Life, Tuya Smart e marcas como Positivo) pela mesma porta que o Home
/// Assistant usa: login por QR code no app do celular, sem conta de desenvolvedor. Cada
/// requisição é cifrada com AES-GCM e assinada com HMAC, igual ao tuya-device-sharing-sdk.
@MainActor
final class TuyaClient {
    static let clientId = "HA_3y9q4ak7g4ephrvke"
    static let schema = "haauthorize"
    private static let loginHost = "https://apigw.iotbing.com"

    private(set) var account: TuyaAccount
    var onTokenChange: ((TuyaAccount) -> Void)?
    private var refreshing: Task<Void, Never>?

    init(account: TuyaAccount) {
        self.account = account
    }

    // MARK: Login por QR code

    struct QRCode {
        let token: String
        /// O que vai dentro do QR que o app Smart Life lê.
        var payload: String { "tuyaSmart--qrLogin?token=\(token)" }
    }

    static func requestQRCode(userCode: String) async throws -> QRCode {
        let url = try loginURL("/v1.0/m/life/home-assistant/qrcode/tokens", query: [
            "clientid": clientId, "usercode": userCode, "schema": schema,
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let json = try await fetchJSON(request)
        guard json["success"] as? Bool == true,
              let result = json["result"] as? [String: Any],
              let token = result["qrcode"] as? String
        else { throw TuyaError.server(json["msg"] as? String ?? "não gerou o QR code") }
        return QRCode(token: token)
    }

    /// nil enquanto o QR ainda não foi escaneado e confirmado no celular.
    static func pollLogin(qr: QRCode, userCode: String) async throws -> TuyaAccount? {
        let url = try loginURL("/v1.0/m/life/home-assistant/qrcode/tokens/\(qr.token)", query: [
            "clientid": clientId, "usercode": userCode,
        ])
        let json = try await fetchJSON(URLRequest(url: url))
        guard json["success"] as? Bool == true, let result = json["result"] as? [String: Any] else { return nil }
        let t = (json["t"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
        let expire = (result["expire_time"] as? NSNumber)?.doubleValue ?? 0
        return TuyaAccount(
            userCode: userCode,
            uid: result["uid"] as? String ?? "",
            username: result["username"] as? String ?? "",
            endpoint: result["endpoint"] as? String ?? "",
            terminalId: result["terminal_id"] as? String ?? "",
            accessToken: result["access_token"] as? String ?? "",
            refreshToken: result["refresh_token"] as? String ?? "",
            expireTime: t + expire * 1000
        )
    }

    private static func loginURL(_ path: String, query: [String: String]) throws -> URL {
        var components = URLComponents(string: loginHost + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw TuyaError.server("URL inválida") }
        return url
    }

    private static func fetchJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TuyaError.server("resposta inesperada")
        }
        return json
    }

    // MARK: Casas e aparelhos

    struct Home { let id: String; let name: String }

    func homes() async throws -> [Home] {
        let result = try await call("GET", "/v1.0/m/life/users/homes") as? [[String: Any]] ?? []
        return result.map { Home(id: "\($0["ownerId"] ?? "")", name: $0["name"] as? String ?? "") }
    }

    func devices(home: String) async throws -> [[String: Any]] {
        try await call("GET", "/v1.0/m/life/ha/home/devices", query: ["homeId": home]) as? [[String: Any]] ?? []
    }

    /// O que dá para comandar (functions) e o que o aparelho informa (status), com faixas e escalas.
    func specifications(device: String) async throws -> (functions: [DPSpec], status: [DPSpec]) {
        let result = try await call("GET", "/v1.1/m/life/\(device)/specifications") as? [String: Any] ?? [:]
        let functions = (result["functions"] as? [[String: Any]] ?? []).map(DPSpec.init(json:))
        let status = (result["status"] as? [[String: Any]] ?? []).map(DPSpec.init(json:))
        return (functions, status)
    }

    func room(device: String) async throws -> String? {
        (try await call("GET", "/v1.0/m/thing/ha/\(device)/room") as? [String: Any])?["name"] as? String
    }

    func send(device: String, commands: [(code: String, value: Any)]) async throws {
        let list = commands.map { ["code": $0.code, "value": $0.value] }
        _ = try await call("POST", "/v1.1/m/thing/\(device)/commands", body: ["commands": list])
    }

    // MARK: Requisição cifrada

    private func call(_ method: String, _ path: String, query: [String: Any]? = nil,
                      body: [String: Any]? = nil, refreshing isRefresh: Bool = false) async throws -> Any? {
        if !isRefresh { await refreshTokenIfNeeded() }

        let rid = UUID().uuidString.lowercased()
        let hashKey = Self.md5Hex(rid + account.refreshToken)
        let secret = String(Self.hmacHex(key: rid, message: hashKey).prefix(16))

        var queryEnc = ""
        var components = URLComponents(string: account.endpoint + path)!
        if let query, !query.isEmpty {
            queryEnc = try Self.encrypt(Self.compactJSON(query), secret: secret)
            components.percentEncodedQuery = "encdata=" + Self.percentEncode(queryEnc)
        }
        var bodyEnc = ""
        var bodyData: Data?
        if let body, !body.isEmpty {
            bodyEnc = try Self.encrypt(Self.compactJSON(body), secret: secret)
            bodyData = try JSONSerialization.data(withJSONObject: ["encdata": bodyEnc])
        }

        var headers = [
            ("X-appKey", Self.clientId),
            ("X-requestId", rid),
            ("X-sid", ""),
            ("X-time", String(Int64(Date().timeIntervalSince1970 * 1000))),
        ]
        if !account.accessToken.isEmpty { headers.append(("X-token", account.accessToken)) }
        let signed = headers.filter { !$0.1.isEmpty }.map { "\($0.0)=\($0.1)" }.joined(separator: "||")
            + queryEnc + bodyEnc

        guard let url = components.url else { throw TuyaError.server("URL inválida") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(Self.hmacHex(key: hashKey, message: signed), forHTTPHeaderField: "X-sign")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            debugLog("tuya \(method) \(path): HTTP \(code)")
            throw TuyaError.server("HTTP \(code)")
        }
        guard json["success"] as? Bool == true else {
            let message = json["msg"] as? String ?? "erro"
            debugLog("tuya \(method) \(path): \(json["code"] ?? "") \(message)")
            throw TuyaError.server(message)
        }
        guard let encrypted = json["result"] as? String else { return json["result"] }
        let plain = try Self.decrypt(encrypted, secret: secret)
        let result = (try? JSONSerialization.jsonObject(with: plain, options: .fragmentsAllowed))
            ?? String(data: plain, encoding: .utf8)
        if isRefresh, var dict = result as? [String: Any] {
            dict["t"] = json["t"]
            return dict
        }
        return result
    }

    private func refreshTokenIfNeeded() async {
        if let refreshing { return await refreshing.value }
        let now = Date().timeIntervalSince1970 * 1000
        guard account.expireTime - 60_000 <= now else { return }
        let task = Task { @MainActor in
            do {
                let result = try await call("GET", "/v1.0/m/token/\(account.refreshToken)", refreshing: true) as? [String: Any] ?? [:]
                guard let access = result["accessToken"] as? String, let refresh = result["refreshToken"] as? String else { return }
                let t = (result["t"] as? NSNumber)?.doubleValue ?? now
                account.accessToken = access
                account.refreshToken = refresh
                account.expireTime = t + ((result["expireTime"] as? NSNumber)?.doubleValue ?? 7200) * 1000
                onTokenChange?(account)
                debugLog("tuya: token renovado (\(account.username))")
            } catch {
                debugLog("tuya: não renovou o token: \(error)")
            }
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    // MARK: Cripto

    private static let nonceAlphabet = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678")

    static func encrypt(_ plain: String, secret: String) throws -> String {
        let nonce = String((0..<12).map { _ in nonceAlphabet.randomElement()! })
        let box = try AES.GCM.seal(Data(plain.utf8), using: SymmetricKey(data: Data(secret.utf8)),
                                   nonce: AES.GCM.Nonce(data: Data(nonce.utf8)))
        return Data(nonce.utf8).base64EncodedString() + (box.ciphertext + box.tag).base64EncodedString()
    }

    static func decrypt(_ base64: String, secret: String) throws -> Data {
        guard let data = Data(base64Encoded: base64), data.count > 28 else { throw TuyaError.server("resposta cifrada inválida") }
        let rest = data.dropFirst(12)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: data.prefix(12)),
                                        ciphertext: rest.dropLast(16), tag: rest.suffix(16))
        return try AES.GCM.open(box, using: SymmetricKey(data: Data(secret.utf8)))
    }

    static func md5Hex(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func hmacHex(key: String, message: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(key.utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func compactJSON(_ object: [String: Any]) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), encoding: .utf8) ?? "{}"
    }

    private static func percentEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? string
    }
}

enum TuyaError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self { case .server(let message): message }
    }
}
