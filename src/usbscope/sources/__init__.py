"""Adapters that translate OS facts into the domain model."""

from .charging import ChargingSource
from .ioreg import IoregSource, parse_ports
from .profiler import SystemProfiler
from .shell import CommandResult, run_command
from .usbregistry import USBRegistrySource, parse_usb_devices

__all__ = [
    "ChargingSource",
    "CommandResult",
    "IoregSource",
    "SystemProfiler",
    "USBRegistrySource",
    "parse_ports",
    "parse_usb_devices",
    "run_command",
]
