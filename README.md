# Red Bull Online Food-Delivery — Data Platform (DE Case Study)

Raw delivery-platform CSVs (USA / GBR / DEU, Q1 2024) → Snowflake `RAW` → dbt `STAGING`
(cleaning) → `INTERMEDIATE` (reconciliation) → dimensional `MARTS`, with market-scoped
RBAC, ~130 tests, and a natural-language analytics layer on Cortex Analyst.

```
local CSV shards ─PUT─▶ @RB_RAW_STAGE ─COPY INTO─▶ RAW.*  ─dbt─▶ STAGING ─dbt─▶ INTERMEDIATE ─dbt─▶ MARTS
                                       (load by column name,                                       │
                                        lineage columns,                    ┌── RAP_MARKET row policy
                                        rejects tolerated)                  │    (analyst -> own market)
                                                                           └── RB_DELIVERY_SV
                                                                                └── Cortex Analyst -> "rb-ask"
```

Transport is the only swappable part: the `COPY` bodies in `ingest/copy_templates/` are
reused verbatim by Snowpipe when moving from local `PUT` to an S3 external stage.

## Quickstart

```bash
make setup                         # uv venv + deps

cp .env.example .env               # then edit: SNOWFLAKE_* + RAW_DATA_DIR  (never committed)

make init                          # warehouses, DB, schemas, 6 roles, RBAC policy, RAW tables
make load-deu load-gbr load-usa    # PUT + COPY each market;  make verify M=GBR to reconcile

make dbt-deps dbt-build            # STAGING + INTERMEDIATE + MARTS + ~130 tests
make semantic-view                 # Cortex Analyst semantic view (needs MARTS)

make rbac-demo                     # prove market analysts see only their market
make ask Q="how many GBR outlets carry Monster but not Red Bull"
make genai-eval                    # score the NL->SQL layer on the gold set
```

## Layout

| Path | What |
|---|---|
| `ingest/feeds.yml` | feed registry — add a market/platform here, not in code |
| `ingest/loader.py` | `rb-load` CLI: `init` / `stage` / `copy` / `run` / `reconcile` / `verify` / `apply` |
| `ingest/copy_templates/` | per-feed `COPY` bodies (also the future `CREATE PIPE` bodies) |
| `snowflake/ddl/` | `00` account · `01` file format + stage · `02` RAW · `03` row access policy · `04` semantic view |
| `dbt/` | staging / intermediate / marts models, ~130 tests, `generate_schema_name` + cleaning macros |
| `rbac/` | `verify_rbac.sql` (live demo) · `verify_rbac.py` (`make rbac-demo`, exits non-zero on leak) |
| `genai/` | `rb-ask` CLI, Cortex Analyst client, gold set + `evaluate.py` — see `genai/README.md` |
| `docs/` | data dictionary · data-quality register · modeling decisions · system design |
| `.github/workflows/ci.yml` | ruff + mypy + pytest on every push/PR (no secrets needed) |

## Model

`MARTS`: `dim_market` / `dim_platform` / `dim_date` / `dim_chain` / `dim_product` (331) /
`dim_outlet` (1.16 M) · `fct_outlet_availability` & `fct_outlet_metric` (1.98 M, listing grain) ·
`fct_menu_item` (13.8 M, menu-line grain).

## Data notes

- Feeds: `outlet` (all markets), `portfolio` (**GBR + DEU only**), `matching` (all markets).
- Each feed is one logical table sharded into ~100 MB chunks; shards do not overlap.
- Raw data is **not** in this repo — `RAW_DATA_DIR` in `.env` points at the local copy.
- Load is provably complete: `rb-load verify` re-parses the local CSVs and matches `RAW` exactly.
