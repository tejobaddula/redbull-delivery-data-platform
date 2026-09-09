# Data Quality Register

Every issue found in the raw data, its impact, and where the pipeline fixes it.
"Fix" = corrected in the model with the raw value preserved in `RAW`; "Flag" = surfaced
via a dbt test / quarantine, not silently changed; "Defer" = documented, out of scope now.

Legend for layer: **L0** load (file format / COPY), **L1** dbt staging, **L2** dbt marts.

| # | Issue | Feed(s) | Evidence | Handling | Layer |
|---|---|---|---|---|---|
| 1 | Embedded quotes escaped as `\"` not `""` — breaks naive CSV parsing | outlet, portfolio | `"Burger Crew \"Homemade Beef Grill\""` (DEU outlet row 96) | `FILE FORMAT ... ESCAPE='\\'`; verified 0 rejects on DEU | L0 |
| 2 | Ragged rows (embedded tab/newline in quoted text) | portfolio (GBR ~2.5% in earlier sampling) | column-count mismatch | `ERROR_ON_COLUMN_COUNT_MISMATCH=FALSE` + `ON_ERROR=CONTINUE`; rejects counted by `reconcile` (COPY_HISTORY) | L0 |
| 3 | `market` = `US`/`UK`/`DE`, folder = `USA`/`GBR`/`DEU`, `address_country` = `US`/`UK`/`DE` | outlet | 3 vocabularies for one concept | conform to ISO-3166 alpha-3 via `dim_market` seed; `_market` (from path) is source of truth | L1/L2 |
| 4 | `address_locality` holds state/region/nation, `city` holds county | outlet | `address_locality='England'`, `city='Westminster'` | rename to true meaning in `dim_outlet` (`region`, `admin_area`) | L2 |
| 5 | `name` loses spaces | outlet (DEU esp.) | `PizzeriaCaféBar` vs `business='Pizzeria-Café-Bar'` | `Flag`: keep raw; prefer `business` when populated; note in dim | L1 |
| 6 | `average_rating` already integer 1–5 (decimal precision lost upstream) | outlet | no decimals anywhere | `Defer`: keep as-is, document; cannot recover | — |
| 7 | Empty string / `null` / `0.0` used as "unknown" | all | mixed sentinels | `EMPTY_FIELD_AS_NULL` at load; `NULLIF`/`TRY_CAST` in staging; `0.0` disambiguated per column | L0/L1 |
| 8 | Decimal comma in DEU numeric-ish text | portfolio | `Fanta 0,5l` in `item_name` | parsed in a staging macro when extracting volume | L1 |
| 9 | Multilingual / kebab-case categories | outlet, portfolio | `italian-pizza`, `Alkoholfreie Getränke`, `Best Sellers 💥` | keep raw; seed-mapped English for the common set; remainder → GenAI PoC | L1 |
| 10 | `item_subbrand` = `<brand> Unspecified` sentinel | portfolio | `Pepsi Unspecified` | treated as NULL sub-brand in `dim_product` | L2 |
| 11 | `item_price` is the menu-line price (combo/deal), not the drink | portfolio | `Red Bull` brand on `item_name='Pizza Cacciatora'`, price 11.00 | `Flag`: model line price honestly; drink-level price is not derivable | L2 |
| 12 | `id_drink` mislinks brand to unrelated items | portfolio | Red Bull brand rows with pizza names | `Flag` via test on `dim_product` (brand vs category coherence); candidate for GenAI cleanup | L2 |
| 13 | Duplicates on natural key | all (to verify per feed) | TBD after load | dedup keep latest `created_at` / `_load_ts` in staging | L1 |
| 14 | Referential integrity: portfolio/matching rows with no parent outlet | portfolio, matching | sampled single-shard overlap was low (sharding + real orphans) | dbt `relationships` tests; orphans kept + quarantined, not dropped | L2 |
| 15 | `portfolio.created_at` 100% empty | portfolio | header present, no values | fall back to partition date `2024-03-01` + `_load_ts` | L1 |
| 16 | **USA `portfolio` entirely missing** | portfolio | 0 files delivered | documented gap; `fct_menu_item` has no USA grain; surfaced in presentation | — |
| 17 | Dead columns (`business_url`, `telephone_platform`, `ghost_kitchen`, `banner_img_hash`, `banner_available` constant) | outlet, portfolio | ~0% populated / single value | kept in `RAW`, dropped from staging + marts | L1 |
| 18 | `cuisine` is `category` + `description` concatenated | outlet | exact overlap | derive from parts, don't carry the redundant field | L1 |
| 19 | Cryptic flag names `ed` / `ed_comp` / `sd` / `sd_coke` / `leading_id_ext_link` | matching | no data dictionary supplied | documented interpretation in `dim`/`fct` descriptions; flagged as open question for the client | L2 |
| 20 | Per-market column coverage varies wildly | outlet | `telephone` DEU 100% null, `average_cost` DEU 100% null / GBR ~80%, `min_order_amount`/`delivery` USA 100%/57% null, `website` DEU-only | `Flag`: per-market completeness metrics in an observability model; not imputed | L2 |
| 21 | `average_cost` (price tier) holds junk values in ~39 rows (`5`, `23`×27, `40`, `599`) | outlet | `SELECT average_cost, COUNT(*) ... GROUP BY 1` | clamp to 1–4 in `stg_outlet`, else NULL; `dbt_utils.accepted_range` test enforces | L1 |
| 22 | `id_drink` links a brand to unrelated items (Red Bull brand on `Pizza Cacciatora`) | portfolio | brand vs `item_name` mismatch | `Flag`: candidate for GenAI normalization; `dim_product` built from modal brand per `id_drink` | L2 |
| 23 | `portfolio` menu data covers only ~15% of outlets (172k of 1.16M) | portfolio | `COUNT(DISTINCT id_outlet)` vs `outlet` | not fixable — coverage gap; `fct_menu_item` is sparse vs `dim_outlet`; surfaced in presentation | — |

