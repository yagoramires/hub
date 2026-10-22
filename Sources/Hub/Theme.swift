import SwiftUI

enum Theme {
    static let corner: CGFloat = 16

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
        case .feeder: "pawprint.fill"
        case .remote: device.category == "infrared_tv" ? "tv.fill" : "av.remote.fill"
        case .other: "switch.2"
        }
    }

    /// Gradiente do cartão do ar conforme o modo.
    static func acGradient(mode: String?) -> [Color] {
        switch mode {
        case "heat": [Color(red: 1.00, green: 0.55, blue: 0.25), Color(red: 0.90, green: 0.25, blue: 0.30)]
        case "dry": [Color(red: 0.20, green: 0.78, blue: 0.75), Color(red: 0.10, green: 0.55, blue: 0.62)]
        case "wind", "fanOnly", "fan": [Color(red: 0.50, green: 0.58, blue: 0.98), Color(red: 0.36, green: 0.40, blue: 0.85)]
        case "auto", "aIComfort": [Color(red: 0.62, green: 0.45, blue: 1.00), Color(red: 0.30, green: 0.48, blue: 0.98)]
        default: [Color(red: 0.25, green: 0.75, blue: 1.00), Color(red: 0.16, green: 0.42, blue: 0.95)]
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

/// Botão redondo pequeno com ícone, usado nos cabeçalhos.
struct IconButton: View {
    let symbol: String
    var help = ""
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Pílula selecionável (modos do ar, modos da luz…).
struct Chip: View {
    let title: String
    var symbol: String?
    let selected: Bool
    var tint: Color = .accentColor
    var onDark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
                if !title.isEmpty { Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)) }
            }
            .padding(.horizontal, title.isEmpty ? 0 : 9)
            .frame(minWidth: 30)
            .frame(height: 24)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if onDark { return selected ? .black.opacity(0.8) : .white.opacity(0.9) }
        return selected ? .white : .primary
    }

    private var background: Color {
        if onDark { return selected ? .white.opacity(0.92) : .white.opacity(0.16) }
        return selected ? tint : Color.primary.opacity(0.07)
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
                .frame(maxHeight: 560)
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
