import Foundation

/// A stable, user-facing interpretation of adapter warnings. The raw text is
/// retained as the technical diagnostic so no information is lost.
public struct WarningRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: String
    public let severity: String
    public let field: String
    public let message: String
    public let remediation: String
    public let technical: String
}

public enum WarningPresentation {
    public static func rows(_ warnings: [String]) -> [WarningRow] {
        warnings.enumerated().map { index, warning in
            let parts = warning.split(separator: ":", maxSplits: 1).map(String.init)
            let source = parts.first?.isEmpty == false ? parts[0] : "unknown"
            let message = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : warning
            let field = message.split(separator: " ", maxSplits: 1).first.map(String.init) ?? "source"
            let failed = message.localizedCaseInsensitiveContains("failed") || message.localizedCaseInsensitiveContains("invalid")
            return WarningRow(id: "warning:\(index):\(warning)", source: source,
                              severity: failed ? "failed" : "partial", field: field,
                              message: message,
                              remediation: failed ? "Retry the read or use a supported direct bundle."
                                : "Review the affected field and export diagnostics if it persists.",
                              technical: warning)
        }
    }
}
