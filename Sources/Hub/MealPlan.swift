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

    @Local private var editing: Meal?
    @Local private var isNew = false

    private static let maxMeals = 10
    private var meals: [Meal] { Meal.decode(device.status["meal_plan"]?.string) }
    private var maxPortions: Int { Int(device.functions["manual_feed"]?.max ?? 12).clamped(1, 20) }

    var body: some View {
        Panel(title: "Refeições programadas") {
            if let editing {
                MealEditor(meal: editing, maxPortions: maxPortions, isNew: isNew,
                           save: { save($0) }, delete: { delete(editing) }, cancel: { self.editing = nil })
            } else {
                if meals.isEmpty {
                    Text("Nenhuma refeição programada.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                ForEach(meals) { meal in
                    HStack(spacing: 10) {
                        Button { isNew = false; editing = meal } label: {
                            HStack(spacing: 10) {
                                Text(meal.time)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(meal.portions == 1 ? "1 porção" : "\(meal.portions) porções")
                                        .font(.system(size: 11.5, weight: .medium))
                                    Text(meal.daysText).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .opacity(meal.enabled ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        Toggle("", isOn: Binding(get: { meal.enabled }, set: { on in
                            var changed = meal
                            changed.enabled = on
                            write(meals.map { $0.matches(meal) ? changed : $0 })
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
                        isNew = true
                        editing = Meal()
                    } label: {
                        Label("Adicionar refeição", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
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
        if let index = list.firstIndex(where: { $0.matches(editing ?? meal) }), !isNew {
            list[index] = meal
        } else {
            list.append(meal)
        }
        write(list)
        editing = nil
    }

    private func delete(_ meal: Meal) {
        write(meals.filter { !$0.matches(meal) })
        editing = nil
    }

    private func write(_ list: [Meal]) {
        store.setTuya(device, "meal_plan", Meal.encode(list))
    }
}

private extension Meal {
    /// As refeições vêm do aparelho sem id; compara pelo conteúdo.
    func matches(_ other: Meal) -> Bool {
        days == other.days && hour == other.hour && minute == other.minute
            && portions == other.portions && enabled == other.enabled
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(self, low), high) }
}

struct MealEditor: View {
    @Local var meal: Meal
    let maxPortions: Int
    let isNew: Bool
    let save: (Meal) -> Void
    let delete: () -> Void
    let cancel: () -> Void

    init(meal: Meal, maxPortions: Int, isNew: Bool, save: @escaping (Meal) -> Void,
         delete: @escaping () -> Void, cancel: @escaping () -> Void) {
        _meal = Local(initialValue: meal)
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
                Text(":").font(.system(size: 30, weight: .light, design: .rounded)).padding(.bottom, 4)
                TimeWheel(value: $meal.minute, range: 0...59, step: 5)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                StepperButton(symbol: "minus") { meal.portions = max(1, meal.portions - 1) }
                Text(meal.portions == 1 ? "1 porção" : "\(meal.portions) porções")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
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
                .font(.system(size: 34, weight: .semibold, design: .rounded))
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
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 44, height: 18)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
