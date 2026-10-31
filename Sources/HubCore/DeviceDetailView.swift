import NeyKit
import SwiftUI

/// Tudo o que um aparelho Tuya aceita. Luz e alimentador têm controles próprios; o resto vira
/// interruptor, lista ou barra conforme o tipo do ponto de dados.
struct DeviceDetailView: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let back: () -> Void

    private var accent: Color { Theme.accent(device.kind) }
    /// Cor que o aparelho acende: a da luz, a do app aberto na TV ou a do tipo.
    private var light: Color {
        switch device.kind {
        case .light: Theme.lightFill(device).glow
        case .tv: device.tvLight(TVApps.load())
        default: accent
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
                .background(alignment: .top) {
                    if device.kind == .light, device.isOn {
                        SoftGlow(color: light, width: 420, height: 360, spread: 90)
                            .opacity(0.18).offset(y: 40)
                    }
                }
            Scroller {
                DeviceOptions(device: device)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", help: "Voltar", action: back)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(Theme.font(14, .semibold)).lineLimit(1)
                Text(device.kind == .tv ? device.tvStatus : subtitle)
                    .font(Theme.font(11)).foregroundStyle(.secondary)
            }
            Spacer()
            if device.canToggle, device.source != .smartThings {
                PowerSwitch(on: device.isOn, label: device.name) { store.toggle(device) }
            }
        }
    }

    private var subtitle: String {
        guard device.online else { return "Sem conexão" }
        if device.kind == .light, device.isOn {
            let level = device.brightness.map { " em \(Int(($0 * 100).rounded()))%" } ?? ""
            return "Acesa\(level)"
        }
        return device.room ?? source
    }

    private var source: String {
        switch device.source {
        case .androidTV: "Google TV"
        case .smartThings: "SmartThings"
        case .tuya: "Smart Life"
        }
    }

}

