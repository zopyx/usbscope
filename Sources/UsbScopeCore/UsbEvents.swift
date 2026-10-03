import Foundation

#if canImport(IOKit)
import IOKit
#endif

/// One hotplug edge: a USB device appeared or went away.
///
/// The identity (`key`) is the same string the table rows and the change
/// highlighter use — `UsbScopeCore.deviceKey` — so an event can be matched
/// against a row and the log stays comparable with the differ.
public enum UsbEventKind: String, Codable, Sendable {
    case attached
    case detached
}

/// A recorded attach/detach event, with the device identity of that moment.
public struct UsbEvent: Codable, Sendable, Equatable {
    public var kind: UsbEventKind
    public var seenAt: Date
    /// Stable device identity — `deviceKey(device)` at the time of the event.
    public var key: String
    public var name: String
    public var vendor: String?
    public var vendorID: Int?
    public var productID: Int?
    public var locationID: Int?
    public var serial: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case seenAt = "seen_at"
        case key, name, vendor, serial
        case vendorID = "vendor_id"
        case productID = "product_id"
        case locationID = "location_id"
    }

    public init(kind: UsbEventKind, seenAt: Date, device: UsbDevice) {
        self.kind = kind
        self.seenAt = seenAt
        self.key = deviceKey(device)
        self.name = device.name
        self.vendor = device.vendor
        self.vendorID = device.vendorID
        self.productID = device.productID
        self.locationID = device.locationID
        self.serial = device.serial
    }

    public init(
        kind: UsbEventKind, seenAt: Date, key: String, name: String, vendor: String? = nil,
        vendorID: Int? = nil, productID: Int? = nil, locationID: Int? = nil, serial: String? = nil
    ) {
        self.kind = kind
        self.seenAt = seenAt
        self.key = key
        self.name = name
        self.vendor = vendor
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.serial = serial
    }
}

/// Turn a `ChangeSet` into ordered attach/detach events.
///
/// Removals come first, then attachments, and each group is sorted by device
/// key: a `ChangeSet` is built from dictionaries, so its order is not stable
/// across processes — the log and its tests need a deterministic one.
public func usbEvents(_ changes: ChangeSet, at: Date) -> [UsbEvent] {
    let detached = changes.removed.map { UsbEvent(kind: .detached, seenAt: at, device: $0) }
        .sorted { $0.key < $1.key }
    let attached = changes.added.map { UsbEvent(kind: .attached, seenAt: at, device: $0) }
        .sorted { $0.key < $1.key }
    return detached + attached
}

/// Diff two snapshots and describe the device edges between them.
public func usbEvents(from previous: Snapshot?, to current: Snapshot, at: Date) -> [UsbEvent] {
    usbEvents(diffSnapshots(previous: previous, current: current), at: at)
}

/// A hotplug watcher on `IOUSBHostDevice`.
///
/// **How it detects a hotplug.** The edge is genuinely event-driven: the watcher
/// arms two IOKit notifications — `kIOMatchedNotification` and
/// `kIOTerminatedNotification` — on the `IOUSBHostDevice` class through
/// `IOServiceAddMatchingNotification`, on a dedicated run-loop thread. Between
/// edges it does *nothing*; no timer is involved on the normal path.
///
/// **Why the identity comes from a snapshot diff.** IOKit's notification hands
/// over the `io_service_t`, but the terminating notification of a device that is
/// going away does not reliably expose its properties any more, so a key read
/// straight from the service would not be stable between the attach and the
/// detach of the same device. The watcher therefore resolves the edge the same
/// way the app does: it collects one snapshot and diffs it against the previous
/// one (`diffSnapshots`), which yields the exact `deviceKey` both sides agree
/// on. Only the *trigger* is event-driven — the identity resolution is one
/// triggered snapshot read, never a background poll.
///
/// **Polling fallback.** `Mode.polling` (and `Mode.automatic` when IOKit cannot
/// be armed, e.g. inside the App Store sandbox) instead compares snapshots on a
/// `DispatchSourceTimer` at `pollInterval`. `isEventDriven` and `status` say
/// which path is actually active, so a caller is never left guessing.
public final class UsbHotplugWatcher: @unchecked Sendable {
    public enum Mode: Sendable {
        /// IOKit notifications when they can be armed, otherwise polling.
        case automatic
        /// IOKit notifications only; never polls.
        case ioKit
        /// Always polls the snapshot differ (the documented fallback).
        case polling
    }

