"""Power-delivery depth: PDO types, option identity and the PD menu summary."""

from __future__ import annotations

from usbscope.macapp.viewmodel import port_details
from usbscope.models import Port, PowerOption, PowerSource, Snapshot
from usbscope.sources.ioreg import _power_option_kind


def test_pdo_classes_are_decoded() -> None:
    assert _power_option_kind("IOPortFeaturePowerSourceOptionFixed") == "fixed"
    assert _power_option_kind("IOPortFeaturePowerSourceOptionAdjustable") == "adjustable"
    assert _power_option_kind("IOPortFeaturePowerSourceOptionVariable") == "variable"
    assert _power_option_kind("IOPortFeaturePowerSourceOptionBattery") == "battery"
    # an unknown class keeps its name instead of being guessed
    assert _power_option_kind("SomethingElse") == "somethingElse"
    assert _power_option_kind(None) is None
    assert _power_option_kind("IOPortFeaturePowerSourceOption") is None


def test_kind_label_names_the_pps_apdo() -> None:
    assert PowerOption(kind="fixed").kind_label == "fixed"
    assert PowerOption(kind="adjustable").kind_label == "adjustable (PPS)"
    assert PowerOption(kind="battery").kind_label == "battery"
    assert PowerOption(kind="mystery").kind_label == "mystery"
    assert PowerOption().kind_label is None


def test_the_captured_contract_carries_its_pdo_type_and_uuid(snapshot: Snapshot) -> None:
    usb_c1 = next(port for port in snapshot.ports if port.name == "USB-C@1")
    usb_pd = next(source for source in usb_c1.power_sources if source.name == "USB-PD")
    assert usb_pd.selected is True
    assert usb_pd.winning is not None
    assert usb_pd.winning.kind == "fixed"
    assert usb_pd.winning.uuid == "BAC8D9DA-DC62-4A85-8590-D9037ACB133B"
    # every option of the captured charger is a fixed PDO
    assert {option.kind for option in usb_pd.options} == {"fixed"}
    assert len({option.uuid for option in usb_pd.options}) == len(usb_pd.options)


def test_the_pd_menu_is_summarised_in_the_details(snapshot: Snapshot) -> None:
    usb_c1 = next(port for port in snapshot.ports if port.name == "USB-C@1")
    pairs = dict(port_details(usb_c1))
    assert pairs["Selected source"] == "USB-PD"
    # 4 fixed options, 5–20 V, ceiling 100 W
    assert pairs["PD menu"] == "4 option(s) · 5–20 V · up to 100 W · fixed"


def test_a_non_fixed_option_is_marked_in_the_details() -> None:
    """A PPS/APDO shows its kind next to the voltage/current/power triple."""
    option = PowerOption(voltage_mv=9000, max_current_ma=3000, kind="adjustable")
    port = _port_with_option(option)
    pairs = dict(port_details(port))
    assert pairs["USB-PD option 1"].endswith("(adjustable (PPS))")
    # a plain fixed option stays clean
    fixed = _port_with_option(PowerOption(voltage_mv=5000, max_current_ma=3000, kind="fixed"))
    assert "(fixed)" not in dict(port_details(fixed))["USB-PD option 1"]


def _port_with_option(option: PowerOption) -> Port:
    source = PowerSource(name="USB-PD", selected=True, winning=option, options=(option,))
    return Port(description="Port-USB-C@1", kind="USB-C", power_sources=(source,))
