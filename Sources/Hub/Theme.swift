import SwiftUI

enum Theme {
    static let tileCorner: CGFloat = 24

    /// Fundo do popover: um quarto escuro à noite, onde cada aparelho ligado acende a própria luz.
    static let room = Color(light: 0xF1F1F4, dark: 0x19191C)
    /// Aparelho desligado: objeto fosco, sem brilho.
    static let matte = Color(light: 0xFFFFFF, dark: 0x232327)
    static let well = Color.primary.opacity(0.06)

    /// Fonte do Hub: Outfit (variável, embutida em Resources/Fonts) em tudo, textos e números.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let value: CGFloat = switch weight {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
        let key = "\(size)-\(value)"
        if let cached = fonts[key] { return cached }
        // Eixo de peso da fonte variável pela etiqueta OpenType 'wght'.
        let variation = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = NSFontDescriptor(fontAttributes: [.family: "Outfit", variation: [0x7767_6874: value]])
        let font = NSFont(descriptor: descriptor, size: size).flatMap { $0.familyName == "Outfit" ? Font($0) : nil }
            ?? .system(size: size, weight: weight)
        fonts[key] = font
        return font
    }

    /// Fontes já montadas: cada texto pedia uma NSFont nova a cada desenho.
    private static var fonts: [String: Font] = [:]

    /// Números grandes: a mesma Outfit, com algarismos de largura fixa onde for preciso (monospacedDigit).
    static func number(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { font(size, weight) }

    /// Registra as fontes de Resources/Fonts (Archivo e os ícones Lucide) só para este app.
    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
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
        case .tv: Color(red: 0.96, green: 0.36, blue: 0.40)
        case .light: Color(red: 1.00, green: 0.71, blue: 0.20)
        case .plug: Color(red: 0.25, green: 0.82, blue: 0.55)
        case .feeder: Color(red: 1.00, green: 0.45, blue: 0.53)
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
        } else if let code = Self.lucide[name], let scalar = UnicodeScalar(code) {
            Text(String(Character(scalar)))
                .font(.custom("lucide", size: size))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: name).font(.system(size: size * 0.85, weight: .medium))
        }
    }

    /// Códigos da lucide-static 0.460.0 (font/info.json).
    private static let lucide: [String: UInt32] = [
        "arrow.clockwise": 0xe149, "arrow.uturn.backward": 0xe2a1, "av.remote.fill": 0xe5f1, "checkmark.circle.fill": 0xe226,
        "chevron.down": 0xe071, "chevron.left": 0xe072, "chevron.right": 0xe073, "chevron.up": 0xe074, "delete.left": 0xe0b2,
        "ellipsis.circle": 0xe0ba, "exclamationmark.triangle.fill": 0xe193, "fan.fill": 0xe37d, "gearshape": 0xe158,
        "gearshape.fill": 0xe245, "hand.draw": 0xe1e8, "house.fill": 0xe0f8, "house.lodge.fill": 0xe0f8, "magnifyingglass": 0xe155,
        "minus": 0xe120, "plus": 0xe141, "playpause.fill": 0xe140, "plus.circle.fill": 0xe086, "power": 0xe144,
        "rectangle.connected.to.line.below": 0xe111, "tv.fill": 0xe195, "xmark": 0xe1b2, "xmark.circle.fill": 0xe088,
        "air.conditioner.horizontal.fill": 0xe351, "light.strip.2.fill": 0xe1c2, "light.recessed.fill": 0xe2d9,
        "lightbulb.fill": 0xe1c2, "poweroutlet.strip.fill": 0xe383, "powerplug.fill": 0xe383,
        "switch.2": 0xe144, "sun.max.fill": 0xe17c, "drop.fill": 0xe0b8, "wind": 0xe1b0, "snowflake": 0xe169,
        "a.circle.fill": 0xe376, "sparkles": 0xe417, "speaker.wave.2.fill": 0xe1ab, "speaker.slash.fill": 0xe1ac,
        "wifi.slash": 0xe1af, "hourglass": 0xe296,
    ]
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

/// Botão redondo pequeno com ícone, usado nos cabeçalhos.
struct IconButton: View {
    let symbol: String
    var help = ""
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(symbol, size: 13)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}


extension Double {
    /// 12.5 → "12,5"; 23.0 → "23".
    var short: String {
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
    /// Luz que o aparelho ligado espalha pelo fundo, por trás do cartão.
    func glow(_ color: Color, on: Bool = true, radius: CGFloat = 34, opacity: Double = 0.45) -> some View {
        background {
            if on {
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .fill(color)
                    .blur(radius: radius)
                    .opacity(opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Cartão fosco do Hub, com o fio de luz em cima e a borda na cor do aparelho quando ligado.
    func card(_ fill: Color = Theme.matte, edge: Color? = nil, corner: CGFloat = Theme.tileCorner) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return background(shape.fill(fill))
            .overlay(shape.strokeBorder(edge ?? Color.primary.opacity(0.07), lineWidth: 1))
            .clipShape(shape)
    }
}

/// O SDK do macOS 27 transformou `@State` em macro, e o plugin dela só vem com o Xcode. Pelo
/// typealias o compilador usa o property wrapper de sempre, que funciona só com as Command Line Tools.
typealias Local<Value> = SwiftUI.State<Value>

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
            ScrollView { content }
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
