"""Expectation checks for CI and QA rigs (``usbscope check``).

A hardware test rig wants a one-line, exit-code answer to "is the thing I am
testing actually plugged in and enumerated?". This module is that answer: it
parses ``--expect`` expressions, evaluates them against one snapshot and reports
per-expectation pass/fail. The rules are pure and presentation free, so the Rich
CLI, the Swift CLI twin and the unit tests share the exact same semantics.

Supported expressions (``--expect`` may be repeated):

* ``device=<vid:pid>`` or ``device=<name substring>`` — at least one device
  matches the USB ID (``0x1050:0x0407``) or carries the substring in its
  vendor/name.
* ``port=<name>`` — at least one receptacle is named exactly ``name``
  (``USB-C@3``), case-insensitively.
* ``connected>=N`` — at least ``N`` ports report an active connection.
* ``devices>=N`` — at least ``N`` devices are known.
* ``warning=0`` — exactly ``0`` collection warnings (the other comparison
  operators are accepted on every numeric key).

Anything else is malformed and makes the CLI exit ``2`` — a typo must not be
mistaken for a failing device.
"""

from __future__ import annotations

import json
import re
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from .models import Snapshot, UsbDevice

__all__ = [
    "CheckReport",
    "Expectation",
    "ExpectationError",
    "Outcome",
    "check_to_json",
    "evaluate",
    "parse_expectation",
    "render_check",
]

# Keys that count something and take a numeric comparison.
_COUNT_KEYS = frozenset({"connected", "devices", "warning", "warnings"})
# Keys that name/match one or more entities and only support equality.
_MATCH_KEYS = frozenset({"device", "port"})
# Longest operators first so ``>=`` is not read as ``>`` followed by ``=``.
_OPERATORS = (">=", "<=", "==", "=", ">", "<")

_EXPECTATION_RE = re.compile(r"^(?P<key>[a-z_]+)\s*(?P<op>>=|<=|==|=|>|<)\s*(?P<value>.+)$")
# ``0x1050:0x0407`` with the ``0x`` optional on either half, hex digits only.
_USB_ID_RE = re.compile(r"^(?:0x)?([0-9a-f]{1,4}):(?:0x)?([0-9a-f]{1,4})$", re.IGNORECASE)


class ExpectationError(ValueError):
    """A ``--expect`` expression the CLI cannot parse (exit code 2)."""


@dataclass(frozen=True, slots=True)
class Expectation:
    """One parsed ``--expect`` expression.

    ``target`` is the number a count key is compared against; it stays ``None``
    for the two match keys, whose ``value`` is a name/ID looked up in the
    snapshot instead.
    """

    raw: str
    key: str
    op: str
    value: str
    target: int | None = None


@dataclass(frozen=True, slots=True)
class Outcome:
    """The result of evaluating one expectation against one snapshot."""

    expression: str
    key: str
    op: str
    target: int | None
    actual: int
    ok: bool
    detail: str

    def to_dict(self) -> dict[str, Any]:
        """Plain JSON-compatible form, key order fixed for a stable document."""
        return {
            "expression": self.expression,
            "key": self.key,
            "op": self.op,
            "target": self.target,
            "actual": self.actual,
            "ok": self.ok,
            "detail": self.detail,
        }


@dataclass(frozen=True, slots=True)
class CheckReport:
    """Every outcome of one ``check`` run, in the order they were given."""

    outcomes: tuple[Outcome, ...] = ()

    @property
    def passed(self) -> bool:
        """True when every expectation holds (vacuously true for none)."""
        return all(outcome.ok for outcome in self.outcomes)

    @property
    def passed_count(self) -> int:
        """How many expectations hold."""
        return sum(1 for outcome in self.outcomes if outcome.ok)

    @property
    def failed(self) -> tuple[Outcome, ...]:
        """The expectations that did not hold."""
        return tuple(outcome for outcome in self.outcomes if not outcome.ok)

    def to_dict(self) -> dict[str, Any]:
        """Machine readable result document (``kind: check``)."""
        return {
            "kind": "check",
            "passed": self.passed,
            "total": len(self.outcomes),
            "passed_count": self.passed_count,
            "failed_count": len(self.failed),
            "expectations": [outcome.to_dict() for outcome in self.outcomes],
        }


def _split(expression: str) -> tuple[str, str, str]:
    """Split ``key<op>value`` or raise :class:`ExpectationError`."""
    text = expression.strip()
    match = _EXPECTATION_RE.match(text)
    if match is None:
        raise ExpectationError(
            f"malformed expectation {expression!r}: expected '<key><op><value>', "
            "e.g. device=0x1050:0x0407, port=USB-C@3, connected>=1, warning=0"
        )
    key = match.group("key")
    op = match.group("op")
    value = match.group("value").strip()
    if not value:
        raise ExpectationError(f"malformed expectation {expression!r}: empty value")
    return key, op, value


