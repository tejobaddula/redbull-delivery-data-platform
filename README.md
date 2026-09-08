# Red Bull Online Food-Delivery — Data Platform (DE Case Study)

Raw delivery-platform CSVs (USA / GBR / DEU, Q1 2024) → Snowflake `RAW` → dbt `STAGING`
(cleaning) → dimensional `MARTS`, with RBAC, tests, CI/CD, and a GenAI PoC.

```
local CSV shards ──PUT──▶ @RB_RAW_STAGE ──COPY INTO──▶ RAW.*  ──dbt──▶ STAGING.stg_*  ──dbt──▶ MARTS.dim_* / fct_*
                                          (load by column name,                              (row access policy:
                                           file lineage columns,                              market analysts see
                                           rejects tolerated)                                 one market, HQ sees all)
```

Transport is the only swappable part: the `COPY` bodies in `ingest/copy_templates/` are
reused verbatim by Snowpipe when moving from local `PUT` to an S3 external stage.

## Quickstart

```bash
# 1. tooling
make setup                        # uv venv + deps

# 2. credentials  (never committed)
cp .env.example .env              # then edit .env: account, user, password, RAW_DATA_DIR

# 3. Snowflake objects
make init                         # warehouses, DB, schemas, roles, stage, RAW tables

# 4. load a market end to end  (start with DEU — smallest, has all 3 feeds)
make load-deu
make reconcile-deu                # file row counts vs rows loaded
```

## Layout

| Path | What |
|---|---|
| `ingest/feeds.yml` | feed registry — add a market/platform here, not in code |
| `ingest/loader.py` | `rb-load` CLI: `init` / `stage` / `copy` / `run` / `reconcile` |
| `ingest/copy_templates/` | per-feed `COPY` bodies (also the future `CREATE PIPE` bodies) |
| `snowflake/ddl/` | `00` account setup · `01` file format + stage · `02` RAW tables · `03` row access policies |
| `dbt/` | staging + marts models, tests, docs |
| `docs/` | data dictionary · data-quality register · modeling decisions · system design |
| `genai/` | GenAI proof-of-concept |

## Data notes

- Feeds: `outlet` (all markets), `portfolio` (**GBR + DEU only**), `matching` (all markets).
- Each feed is one logical table sharded into ~100 MB chunks; shards do not overlap.
- Raw data is **not** in this repo — `RAW_DATA_DIR` in `.env` points at the local copy.
