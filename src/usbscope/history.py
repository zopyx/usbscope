"""In-memory power history: a bounded ring of charging samples plus a timeline.

This is the pure, headless part of the Swift ``UsbScopeCore.SnapshotHistory``.
Python does not run the IOKit hotplug watcher (that part is deliberately
Swift-only, see ``docs/index.md``), but a bounded sample ring and the power
timeline derived from it are pure logic, so both implementations agree on what a
timeline point is.

A :class:`PowerPoint` is one sample: its timestamp, the live power flowing into
the machine (``Charging.system_power_in_mw`` — what the Power view shows as
"… W in", a measurement, not the port contract), the state of charge and the
charging flag. A sample without charging telemetry still produces a point with
``watts``/``state_of_charge``/``charging`` left as ``None``, so the timeline keeps
the gap instead of silently dropping the moment.
"""

from __future__ import annotations

from collections import deque
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime

from .models import Charging

__all__ = [
    "DEFAULT_CAPACITY",
    "PowerHistory",
    "PowerPoint",
    "power_point",
]

#: How many samples the ring keeps by default (at a 5 s cadence, 240 is 20 min).
DEFAULT_CAPACITY = 240


@dataclass(frozen=True, slots=True)
class PowerPoint:
    """One sample of the machine's power draw on the timeline."""

    seen_at: datetime
    #: Live power into the machine in watt, ``None`` when there is no telemetry.
    watts: float | None = None
    state_of_charge: int | None = None
    charging: bool | None = None

    @property
    def has_power(self) -> bool:
        """Whether this point carries a measured power value."""
        return self.watts is not None


def power_point(charging: Charging | None, seen_at: datetime) -> PowerPoint:
    """Map one charging sample onto a timeline point (pure).

    The watt value is the *measured* system input (``system_power_in_mw``), not
    the negotiated contract: ``Charging`` never lies about which of the two it is.
    """
    if charging is None:
        return PowerPoint(seen_at=seen_at)
    system_power_in_mw = charging.system_power_in_mw
    return PowerPoint(
        seen_at=seen_at,
        watts=None if system_power_in_mw is None else system_power_in_mw / 1000,
        state_of_charge=charging.state_of_charge,
        charging=charging.charging,
    )


class PowerHistory:
    """A bounded ring of charging samples and the power timeline they form.

    The ring drops the oldest sample once ``capacity`` is reached, so a
    long-running watcher cannot grow without bound. ``timeline`` returns the
    samples oldest first; ``watts_timeline`` filters out the points without a
    measured value, for a chart's y axis.
    """

    def __init__(self, capacity: int = DEFAULT_CAPACITY) -> None:
        if capacity < 1:
            raise ValueError("capacity must be at least 1")
        self._capacity = capacity
        self._points: deque[PowerPoint] = deque(maxlen=capacity)

    @property
    def capacity(self) -> int:
        """How many samples the ring keeps."""
        return self._capacity

    def __len__(self) -> int:
        """Number of samples currently held."""
        return len(self._points)

    def __bool__(self) -> bool:
        """True when at least one sample was recorded."""
        return bool(self._points)

    @property
    def points(self) -> tuple[PowerPoint, ...]:
        """The samples, oldest first."""
        return tuple(self._points)

    @property
    def latest(self) -> PowerPoint | None:
        """The most recent sample, or ``None`` when the history is empty."""
        return self._points[-1] if self._points else None

    def record(self, charging: Charging | None, *, seen_at: datetime) -> PowerPoint:
        """Append one sample and return the point that was stored."""
        point = power_point(charging, seen_at)
        self._points.append(point)
        return point

    def record_many(self, samples: Iterable[tuple[datetime, Charging | None]]) -> None:
        """Append ``(seen_at, charging)`` samples in order."""
        for seen_at, charging in samples:
            self.record(charging, seen_at=seen_at)

    def timeline(self) -> tuple[PowerPoint, ...]:
        """The charging watts over time, oldest first (gaps included)."""
        return tuple(self._points)

    def watts_timeline(self) -> tuple[tuple[datetime, float], ...]:
        """Only the samples with a measured value, as ``(seen_at, watts)`` pairs."""
        return tuple(
            (point.seen_at, point.watts) for point in self._points if point.watts is not None
        )

    def clear(self) -> None:
        """Drop every sample."""
        self._points.clear()
