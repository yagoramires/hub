import NeyKit
import SwiftUI

enum Theme {
    static let tileCorner = Grafite.cardRadius

    /// Fundo e cartões do Grafite do NeyHub; o aparelho ligado acende em halo (`glow`).
    static let room = Grafite.bg
    static let matte = Grafite.card
    static let well = Color.white.opacity(0.06)

    /// Fonte do sistema, como o resto do NeyHub.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    /// Números grandes (monospacedDigit onde for preciso).
    static func number(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { font(size, weight) }

    /// Pasta com `Fonts/` (ícones Lucide) e `AppLogos/`: a do .app no avulso, `<Hub>.neyplugin/Resources` no NeyHub. nil = nada empacotado.
    private(set) static var resources: URL?
    /// Lucide registrada: sem ela os ícones caem no SF Symbol (o código da Lucide sairia como um quadrado vazio).
    private(set) static var hasLucide = false

    /// Registra as fontes de `<resources>/Fonts` (os ícones Lucide) só para este processo. Sem pasta ou sem
    /// fonte: SF Symbols e o nome no lugar do logo dos apps da TV, e fica no registro.
    static func registerFonts(from resources: URL?) {
        self.resources = resources
        let urls = resources.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0.appendingPathComponent("Fonts"), includingPropertiesForKeys: nil)
        }?.filter { $0.pathExtension == "ttf" } ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        hasLucide = urls.contains { $0.lastPathComponent == "lucide.ttf" }
        if !hasLucide {
            debugLog("recursos: fontes ausentes em \(resources?.path ?? "nenhuma pasta"); usando ícones genéricos")
        }
    }

    /// A Lucide registrada desenha esse código (código errado sairia como quadrado vazio).
    static func lucideHasGlyph(_ code: UInt32) -> Bool {
        guard let font = NSFont(name: "lucide", size: 12), let scalar = UnicodeScalar(code) else { return false }
        var chars = Array(String(Character(scalar)).utf16), glyphs = [CGGlyph](repeating: 0, count: chars.count)
        return CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count) && glyphs[0] != 0
    }

    /// Ícone da barra de menus: `house-wifi` da Lucide em template 18×18; sem a fonte, a casa do SF Symbol.
    static func menuBarImage(anyOn: Bool) -> NSImage {
        if hasLucide, let font = NSFont(name: "lucide", size: 16), let code = Icon.lucideCodes["house.wifi"], let scalar = UnicodeScalar(code) {
            let text = NSAttributedString(string: String(Character(scalar)), attributes: [.font: font, .foregroundColor: NSColor.black])
            let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let size = text.size()
                text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
                return true
            }
            image.isTemplate = true
            return image
        }
        let image = NSImage(systemSymbolName: anyOn ? "house.fill" : "house", accessibilityDescription: "Domo") ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    /// Cores do topo e da base da luz acesa: branca (do quente ao frio, pelo tom) ou a cor escolhida.
    static func lightFill(_ device: HubDevice) -> (low: Color, high: Color, glow: Color) {
        if device.status["work_mode"]?.string == "colour", let hsv = device.colour {
            let hue = hsv.h / 360, saturation = max(hsv.s, 0.25)
            return (Color(hue: hue, saturation: saturation, brightness: 0.92),
                    Color(hue: hue, saturation: saturation * 0.5, brightness: 1),
                    Color(hue: hue, saturation: saturation, brightness: 1))
        }
        let spec = device.functions["temp_value_v2"] ?? device.functions["temp_value"]
        let cool = spec.flatMap { spec in device.status[spec.code]?.number.map { ($0 - spec.min) / max(spec.max - spec.min, 1) } } ?? 0
        let warm = (low: (1.0, 0.68, 0.24), high: (1.0, 0.84, 0.6))
        let cold = (low: (0.78, 0.87, 1.0), high: (0.94, 0.97, 1.0))
        func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Color {
            Color(red: a.0 + (b.0 - a.0) * cool, green: a.1 + (b.1 - a.1) * cool, blue: a.2 + (b.2 - a.2) * cool)
        }
        return (mix(warm.low, cold.low), mix(warm.high, cold.high), mix(warm.low, cold.low))
    }

    static func accent(_ kind: HubDevice.Kind) -> Color {
        switch kind {
        case .airConditioner: Color(red: 0.25, green: 0.70, blue: 1.00)
        case .tv: Grafite.accent
        case .light: Color(red: 1.00, green: 0.71, blue: 0.20)
        case .plug: Color(red: 0.25, green: 0.82, blue: 0.55)
        case .feeder: Grafite.accent
        case .remote: Color(red: 0.58, green: 0.50, blue: 1.00)
        case .other: Color(red: 0.45, green: 0.62, blue: 1.00)
        }
    }

    static func symbol(_ device: HubDevice) -> String {
        switch device.kind {
        case .airConditioner: "air.conditioner.horizontal.fill"
        case .tv: "tv.fill"
        case .light: device.category == "dd" || device.name.lowercased().contains("led") ? "light.strip.2.fill"
            : device.category == "cz" ? "light.recessed.fill" : "lightbulb.fill"
        case .plug: device.category == "pc" ? "poweroutlet.strip.fill" : "powerplug.fill"
        case .feeder: "feeder.bowl"
        case .remote: device.category == "infrared_tv" ? "tv.fill" : "av.remote.fill"
        case .other: "switch.2"
        }
    }

}

