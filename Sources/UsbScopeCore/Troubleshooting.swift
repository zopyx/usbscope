import Foundation

public enum DiagnosticScenario: String, Codable, Sendable, CaseIterable {
    case slowConnection, chargeOnlyConnection, deviceMissing, restrictedDevice
}

public struct DiagnosticRecommendation: Codable, Sendable, Equatable {
    public let title: String
    public let action: String
    public let evidence: [String]

    public init(title: String, action: String, evidence: [String]) {
        self.title = title; self.action = action; self.evidence = evidence
    }
}

public struct DiagnosticEvaluation: Codable, Sendable, Equatable {
    public let scenario: DiagnosticScenario
    public let outcome: DataState
    public let summary: String
    public let recommendations: [DiagnosticRecommendation]

    public init(scenario: DiagnosticScenario, outcome: DataState, summary: String,
                recommendations: [DiagnosticRecommendation]) {
        self.scenario = scenario; self.outcome = outcome; self.summary = summary
        self.recommendations = recommendations
    }
}

/// Evidence-based troubleshooting guidance. It deliberately reports unknown
/// when the snapshot cannot support a conclusion and never claims certainty.
public enum Troubleshooting {
    public static func evaluate(_ scenario: DiagnosticScenario, snapshot: Snapshot) -> DiagnosticEvaluation {
        let connected = snapshot.connectedPorts
        switch scenario {
        case .slowConnection:
            let slow = connected.filter { $0.usbTransport?.mode.rank ?? 0 <= UsbMode.highSpeed.rank }
            let evidence = slow.map { "\($0.name): negotiated \($0.mode.label)" }
            return DiagnosticEvaluation(scenario: scenario, outcome: slow.isEmpty ? .unknown : .present,
                summary: slow.isEmpty ? "No connected port has enough data to identify a slow link." : "One or more connected links are negotiated at a lower mode.",
                recommendations: slow.isEmpty ? [] : [DiagnosticRecommendation(title: "Check the link", action: "Try a known-good cable and connect directly to the Mac; compare the negotiated mode after refresh.", evidence: evidence)])
        case .chargeOnlyConnection:
            let chargeOnly = connected.filter { !$0.transports.contains(where: { $0.active && ["USB2", "USB3", "USB4"].contains($0.kind) }) }
            let evidence = chargeOnly.map { "\($0.name): no active USB data transport" }
            return DiagnosticEvaluation(scenario: scenario, outcome: chargeOnly.isEmpty ? .unknown : .present,
                summary: chargeOnly.isEmpty ? "The snapshot does not identify a charge-only connection." : "A connected port has no active USB data transport.",
                recommendations: chargeOnly.isEmpty ? [] : [DiagnosticRecommendation(title: "Check cable and accessory mode", action: "Try another data-capable cable, remove intermediate hubs, and refresh.", evidence: evidence)])
        case .deviceMissing:
            let evidence = connected.map { "\($0.name): connected=\($0.connected)" }
            return DiagnosticEvaluation(scenario: scenario, outcome: connected.isEmpty ? .unknown : .present,
                summary: connected.isEmpty ? "No connected port was reported; the missing device cannot be localized." : "The snapshot contains connected ports; no missing object can be inferred without a target.",
                recommendations: [DiagnosticRecommendation(title: "Refresh and inspect the port", action: "Reconnect directly, refresh, and compare the port and device counts with a baseline.", evidence: evidence)])
        case .restrictedDevice:
            let restricted = snapshot.devices.filter { $0.restricted == true } + connected.flatMap { $0.devices.filter { $0.restricted == true } }
            let evidence = restricted.map { "\($0.label): macOS reports restricted" }
            return DiagnosticEvaluation(scenario: scenario, outcome: restricted.isEmpty ? .unknown : .present,
                summary: restricted.isEmpty ? "macOS did not report a restricted device in this snapshot." : "macOS reports one or more restricted devices.",
                recommendations: restricted.isEmpty ? [] : [DiagnosticRecommendation(title: "Review the restriction", action: "Inspect the device’s authorization and transport details; reconnect only if you trust the accessory.", evidence: evidence)])
        }
    }
}
