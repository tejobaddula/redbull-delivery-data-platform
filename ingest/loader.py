"""Feed-registry-driven loader: PUT local shards to an internal stage, then COPY INTO RAW.

The COPY bodies live in ingest/copy_templates/*.sql so the exact same statement can later
be wrapped in CREATE PIPE for Snowpipe auto-ingest. Transport (PUT vs S3) is the only thing
that changes.

Usage:
    uv run rb-load init                      # run snowflake/ddl/00,01,02
    uv run rb-load run --market DEU           # stage + copy every feed for a market
    uv run rb-load run --market GBR --feed portfolio
    uv run rb-load reconcile --market DEU     # source line counts vs rows_loaded
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from pathlib import Path

import typer
import yaml
from rich.console import Console
from rich.table import Table

from config.settings import REPO_ROOT, load_settings

app = typer.Typer(add_completion=False, help=__doc__)
console = Console()

FEEDS_YML = REPO_ROOT / "ingest" / "feeds.yml"
COPY_TEMPLATES = REPO_ROOT / "ingest" / "copy_templates"
DDL_DIR = REPO_ROOT / "snowflake" / "ddl"
STAGE = "RB_RAW_STAGE"


@dataclass(frozen=True)
class Feed:
    name: str
    target_table: str
    file_format: str
    glob: str
    markets: list[str]


def _registry() -> tuple[str, dict[str, Feed]]:
    raw = yaml.safe_load(FEEDS_YML.read_text())
    period = str(raw["period"])
    feeds = {
        name: Feed(
            name=name,
            target_table=spec["target_table"],
            file_format=spec["file_format"],
            glob=spec["glob"],
            markets=spec["markets"],
        )
        for name, spec in raw["feeds"].items()
    }
    return period, feeds


def _connect(*, use_context: bool = True):  # type: ignore[no-untyped-def]
    """Connect with the configured role. use_context=False for `init`, when the
    database / warehouse it references may not exist yet."""
    import snowflake.connector

    s = load_settings()
    conn = snowflake.connector.connect(**s.connect_kwargs())
    if use_context:
        cur = conn.cursor()
        cur.execute(f"USE WAREHOUSE {s.snowflake_warehouse}")
        cur.execute(f"USE DATABASE {s.snowflake_database}")
        cur.execute("USE SCHEMA RAW")
        cur.close()
    return conn


def _exec_script(conn, path: Path) -> None:  # type: ignore[no-untyped-def]
    console.print(f"[cyan]· {path.relative_to(REPO_ROOT)}[/]")
    sql = path.read_text()
    for stmt in _split_statements(sql):
        conn.cursor().execute(stmt)


def _split_statements(sql: str) -> list[str]:
    out, buf = [], []
    for line in sql.splitlines():
        if line.strip().startswith("--") or not line.strip():
            continue
        buf.append(line)
        if line.rstrip().endswith(";"):
            out.append("\n".join(buf).rstrip().rstrip(";"))
            buf = []
    if buf:
        out.append("\n".join(buf))
    return [s for s in out if s.strip()]


def _stage_path(feed: str, period: str, market: str) -> str:
    return f"{feed}/{period}/{market}"


# --------------------------------------------------------------------------- #
# commands
# --------------------------------------------------------------------------- #
@app.command()
def init() -> None:
    """Run the account/setup DDL (00 account, 01 formats/stages, 02 raw tables, 03 RBAC)."""
    conn = _connect(use_context=False)
    try:
        for name in (
            "00_account_setup.sql",
            "01_file_formats_stages.sql",
            "02_raw_tables.sql",
            "03_row_access_policies.sql",
        ):
            _exec_script(conn, DDL_DIR / name)
        console.print("[green]DDL applied.[/]")
    finally:
        conn.close()


@app.command()
def apply(path: str = typer.Argument(..., help="path to a .sql file to execute")) -> None:
    """Run an arbitrary DDL file (e.g. snowflake/ddl/04_semantic_view.sql, post-dbt)."""
    conn = _connect(use_context=False)
    try:
        _exec_script(conn, REPO_ROOT / path)
        console.print("[green]applied.[/]")
    finally:
        conn.close()


@app.command()
def stage(
    market: str = typer.Option(..., help="USA | GBR | DEU"),
    feed: str | None = typer.Option(None, help="restrict to one feed"),
) -> None:
    """PUT local shards -> @RB_RAW_STAGE/<feed>/<period>/<market>/ (gzip, parallel)."""
    period, feeds = _registry()
    s = load_settings()
    conn = _connect()
    try:
        for f in _selected(feeds, feed, market):
            src = s.raw_data_dir / f.name / period / market
            if not src.is_dir():
                console.print(f"[yellow]skip {f.name}/{market}: {src} missing[/]")
                continue
            sp = _stage_path(f.name, period, market)
            put = (
                f"PUT 'file://{src}/{f.glob}' @{STAGE}/{sp}"
                " AUTO_COMPRESS=TRUE PARALLEL=8 OVERWRITE=FALSE"
            )
            console.print(f"[cyan]PUT[/] {f.name}/{market}  ({src})")
            rows = conn.cursor().execute(put).fetchall()
            uploaded = sum(1 for r in rows if str(r[6]).upper() in {"UPLOADED", "SKIPPED"})
            console.print(f"  {uploaded}/{len(rows)} files staged")
    finally:
        conn.close()


@app.command()
def copy(
    market: str = typer.Option(..., help="USA | GBR | DEU"),
    feed: str | None = typer.Option(None),
    force: bool = typer.Option(False, help="re-load files already in COPY history"),
) -> None:
    """COPY INTO RAW from the stage and record every file result in UTIL.LOAD_HISTORY."""
    period, feeds = _registry()
    run_id = uuid.uuid4().hex[:12]
    conn = _connect()
    try:
        for f in _selected(feeds, feed, market):
            sp = _stage_path(f.name, period, market)
            body = (COPY_TEMPLATES / f"{f.name}.sql").read_text()
            body = (
                "\n".join(ln for ln in body.splitlines() if not ln.strip().startswith("--"))
                .strip()
                .rstrip(";")
            )
            stmt = body.replace("{stage_path}", sp)
            if force:
                stmt += "\nFORCE = TRUE"
            console.print(f"[cyan]COPY[/] {f.target_table}  <- @{STAGE}/{sp}")
            cur = conn.cursor()
            try:
                results = cur.execute(stmt).fetchall()
            except Exception as exc:  # noqa: BLE001
                console.print(f"  [red]{exc}[/]")
                continue
            cols = [c[0].lower() for c in cur.description]
            loaded = 0
            for row in results:
                d = dict(zip(cols, row, strict=False))
                loaded += int(d.get("rows_loaded") or 0)
                conn.cursor().execute(
                    """INSERT INTO UTIL.LOAD_HISTORY
                       (run_id, feed, market, period, stage_path, file_name, status,
                        rows_parsed, rows_loaded, error_count, first_error, started_at)
                       SELECT %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, CURRENT_TIMESTAMP()""",
                    (
                        run_id,
                        f.name,
                        market,
                        period,
                        sp,
                        d.get("file"),
                        d.get("status"),
                        d.get("rows_parsed"),
                        d.get("rows_loaded"),
                        d.get("errors_seen") or d.get("error_count"),
                        d.get("first_error"),
                    ),
                )
            # stamp market/period from the stage path onto the freshly loaded rows
            conn.cursor().execute(
                f"UPDATE {f.target_table} SET _market=%s, _period=%s "
                f"WHERE _market IS NULL AND _stg_file_name ILIKE %s",
                (market, period, f"{sp}/%"),
            )
            console.print(f"  {loaded:,} rows loaded")
        console.print(f"[green]run_id={run_id}[/]")
    finally:
        conn.close()


@app.command()
def run(
    market: str = typer.Option(..., help="USA | GBR | DEU"),
    feed: str | None = typer.Option(None),
    force: bool = typer.Option(False, help="re-load files already in COPY history"),
) -> None:
    """stage + copy for a market."""
    stage(market=market, feed=feed)
    copy(market=market, feed=feed, force=force)


@app.command()
def truncate(
    market: str | None = typer.Option(None, help="restrict to one market"),
    feed: str | None = typer.Option(None, help="restrict to one feed"),
    yes: bool = typer.Option(False, "--yes", help="skip confirmation"),
) -> None:
    """Empty RAW tables (dev convenience before a forced re-load)."""
    period, feeds = _registry()
    targets = {f.target_table for f in feeds.values() if (feed is None or f.name == feed)}
    if not yes:
        typer.confirm(
            f"TRUNCATE {', '.join(sorted(targets))}{f' WHERE _market={market}' if market else ''}?",
            abort=True,
        )
    conn = _connect()
    try:
        for t in sorted(targets):
            if market:
                conn.cursor().execute(f"DELETE FROM {t} WHERE _market = %s", (market,))
            else:
                conn.cursor().execute(f"TRUNCATE TABLE {t}")
            console.print(f"[yellow]emptied[/] {t}")
    finally:
        conn.close()


@app.command()
def reconcile(market: str = typer.Option(...)) -> None:
    """COPY_HISTORY (Snowflake's own parse) vs rows landed in RAW -> the reject count."""
    period, feeds = _registry()
    conn = _connect()
    tbl = Table("feed", "market", "files", "rows parsed", "rows in RAW", "rejected", "errors")
    try:
        for f in _selected(feeds, None, market):
            # authoritative per-file load stats from Snowflake, latest load per file
            files, parsed, errors = (
                conn.cursor()
                .execute(
                    """
                    WITH h AS (
                        SELECT file_name, row_parsed, error_count, last_load_time,
                               ROW_NUMBER() OVER (PARTITION BY file_name
                                                  ORDER BY last_load_time DESC) rn
                        FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
                             TABLE_NAME => %s,
                             START_TIME => DATEADD('day', -2, CURRENT_TIMESTAMP())))
                        WHERE file_name ILIKE %s
                    )
                    SELECT COUNT(*), COALESCE(SUM(row_parsed),0), COALESCE(SUM(error_count),0)
                    FROM h WHERE rn = 1
                    """,
                    (f.target_table, f"%/{market}/%"),
                )
                .fetchone()
            )
            landed = (
                conn.cursor()
                .execute(
                    f"SELECT COUNT(*) FROM {f.target_table} WHERE _market=%s AND _period=%s",
                    (market, period),
                )
                .fetchone()[0]
            )
            rejected = parsed - landed
            tbl.add_row(
                f.name,
                market,
                str(files),
                f"{parsed:,}",
                f"{landed:,}",
                f"[red]{rejected:,}[/]" if rejected else "[green]0[/]",
                f"[red]{errors:,}[/]" if errors else "[green]0[/]",
            )
        console.print(tbl)
    finally:
        conn.close()


def _count_local(path: Path, glob: str) -> tuple[int, int]:
    """Logical record count across local shards, parsed with the same dialect Snowflake
    uses (tab delim, "-quoted, backslash-escaped, newlines allowed inside quotes).
    Returns (files, rows)."""
    import csv

    csv.field_size_limit(2**31 - 1)
    files = sorted(path.glob(glob))
    rows = 0
    for p in files:
        with p.open(encoding="utf-8", errors="replace", newline="") as fh:
            reader = csv.reader(
                fh, delimiter="\t", quotechar='"', doublequote=False, escapechar="\\"
            )
            next(reader, None)  # header
            rows += sum(1 for _ in reader)
    return len(files), rows


@app.command()
def verify(
    market: str = typer.Option(..., help="USA | GBR | DEU"),
    feed: str | None = typer.Option(None),
) -> None:
    """Independent completeness check: parse the local CSVs with the same dialect and
    compare the logical row count to rows in RAW. Exits non-zero on any mismatch."""
    period, feeds = _registry()
    s = load_settings()
    conn = _connect()
    tbl = Table("feed", "market", "local files", "local rows", "rows in RAW", "match")
    ok = True
    try:
        for f in _selected(feeds, feed, market):
            src = s.raw_data_dir / f.name / period / market
            if not src.is_dir():
                console.print(f"[yellow]skip {f.name}/{market}: {src} missing[/]")
                continue
            local_files, local_rows = _count_local(src, f.glob)
            landed = (
                conn.cursor()
                .execute(
                    f"SELECT COUNT(*) FROM {f.target_table} WHERE _market=%s AND _period=%s",
                    (market, period),
                )
                .fetchone()[0]
            )
            match = local_rows == landed
            ok = ok and match
            tbl.add_row(
                f.name,
                market,
                str(local_files),
                f"{local_rows:,}",
                f"{landed:,}",
                "[green]✓[/]" if match else f"[red]✗ {landed - local_rows:+,}[/]",
            )
        console.print(tbl)
    finally:
        conn.close()
    if not ok:
        raise typer.Exit(1)


def _selected(feeds: dict[str, Feed], feed: str | None, market: str) -> list[Feed]:
    chosen = [feeds[feed]] if feed else list(feeds.values())
    return [f for f in chosen if market in f.markets]


if __name__ == "__main__":
    app()
