# JSON schema changelog

The machine readable snapshot (`usbscope --json`) carries a top-level
`schema_version`. Consumers may rely on it; it changes only when existing keys
change meaning or disappear.

Rules:

* **Additive** keys (new fields on existing objects, new objects) do **not** bump
  the version — a reader that ignores unknown keys keeps working.
* **Breaking** changes (removing a key, changing a key's type or meaning) bump
  `schema_version` and are listed here.
* The constant lives in `Sources/UsbScopeCore/Serialize.swift`
  (`Serialize.schemaVersion`); a test asserts it agrees with the head of this
  file.

| Version | Change |
| --- | --- |
| 1 | First published schema: `snapshot`, `ports`, `buses`, `thunderbolt`, `charging`, `warnings`. |

Notable **additive** additions (no version bump — a reader that ignores unknown
keys keeps working):

* `devices[]`: `device_class`, `device_subclass`, `device_protocol`, `class_name`,
  `class_text`, `bcd_usb`, `max_packet_size0`, `num_configurations`, `speed_code`,
  `tier`, `parent`, `address` — the USB descriptor basics from `ioreg -p IOUSB`.
* `power_sources[].winning` / `.options[]`: `kind`, `kind_label`, `uuid` — the PDO
  type and the controller's option identity.
* `thunderbolt_fabric` (top level): the USB4 topology from
  `ioreg -c IOThunderboltSwitch` — `routers[]` with their identity (`router_id`,
  `uid`, `depth`, `route_string`, `thunderbolt_version`), the switch `ports[]`
  (`protocol`, link speed/width, lane, credits) and the tunnel adapters
  `tunnels[]` (PCIe/USB/DisplayPort with their driver).
* `devices[].interfaces[]`: the interface descriptors macOS publishes in the
  registry (`IOUSBHostInterface`) — `number`, `alternate_setting`, `configuration`,
  `class_code`, `class_text`, `subclass`, `protocol`, `endpoints` (the *count*
  macOS reports; the endpoint descriptors themselves are not published) and `name`.
  Empty for a device that publishes none.
# Fix-spec data contract

The current snapshot document remains schema version 1 for parity with the
existing CLI and Python-compatible fixtures. New diagnostic metadata is kept in
separate diagnostic bundles so ordinary snapshot consumers do not break.

## Merge precedence

For overlapping USB device fields, the normalized value is selected in this
order: `systemProfiler` identity and user-facing connection facts, `ioPort`
port and transport facts, `ioUSB` descriptor facts, `interfaceRegistry`
interface descriptors, and `diskutil` storage facts. A source fills a missing
field but does not replace an already reported higher-precedence value. Duplicate
location IDs are retained deterministically and produce a data-quality warning.

Identity diagnostics expose the hierarchy used by new code: location ID, serial,
bus/port path, then vendor/product/name. Legacy `deviceKey` strings remain
unchanged for event-log and snapshot compatibility; weak fallback collisions
are surfaced as warnings instead of silently dropping a record.

## Availability and provenance

New APIs use `DataState` (`absent`, `unknown`, `unavailable`, `unsupported`,
`stale`, `present`) and `FactCertainty` (`observed`, `derived`, `unavailable`,
`stale`). Security findings include evidence containing the field path, observed
value, source, and rule identifier. This lets reports explain both what macOS
reported and what usbscope inferred.

## Migration

Schema-less legacy snapshots are treated as version 0 and migrated to the
current header. Future schema versions are rejected with an explicit version
mismatch rather than silently losing fields.
