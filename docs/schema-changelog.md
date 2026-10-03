# JSON schema changelog

The machine readable snapshot (`usbscope --json`) carries a top-level
`schema_version`. Consumers may rely on it; it changes only when existing keys
change meaning or disappear.

Rules:

* **Additive** keys (new fields on existing objects, new objects) do **not** bump
  the version — a reader that ignores unknown keys keeps working.
* **Breaking** changes (removing a key, changing a key's type or meaning) bump
  `schema_version` and are listed here.
* The constant lives in `src/usbscope/serialize.py` (`SCHEMA_VERSION`) and
  `Sources/UsbScopeCore/Serialize.swift` (`Serialize.schemaVersion`); a test on
  both sides asserts they agree with the head of this file.

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
