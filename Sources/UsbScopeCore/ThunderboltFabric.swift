import Foundation

/// Adapter for the USB4/Thunderbolt fabric (`ioreg -c IOThunderboltSwitch`) —
/// the twin of `usbscope/sources/thunderbolt.py`.
///
/// `ioreg -r -c IOThunderboltSwitch -a -l -w0` returns every USB4 router the host
/// publishes: the switches (host routers and, when a device is daisy chained,
/// downstream routers), their ports with the link facts the switch reports and —
/// below the adapter ports — the kernel driver nodes that terminate a tunneled
/// protocol (PCIe, USB, DisplayPort).
///
/// The plist is parsed straight from stdout: no entitlements, no private
/// framework, no sudo. `ioreg -p IOThunderbolt` (the plane root) carries only
/// plane metadata and no routers, so the class query is what usbscope uses.
public enum ThunderboltSwitch {
    static let switchClassPrefix = "IOThunderboltSwitch"
    static let portClass = "IOThunderboltPort"

    /// `Description` values macOS uses for a port of a switch, mapped to a
    /// stable token. Anything else stays `unknown` instead of being guessed from
    /// the raw `Adapter Type` bitfield, whose encoding is not public.
    static let protocolByLabel: [String: String] = [
        "thunderbolt port": "thunderbolt",
        "pcie adapter": "pcie",
        "usb adapter": "usb",
        "dp or hdmi adapter": "displayport",
    ]

    /// Stable protocol token of a switch port (`thunderbolt`, `pcie`, …).
    public static func protocolKind(_ label: String?) -> String {
        guard let label else { return "unknown" }
        let key = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return protocolByLabel[key] ?? "unknown"
    }

    static func ioClass(_ node: [String: Any]) -> String {
        (node["IOObjectClass"] as? String) ?? ""
    }

    static func isSwitch(_ node: [String: Any]) -> Bool {
        ioClass(node).hasPrefix(switchClassPrefix)
    }

    static func isPort(_ node: [String: Any]) -> Bool {
        ioClass(node) == portClass
    }

    static func portChildren(_ node: [String: Any]) -> [[String: Any]] {
        IOReg.children(node).filter(isPort)
    }

    /// The driver node macOS publishes below a tunneled port, if any.
    ///
    /// A native Thunderbolt link port has no child; a PCIe/USB/DisplayPort port
    /// carries exactly one adapter node. A daisy-chained router appears as a
    /// switch child instead, so switches are never mistaken for an adapter.
    static func adapterNode(_ portNode: [String: Any]) -> [String: Any]? {
        IOReg.children(portNode).first { !isPort($0) && !isSwitch($0) }
    }

    /// Build the tunnel endpoint of a port, or `nil` for a native link port.
    ///
    /// A tunnel requires the adapter driver node as evidence; the protocol token
    /// is the port's own label. A vendor adapter with an unknown label therefore
    /// shows up as a tunnel of protocol `unknown` instead of being dropped.
    static func tunnel(_ port: ThunderboltFabricPort, _ node: [String: Any]) -> ThunderboltTunnel? {
        guard let adapter = adapterNode(node) else { return nil }
        return ThunderboltTunnel(
            protocolName: port.protocolName,
            label: port.label,
            portNumber: port.number,
            adapterType: port.adapterType,
            driver: IOReg.text(adapter["CFBundleIdentifier"]),
            driverClass: IOReg.text(adapter["IOObjectClass"]),
            deviceID: IOReg.text(adapter["Device ID"])
        )
    }

    static func parsePort(_ node: [String: Any]) -> ThunderboltFabricPort {
        let label = IOReg.text(node["Description"]) ?? "?"
        return ThunderboltFabricPort(
            label: label,
            protocolName: protocolKind(label),
            number: IOReg.int(node["Port Number"]),
            socketID: IOReg.text(node["Socket ID"]),
            adapterType: IOReg.int(node["Adapter Type"]),
            currentLinkSpeed: IOReg.int(node["Current Link Speed"]),
            targetLinkSpeed: IOReg.int(node["Target Link Speed"]),
            supportedLinkSpeed: IOReg.int(node["Supported Link Speed"]),
            currentLinkWidth: IOReg.int(node["Current Link Width"]),
            targetLinkWidth: IOReg.int(node["Target Link Width"]),
            supportedLinkWidth: IOReg.int(node["Supported Link Width"]),
            lane: IOReg.int(node["Lane"]),
            dualLinkPort: IOReg.int(node["Dual-Link Port"]),
            linkBandwidth: IOReg.int(node["Link Bandwidth"]),
            maxCredits: IOReg.int(node["Max Credits"]),
            maxInHopID: IOReg.int(node["Max In Hop ID"]),
            maxOutHopID: IOReg.int(node["Max Out Hop ID"]),
            upstreamPortNumber: IOReg.int(node["Upstream Port Number"]),
            restricted: IOReg.bool(node["TRM Transport Restricted"])
        )
    }

