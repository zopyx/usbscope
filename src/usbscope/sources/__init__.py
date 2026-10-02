"""Adapters that translate OS facts into the domain model."""

from .ioreg import IoregSource, parse_ports
from .profiler import SystemProfiler
from .shell import CommandResult, run_command

__all__ = ["CommandResult", "IoregSource", "SystemProfiler", "parse_ports", "run_command"]
