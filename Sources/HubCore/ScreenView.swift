import NeyKit
import SwiftUI

/// Tela do Hub (janela do NeyHub ou modo Janela do avulso), no tema do próprio Hub. Casa: o ar à esquerda; TV, aparelhos
/// e ração no meio; o detalhe do aparelho sempre aberto à direita. TV: o controle inteiro. Ração: o plano de refeições.
struct ScreenView: View {
    @EnvironmentObject private var store: HubStore
    @ViewState private var tab: Tab
    @ViewState private var selected: String?
    @ViewState private var showSettings: Bool

    enum Tab: String, CaseIterable { case casa = "Casa", tv = "TV", racao = "Ração" }

    /// Os parâmetros só servem ao `--render` (ele não clica).
    init(tab: Tab = .casa, selected: String? = nil, showSettings: Bool = false) {
        _tab = ViewState(wrappedValue: tab)
        _selected = ViewState(wrappedValue: selected)
        _showSettings = ViewState(wrappedValue: showSettings)
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsView(back: { showSettings = false })
                    .frame(width: 400)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    banners
                    content
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
            }
        }
        .font(Theme.font(13))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoomGlows().ignoresSafeArea())
        // Popover e tela dividem o timer de 10 s: cada um conta enquanto aparece.
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
        .onReceive(NotificationCenter.default.publisher(for: .hubOpenSettings)) { _ in showSettings = true }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.greeting).font(Theme.font(18, .bold)).foregroundStyle(Grafite.strong)
                Text(store.summary).font(Theme.font(12)).foregroundStyle(Grafite.muted).lineLimit(2)
            }
            Spacer(minLength: 12)
            // Abas segmentadas, como as da tela do Dose.
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button(item.rawValue) { withAnimation(.snappy(duration: 0.25)) { tab = item } }
                        .buttonStyle(TabStyle(selected: tab == item))
                }
            }
            .padding(3)
            .background(Grafite.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Grafite.border, lineWidth: 1))
            .padding(.trailing, 4)
            IconButton(symbol: "arrow.clockwise", help: "Atualizar") { Task { await store.refresh() } }
                .rotationEffect(.degrees(store.loading ? 360 : 0))
                .animation(store.loading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: store.loading)
            IconButton(symbol: "gearshape", help: "Ajustes") { showSettings = true }
        }
    }

    @ViewBuilder private var banners: some View {
        if let error = store.error { ErrorBanner(text: error) { store.error = nil } }
        if store.devices.count > 1, store.devices.allSatisfy({ !$0.online }) {
            ErrorBanner(text: "Todos os aparelhos estão offline na nuvem. Eles costumam ficar assim quando perdem o Wi‑Fi (troca de roteador ou de senha).") {}
        }
    }

    @ViewBuilder private var content: some View {
        if !store.hasAccounts {
            EmptyState { showSettings = true }
        } else if store.devices.isEmpty {
            VStack(spacing: 8) {
                if store.loadedOnce { Text("Nenhum aparelho encontrado").foregroundStyle(.secondary) }
                else { ProgressView().controlSize(.small); Text("Buscando aparelhos…").foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            switch tab {
            case .casa: GeometryReader { casa(width: $0.size.width) }
            case .tv: centered(store.televisions, empty: "Nenhuma TV pareada. Pareie nos Ajustes.") { TVRemoteView(device: $0) }
            case .racao:
                centered(store.feeders.filter { $0.functions["meal_plan"] != nil }, empty: "Nenhum alimentador com refeições programadas.") { feeder in
                    VStack(spacing: 12) {
                        FeederCard(device: feeder)
                        MealPlanPanel(device: feeder)
                    }
                }
            }
        }
    }

    // MARK: Casa

    /// Largura (sem as margens da tela) a partir da qual a Casa fica em três colunas: o ar e o meio com ~256 pt cada (menos
    /// que isso o seletor de modo do ar quebra) e o detalhe com 260 pt. No NeyHub: área do plugin de 844 pt, ou seja, a
    /// janela com 1046 pt ou mais (170 da barra lateral, 32 da margem do NeyHub, 44 da margem da tela).
    static let threeColumns: CGFloat = 800
    /// O detalhe encolhe até aqui (as barras da luz afinam e as cores quebram em duas linhas).
    static let detailWidth: CGFloat = 260
    /// Abaixo disso a grade de aparelhos do meio fica com uma coluna (nomes inteiros em vez de "Luz…").
    static let twoTileColumns: CGFloat = 330

    /// Larga: três colunas como no mockup. Média (a janela padrão do NeyHub): ar, TV e aparelhos numa coluna e o detalhe
    /// ao lado. Estreita: uma coluna só, com o detalhe no fim.
    @ViewBuilder private func casa(width: CGFloat) -> some View {
        let detailWidth = Self.detailWidth
        if width >= Self.threeColumns {
            let left = (width - 28 - detailWidth) * 0.5
            let center = width - 28 - detailWidth - left
            HStack(alignment: .top, spacing: 14) {
                column { climate }.frame(width: left)
                column { middle(tileColumns: center >= Self.twoTileColumns ? 2 : 1) }
                detail.frame(width: detailWidth).frame(maxHeight: .infinity, alignment: .top)
            }
        } else if width >= 560 {
            HStack(alignment: .top, spacing: 14) {
                column { climate; middle(tileColumns: width - 14 - detailWidth >= Self.twoTileColumns ? 2 : 1) }
                detail.frame(width: detailWidth).frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            column { climate; middle(tileColumns: 2); detail }
        }
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) { content() }.padding(.bottom, 20)
        }
    }

    @ViewBuilder private var climate: some View {
        ForEach(store.climate) { ACCard(device: $0) }
    }

    @ViewBuilder private func middle(tileColumns: Int) -> some View {
        ForEach(store.televisions) { device in TVCard(device: device) { tab = .tv } }
        TileGrid(devices: store.tiles, columns: tileColumns) { tile in DeviceTile(device: tile, open: { selected = tile.id }, select: { selected = tile.id }) }
        ForEach(store.feeders) { feeder in FeederCard(device: feeder, select: { selected = feeder.id }) }
        if !store.remotes.isEmpty {
            SectionTitle(text: "Controles")
            TileGrid(devices: store.remotes, columns: tileColumns) { tile in DeviceTile(device: tile, open: { selected = tile.id }, select: { selected = tile.id }) }
        }
    }

    /// Sempre aberto: o mesmo detalhe do popover (luz, alimentador, tomada…), ou a dica quando nada foi escolhido.
    @ViewBuilder private var detail: some View {
        if let device = store.devices.first(where: { $0.id == selected }) {
            DeviceDetailView(device: device) { selected = nil }
                .id(device.id)
                .card()
        } else {
            VStack(spacing: 10) {
                Icon("hand.draw", size: 22).foregroundStyle(.secondary)
                Text("Clique num aparelho para ver o detalhe aqui.")
                    .font(Theme.font(12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .card()
        }
    }

    // MARK: TV e Ração

    private func centered<Item: Identifiable, Shown: View>(_ items: [Item], empty: String,
                                                           @ViewBuilder _ panel: @escaping (Item) -> Shown) -> some View {
        ScrollView(showsIndicators: false) {
            if items.isEmpty {
                Text(empty).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(items) { panel($0).frame(width: 420) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }
}

/// Aba do cabeçalho: a escolhida é a pílula clara, como no mockup.
private struct TabStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(12))
            .padding(.horizontal, 11)
            .frame(height: 24)
            .foregroundStyle(selected ? Grafite.strong : Grafite.muted)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color(red: 0.165, green: 0.176, blue: 0.2) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Fundo da tela: o quarto escuro do popover, com a luz suave de cada tipo de aparelho ligado.
struct RoomGlows: View {
    @EnvironmentObject private var store: HubStore

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Theme.room
                glow(Theme.accent(.airConditioner), on: store.climate.contains { $0.online && $0.isOn },
                     at: CGPoint(x: size.width * 0.2, y: size.height * 0.3), size: CGSize(width: 600, height: 300))
                glow(store.televisions.first.map { $0.tvLight(TVApps.load()) } ?? Theme.accent(.tv), on: store.televisions.contains { $0.online && $0.isOn },
                     at: CGPoint(x: size.width * 0.6, y: size.height * 0.7), size: CGSize(width: 500, height: 300))
                glow(Theme.accent(.light), on: store.tiles.contains { $0.kind == .light && $0.online && $0.isOn },
                     at: CGPoint(x: size.width * 0.85, y: size.height * 0.4), size: CGSize(width: 400, height: 260))
            }
        }
        .animation(.easeOut(duration: 0.6), value: store.anyOn)
    }

    /// Gradiente radial (e não blur): a luz se espalha igual na tela e no `--render`.
    private func glow(_ color: Color, on: Bool, at point: CGPoint, size: CGSize) -> some View {
        Ellipse().fill(RadialGradient(colors: [color.opacity(0.12), color.opacity(0)], center: .center, startRadius: 0,
                                      endRadius: size.width / 2))
            .scaleEffect(x: 1, y: size.height / size.width)
            .frame(width: size.width, height: size.width)
            .opacity(on ? 1 : 0).position(point).allowsHitTesting(false)
    }
}
