# Modeling Decisions

What was chosen, what was deferred, and why. Paired with `data_quality.md` (issue register)
and `data_dictionary.md` (column reference).

## Layering

`RAW` (all-VARCHAR, append-only, lineage columns) → `STAGING` (typed, cleaned, deduped,
1 model per feed) → `MARTS` (dimensional model). dbt owns `STAGING` + `MARTS`; the loader
owns `RAW`. Staging models are **views** (cheap, always fresh); marts are **tables**.

## Profiling findings that shaped the model

Run against the full load (1.98 M outlet / 13.8 M portfolio / 1.98 M matching):

| Finding | Consequence |
|---|---|
| `id_ext_link` unique in `outlet` and `matching`; `id_beverage` unique in `portfolio` — **0 duplicates** | natural keys are trustworthy; `QUALIFY` dedup is a safety net, not a necessity |
| **Referential integrity is perfect** — 0 orphans `portfolio→outlet`, `matching→outlet` (both `id_ext_link` and `id_outlet`) | facts can inner-join to dims; no orphan quarantine needed, but tests stay |
| `matching` is **1:1 with `outlet`** on `id_ext_link` (same row counts, same `id_outlet` cardinality) | `matching` → a fact at listing grain, not collapsed to physical outlet |
| `portfolio` covers only **172 k of 1.16 M outlets (~15 %)** | `fct_menu_item` is sparse vs `dim_outlet`; surface coverage % in the presentation |
| market vocab is **1:1 and consistent** (`market` US/UK/DE ↔ `address_country` ↔ `currency` ↔ path `_market`) | `dim_market` is a 3-row seed; conformance is trivial |
| flag logic verified: `ed ⊇ serves_red_bull`, `sd ⊇ sd_coke`, `serves_drinks == sd` rate | documented flag semantics in `stg_matching`; superset relationships enforced by tests |
| `average_cost`: 1–4 tier, but **39 rows** hold junk (5, 23, 599, …) | clamped to 1–4 in staging, else NULL |
| `item_drink_category_1` ≈ constant `Soft Drink`; `_2` is the useful split | model on `drink_subcategory`; keep `_1` documented but unused |
| `portfolio.created_at` 100 % empty; `outlet`/`matching` span 2024-01-29 → 2024-03-15 | `menu_snapshot_date` = `coalesce(created_at, load-period first-of-month)` |

## Dimensional model (built — Phase 4)

`STAGING` (3 views) → `INTERMEDIATE` (2 tables) → `MARTS` (6 dims + 3 facts, tables).

| Model | Grain | Rows | Source |
|---|---|--:|---|
| `int_outlet__unified` | physical outlet | 1,157,233 | stg_outlet + stg_matching |
| `int_product__canonical` | drink (`id_drink`) | 331 | stg_portfolio |
| `dim_market` | market | 3 | seed |
| `dim_platform` | platform (`id_platform`) | 6 | stg_outlet |
| `dim_date` | day | 365 | dbt_date (2024) |
| `dim_chain` | chain (`chain_name`) | 140 | stg_matching |
| `dim_product` | drink (`id_drink`) | 331 | int_product__canonical |
| `dim_outlet` | physical outlet (`id_outlet`) | 1,157,233 | int_outlet__unified + availability roll-up |
| `fct_outlet_availability` | listing (`id_ext_link`) | 1,979,295 | stg_matching |
| `fct_outlet_metric` | listing (`id_ext_link`) | 1,979,295 | stg_outlet |
| `fct_menu_item` | menu line (`id_beverage`) | 13,807,560 | stg_portfolio |

**115 dbt tests pass** (unique/not_null surrogate keys, FK `relationships` facts→dims, ranges).

### Grain decisions

- **`dim_outlet` = physical outlet (`id_outlet`)**, not listing. "Tacos Vip on DoorDash + Uber
  Eats" is one row; platform lands on the facts. Business questions are about places.
- **`fct_*` stay at listing grain (`id_ext_link`)** — full per-platform detail preserved; the
  dim is the rolled-up view.
- **`dim_product` = `id_drink`** — brand/subcategory are 100% consistent per `id_drink`, so it's
  a clean key. But `id_drink` is a product *family* (248/331 have multiple pack sizes), so
  `volume_ml` lives on `fct_menu_item`; the dim only carries `modal_volume_ml` (typical size).

### Availability roll-up (`dim_outlet`)

28,118 outlets have platform listings that **disagree** on `serves_red_bull`. Rather than pick
one silently:
- `serves_red_bull` = `BOOLOR_AGG` — true if Red Bull is on **any** platform's menu (a
  distribution question: if it's orderable anywhere, it's available)
- `serves_red_bull_primary` = the value on the primary listing (`is_primary_listing`)
- `has_red_bull_conflict` = the listings disagree (so an analyst can filter these out)

### Reconciliation (`int_outlet__unified`)

~30–36% of outlets have name/category/postal drift across listings. Rules: `MODE` for
categoricals, longest string for `address_full`, primary listing for geo, `*_conflict` flags
surfaced all the way to `dim_outlet`.

## Deferred (documented, not built)

| Deferred | Why | Revisit when |
|---|---|---|
| **SCD Type 2** on `dim_outlet` / `dim_product` | only one monthly snapshot (`202403`) — nothing to slowly change yet | second period arrives; keys are already modeled for it |
| **FX normalisation** to a single currency | rates are a business input we don't have; mixing currencies silently is worse than keeping local + a `currency_code` | Finance supplies a rate table |
| **Clean taxonomy** for `menu_section` (free-text, multilingual, emoji) | low analytical value vs effort; needs fuzzy/LLM mapping | GenAI PoC (Deliverable 4) |
| **`dim_product` completeness** | reconstructed from GBR+DEU menus only; USA has no portfolio | USA portfolio delivered |
| **Address geocoding / dedup** beyond what `matching` provides | `matching` already gives Google Place IDs + similarity scores | if match coverage (`place_id` 51–83 %) proves insufficient |
| **`is_ghost_kitchen`** | source column 100 % empty despite "Ghost Kitchen" text in `address_bulk` | could parse from text later |
