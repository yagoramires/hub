import NeyKit
import SwiftUI

/// Cartão do ar-condicionado: o ar ligado solta luz fria, a régua vai do frio ao quente e
/// arrastar nela escolhe a temperatura. Modos e ventilação ficam embaixo.
struct ACCard: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    /// Nos detalhes o cabeçalho da tela já mostra o nome.
    var showsName = true
    @ViewState private var target: Double? = nil
    @ViewState private var sendTask: Task<Void, Never>? = nil

    private var on: Bool { device.isOn }
    private var setpoint: Double { target ?? device.acSetpoint ?? 24 }
    private var tint: Color { Self.tint(device.acMode) }

    /// Cor da luz do ar conforme o modo.
    static func tint(_ mode: String?) -> Color {
        switch mode {
        case "heat": Color(hex: 0xFF9F45)
        case "dry": Color(hex: 0x3FD9C9)
        case "wind", "fanOnly", "fan": Color(hex: 0x8FA2FF)
        case "auto", "aIComfort": Color(hex: 0xA98BFF)
        default: Color(hex: 0x5CC8FF)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if on { controls } else { offSummary }
        }
        .padding(14)
        .background(alignment: .top) { if on { Airflow(color: tint).frame(height: 34) } }
        .card()
        .glow(tint, on: on)
        .opacity(device.online ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.25), value: on)
        .animation(.easeInOut(duration: 0.25), value: device.acMode)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if showsName {
                    Text(device.name).font(Theme.font(13.5, .semibold)).lineLimit(1)
                }
                Text(subtitle).font(Theme.font(11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            PowerSwitch(on: on, label: device.name) { store.toggle(device) }
                .disabled(!device.online)
        }
    }

    private var subtitle: String {
        guard device.online else { return "Sem conexão" }
        guard on else { return "Desligado" }
        return switch device.acMode {
        case "cool": "Resfriando o quarto"
        case "heat": "Aquecendo o quarto"
        case "dry": "Tirando a umidade"
        case "wind", "fanOnly", "fan": "Só ventilando"
        default: "No automático"
        }
    }

    /// Desligado: a temperatura do quarto em destaque; liga pelo botão de power do cabeçalho.
    private var offSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            if let room = device.acRoomTemperature {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(room.short)°").font(Theme.number(40, .light))
                    Text(device.acHumidity.map { "no quarto, \(Int($0))% de umidade" } ?? "no quarto")
                        .font(Theme.font(11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let setpoint = device.acSetpoint {
                Text("Liga em \(setpoint.short)°").font(Theme.font(11.5)).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                HStack(alignment: .top, spacing: 3) {
                    Text(setpoint.short)
                        .font(Theme.number(68, .light))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: setpoint))
                    Text("°C").font(Theme.number(17, .regular)).foregroundStyle(.secondary).padding(.top, 8)
                }
                Spacer()
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 3) {
                    if let room = device.acRoomTemperature { reading("no quarto", "\(room.short)°") }
                    if let humidity = device.acHumidity, humidity > 0 { reading("umidade", "\(Int(humidity))%") }
                }
                .padding(.bottom, 8)
            }

            TemperatureRuler(value: setpoint, range: device.acSetpointRange) { set($0) }

            modes

            Scroller(axis: .horizontal) {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(device.acFanModes, id: \.self) { fan in
                            Button(Labels.value(fan)) {
                                store.stCommand(device, capability: "airConditionerFanMode", command: "setFanMode",
                                                arguments: [fan], optimistic: ["airConditionerFanMode.fanMode": .string(fan)])
                            }
                        }
                    } label: {
                        Label { Text("Vento \(Labels.value(device.acFanMode ?? "auto").lowercased())") } icon: { Icon("fan.fill", size: 12) }
                    }
                    .menuStyle(.button)
                    .buttonStyle(SoftChipStyle(selected: false, tint: tint))
                    .menuIndicator(.hidden)
                    .fixedSize()

                    ForEach(device.acOptionalModes.filter { $0 != "off" }, id: \.self) { option in
                        let selected = device.acOptionalMode == option
                        Button(Labels.value(option)) {
                            let next = selected ? "off" : option
                            store.stCommand(device, capability: "custom.airConditionerOptionalMode", command: "setAcOptionalMode",
                                            arguments: [next], optimistic: ["custom.airConditionerOptionalMode.acOptionalMode": .string(next)])
                        }
                        .buttonStyle(SoftChipStyle(selected: selected, tint: tint))
                    }
                }
            }
        }
    }

    private func reading(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(Theme.font(11.5)).foregroundStyle(.secondary)
            Text(value).font(Theme.number(12, .semibold))
        }
    }

    /// O modo escolhido mostra o nome; os outros só o ícone.
    private var modes: some View {
        HStack(spacing: 2) {
            ForEach(device.acModes, id: \.self) { mode in
                let selected = device.acMode == mode
                Button {
                    store.stCommand(device, capability: "airConditionerMode", command: "setAirConditionerMode",
                                    arguments: [mode], optimistic: ["airConditionerMode.airConditionerMode": .string(mode)])
                } label: {
                    HStack(spacing: 5) {
                        Icon(Labels.acModeSymbol(mode), size: 12)
                        if selected { Text(Labels.value(mode)).font(Theme.font(12, .bold)) }
                    }
                    .frame(maxWidth: selected ? .infinity : nil, minHeight: 32)
                    .frame(width: selected ? nil : 40)
                    .foregroundStyle(selected ? Color.black.opacity(0.8) : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? tint : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help(Labels.value(mode))
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well))
    }

    /// Junta arrastadas e cliques seguidos num comando só.
    private func set(_ value: Double) {
        let range = device.acSetpointRange
        let next = min(max(value.rounded(), range.lowerBound), range.upperBound)
        guard next != setpoint else { return }
        withAnimation(.snappy) { target = next }
        sendTask?.cancel()
        sendTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            store.stCommand(device, capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint",
                            arguments: [Int(next)], optimistic: ["thermostatCoolingSetpoint.coolingSetpoint": .double(next)])
            target = nil
        }
    }
}

