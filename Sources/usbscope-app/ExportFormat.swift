import Foundation

/// Typed dispatch for the app's table exports.
enum ExportFormat: String, CaseIterable, Sendable {
    case json
    case csv
}
