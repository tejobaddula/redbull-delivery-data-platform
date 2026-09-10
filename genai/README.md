# GenAI PoC — "Ask Red Bull Delivery"

Natural-language analytics over the dimensional model. A user (technical or not)
asks a question in plain English; **Cortex Analyst** turns it into SQL against the
`RB_DELIVERY_SV` semantic view; the SQL runs under **the user's own Snowflake role**,
so market-level row security is enforced automatically.

```
question ─▶ Cortex Analyst ─▶ SQL over RB_DELIVERY_SV ─▶ run as caller's role ─▶ answer
              (claude-sonnet on          │                        │
               Snowflake, in-VPC)        │                        └─ RAP_MARKET row policy
                                         └─ hand-curated: 9 tables, 14 joins,
                                            ~45 dimensions, 9 metrics, synonyms
```

## Why this use case

The marts already answer *"where is Red Bull stocked, where are the gaps"*. The
bottleneck is **access** — a category manager in Munich shouldn't need SQL or a
BI-team ticket to ask "which chains in Bavaria carry Monster but not Red Bull?".
This puts the dimensional model behind plain English while keeping governance intact.

## Run it

```bash
uv run rb-ask "how many outlets carry a competitor energy drink but not Red Bull, by market?"
uv run rb-ask --role RB_ANALYST_GBR "how many outlets carry Red Bull by market?"   # RBAC: GBR only
uv run rb-ask --sql-only "average menu price of Red Bull in Germany"                # plan, don't execute
uv run rb-ask --confirm "..."                                                       # keypress before running

uv run python genai/evaluate.py        # score the gold set
```

## Files

| File | |
|---|---|
| `../snowflake/ddl/04_semantic_view.sql` | the semantic view — relationships, metrics, synonyms (committed as code) |
| `analyst.py` | Cortex Analyst REST client + guardrails + RBAC-aware execution |
| `ask.py` | `rb-ask` CLI |
| `evals/gold.yml` | 16 gold questions with reference SQL |
| `evaluate.py` | scores: valid-SQL rate, execution accuracy, clarification handling, latency |

## Production readiness

### Cost management
- **Cortex Analyst billing** is per message (Snowflake AI Services credits), *not*
  per token — one question ≈ one unit regardless of schema size. No warehouse
  runs during generation; the warehouse only spins up to execute the final SQL.
- Controls in place: `STATEMENT_TIMEOUT_IN_SECONDS = 60` and a `LIMIT 10000` row
  cap on every executed query; `RB_BI_WH` is XS with 60s auto-suspend.
- To add for production: a per-user daily question quota, a `RESOURCE_MONITOR` on
  the BI warehouse, and caching identical (question, role) pairs for a short TTL.

### Determinism
- Cortex Analyst is **not** guaranteed deterministic (LLM generation). Mitigations:
  - **Metrics in the semantic view** — `red_bull_penetration_pct`, `opportunity_outlet_count`
    etc. are defined once in SQL, so common questions resolve to a fixed metric rather
    than freshly-generated arithmetic.
  - **Verified Query Repository** — approved (question → SQL) pairs; when Analyst
    matches one it returns it verbatim (`verified_query_used = true`). The eval
    harness tracks this rate; the plan is to promote every gold question into the VQR.
  - The generated SQL is always surfaced, so a non-deterministic answer is visible,
    not silent.

### Human-in-the-loop
- The CLI always prints the **interpretation** ("Interpreted as: …") and the **SQL**
  before the result — the reviewer sees exactly what was asked and run.
- `question_category` from Analyst (`CLEAR_SQL` vs `UNCLEAR` / ambiguous) is shown;
  ambiguous questions return a clarification instead of a guess.
- `--confirm` gates execution on a keypress.
- Production: route `UNCLEAR` questions and low-confidence answers to a review queue;
  log every (question, sql, role, request_id) to a table for audit and for building
  the verified-query set.

### Evaluation metrics (what says "ready for production")
| Metric | Target | This PoC (`make genai-eval`, 16 questions) |
|---|---|---|
| **Execution accuracy** | ≥ 95% | **93%** (14/15 scorable) |
| **Valid-SQL rate** | 100% | **100%** |
| **Clarification handling** | ambiguous → no confident wrong answer | **1/1** ("which market is doing best?" → `UNCLEAR`, no SQL) |
| **Verified-query coverage** | ≥ 80% of top questions | 0% (VQR not seeded yet — the next step) |
| **avg latency** | < 10s | **6.5s** |
| **RBAC leak rate** | 0 | 0 — verified separately (`rb-ask --role RB_ANALYST_GBR` returns GBR only) |

The one accuracy miss is a menu-line count that differs by grain interpretation — exactly
the kind of question that should be promoted into the Verified Query Repository so it
resolves identically every time. The gold set here is 16 questions; a real deployment
needs 100+, drawn from actual analyst logs and refreshed as the marts evolve.

### PoC → production
1. **Semantic view in version control + CI** — it already lives in `snowflake/ddl/`;
   add a CI step that recreates it and runs `genai/evaluate.py` on every PR that
   touches the marts or the view.
2. **Verified Query Repository** seeded from the gold set, expanded from logs.
3. **Front end** — Streamlit in Snowflake (stays in-account, inherits SSO + RBAC)
   or embed the Analyst API in the existing BI portal.
4. **Observability** — log to `UTIL.ANALYST_REQUESTS` (request_id, question, sql,
   role, category, latency, thumbs-up/down); dashboard accuracy and cost trends.
5. **Add Cortex Search** over `docs/` (data dictionary, DQ register, modeling
   decisions) as a second agent tool, so the bot also answers "why is there no USA
   menu data?" and "what does `ed_comp` mean?" — the caveats, not just the numbers.