    static func parseRouter(_ node: [String: Any]) -> ThunderboltRouter {
        var ports: [ThunderboltFabricPort] = []
        var tunnels: [ThunderboltTunnel] = []
        for portNode in portChildren(node) {
            let port = parsePort(portNode)
            ports.append(port)
            if let tunnel = tunnel(port, portNode) { tunnels.append(tunnel) }
        }
        return ThunderboltRouter(
            routerID: IOReg.int(node["Router ID"]),
            uid: IOReg.int(node["UID"]),
            vendorID: IOReg.int(node["Vendor ID"]),
            vendorName: IOReg.text(node["Device Vendor Name"]),
            deviceModelName: IOReg.text(node["Device Model Name"]),
            deviceModelID: IOReg.int(node["Device Model ID"]),
            deviceModelRevision: IOReg.int(node["Device Model Revision"]),
            thunderboltVersion: IOReg.int(node["Thunderbolt Version"]),
            depth: IOReg.int(node["Depth"]),
            routeString: IOReg.int(node["Route String"]),
            maxPortNumber: IOReg.int(node["Max Port Number"]),
            ports: ports,
            tunnels: tunnels
        )
    }

    /// Every switch node at or below `node`, host routers first.
    ///
    /// A daisy-chained router hangs below a port of its upstream router, so the
    /// walk descends through the ports to find it.
    static func collectSwitches(_ node: [String: Any], into out: inout [ThunderboltRouter]) {
        if isSwitch(node) {
            out.append(parseRouter(node))
            for portNode in portChildren(node) {
                for child in IOReg.children(portNode) { collectSwitches(child, into: &out) }
            }
            return
        }
        for child in IOReg.children(node) { collectSwitches(child, into: &out) }
    }

    /// Translate a parsed `-c IOThunderboltSwitch` plist into the fabric.
    public static func parse(_ payload: Any) -> ThunderboltFabric {
        let entries: [Any] = (payload as? [Any]) ?? [payload]
        var routers: [ThunderboltRouter] = []
        for entry in entries {
            guard let node = entry as? [String: Any] else { continue }
            collectSwitches(node, into: &routers)
        }
        return ThunderboltFabric(routers: routers)
    }

    public static let binary = Shell.systemBinary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")
}

/// Reads the USB4/Thunderbolt fabric the switches publish.
public struct ThunderboltFabricSource: Sendable {
    private let run: Runner

    public init(runner: Runner? = nil) {
        self.run = runner ?? { Shell.run($0) }
    }

    /// The parsed `IOThunderboltSwitch` payload and an optional warning.
    public func tree() -> (Any?, String?) {
        let result = run([ThunderboltSwitch.binary, "-r", "-c", "IOThunderboltSwitch", "-a", "-l", "-w0"])
        guard result.ok else { return (nil, result.error ?? "ioreg failed") }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: result.stdout, options: [], format: nil
        ) else {
            return (nil, "ioreg returned unparsable output")
        }
        guard plist is [String: Any] || plist is [Any] else {
            return (nil, "ioreg returned an unexpected structure")
        }
        return (plist, nil)
    }

    /// The fabric of the machine plus any non-fatal warnings.
    ///
    /// An empty result is not a failure: a Mac without Thunderbolt reports no
    /// switch at all, so it yields an empty fabric and no warning.
    public func fabric() -> (ThunderboltFabric, [String]) {
        let (tree, warning) = tree()
        guard let tree else { return (ThunderboltFabric(), warning.map { [$0] } ?? []) }
        return (ThunderboltSwitch.parse(tree), [])
    }
}
