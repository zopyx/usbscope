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
failed-source rate, and time-to-identify-device. No metric is transmitted.
