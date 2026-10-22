import SwiftUI

/// Tudo o que um aparelho Tuya aceita. Luz e alimentador têm controles próprios; o resto vira
/// interruptor, lista ou barra conforme o tipo do ponto de dados.
struct DeviceDetailView: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let back: () -> Void

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
        VStack(spacing: 0) {
            header.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
            Scroller {
                VStack(spacing: 10) {
                    if !device.online {
                        ErrorBanner(text: "Aparelho offline: os comandos só chegam quando ele voltar.") {}
                    }
                    if device.source == .smartThings, device.kind == .airConditioner {
                        ACCard(device: device)
                    }
                    if device.kind == .tv { TVRemoteView(device: device) }
                    if device.kind == .light { LightControls(device: device) }
                    if device.kind == .feeder { FeederControls(device: device) }
                    if device.kind == .feeder, device.functions["meal_plan"] != nil { MealPlanPanel(device: device) }
                    if !device.extraSwitches.isEmpty { outlets }
                    generic
                    readings
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", help: "Voltar", action: back)
            Image(systemName: Theme.symbol(device))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(device.isOn ? .white : accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(device.isOn ? accent : accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                Text([device.room, device.online ? nil : "Offline"].compactMap { $0 }.joined(separator: " · ").ifEmpty(source))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if device.canToggle, device.source != .smartThings {
                PowerButton(on: device.isOn, tint: accent) { store.toggle(device) }
            }
        }
    }

    private var source: String {
        switch device.source {
        case .androidTV: "Google TV"
        case .smartThings: "SmartThings"
        case .tuya: "Smart Life"
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
                            Text(title).font(.system(size: 12))
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
                            Text(Labels.code(code, spec: device.statusSpecs[code])).font(.system(size: 12))
                            Spacer()
                            Text("\(reading.value.short) \(reading.unit)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
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

struct LightControls: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice

    private var brightness: DPSpec? { device.functions["bright_value_v2"] ?? device.functions["bright_value"] }
    private var temperature: DPSpec? { device.functions["temp_value_v2"] ?? device.functions["temp_value"] }
    private var colour: String? { ["colour_data_v2", "colour_data"].first { device.functions[$0] != nil } }
    private var mode: String? { device.status["work_mode"]?.string }

    private static let hues: [Double] = [0, 25, 50, 120, 175, 210, 265, 310]

    var body: some View {
        Panel(title: "Luz") {
            if device.functions["work_mode"]?.range.contains("colour") == true {
                HStack(spacing: 6) {
                    Chip(title: "Branca", symbol: "sun.max.fill", selected: mode == "white", tint: Theme.accent(.light)) {
                        store.setTuya(device, "work_mode", "white")
                    }
                    Chip(title: "Colorida", symbol: "paintpalette.fill", selected: mode == "colour", tint: Theme.accent(.light)) {
                        store.setTuya(device, "work_mode", "colour")
                    }
                    Spacer()
                }
            }
            if let brightness {
                SpecSlider(title: "Brilho", spec: brightness, raw: device.status[brightness.code]?.number ?? brightness.max,
                           tint: Theme.accent(.light), percent: true, symbol: "sun.min.fill") {
                    var commands: [(code: String, value: Any)] = [(brightness.code, Int($0))]
                    if let power = device.powerCode, !device.isOn { commands.insert((power, true), at: 0) }
                    store.setTuya(device, commands)
                }
            }
            if let temperature, mode != "colour" {
                SpecSlider(title: "Tom", spec: temperature, raw: device.status[temperature.code]?.number ?? temperature.min,
                           tint: Theme.accent(.light), percent: true, symbol: "thermometer.medium",
                           track: [Color(red: 1, green: 0.72, blue: 0.4), Color(red: 1, green: 0.95, blue: 0.88), Color(red: 0.75, green: 0.87, blue: 1)]) {
                    store.setTuya(device, temperature.code, Int($0))
                }
            }
            if let colour {
                HStack(spacing: 8) {
                    ForEach(Self.hues, id: \.self) { hue in
                        Button {
                            let value = Int(brightness.flatMap { device.status[$0.code]?.number } ?? 1000)
                            let data = "{\"h\":\(Int(hue)),\"s\":1000,\"v\":\(max(value, 100))}"
                            var commands: [(code: String, value: Any)] = [("work_mode", "colour"), (colour, data)]
                            if let power = device.powerCode, !device.isOn { commands.insert((power, true), at: 0) }
                            store.setTuya(device, commands)
                        } label: {
                            Circle()
                                .fill(Color(hue: hue / 360, saturation: 0.85, brightness: 1))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                                .shadow(color: Color(hue: hue / 360, saturation: 0.85, brightness: 1).opacity(0.5), radius: 4)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: Alimentador

struct FeederControls: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    @Local private var portions = 1

    private var spec: DPSpec? { device.functions["manual_feed"] }
    private var feeding: Bool { device.status["feed_state"]?.string == "feeding" }

    var body: some View {
        Panel(title: "Ração") {
            if let spec {
                HStack(spacing: 14) {
                    StepperButton(symbol: "minus") { portions = max(Int(max(spec.min, 1)), portions - 1) }
                    VStack(spacing: 0) {
                        Text("\(portions)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText(value: Double(portions)))
                        Text(portions == 1 ? "porção" : "porções").font(.system(size: 11)).foregroundStyle(.secondary)
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
                        Image(systemName: feeding ? "hourglass" : "pawprint.fill")
                        Text(feeding ? "Servindo…" : "Servir agora")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent(.feeder)))
                }
                .buttonStyle(PressStyle())
                .disabled(!device.online || feeding)
            } else if device.functions["quick_feed"] != nil {
                Button("Servir agora") { store.setTuya(device, "quick_feed", true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent(.feeder))
            }
            if let last = device.status["feed_report"]?.number, last > 0 {
                Text("Última refeição: \(Int(last)) \(last == 1 ? "porção" : "porções")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
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
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
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
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

struct ToggleRow: View {
    let title: String
    let isOn: Bool
    var tint: Color = .accentColor
    let set: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
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
    var tint: Color = .accentColor
    var percent = false
    var symbol: String?
    var track: [Color]?
    let commit: (Double) -> Void

    @Local private var dragging: Double?
    @Local private var held: Double?

    private var span: Double { max(spec.max - spec.min, 1) }

    var body: some View {
        let fraction = dragging ?? held ?? min(max((raw - spec.min) / span, 0), 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if let track {
                    Capsule().fill(LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing)).opacity(0.85)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: 22, height: 22)
                        .offset(x: 4 + (geometry.size.width - 30) * fraction)
                } else {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint.opacity(0.85))
                        .frame(width: max(30, geometry.size.width * fraction))
                }
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                    Text(title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(label(spec.min + fraction * span))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, track == nil ? 11 : 34)
                .foregroundStyle(track == nil ? Color.primary : Color.black.opacity(0.75))
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
        if percent { return "\(Int(((raw - spec.min) / span * 100).rounded()))%" }
        return "\(spec.scaled(raw).short)\(spec.unit.isEmpty ? "" : " \(spec.unit)")"
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
