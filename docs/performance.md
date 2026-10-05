# Performance and monitoring policy

usbscope treats connection state as dynamic and host metadata as stable.
Automatic refreshes therefore share one `SnapshotCoordinator` and use a
thread-safe `StableMetadataCache` for `SPHardwareDataType` (model and chip).
The cache is keyed by host and OS version, expires after one hour, and is never
used when a hardware read returned a warning or no value. Ports, devices,
interfaces, power, storage, Thunderbolt, and restriction data are collected on
each accepted refresh so a cached host descriptor cannot make live state stale.

The cache can be invalidated by the owning collector after a system update or
other explicit cold-read event. Fixture and CLI callers can pass `nil` or their
own cache to `SnapshotBuilder.collect`, which keeps tests deterministic and
preserves dependency injection.

Subprocess output is bounded by `Shell.Limits`; stdout and stderr are drained
concurrently, and a timeout returns a structured result. Event history is
bounded to 500 in-memory events and the on-disk event log rotates by size and
age. Diagnostic exports include per-source timings so a slow adapter can be
identified without profiling the UI.

The optional low-power profile is explicit and persisted with preferences. It
skips Thunderbolt and charging reads, leaves those fields unavailable, and
adds a visible source warning so reduced collection is never mistaken for a
complete snapshot. Balanced monitoring remains the default.
