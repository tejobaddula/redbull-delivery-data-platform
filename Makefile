.PHONY: setup lint typecheck test init load-deu load-gbr load-usa reconcile verify dbt dbt-deps dbt-build

# load .env, then run dbt from the dbt/ dir with the local profiles.yml
DBT = set -a; . ./.env; set +a; cd dbt && DBT_PROFILES_DIR=. uv run dbt

setup:            ## create venv + install deps
	uv sync --extra dbt --extra dev

lint:
	uv run ruff check .
	uv run ruff format --check .

typecheck:
	uv run mypy ingest config rbac

test:
	uv run pytest -q

init:             ## create warehouses / db / schemas / roles / stage / raw tables
	uv run rb-load init

load-deu:
	uv run rb-load run --market DEU

load-gbr:
	uv run rb-load run --market GBR

load-usa:
	uv run rb-load run --market USA

reconcile:        ## COPY_HISTORY vs RAW (per market: make reconcile M=DEU)
	uv run rb-load reconcile --market $(or $(M),DEU)

verify:           ## independent local-CSV parse vs RAW (per market: make verify M=GBR)
	uv run rb-load verify --market $(or $(M),DEU)

dbt-deps:
	$(DBT) deps

dbt:              ## arbitrary dbt command: make dbt ARGS="run --select staging"
	$(DBT) $(ARGS)

dbt-build:        ## seeds + models + tests
	$(DBT) build

rbac-demo:        ## prove market analysts see only their market
	uv run python rbac/verify_rbac.py
