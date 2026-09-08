# Raw Data Dictionary

Source: delivery-platform scrape, Q1 2024 (partition `202403`), markets **USA / GBR / DEU**.
Each feed is one logical table sharded into ~100 MB chunks (same schema, non-overlapping rows).
All files: tab-delimited, double-quoted, header row, UTF-8, embedded quotes escaped as `\"`.

| Feed | Grain | Markets | Rows (approx) | Notes |
|---|---|---|---|---|
| `outlet` | one platform listing of an outlet | USA, GBR, DEU | ~2.0 M | storefront attributes |
| `portfolio` | one drink menu line item | GBR, DEU | ~18.4 M | **no USA data delivered** |
| `matching` | one outlet ↔ Google Maps match | USA, GBR, DEU | ~2.0 M | identity + Red Bull/competitor flags |

Delivery platforms: USA = DoorDash, Uber Eats, Grubhub · GBR = Just Eat, Deliveroo, Uber Eats
· DEU = Lieferando only. `matching.platform_name` is always `Googlemaps`.

## Join keys

| Key | Meaning | In |
|---|---|---|
| `id_ext_link` | one listing on one platform (natural PK of `outlet`) | outlet, portfolio, matching |
| `id_outlet` | the real-world outlet, shared across its platform listings | outlet, portfolio, matching |
| `id_platform` / `platform_name` | delivery platform | all |
| `id_beverage` | PK of a `portfolio` menu line | portfolio |
| `id_drink` / `id_category` | FK to canonical drink / drink-category (dimension not supplied — derived) | portfolio |
| `place_id` | Google Maps Place ID | matching |

Flow: `outlet` (storefront) → `portfolio` (its drink menu, via `id_ext_link` / `id_outlet`)
→ `matching` (Red Bull vs competitor availability, via `id_outlet`).

---

## `outlet` — 37 columns

| Column | Type | Non-null USA/GBR/DEU | Notes |
|---|---|---|---|
| id_ext_link | id | 100/100/100 | listing PK |
| id_outlet | id | 100/100/100 | real-world outlet |
| id_platform | id | 100/100/100 | |
| platform_name | string | 100/100/100 | casing not normalized (`Doordash`, `Justeat`) |
| link | url | 100 | platform storefront URL |
| name | string | 100 | free text; **DEU frequently loses spaces** (`WORLD OF PIZZA` ok, `PizzeriaCaféBar`) |
| address_bulk | string | 100 | full unparsed address; USA = complete, GBR/DEU = partial |
| business | string | 27/24/100 | parent chain/brand; DEU just copies `name`; inconsistent formatting |
| business_url | string | ~0 | **dead column** |
| delivery | float | 0/52/72 | delivery fee, local currency; USA all null; many `0.0` |
| category | string | 97/99/100 | primary cuisine; **language/format differs** (USA `Mexican`, DEU `italian-pizza`) |
| description | string | 94/96/96 | `;`-delimited secondary tags |
| telephone | string | 48/93/0 | E.164-ish; **DEU all null** |
| latitude / longitude | float | 100 | WGS84 |
| num_ratings | int | 66/76/100 | nullable; `0` present in DEU |
| average_rating | int | 75/75/93 | **integer 1–5, not decimal** — precision lost upstream |
| average_cost | int | 86/26/0 | price tier 1–4; **DEU all null**, GBR sparse |
| city | string | 100 | often a **county/borough**, not a city |
| icon_url | url | 42/39/0 | logo URL |
| local_icon_name | string | 42/39/100 | filename/hash; DEU placeholders (`logo`, `default.png`) |
| min_order_amount | float | 0/41/93 | **USA all null** |
| banner_available | bool | 100 | **constant `true`** — useless |
| banner_img_link | url | sparse | mostly empty |
| banner_img_hash | string | ~0 | **dead column** |
| market | string | 100 | `US` / `UK` / `DE` — not ISO, disagrees with folder (`USA`/`GBR`/`DEU`) |
| street_address | string | 99–100 | parsed street (expanded form vs `address_bulk`) |
| postal_code | string | 99/88/100 | keep as string (UK alphanumeric, US leading zeros) |
| address_locality | string | 100 | **actually the state/region/nation** — mislabeled |
| address_country | string | 100 | `US` / `UK` / `DE` |
| telephone_platform | string | ~0 | **dead column** |
| cuisine | string | 97/99/100 | `category` + `description` concatenated — **redundant** |
| website | string | 0/0/69 | outlet's own site; **DEU only** |
| ghost_kitchen | bool | ~0 | **dead column** (despite "Ghost Kitchen" text in `address_bulk`) |
| local_currency | string | 100 | `USD`/`GBP`/`EUR`, 1:1 with market |
| created_at | date | 100 | scrape date (`YYYY-MM-DD`, Feb–Mar 2024) |
| segment_type | string | 100 | `restaurant` \| `grocery/convenience store/supermarket/liquor store` |

