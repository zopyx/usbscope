"""Table operations for the app: sorting, filtering and clipboard export.

They work on the :mod:`usbscope.macapp.viewmodel` table models and stay pure
Python. Sorting prefers a hidden ``Cell.sort_value`` (a mode rank, a number of
megabits) over the visible text, so ``USB 1.1`` sorts below ``USB 3.2 Gen 2``
instead of alphabetically.
"""

from __future__ import annotations

import re
from typing import cast

from .viewmodel import Cell, TableModel

__all__ = ["filter_model", "matches", "natural_key", "sort_model", "to_csv", "to_tsv"]

_NUMBER = re.compile(r"(\d+)")
_Smart = tuple[tuple[int, object], ...]


def natural_key(text: str) -> _Smart:
    """Sort key that orders digits inside text numerically (``@2`` before ``@10``)."""
    parts: list[tuple[int, object]] = []
    for piece in _NUMBER.split(text):
        if not piece:
            continue
        parts.append((0, int(piece)) if piece.isdigit() else (1, piece.casefold()))
    return tuple(parts)


def _column_keys(model: TableModel, column_index: int) -> list[tuple[int, object]]:
    """Sort keys for one column, numeric when every row carries a number."""
    values = [
        cell.sort_value if cell.sort_value is not None else cell.text
        for cell in (row[column_index] for row in model.rows)
    ]
    numeric = bool(values) and all(
        isinstance(value, (int, float)) and not isinstance(value, bool) for value in values
    )
    if numeric:
        return [(0, float(cast("float", value))) for value in values]
    return [(1, natural_key(str(value))) for value in values]


def sort_model(model: TableModel, column_index: int, *, reverse: bool = False) -> TableModel:
    """Return ``model`` with its rows ordered by ``column_index``.

    Columns without sortable content (an index outside the table) come back
    unchanged instead of raising, so a stale sort state cannot break the UI.
    """
    if not model.rows or not 0 <= column_index < len(model.columns):
        return model
    order = sorted(
        range(model.row_count), key=_column_keys(model, column_index).__getitem__, reverse=reverse
    )
    return _reorder(model, order)


def _reorder(model: TableModel, order: list[int]) -> TableModel:
    def pick(values: tuple[object, ...]) -> tuple[object, ...]:
        return tuple(values[index] for index in order)

    from dataclasses import replace

    updated = replace(
        model,
        rows=pick(model.rows),  # type: ignore[arg-type]
        row_keys=pick(model.row_keys) if model.row_keys else (),
        row_highlights=pick(model.row_highlights) if model.row_highlights else (),
    )
    return updated


def matches(row: tuple[Cell, ...], terms: tuple[str, ...]) -> bool:
    """True when every search term occurs in at least one cell of the row."""
    haystack = " ".join(cell.text for cell in row).casefold()
    return all(term in haystack for term in terms)


def filter_model(model: TableModel, query: str) -> TableModel:
    """Return the rows whose cells contain every whitespace separated term.

    An empty query keeps the model as it is, and the columns are untouched so the
    header stays visible while searching.
    """
    terms = tuple(term.casefold() for term in query.split())
    if not terms:
        return model

    from dataclasses import replace

    keep = [index for index, row in enumerate(model.rows) if matches(row, terms)]
    return replace(
        model,
        rows=tuple(model.rows[index] for index in keep),
        row_keys=tuple(model.row_keys[index] for index in keep) if model.row_keys else (),
        row_highlights=(
            tuple(model.row_highlights[index] for index in keep) if model.row_highlights else ()
        ),
    )


def to_tsv(model: TableModel, *, header: bool = True, column: int | None = None) -> str:
    """Render the table (or a single column) as tab separated text for the clipboard."""
    lines: list[str] = []
    if header and column is None:
        lines.append("\t".join(item.title for item in model.columns))
    for row in model.rows:
        cells = row if column is None else (row[column],)
        lines.append("\t".join(_clean(cell.text) for cell in cells))
    return "\n".join(lines)


def to_csv(model: TableModel, *, header: bool = True) -> str:
    """Render the table as CSV (RFC 4180 quoting via the csv module)."""
    import csv
    import io

    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    if header:
        writer.writerow([item.title for item in model.columns])
    for row in model.rows:
        writer.writerow([_clean(cell.text) for cell in row])
    return buffer.getvalue().rstrip("\n")


def _clean(text: str) -> str:
    """Make a cell safe for a single TSV line."""
    return " ".join(text.split())