/// Régua de meio em meio grau: do azul (frio) ao laranja (quente); o que passa da escolha fica apagado.
struct TemperatureRuler: View {
    let value: Double
    let range: ClosedRange<Double>
    let set: (Double) -> Void

    private var steps: [Double] { Array(stride(from: range.lowerBound, through: range.upperBound, by: 0.5)) }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(steps, id: \.self) { step in
                        tick(step).frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let fraction = min(max(drag.location.x / geometry.size.width, 0), 1)
                    set(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
                })
            }
            .frame(height: 40)
            .accessibilityElement()
            .accessibilityLabel("Temperatura")
            .accessibilityValue("\(value.short) graus")
            .accessibilityAdjustableAction { direction in set(value + (direction == .increment ? 1 : -1)) }

            // Cada número no centro do traço dele (mesma conta da régua), não espaçados por igual.
            GeometryReader { geometry in
                ForEach(labels, id: \.self) { label in
                    let slot = (label - range.lowerBound) * 2 + 0.5
                    Text(label.short)
                        .font(Theme.number(10, label == value ? .bold : .regular))
                        .foregroundStyle(label == value ? Color.primary : Color.secondary)
                        .fixedSize()
                        .position(x: geometry.size.width * slot / Double(steps.count), y: 7)
                }
            }
            .frame(height: 14)
        }
    }

    private var labels: [Double] {
        let low = range.lowerBound, high = range.upperBound
        return Array(Set([low, value, high] + stride(from: low, through: high, by: 3).filter { abs($0 - value) >= 2 && high - $0 >= 2 })).sorted()
    }

    private func tick(_ step: Double) -> some View {
        let current = step == value
        let k = (step - range.lowerBound) / max(range.upperBound - range.lowerBound, 1)
        let color = Color(red: 0.36 + 0.64 * k, green: 0.78 - 0.16 * k, blue: 1 - 0.73 * k)
        return Capsule()
            .fill(current ? Color.primary : color)
            .frame(width: current ? 4 : 2, height: current ? 40 : step.rounded() == step ? 22 : 12)
            .opacity(current || step < value ? 1 : 0.28)
            .shadow(color: current ? Color.primary.opacity(0.5) : .clear, radius: 6)
    }
}

/// Linhas de vento correndo no topo do cartão. Param com "reduzir movimento" ligado.
struct Airflow: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * -20
            Canvas { canvas, size in
                for (row, line) in [(8.0, 1.1, 0.32), (18.0, 0.9, 0.18), (28.0, 0.7, 0.1)].enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: line.0))
                    let w = size.width
                    path.addCurve(to: CGPoint(x: w / 2, y: line.0), control1: CGPoint(x: w * 0.17, y: line.0 - 8 + Double(row) * 2),
                                  control2: CGPoint(x: w * 0.34, y: line.0 + 8))
                    path.addCurve(to: CGPoint(x: w, y: line.0), control1: CGPoint(x: w * 0.66, y: line.0 - 8),
                                  control2: CGPoint(x: w * 0.83, y: line.0 + 6))
                    canvas.stroke(path, with: .color(color.opacity(line.2)),
                                  style: StrokeStyle(lineWidth: line.1, lineCap: .round, dash: [8 - Double(row) * 2, 14 + Double(row) * 4],
                                                     dashPhase: phase * (1 + Double(row) * 0.3)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Liga/desliga que acende na cor do aparelho.
/// Liga/desliga do aparelho no cabeçalho: o switch do NeyKit.
struct PowerSwitch: View {
    let on: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        GSwitch(isOn: Binding(get: { on }, set: { _ in action() }), label: label)
            .help(on ? "Desligar" : "Ligar")
    }
}

struct SoftChipStyle: ButtonStyle {
    let selected: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(11.5, .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(selected ? tint : Grafite.ghostText)
            .overlay(Capsule().strokeBorder(selected ? tint : Grafite.ghostBorder, lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

