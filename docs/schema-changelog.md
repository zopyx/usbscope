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
