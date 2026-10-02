"""Small, dependency free command runner shared by the adapters."""

from __future__ import annotations

import subprocess
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

DEFAULT_TIMEOUT = 25.0


def system_binary(name: str, *candidates: str) -> str:
    """Return an absolute path of a system tool, falling back to the bare name.

    macOS keeps its CLI tools in /usr/sbin and /usr/bin. Calling them by name
    would fail in a context with an empty or minimal PATH (a bundled binary
    launched from Finder, a launchd job, ``env -i``), so the absolute path wins
    when it exists.
    """
    for candidate in candidates:
        if Path(candidate).is_file():
            return candidate
    return name


@dataclass(frozen=True, slots=True)
class CommandResult:
    """Outcome of a command; a failure is data, never an exception."""

    argv: tuple[str, ...]
    returncode: int
    stdout: bytes = b""
    error: str | None = None

    @property
    def ok(self) -> bool:
        """True when the command ran and exited with status 0."""
        return self.error is None and self.returncode == 0


def run_command(argv: Sequence[str], timeout: float = DEFAULT_TIMEOUT) -> CommandResult:
    """Run ``argv`` and capture its output without ever raising."""
    try:
        completed = subprocess.run(
            list(argv),
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError:
        return CommandResult(tuple(argv), 127, error=f"{argv[0]} not found")
    except subprocess.TimeoutExpired:
        return CommandResult(tuple(argv), 124, error=f"{argv[0]} timed out after {timeout:.0f}s")
    except OSError as exc:  # pragma: no cover - defensive
        return CommandResult(tuple(argv), 126, error=f"{argv[0]}: {exc}")
    return CommandResult(tuple(argv), completed.returncode, bytes(completed.stdout))
