"""Security posture analysis of a :class:`~usbscope.models.Snapshot`.

Pure and presentation free: :func:`analyse` turns a snapshot into a ranked list
of findings, each carrying a severity (``info`` / ``attention`` / ``warning``)
and a short human reason. The Rich CLI and its Swift twin print the very same
findings, so the rules and their wording live here instead of in a renderer.

Every rule is derived from a fact macOS actually reported to us; a signal that
would need the interface descriptor tree (which macOS only exposes through an
``IOUSBHostDevice`` user client) is deliberately *not* invented — see the
``composite-per-interface`` rule, which states that limit instead of guessing
the contained functions.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from .models import Port, Snapshot, UsbDevice

__all__ = ["Finding", "FindingSeverity", "SecurityReport", "analyse"]

# macOS marks a receptacle that needs no user decision with one of these; any
# other value is an authorization state worth surfacing (the "allow accessory
# to connect" prompt of macOS 13+).
STANDARD_AUTHORIZATIONS = frozenset({"Not Required", "No Action"})

# The transports that carry USB data; CC/SD/DisplayPort do not.
_USB_TRANSPORT_KINDS = frozenset({"usb2", "usb3", "usb4"})

# USB-IF base class codes this analyser keys on.
_CLASS_HID = 0x03
_CLASS_MASS_STORAGE = 0x08
_CLASS_PER_INTERFACE = 0x00
_CLASS_MISC = 0xEF  # Interface Association Descriptor (composite)

_MASS_STORAGE = "mass-storage device (class 8) — it presents a filesystem to the host"
_HID_NO_SERIAL = (
    "HID device without a serial number — an identical device cannot be told apart across reads"
)
_COMPOSITE_PER_INTERFACE = (
    "class declared per interface (composite) — macOS does not expose the interface classes "
    "without a user client, so the contained functions (e.g. HID and mass storage) cannot be "
    "confirmed here"
)
_COMPOSITE_IAD = (
    "Interface Association Descriptor composite (0xEF/2/1) — macOS does not expose the interface "
    "classes without a user client, so the contained functions cannot be confirmed here"
)
_DEVICE_RESTRICTED = (
    "macOS reports the device as restricted (TRM) — it was not granted access without a prompt"
)
_TRANSPORT_RESTRICTED = "an active transport of this port is restricted by macOS (TRM)"
_NO_USB_DATA = (
    "a device is attached but the controller reports no active USB data transport "
    "(charge/accessory only)"
)
_HID_AND_STORAGE = "this port carries both a HID (class 3) and a mass-storage (class 8) device"


class FindingSeverity(StrEnum):
    """How much a finding deserves the reader's attention."""

    INFO = "info"
    ATTENTION = "attention"
    WARNING = "warning"

    @property
    def rank(self) -> int:
        """Sort rank; higher is more severe."""
        return _SEVERITY_RANK[self.value]


_SEVERITY_RANK: dict[str, int] = {"info": 0, "attention": 1, "warning": 2}


@dataclass(frozen=True, slots=True)
class Finding:
    """One security-relevant observation about a device or a port.

    ``rule`` is a stable identifier (safe to match on), ``subject`` names the
    device or port it is about and ``detail`` is the short human reason. The
    optional ``device``/``port``/``location_id`` carry the identity so a UI can
    jump to the source row without re-deriving it.
    """

    rule: str
    severity: FindingSeverity
    subject: str
    detail: str
    port: str | None = None
    device: str | None = None
    location_id: int | None = None


@dataclass(frozen=True, slots=True)
class SecurityReport:
    """The findings of one snapshot, most severe first."""

    findings: tuple[Finding, ...] = ()

    @property
    def is_empty(self) -> bool:
        """True when nothing stood out."""
        return not self.findings

    def count(self, severity: FindingSeverity) -> int:
        """Number of findings of a given severity."""
        return sum(1 for finding in self.findings if finding.severity is severity)

    @property
    def counts(self) -> dict[str, int]:
        """Per-severity counts plus the total, in a stable order for the JSON."""
        return {
            "info": self.count(FindingSeverity.INFO),
            "attention": self.count(FindingSeverity.ATTENTION),
            "warning": self.count(FindingSeverity.WARNING),
            "total": len(self.findings),
        }


