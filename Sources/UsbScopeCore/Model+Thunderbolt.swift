import Foundation

/// The Thunderbolt/USB4 *fabric* — the twin of `usbscope/models_thunderbolt.py`.
///
/// Where `ThunderboltPort` is the `system_profiler` view of a *receptacle* (one
/// physical socket with its status and cable capability), the fabric is the
/// `ioreg -c IOThunderboltSwitch` view of the USB4 *topology*: the switches
/// (routers) the host exposes, the ports of each router with the link facts the
/// switch publishes, and the down-adapter ports that carry a tunneled protocol
/// (PCIe, USB, DisplayPort). Both describe the same hardware from two angles and
/// are kept apart instead of being averaged.

/// A down-adapter port of a switch: the endpoint of a tunneled protocol.
///
/// `driver`/`driverClass`/`deviceID` come from the adapter node macOS publishes
/// below the port and name the kernel driver that terminates the tunnel.
/// Whether a tunnel is *established* is not part of this plane.
public struct ThunderboltTunnel: Equatable, Sendable {
    /// The stable protocol token (`thunderbolt`, `pcie`, `usb`, `displayport`,
    /// `unknown`); named `protocolName` because `protocol` is a Swift keyword.
    public var protocolName: String
    public var label: String
    public var portNumber: Int?
    public var adapterType: Int?
    public var driver: String?
    public var driverClass: String?
    public var deviceID: String?

    public init(
        protocolName: String, label: String, portNumber: Int? = nil, adapterType: Int? = nil,
        driver: String? = nil, driverClass: String? = nil, deviceID: String? = nil
    ) {
        self.protocolName = protocolName
        self.label = label
        self.portNumber = portNumber
        self.adapterType = adapterType
        self.driver = driver
        self.driverClass = driverClass
        self.deviceID = deviceID
    }
}

/// One `IOThunderboltPort` of a router, with the link facts it publishes.
///
/// The link speeds and widths are raw enumeration values of the switch: macOS
/// publishes them but not their encoding, so they are reported verbatim instead
/// of being turned into a Gbit/s number that would be a guess.
public struct ThunderboltFabricPort: Equatable, Sendable {
    public var label: String
    public var protocolName: String
    public var number: Int?
    public var socketID: String?
    public var adapterType: Int?
    public var currentLinkSpeed: Int?
    public var targetLinkSpeed: Int?
    public var supportedLinkSpeed: Int?
    public var currentLinkWidth: Int?
    public var targetLinkWidth: Int?
    public var supportedLinkWidth: Int?
    public var lane: Int?
    public var dualLinkPort: Int?
    public var linkBandwidth: Int?
    public var maxCredits: Int?
    public var maxInHopID: Int?
    public var maxOutHopID: Int?
    public var upstreamPortNumber: Int?
    public var restricted: Bool?

    public init(
        label: String, protocolName: String, number: Int? = nil, socketID: String? = nil,
        adapterType: Int? = nil, currentLinkSpeed: Int? = nil, targetLinkSpeed: Int? = nil,
        supportedLinkSpeed: Int? = nil, currentLinkWidth: Int? = nil, targetLinkWidth: Int? = nil,
        supportedLinkWidth: Int? = nil, lane: Int? = nil, dualLinkPort: Int? = nil,
        linkBandwidth: Int? = nil, maxCredits: Int? = nil, maxInHopID: Int? = nil,
        maxOutHopID: Int? = nil, upstreamPortNumber: Int? = nil, restricted: Bool? = nil
    ) {
        self.label = label
        self.protocolName = protocolName
        self.number = number
        self.socketID = socketID
        self.adapterType = adapterType
        self.currentLinkSpeed = currentLinkSpeed
        self.targetLinkSpeed = targetLinkSpeed
        self.supportedLinkSpeed = supportedLinkSpeed
        self.currentLinkWidth = currentLinkWidth
        self.targetLinkWidth = targetLinkWidth
        self.supportedLinkWidth = supportedLinkWidth
        self.lane = lane
        self.dualLinkPort = dualLinkPort
        self.linkBandwidth = linkBandwidth
        self.maxCredits = maxCredits
        self.maxInHopID = maxInHopID
        self.maxOutHopID = maxOutHopID
        self.upstreamPortNumber = upstreamPortNumber
        self.restricted = restricted
    }
}

/// One `IOThunderboltSwitch`: a USB4 router of the fabric.
///
/// A host router sits at `depth` 0 and a daisy-chained device at a higher depth.
/// `tunnels` lists the down-adapter ports of this router and is stored, not
/// derived, so its order matches the registry.
public struct ThunderboltRouter: Equatable, Sendable {
    public var routerID: Int?
    public var uid: Int?
    public var vendorID: Int?
    public var vendorName: String?
    public var deviceModelName: String?
    public var deviceModelID: Int?
    public var deviceModelRevision: Int?
    public var thunderboltVersion: Int?
    public var depth: Int?
    public var routeString: Int?
    public var maxPortNumber: Int?
    public var ports: [ThunderboltFabricPort] = []
    public var tunnels: [ThunderboltTunnel] = []

    public init(
        routerID: Int? = nil, uid: Int? = nil, vendorID: Int? = nil, vendorName: String? = nil,
        deviceModelName: String? = nil, deviceModelID: Int? = nil, deviceModelRevision: Int? = nil,
        thunderboltVersion: Int? = nil, depth: Int? = nil, routeString: Int? = nil,
        maxPortNumber: Int? = nil, ports: [ThunderboltFabricPort] = [],
        tunnels: [ThunderboltTunnel] = []
    ) {
        self.routerID = routerID
        self.uid = uid
        self.vendorID = vendorID
        self.vendorName = vendorName
        self.deviceModelName = deviceModelName
        self.deviceModelID = deviceModelID
        self.deviceModelRevision = deviceModelRevision
        self.thunderboltVersion = thunderboltVersion
        self.depth = depth
        self.routeString = routeString
        self.maxPortNumber = maxPortNumber
        self.ports = ports
        self.tunnels = tunnels
    }
}

/// Every router macOS exposes, in registry order (host routers first).
public struct ThunderboltFabric: Equatable, Sendable {
    public var routers: [ThunderboltRouter] = []

    public init(routers: [ThunderboltRouter] = []) {
        self.routers = routers
    }

    /// All ports of all routers, in router order.
    public var ports: [ThunderboltFabricPort] { routers.flatMap(\.ports) }

    /// All tunnel endpoints of all routers, in router order.
    public var tunnels: [ThunderboltTunnel] { routers.flatMap(\.tunnels) }
}
