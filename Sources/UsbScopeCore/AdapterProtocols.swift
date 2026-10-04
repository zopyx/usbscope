import Foundation

/// Injectable boundaries for every operating-system data source.
///
/// Production adapters conform directly; tests and future sandbox-specific
/// implementations can provide fixture doubles without launching a process or
/// touching IOKit. The tuple shapes intentionally match the existing adapter
/// APIs so this is additive and source-compatible.
public protocol ProfilerAdapter: Sendable {
    func usbBuses() -> ([Bus], [String])
    func thunderbolt() -> ([ThunderboltPort], [String])
    func hardware() -> (model: String?, chip: String?, warnings: [String])
}

public protocol IOPortAdapter: Sendable {
    func ports() -> ([UsbPort], [String])
}

public protocol InterfaceAdapter: Sendable {
    func interfaces() -> ([Int: [DeviceInterface]], [String])
}

public protocol ChargingAdapter: Sendable {
    func charging() -> (Charging?, [String])
}

public protocol USBRegistryAdapter: Sendable {
    func devices() -> ([UsbDevice], [String])
}

public protocol ThunderboltFabricAdapter: Sendable {
    func fabric() -> (ThunderboltFabric, [String])
}

public protocol StorageAdapter: Sendable {
    func inventoryResult(clock: @Sendable () -> Date) -> StorageInventory
}

extension SystemProfiler: ProfilerAdapter {}
extension IoregSource: IOPortAdapter {}
extension USBInterfaceSource: InterfaceAdapter {}
extension ChargingSource: ChargingAdapter {}
extension USBRegistrySource: USBRegistryAdapter {}
extension ThunderboltFabricSource: ThunderboltFabricAdapter {}
extension StorageSource: StorageAdapter {}
