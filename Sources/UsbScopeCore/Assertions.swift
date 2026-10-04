import Foundation

/// Expectation checks for CI and QA rigs — the twin of `usbscope/assertions.py`.
///
/// Parses `--expect` expressions, evaluates them against one snapshot and
/// reports per-expectation pass/fail. The Python CLI, this CLI twin and the
/// tests share the exact same rules and wording.
///
/// Supported expressions (`--expect` may be repeated):
///
/// * `device=<vid:pid>` or `device=<name substring>` — at least one device
///   matches the USB ID or carries the substring in its vendor/name;
/// * `port=<name>` — at least one receptacle is named exactly `name`;
/// * `connected>=N`, `devices>=N`, `warning=0` — numeric comparisons over the
///   snapshot counts (every comparison operator is accepted).
///
/// Anything else is malformed and makes the CLI exit `2` — a typo must never be
/// reported as a failed check.
///
/// Pretty or compact JSON text with sorted keys.
///
/// `Serialize` keeps its own serialisation private to the snapshot document; the
/// auxiliary documents (check result, baseline diff, event line) share this tiny
/// helper so their key order is deterministic on every run.
func sortedJSONText(_ object: Any, pretty: Bool) -> String {
    var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes, .sortedKeys]
    if pretty { options.insert(.prettyPrinted) }
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: options),
          let text = String(data: data, encoding: .utf8)
    else { return "{}" }
    return text
}

public enum AssertionError: Error, Equatable, CustomStringConvertible {
    case malformed(String)

    public var description: String {
        switch self {
        case let .malformed(message): message
        }
    }
}

/// One parsed `--expect` expression.
///
/// `target` is the number a count key is compared against; it stays `nil` for
/// the two match keys, whose `value` is looked up in the snapshot instead.
public struct Expectation: Equatable, Sendable {
    public let raw: String
    public let key: String
    public let op: String
    public let value: String
    public let target: Int?
}

/// The result of evaluating one expectation against one snapshot.
public struct Outcome: Equatable, Sendable {
    public let expression: String
    public let key: String
    public let op: String
    public let target: Int?
    public let actual: Int
    public let ok: Bool
    public let detail: String

    /// Plain JSON-compatible form.
    public var dictionary: [String: Any] {
        [
            "expression": expression,
            "key": key,
            "op": op,
            "target": Serialize.orNull(target),
            "actual": actual,
            "ok": ok,
            "detail": detail,
        ]
    }
}

/// Every outcome of one `check` run, in the order they were given.
public struct CheckReport: Sendable {
    public let outcomes: [Outcome]

    public init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    /// True when every expectation holds (vacuously true for none).
    public var passed: Bool { outcomes.allSatisfy(\.ok) }

    /// How many expectations hold.
    public var passedCount: Int { outcomes.filter(\.ok).count }

    /// The expectations that did not hold.
    public var failed: [Outcome] { outcomes.filter { !$0.ok } }

    /// Machine readable result document (`kind: check`).
    public var dictionary: [String: Any] {
        [
            "kind": "check",
            "passed": passed,
            "total": outcomes.count,
            "passed_count": passedCount,
            "failed_count": failed.count,
            "expectations": outcomes.map(\.dictionary),
        ]
    }
}

public enum Assertions {
    static let countKeys: Set<String> = ["connected", "devices", "warning", "warnings"]
    static let matchKeys: Set<String> = ["device", "port"]

    // MARK: - parsing

