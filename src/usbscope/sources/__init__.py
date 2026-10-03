"""Adapters that translate OS facts into the domain model."""

from .charging import ChargingSource
from .ioreg import IoregSource, parse_ports
from .profiler import SystemProfiler
from .shell import CommandResult, run_command
from .storage import StorageDevice, StorageSource, parse_storage
from .thunderbolt import ThunderboltFabricSource, parse_fabric
from .usbregistry import USBRegistrySource, parse_usb_devices

__all__ = [
    "ChargingSource",
    "CommandResult",
    "IoregSource",
    "StorageDevice",
    "StorageSource",
    "SystemProfiler",
    "ThunderboltFabricSource",
    "USBRegistrySource",
    "parse_fabric",
    "parse_ports",
    "parse_storage",
    "parse_usb_devices",
    "run_command",
]
