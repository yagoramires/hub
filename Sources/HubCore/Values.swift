import Foundation

/// Valor de um ponto de dados (Tuya) ou atributo (SmartThings), já tipado.
package enum DPValue: Equatable, CustomStringConvertible {
    case bool(Bool), int(Int), double(Double), string(String), other(String)

    init(_ any: Any?) {
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        } else if let string = any as? String {
            self = .string(string)
        } else if let any, !(any is NSNull),
                  let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]),
                  let string = String(data: data, encoding: .utf8) {
            self = .other(string)
        } else {
            self = .other("null")
        }
    }

    var json: Any {
        switch self {
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        case .other(let value): (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)) ?? NSNull()
        }
    }

    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }

    var number: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    var string: String? {
        switch self {
        case .string(let value): value
        case .other(let value): value
        default: nil
        }
    }

    /// Para atributos que são listas (ex.: modos suportados do ar).
    var list: [String] {
        (json as? [Any])?.compactMap { $0 as? String } ?? []
    }

    package var description: String {
        switch self {
        case .bool(let value): "\(value)"
        case .int(let value): "\(value)"
        case .double(let value): "\(value)"
        case .string(let value): "\"\(value)\""
        case .other(let value): value
        }
    }
}

/// O que um ponto de dados Tuya aceita: tipo, faixa, escala e opções.
package struct DPSpec: Equatable {
    package var code: String
    package var type: String
    var name: String
    package var min = 0.0
    package var max = 0.0
    package var scale = 0
    var step = 1.0
    package var unit = ""
    package var range: [String] = []

    init(json: [String: Any]) {
        code = json["code"] as? String ?? ""
        type = json["type"] as? String ?? ""
        name = json["name"] as? String ?? ""
        let raw = json["values"]
        let values = (raw as? [String: Any])
            ?? (raw as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            ?? [:]
        min = (values["min"] as? NSNumber)?.doubleValue ?? 0
        max = (values["max"] as? NSNumber)?.doubleValue ?? 0
        scale = (values["scale"] as? NSNumber)?.intValue ?? 0
        // step 0 dividiria por zero ao arredondar a barra (e Int(NaN) trava o app).
        let rawStep = (values["step"] as? NSNumber)?.doubleValue ?? 1
        step = rawStep > 0 ? rawStep : 1
        unit = values["unit"] as? String ?? ""
        range = values["range"] as? [String] ?? []
    }

    var isBool: Bool { type == "Boolean" }
    package var isInteger: Bool { type == "Integer" }
    package var isEnum: Bool { type == "Enum" }

    /// Valor cru do aparelho → valor que se mostra (ex.: 125 com escala 1 → 12,5).
    func scaled(_ raw: Double) -> Double { raw / pow(10, Double(scale)) }
}
