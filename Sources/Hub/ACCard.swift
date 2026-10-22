import SwiftUI

/// Cartão grande do ar-condicionado: temperatura no centro, modos e ventilação embaixo.
struct ACCard: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    @Local private var target: Double?
    @Local private var sendTask: Task<Void, Never>?

    private var on: Bool { device.isOn }
    private var setpoint: Double { target ?? device.acSetpoint ?? 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if on { controls } else { offSummary }
        }
        .padding(14)
        .foregroundStyle(on ? .white : .primary)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner + 2, style: .continuous))
        .opacity(device.online ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.25), value: on)
        .animation(.easeInOut(duration: 0.25), value: device.acMode)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "air.conditioner.horizontal.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(on ? .white.opacity(0.2) : Color.primary.opacity(0.07)))
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).opacity(0.75)
            }
            Spacer()
            PowerButton(on: on, onDark: on) { store.toggle(device) }
                .disabled(!device.online)
        }
    }

    private var subtitle: String {
        guard device.online else { return "Offline" }
        var parts: [String] = []
        if let room = device.acRoomTemperature { parts.append("Ambiente \(room.short)°") }
        if let humidity = device.acHumidity, humidity > 0 { parts.append("\(Int(humidity))% umidade") }
        return parts.isEmpty ? (on ? "Ligado" : "Desligado") : parts.joined(separator: " · ")
    }

    private var offSummary: some View {
        HStack {
            Text("Desligado").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if let setpoint = device.acSetpoint {
                Text("Programado para \(setpoint.short)°").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                Spacer()
                StepButton(symbol: "minus") { bump(-1) }
                    .disabled(setpoint <= device.acSetpointRange.lowerBound)
                HStack(alignment: .top, spacing: 1) {
                    Text(setpoint.short)
                        .font(.system(size: 54, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: setpoint))
                    Text("°C").font(.system(size: 15, weight: .medium, design: .rounded)).padding(.top, 10).opacity(0.8)
                }
                .frame(minWidth: 110)
                StepButton(symbol: "plus") { bump(1) }
                    .disabled(setpoint >= device.acSetpointRange.upperBound)
                Spacer()
            }

            row {
                ForEach(device.acModes, id: \.self) { mode in
                    // Só o modo ativo mostra o nome; os outros ficam no ícone para caber numa linha.
                    Chip(title: device.acMode == mode ? Labels.value(mode) : "", symbol: Labels.acModeSymbol(mode),
                         selected: device.acMode == mode, onDark: true) {
                        store.stCommand(device, capability: "airConditionerMode", command: "setAirConditionerMode",
                                        arguments: [mode], optimistic: ["airConditionerMode.airConditionerMode": .string(mode)])
                    }
                    .help(Labels.value(mode))
                }
            }

            row {
                Image(systemName: "fan.fill").font(.system(size: 11)).opacity(0.75)
                ForEach(device.acFanModes, id: \.self) { fan in
                    Chip(title: Labels.value(fan), selected: device.acFanMode == fan, onDark: true) {
                        store.stCommand(device, capability: "airConditionerFanMode", command: "setFanMode",
                                        arguments: [fan], optimistic: ["airConditionerFanMode.fanMode": .string(fan)])
                    }
                }
            }

            if device.acOptionalModes.count > 1 {
                row {
                    Image(systemName: "sparkles").font(.system(size: 11)).opacity(0.75)
                    ForEach(device.acOptionalModes, id: \.self) { option in
                        Chip(title: option == "off" ? "Normal" : Labels.value(option),
                             selected: (device.acOptionalMode ?? "off") == option, onDark: true) {
                            store.stCommand(device, capability: "custom.airConditionerOptionalMode", command: "setAcOptionalMode",
                                            arguments: [option], optimistic: ["custom.airConditionerOptionalMode.acOptionalMode": .string(option)])
                        }
                    }
                }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Scroller(axis: .horizontal) {
            HStack(spacing: 5) { content() }
        }
    }

    private var background: some View {
        ZStack {
            if on {
                LinearGradient(colors: Theme.acGradient(mode: device.acMode), startPoint: .topLeading, endPoint: .bottomTrailing)
                // Um brilho suave no canto, para não parecer chapado.
                RadialGradient(colors: [.white.opacity(0.25), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
            } else {
                Color.primary.opacity(0.06)
            }
        }
    }

    /// Junta cliques seguidos em + e − num comando só.
    private func bump(_ delta: Double) {
        let range = device.acSetpointRange
        let next = min(max(setpoint + delta, range.lowerBound), range.upperBound)
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

struct StepButton: View {
    let symbol: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
    }
}

struct PowerButton: View {
    let on: Bool
    var tint: Color = .accentColor
    var onDark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(on ? (onDark ? Color.black.opacity(0.75) : .white) : .secondary)
                .background(Circle().fill(on ? (onDark ? Color.white.opacity(0.92) : tint) : Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(on ? "Desligar" : "Ligar")
    }
}