    /// One detection result: the fresh snapshot, its diff and the device edges.
    public struct Update: Sendable {
        public var snapshot: Snapshot
        public var changes: ChangeSet
        public var events: [UsbEvent]
        public var at: Date
    }

    public typealias Handler = @Sendable (Update) -> Void

    /// The IOKit class the notifications match.
    public static let deviceClass = "IOUSBHostDevice"

    public let mode: Mode
    public let pollInterval: TimeInterval
    public let debounce: TimeInterval

    private let collect: @Sendable () -> Snapshot
    private let clock: @Sendable () -> Date
    private let queue = DispatchQueue(label: "com.zopyx.usbscope.hotplug")
    private let lock = NSLock()

    private var _running = false
    private var _isEventDriven = false
    private var _status = "idle"
    private var _previous: Snapshot?
    private var _handler: Handler?
    private var pending: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?

    #if canImport(IOKit)
    private var port: IONotificationPortRef?
    private var runLoop: CFRunLoop?
    private var attachIterator: io_iterator_t = 0
    private var detachIterator: io_iterator_t = 0
    #endif

    public init(
        mode: Mode = .automatic,
        pollInterval: TimeInterval = 2.0,
        debounce: TimeInterval = 0.15,
        collect: @escaping @Sendable () -> Snapshot = { SnapshotBuilder.collect() },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mode = mode
        self.pollInterval = max(pollInterval, 0.01)
        self.debounce = max(debounce, 0)
        self.collect = collect
        self.clock = clock
    }

