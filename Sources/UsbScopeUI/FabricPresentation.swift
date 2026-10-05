import Foundation
import UsbScopeCore

/// What a flattened fabric row stands for.
public enum FabricRowKind: String, Sendable {
    case router
    case port
    case tunnel
}

/// One line of the USB4/Thunderbolt fabric tree, already flattened.
public struct FabricRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: FabricRowKind
    /// Indentation level: routers 0, their ports 1, tunnels below a port 2.
    public let depth: Int
    public let title: String
    public let detail: String
    /// The raw link enumerations of a port, verbatim (`speed … · width …`).
    public let rawLink: String?
}

/// The USB4/Thunderbolt fabric tab's presentation.
///
/// The link speeds and widths are the switch's own enumeration values: macOS
/// publishes them but not their encoding, so they are shown verbatim and the
/// note below says so — turning them into a Gbit/s number would be a guess.
/// Like the security note, `rawLinkNote` stays English because it documents a
/// technical limitation of the data, not the UI.
public enum FabricPresentation {
    public static let rawLinkNote =
        "Link speed and width are the raw enumerations the USB4 switch publishes; "
        + "macOS does not document their encoding, so they are shown verbatim instead of "
        + "being converted to Gbit/s."

    public static func rawLinkNote(_ language: AppLanguage) -> String {
        language == .de
            ? "Verbindungsrate und Breite sind die Roh-Aufzählungen des USB4-Switches; macOS dokumentiert ihre Codierung nicht, daher werden sie unverändert statt als Gbit/s angezeigt."
            : rawLinkNote
    }

