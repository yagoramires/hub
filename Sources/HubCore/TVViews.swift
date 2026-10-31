import NeyKit
import SwiftUI

enum TVApps {
    struct App: Identifiable, Codable, Equatable {
        let name: String
        let link: String
        var id: String { link }

        var color: Color {
            if let known = TVApps.colors[name] { return Color(hex: known) }
            // App adicionado pelo usuário: cor estável a partir do nome.
            let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
            return Color(hue: hue, saturation: 0.6, brightness: 0.75)
        }

        var package: String? {
            link.hasPrefix(TVApps.launchPrefix) ? String(link.dropFirst(TVApps.launchPrefix.count)) : TVApps.linkPackages[link]
        }

        /// Ícone da Play Store guardado em `<resources>/AppLogos`; app sem ícone (ou sem a pasta) fica com o nome.
        var logo: NSImage? {
            guard let package, let folder = Theme.resources else { return nil }
            return NSImage(contentsOf: folder.appendingPathComponent("AppLogos/\(package).png"))
        }
    }

    static let launchPrefix = "market://launch?id="
    private static let linkPackages = [
        "https://www.youtube.com": "com.google.android.youtube.tv", "netflix://": "com.netflix.ninja",
        "https://app.primevideo.com": "com.amazon.amazonvideo.livingroom", "https://www.disneyplus.com": "com.disney.disneyplus",
        "spotify://": "com.spotify.tv.android", "twitch://home": "tv.twitch.android.app",
    ]

    /// Links documentados pelo Home Assistant; o resto abre pelo pacote (market://launch?id=…).
    static let defaults: [App] = [
        App(name: "YouTube", link: "https://www.youtube.com"),
        App(name: "Netflix", link: "netflix://"),
        App(name: "Prime", link: "https://app.primevideo.com"),
        App(name: "Disney+", link: "https://www.disneyplus.com"),
        App(name: "Globoplay", link: "market://launch?id=com.globo.globotv"),
        App(name: "Spotify", link: "spotify://"),
        App(name: "Max", link: "market://launch?id=com.wbd.stream"),
        App(name: "Apple TV", link: "market://launch?id=com.apple.atve.androidtv.appletv"),
        App(name: "Twitch", link: "twitch://home"),
        App(name: "Crunchyroll", link: "market://launch?id=com.crunchyroll.crunchyroid"),
        App(name: "Pluto TV", link: "market://launch?id=tv.pluto.android"),
    ]

    /// Cor de cada app: vira a luz da TV no Hub quando ele está aberto.
    private static let colors: [String: UInt32] = [
        "YouTube": 0xFF1F2D, "Netflix": 0xE50914, "Prime": 0x1AA8E8, "Prime Video": 0x1AA8E8, "Disney+": 0x13708F,
        "Globoplay": 0xFF2D55, "Spotify": 0x1ED760, "Max": 0x4B3BFF, "Twitch": 0x9146FF, "Crunchyroll": 0xF47521,
        "Pluto TV": 0xFFD400, "Apple TV": 0x6E8BFF,
    ]

    private static let key = "tvApps"
    /// Os padrões do Hub: `.standard` no avulso, `AppDefaults.forApp("local.hub")` no NeyHub (o mesmo domínio).
    static var userDefaults = UserDefaults.standard
    static let changed = Notification.Name("hubTVAppsChanged")
    /// Lida do disco uma vez; o resto do app usa esta cópia.
    private static var cached: [App]?

    static func load() -> [App] {
        if let cached { return cached }
        let apps = (userDefaults.data(forKey: key).flatMap { try? JSONDecoder().decode([App].self, from: $0) } ?? defaults)
            // com.hbo.hbonow não existe nessa TV; o Max dela é com.wbd.stream (listas salvas com o nome errado).
            .map { $0.link == "market://launch?id=com.hbo.hbonow" ? App(name: $0.name, link: "market://launch?id=com.wbd.stream") : $0 }
        cached = apps
        return apps
    }

