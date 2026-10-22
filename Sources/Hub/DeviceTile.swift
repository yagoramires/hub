import SwiftUI

/// Bloco da grade: clicar liga/desliga; a seta abre os detalhes.
struct DeviceTile: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let open: () -> Void
    @Local private var hover = false

    private var accent: Color { Theme.accent(device.kind) }
    private var lit: Bool { device.online && (device.isOn || (device.kind == .feeder && device.status["feed_state"]?.string == "feeding")) }

    var body: some View {
        Button(action: primary) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: Theme.symbol(device))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(lit ? .white : .secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(lit ? accent : Color.primary.opacity(0.08)))
                        .shadow(color: lit ? accent.opacity(0.55) : .clear, radius: 8, y: 2)
                    Spacer()
                    Button(action: open) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0.0)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Detalhes")
                }
                Spacer(minLength: 8)
                Text(device.name)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(height: 98)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(lit ? accent.opacity(0.16) : Color.primary.opacity(hover ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(lit ? accent.opacity(0.45) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .opacity(device.online ? 1 : 0.5)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: lit)
        .contextMenu {
            Button("Detalhes", action: open)
            if device.canToggle { Button(device.isOn ? "Desligar" : "Ligar") { store.toggle(device) } }
        }
    }

    /// Alimentador e controles abrem os detalhes; o resto liga e desliga.
    private func primary() {
        if device.canToggle && device.kind != .feeder && device.kind != .remote {
            store.toggle(device)
        } else {
            open()
        }
    }

    private var detail: String {
        guard device.online else { return "Offline" }
        switch device.kind {
        case .light:
            guard device.isOn else { return "Apagada" }
            if let spec = device.functions["bright_value_v2"] ?? device.functions["bright_value"],
               let raw = device.status[spec.code]?.number, spec.max > spec.min {
                return "Acesa · \(Int(((raw - spec.min) / (spec.max - spec.min) * 100).rounded()))%"
            }
            return "Acesa"
        case .plug:
            guard device.isOn else { return "Desligada" }
            if let power = device.reading("cur_power"), power.value > 0 { return "Ligada · \(power.value.short) W" }
            return "Ligada"
        case .feeder:
            switch device.status["feed_state"]?.string {
            case "feeding": return "Servindo…"
            default:
                if let last = device.status["feed_report"]?.number, last > 0 { return "Última: \(Int(last)) porç." }
                return "Pronto"
            }
        case .remote:
            return device.category == "wnykq" ? "Controle universal" : "Infravermelho"
        default:
            return device.canToggle ? (device.isOn ? "Ligado" : "Desligado") : "Online"
        }
    }
}

/// Afunda um pouco ao clicar.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