## Verified NON-issues (checked, turned out clean)

| Check | Result |
|---|---|
| Referential integrity `portfolio`/`matching` → `outlet` (on `id_ext_link` and `id_outlet`) | **0 orphans** in every direction (earlier low-overlap was a single-shard sampling artifact) |
| `id_ext_link` / `id_beverage` uniqueness | 0 duplicates — natural keys are sound |
| Latitude / longitude out of range, `average_rating` out of 0–5 | 0 rows |
| Negative `item_price`, unparseable `item_price` | 0 negative, 1 unparseable (of 13.8 M), 20,160 legitimately `0.00` |
| Market vocab consistency (`market` / `address_country` / `currency` / path) | 1:1 and consistent across all 3 markets |

## Load-time results (all markets, `202403`)

| Market | Feed | Files | Rows parsed | Rows in RAW | Rejected | Errors |
|---|---|---|---|---|---|---|
| DEU | outlet | 1 | 51,128 | 51,128 | 0 | 0 |
| DEU | portfolio | 7 | 1,301,490 | 1,301,490 | 0 | 0 |
| DEU | matching | 1 | 51,128 | 51,128 | 0 | 0 |
| GBR | outlet | 3 | 313,829 | 313,829 | 0 | 0 |
| GBR | portfolio | 63 | 12,506,070 | 12,506,070 | 0 | 0 |
| GBR | matching | 1 | 313,829 | 313,829 | 0 | 0 |
| USA | outlet | 11 | 1,614,338 | 1,614,338 | 0 | 0 |
| USA | matching | 4 | 1,614,338 | 1,614,338 | 0 | 0 |
| USA | portfolio | — | — | — | — | not delivered (issue #16) |

Totals: outlet **1,979,295** · portfolio **13,807,560** · matching **1,979,295**.
0 rejects after fixing issue #1 (`ESCAPE='\\'`). Regenerate with
`uv run rb-load reconcile --market <M>`.

**Independent completeness check** (`rb-load verify`): the local CSVs re-parsed in Python
with the same dialect (tab / `"`-quoted / `\`-escaped / newlines-in-quotes) give the exact
same logical row count as `RAW` for every feed in every market — ✓ across the board.
This is a second opinion that does not rely on Snowflake's own `COPY_HISTORY` numbers.

**Observation:** `outlet` and `matching` have identical row counts per market — `matching`
is 1:1 with platform listings (`id_ext_link`), not collapsed to physical outlets.

**Observation:** GBR portfolio is 12.5 M logical rows but ~17.1 M physical lines — ~27 % of
lines are continuations from newlines embedded in quoted `item_desc` / `item_category`.
Naive line-based tooling miscounts this feed badly.
