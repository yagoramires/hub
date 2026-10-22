import CoreImage.CIFilterBuiltins
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: HubStore
    let back: () -> Void

    @Local private var userCode = ""
    @Local private var clientId = ""
    @Local private var clientSecret = ""
    @Local private var token = ""
    @Local private var showToken = false
    @Local private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconButton(symbol: "chevron.left", help: "Voltar", action: back)
                Text("Ajustes").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(12)

            Scroller {
                VStack(spacing: 10) {
                    tuyaPanel
                    smartThingsPanel
                    Panel(title: "App") {
                        ToggleRow(title: "Abrir ao iniciar a sessão", isOn: launchAtLogin) { enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                launchAtLogin = enabled
                            } catch {
                                store.error = "Não consegui mudar a abertura automática: \(error.localizedDescription)"
                            }
                        }
                        HStack {
                            Button("Abrir registro") { NSWorkspace.shared.open(Log.url) }
                            Spacer()
                            Button("Sair do Hub") { NSApp.terminate(nil) }
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

    private var tuyaPanel: some View {
        Panel(title: "Smart Life · Tuya · Positivo") {
            ForEach(store.credentials.tuya, id: \.uid) { account in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(account.username.isEmpty ? "Conta Tuya" : account.username).font(.system(size: 12, weight: .medium))
                        Text("\(store.devices.filter { $0.source == .tuya(account: account.uid) }.count) aparelhos")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remover") { store.removeTuya(uid: account.uid) }.controlSize(.small)
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
                        Text("No app **Smart Life**, toque no ícone de leitor no canto de cima da tela inicial e escaneie. Depois confirme o login no celular.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 6) {
                        if pairing.qrPayload != nil { ProgressView().controlSize(.mini) }
                        Text(pairing.message ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button("Cancelar") { store.cancelPairing() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Código de usuário: no app Smart Life, vá em **Eu → ⚙︎ Configurações → Conta e segurança → Código de usuário**.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("Código de usuário", text: $userCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.startPairing(userCode: userCode) }
                    Button("Gerar QR") { store.startPairing(userCode: userCode) }
                        .disabled(userCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: SmartThings

    private var smartThingsPanel: some View {
        Panel(title: "SmartThings") {
            if let auth = store.credentials.smartThings {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Conectado").font(.system(size: 12, weight: .medium))
                        Text(auth.clientId.isEmpty ? "Token pessoal: vence \(auth.expiresAt.formatted(date: .omitted, time: .shortened))"
                                                   : "Renova sozinho")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Desconectar") { store.disconnectSmartThings() }.controlSize(.small)
                }
            } else if let app = store.credentials.smartThingsApp {
                Text("App OAuth pronto. Falta entrar com a conta Samsung, numa janela que abre agora.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Entrar com a Samsung") { store.connectSmartThings(clientId: app.clientId, clientSecret: app.clientSecret) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Text("Use o Client ID e o Client Secret do app OAuth criado no SmartThings CLI. O login abre numa janela da Samsung.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Client ID", text: $clientId).textFieldStyle(.roundedBorder).controlSize(.small)
                SecureField("Client Secret", text: $clientSecret).textFieldStyle(.roundedBorder).controlSize(.small)
                HStack {
                    Button("Entrar com a Samsung") { store.connectSmartThings(clientId: clientId, clientSecret: clientSecret) }
                        .disabled(clientId.isEmpty || clientSecret.isEmpty)
                    Spacer()
                    Button(showToken ? "Esconder" : "Usar token pessoal") { showToken.toggle() }
                        .buttonStyle(.link)
                }
                .controlSize(.small)
                if showToken {
                    Text("Tokens de account.smartthings.com/tokens valem só 24 h. Bom para testar.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    HStack {
                        SecureField("Token", text: $token).textFieldStyle(.roundedBorder)
                        Button("Usar") { store.useSmartThingsToken(token) }.disabled(token.isEmpty)
                    }
                    .controlSize(.small)
                }
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