    /// `speed cur/tgt/sup 2/2/2 · width cur/tgt/sup 1/1/1` for what is known.
    public static func linkText(_ port: ThunderboltFabricPort, language: AppLanguage = .en) -> String {
        var parts: [String] = []
        if let text = triplet(language == .de ? "Rate" : "speed", port.currentLinkSpeed, port.targetLinkSpeed, port.supportedLinkSpeed) {
            parts.append(text)
        }
        if let text = triplet(language == .de ? "Breite" : "width", port.currentLinkWidth, port.targetLinkWidth, port.supportedLinkWidth) {
            parts.append(text)
        }
        if let bandwidth = port.linkBandwidth { parts.append(language == .de ? "Bandbreite \(bandwidth)" : "bandwidth \(bandwidth)") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    private static func triplet(_ label: String, _ current: Int?, _ target: Int?, _ supported: Int?) -> String? {
        guard current != nil || target != nil || supported != nil else { return nil }
        func value(_ raw: Int?) -> String { raw.map(String.init) ?? "–" }
        return "\(label) cur/tgt/sup \(value(current))/\(value(target))/\(value(supported))"
    }

    /// A short identity for a router: model/vendor, or its IDs.
    public static func routerTitle(_ router: ThunderboltRouter, index: Int,
                                   language: AppLanguage = .en) -> String {
        let name = [router.vendorName, router.deviceModelName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let id = router.routerID.map { "#\($0)" } ?? "#\(index)"
        return name.isEmpty ? "Router \(id)" : "Router \(id) — \(name)"
    }

    /// The router's identity facts: depth, version, port/tunnel counts.
    public static func routerDetail(_ router: ThunderboltRouter, language: AppLanguage = .en) -> String {
        var parts: [String] = []
        if let depth = router.depth { parts.append(language == .de ? "Tiefe \(depth)" : "depth \(depth)") }
        if let version = router.thunderboltVersion { parts.append(language == .de ? "TB-Version \(version)" : "TB version \(version)") }
        if let uid = router.uid { parts.append("UID \(uid)") }
        parts.append(language == .de ? "\(router.ports.count) Anschlüsse" : "\(router.ports.count) port(s)")
        parts.append(language == .de ? "\(router.tunnels.count) Tunnel" : "\(router.tunnels.count) tunnel(s)")
        return parts.joined(separator: " · ")
    }

    public static func portTitle(_ port: ThunderboltFabricPort, language: AppLanguage = .en) -> String {
        let number = port.number.map { language == .de ? "Anschluss \($0)" : "Port \($0)" }
            ?? (language == .de ? "Anschluss" : "Port")
        return "\(number) · \(port.label) · \(port.protocolName)"
    }

    public static func portDetail(_ port: ThunderboltFabricPort, language: AppLanguage = .en) -> String {
        var parts: [String] = []
        if let socket = port.socketID, !socket.isEmpty { parts.append(language == .de ? "Buchse \(socket)" : "socket \(socket)") }
        if let lane = port.lane { parts.append(language == .de ? "Spur \(lane)" : "lane \(lane)") }
        if let adapter = port.adapterType { parts.append(language == .de ? "Adapter \(adapter)" : "adapter \(adapter)") }
        if let upstream = port.upstreamPortNumber { parts.append(language == .de ? "Upstream \(upstream)" : "upstream \(upstream)") }
        if port.restricted == true { parts.append(language == .de ? "eingeschränkt" : "restricted") }
        return parts.joined(separator: " · ")
    }

    public static func tunnelDetail(_ tunnel: ThunderboltTunnel, language: AppLanguage = .en) -> String {
        var parts: [String] = []
        if let driver = tunnel.driver, !driver.isEmpty { parts.append(driver) }
        if let driverClass = tunnel.driverClass, !driverClass.isEmpty { parts.append(driverClass) }
        if let deviceID = tunnel.deviceID, !deviceID.isEmpty { parts.append(language == .de ? "Gerät \(deviceID)" : "device \(deviceID)") }
        return parts.joined(separator: " · ")
    }

    /// Flatten the fabric into router → port → tunnel rows.
    ///
    /// A tunnel is nested under the port it names (`portNumber`); a tunnel whose
    /// port is not among the router's ports is listed once directly below the
    /// router, so nothing the switch reported is dropped.
    public static func rows(_ fabric: ThunderboltFabric, language: AppLanguage = .en) -> [FabricRow] {
        var rows: [FabricRow] = []
        for (index, router) in fabric.routers.enumerated() {
            rows.append(
                FabricRow(
                    id: "router:\(index)",
                    kind: .router,
                    depth: 0,
                    title: routerTitle(router, index: index, language: language),
                    detail: routerDetail(router, language: language),
                    rawLink: nil
                )
            )
            var nested = Set<Int>()
            for (portIndex, port) in router.ports.enumerated() {
                rows.append(
                    FabricRow(
                        id: "router:\(index):port:\(portIndex)",
                        kind: .port,
                        depth: 1,
                        title: portTitle(port, language: language),
                        detail: portDetail(port, language: language),
                        rawLink: linkText(port, language: language)
                    )
                )
                for (tunnelIndex, tunnel) in router.tunnels.enumerated()
                    where tunnel.portNumber != nil && tunnel.portNumber == port.number {
                    nested.insert(tunnelIndex)
                    rows.append(tunnelRow(tunnel, router: index, index: tunnelIndex, depth: 2, language: language))
                }
            }
            for (tunnelIndex, tunnel) in router.tunnels.enumerated() where !nested.contains(tunnelIndex) {
                rows.append(tunnelRow(tunnel, router: index, index: tunnelIndex, depth: 1, language: language))
            }
        }
        return rows
    }

    private static func tunnelRow(
        _ tunnel: ThunderboltTunnel, router: Int, index: Int, depth: Int,
        language: AppLanguage = .en
    ) -> FabricRow {
        FabricRow(
            id: "router:\(router):tunnel:\(index)",
            kind: .tunnel,
            depth: depth,
            title: "→ \(tunnel.protocolName): \(tunnel.label)",
            detail: tunnelDetail(tunnel, language: language),
            rawLink: nil
        )
    }

    /// `2 router(s) · 8 port(s) · 3 tunnel(s)`.
    public static func summary(_ fabric: ThunderboltFabric, language: AppLanguage = .en) -> String {
        if language == .de {
            return "\(fabric.routers.count) Router · \(fabric.ports.count) Anschlüsse · \(fabric.tunnels.count) Tunnel"
        }
        return "\(fabric.routers.count) router(s) · \(fabric.ports.count) port(s) · \(fabric.tunnels.count) tunnel(s)"
    }
}