/// Nomes amigáveis para códigos que se repetem entre aparelhos.
enum Labels {
    static func code(_ code: String, spec: DPSpec?) -> String {
        if let known = codes[code] { return known }
        if code.hasPrefix("switch_"), let n = Int(code.dropFirst(7)) { return "Saída \(n)" }
        if code.hasPrefix("countdown_") { return "Timer" }
        if let name = spec?.name, !name.isEmpty, name != code { return name }
        return code.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func value(_ value: String) -> String { values[value] ?? value.capitalized }

    private static let codes: [String: String] = [
        "switch_led": "Ligada", "switch": "Ligado", "switch_1": "Ligada", "power": "Ligado",
        "bright_value": "Brilho", "bright_value_v2": "Brilho", "temp_value": "Tom", "temp_value_v2": "Tom",
        "work_mode": "Modo", "colour_data": "Cor", "colour_data_v2": "Cor", "scene_data_v2": "Cena",
        "countdown": "Timer", "relay_status": "Ao voltar a energia", "light_mode": "Luz indicadora",
        "child_lock": "Trava infantil", "switch_backlight": "Luz indicadora", "light": "Luz",
        "manual_feed": "Porções", "quick_feed": "Servir agora", "feed_state": "Estado",
        "feed_report": "Última refeição", "slow_feed": "Servir devagar", "voice_times": "Chamar pelo som",
        "battery_percentage": "Bateria", "charge_state": "Carregando", "factory_reset": "Restaurar",
        "cur_power": "Potência", "cur_voltage": "Tensão", "cur_current": "Corrente", "add_ele": "Consumo",
        "do_not_disturb": "Não perturbe", "overcharge_switch": "Proteção de sobrecarga", "music_data": "Música",
    ]

    private static let values: [String: String] = [
        "white": "Branca", "colour": "Colorida", "scene": "Cena", "music": "Música",
        "power_off": "Desligada", "power_on": "Ligada", "off": "Desligada", "on": "Ligada",
        "last": "Como estava", "memory": "Como estava", "none": "Nenhuma", "relay": "Com o relé", "pos": "Invertida",
        "standby": "Pronto", "feeding": "Servindo", "done": "Servido",
        // Ar-condicionado
        "cool": "Frio", "auto": "Auto", "dry": "Seco", "wind": "Ventilar", "fanOnly": "Ventilar", "fan": "Ventilar",
        "heat": "Quente", "aIComfort": "IA", "low": "Baixo", "medium": "Médio", "high": "Alto", "turbo": "Turbo",
        "windFree": "WindFree", "sleep": "Dormir", "speed": "Rápido", "quiet": "Silencioso", "windFreeSleep": "WF Dormir",
        "longWind": "Longo alcance", "smart": "Smart",
    ]

    static func acModeSymbol(_ mode: String) -> String {
        switch mode {
        case "cool": "snowflake"
        case "heat": "sun.max.fill"
        case "dry": "drop.fill"
        case "wind", "fanOnly", "fan": "wind"
        case "auto": "a.circle.fill"
        default: "sparkles"
        }
    }
}

/// Ícone Lucide (traço fino), pela fonte embutida. Recebe o nome do SF Symbol equivalente; sem
/// equivalente na Lucide, cai no SF Symbol.
struct Icon: View {
    let name: String
    var size: CGFloat

    init(_ name: String, size: CGFloat = 15) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if name == "feeder.bowl" {
            FoodBowl()
                .stroke(style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else if Theme.hasLucide, let code = Self.lucideCodes[name], let scalar = UnicodeScalar(code) {
            Text(String(Character(scalar)))
                .font(.custom("lucide", size: size))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: name).font(.system(size: size * 0.85, weight: .medium))
        }
    }

