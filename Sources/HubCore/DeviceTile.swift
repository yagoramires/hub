import NeyKit
import SwiftUI

/// Botão compacto da grade: o círculo da direita liga e desliga; clicar em qualquer outro ponto
/// abre o menu com as opções do aparelho. Aceso, o botão inteiro vira luz.
struct DeviceTile: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice
    let open: () -> Void
    /// Tela do Hub: o clique escolhe o aparelho para o painel de detalhe, em vez de abrir o menu.
    var select: (() -> Void)?
    @ViewState private var options = false

    private var accent: Color { Theme.accent(device.kind) }
    private var on: Bool { device.online && device.isOn }
    private var lit: Bool { on && device.kind == .light }
    private var fill: (low: Color, high: Color, glow: Color) { Theme.lightFill(device) }
    /// Tinta escura por cima da luz acesa.
    private let dark = Color(red: 0.23, green: 0.14, blue: 0)

    var body: some View {
        HStack(spacing: 8) {
            Icon(device.online ? Theme.symbol(device) : "wifi.slash", size: 15)
                .foregroundStyle(lit ? dark : on ? accent : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(lit ? Color.white.opacity(0.45) : on ? accent.opacity(0.16) : Theme.well))
                .overlay(alignment: .topTrailing) {
                    if device.kind == .plug && on {
                        Circle().fill(accent).frame(width: 7, height: 7).shadow(color: accent, radius: 5)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(Theme.font(12.5, .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    .foregroundStyle(lit ? dark : Color.primary)
                Text(status).font(Theme.font(11)).lineLimit(1)
                    .foregroundStyle(lit ? dark.opacity(0.72) : Color.secondary)
            }
            Spacer(minLength: 4)
            if device.canToggle, device.kind != .remote {
                Button { store.toggle(device) } label: {
                    Icon("power", size: 12)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(lit ? dark : on ? Color.black.opacity(0.78) : Color.secondary)
                        .background(Circle().fill(lit ? Color.white.opacity(0.7) : on ? accent : Theme.well))
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .disabled(!device.online)
                .help(on ? "Desligar" : "Ligar")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background {
            if lit {
                LinearGradient(colors: [fill.low, fill.high], startPoint: .leading, endPoint: .trailing)
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Brilho numa barrinha embaixo, para a luz que regula.
            if lit, let brightness = device.brightness {
                GeometryReader { geometry in
                    Capsule().fill(dark.opacity(0.35))
                        .frame(width: max(geometry.size.width - 28, 0) * brightness, height: 3)
                        .offset(x: 14, y: geometry.size.height - 7)
                }
            }
        }
        .card(device.kind == .plug && on ? Color(light: 0xECF8F1, dark: 0x1F2522) : Theme.matte,
              edge: on ? (lit ? fill.glow : accent).opacity(0.35) : nil, corner: 18)
        .glow(fill.glow, on: lit, radius: 22, opacity: 0.25 + 0.3 * (device.brightness ?? 1))
        .opacity(device.online ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            return device.brightness.map { "\(Int(($0 * 100).rounded()))%" } ?? "Acesa"
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
        .card(edge: feeding ? accent.opacity(0.5) : nil, corner: 18)
        .glow(accent, on: feeding, radius: 22, opacity: 0.5)
        .opacity(device.online ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
