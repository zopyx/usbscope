# Failure matrix

| Operation/source | User-visible state | Technical diagnostic | Recovery |
| --- | --- | --- | --- |
| `system_profiler` unavailable | Partial snapshot with warning | Source error and affected device fields | Refresh; inspect in-process/registry data |
| `ioreg` unavailable | Partial ports/descriptor data | Source warning with command identity | Refresh; use a direct bundle or supported macOS |
| `diskutil` unavailable | Storage source failed, not “no storage” | `StorageInventory.status = failed` | Refresh or inspect permissions |
| malformed plist/JSON | Affected source marked partial/failed | Parser warning names source/field | Collect diagnostics and add fixture |
| subprocess timeout | Refresh/export/eject reports timeout | `commandTimedOut`, stderr bounded | Retry after checking system load |
| export write failure | Visible actionable export error | Temporary path and destination are not left partial | Choose another destination and retry |
| baseline schema too new | Baseline rejected | Explicit schema mismatch | Export with a compatible app version |
| stale refresh result | Last valid snapshot retained and marked stale | Generation/sequence rejected | Wait for current refresh or retry |
| eject failure | Target remains visible with failure message | Command status and stderr available | Reconnect/mount state and retry deliberately |

Every row is designed to preserve the distinction between no matching data,
unavailable source, stale data, and an actual operation failure.