def analyse(snapshot: Snapshot) -> SecurityReport:
    """Turn a snapshot into a ranked security report.

    The device rules run over the deduplicated :attr:`Snapshot.devices`, the
    port rules over :attr:`Snapshot.ports`; nothing is invented that the OS did
    not report.
    """
    findings: list[Finding] = []
    for device in snapshot.devices:
        findings.extend(_device_findings(device))
    for port in snapshot.ports:
        findings.extend(_port_findings(port))
    return SecurityReport(tuple(sorted(findings, key=_sort_key)))


def _sort_key(finding: Finding) -> tuple[int, str, str, str]:
    """Most severe first, then a stable alpha order so two runs cannot differ."""
    return (
        -finding.severity.rank,
        finding.rule,
        finding.subject,
        finding.device or "",
    )


def _device_findings(device: UsbDevice) -> list[Finding]:
    """Device-level rules, keyed on the descriptor class triple macOS reports."""
    findings: list[Finding] = []

    def add(rule: str, severity: FindingSeverity, detail: str) -> None:
        findings.append(
            Finding(
                rule,
                severity,
                device.label,
                detail,
                device=device.label,
                location_id=device.location_id,
            )
        )

    if device.device_class == _CLASS_MASS_STORAGE:
        add("mass-storage", FindingSeverity.WARNING, _MASS_STORAGE)
    if device.device_class == _CLASS_HID and not device.serial:
        add("hid-without-serial", FindingSeverity.ATTENTION, _HID_NO_SERIAL)
    if device.device_class == _CLASS_PER_INTERFACE:
        add("composite-per-interface", FindingSeverity.INFO, _COMPOSITE_PER_INTERFACE)
    elif (
        device.device_class == _CLASS_MISC
        and device.device_subclass == 0x02
        and device.device_protocol == 0x01
    ):
        add("composite-iad", FindingSeverity.INFO, _COMPOSITE_IAD)
    if device.restricted is True:
        add("restricted-by-macos", FindingSeverity.ATTENTION, _DEVICE_RESTRICTED)
    return findings


def _port_findings(port: Port) -> list[Finding]:
    """Port-level rules (authorization, restriction, no data transport, mix)."""
    findings: list[Finding] = []

    def add(rule: str, severity: FindingSeverity, detail: str) -> None:
        findings.append(Finding(rule, severity, port.name, detail, port=port.name))

    if port.authorization and port.authorization not in STANDARD_AUTHORIZATIONS:
        add(
            "authorization",
            FindingSeverity.ATTENTION,
            f"accessory authorization is '{port.authorization}' — macOS neither reported "
            "'Not Required' nor 'No Action'",
        )
    if any(transport.active and transport.restricted is True for transport in port.transports):
        add("restricted-transport", FindingSeverity.ATTENTION, _TRANSPORT_RESTRICTED)
    if port.connected and port.devices and not _has_active_usb_transport(port):
        add("no-usb-data", FindingSeverity.ATTENTION, _NO_USB_DATA)
    classes = {device.device_class for device in port.devices}
    if _CLASS_HID in classes and _CLASS_MASS_STORAGE in classes:
        add("hid-and-storage-on-port", FindingSeverity.WARNING, _HID_AND_STORAGE)
    return findings


def _has_active_usb_transport(port: Port) -> bool:
    """True when at least one USB2/USB3/USB4 transport is carrying traffic."""
    return any(
        transport.active and transport.kind.lower() in _USB_TRANSPORT_KINDS
        for transport in port.transports
    )