/// Todas as opções de um aparelho: usadas na tela de detalhes e no menu que abre ao clicar no botão.
struct DeviceOptions: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice

    private var accent: Color { Theme.accent(device.kind) }

    /// Pontos que já têm controle próprio ou que não fazem sentido mostrar.
    private var handled: Set<String> {
        var codes: Set<String> = ["factory_reset", "meal_plan", "scene_data", "scene_data_v2", "music_data",
                                  "control_data", "colour_data", "colour_data_v2", "countdown", "countdown_1"]
        if let power = device.powerCode { codes.insert(power) }
        if device.kind == .light { codes.formUnion(["bright_value", "bright_value_v2", "temp_value", "temp_value_v2", "work_mode"]) }
        if device.kind == .feeder { codes.formUnion(["manual_feed", "quick_feed"]) }
        if device.kind == .plug { codes.formUnion(["cycle_time", "random_time"]) }
        codes.formUnion(device.extraSwitches)
        return codes
    }

    var body: some View {
            VStack(spacing: 10) {
                if !device.online {
                    ErrorBanner(text: "Aparelho offline: os comandos só chegam quando ele voltar.") {}
                }
                if device.source == .smartThings, device.kind == .airConditioner {
                    ACCard(device: device, showsName: false)
                }
                if device.kind == .tv { TVRemoteView(device: device) }
                if device.kind == .light, device.brightnessSpec != nil || device.colourCode != nil { LightControls(device: device) }
                if device.kind == .feeder { FeederControls(device: device) }
                if device.kind == .feeder, device.functions["meal_plan"] != nil { MealPlanPanel(device: device) }
                if !device.extraSwitches.isEmpty { outlets }
                generic
                readings
            }
    }

    private var outlets: some View {
        Panel(title: "Saídas") {
            ForEach(device.extraSwitches, id: \.self) { code in
                ToggleRow(title: Labels.code(code, spec: device.functions[code]),
                          isOn: device.status[code]?.bool ?? false, tint: accent) { store.setTuya(device, code, $0) }
            }
        }
    }

    @ViewBuilder
    private var generic: some View {
        let specs = device.functions.values
            .filter { !handled.contains($0.code) && ($0.isBool || $0.isEnum || $0.isInteger) }
            .sorted { $0.code < $1.code }
        if !specs.isEmpty {
            Panel(title: "Ajustes") {
                ForEach(specs, id: \.code) { spec in
                    let title = device.kind == .feeder && spec.code == "switch" ? "Refeições programadas" : Labels.code(spec.code, spec: spec)
                    if spec.isBool {
                        ToggleRow(title: title, isOn: device.status[spec.code]?.bool ?? false, tint: accent) {
                            store.setTuya(device, spec.code, $0)
                        }
                    } else if spec.isEnum {
                        HStack {
                            Text(title).font(Theme.font(12))
                            Spacer()
                            Menu(Labels.value(device.status[spec.code]?.string ?? "—")) {
                                ForEach(spec.range, id: \.self) { option in
                                    Button(Labels.value(option)) { store.setTuya(device, spec.code, option) }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .frame(minHeight: 26)
                    } else {
                        SpecSlider(title: title, spec: spec, raw: device.status[spec.code]?.number ?? spec.min, tint: accent) {
                            store.setTuya(device, spec.code, Int($0))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var readings: some View {
        // Coeficientes de calibração e código de falha não interessam a ninguém.
        let hidden: Set<String> = ["electric_coe", "electricity_coe", "power_coe", "voltage_coe", "fault"]
        let codes = device.statusSpecs.keys
            .filter { device.functions[$0] == nil && device.status[$0]?.number != nil && !hidden.contains($0) }
            .sorted()
        if !codes.isEmpty {
            Panel(title: "Leituras") {
                ForEach(codes, id: \.self) { code in
                    if let reading = device.reading(code) {
                        HStack {
                            Text(Labels.code(code, spec: device.statusSpecs[code])).font(Theme.font(12))
                            Spacer()
                            Text("\(reading.value.short) \(reading.unit)")
                                .font(Theme.font(12, .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .frame(minHeight: 22)
                    }
                }
            }
        }
    }
}

// MARK: Luz

/// Duas barras altas: o brilho (o preenchimento é a própria luz) e o tom da branca ou a saturação
/// da cor. Embaixo, a luz branca e as cores.
struct LightControls: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice

    private var temperature: DPSpec? { device.functions["temp_value_v2"] ?? device.functions["temp_value"] }
    private var colourMode: Bool { device.status["work_mode"]?.string == "colour" }
    private var hasColour: Bool { device.colourCode != nil && device.functions["work_mode"]?.range.contains("colour") == true }

    private static let hues: [(name: String, hue: Double)] = [
        ("Vermelho", 0), ("Laranja", 25), ("Amarelo", 50), ("Verde", 120), ("Ciano", 180), ("Azul", 220), ("Roxo", 270), ("Rosa", 320),
    ]

    var body: some View {
        let fill = Theme.lightFill(device)
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                if device.brightnessSpec != nil || colourMode {
                    VerticalBar(label: "Brilho", value: device.isOn ? (device.brightness ?? 1) : 0, style: .light(fill.low, fill.high)) {
                        setBrightness($0)
                    }
                    .frame(minWidth: 110, maxWidth: 150)
                }
                if colourMode, let hsv = device.colour {
                    VerticalBar(label: "Saturação", value: hsv.s,
                                style: .knob([Color(hue: hsv.h / 360, saturation: 1, brightness: 1), .white])) {
                        setColour(hue: hsv.h, saturation: $0)
                    }
                    .frame(minWidth: 60, maxWidth: 72)
                } else if let temperature {
                    let raw = device.status[temperature.code]?.number ?? temperature.min
                    VerticalBar(label: "Tom", value: (raw - temperature.min) / max(temperature.max - temperature.min, 1),
                                style: .knob([Color(red: 0.84, green: 0.91, blue: 1), Color(red: 1, green: 0.95, blue: 0.88), Color(red: 1, green: 0.71, blue: 0.36)]),
                                top: "fria", bottom: "quente") {
                        store.setTuya(device, temperature.code, Int((temperature.min + $0 * (temperature.max - temperature.min)).rounded()))
                    }
                    .frame(minWidth: 60, maxWidth: 72)
                }
            }
            .frame(height: 340)
            .frame(maxWidth: .infinity)

            if hasColour {
                // Numa linha no popover; no detalhe estreito da tela do Hub, em duas.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        white
                        hues(Self.hues)
                    }
                    VStack(spacing: 8) {
                        HStack { white; hues(Array(Self.hues.prefix(4))) }
                        HStack { hues(Array(Self.hues.dropFirst(4))) }
                    }
                }
                .padding(.horizontal, 4)
            }
            Text("Arraste as barras. Clicar na luz da tela inicial acende e apaga.")
                .font(Theme.font(11)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var white: some View {
        swatch("Branca", fill: AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.88), Color(red: 1, green: 0.71, blue: 0.36)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)),
               ring: Color(red: 1, green: 0.77, blue: 0.4), selected: !colourMode) {
            var commands: [(code: String, value: Any)] = [("work_mode", "white")]
            if let power = device.powerCode, !device.isOn { commands.insert((power, true), at: 0) }
            store.setTuya(device, commands)
        }
    }

    @ViewBuilder private func hues(_ items: [(name: String, hue: Double)]) -> some View {
        ForEach(items, id: \.hue) { item in
            Spacer(minLength: 0)
            let color = Color(hue: item.hue / 360, saturation: 0.85, brightness: 1)
            let selected = colourMode && device.colour.map { abs($0.h - item.hue) < 12 } == true
            swatch(item.name, fill: AnyShapeStyle(color), ring: color, selected: selected) {
                setColour(hue: item.hue, saturation: 1)
            }
        }
    }

    private func swatch(_ name: String, fill: AnyShapeStyle, ring: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(fill)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? ring : .clear, lineWidth: 2))
                .shadow(color: selected ? ring.opacity(0.6) : .clear, radius: 8)
        }
        .buttonStyle(PressStyle())
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setBrightness(_ fraction: Double) {
        guard let power = device.powerCode else { return }
        if fraction < 0.03 { return store.setTuya(device, power, false) }
        if colourMode, let hsv = device.colour { return setColour(hue: hsv.h, saturation: hsv.s, value: fraction) }
        guard let spec = device.brightnessSpec else { return }
        let raw = ((spec.min + fraction * (spec.max - spec.min)) / spec.step).rounded() * spec.step
        var commands: [(code: String, value: Any)] = [(spec.code, Int(min(max(raw, spec.min), spec.max)))]
        if !device.isOn { commands.insert((power, true), at: 0) }
        store.setTuya(device, commands)
    }

    private func setColour(hue: Double, saturation: Double, value: Double? = nil) {
        guard let code = device.colourCode else { return }
        let top = code == "colour_data_v2" ? 1000.0 : 255.0
        let value = max(value ?? device.brightness ?? 1, 0.1)
        let data = "{\"h\":\(Int(hue)),\"s\":\(Int(saturation * top)),\"v\":\(Int(value * top))}"
        var commands: [(code: String, value: Any)] = [("work_mode", "colour"), (code, data)]
        if let power = device.powerCode, !device.isOn { commands.insert((power, true), at: 0) }
        store.setTuya(device, commands)
    }
}

/// Barra vertical: arrastar ou clicar escolhe o valor (0 embaixo, 1 em cima). Só manda o comando
/// ao soltar e segura o valor até a nuvem confirmar.
struct VerticalBar: View {
    enum Style {
        /// Preenchimento de luz com o fio aceso no topo e o número por cima.
        case light(Color, Color)
        /// Faixa de cor com um botão branco.
        case knob([Color])
    }

    let label: String
    let value: Double
    let style: Style
    var top: String?
    var bottom: String?
    let commit: (Double) -> Void

    @ViewState private var dragging: Double? = nil
    @ViewState private var held: Double? = nil

    var body: some View {
        let fraction = dragging ?? held ?? value
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .bottom) {
                switch style {
                case .light(let low, let high):
                    Rectangle().fill(Theme.matte)
                    VStack(spacing: 0) {
                        Rectangle().fill(.white).frame(height: fraction > 0 ? 3 : 0).shadow(color: high, radius: 9)
                        LinearGradient(colors: [high, low], startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: height * fraction + (fraction > 0 ? 3 : 0))
                    VStack(spacing: 2) {
                        Text("\(Int((fraction * 100).rounded()))")
                            .font(Theme.number(44, .regular))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(label.lowercased()).font(Theme.font(12, .semibold))
                    }
                    .foregroundStyle(fraction > 0.3 ? Color(red: 0.18, green: 0.11, blue: 0) : Color.primary)
                    .padding(.bottom, 20)
                case .knob(let colors):
                    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    VStack {
                        if let top { Text(top) }
                        Spacer()
                        if let bottom { Text(bottom) }
                    }
                    .font(Theme.font(10.5, .bold))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .padding(.vertical, 12)
                    Capsule().fill(.white)
                        .frame(height: 46)
                        .padding(.horizontal, 12)
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                        .offset(y: -(height - 58) * fraction - 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in dragging = min(max(1 - drag.location.y / height, 0), 1) }
                .onEnded { _ in
                    guard let dragging else { return }
                    commit(dragging)
                    held = dragging
                    self.dragging = nil
                    Task { try? await Task.sleep(for: .seconds(4)); held = nil }
                })
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((fraction * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in commit(min(max(fraction + (direction == .increment ? 0.1 : -0.1), 0), 1)) }
    }
}

// MARK: Alimentador

struct FeederControls: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    @ViewState private var portions = 1

    private var spec: DPSpec? { device.functions["manual_feed"] }
    private var feeding: Bool { device.status["feed_state"]?.string == "feeding" }

    var body: some View {
        Panel(title: "Ração") {
            if let spec {
                HStack(spacing: 14) {
                    StepperButton(symbol: "minus") { portions = max(Int(max(spec.min, 1)), portions - 1) }
                    VStack(spacing: 0) {
                        Text("\(portions)")
                            .font(Theme.number(34, .medium))
                            .contentTransition(.numericText(value: Double(portions)))
                        Text(portions == 1 ? "porção" : "porções").font(Theme.font(11)).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 70)
                    StepperButton(symbol: "plus") { portions = min(Int(spec.max > 0 ? spec.max : 12), portions + 1) }
                }
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: portions)

                Button {
                    store.setTuya(device, "manual_feed", portions)
                } label: {
                    HStack {
                        Icon(feeding ? "hourglass" : "feeder.bowl")
                        Text(feeding ? "Servindo…" : "Servir agora")
                    }
                    .font(Theme.font(13, .bold))
                    .foregroundStyle(Color(red: 0.23, green: 0.03, blue: 0.07))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent(.feeder)))
                }
                .buttonStyle(PressStyle())
                .disabled(!device.online || feeding)
            } else if device.functions["quick_feed"] != nil {
                GPill(title: "Servir agora") { store.setTuya(device, "quick_feed", true) }
            }
            if let last = device.status["feed_report"]?.number, last > 0 {
                Text("Última refeição: \(Int(last)) \(last == 1 ? "porção" : "porções")")
                    .font(Theme.font(11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(symbol, size: 13)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Peças

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.font(12, .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct ToggleRow: View {
    let title: String
    let isOn: Bool
    var tint: Color = Grafite.accent
    let set: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(Theme.font(12))
            Spacer()
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(tint)
        }
        .frame(minHeight: 26)
    }
}

/// Barra grossa estilo Central de Controle. Só manda o comando ao soltar, para não disparar
/// dezenas de requisições enquanto arrasta.
struct SpecSlider: View {
    let title: String
    let spec: DPSpec
    let raw: Double
    var tint: Color = Grafite.accent
    let commit: (Double) -> Void

    @ViewState private var dragging: Double? = nil
    @ViewState private var held: Double? = nil

    private var span: Double { max(spec.max - spec.min, 1) }

    var body: some View {
        let fraction = dragging ?? held ?? min(max((raw - spec.min) / span, 0), 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint.opacity(0.85))
                    .frame(width: max(30, geometry.size.width * fraction))
                HStack(spacing: 6) {
                    Text(title).font(Theme.font(12, .medium))
                    Spacer()
                    Text(label(spec.min + fraction * span))
                        .font(Theme.font(11.5, .semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 11)
                .foregroundStyle(Color.primary)
                .allowsHitTesting(false)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragging = min(max(value.location.x / geometry.size.width, 0), 1) }
                    .onEnded { _ in
                        guard let dragging else { return }
                        let raw = ((spec.min + dragging * span) / spec.step).rounded() * spec.step
                        commit(min(max(raw, spec.min), spec.max))
                        held = dragging
                        self.dragging = nil
                        // Segura o valor até a nuvem confirmar, para a barra não pular de volta.
                        Task { try? await Task.sleep(for: .seconds(4)); held = nil }
                    }
            )
        }
        .frame(height: 30)
    }

    private func label(_ raw: Double) -> String {
        return "\(spec.scaled(raw).short)\(spec.unit.isEmpty ? "" : " \(spec.unit)")"
    }
}

