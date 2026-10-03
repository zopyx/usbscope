import Foundation

/// Value coercion shared by the plist/JSON adapters.
///
/// On Darwin an `NSNumber` bridges to `Bool` for the integers `0` and `1`, so
/// `value is Bool` is *not* a reliable boolean test — it would silently drop the
/// legitimate integers `0` and `1` (a pin assignment of `0`, a port number of
/// `1`, `power_mode == 1`, …) and the two implementations would then disagree on
/// the JSON. `CFGetTypeID` tells a real `CFBoolean` from a `CFNumber`.
enum PlistValue {
    /// True only for a genuine boolean (a `CFBoolean`, or a Swift `Bool`).
    static func isBool(_ value: Any) -> Bool {
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        }
        return value is Bool
    }

    /// Parse an integer the way Python's `int(text, 0)` does: an explicit
    /// `0x`/`0o`/`0b` base prefix or plain decimal, with an optional sign.
    ///
    /// Swift's `Int(_:radix:)` rejects `radix: 0` (it traps with "Radix not in
    /// range 2...36"), so the prefix has to be split off by hand.
    static func int(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let negative = trimmed.hasPrefix("-")
        let unsigned = (negative || trimmed.hasPrefix("+")) ? String(trimmed.dropFirst()) : trimmed
        let lowered = unsigned.lowercased()
        let radix: Int
        let digits: String
        switch true {
        case lowered.hasPrefix("0x"): (radix, digits) = (16, String(unsigned.dropFirst(2)))
        case lowered.hasPrefix("0o"): (radix, digits) = (8, String(unsigned.dropFirst(2)))
        case lowered.hasPrefix("0b"): (radix, digits) = (2, String(unsigned.dropFirst(2)))
        default: (radix, digits) = (10, unsigned)
        }
        guard let magnitude = Int(digits, radix: radix) else { return nil }
        return negative ? -magnitude : magnitude
    }
}
