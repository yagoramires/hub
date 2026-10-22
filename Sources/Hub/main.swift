import AppKit

// Modo terminal, para depurar sem abrir a interface (usa os mesmos tokens do app):
//   Hub --dump                              lista aparelhos, pontos de dados e valores
//   Hub --tuya <id> <código> <valor JSON>   manda um comando Tuya
//   Hub --st <id> <capability> <comando> [argumentos JSON]
//   Hub --import-st-app <saída.json>       guarda o app OAuth criado pelo SmartThings CLI
//   Hub --render <tela> <arquivo.png>      desenha uma tela com aparelhos de exemplo
let arguments = CommandLine.arguments
if arguments.count > 1, arguments[1].hasPrefix("--") {
    Task { @MainActor in
        await DebugCLI.run(Array(arguments.dropFirst()))
        exit(0)
    }
    dispatchMain()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
