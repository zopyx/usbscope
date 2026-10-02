"""Tests for the USB mode classification (the core interpretation logic)."""

from __future__ import annotations

import pytest

from usbscope.models import UsbMode


@pytest.mark.parametrize(
    ("mbps", "expected"),
    [
        (1.5, UsbMode.LOW_SPEED),
        (12, UsbMode.FULL_SPEED),
        (480, UsbMode.HIGH_SPEED),
        (5000, UsbMode.SUPER_SPEED),
        (10000, UsbMode.SUPER_SPEED_PLUS),
        (20000, UsbMode.USB4_20),
        (40000, UsbMode.USB4_40),
        (80000, UsbMode.USB4_80),
        (12000000, UsbMode.FULL_SPEED),  # bit/s as reported by ioreg
        (None, UsbMode.UNKNOWN),
        (777, UsbMode.UNKNOWN),
    ],
)
def test_from_mbps(mbps: int | float | None, expected: UsbMode) -> None:
    assert UsbMode.from_mbps(mbps) is expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("12 Mbps (Full Speed)", UsbMode.FULL_SPEED),
        ("480 Mbps (High Speed)", UsbMode.HIGH_SPEED),
        ("1.5 Mbps (Low Speed)", UsbMode.LOW_SPEED),
        ("5 Gbps (SuperSpeed)", UsbMode.SUPER_SPEED),
        ("10 Gbps (SuperSpeedPlus)", UsbMode.SUPER_SPEED_PLUS),
        ("20 Gbps", UsbMode.USB4_20),
        ("12 Mb/s", UsbMode.FULL_SPEED),
        ("Up to 40 Gb/s", UsbMode.USB4_40),
        ("None", UsbMode.UNKNOWN),
        ("No Link", UsbMode.UNKNOWN),
        ("", UsbMode.UNKNOWN),
        (None, UsbMode.UNKNOWN),
    ],
)
def test_from_text(text: str | None, expected: UsbMode) -> None:
    assert UsbMode.from_text(text) is expected


def test_labels_and_ranking() -> None:
    assert UsbMode.HIGH_SPEED.label == "USB 2.0 High-Speed · 480 Mbit/s"
    assert UsbMode.HIGH_SPEED.short == "2.0 HS"
    assert UsbMode.UNKNOWN.rank == 0
    assert UsbMode.USB4_40.rank > UsbMode.SUPER_SPEED.rank > UsbMode.HIGH_SPEED.rank
