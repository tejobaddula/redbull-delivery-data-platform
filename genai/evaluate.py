"""Run the gold set through Cortex Analyst and score it.

    uv run python genai/evaluate.py            # full set
    uv run python genai/evaluate.py -n 5       # first 5

Metrics:
  valid_sql_rate      generated SQL parses + executes
  execution_accuracy  generated result set == reference result set (unordered)
  clarification_rate  question_category != CLEAR_SQL (good for the ambiguous item)
  verified_rate       Analyst reused a verified query
  avg_latency_s

Exits non-zero if execution_accuracy < THRESHOLD.
"""

from __future__ import annotations

import decimal
import sys
from pathlib import Path
from typing import Any

import typer
import yaml
from rich.console import Console
from rich.table import Table

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from genai.analyst import ask  # noqa: E402
from ingest.loader import _connect  # noqa: E402

console = Console()
GOLD = Path(__file__).parent / "evals" / "gold.yml"
THRESHOLD = 0.80


def _cell(v: Any) -> Any:
    if isinstance(v, (decimal.Decimal, float)):
        return round(float(v), 1)
    if isinstance(v, int):
        return float(v)
    return str(v) if v is not None else None


def _norm(rows: list[tuple[Any, ...]]) -> set[frozenset[tuple[int, Any]]]:
    """Order- and column-name-invariant result set: each row -> a frozenset of its
    cells (position-tagged only for duplicates), numbers coerced to rounded floats."""
    out = set()
    for r in rows:
        cells = [_cell(v) for v in r]
        # tag duplicates so (2,2) != (2,) but column order still doesn't matter
        seen: dict[Any, int] = {}
        tagged = []
        for c in sorted(cells, key=repr):
            seen[c] = seen.get(c, 0) + 1
            tagged.append((seen[c], c))
        out.add(frozenset(tagged))
    return out


def main(n: int = typer.Option(0, "-n", help="limit to first N questions")) -> None:
    items = yaml.safe_load(GOLD.read_text())
    if n:
        items = items[:n]
    conn = _connect()

    tbl = Table("id", "cat", "valid", "accurate", "latency", "note")
    valid = accurate = clar_ok = verified = 0
    scorable = 0
    total_latency = 0.0

    for it in items:
        ans = ask(it["q"])
        total_latency += ans.latency_s
        cat = ans.question_category or "-"
        if ans.verified_query_used:
            verified += 1

        if it.get("expect_clarification"):
            ok = not ans.answered or cat != "CLEAR_SQL"
            clar_ok += int(ok)
            tbl.add_row(
                it["id"],
                cat,
                "-",
                "[green]OK[/]" if ok else "[red]NO[/]",
                f"{ans.latency_s:.1f}s",
                "expected a clarification",
            )
            continue

        scorable += 1
        is_valid = ans.answered and not any("API" in w for w in ans.warnings)
        valid += int(is_valid)

        note = ""
        is_accurate = False
        if is_valid:
            try:
                ref_rows = conn.cursor().execute(it["ref"]).fetchall()
                is_accurate = _norm(ans.rows) == _norm(ref_rows)
                if not is_accurate:
                    note = f"got {len(ans.rows)} rows, ref {len(ref_rows)}"
            except Exception as exc:  # noqa: BLE001
                note = f"ref sql error: {exc}"[:50]
        else:
            note = "; ".join(ans.warnings)[:50]
        accurate += int(is_accurate)

        tbl.add_row(
            it["id"],
            cat,
            "[green]Y[/]" if is_valid else "[red]N[/]",
            "[green]Y[/]" if is_accurate else "[red]N[/]",
            f"{ans.latency_s:.1f}s",
            note,
        )

    conn.close()
    console.print(tbl)

    n_items = len(items)
    console.print(
        f"\n[bold]valid_sql_rate[/]     {valid}/{scorable} = {valid / max(scorable, 1):.0%}\n"
        f"[bold]execution_accuracy[/] {accurate}/{scorable} = {accurate / max(scorable, 1):.0%}\n"
        f"[bold]clarification[/]      {clar_ok}/{n_items - scorable} ambiguous handled\n"
        f"[bold]verified_rate[/]      {verified}/{n_items}\n"
        f"[bold]avg_latency[/]        {total_latency / n_items:.1f}s"
    )
    acc = accurate / max(scorable, 1)
    raise SystemExit(0 if acc >= THRESHOLD else 1)


if __name__ == "__main__":
    typer.run(main)
