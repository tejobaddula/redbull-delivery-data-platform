"""CLI: ask the Red Bull delivery marts a question in plain English.

    uv run rb-ask "how many GBR outlets carry Monster but not Red Bull?"
    uv run rb-ask --role RB_ANALYST_GBR "how many outlets carry Red Bull by market?"
    uv run rb-ask --sql-only "average menu price of Red Bull in Germany"

Human-in-the-loop: the interpretation and SQL are always shown before the
result, and --confirm makes execution require a keypress.
"""

from __future__ import annotations

import typer
from rich.console import Console
from rich.syntax import Syntax
from rich.table import Table

from genai.analyst import ask as run_ask

app = typer.Typer(add_completion=False, help=__doc__)
console = Console()


@app.command()
def ask(
    question: str = typer.Argument(..., help="natural-language question"),
    role: str | None = typer.Option(None, help="Snowflake role to run as (RBAC applies)"),
    sql_only: bool = typer.Option(False, "--sql-only", help="show SQL, do not execute"),
    confirm: bool = typer.Option(False, "--confirm", help="require a keypress before executing"),
) -> None:
    answer = run_ask(question, role=role, execute=not sql_only)

    console.print(
        f"[dim]role[/] {answer.role}   "
        f"[dim]category[/] {answer.question_category or '-'}   "
        f"[dim]model[/] {answer.model or '-'}   "
        f"[dim]{answer.latency_s:.1f}s[/]"
        + ("   [green]verified query[/]" if answer.verified_query_used else "")
    )

    if answer.interpretation:
        console.print(f"\n[bold]Interpreted as:[/] {answer.interpretation}")

    if not answer.sql:
        for w in answer.warnings:
            console.print(f"[yellow]· {w}[/]")
        raise typer.Exit(1)

    console.print()
    console.print(Syntax(answer.sql, "sql", theme="ansi_dark", word_wrap=True))
    for w in answer.warnings:
        console.print(f"[yellow]· {w}[/]")

    if sql_only:
        return
    if confirm:
        typer.confirm("\nRun this query?", abort=True)

    tbl = Table(*answer.columns)
    for r in answer.rows[:50]:
        tbl.add_row(*("" if v is None else str(v) for v in r))
    console.print()
    console.print(tbl)
    if len(answer.rows) > 50:
        console.print(f"[dim]... {len(answer.rows) - 50} more rows[/]")


if __name__ == "__main__":
    app()