def parse_expectation(expression: str) -> Expectation:
    """Parse one ``--expect`` expression into an :class:`Expectation`.

    Raises :class:`ExpectationError` for an unknown key, a comparison operator
    on a match key, a non-numeric count or a negative count — the caller turns
    that into exit code ``2`` so a typo is never reported as a failed check.
    """
    key, op, value = _split(expression)
    text = expression.strip()
    if key in _MATCH_KEYS:
        if op not in {"=", "=="}:
            raise ExpectationError(
                f"malformed expectation {text!r}: {key} only supports '=', not {op!r}"
            )
        return Expectation(raw=text, key=key, op="=", value=value)
    if key in _COUNT_KEYS:
        try:
            target = int(value, 10)
        except ValueError as exc:
            raise ExpectationError(
                f"malformed expectation {text!r}: {key} needs a whole number, got {value!r}"
            ) from exc
        if target < 0:
            raise ExpectationError(f"malformed expectation {text!r}: {key} cannot be negative")
        return Expectation(raw=text, key=key, op=op, value=value, target=target)
    known = ", ".join(sorted(_MATCH_KEYS | _COUNT_KEYS))
    raise ExpectationError(f"malformed expectation {text!r}: unknown key {key!r} (known: {known})")


def normalize_usb_id(value: str) -> str:
    """Return ``0xvvvv:0xpppp`` for a matching ID string (input already validated)."""
    match = _USB_ID_RE.match(value)
    assert match is not None  # guaranteed by the caller
    return f"0x{int(match.group(1), 16):04x}:0x{int(match.group(2), 16):04x}"


def device_matches(device: UsbDevice, value: str) -> bool:
    """True when ``value`` names this device (USB ID or a name/vendor substring)."""
    if _USB_ID_RE.match(value):
        return device.id_string.lower() == normalize_usb_id(value)
    needle = value.lower()
    haystack = f"{device.vendor or ''} {device.name}".lower()
    return needle in haystack


def _compare(actual: int, op: str, target: int) -> bool:
    if op == ">=":
        return actual >= target
    if op == "<=":
        return actual <= target
    if op in {"=", "=="}:
        return actual == target
    if op == ">":
        return actual > target
    return actual < target


def _evaluate(snapshot: Snapshot, expectation: Expectation) -> Outcome:
    """Evaluate one expectation; the only place that reads the snapshot."""
    key, op, value = expectation.key, expectation.op, expectation.value

    def outcome(actual: int, ok: bool, detail: str) -> Outcome:
        return Outcome(expectation.raw, key, op, expectation.target, actual, ok, detail)

    if key == "device":
        matches = [device for device in snapshot.devices if device_matches(device, value)]
        count = len(matches)
        detail = f"{count} matching device(s)" if count else "no matching device"
        return outcome(count, count >= 1, detail)
    if key == "port":
        count = sum(1 for port in snapshot.ports if port.name.lower() == value.lower())
        detail = f"{count} matching port(s)" if count else "no matching port"
        return outcome(count, count >= 1, detail)
    actual = {
        "connected": len(snapshot.connected_ports),
        "devices": len(snapshot.devices),
        "warning": len(snapshot.warnings),
        "warnings": len(snapshot.warnings),
    }[key]
    assert expectation.target is not None  # every count key carries one
    ok = _compare(actual, op, expectation.target)
    label = "warning(s)" if key.startswith("warning") else key
    return outcome(actual, ok, f"{actual} {label} {op} {expectation.target}")


def evaluate(snapshot: Snapshot, expectations: Sequence[Expectation]) -> CheckReport:
    """Evaluate every expectation against one snapshot, in order."""
    return CheckReport(tuple(_evaluate(snapshot, item) for item in expectations))


def check_to_json(report: CheckReport) -> str:
    """Serialise a check result as a stable JSON document (sorted keys)."""
    return json.dumps(report.to_dict(), indent=2, ensure_ascii=False, sort_keys=True)


def render_check(report: CheckReport) -> str:
    """Plain-text form, one line per expectation plus a summary (no Rich markup)."""
    lines = [
        f"  {'✓' if outcome.ok else '✗'} {outcome.expression}  →  {outcome.detail}"
        for outcome in report.outcomes
    ]
    total = len(report.outcomes)
    status = "ok" if report.passed else f"{len(report.failed)} failed"
    lines.append(f"{report.passed_count}/{total} expectation(s) hold — {status}")
    return "\n".join(lines)
