import CoreImage.CIFilterBuiltins
import NeyKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: HubStore
    @EnvironmentObject private var shell: Shell
    /// nil nos ajustes do Hub dentro do NeyHub (não há para onde voltar).
    let back: (() -> Void)?

    @ViewState private var userCode = ""
    @ViewState private var pairingApp = "Smart Life"
    @ViewState private var clientId = ""
    @ViewState private var clientSecret = ""
    @ViewState private var token = ""
    @ViewState private var showToken = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let back { IconButton(symbol: "chevron.left", help: "Voltar", action: back) }
                Text("Ajustes").font(Theme.font(15, .semibold))
                Spacer()
            }
            .padding(12)

            Scroller {
                VStack(spacing: 10) {
                    tuyaPanel
                    smartThingsPanel
                    TVSettingsPanel()
                    Panel(title: "App") {
                        // Hospedado o login, o modo, a atualização e o Sair são do NeyHub.
                        if shell.state.showsLogin { LoginRow() }
                        if shell.state.showsPresence, let presence = shell.presence {
                            ForEach([("Janela", \Presence.screen), ("Barra de menus", \Presence.menuBar)], id: \.0) { title, key in
                                // Desligar os dois não vale: o outro volta a ligar (`normalized`).
                                ToggleRow(title: title, isOn: presence[keyPath: key]) {
                                    var next = presence
                                    next[keyPath: key] = $0
                                    shell.onPresence(next.normalized(hasScreen: true))
                                }
                            }
                        }
                        if shell.state.showsUpdate {
                            HStack {
                                Text("Atualização pronta — entra ao sair").font(Theme.font(11.5))
                                Spacer()
                                GPill(title: "Reiniciar agora") { shell.relaunch() }.accessibilityLabel("Reiniciar o Domo agora")
                            }
                            .controlSize(.small)
                        }
                        HStack {
                            GPill(title: "Abrir registro", style: .ghost) { NSWorkspace.shared.open(Log.url) }
                            Spacer()
                            Text("Domo \(shell.state.version)").font(Theme.font(11)).foregroundStyle(.secondary)
                            if shell.state.showsQuit { GPill(title: "Sair do Domo", style: .ghost) { NSApp.terminate(nil) } }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: Tuya

    static let tuyaApps = ["Smart Life", "Tuya Smart", "Positivo"]

    private var tuyaPanel: some View {
        Panel(title: "Smart Life · Tuya Smart · Positivo") {
            ForEach(store.credentials.tuya, id: \.uid) { account in
                let devices = store.devices.filter { $0.source == .tuya(account: account.uid) }
                HStack {
                    Icon("checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(account.app ?? "Conta Tuya").font(Theme.font(12, .medium))
                        Text(devices.isEmpty ? "Nenhum aparelho" : devices.map(\.name).joined(separator: ", "))
                            .font(Theme.font(10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        ForEach(Self.tuyaApps, id: \.self) { app in
                            Button("É do \(app)") { store.renameTuya(uid: account.uid, app: app) }
                        }
                        Divider()
                        Button("Remover conta", role: .destructive) { store.removeTuya(uid: account.uid) }
                    } label: {
                        Icon("ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if let pairing = store.pairing {
                VStack(spacing: 8) {
                    if let payload = pairing.qrPayload, let image = QRCode.image(payload) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 180, height: 180)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                        Text("No app **\(pairing.app)** (na conta \(pairing.app)), toque no ícone de leitor no canto de cima da tela inicial e escaneie. Depois confirme o login no celular.")
                            .font(Theme.font(11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        if pairing.qrPayload != nil { ProgressView().controlSize(.mini) }
                        Text(pairing.message ?? "").font(Theme.font(11)).foregroundStyle(.secondary)
                    }
                    GPill(title: "Cancelar", style: .ghost) { store.cancelPairing() }
                }
                .frame(maxWidth: .infinity)
            } else {
                if !store.credentials.tuya.isEmpty { Divider().padding(.vertical, 2) }
                Text(store.credentials.tuya.isEmpty ? "Conectar conta" : "Conectar outra conta")
                    .font(Theme.font(12, .medium))
                HStack(spacing: 6) {
                    ForEach(Self.tuyaApps, id: \.self) { app in
                        Button(app) { pairingApp = app }
                            .buttonStyle(SoftChipStyle(selected: pairingApp == app, tint: Grafite.accent))
                    }
                }
                Text("No app \(pairingApp), vá em **Eu → ⚙︎ Configurações → Conta e segurança → Código de usuário** e cole aqui.")
                    .font(Theme.font(11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("Código de usuário do \(pairingApp)", text: $userCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { pair() }
                    GPill(title: "Gerar QR", action: pair)
                        .disabled(userCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.small)
            }
        }
    }

    private func pair() {
        store.startPairing(userCode: userCode, app: pairingApp)
        userCode = ""
    }

    // MARK: SmartThings

    private var smartThingsPanel: some View {
        Panel(title: "SmartThings") {
            if let auth = store.credentials.smartThings {
                HStack {
                    Icon("checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Conectado").font(Theme.font(12, .medium))
                        Text(auth.clientId.isEmpty ? "Token pessoal: vence \(auth.expiresAt.formatted(date: .omitted, time: .shortened))"
                                                   : "Renova sozinho")
                            .font(Theme.font(10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GPill(title: "Desconectar", style: .ghost) { store.disconnectSmartThings() }
                }
            } else if let app = store.credentials.smartThingsApp {
                Text("App OAuth pronto. O login da Samsung abre no seu navegador; depois de autorizar, volte aqui.")
                    .font(Theme.font(11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GPill(title: "Entrar com a Samsung") { store.connectSmartThings(clientId: app.clientId, clientSecret: app.clientSecret) }
            } else {
                Text("Use o Client ID e o Client Secret do app OAuth criado no SmartThings CLI. O login abre no seu navegador.")
                    .font(Theme.font(11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Client ID", text: $clientId).textFieldStyle(.roundedBorder).controlSize(.small)
                SecureField("Client Secret", text: $clientSecret).textFieldStyle(.roundedBorder).controlSize(.small)
                HStack {
                    GPill(title: "Entrar com a Samsung") { store.connectSmartThings(clientId: clientId, clientSecret: clientSecret) }
                        .disabled(clientId.isEmpty || clientSecret.isEmpty)
                    Spacer()
                    Button(showToken ? "Esconder" : "Usar token pessoal") { showToken.toggle() }
                        .buttonStyle(.link)
                }
                .controlSize(.small)
                if showToken {
                    Text("Tokens de account.smartthings.com/tokens valem só 24 h. Bom para testar.")
                        .font(Theme.font(10.5)).foregroundStyle(.secondary)
                    HStack {
                        SecureField("Token", text: $token).textFieldStyle(.roundedBorder)
                        GPill(title: "Usar") { store.useSmartThingsToken(token) }.disabled(token.isEmpty)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Abrir ao iniciar a sessão: só no avulso (o NeyHub nunca chama o SMAppService pelo Hub).
private struct LoginRow: View {
    @EnvironmentObject private var store: HubStore
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ToggleRow(title: "Abrir ao iniciar a sessão", isOn: launchAtLogin) { enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchAtLogin = enabled
            } catch {
                store.error = "Não consegui mudar a abertura automática: \(error.localizedDescription)"
            }
        }
    }
}

enum QRCode {
    static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)))
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
