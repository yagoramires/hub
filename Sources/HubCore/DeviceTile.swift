import NeyKit
import SwiftUI

/// Cartão da grade: ícone na cor do tipo e o switch em cima, nome e estado embaixo; clicar fora do switch abre as
/// opções do aparelho. Ligado, acende em halo na cor dele (a luz, na cor real).
struct DeviceTile: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let open: () -> Void
    /// Tela do Hub: o clique escolhe o aparelho para o painel de detalhe, em vez de abrir o menu.
    var select: (() -> Void)?
    @ViewState private var options = false

    private var on: Bool { device.online && device.isOn }
    /// Cor do ícone e do halo: a da luz acesa, senão a do tipo.
    private var tint: Color { device.kind == .light && on ? Theme.lightFill(device).glow : Theme.accent(device.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Icon(device.online ? Theme.symbol(device) : "wifi.slash", size: 15)
                    .foregroundStyle(device.online ? tint : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(device.online ? tint.opacity(on ? 0.18 : 0.12) : Theme.well))
                    .shadow(color: on ? tint.opacity(0.3) : .clear, radius: 5)
                Spacer(minLength: 4)
                if device.canToggle, device.kind != .remote {
                    GSwitch(isOn: Binding(get: { on }, set: { _ in store.toggle(device) }), label: device.name)
                        .disabled(!device.online)
                        .help(on ? "Desligar" : "Ligar")
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(Theme.font(12.5, .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Text(status).font(Theme.font(11)).lineLimit(1)
                    .foregroundStyle(on ? tint.opacity(0.9) : Color.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .glow(tint, on: on)
        .opacity(device.online ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
        .onTapGesture { if let select { select() } else if device.kind == .remote { open() } else { options = true } }
        .popover(isPresented: $options, arrowEdge: .bottom) {
            OptionsMenu(device: device).environmentObject(store)
        }
        .animation(.easeOut(duration: 0.2), value: on)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Opções") { options = true }
        .contextMenu {
            Button("Opções") { options = true }
            if device.canToggle { Button(device.isOn ? "Desligar" : "Ligar") { store.toggle(device) } }
        }
    }

    private var status: String {
        guard device.online else { return "Sem conexão" }
        switch device.kind {
        case .light:
            guard on else { return "Apagada" }
            return device.brightness.map { "Acesa · \(Int(($0 * 100).rounded()))%" } ?? "Acesa"
        case .plug:
            guard on else { return "Desligada" }
            if let power = device.reading("cur_power"), power.value > 0 {
                return "\(power.value >= 100 ? "\(Int(power.value.rounded()))" : power.value.short) W"
            }
            return "Ligada"
        case .remote:
            return device.category == "wnykq" ? "Controle universal" : "Infravermelho"
        default:
            return device.canToggle ? (on ? "Ligado" : "Desligado") : "Online"
        }
    }
}

/// Alimentador compacto: o anel em volta do pote conta o tempo até a próxima refeição, "Servir"
/// solta uma porção e clicar no resto abre as refeições e os ajustes.
struct FeederCard: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    /// Tela do Hub: o clique escolhe o alimentador para o painel de detalhe.
    var select: (() -> Void)?
    @ViewState private var options = false

    private var accent: Color { Theme.accent(.feeder) }
    private var feeding: Bool { device.status["feed_state"]?.string == "feeding" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let schedule = Meal.schedule(Meal.decode(device.status["meal_plan"]?.string), now: context.date)
            HStack(spacing: 10) {
                ring(schedule, now: context.date)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(Theme.font(12.5, .semibold)).lineLimit(1)
                    Text(next(schedule, now: context.date)).font(Theme.font(11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if device.functions["manual_feed"] != nil || device.functions["quick_feed"] != nil {
                    Button(feeding ? "Servindo" : "Servir") {
                        if device.functions["manual_feed"] != nil {
                            store.setTuya(device, "manual_feed", 1)
                        } else {
                            store.setTuya(device, "quick_feed", true)
                        }
                    }
                    .buttonStyle(FilledStyle(tint: accent))
                    .disabled(!device.online || feeding)
                    .help("Servir 1 porção agora")
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .card(edge: feeding ? accent.opacity(0.5) : nil)
        .glow(accent, on: feeding)
        .opacity(device.online ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
        .onTapGesture { if let select { select() } else { options = true } }
        .popover(isPresented: $options, arrowEdge: .bottom) {
            OptionsMenu(device: device).environmentObject(store)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Refeições e ajustes") { options = true }
        .contextMenu { Button("Refeições e ajustes") { options = true } }
    }

    private func ring(_ schedule: (previous: Date?, next: (date: Date, meal: Meal)?), now: Date) -> some View {
        let progress: Double = {
            guard let previous = schedule.previous, let next = schedule.next?.date else { return 0 }
            return min(max(now.timeIntervalSince(previous) / next.timeIntervalSince(previous), 0), 1)
        }()
        return ZStack {
            Circle().stroke(Theme.well, lineWidth: 3)
            Circle().trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Icon("feeder.bowl", size: 16).foregroundStyle(accent)
        }
        .frame(width: 34, height: 34)
        .help("Tempo até a próxima refeição")
    }

    private func next(_ schedule: (previous: Date?, next: (date: Date, meal: Meal)?), now: Date) -> String {
        guard device.online else { return "Sem conexão" }
        if feeding { return "Servindo agora" }
        guard let next = schedule.next else { return "Sem refeições programadas" }
        return "\(next.meal.time), daqui a \(Self.remaining(next.date.timeIntervalSince(now)))"
    }

    /// 25 min → "25 min"; 7 h 20 → "7 h"; mais de dois dias → "3 dias".
    static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        if minutes < 48 * 60 { return "\(minutes / 60) h" }
        return "\(minutes / 1440) dias"
    }
}

/// Menu que abre por cima do Hub com todas as opções de um aparelho.
struct OptionsMenu: View {
    let device: HubDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(device.name).font(Theme.font(13.5, .semibold)).padding(.horizontal, 4)
            ScrollView(showsIndicators: false) {
                DeviceOptions(device: device).padding(.bottom, 4)
            }
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 330)
        .font(Theme.font(13))
        .background(Theme.room.ignoresSafeArea())
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
