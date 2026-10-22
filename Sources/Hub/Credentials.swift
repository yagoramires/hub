import Foundation
import Security

/// Tokens de cada nuvem. Ficam no Keychain como um único JSON.
struct Credentials: Codable, Equatable {
    var tuya: [TuyaAccount] = []
    var smartThings: SmartThingsAuth?
    /// App OAuth criado pelo SmartThings CLI, guardado antes do primeiro login.
    var smartThingsApp: SmartThingsApp?

    private static let service = "local.hub"
    private static let account = "credentials"

    static func load() -> Credentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let decoded = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return Credentials() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            if added != errSecSuccess { debugLog("keychain: falhou ao salvar (\(added))") }
        } else if status != errSecSuccess {
            debugLog("keychain: falhou ao atualizar (\(status))")
        }
    }
}

struct TuyaAccount: Codable, Equatable {
    /// App onde a conta foi criada (Smart Life, Tuya Smart, Positivo). São contas separadas
    /// na mesma nuvem; serve só para o usuário saber qual é qual.
    var app: String?
    var userCode: String
    var uid: String
    var username: String
    var endpoint: String
    var terminalId: String
    var accessToken: String
    var refreshToken: String
    /// Milissegundos desde 1970, como a Tuya manda.
    var expireTime: Double
}

struct SmartThingsAuth: Codable, Equatable {
    /// Vazio quando o usuário colou um token pessoal (vale 24 h e não renova).
    var clientId: String
    var clientSecret: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

struct SmartThingsApp: Codable, Equatable {
    var clientId: String
    var clientSecret: String
}