    static func save(_ apps: [App]) {
        cached = apps
        userDefaults.set(try? JSONEncoder().encode(apps), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// O app aberto na TV como botão: o da lista, se houver, senão um montado pelo pacote.
    static func app(package: String?, in apps: [App]) -> App? {
        guard let package, !package.isEmpty, name(of: package) != "Início" else { return nil }
        return apps.first { $0.package == package }
            ?? App(name: name(of: package) ?? package.split(separator: ".").last.map { $0.capitalized } ?? package,
                   link: launchPrefix + package)
    }

    /// Apps que abrem a busca pelo link mas ignoram o texto; o Hub digita depois.
    static let typesAfterSearch: Set<String> = ["com.wbd.stream"]

    /// Link de busca de cada app (conferido com `cmd package query-activities` na TCL).
    /// A Netflix aceita o link nflx://…/search mas ignora, aberta ou não (testado em 2026-10-24).
    static func searchLink(package: String, query: String) -> String? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        return switch package {
        case "com.google.android.youtube.tv": "https://www.youtube.com/results?search_query=\(q)"
        case "com.amazon.amazonvideo.livingroom": "https://app.primevideo.com/search?phrase=\(q)"
        case "com.disney.disneyplus": "https://www.disneyplus.com/search?q=\(q)"
        case "com.wbd.stream": "https://play.hbomax.com/search"
        default: nil
        }
    }

    static func name(of package: String) -> String? {
        let known = [
            "com.google.android.youtube.tv": "YouTube", "com.netflix.ninja": "Netflix",
            "com.amazon.amazonvideo.livingroom": "Prime Video", "com.disney.disneyplus": "Disney+",
            "com.globo.globotv": "Globoplay", "com.spotify.tv.android": "Spotify", "com.hbo.hbonow": "Max", "com.wbd.stream": "Max",
            "tv.twitch.android.app": "Twitch", "com.crunchyroll.crunchyroid": "Crunchyroll", "tv.pluto.android": "Pluto TV",
            "com.apple.atve.androidtv.appletv": "Apple TV",
            "com.google.android.apps.tv.launcherx": "Início", "com.google.android.tvlauncher": "Início",
        ]
        return known[package]
    }

    /// App que está aberto na TV, pronto para virar botão (nil se for a tela inicial ou já estiver na lista).
    static func fromCurrent(_ package: String?, existing: [App]) -> App? {
        guard let app = app(package: package, in: existing) else { return nil }
        return existing.contains { $0.link == app.link || $0.name == app.name } ? nil : app
    }
}

extension HubDevice {
    var tvStatus: String {
        guard online else { return status["needs_pairing"]?.bool == true ? "Precisa parear de novo" : "Sem conexão" }
        guard isOn else { return "Em espera" }
        if let package = status["app"]?.string, let app = TVApps.name(of: package) {
            return app == "Início" ? "Na tela inicial" : "\(app) aberto"
        }
        return "Ligada"
    }

    /// Luz da TV ligada: o verde do app, qualquer que seja o app aberto.
    func tvLight(_ apps: [TVApps.App]) -> Color { Grafite.accent }
}

extension Color {
    /// Cores claras (Spotify, Prime, Apple TV) pedem texto escuro por cima.
    var prefersDarkInk: Bool {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return false }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent > 0.5
    }

    var ink: Color { prefersDarkInk ? Color.black.opacity(0.85) : .white }
}

/// Cartão da TV na tela principal: brilha na cor do app aberto, com os apps e o volume à mão.
struct TVCard: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let open: () -> Void
    @ViewState private var apps = TVApps.load()

    private var on: Bool { device.online && device.isOn }
    private var light: Color { device.tvLight(apps) }
    private var current: TVApps.App? { TVApps.app(package: device.status["app"]?.string, in: apps) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Group {
                    if on, let current {
                        AppLogo(app: current, corner: 8)
                    } else {
                        Icon("tv.fill", size: 14)
                            .foregroundStyle(on ? light : Color.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? light.opacity(0.18) : Theme.well))
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(Theme.font(13.5, .semibold)).lineLimit(1)
                    Text(device.tvStatus).font(Theme.font(11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: open) {
                    Icon("av.remote.fill", size: 13)
                        .foregroundStyle(Grafite.ghostText)
                        .frame(width: 28, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Grafite.ghostBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help("Controle")
                PowerSwitch(on: on, label: device.name) { store.toggle(device) }
                    .disabled(!device.online)
            }
            if on {
                HStack(spacing: 8) {
                    ForEach(apps.prefix(6)) { app in
                        let open = app.package == current?.package
                        Button { store.tvLaunch(device, app.link) } label: {
                            AppLogo(app: app, corner: 13)
                                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(open ? Grafite.accent : .clear, lineWidth: 2).padding(-4))
                        }
                        .buttonStyle(PressStyle())
                        .help(app.name)
                        .accessibilityLabel("Abrir \(app.name)")
                    }
                }
                .padding(.horizontal, 2)
                HStack(spacing: 6) {
                    VolumeSlider(device: device, tint: light)
                    ForEach([("arrow.uturn.backward", "Voltar", ATVRemote.Key.back),
                             ("house.fill", "Início", .home),
                             ("playpause.fill", "Tocar ou pausar", .playPause)], id: \.1) { symbol, label, key in
                        TVKey(device: device, symbol: symbol, label: label, key: key, height: 34, corner: 8)
                            .frame(width: 34)
                    }
                }
            }
        }
        .padding(12)
        .card()
        .glow(light, on: on)
        .animation(.easeOut(duration: 0.3), value: device.status["app"]?.string)
        .onReceive(NotificationCenter.default.publisher(for: TVApps.changed)) { _ in apps = TVApps.load() }
    }
}

