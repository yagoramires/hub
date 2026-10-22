import SwiftUI

/// Conteúdo do popover: início, detalhes de um aparelho ou ajustes.
struct RootView: View {
    @EnvironmentObject private var store: HubStore
    @Local private var route: Route

    init(route: Route = .home) {
        _route = Local(initialValue: route)
    }

    enum Route: Equatable {
        case home, device(String), settings
    }

    var body: some View {
        ZStack {
            switch route {
            case .home:
                HomeView(open: { go(.device($0)) }, settings: { go(.settings) })
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .device(let id):
                if let device = store.devices.first(where: { $0.id == id }) {
                    DeviceDetailView(device: device, back: { go(.home) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Color.clear.onAppear { go(.home) }
                }
            case .settings:
                SettingsView(back: { go(.home) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 380)
        .onReceive(NotificationCenter.default.publisher(for: .hubPopoverClosed)) { _ in
            // Ao reabrir, começa sempre do início (menos se estiver no meio de um pareamento).
            if store.pairing == nil { route = .home }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hubOpenSettings)) { _ in route = .settings }
    }

    private func go(_ next: Route) {
        withAnimation(.snappy(duration: 0.28)) { route = next }
    }
}

extension Notification.Name {
    static let hubPopoverClosed = Notification.Name("hubPopoverClosed")
    static let hubOpenSettings = Notification.Name("hubOpenSettings")
}

struct HomeView: View {
    @EnvironmentObject private var store: HubStore
    let open: (String) -> Void
    let settings: () -> Void

    private var climate: [HubDevice] { store.devices.filter { $0.kind == .airConditioner && $0.source == .smartThings } }
    private var tiles: [HubDevice] { store.devices.filter { !($0.kind == .airConditioner && $0.source == .smartThings) && $0.kind != .remote } }
    private var remotes: [HubDevice] { store.devices.filter { $0.kind == .remote } }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if let error = store.error {
                ErrorBanner(text: error) { store.error = nil }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if store.devices.count > 1, store.devices.allSatisfy({ !$0.online }) {
                ErrorBanner(text: "Todos os aparelhos estão offline na nuvem. Eles costumam ficar assim quando perdem o Wi‑Fi (troca de roteador ou de senha).") {}
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if !store.hasAccounts {
                EmptyState(settings: settings)
            } else if store.devices.isEmpty {
                VStack(spacing: 8) {
                    if store.loadedOnce { Text("Nenhum aparelho encontrado").foregroundStyle(.secondary) }
                    else { ProgressView().controlSize(.small); Text("Buscando aparelhos…").foregroundStyle(.secondary) }
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Scroller {
                    VStack(spacing: 10) {
                        ForEach(climate) { ACCard(device: $0) }
                        TileGrid(devices: tiles, open: open)
                        if !remotes.isEmpty {
                            SectionTitle(text: "Controles")
                            TileGrid(devices: remotes, open: open)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.system(size: 19, weight: .semibold, design: .rounded))
                Text(summary).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(symbol: "arrow.clockwise", help: "Atualizar") { Task { await store.refresh() } }
                .rotationEffect(.degrees(store.loading ? 360 : 0))
                .animation(store.loading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: store.loading)
            IconButton(symbol: "gearshape", help: "Ajustes", action: settings)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Bom dia"
        case 12..<18: "Boa tarde"
        default: "Boa noite"
        }
    }

    private var summary: String {
        let online = store.devices.filter(\.online)
        guard !store.devices.isEmpty else { return store.hasAccounts ? "Casa" : "Nenhuma conta conectada" }
        let on = online.filter(\.isOn).count
        var text = on == 0 ? "Tudo desligado" : on == 1 ? "1 aparelho ligado" : "\(on) aparelhos ligados"
        let offline = store.devices.count - online.count
        if offline > 0 { text += " · \(offline) offline" }
        return text
    }
}

/// Grade de duas colunas. São poucos aparelhos, então não precisa ser lazy.
struct TileGrid: View {
    let devices: [HubDevice]
    let open: (String) -> Void

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: devices.count, by: 2)), id: \.self) { index in
                GridRow {
                    DeviceTile(device: devices[index]) { open(devices[index].id) }
                    if index + 1 < devices.count {
                        DeviceTile(device: devices[index + 1]) { open(devices[index + 1].id) }
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .padding(.leading, 4)
    }
}

struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

struct EmptyState: View {
    let settings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "house.lodge.fill")
                .font(.system(size: 30))
                .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
            Text("Conecte suas contas").font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Smart Life, Tuya Smart e Positivo para a casa;\nSmartThings para o ar-condicionado.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Conectar", action: settings)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
