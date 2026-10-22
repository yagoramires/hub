import Foundation
import Security

/// Tokens de cada nuvem, num JSON em ~/Library/Application Support/Hub com permissão só do
/// usuário (0600). Já ficaram no Keychain, mas com certificado local (sem Team ID da Apple) o
/// macOS amarra o acesso ao hash de cada build e pedia a senha depois de toda compilação.
struct Credentials: Codable, Equatable {
    var tuya: [TuyaAccount] = []
    var smartThings: SmartThingsAuth?
    /// App OAuth criado pelo SmartThings CLI, guardado antes do primeiro login.
    var smartThingsApp: SmartThingsApp?
    /// TVs com Google TV / Android TV já pareadas (o pareamento fica no certificado do Hub).
    var androidTVs: [AndroidTVConfig]?

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Hub/credentials.json")

    static func load() -> Credentials {
        if let data = try? Data(contentsOf: url) {
            return (try? JSONDecoder().decode(Credentials.self, from: data)) ?? Credentials()
        }
        // Primeira vez com arquivo: traz o que estava no Keychain (pede a senha uma última vez).
        guard let migrated = loadFromKeychain() else { return Credentials() }
        migrated.save()
        debugLog("credenciais migradas do Keychain para \(url.path)")
        return migrated
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: 0o700])
        // Escreve num temporário e troca, para outro processo nunca ler um arquivo pela metade.
        let temp = Self.url.appendingPathExtension("tmp")
        guard manager.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            return debugLog("credenciais: não consegui gravar")
        }
        _ = try? manager.replaceItemAt(Self.url, withItemAt: temp)
        if !manager.fileExists(atPath: Self.url.path) { try? manager.moveItem(at: temp, to: Self.url) }
    }

    private static func loadFromKeychain() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "local.hub",
            kSecAttrAccount as String: "credentials",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
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

struct AndroidTVConfig: Codable, Equatable {
    var name: String
    var host: String
}