/// Barra de volume estilo Central de Controle: arrastar escolhe o volume, o alto-falante tira o som.
struct VolumeSlider: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let tint: Color
    var height: CGFloat = 34
    @ViewState private var dragging: Double? = nil

    var body: some View {
        let maximum = max(device.status["volume_max"]?.number ?? 100, 1)
        let level = device.status["volume"]?.number ?? 0
        let muted = device.status["muted"]?.bool == true
        let fraction = dragging ?? level / maximum
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.well)
                Rectangle().fill(tint.opacity(muted ? 0.35 : 1))
                    .frame(width: max(height, geometry.size.width * fraction))
                HStack {
                    Icon(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 12)
                        .foregroundStyle(tint.ink)
                        .frame(width: height, height: height)
                    Spacer()
                    Text(muted ? "mudo" : "\(Int((fraction * maximum).rounded()))")
                        .font(Theme.number(12.5, .bold))
                        .monospacedDigit()
                        .padding(.trailing, 12)
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard drag.startLocation.x > height else { return }
                    dragging = min(max(drag.location.x / geometry.size.width, 0), 1)
                }
                .onEnded { drag in
                    // Toque no alto-falante tira/volta o som; o resto da barra é o volume.
                    if drag.startLocation.x <= height, abs(drag.translation.width) < 4 { return store.tvKey(device, .mute) }
                    guard let dragging else { return }
                    store.tvSetVolume(device, to: Int((dragging * maximum).rounded()))
                    let sent = dragging
                    // Um toque novo nesse meio tempo tem o próprio valor; não apaga.
                    Task { try? await Task.sleep(for: .seconds(2)); if self.dragging == sent { self.dragging = nil } }
                })
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.2), value: level)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(muted ? "sem som" : "\(Int(level))")
        .accessibilityAdjustableAction { direction in store.tvKey(device, direction == .increment ? .volumeUp : .volumeDown) }
    }
}

