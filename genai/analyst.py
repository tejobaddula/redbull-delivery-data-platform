"""Cortex Analyst client — natural language -> SQL over MARTS.RB_DELIVERY_SV.

The generated SQL is executed under the *caller's* Snowflake role, so the
RAP_MARKET row access policy on the MARTS tables still applies: an RB_ANALYST_GBR
user asking "how many outlets carry Red Bull" gets GBR only, automatically.

Determinism / cost / HITL notes live in genai/README.md.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from typing import Any

import requests
import snowflake.connector

from config.settings import load_settings

SEMANTIC_VIEW = "REDBULL_DELIVERY.MARTS.RB_DELIVERY_SV"
ANALYST_PATH = "/api/v2/cortex/analyst/message"
STATEMENT_TIMEOUT_S = 60
ROW_CAP = 10_000


@dataclass
class Answer:
    question: str
    interpretation: str | None
    sql: str | None
    columns: list[str] = field(default_factory=list)
    rows: list[tuple[Any, ...]] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    latency_s: float = 0.0
    role: str = ""
    request_id: str | None = None
    question_category: str | None = None  # CLEAR_SQL / AMBIGUOUS / ...
    verified_query_used: bool = False
    model: str | None = None

    @property
    def answered(self) -> bool:
        return bool(self.sql)


def _connect(role: str | None):  # type: ignore[no-untyped-def]
    s = load_settings()
    kw = s.connect_kwargs()
    if role:
        kw["role"] = role
    conn = snowflake.connector.connect(**kw)
    conn.cursor().execute("USE DATABASE REDBULL_DELIVERY")
    conn.cursor().execute(f"ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = {STATEMENT_TIMEOUT_S}")
    return conn


def _guardrail(sql: str) -> list[str]:
    """Cortex Analyst only emits SELECTs over the semantic view, but defend anyway."""
    warnings: list[str] = []
    lowered = sql.lower()
    banned = (
        " insert ",
        " update ",
        " delete ",
        " merge ",
        " drop ",
        " alter ",
        " create ",
        " grant ",
    )
    if any(b in f" {lowered} " for b in banned):
        raise ValueError(f"refusing non-SELECT SQL from Analyst: {sql[:200]}")
    if "limit" not in lowered:
        warnings.append(f"no LIMIT in generated SQL; capping at {ROW_CAP}")
    return warnings


def ask(question: str, role: str | None = None, *, execute: bool = True) -> Answer:
    started = time.monotonic()
    conn = _connect(role)
    effective_role = conn.cursor().execute("SELECT CURRENT_ROLE()").fetchone()[0]
    try:
        body = {
            "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
            "semantic_view": SEMANTIC_VIEW,
        }
        resp = requests.post(
            f"https://{conn.host.lower()}{ANALYST_PATH}",
            headers={
                "Authorization": f'Snowflake Token="{conn.rest.token}"',
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            data=json.dumps(body),
            timeout=90,
        )
        if resp.status_code != 200:
            return Answer(
                question,
                None,
                None,
                warnings=[f"analyst API {resp.status_code}: {resp.text[:300]}"],
                latency_s=time.monotonic() - started,
                role=effective_role,
            )

        payload = resp.json()
        interpretation, sql, verified = None, None, False
        for item in payload.get("message", {}).get("content", []):
            if item.get("type") == "text":
                interpretation = item["text"].split("interpretation of your question:")[-1].strip()
            elif item.get("type") == "sql":
                sql = item["statement"].strip().rstrip(";")
                verified = bool(item.get("confidence", {}).get("verified_query_used"))
        meta = payload.get("response_metadata", {})

        ans = Answer(
            question,
            interpretation,
            sql,
            latency_s=time.monotonic() - started,
            role=effective_role,
            request_id=payload.get("request_id"),
            question_category=meta.get("question_category"),
            verified_query_used=verified,
            model=(meta.get("model_names") or [None])[0],
            warnings=list(payload.get("warnings", [])),
        )
        if not sql:
            ans.warnings.append("Analyst returned no SQL (asked for clarification)")
            return ans

        ans.warnings += _guardrail(sql)
        if not execute:
            return ans
        run_sql = sql if "limit" in sql.lower() else f"{sql.rstrip(';')}\nLIMIT {ROW_CAP}"
        cur = conn.cursor()
        cur.execute(run_sql)
        ans.columns = [c[0] for c in cur.description]
        ans.rows = cur.fetchall()
        ans.latency_s = time.monotonic() - started
        return ans
    finally:
        conn.close()
