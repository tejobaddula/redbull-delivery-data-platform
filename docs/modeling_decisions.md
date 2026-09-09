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

## Dimensional model (target — Phase 4)

| Model | Grain | Source | Notes |
|---|---|---|---|
| `dim_market` | market | seed | ISO codes, currency |
| `dim_platform` | delivery platform | stg_outlet | 6 platforms |
| `dim_outlet` | physical outlet (`id_outlet`) | stg_outlet | dedup across platform listings; keep first-seen attributes + list of platforms |
| `dim_product` | canonical drink (`id_drink`) | stg_portfolio | derived — no source dimension supplied; brand / manufacturer / subcategory / modal volume |
| `dim_chain` | chain (`chain_name`) | stg_matching | only where `is_chain` |
| `dim_date` | day | dbt_date | 2024 Q1+ |
| `fct_menu_item` | menu line (`id_beverage`) | stg_portfolio | measures: `line_price`, `volume_ml`; GBR + DEU only |
| `fct_outlet_availability` | outlet listing (`id_ext_link`) | stg_matching | the Red Bull / competitor flags + match scores |
| `fct_outlet_metric` | outlet listing (`id_ext_link`) | stg_outlet | ratings, price tier, fees, min order |

Grain choice for `dim_outlet`: **physical outlet (`id_outlet`)**, not listing. Same restaurant
on DoorDash + Uber Eats is one row; platform lands on the facts. Rationale: business questions
("how many outlets carry Red Bull in Bavaria?") are about places, not listings.

## Deferred (documented, not built)

| Deferred | Why | Revisit when |
|---|---|---|
| **SCD Type 2** on `dim_outlet` / `dim_product` | only one monthly snapshot (`202403`) — nothing to slowly change yet | second period arrives; keys are already modeled for it |
| **FX normalisation** to a single currency | rates are a business input we don't have; mixing currencies silently is worse than keeping local + a `currency_code` | Finance supplies a rate table |
| **Clean taxonomy** for `menu_section` (free-text, multilingual, emoji) | low analytical value vs effort; needs fuzzy/LLM mapping | GenAI PoC (Deliverable 4) |
| **`dim_product` completeness** | reconstructed from GBR+DEU menus only; USA has no portfolio | USA portfolio delivered |
| **Address geocoding / dedup** beyond what `matching` provides | `matching` already gives Google Place IDs + similarity scores | if match coverage (`place_id` 51–83 %) proves insufficient |
| **`is_ghost_kitchen`** | source column 100 % empty despite "Ghost Kitchen" text in `address_bulk` | could parse from text later |
