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
        .font(Theme.font(13))
        // Sem ignorar a área segura, sobrava a faixa cinza do popover na borda.
        .background(Theme.room.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: .hubPopoverClosed)) { _ in
            // Ao reabrir, começa sempre do início (menos se estiver no meio de um pareamento).
            if store.pairing == nil, store.tvPairing == nil { route = .home }
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
    private var tvs: [HubDevice] { store.devices.filter { $0.kind == .tv } }
    private var tiles: [HubDevice] {
        store.devices.filter { !($0.kind == .airConditioner && $0.source == .smartThings) && ![.remote, .tv, .feeder].contains($0.kind) }
    }
    private var feeders: [HubDevice] { store.devices.filter { $0.kind == .feeder } }
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
                .font(Theme.font(12))
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Scroller {
                    VStack(spacing: 10) {
                        ForEach(climate) { ACCard(device: $0) }
                        ForEach(tvs) { device in TVCard(device: device) { open(device.id) } }
                        TileGrid(devices: tiles, columns: 2) { tile in DeviceTile(device: tile) { open(tile.id) } }
                        TileGrid(devices: feeders, columns: 1) { FeederCard(device: $0) }
                        if !remotes.isEmpty {
                            SectionTitle(text: "Controles")
                            TileGrid(devices: remotes, columns: 2) { tile in DeviceTile(device: tile) { open(tile.id) } }
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
                Text(greeting).font(Theme.font(20, .semibold))
                Text(summary).font(Theme.font(12)).foregroundStyle(.secondary).lineLimit(2)
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

    /// A casa numa frase: "Ar em 23°, Luz da sala acesa, TV no YouTube".
    private var summary: String {
        guard !store.devices.isEmpty else { return store.hasAccounts ? "Casa" : "Nenhuma conta conectada" }
        let on = store.devices.filter { $0.online && $0.isOn }
        var parts: [String] = []
        for ac in on where ac.kind == .airConditioner {
            parts.append(ac.acSetpoint.map { "Ar em \($0.short)°" } ?? "Ar ligado")
        }
        let lights = on.filter { $0.kind == .light }
        if lights.count == 1 { parts.append("\(lights[0].name) acesa") } else if lights.count > 1 { parts.append("\(lights.count) luzes acesas") }
        for tv in on where tv.kind == .tv {
            parts.append(tv.status["app"]?.string.flatMap(TVApps.name(of:)).map { $0 == "Início" ? "TV ligada" : "TV no \($0)" } ?? "TV ligada")
        }
        // Só tomadas e afins ligados: a contagem basta.
        if parts.isEmpty { parts.append(on.isEmpty ? "Tudo desligado" : on.count == 1 ? "1 aparelho ligado" : "\(on.count) aparelhos ligados") }
        let offline = store.devices.filter { !$0.online }.count
        if offline > 0 { parts.append(offline == 1 ? "1 sem conexão" : "\(offline) sem conexão") }
        return parts.joined(separator: ", ")
    }
}

/// Grade de colunas iguais. São poucos aparelhos, então não precisa ser lazy.
struct TileGrid<Tile: View>: View {
    let devices: [HubDevice]
    let columns: Int
    @ViewBuilder let tile: (HubDevice) -> Tile

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: devices.count, by: columns)), id: \.self) { index in
                GridRow {
                    ForEach(index..<index + columns, id: \.self) { slot in
                        // .id do aparelho: aparelho novo antes na lista não herda o menu aberto de outro.
                        if slot < devices.count { tile(devices[slot]).id(devices[slot].id) } else { Color.clear.frame(height: 1) }
                    }
                }
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.font(12, .semibold))
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
            Icon("exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(Theme.font(11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Icon("xmark", size: 9) }
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
            Icon("house.lodge.fill", size: 30)
                .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
            Text("Conecte suas contas").font(Theme.font(14, .semibold))
            Text("Smart Life, Tuya Smart e Positivo para a casa;\nSmartThings para o ar-condicionado.")
                .font(Theme.font(11.5))
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
