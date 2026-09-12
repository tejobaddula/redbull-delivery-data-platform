"""Unit tests for the pure, no-Snowflake-connection parts of ingest/loader.py.

Deliberately excludes anything that opens a real connection (_connect, stage,
copy, ...) so this suite runs in CI with no Snowflake credentials at all.
"""

from __future__ import annotations

from ingest.loader import Feed, _selected, _split_statements, _stage_path
from ingest.loader import _registry as registry


def test_registry_loads_all_three_feeds() -> None:
    period, feeds = registry()
    assert period == "202403"
    assert set(feeds) == {"outlet", "portfolio", "matching"}


def test_registry_portfolio_has_no_usa() -> None:
    """USA portfolio was never delivered upstream -> feeds.yml must encode that gap."""
    _, feeds = registry()
    assert feeds["portfolio"].markets == ["GBR", "DEU"]
    assert "USA" not in feeds["portfolio"].markets


def test_registry_outlet_and_matching_cover_all_markets() -> None:
    _, feeds = registry()
    assert set(feeds["outlet"].markets) == {"USA", "GBR", "DEU"}
    assert set(feeds["matching"].markets) == {"USA", "GBR", "DEU"}


def test_stage_path_format() -> None:
    assert _stage_path("outlet", "202403", "DEU") == "outlet/202403/DEU"


def test_selected_filters_out_unavailable_market() -> None:
    """USA has no portfolio feed, so _selected must drop it, not error."""
    feeds = {
        "outlet": Feed("outlet", "RAW.OUTLET", "RB_TSV", "outlet*.csv", ["USA", "GBR"]),
        "portfolio": Feed("portfolio", "RAW.PORTFOLIO", "RB_TSV", "portfolio*.csv", ["GBR"]),
    }
    assert [f.name for f in _selected(feeds, None, "USA")] == ["outlet"]
    assert [f.name for f in _selected(feeds, None, "GBR")] == ["outlet", "portfolio"]


def test_selected_restricts_to_one_feed() -> None:
    feeds = {
        "outlet": Feed("outlet", "RAW.OUTLET", "RB_TSV", "outlet*.csv", ["USA"]),
        "matching": Feed("matching", "RAW.MATCHING", "RB_TSV", "matching*.csv", ["USA"]),
    }
    assert [f.name for f in _selected(feeds, "matching", "USA")] == ["matching"]


def test_split_statements_ignores_comments_and_blank_lines() -> None:
    sql = (
        "-- a leading comment\n"
        "USE ROLE ACCOUNTADMIN;\n"
        "\n"
        "-- another comment\n"
        "CREATE WAREHOUSE IF NOT EXISTS X\n"
        "    WAREHOUSE_SIZE = 'XSMALL';\n"
    )
    stmts = _split_statements(sql)
    assert len(stmts) == 2
    assert stmts[0] == "USE ROLE ACCOUNTADMIN"
    assert "CREATE WAREHOUSE IF NOT EXISTS X" in stmts[1]
    assert not stmts[1].endswith(";")


def test_split_statements_keeps_trailing_statement_without_semicolon() -> None:
    stmts = _split_statements("SELECT 1")
    assert stmts == ["SELECT 1"]