    /// Códigos da lucide-static 1.65.0 (font/info.json), pela chave do SF Symbol equivalente.
    static let lucideCodes: [String: UInt32] = [
        "arrow.clockwise": 0xe145, "arrow.uturn.backward": 0xe2a1, "av.remote.fill": 0xe5ec,
        "checkmark.circle.fill": 0xe226, "chevron.down": 0xe06d, "chevron.left": 0xe06e, "chevron.right": 0xe06f,
        "chevron.up": 0xe070, "delete.left": 0xe0ae, "ellipsis.circle": 0xe0b6, "exclamationmark.triangle.fill": 0xe193,
        "fan.fill": 0xe379, "gearshape": 0xe154, "gearshape.fill": 0xe245, "hand.draw": 0xe1e8, "house.fill": 0xe0f5,
        "house.lodge.fill": 0xe0f5, "magnifyingglass": 0xe151, "minus": 0xe11c, "plus": 0xe13d, "playpause.fill": 0xe13c,
        "plus.circle.fill": 0xe081, "power": 0xe140, "rectangle.connected.to.line.below": 0xe10d, "tv.fill": 0xe195,
        "xmark": 0xe1b2, "xmark.circle.fill": 0xe084, "air.conditioner.horizontal.fill": 0xe34d,
        "light.strip.2.fill": 0xe1c2, "light.recessed.fill": 0xe2d9, "lightbulb.fill": 0xe1c2,
        "poweroutlet.strip.fill": 0xe37f, "powerplug.fill": 0xe37f, "switch.2": 0xe140, "sun.max.fill": 0xe178,
        "drop.fill": 0xe0b4, "wind": 0xe1b0, "snowflake": 0xe165, "a.circle.fill": 0xe372, "sparkles": 0xe412,
        "speaker.wave.2.fill": 0xe1ab, "speaker.slash.fill": 0xe1ac, "wifi.slash": 0xe1af, "hourglass": 0xe296,
        "house.wifi": 0xe63c, "mic": 0xe118, "line.3.horizontal": 0xe115, "info.circle": 0xe0f9, "captions.bubble": 0xe3a4,
        "backward.end.fill": 0xe15f, "forward.end.fill": 0xe160, "backward.fill": 0xe147, "forward.fill": 0xe0bd,
        "play.fill": 0xe13c, "pause.fill": 0xe12e, "play.rectangle": 0xe485,
    ]
}

/// Luz suave em elipse: o que antes era uma elipse com `.blur(radius: spread)`, feito com gradiente radial (o `--render`
/// não desenha blur, e assim a tela e o PNG ficam iguais). Cheia no centro e some `spread` além da borda.
struct SoftGlow: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat
    var spread: CGFloat = 0

    var body: some View {
        let w = width + spread * 2, h = height + spread * 2
        Ellipse()
            .fill(RadialGradient(stops: [.init(color: color, location: 0), .init(color: color, location: 0.25),
                                         .init(color: color.opacity(0), location: 1)],
                                 center: .center, startRadius: 0, endRadius: w / 2))
            .frame(width: w, height: w)
            .scaleEffect(x: 1, y: h / w)
            .frame(width: w, height: h)
            .allowsHitTesting(false)
    }
}

/// Pote de ração com grãos, no traço da Lucide (grade de 24, linha de 2). A Lucide não tem um.
struct FoodBowl: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(2.5, 12.5))
        path.addLine(to: p(21.5, 12.5))
        path.addQuadCurve(to: p(16.5, 20), control: p(21, 19))
        path.addLine(to: p(7.5, 20))
        path.addQuadCurve(to: p(2.5, 12.5), control: p(3, 19))
        path.closeSubpath()
        for (x, y) in [(8.0, 9.2), (12.0, 7.4), (16.0, 9.2)] {
            path.addEllipse(in: CGRect(origin: p(x - 1.7, y - 1.7), size: CGSize(width: 3.4 * k, height: 3.4 * k)))
        }
        return path
    }
}

/// Botão quadrado pequeno com borda e ícone, usado nos cabeçalhos.
struct IconButton: View {
    let symbol: String
    var help = ""
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(symbol, size: 13)
                .foregroundStyle(Grafite.ghostText)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Grafite.ghostBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}


extension Double {
    /// 12.5 → "12,5"; 23.0 → "23".
    package var short: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
}

extension View {
    /// Halo do aparelho ligado: o cartão acende por dentro (canto de cima), a borda pega a cor e a luz vaza por trás.
    /// `radius`/`opacity` ficaram dos chamadores antigos; a intensidade é a mesma em todo aparelho (aprovada no mockup).
    func glow(_ color: Color, on: Bool = true, radius: CGFloat = 0, opacity: Double = 0) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
        return overlay {
            if on {
                ZStack {
                    shape.fill(RadialGradient(colors: [color.opacity(0.13), color.opacity(0)], center: .topLeading,
                                              startRadius: 0, endRadius: 240)).blendMode(.plusLighter)
                    shape.strokeBorder(color.opacity(0.30), lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
        }
        .background {
            if on { shape.fill(Theme.matte).shadow(color: color.opacity(0.38), radius: 14, y: 8).allowsHitTesting(false) }
        }
    }

    /// Cartão grafite do NeyKit, com a borda na cor do aparelho quando pedida.
    func card(_ fill: Color = Theme.matte, edge: Color? = nil, corner: CGFloat = Theme.tileCorner) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return background(shape.fill(fill))
            .overlay(shape.strokeBorder(edge ?? Grafite.cardBorder, lineWidth: 1))
            .clipShape(shape)
    }
}

/// Rolagem que vira pilha simples no `Hub --render` (o ImageRenderer não desenha ScrollView).
struct Scroller<Content: View>: View {
    var axis: Axis.Set = .vertical
    @ViewBuilder let content: Content
    @Environment(\.hubSnapshot) private var snapshot

    var body: some View {
        if snapshot {
            content
        } else if axis == .horizontal {
            ScrollView(.horizontal, showsIndicators: false) { content }
        } else {
            ScrollView(showsIndicators: false) { content }
                .frame(maxHeight: 640)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hubSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}
