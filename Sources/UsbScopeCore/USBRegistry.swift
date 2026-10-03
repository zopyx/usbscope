import Foundation

/// Adapter for the USB device tree (`ioreg -p IOUSB`) — the twin of
/// `usbscope/sources/usbregistry.py`.
///
/// Where `system_profiler` names a device and `ioreg -p IOPort` describes the
/// *receptacle*, this plane carries what the device itself reports to the host
/// controller: the USB descriptor basics (`bDeviceClass`/`SubClass`/`Protocol`,
/// `bcdUSB`, `bMaxPacketSize0`, `bNumConfigurations`), the enumeration speed
/// code, the address and — from the tree shape — the hub tier and parent hub.
///
/// The full interface/endpoint descriptor tree is not here (it needs an
/// `IOUSBHostDevice` user client), so a class of `0` is reported as
/// `per-interface` instead of guessed.
public enum USBRegistry {
    /// USB-IF base class codes (USB 2.0 spec, table 9-6) plus the vendor ranges.
    public static let classNames: [Int: String] = [
        0x00: "per-interface", 0x01: "audio", 0x02: "communications", 0x03: "HID",
        0x05: "physical", 0x06: "image", 0x07: "printer", 0x08: "mass storage",
        0x09: "hub", 0x0A: "CDC data", 0x0B: "smart card", 0x0C: "content security",
        0x0D: "video", 0x0E: "health", 0x0F: "audio/video", 0x10: "billboard",
        0x11: "USB bridge", 0xDC: "diagnostic", 0xE0: "wireless", 0xEF: "miscellaneous",
        0xFE: "application specific", 0xFF: "vendor specific",
    ]

    /// `Device Speed` / `USBSpeed` enumeration of the host controller stack.
    static let speedCodes: [Int: String] = [
        0: "low_speed", 1: "full_speed", 2: "high_speed", 3: "super_speed",
        4: "super_speed_plus",
    ]

    static let deviceMarkers = ["bDeviceClass", "UsbDeviceSignature", "Device Speed"]
    static let noise: Set<String> = ["IORegistryEntryChildren", "IOObjectClass", "IOClass", "IONameMatch"]

    public static func className(_ value: Int?) -> String? {
        guard let value else { return nil }
        return classNames[value] ?? String(format: "0x%02x", value)
    }

    public static func speedCodeName(_ value: Int?) -> String? {
        guard let value else { return nil }
        return speedCodes[value] ?? "code \(value)"
    }

    /// `512` (`0x0200`) → `2.00`, the USB specification version.
    public static func bcdUsb(_ value: Int?) -> String? {
        guard let value, value > 0 else { return nil }
        return "\(value >> 8).\((value >> 4) & 0xF)\(value & 0xF)"
    }

    static func isDevice(_ node: [String: Any]) -> Bool {
        deviceMarkers.contains { node[$0] != nil }
    }

    static func name(_ node: [String: Any]) -> String? {
        (node["USB Product Name"] as? String) ?? (node["IORegistryEntryName"] as? String)
    }

    static func parseDevice(_ node: [String: Any], tier: Int, parent: String?) -> UsbDevice {
        let deviceClass = IOReg.int(node["bDeviceClass"])
        let bits = IOReg.int(node["UsbLinkSpeed"])
        let speedMbps = (bits != nil && bits! > 100_000) ? (Double(bits!) / 1_000_000).rounded() : nil
        let bcdDevice = IOReg.int(node["bcdDevice"])
        return UsbDevice(
            name: name(node) ?? "unknown device",
            vendor: IOReg.text(node["USB Vendor Name"]),
            vendorID: IOReg.int(node["idVendor"]),
            productID: IOReg.int(node["idProduct"]),
            locationID: IOReg.int(node["locationID"]),
            speedText: speedMbps.map { "\(Int($0)) Mbit/s" },
            speedMbps: speedMbps,
            connection: (node["UserInstallable"] as? Bool) == true ? "Removable" : nil,
            version: bcdDevice.map { String(format: "0x%04x", $0) },
            source: "ioreg-usb",
            deviceClass: deviceClass,
            deviceSubclass: IOReg.int(node["bDeviceSubClass"]),
            deviceProtocol: IOReg.int(node["bDeviceProtocol"]),
            className: className(deviceClass),
            bcdUsb: bcdUsb(IOReg.int(node["bcdUSB"])),
            maxPacketSize0: IOReg.int(node["bMaxPacketSize0"]),
            numConfigurations: IOReg.int(node["bNumConfigurations"]),
            speedCode: IOReg.int(node["Device Speed"]),
            tier: tier,
            parent: parent,
            address: IOReg.int(node["kUSBAddress"]) ?? IOReg.int(node["USB Address"])
        )
    }

    /// Collect every device node with its tier and the hub it hangs off.
    ///
    /// A device directly on a controller is tier 1; behind a hub, tier 2, and so
    /// on (`UsbHostControllerTierLimit` is 6 on Apple silicon).
    private static func collect(
        _ node: [String: Any], depth: Int, parent: String?, into out: inout [UsbDevice]
    ) {
        for child in IOReg.children(node) {
            if isDevice(child) {
                out.append(parseDevice(child, tier: depth + 1, parent: parent))
                collect(child, depth: depth + 1, parent: name(child), into: &out)
            } else {
                collect(child, depth: depth, parent: parent, into: &out)
            }
        }
    }

    /// Translate a parsed `-p IOUSB` plist into devices.
    public static func devices(in tree: [String: Any]) -> [UsbDevice] {
        var out: [UsbDevice] = []
        collect(tree, depth: 0, parent: nil, into: &out)
        return out
    }

    public static let binary = Shell.systemBinary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")
}

/// Reads the USB device tree the host controllers publish.
public struct USBRegistrySource: Sendable {
    private let run: Runner

    public init(runner: Runner? = nil) {
        self.run = runner ?? { Shell.run($0) }
    }

    /// The parsed `IOUSB` plane and an optional warning.
    public func tree() -> ([String: Any]?, String?) {
        let result = run([USBRegistry.binary, "-a", "-l", "-w0", "-p", "IOUSB"])
        guard result.ok else { return (nil, result.error ?? "ioreg failed") }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: result.stdout, options: [], format: nil
        ) as? [String: Any] else {
            return (nil, "ioreg returned unparsable output")
        }
        return (plist, nil)
    }

    /// The devices of the USB tree plus any non-fatal warnings.
    ///
    /// Unlike the port controller, an empty tree is not a problem: a Mac with
    /// nothing plugged in reports no `IOUSBHostDevice` at all.
    public func devices() -> ([UsbDevice], [String]) {
        let (tree, warning) = tree()
        guard let tree else { return ([], warning.map { [$0] } ?? []) }
        return (USBRegistry.devices(in: tree), [])
    }
}
