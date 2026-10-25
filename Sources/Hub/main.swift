import AppKit
import HubCore
import NeyKit

// Modo terminal, para depurar sem abrir a interface (usa os mesmos tokens do app):
//   Hub --selftest                          roda os testes e imprime "selftest ok"
//   Hub --dump                              lista aparelhos, pontos de dados e valores
//   Hub --tuya <id> <código> <valor JSON>   manda um comando Tuya
//   Hub --st <id> <capability> <comando> [argumentos JSON]
//   Hub --import-st-app <saída.json>       guarda o app OAuth criado pelo SmartThings CLI
//   Hub --atv-scan                          procura TVs Google TV / Android TV na rede
//   Hub --render <tela> <arquivo.png>      desenha uma tela com aparelhos de exemplo
let app = NSApplication.shared
let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    NeyKitSelfTest.run()
    MainActor.assumeIsolated { HubApp.selfTest() }
    print("selftest ok")
    exit(0)
}

if arguments.count > 1, arguments[1].hasPrefix("--"), arguments[1] != "--show" {
    Task { @MainActor in
        await DebugCLI.run(Array(arguments.dropFirst()))
        exit(0)
    }
    dispatchMain()
}

let delegate = MainActor.assumeIsolated { HubAppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
