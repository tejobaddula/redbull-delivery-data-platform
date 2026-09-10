"""Automated proof that market-scoped row-level security works.

Connects as each RB_ANALYST_* role and asserts what it can and cannot see in MARTS.
Exits non-zero on any violation. Run: `make rbac-demo`.
"""

from __future__ import annotations

import sys
from typing import Any

import snowflake.connector
from rich.console import Console
from rich.table import Table

sys.path.insert(0, ".")
from config.settings import load_settings  # noqa: E402

console = Console()
SETTINGS = load_settings()

EXPECTED_VISIBLE = {
    "RB_ANALYST_USA": {"USA"},
    "RB_ANALYST_GBR": {"GBR"},
    "RB_ANALYST_DEU": {"DEU"},
    "RB_ANALYST_HQ": {"USA", "GBR", "DEU"},
}
MARKET_SCOPED = ["MARTS.DIM_OUTLET", "MARTS.FCT_OUTLET_AVAILABILITY", "MARTS.FCT_OUTLET_METRIC"]
GLOBAL_DIMS = {"MARTS.DIM_PRODUCT": 331, "MARTS.DIM_PLATFORM": 6}


def query_as(role: str, sql: str) -> list[tuple[Any, ...]]:
    conn = snowflake.connector.connect(
        account=SETTINGS.snowflake_account,
        user=SETTINGS.snowflake_user,
        password=SETTINGS.snowflake_password,
        role=role,
        warehouse="RB_BI_WH",
    )
    try:
        cur = conn.cursor()
        cur.execute("USE DATABASE REDBULL_DELIVERY")
        cur.execute(sql)
        return list(cur.fetchall())
    finally:
        conn.close()


def markets_seen(role: str, table: str) -> set[str]:
    return {row[0] for row in query_as(role, f"SELECT DISTINCT market_code FROM {table}")}


def count_as(role: str, table: str) -> int:
    return int(query_as(role, f"SELECT COUNT(*) FROM {table}")[0][0])


def main() -> int:
    tbl = Table("role", "table", "markets visible", "expected", "result")
    ok = True

    for role, expected in EXPECTED_VISIBLE.items():
        for table in MARKET_SCOPED:
            seen = markets_seen(role, table)
            passed = seen == expected
            ok = ok and passed
            tbl.add_row(
                role,
                table.split(".")[-1],
                ",".join(sorted(seen)) or "(none)",
                ",".join(sorted(expected)),
                "[green]PASS[/]" if passed else "[red]FAIL[/]",
            )

    for table, n in GLOBAL_DIMS.items():
        got = count_as("RB_ANALYST_DEU", table)
        passed = got == n
        ok = ok and passed
        tbl.add_row(
            "RB_ANALYST_DEU",
            table.split(".")[-1],
            f"{got} rows",
            f"{n} rows (unfiltered)",
            "[green]PASS[/]" if passed else "[red]FAIL[/]",
        )

    console.print(tbl)
    console.print("[green]RBAC verified[/]" if ok else "[red]RBAC VIOLATION[/]")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
