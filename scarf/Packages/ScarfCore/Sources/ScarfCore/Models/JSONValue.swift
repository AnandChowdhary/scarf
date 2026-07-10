import Foundation

/// A lossless, order-agnostic representation of any JSON fragment.
///
/// Exists so Codable models that round-trip Hermes-owned files (today:
/// `cron/jobs.json`) can carry the keys they don't model through a
/// decode → edit → encode cycle instead of silently stripping them.
/// Hermes adds per-job fields across releases (`run_claim`, `repeat`,
/// `enabled_toolsets`, …) and a GUI rewrite must never delete state the
/// scheduler owns — see the v0.18.2 audit.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported JSON value"
            )
        }
    }

    public nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// A CodingKey over arbitrary string keys — used to sweep up the keys a
/// model doesn't declare so they can be preserved as `JSONValue`s.
public struct AnyCodingKey: CodingKey, Sendable {
    public let stringValue: String
    public let intValue: Int? = nil

    public init(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { return nil }
}
