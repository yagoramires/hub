import SwiftUI

enum TVApps {
    struct App: Identifiable, Codable, Equatable {
        let name: String
        let link: String
        var id: String { link }

        var color: Color {
            if let known = TVApps.colors[name] { return known }
            // App adicionado pelo usuário: cor estável a partir do nome.
            let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
            return Color(hue: hue, saturation: 0.6, brightness: 0.75)
        }
    }

    /// Links documentados pelo Home Assistant; o resto abre pelo pacote (market://launch?id=…).
    static let defaults: [App] = [
        App(name: "YouTube", link: "https://www.youtube.com"),
        App(name: "Netflix", link: "netflix://"),
        App(name: "Prime", link: "https://app.primevideo.com"),
        App(name: "Disney+", link: "https://www.disneyplus.com"),
        App(name: "Globoplay", link: "market://launch?id=com.globo.globotv"),
        App(name: "Spotify", link: "spotify://"),
        App(name: "Max", link: "market://launch?id=com.wbd.stream"),
        App(name: "Twitch", link: "twitch://home"),
        App(name: "Crunchyroll", link: "market://launch?id=com.crunchyroll.crunchyroid"),
        App(name: "Pluto TV", link: "market://launch?id=tv.pluto.android"),
    ]

    private static let colors: [String: Color] = [
        "YouTube": Color(red: 0.93, green: 0.13, blue: 0.13), "Netflix": Color(red: 0.75, green: 0.04, blue: 0.08),
        "Prime": Color(red: 0.0, green: 0.66, blue: 0.88), "Disney+": Color(red: 0.07, green: 0.2, blue: 0.55),
        "Globoplay": Color(red: 0.98, green: 0.36, blue: 0.13), "Spotify": Color(red: 0.11, green: 0.73, blue: 0.33),
        "Max": Color(red: 0.0, green: 0.2, blue: 0.85), "Twitch": Color(red: 0.57, green: 0.27, blue: 1.0),
        "Crunchyroll": Color(red: 0.96, green: 0.46, blue: 0.13), "Pluto TV": Color(red: 0.2, green: 0.2, blue: 0.25),
    ]

    private static let key = "tvApps"

    static func load() -> [App] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let apps = try? JSONDecoder().decode([App].self, from: data) else { return defaults }
        return apps
    }

    static func save(_ apps: [App]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(apps), forKey: key)
    }

    static func name(of package: String) -> String? {
        let known = [
            "com.google.android.youtube.tv": "YouTube", "com.netflix.ninja": "Netflix",
            "com.amazon.amazonvideo.livingroom": "Prime Video", "com.disney.disneyplus": "Disney+",
            "com.globo.globotv": "Globoplay", "com.spotify.tv.android": "Spotify", "com.wbd.stream": "Max",
            "tv.twitch.android.app": "Twitch", "com.crunchyroll.crunchyroid": "Crunchyroll", "tv.pluto.android": "Pluto TV",
            "com.google.android.apps.tv.launcherx": "Início", "com.google.android.tvlauncher": "Início",
        ]
        return known[package]
    }

    /// App que está aberto na TV, pronto para virar botão (nil se for a tela inicial ou já estiver na lista).
    static func fromCurrent(_ package: String?, existing: [App]) -> App? {
        guard let package, !package.isEmpty, name(of: package) != "Início" else { return nil }
        let app = App(name: name(of: package) ?? package.split(separator: ".").last.map { $0.capitalized } ?? package,
                      link: "market://launch?id=\(package)")
        return existing.contains { $0.link == app.link || $0.name == app.name } ? nil : app
    }
}

extension HubDevice {
    var tvStatus: String {
        guard online else { return status["needs_pairing"]?.bool == true ? "Precisa parear de novo" : "Fora do ar" }
        guard isOn else { return "Em espera" }
        if let package = status["app"]?.string, let app = TVApps.name(of: package) { return "Ligada · \(app)" }
        return "Ligada"
    }
}

