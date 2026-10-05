# Privacy inventory

| Data | Exported | Persisted/logged | Default treatment |
| --- | --- | --- | --- |
| Host name | Snapshot/reports/diagnostics | Snapshot only when explicitly exported | Redacted in diagnostic bundles |
| Serial number | Snapshot/reports/security evidence | Event identity may contain it | Redacted in diagnostics; not in notifications by default |
| Location ID and VID/PID | Snapshot/reports/diff | Event records can contain identity | Location IDs redacted in diagnostics |
| Mount path and volume name | Storage reports/diagnostics | Not persisted by the app | Paths redacted in diagnostics |
| Event history | Diagnostics and Timeline | Rotating local JSONL log | Event identities redacted in diagnostics |
| Credentials | Never collected | Never persisted | Excluded by design |

usbscope performs local collection only and does not send telemetry. Users are
shown an export disclosure before privacy-sensitive export flows in the app
documentation; diagnostic bundles use `RedactionPolicy` by default.

Diagnostic metadata also records field provenance (for example
`systemProfiler`, `ioUSB`, and `interfaceRegistry`) using a read-local device
index rather than a serial number or location ID. Provenance explains how a
fact was obtained without adding another identifier to the support bundle.
