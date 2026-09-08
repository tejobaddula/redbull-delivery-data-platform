.PHONY: setup lint typecheck test init load-deu load-gbr load-usa reconcile-deu

setup:            ## create venv + install deps
	uv sync --extra dbt --extra dev

lint:
	uv run ruff check .
	uv run ruff format --check .

typecheck:
	uv run mypy ingest config

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

reconcile-deu:
	uv run rb-load reconcile --market DEU