/// Cartão da TV na tela principal: liga/desliga, volume e atalho para o controle completo.
struct TVCard: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let open: () -> Void

    private var accent: Color { Theme.accent(.tv) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(device.isOn ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(device.isOn ? accent : Color.primary.opacity(0.08)))
                    .shadow(color: device.isOn ? accent.opacity(0.5) : .clear, radius: 8, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text(device.tvStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                PowerButton(on: device.isOn, tint: accent) { store.toggle(device) }
                    .disabled(!device.online)
            }
            if device.online {
                HStack(spacing: 6) {
                    RoundKey(symbol: device.status["muted"]?.bool == true ? "speaker.slash.fill" : "speaker.fill") {
                        store.tvKey(device, .mute)
                    }
                    RoundKey(symbol: "minus") { store.tvKey(device, .volumeDown) }
                    VolumeBar(device: device)
                    RoundKey(symbol: "plus") { store.tvKey(device, .volumeUp) }
                    Button(action: open) {
                        Label("Controle", systemImage: "av.remote.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(accent.opacity(0.18)))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(device.isOn ? accent.opacity(0.12) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(device.isOn ? accent.opacity(0.4) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

struct VolumeBar: View {
    let device: HubDevice

    var body: some View {
        let level = device.status["volume"]?.number ?? 0
        let maximum = max(device.status["volume_max"]?.number ?? 100, 1)
        let muted = device.status["muted"]?.bool == true
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Theme.accent(.tv).opacity(muted ? 0.3 : 0.8))
                    .frame(width: max(6, geometry.size.width * level / maximum))
            }
        }
        .frame(height: 6)
        .overlay(alignment: .center) {
            Text(muted ? "mudo" : "\(Int(level))")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .offset(y: -11)
        }
        .animation(.easeOut(duration: 0.2), value: level)
    }
}

struct RoundKey: View {
    let symbol: String
    var size: CGFloat = 30
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Controle completo: direcional, voltar, início, volume e apps. As setas e o Enter do teclado também funcionam.
struct TVRemoteView: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    @FocusState private var focused: Bool
    @Local private var apps = TVApps.load()

    private func update(_ list: [TVApps.App]) {
        apps = list
        TVApps.save(list)
    }

    var body: some View {
        VStack(spacing: 10) {
            Panel(title: "Controle") {
                VStack(spacing: 14) {
                    dpad
                    HStack(spacing: 18) {
                        labeled("Voltar", "arrow.uturn.backward") { store.tvKey(device, .back) }
                        labeled("Início", "house.fill") { store.tvKey(device, .home) }
                        labeled("Play", "playpause.fill") { store.tvKey(device, .playPause) }
                        labeled("Entrada", "rectangle.connected.to.line.below") { store.tvKey(device, .input) }
                    }
                    HStack(spacing: 8) {
                        RoundKey(symbol: device.status["muted"]?.bool == true ? "speaker.slash.fill" : "speaker.fill") {
                            store.tvKey(device, .mute)
                        }
                        RoundKey(symbol: "minus") { store.tvKey(device, .volumeDown) }
                        VolumeBar(device: device).padding(.top, 8)
                        RoundKey(symbol: "plus") { store.tvKey(device, .volumeUp) }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Panel(title: "Apps") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(apps) { app in
                        Button { store.tvLaunch(device, app.link) } label: {
                            Text(app.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(app.color))
                        }
                        .buttonStyle(PressStyle())
                        .contextMenu {
                            Button("Remover", role: .destructive) { update(apps.filter { $0 != app }) }
                        }
                    }
                }
                HStack {
                    if let current = TVApps.fromCurrent(device.status["app"]?.string, existing: apps) {
                        Button { update(apps + [current]) } label: {
                            Label("Adicionar \(current.name), aberto na TV", systemImage: "plus.circle.fill")
                        }
                    } else {
                        Text("Para adicionar, abra o app na TV. Botão direito remove.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if apps != TVApps.defaults {
                        Button("Restaurar") { update(TVApps.defaults) }
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent(.tv))
            }

            Text("Dica: com o controle aberto, as setas, Enter e Delete do teclado comandam a TV.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .delete, .escape]) { press in
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

    private var dpad: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.06)).frame(width: 150, height: 150)
            VStack(spacing: 0) {
                arrow("chevron.up", .up)
                HStack(spacing: 0) {
                    arrow("chevron.left", .left)
                    Button { store.tvKey(device, .center) } label: {
                        Text("OK")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Theme.accent(.tv)))
                            .shadow(color: Theme.accent(.tv).opacity(0.45), radius: 8, y: 2)
                    }
                    .buttonStyle(PressStyle())
                    arrow("chevron.right", .right)
                }
                arrow("chevron.down", .down)
            }
        }
    }

    private func arrow(_ symbol: String, _ key: ATVRemote.Key) -> some View {
        Button { store.tvKey(device, key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func labeled(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            RoundKey(symbol: symbol, size: 36, action: action)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// Parear e remover TVs, dentro dos Ajustes.
struct TVSettingsPanel: View {
    @EnvironmentObject private var store: HubStore
    @Local private var code = ""
    @Local private var name = ""

    var body: some View {
        Panel(title: "TV · Google TV / Android TV") {
            ForEach(store.credentials.androidTVs ?? [], id: \.host) { tv in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tv.name).font(.system(size: 12, weight: .medium))
                        Text(tv.host).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remover") { store.removeTV(host: tv.host) }.controlSize(.small)
                }
            }

            if let pairing = store.tvPairing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pareando com \(pairing.name)").font(.system(size: 12, weight: .medium))
                    if let message = pairing.message {
                        Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if pairing.waitingCode {
                        HStack {
                            TextField("Código da TV (ex.: 4F2A9C)", text: $code)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .onSubmit { store.finishTVPairing(code: code) }
                            Button("Confirmar") { store.finishTVPairing(code: code) }
                                .buttonStyle(.borderedProminent)
                                .disabled(code.trimmingCharacters(in: .whitespaces).count != 6)
                        }
                        .controlSize(.small)
                    }
                    Button("Cancelar") { store.cancelTVPairing(); code = "" }.controlSize(.small)
                }
            } else if let scan = store.tvScan {
                if scan.searching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Procurando TVs na rede…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if scan.found.isEmpty {
                    Text("Nenhuma TV nova encontrada. Ela precisa estar ligada e no mesmo Wi‑Fi.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Procurar de novo") { store.scanTVs() }.controlSize(.small)
                } else {
                    ForEach(scan.found) { tv in
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(tv.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(tv.host).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Parear") {
                                code = ""
                                store.startTVPairing(name: name.isEmpty ? tv.name : name, host: tv.host)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    TextField("Nome no Hub (opcional, ex.: TV da sala)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
            } else {
                Text("Liga, desliga, volume, direcional e apps, direto pela rede de casa. Na primeira vez a TV mostra um código.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Procurar TV") { store.scanTVs() }.controlSize(.small)
            }
        }
    }
}
