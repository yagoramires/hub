import NeyKit
import SwiftUI

/// Refeição programada do alimentador Tuya. O ponto `meal_plan` é Raw (base64) com 5 bytes por
/// refeição: dias da semana (bit 0 = segunda … bit 6 = domingo), hora, minuto, porções e ativa.
/// Plano vazio é um único byte zero ("AA==").
struct Meal: Identifiable, Equatable {
    var id = UUID()
    var days: UInt8 = 0x7f
    var hour = 8
    var minute = 0
    var portions = 1
    var enabled = true

    static func decode(_ base64: String?) -> [Meal] {
        guard let base64, let data = Data(base64Encoded: base64), data.count >= 5 else { return [] }
        let bytes = [UInt8](data)
        return stride(from: 0, through: bytes.count - 5, by: 5).map { i in
            Meal(days: bytes[i], hour: Int(bytes[i + 1]), minute: Int(bytes[i + 2]),
                 portions: Int(bytes[i + 3]), enabled: bytes[i + 4] != 0)
        }
    }

    static func encode(_ meals: [Meal]) -> String {
        guard !meals.isEmpty else { return "AA==" }
        let sorted = meals.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        let bytes: [UInt8] = sorted.flatMap { meal -> [UInt8] in [meal.days, UInt8(meal.hour), UInt8(meal.minute), UInt8(meal.portions), meal.enabled ? 1 : 0] }
        return Data(bytes).base64EncodedString()
    }

    static let dayLetters = ["S", "T", "Q", "Q", "S", "S", "D"]
    static let dayNames = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]

    var time: String { String(format: "%02d:%02d", hour, minute) }

    /// Última refeição que já saiu e a próxima que vai sair, olhando uma semana para cada lado.
    static func schedule(_ meals: [Meal], now: Date = Date(), calendar: Calendar = .current)
        -> (previous: Date?, next: (date: Date, meal: Meal)?) {
        let today = calendar.startOfDay(for: now)
        var times: [(date: Date, meal: Meal)] = []
        for offset in -7...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // weekday do Calendar: 1 = domingo … 7 = sábado; no plano, bit 0 = segunda … bit 6 = domingo.
            let bit = (calendar.component(.weekday, from: day) + 5) % 7
            for meal in meals where meal.enabled && meal.days & (1 << bit) != 0 {
                if let date = calendar.date(bySettingHour: meal.hour, minute: meal.minute, second: 0, of: day) {
                    times.append((date, meal))
                }
            }
        }
        return (times.filter { $0.date <= now }.map(\.date).max(), times.filter { $0.date > now }.min { $0.date < $1.date })
    }

    var daysText: String {
        switch days & 0x7f {
        case 0x7f: "Todo dia"
        case 0x1f: "Seg a sex"
        case 0x60: "Fim de semana"
        case 0: "Nenhum dia"
        default: (0..<7).filter { days & (1 << $0) != 0 }.map { Self.dayNames[$0] }.joined(separator: ", ")
        }
    }
}

/// Lista e edição das refeições programadas. Cada mudança regrava o plano inteiro no aparelho.
struct MealPlanPanel: View {
    @EnvironmentObject private var store: HubStore
    let device: HubDevice

    @ViewState private var editing: Meal? = nil
    /// Posição da refeição no plano (o aparelho manda sem id). nil = refeição nova. Comparar pelo
    /// conteúdo mexia em duas refeições iguais de uma vez.
    @ViewState private var editingIndex: Int? = nil
    private var isNew: Bool { editingIndex == nil }

    private static let maxMeals = 10
    private var meals: [Meal] { Meal.decode(device.status["meal_plan"]?.string) }
    private var maxPortions: Int { Int(device.functions["manual_feed"]?.max ?? 12).clamped(1, 20) }