    /// Split `key<op>value`; the operator is the first `>=`, `<=`, `==`, `=`, `>` or `<`.
    static func firstOperator(in text: String) -> (op: String, start: String.Index, end: String.Index)? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == ">" || character == "<" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "=" {
                    return (String(character) + "=", index, text.index(after: next))
                }
                return (String(character), index, next)
            }
            if character == "=" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "=" {
                    return ("==", index, text.index(after: next))
                }
                return ("=", index, next)
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func split(_ expression: String) throws -> (key: String, op: String, value: String) {
        let text = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found = firstOperator(in: text) else {
            throw AssertionError.malformed(
                "malformed expectation '\(expression)': expected '<key><op><value>', "
                    + "e.g. device=0x1050:0x0407, port=USB-C@3, connected>=1, warning=0"
            )
        }
        let key = String(text[text.startIndex..<found.start]).trimmingCharacters(in: .whitespaces)
        let value = String(text[found.end...]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ $0.isLowercase || $0 == "_" }) else {
            throw AssertionError.malformed("malformed expectation '\(expression)': bad key '\(key)'")
        }
        guard !value.isEmpty else {
            throw AssertionError.malformed("malformed expectation '\(expression)': empty value")
        }
        return (key, found.op, value)
    }

    /// Parse one `--expect` expression, throwing `AssertionError` on a malformed one.
    public static func parse(_ expression: String) throws -> Expectation {
        let (key, op, value) = try split(expression)
        let text = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if matchKeys.contains(key) {
            guard op == "=" || op == "==" else {
                throw AssertionError.malformed(
                    "malformed expectation '\(text)': \(key) only supports '=', not '\(op)'"
                )
            }
            return Expectation(raw: text, key: key, op: "=", value: value, target: nil)
        }
        if countKeys.contains(key) {
            guard let target = Int(value), target >= 0 else {
                throw AssertionError.malformed(
                    "malformed expectation '\(text)': \(key) needs a whole number, got '\(value)'"
                )
            }
            return Expectation(raw: text, key: key, op: op, value: value, target: target)
        }
        let known = (matchKeys.union(countKeys)).sorted().joined(separator: ", ")
        throw AssertionError.malformed(
            "malformed expectation '\(text)': unknown key '\(key)' (known: \(known))"
        )
    }

    // MARK: - matching

    /// Parse `0x1050:0x0407` (the `0x` is optional on either half, hex only).
    public static func parseUSBID(_ value: String) -> (vendor: Int, product: Int)? {
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        func half(_ raw: Substring) -> Int? {
            var text = String(raw)
            if text.lowercased().hasPrefix("0x") { text = String(text.dropFirst(2)) }
            guard (1...4).contains(text.count), text.allSatisfy(\.isHexDigit) else { return nil }
            return Int(text, radix: 16)
        }
        guard let vendor = half(parts[0]), let product = half(parts[1]) else { return nil }
        return (vendor, product)
    }

    /// `0xvvvv:0xpppp` for a matching ID string.
    public static func normalizeUSBID(_ value: String) -> String {
        guard let id = parseUSBID(value) else { return value }
        return String(format: "0x%04x:0x%04x", id.vendor, id.product)
    }

    /// True when `value` names this device (USB ID or a name/vendor substring).
    public static func deviceMatches(_ device: UsbDevice, _ value: String) -> Bool {
        if let _ = parseUSBID(value) {
            return device.idString.lowercased() == normalizeUSBID(value).lowercased()
        }
        let haystack = "\((device.vendor ?? "")) \(device.name)".lowercased()
        return haystack.contains(value.lowercased())
    }

    static func compare(_ actual: Int, _ op: String, _ target: Int) -> Bool {
        switch op {
        case ">=": actual >= target
        case "<=": actual <= target
        case "=", "==": actual == target
        case ">": actual > target
        default: actual < target
        }
    }

    // MARK: - evaluation

    static func evaluate(_ snapshot: Snapshot, _ expectation: Expectation) -> Outcome {
        func outcome(_ actual: Int, _ ok: Bool, _ detail: String) -> Outcome {
            Outcome(
                expression: expectation.raw, key: expectation.key, op: expectation.op,
                target: expectation.target, actual: actual, ok: ok, detail: detail
            )
        }
        if expectation.key == "device" {
            let count = snapshot.devices.filter { deviceMatches($0, expectation.value) }.count
            return outcome(
                count, count >= 1, count > 0 ? "\(count) matching device(s)" : "no matching device"
            )
        }
        if expectation.key == "port" {
            let count = snapshot.ports.filter {
                $0.name.lowercased() == expectation.value.lowercased()
            }.count
            return outcome(
                count, count >= 1, count > 0 ? "\(count) matching port(s)" : "no matching port"
            )
        }
        let actual: Int
        switch expectation.key {
        case "connected": actual = snapshot.connectedPorts.count
        case "devices": actual = snapshot.devices.count
        default: actual = snapshot.warnings.count
        }
        let target = expectation.target ?? 0
        let label = expectation.key.hasPrefix("warning") ? "warning(s)" : expectation.key
        return outcome(
            actual, compare(actual, expectation.op, target),
            "\(actual) \(label) \(expectation.op) \(target)"
        )
    }

    /// Evaluate every expectation against one snapshot, in order.
    public static func evaluate(_ snapshot: Snapshot, _ expectations: [Expectation]) -> CheckReport {
        CheckReport(outcomes: expectations.map { evaluate(snapshot, $0) })
    }

    // MARK: - output

    /// Serialise a check result as a stable JSON document (sorted keys).
    public static func json(_ report: CheckReport) -> String {
        sortedJSONText(report.dictionary, pretty: true)
    }

    /// Plain-text form, one line per expectation plus a summary.
    public static func render(_ report: CheckReport) -> String {
        var lines = report.outcomes.map { outcome in
            "  \(outcome.ok ? "✓" : "✗") \(outcome.expression)  →  \(outcome.detail)"
        }
        let total = report.outcomes.count
        let status = report.passed ? "ok" : "\(report.failed.count) failed"
        lines.append("\(report.passedCount)/\(total) expectation(s) hold — \(status)")
        return lines.joined(separator: "\n")
    }
}