## `portfolio` — 25 columns (GBR, DEU only)

| Column | Type | Non-null GBR/DEU | Notes |
|---|---|---|---|
| id_beverage | id | 100 | menu-line PK |
| id_ext_link | id | 100 | FK → `outlet.id_ext_link` |
| id_outlet | id | 100 | FK → `outlet.id_outlet` |
| item_position | string | 100 | menu path `section-group-item` (`0-3-1`) |
| item_category | string | 100 | on-screen menu section header; **free text + emoji + local language** |
| id_drink | id | 100 | FK → canonical drink dimension (not supplied) |
| item_manufacturer | string | 100 | mixed legal-name vs brand (`Coca-Cola`, `PepsiCo`, `fritz-kulturgüter GmbH`) |
| item_brand | string | 100 | `Coca-Cola`, `Pepsi`, `Red Bull`, `Fanta` |
| item_subbrand | string | 100 | `<brand> Unspecified` sentinel when unresolved |
| item_volume | float (mL) | 54/93 | container size; **GBR ~46 % null** |
| item_price | decimal(_,4) | 100 | price of the **menu line** (often a combo/deal, not the drink alone) |
| id_category | id | 100 | FK → drink-category dimension |
| item_drink_category_1 | string | 100 | coarse (`Soft Drink`; Red Bull → `Energy`) |
| item_drink_category_2 | string | 100 | fine (`Cola`, `Energy`, `Tonic Water`) |
| item_image_url | url | 62/58 | |
| item_image_hash | string | 7/8 | mostly empty |
| item_name | string | 100 | raw menu text — combos, deposits, multilingual, **decimal comma in DEU** |
| item_desc | string | 70/87 | free text; often allergen boilerplate |
| addon_prompt | bool (0/1) | 100 | item is an add-on prompt |
| addon_prompt_text | string | 69/65 | add-on label (`Coke (330 ml)`) — often the only true drink size |
| packaging_size | string | 4/0.6 | very sparse, very dirty (`8 x`, `2 cans`, `x 0`) |
| banner_available | bool | 100 | **constant `false`** |
| banner_img_link / banner_img_hash | string | 0 | **dead columns** |
| created_at | date | **0 — always empty** | header exists, no values |

## `matching` — 21 columns

| Column | Type | Non-null USA/GBR/DEU | Notes |
|---|---|---|---|
| id_outlet | id | 100 | FK → `outlet.id_outlet` |
| id_platform | id | 100 | **constant** (Google Maps) |
| platform_name | string | 100 | **constant** `Googlemaps` |
| id_ext_link | id | 100 | Google-side listing ref |
| place_id | string | 79/51/83 | Google Maps Place ID; **null = no confident match** |
| similarity_score_name | float 0–1 | ~100 | fuzzy-match confidence, name |
| similarity_score_address | float 0–1 | 92–95 | fuzzy-match confidence, address |
| merged_chain_name | string | 15/14/6 | canonical chain name, **only when `is_chain=1`** |
| is_chain | bool (0/1) | 100 | |
| num_restaurants | int | 15/14/6 | chain size; populated only for chains |
| serves_drinks | bool (0/1) | 100 | outlet sells beverages at all |
| serves_red_bull | bool (0/1) | 100 | **key flag** — Red Bull on menu |
| sugar_free_available | bool (0/1) | 100 | Red Bull Sugarfree present |
| organics_available | bool (0/1) | 100 | Organics by Red Bull present |
| editions_available | bool (0/1) | 100 | Red Bull Editions present |
| ed | bool (0/1) | 100 | any energy drink on menu *(interpretation — confirm)* |
| ed_comp | bool (0/1) | 100 | competitor energy drink present *(interpretation)* |
| sd_coke | bool (0/1) | 100 | Coca-Cola soft drink present *(interpretation)* |
| sd | bool (0/1) | 100 | any soft drink present *(interpretation)* |
| leading_id_ext_link | bool (0/1) — **misnamed** | 100 | value is `0`/`1`, not an ID; likely "primary listing for the outlet" |
| created_at | date | 100 | scrape date |

---

## RAW-layer additions

Every RAW table also carries lineage columns populated at load:
`_market`, `_period` (from the stage path), `_stg_file_name`, `_stg_file_row_number`,
`_stg_file_last_modified`, `_load_ts`.
