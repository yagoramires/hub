import Foundation

/// Um aparelho de qualquer nuvem, no formato que a interface usa.
package struct HubDevice: Identifiable, Equatable {
    enum Source: Equatable {
        case tuya(account: String)
        case smartThings
        case androidTV(host: String)
    }

    package enum Kind: Int, Comparable {
        case airConditioner, tv, light, plug, feeder, remote, other
        package static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    package let id: String
    package var name: String
    var source: Source
    package var category: String
    package var kind: Kind
    package var online: Bool
    package var room: String?
    /// Tuya: código do ponto → valor. SmartThings: "capability.atributo" → valor.
    package var status: [String: DPValue] = [:]
    /// Tuya: o que dá para comandar.
    package var functions: [String: DPSpec] = [:]
    /// Tuya: faixas e escalas do que o aparelho informa.
    var statusSpecs: [String: DPSpec] = [:]
    /// SmartThings: capabilities do componente principal.
    package var capabilities: Set<String> = []

    static func tuyaKind(category: String, name: String = "") -> Kind {
        // Relé ou tomada ligado numa luz: na Tuya é "cz", mas para quem usa é uma luz.
        if ["cz", "kg", "tdq"].contains(category),
           name.lowercased().range(of: #"\b(luz|led|l[aâ]mpada|abajur|lumin[aá]ria|spot)\b"#, options: .regularExpression) != nil {
            return .light
        }
        return switch category {
        case "dj", "dd", "xdd", "fwd", "dc", "tgq", "fsd", "tyndj", "gyd": .light
        case "cz", "pc", "kg", "tdq", "wkcz", "cl": .plug
        case "cwwsq", "cwysj", "cwjwq": .feeder
        case "kt", "ktkzq": .airConditioner
        case "wnykq", "qt": .remote
        default: category.hasPrefix("infrared") ? .remote : .other
        }
    }

    // MARK: Liga/desliga

    /// Ponto Tuya que liga e desliga o aparelho inteiro, quando existe.
    var powerCode: String? {
        // No alimentador, "switch" não desliga o aparelho (é o liga/desliga das refeições programadas).
        if kind == .feeder { return nil }
        for code in ["switch_led", "switch", "switch_1", "power", "switch_on"] {
            if functions[code]?.isBool == true { return code }
        }
        return nil
    }

    var canToggle: Bool {
        switch source {
        case .smartThings: capabilities.contains("switch")
        case .tuya: powerCode != nil
        case .androidTV: online
        }
    }

    var isOn: Bool {
        switch source {
        case .smartThings: status["switch.switch"]?.string == "on"
        case .tuya: powerCode.flatMap { status[$0]?.bool } ?? false
        case .androidTV: status["power"]?.bool ?? false
        }
    }

    /// Para tomadas e filtros de linha com várias saídas.
    var extraSwitches: [String] {
        functions.keys.filter { $0.hasPrefix("switch_") && $0 != powerCode && functions[$0]?.isBool == true
            && Int($0.dropFirst(7)) != nil }.sorted()
    }

    // MARK: Leituras

    /// Valor numérico já na escala certa (ex.: cur_power 125 → 12,5 W).
    func reading(_ code: String) -> (value: Double, unit: String)? {
        guard let raw = status[code]?.number else { return nil }
        let spec = statusSpecs[code] ?? functions[code]
        return (spec?.scaled(raw) ?? raw, spec?.unit ?? "")
    }

    // MARK: Luz (Tuya)

    var brightnessSpec: DPSpec? { functions["bright_value_v2"] ?? functions["bright_value"] }

    /// Brilho de 0 a 1, ou nil se a luz não regula.
    var brightness: Double? {
        // No modo colorido o brilho é o v do colour_data; o bright_value só vale para a branca.
        if status["work_mode"]?.string == "colour", let colour { return colour.v }
        guard let spec = brightnessSpec, spec.max > spec.min, let raw = status[spec.code]?.number else { return nil }
        return min(max((raw - spec.min) / (spec.max - spec.min), 0), 1)
    }

    var colourCode: String? { ["colour_data_v2", "colour_data"].first { functions[$0] != nil } }

    /// Cor atual: h de 0 a 360, s e v de 0 a 1 (a v2 vai até 1000, a antiga até 255).
    var colour: (h: Double, s: Double, v: Double)? {
        guard let code = colourCode, let text = status[code]?.string,
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let h = (json["h"] as? NSNumber)?.doubleValue, let s = (json["s"] as? NSNumber)?.doubleValue,
              let v = (json["v"] as? NSNumber)?.doubleValue else { return nil }
        let top = code == "colour_data_v2" ? 1000.0 : 255.0
        return (h, s / top, v / top)
    }

    // MARK: Ar-condicionado (SmartThings)

    var acMode: String? { status["airConditionerMode.airConditionerMode"]?.string }
    var acModes: [String] {
        let list = status["airConditionerMode.supportedAcModes"]?.list ?? []
        return list.isEmpty ? ["cool", "auto", "dry", "wind", "heat"] : list
    }
    var acSetpoint: Double? { status["thermostatCoolingSetpoint.coolingSetpoint"]?.number }
    var acRoomTemperature: Double? { status["temperatureMeasurement.temperature"]?.number }
    var acHumidity: Double? { status["relativeHumidityMeasurement.humidity"]?.number }
    var acFanMode: String? { status["airConditionerFanMode.fanMode"]?.string }
    var acFanModes: [String] {
        let list = status["airConditionerFanMode.supportedAcFanModes"]?.list ?? []
        return list.isEmpty ? ["auto", "low", "medium", "high", "turbo"] : list
    }
    var acOptionalMode: String? { status["custom.airConditionerOptionalMode.acOptionalMode"]?.string }
    var acOptionalModes: [String] { status["custom.airConditionerOptionalMode.supportedAcOptionalMode"]?.list ?? [] }
    var acSetpointRange: ClosedRange<Double> {
        let range = status["custom.thermostatSetpointControl.minimumSetpoint"]?.number
            .flatMap { min in status["custom.thermostatSetpointControl.maximumSetpoint"]?.number.map { min...$0 } }
        return range ?? 16...30
    }
}
