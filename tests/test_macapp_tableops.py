"""Tests for table sorting, filtering and clipboard export."""

from __future__ import annotations

from typing import cast

import pytest

from usbscope.macapp.tableops import filter_model, natural_key, sort_model, to_tsv
from usbscope.macapp.viewmodel import VIEWS, TableModel, table_model
from usbscope.models import Snapshot


def _keys(model: TableModel, index: int) -> list[float]:
    """The hidden sort values of one column, as floats (they are ranks or 0/1)."""
    return [float(cast(float, row[index].sort_value)) for row in model.rows]


def test_natural_key_orders_digits_numerically() -> None:
    names = ["USB-C@10", "USB-C@2", "HDMI@1"]
    assert sorted(names, key=natural_key) == ["HDMI@1", "USB-C@2", "USB-C@10"]


def test_natural_key_is_case_insensitive() -> None:
    assert natural_key("usb") == natural_key("USB")


def test_sorting_the_port_column_orders_by_port_number(snapshot: Snapshot) -> None:
    plain_model = table_model(snapshot, "ports")
    model = sort_model(plain_model, 0)
    numbers = _keys(model, 0)
    assert numbers == sorted(numbers)
    assert set(model.row_keys) == set(plain_model.row_keys)


def test_sorting_by_the_mode_column_uses_the_link_rank(snapshot: Snapshot) -> None:
    model = sort_model(table_model(snapshot, "ports"), 3)
    ranks = _keys(model, 3)
    assert ranks == sorted(ranks)
    # free ports first, a connected 1.x link last — the visible order, not the text
    assert ranks[0] == -2
    assert ranks[-1] > 0


def test_sorting_is_reversible(snapshot: Snapshot) -> None:
    ascending = sort_model(table_model(snapshot, "ports"), 0)
    descending = sort_model(table_model(snapshot, "ports"), 0, reverse=True)
    up = _keys(ascending, 0)
    down = _keys(descending, 0)
    assert up == sorted(up)
    assert down == sorted(down, reverse=True)


def test_sorting_keeps_every_row(snapshot: Snapshot) -> None:
    plain = table_model(snapshot, "devices")
    sorted_model = sort_model(plain, 3)
    assert sorted_model.row_count == plain.row_count
    assert set(sorted_model.row_keys) == set(plain.row_keys)
    assert sorted_model.columns == plain.columns


def test_sorting_an_out_of_range_column_changes_nothing(snapshot: Snapshot) -> None:
    plain = table_model(snapshot, "ports")
    assert sort_model(plain, 99) is plain
    assert sort_model(plain, -1) is plain


@pytest.mark.parametrize("view", VIEWS)
def test_every_view_can_be_sorted_by_every_column(snapshot: Snapshot, view: str) -> None:
    plain = table_model(snapshot, view)
    for index in range(len(plain.columns)):
        sorted_model = sort_model(plain, index)
        assert sorted_model.row_count == plain.row_count
        assert set(sorted_model.row_keys) == set(plain.row_keys)


def test_filter_matches_any_column(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "devices")
    assert filter_model(model, "yubikey").row_count == 1
    assert filter_model(model, "yubico").row_count == 1  # vendor column
    assert filter_model(model, "0x1050").row_count == 1  # VID:PID column
    assert filter_model(model, "samsung").row_count == 0


def test_filter_requires_every_term(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "devices")
    assert filter_model(model, "yubikey yubico").row_count == 1
    assert filter_model(model, "yubikey samsung").row_count == 0


def test_empty_query_keeps_the_model(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "ports")
    assert filter_model(model, "   ") is model


def test_filter_keeps_row_keys_aligned_with_rows(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "ports")
    filtered = filter_model(model, "connected")
    pairs = dict(zip(model.row_keys, model.rows, strict=True))
    assert 0 < filtered.row_count < model.row_count
    for key, row in zip(filtered.row_keys, filtered.rows, strict=True):
        assert pairs[key] == row


def test_filter_and_sort_combine(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "ports")
    filtered = filter_model(model, "USB-C")
    ordered = sort_model(filtered, 0)
    assert ordered.row_count == filtered.row_count
    assert set(ordered.row_keys) == set(filtered.row_keys)


def test_tsv_export_includes_the_header(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "devices")
    lines = to_tsv(model).splitlines()
    assert lines[0].split("\t") == [column.title for column in model.columns]
    assert len(lines) == model.row_count + 1
    assert lines[1].split("\t")[0] == "YubiKey OTP+FIDO+CCID"


def test_tsv_export_can_omit_the_header_and_pick_a_column(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "ports")
    body = to_tsv(model, header=False).splitlines()
    assert len(body) == model.row_count
    first_column = to_tsv(model, header=False, column=0).splitlines()
    assert first_column == [row[0].text for row in model.rows]


def test_clipboard_text_is_available_on_the_model(snapshot: Snapshot) -> None:
    model = table_model(snapshot, "thunderbolt")
    assert model.clipboard_text().count("\n") == model.row_count
    assert model.clipboard_text(column=1).splitlines() == [row[1].text for row in model.rows]


def test_tsv_cells_are_single_line(snapshot: Snapshot) -> None:
    text = to_tsv(table_model(snapshot, "ports"))
    assert all("\t\t" not in line for line in text.splitlines())