    /// True when IOKit notifications are the active source (never set by polling).
    public var isEventDriven: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEventDriven
    }

    /// Human readable description of the active source.
    public var status: String {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _running
    }

    /// Start watching.
    ///
    /// `seed` is the snapshot the first diff is measured against (e.g. the
    /// snapshot the app already has). When it is `nil` the watcher collects one
    /// baseline in the background; a baseline read never reports an event, so
    /// "the first read is not a plug event" holds here too. `handler` runs on
    /// the watcher's own serial queue and only fires when something changed.
    public func start(seed: Snapshot? = nil, _ handler: @escaping Handler) {
        lock.lock()
        guard !_running else { lock.unlock(); return }
        _running = true
        _handler = handler
        _previous = seed
        lock.unlock()

        let armed: Bool
        switch mode {
        case .ioKit:
            armed = startIOKit()
        case .polling:
            armed = false
        case .automatic:
            armed = startIOKit()
        }

        if armed {
            setSource(eventDriven: true, status: "IOKit notifications · \(Self.deviceClass)")
        } else if mode == .ioKit {
            setSource(eventDriven: false, status: "IOKit unavailable — not watching")
        } else {
            startPolling()
            setSource(
                eventDriven: false,
                status: "polling every \(format(pollInterval)) s (IOKit unavailable)"
            )
        }

        // Establish the baseline, and (while polling) kick the first comparison.
        if seed == nil || !armed {
            queue.async { [weak self] in self?.process() }
        }
    }

    public func stop() {
        lock.lock()
        guard _running else { lock.unlock(); return }
        _running = false
        _handler = nil
        _status = "stopped"
        _isEventDriven = false
        let timer = pollTimer
        pollTimer = nil
        let item = pending
        pending = nil
        #if canImport(IOKit)
        let runLoop = self.runLoop
        #else
        let runLoop: CFRunLoop? = nil
        #endif
        lock.unlock()

        timer?.cancel()
        item?.cancel()
        if let runLoop {
            // Waking and stopping from another thread is the documented pattern.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    // MARK: - Detection pipeline

    /// One comparison of a fresh snapshot against the previous one.
    private func process() {
        lock.lock()
        guard _running, let handler = _handler else { lock.unlock(); return }
        let previous = _previous
        lock.unlock()

        // Slow (it shells out), so never under the lock.
        let snapshot = collect()
        let at = clock()
        let changes = diffSnapshots(previous: previous, current: snapshot)

        lock.lock()
        _previous = snapshot
        let stillRunning = _running
        lock.unlock()
        guard stillRunning else { return }
        guard !changes.isEmpty else { return }  // quiet refresh: no handler churn
        handler(Update(snapshot: snapshot, changes: changes, events: usbEvents(changes, at: at), at: at))
    }

    /// Debounced signal from the IOKit callback: coalesces a burst of edges (a
    /// hub that brings five devices) into a single comparison.
    fileprivate func signal() {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.lock.lock()
            self.pending?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.process() }
            self.pending = item
            self.lock.unlock()
            self.queue.asyncAfter(deadline: .now() + self.debounce, execute: item)
        }
    }

    private func setSource(eventDriven: Bool, status: String) {
        lock.lock()
        _isEventDriven = eventDriven
        _status = status
        lock.unlock()
    }

    private func format(_ value: TimeInterval) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Polling fallback

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.process() }
        timer.resume()
        lock.lock()
        pollTimer = timer
        lock.unlock()
    }

    // MARK: - IOKit notifications

    #if canImport(IOKit)
    /// Whether this platform offers the IOKit notification API at all.
    static var ioKitAvailable: Bool {
        // A matching dictionary is the cheapest way to prove IOKit answers.
        IOServiceMatching(deviceClass) != nil
    }

    /// Spawn the run-loop thread and arm the notifications there.
    ///
    /// The semaphore makes the arm result synchronous, so `isEventDriven` is
    /// already correct when `start` returns. The thread keeps the watcher alive
    /// (it captures `self` strongly) — `stop()` is what ends it.
    private func startIOKit() -> Bool {
        guard Self.ioKitAvailable else { return false }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let armed = armIOKit()
            ready.signal()
            guard armed else { return }
            CFRunLoopRun()
            teardownIOKit()
        }
        thread.name = "com.zopyx.usbscope.hotplug.iokit"
        thread.stackSize = 256 * 1024
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return isEventDriven
    }

    /// Arm both notifications on the current (dedicated) run-loop thread.
    private func armIOKit() -> Bool {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

        let refCon = Unmanaged.passUnretained(self).toOpaque()
        var attach: io_iterator_t = 0
        var detach: io_iterator_t = 0
        let attachResult = IOServiceAddMatchingNotification(
            port, kIOMatchedNotification, IOServiceMatching(Self.deviceClass),
            usbHotplugCallback, refCon, &attach
        )
        let detachResult = IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, IOServiceMatching(Self.deviceClass),
            usbHotplugCallback, refCon, &detach
        )
        guard attachResult == KERN_SUCCESS, detachResult == KERN_SUCCESS else {
            if attach != 0 { IOObjectRelease(attach) }
            if detach != 0 { IOObjectRelease(detach) }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            IONotificationPortDestroy(port)
            return false
        }
        // Both iterators arrive pre-filled with the devices present *now*; drain
        // them so the first callback reports a real edge, not the initial state.
        drain(attach)
        drain(detach)

        lock.lock()
        self.port = port
        self.runLoop = CFRunLoopGetCurrent()
        self.attachIterator = attach
        self.detachIterator = detach
        _isEventDriven = true
        lock.unlock()
        return true
    }

    /// Release the notifications after the run loop returned.
    private func teardownIOKit() {
        lock.lock()
        let port = self.port
        let attach = attachIterator
        let detach = detachIterator
        self.port = nil
        self.runLoop = nil
        self.attachIterator = 0
        self.detachIterator = 0
        lock.unlock()
        guard let port else { return }
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        if attach != 0 { IOObjectRelease(attach) }
        if detach != 0 { IOObjectRelease(detach) }
        IONotificationPortDestroy(port)
    }

    /// Consume every service an iterator holds (mandatory: an undrained iterator
    /// is never signalled again).
    private func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
    #else
    static var ioKitAvailable: Bool { false }
    private func startIOKit() -> Bool { false }
    #endif
}

#if canImport(IOKit)
/// The C callback of both notifications: drain the iterator, then wake the watcher.
private func usbHotplugCallback(_ refCon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    while case let service = IOIteratorNext(iterator), service != 0 {
        IOObjectRelease(service)
    }
    guard let refCon else { return }
    Unmanaged<UsbHotplugWatcher>.fromOpaque(refCon).takeUnretainedValue().signal()
}
#endif