    var body: some View {
        Panel(title: "Refeições programadas") {
            if let editing {
                MealEditor(meal: editing, maxPortions: maxPortions, isNew: isNew,
                           save: { save($0) }, delete: { editingIndex.map(delete(at:)) }, cancel: { self.editing = nil })
            } else {
                if meals.isEmpty {
                    Text("Nenhuma refeição programada.")
                        .font(Theme.font(11.5)).foregroundStyle(.secondary)
                }
                ForEach(Array(meals.enumerated()), id: \.offset) { index, meal in
                    HStack(spacing: 10) {
                        Button { editingIndex = index; editing = meal } label: {
                            HStack(spacing: 10) {
                                Text(meal.time)
                                    .font(Theme.font(17, .semibold))
                                    .monospacedDigit()
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(meal.portions == 1 ? "1 porção" : "\(meal.portions) porções")
                                        .font(Theme.font(11.5, .medium))
                                    Text(meal.daysText).font(Theme.font(10.5)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .opacity(meal.enabled ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        Toggle("", isOn: Binding(get: { meal.enabled }, set: { on in
                            var list = meals
                            guard index < list.count else { return }
                            list[index].enabled = on
                            write(list)
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(Theme.accent(.feeder))
                    }
                    .frame(minHeight: 32)
                }
                if meals.count < Self.maxMeals {
                    Button {
                        editingIndex = nil
                        editing = Meal()
                    } label: {
                        Label { Text("Adicionar refeição") } icon: { Icon("plus.circle.fill", size: 12) }
                            .font(Theme.font(12, .semibold))
                            .foregroundStyle(Theme.accent(.feeder))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func save(_ meal: Meal) {
        var list = meals
        if let index = editingIndex, index < list.count {
            list[index] = meal
        } else {
            list.append(meal)
        }
        write(list)
        editing = nil
    }

    private func delete(at index: Int) {
        var list = meals
        if index < list.count { list.remove(at: index) }
        write(list)
        editing = nil
    }

    private func write(_ list: [Meal]) {
        store.setTuya(device, "meal_plan", Meal.encode(list))
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(self, low), high) }
}

struct MealEditor: View {
    @ViewState var meal: Meal
    let maxPortions: Int
    let isNew: Bool
    let save: (Meal) -> Void
    let delete: () -> Void
    let cancel: () -> Void

    init(meal: Meal, maxPortions: Int, isNew: Bool, save: @escaping (Meal) -> Void,
         delete: @escaping () -> Void, cancel: @escaping () -> Void) {
        _meal = ViewState(wrappedValue: meal)
        self.maxPortions = maxPortions
        self.isNew = isNew
        self.save = save
        self.delete = delete
        self.cancel = cancel
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                TimeWheel(value: $meal.hour, range: 0...23)
                Text(":").font(Theme.font(30, .light)).padding(.bottom, 4)
                TimeWheel(value: $meal.minute, range: 0...59, step: 5)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                StepperButton(symbol: "minus") { meal.portions = max(1, meal.portions - 1) }
                Text(meal.portions == 1 ? "1 porção" : "\(meal.portions) porções")
                    .font(Theme.font(13, .semibold))
                    .frame(minWidth: 80)
                StepperButton(symbol: "plus") { meal.portions = min(maxPortions, meal.portions + 1) }
            }

            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { day in
                    let on = meal.days & (1 << day) != 0
                    Button {
                        meal.days ^= 1 << day
                    } label: {
                        Text(Meal.dayLetters[day])
                            .font(Theme.font(11, .bold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(on ? .white : .secondary)
                            .background(Circle().fill(on ? Theme.accent(.feeder) : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(Meal.dayNames[day])
                }
            }

            HStack {
                if !isNew {
                    Button("Apagar", role: .destructive, action: delete)
                }
                Spacer()
                Button("Cancelar", action: cancel)
                Button(isNew ? "Adicionar" : "Salvar") { save(meal) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent(.feeder))
                    .disabled(meal.days & 0x7f == 0)
            }
            .controlSize(.small)
        }
    }
}

/// Número grande com setas para cima e para baixo; a rolagem do trackpad também ajusta.
struct TimeWheel: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        VStack(spacing: 2) {
            arrow("chevron.up", +step)
            Text(String(format: "%02d", value))
                .font(Theme.font(34, .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            arrow("chevron.down", -step)
        }
        .animation(.snappy(duration: 0.2), value: value)
    }

    private func arrow(_ symbol: String, _ delta: Int) -> some View {
        Button {
            let span = range.upperBound - range.lowerBound + 1
            // Minutos andam de 5 em 5 e voltam ao início depois do fim (55 → 00).
            let next = ((value - value % step) + delta - range.lowerBound + span) % span + range.lowerBound
            value = next
        } label: {
            Icon(symbol, size: 11)
                .frame(width: 44, height: 18)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
