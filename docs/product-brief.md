# usbscope product brief

## Audiences and jobs

| Persona | Primary job | Views/actions |
| --- | --- | --- |
| Troubleshooting user | Find why a device is slow, charge-only, missing, or restricted | Overview, Connections, guided diagnostics, Refresh, Details |
| Developer | Inspect negotiated mode, transports, descriptors, and diffs | Ports, Cables, Devices, USB4, Copy JSON, Baseline/Diff |
| IT administrator | Capture repeatable machine state and explain partial reads | Overview, Warnings, History, Export Diagnostics, reports |
| Security-conscious user | Review heuristic observations without false certainty | Security observations, evidence, redacted export, privacy settings |

The first screen is the Overview experience: host/read freshness, connected
ports, devices, negotiated mode, transport, and power/charge state are visible
before secondary metadata. Empty, loading, partial, stale, and failed-source
states are distinct.

## Product metrics

Only local diagnostics record time-to-first-snapshot, per-source latency,
failed-source rate, collection attempts, and time-to-identify-device. These
metrics remain in memory until the user copies or exports diagnostics; no
metric is transmitted or persisted as telemetry.

Security observations remain heuristic and traceable to evidence. Their display
severity can be overridden per stable rule ID in Preferences without changing
the raw observation or its rule ID in exports.

The Copy Diagnostics action includes app/version, OS and architecture, schema
version, freshness, source health and timings, recent event summaries, and the
same default redaction policy as file diagnostics. Reports and table exports
are written atomically, and each empty data view offers a refresh action where
refreshing can change the result.