/// Ícone quadrado do app; sem logo, o nome sobre a cor do app.
struct AppLogo: View {
    let app: TVApps.App
    var corner: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Group {
            if let logo = app.logo {
                Image(nsImage: logo).resizable().interpolation(.high).background(.white)
            } else {
                Text(app.name)
                    .font(Theme.font(10.5, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(app.color)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }
}

/// Controle completo: apps no topo, touchpad ou setas, teclas, volume e busca. As setas, Enter e
/// Delete do teclado também comandam a TV.
struct TVRemoteView: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    @FocusState private var focused: Bool
    @ViewState private var apps = TVApps.load()
    @ViewState private var text = ""
    @FocusState private var typing: Bool
    @ViewState private var usesPad = TVApps.userDefaults.object(forKey: "tvTouchpad") as? Bool ?? true

    private var package: String { device.status["app"]?.string ?? "" }
    private var appName: String { TVApps.name(of: package) ?? "app" }
    private var canSearch: Bool { TVApps.searchLink(package: package, query: "") != nil || package == "com.globo.globotv" }
    private var light: Color { device.tvLight(apps) }
    private var current: TVApps.App? { TVApps.app(package: package, in: apps) }

    /// Com texto, busca direto; vazio, só abre a busca do app.
    private func search() {
        store.tvSearch(device, text)
        text = ""
        releaseKeyboard()
    }

    private func sendText() {
        guard !text.isEmpty else { return }
        store.tvType(device, text)
        text = ""
        releaseKeyboard()
    }

    /// Tira o foco da caixa de busca: senão as setas do Mac continuavam presas nela.
    private func releaseKeyboard() {
        typing = false
        focused = true
    }

    private func update(_ list: [TVApps.App]) {
        apps = list
        TVApps.save(list)
    }

    var body: some View {
        VStack(spacing: 14) {
            appGrid

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    key("power", "Ligar ou desligar a TV", .power)
                    key("rectangle.connected.to.line.below", "Entrada", .input)
                    key("mic", "Assistente", .assist)
                    key("line.3.horizontal", "Menu", .menu)
                    key("gearshape.fill", "Ajustes da TV", .settings)
                }
                Picker("Direcional", selection: Binding(get: { usesPad }, set: { pad in
                    usesPad = pad
                    TVApps.userDefaults.set(pad, forKey: "tvTouchpad")
                })) {
                    Text("Touchpad").tag(true)
                    Text("Setas").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // VOL e CH dos lados das setas (ou do touchpad), como num controle de verdade.
                HStack(spacing: 10) {
                    rocker("VOL", up: ("plus", "Aumentar o volume", .volumeUp), down: ("minus", "Diminuir o volume", .volumeDown))
                    if usesPad {
                        Touchpad(tint: light) { store.tvKey(device, $0) }
                    } else {
                        dpad.frame(maxWidth: .infinity)
                    }
                    rocker("CH", up: ("chevron.up", "Próximo canal", .channelUp), down: ("chevron.down", "Canal anterior", .channelDown))
                }

                HStack(spacing: 6) {
                    key("arrow.uturn.backward", "Voltar", .back)
                    key("house.fill", "Início", .home)
                    key("info.circle", "Informações", .info)
                    key("captions.bubble", "Legendas", .captions)
                    key("speaker.slash.fill", "Sem som", .mute)
                }
                HStack(spacing: 6) {
                    key("backward.end.fill", "Anterior", .mediaPrevious)
                    key("backward.fill", "Voltar a fita", .mediaRewind)
                    TVKey(device: device, symbol: "playpause.fill", label: "Tocar ou pausar", key: .playPause, filled: true)
                    key("forward.fill", "Avançar", .mediaFastForward)
                    key("forward.end.fill", "Próximo", .mediaNext)
                }
            }
            .padding(10)
            .card(Theme.matte)

            VolumeSlider(device: device, tint: light, height: 44)

            searchBar

            Text("Com o controle aberto, as setas, Enter e Delete do teclado comandam a TV.")
                .font(Theme.font(10.5)).foregroundStyle(.secondary)
        }
        .background(alignment: .top) {
            SoftGlow(color: light, width: 340, height: 220, spread: 70).opacity(0.18).offset(y: -90)
        }
        .animation(.easeOut(duration: 0.35), value: package)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .delete, .escape]) { press in
            // Digitando na caixa de busca, as teclas são da caixa, não do controle.
            if typing { return .ignored }
            switch press.key {
            case .upArrow: store.tvKey(device, .up)
            case .downArrow: store.tvKey(device, .down)
            case .leftArrow: store.tvKey(device, .left)
            case .rightArrow: store.tvKey(device, .right)
            case .return: store.tvKey(device, .center)
            case .delete, .escape: store.tvKey(device, .back)
            default: return .ignored
            }
            return .handled
        }
    }

    private var appGrid: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(apps) { app in
                    let open = app.package == current?.package
                    Button { store.tvLaunch(device, app.link) } label: {
                        AppLogo(app: app, corner: 18)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(open ? Grafite.accent : .clear, lineWidth: 2).padding(-4))
                            .scaleEffect(open ? 1.04 : 1)
                    }
                    .buttonStyle(PressStyle())
                    .help(app.name)
                    .accessibilityLabel("Abrir \(app.name)")
                    .contextMenu {
                        Button("Remover", role: .destructive) { update(apps.filter { $0 != app }) }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            HStack {
                if let add = TVApps.fromCurrent(device.status["app"]?.string, existing: apps) {
                    Button { update(apps + [add]) } label: {
                        Label { Text("Adicionar \(add.name), aberto na TV") } icon: { Icon("plus.circle.fill", size: 12) }
                    }
                    .foregroundStyle(light)
                } else {
                    Text("Para adicionar, abra o app na TV. Botão direito remove.").foregroundStyle(.secondary)
                }
                Spacer()
                if apps != TVApps.defaults {
                    Button("Restaurar") { update(TVApps.defaults) }.foregroundStyle(.secondary)
                }
            }
            .font(Theme.font(11))
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
    }

    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if let current {
                        AppLogo(app: current, corner: 8)
                    } else {
                        Icon("magnifyingglass", size: 12).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 28, height: 28)
                TextField(canSearch ? "Buscar no \(appName)" : "Digitar na TV", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.font(13))
                    .focused($typing)
                    .onSubmit { canSearch ? search() : sendText() }
                if !text.isEmpty {
                    Button { text = "" } label: { Icon("xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Limpar")
                }
                Button { store.tvDelete(device) } label: {
                    Icon("delete.left", size: 12).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Apagar uma letra na TV")
                Button(canSearch ? "Buscar" : "Enviar") { canSearch ? search() : sendText() }
                    .buttonStyle(FilledStyle(tint: light))
                    .disabled(!canSearch && text.isEmpty)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 44)
            .card(Theme.well, edge: typing ? light.opacity(0.7) : nil, corner: 8)
            .animation(.easeOut(duration: 0.15), value: typing)
            if canSearch, !text.isEmpty {
                Button("Só digitar o texto na TV", action: sendText)
                    .buttonStyle(.plain).font(Theme.font(11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if !canSearch {
                Text("\(appName == "app" ? "Esse app" : appName) não aceita busca direta: abra a busca na TV e envie o texto.")
                    .font(Theme.font(10.5)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var dpad: some View {
        ZStack {
            Circle().fill(Theme.well).frame(width: 196, height: 196)
                .overlay(Circle().strokeBorder(Grafite.cardBorder))
            VStack(spacing: 0) {
                arrow("chevron.up", .up)
                HStack(spacing: 0) {
                    arrow("chevron.left", .left)
                    Button { store.tvKey(device, .center) } label: {
                        Text("OK")
                            .font(Theme.number(15, .bold))
                            .foregroundStyle(Grafite.strong)
                            .frame(width: 66, height: 66)
                            .background(Circle().fill(Color(red: 0.165, green: 0.176, blue: 0.2)))
                    }
                    .buttonStyle(PressStyle())
                    arrow("chevron.right", .right)
                }
                arrow("chevron.down", .down)
            }
        }
        .frame(height: 200)
    }

    /// Botão comprido de dois lados (VOL, CH).
    private func rocker(_ title: String, up: (String, String, ATVRemote.Key), down: (String, String, ATVRemote.Key)) -> some View {
        VStack(spacing: 0) {
            ForEach([up], id: \.1) { rockerKey($0) }
            Text(title).font(Theme.font(9, .bold)).tracking(1).foregroundStyle(Grafite.label)
            ForEach([down], id: \.1) { rockerKey($0) }
        }
        .frame(width: 42, height: 170)
        .background(Capsule().fill(Theme.well))
        .overlay(Capsule().strokeBorder(Grafite.cardBorder))
    }

    private func rockerKey(_ item: (String, String, ATVRemote.Key)) -> some View {
        Button { store.tvKey(device, item.2) } label: {
            Icon(item.0, size: 13).foregroundStyle(Grafite.ghostText).frame(width: 42, height: 64).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(item.1)
        .accessibilityLabel(item.1)
    }

    private func arrow(_ symbol: String, _ key: ATVRemote.Key) -> some View {
        Button { store.tvKey(device, key) } label: {
            Icon(symbol, size: 17)
                .frame(width: 54, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func key(_ symbol: String, _ label: String, _ key: ATVRemote.Key) -> some View {
        TVKey(device: device, symbol: symbol, label: label, key: key)
    }
}

/// Tecla do controle: usada no controle completo e, menor, no cartão da tela principal.
struct TVKey: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let symbol: String
    let label: String
    let key: ATVRemote.Key
    var height: CGFloat = 32
    var corner: CGFloat = 8
    /// Tecla principal (play/pause): verde do app.
    var filled = false

    var body: some View {
        Button { store.tvKey(device, key) } label: {
            Icon(symbol, size: 13)
                .foregroundStyle(filled ? Grafite.onAccent : Grafite.ghostText)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(filled ? Grafite.accent : Theme.well))
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(filled ? .clear : Grafite.cardBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Área de arrastar como o touchpad do Siri Remote: cada 36 pt num eixo é uma seta; um toque é OK.
struct Touchpad: View {
    let tint: Color
    let send: (ATVRemote.Key) -> Void
    @ViewState private var anchor: CGSize = .zero
    @ViewState private var finger: CGPoint? = nil
    /// O arrasto já mandou alguma seta: soltar não vale OK, mesmo que o dedo volte ao ponto de partida.
    @ViewState private var moved = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(light: 0xE6E6EB, dark: 0x2A2A2F))
            Canvas { canvas, size in
                // Textura de pontinhos, como a de um trackpad.
                for x in stride(from: 7.0, to: size.width, by: 14) {
                    for y in stride(from: 7.0, to: size.height, by: 14) {
                        canvas.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(.primary.opacity(0.12)))
                    }
                }
            }
            if let finger {
                Circle().fill(tint).frame(width: 46, height: 46).blur(radius: 3).opacity(0.6)
                    .shadow(color: tint, radius: 18)
                    .position(finger)
            } else {
                VStack(spacing: 8) {
                    Icon("hand.draw", size: 22)
                    Text("Arraste para mover, clique para OK").font(Theme.font(11.5))
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 210)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                finger = drag.location
                let dx = drag.translation.width - anchor.width, dy = drag.translation.height - anchor.height
                let step: CGFloat = 36
                if abs(dx) >= step, abs(dx) > abs(dy) {
                    moved = true
                    send(dx > 0 ? .right : .left)
                    anchor.width += dx > 0 ? step : -step
                    anchor.height = drag.translation.height
                } else if abs(dy) >= step {
                    moved = true
                    send(dy > 0 ? .down : .up)
                    anchor.height += dy > 0 ? step : -step
                    anchor.width = drag.translation.width
                }
            }
            .onEnded { drag in
                if !moved, abs(drag.translation.width) < 4, abs(drag.translation.height) < 4 { send(.center) }
                moved = false
                anchor = .zero
                withAnimation(.easeOut(duration: 0.25)) { finger = nil }
            })
        .accessibilityElement()
        .accessibilityLabel("Touchpad")
        .accessibilityHint("Use as setas do teclado para mover e Enter para OK")
    }
}

/// Botão cheio na cor do aparelho.
struct FilledStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(12.5, .bold))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(tint.ink)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Parear e remover TVs, dentro dos Ajustes.
struct TVSettingsPanel: View {
    @EnvironmentObject private var store: HubStore
    @ViewState private var code = ""
    @ViewState private var name = ""

    var body: some View {
        Panel(title: "TV · Google TV / Android TV") {
            ForEach(store.credentials.androidTVs ?? [], id: \.host) { tv in
                HStack {
                    Icon("checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tv.name).font(Theme.font(12, .medium))
                        Text(tv.host).font(Theme.font(10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GPill(title: "Remover", style: .ghost) { store.removeTV(host: tv.host) }
                }
            }

            if let pairing = store.tvPairing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pareando com \(pairing.name)").font(Theme.font(12, .medium))
                    if let message = pairing.message {
                        Text(message).font(Theme.font(11)).foregroundStyle(.secondary)
                    }
                    if pairing.waitingCode {
                        HStack {
                            TextField("Código da TV (ex.: 4F2A9C)", text: $code)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .onSubmit { store.finishTVPairing(code: code) }
                            GPill(title: "Confirmar") { store.finishTVPairing(code: code) }
                                .disabled(code.trimmingCharacters(in: .whitespaces).count != 6)
                        }
                        .controlSize(.small)
                    }
                    GPill(title: "Cancelar", style: .ghost) { store.cancelTVPairing(); code = "" }
                }
            } else if let scan = store.tvScan {
                if scan.searching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Procurando TVs na rede…").font(Theme.font(11)).foregroundStyle(.secondary)
                    }
                } else if scan.found.isEmpty {
                    Text("Nenhuma TV nova encontrada. Ela precisa estar ligada e no mesmo Wi‑Fi.")
                        .font(Theme.font(11)).foregroundStyle(.secondary)
                    GPill(title: "Procurar de novo", style: .ghost) { store.scanTVs() }
                } else {
                    ForEach(scan.found) { tv in
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(tv.name).font(Theme.font(12, .medium)).lineLimit(1)
                                Text(tv.host).font(Theme.font(10.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            GPill(title: "Parear") {
                                code = ""
                                store.startTVPairing(name: name.isEmpty ? tv.name : name, host: tv.host)
                            }
                        }
                    }
                    TextField("Nome no Domo (opcional, ex.: TV da sala)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
            } else {
                Text("Liga, desliga, volume, direcional e apps, direto pela rede de casa. Na primeira vez a TV mostra um código.")
                    .font(Theme.font(11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GPill(title: "Procurar TV", style: .ghost) { store.scanTVs() }
            }
        }
    }
}
