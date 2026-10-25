import Foundation

/// Registro em ~/Library/Logs/Hub/hub.log, sempre ligado. Guarda chamadas às nuvens e erros,
/// nunca tokens.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Hub/hub.log")
    /// Passou disso, o atual vira hub.log.1 e começa outro: no máximo ~4 MB em disco.
    private static let limit: UInt64 = 2_000_000
    private static var handle: FileHandle?
    private static let lock = NSLock()
    private static let clock: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// O selftest desliga: nada vai para o hub.log de verdade.
    static var enabled = true
    /// Última linha pedida, gravada ou não (o selftest confere o aviso de recurso ausente).
    private(set) static var last: String?

    static func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        last = message
        guard enabled else { return }
        if handle == nil { open() }
        guard let handle else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(clock.string(from: Date())) \(message)\n".utf8))
        if handle.offsetInFile > limit { rotate() }
    }

    private static func open() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
    }

    private static func rotate() {
        try? handle?.close()
        handle = nil
        let previous = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
    }
}

func debugLog(_ message: @autoclosure () -> String) {
    Log.write(message())
}
