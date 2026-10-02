"""Tests for the persisted app preferences."""

from __future__ import annotations

from usbscope.macapp.preferences import (
    DEFAULT_INTERVAL,
    INTERVALS,
    KEY,
    Preferences,
    load,
    save,
)


class FakeDefaults:
    """Dict backed stand-in for ``NSUserDefaults``."""

    def __init__(self, data: dict[str, object] | None = None) -> None:
        self.data: dict[str, object] = dict(data or {})

    def objectForKey_(self, key: str) -> object:
        return self.data.get(key)

    def setObject_forKey_(self, value: object, key: str) -> None:
        self.data[key] = value


def test_defaults_are_sane() -> None:
    preferences = load(FakeDefaults())
    assert preferences.view == "ports"
    assert preferences.interval == DEFAULT_INTERVAL
    assert preferences.window_frame is None
    assert preferences.sort_column is None
    assert preferences.notifications is True
    assert preferences.column_widths == {}


def test_roundtrip() -> None:
    store = FakeDefaults()
    wanted = Preferences(
        view="cables",
        interval=5.0,
        window_frame=(120.0, 80.0, 1220.0, 640.0),
        sort_column=2,
        sort_reverse=True,
        notifications=False,
        column_widths={"port": 130.0, "notes": 320.0},
    )
    save(wanted, store)
    assert load(store) == wanted


def test_stored_value_is_plist_friendly() -> None:
    store = FakeDefaults()
    save(Preferences(window_frame=(1.0, 2.0, 1220.0, 640.0)), store)
    raw = store.data[KEY]
    assert isinstance(raw, dict)
    assert isinstance(raw["window_frame"], list)
    assert all(
        isinstance(value, (str, float, int, bool, list, dict, type(None))) for value in raw.values()
    )


def test_auto_refresh_off_is_remembered() -> None:
    store = FakeDefaults()
    save(Preferences(interval=None), store)
    assert load(store).interval is None


def test_unknown_view_falls_back() -> None:
    assert load(FakeDefaults({KEY: {"view": "nonsense"}})).view == "ports"


def test_unusable_interval_falls_back_to_the_default() -> None:
    assert (
        load(FakeDefaults({KEY: {"interval": "every now and then"}})).interval == DEFAULT_INTERVAL
    )


def test_interval_outside_the_menu_falls_back() -> None:
    assert load(FakeDefaults({KEY: {"interval": 99.0}})).interval == DEFAULT_INTERVAL
    assert load(FakeDefaults({KEY: {"interval": INTERVALS[1]}})).interval == 2.0


def test_tiny_or_broken_frames_are_dropped() -> None:
    assert load(FakeDefaults({KEY: {"window_frame": [1.0, 2.0, 3.0, 4.0]}})).window_frame is None
    assert load(FakeDefaults({KEY: {"window_frame": [1.0, 2.0]}})).window_frame is None
    assert load(FakeDefaults({KEY: {"window_frame": ["a", "b", "c", "d"]}})).window_frame is None
    kept = load(FakeDefaults({KEY: {"window_frame": [10.0, 20.0, 900.0, 500.0]}}))
    assert kept.window_frame == (10.0, 20.0, 900.0, 500.0)


def test_garbage_column_widths_are_filtered() -> None:
    store = FakeDefaults({KEY: {"column_widths": {"port": 130.0, "bad": "wide", "tiny": 4.0}}})
    assert load(store).column_widths == {"port": 130.0}


def test_non_dict_payload_uses_defaults() -> None:
    assert load(FakeDefaults({KEY: "not a dict"})) == Preferences()


def test_sanitized_does_not_mutate() -> None:
    broken = Preferences(view="nope", interval=42.0)
    fixed = broken.sanitized()
    assert fixed.view == "ports"
    assert broken.view == "nope"
    assert broken.interval == 42.0
