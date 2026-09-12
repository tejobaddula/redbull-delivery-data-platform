# CI/CD

What's actually running (`.github/workflows/ci.yml`) vs. the production design
that isn't wired up, and why.

## What's built and running now

**`.github/workflows/ci.yml`** — triggers on every push to `main` and every PR:

```
checkout → uv sync → ruff check → ruff format --check → mypy → pytest
```

No Snowflake credentials involved. This is a deliberate scope cut, not an
oversight: it validates all the Python that isn't Snowflake-dependent
(the loader's pure logic, config parsing, the GenAI guardrails) with zero
secrets to provision, zero risk of a live-Snowflake CI run failing for
account/network reasons unrelated to the code, and it's something you can
point at right now with a green check.

`.pre-commit-config.yaml` runs the same lint/format locally before a commit
is even made, so most issues never reach CI at all.

## What's designed but not wired up: the Snowflake-connected half

The reason this isn't running today is **credential handling**, on principle:
the GitHub Actions secrets needed (`SNOWFLAKE_ACCOUNT/USER/PASSWORD`) have to
be entered by a human in GitHub's UI, not typed or piped by an assistant —
same rule as never putting a password in a chat message. That's a five-minute
manual step for whoever owns the repo; the design below is what it unlocks.

### 1. Isolated schema per pull request

Right now `dbt/macros/generate_schema_name.sql` always resolves `STAGING` /
`INTERMEDIATE` / `MARTS` to fixed names — correct for one long-lived
environment, wrong for CI, where two PRs building at once would clobber the
same objects and tests. The fix is a `ci` dbt target whose profile schema is
`CI_<run_id>`, and a small change to that macro: when `target.name == 'ci'`,
return `target.schema` instead of the fixed name, so an entire PR's build
lands in one throwaway schema.

```yaml
# additional job in ci.yml, gated on secrets being present
dbt-build:
  needs: python
  env:
    SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
    SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
    SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
    DBT_CI_RUN_ID: ci${{ github.run_id }}
  steps:
    - run: uv run dbt deps
    - run: uv run dbt build --target ci      # RAW is shared/read-only; STAGING..MARTS rebuild in CI_<run_id>
    - if: always()
      run: uv run python -c "... DROP SCHEMA IF EXISTS REDBULL_DELIVERY.CI_${{ github.run_id }} CASCADE ..."
```

`RAW` itself is **not** rebuilt per PR — it's shared, read-only from CI's
perspective (re-ingesting on every PR would be slow and pointless; the model
logic is what's under test, not the load). `RB_TRANSFORMER` needs one added
grant (`CREATE SCHEMA ON DATABASE`) to spin the throwaway schema up, and the
teardown step (`if: always()`) guarantees it's dropped even if the build
fails, so PRs never leave orphaned schemas behind.

### 2. What gates a merge

A PR can't merge unless: `ruff` + `mypy` + `pytest` pass (running now), and
`dbt build --target ci` completes with **all ~130 tests green** in its
isolated schema (branch protection rule requiring both jobs). This is the
same tests you already have — they just run against the PR's version of the
models before it touches anything real.

### 3. Promotion to production on merge

On push to `main` (not a PR), the same `dbt build` job runs again but against
the `dev` target — i.e., the real `STAGING`/`INTERMEDIATE`/`MARTS` schemas —
so the model is only ever rebuilt "for real" from a commit that already
passed every check in isolation. `dbt docs generate` also runs here, publishing
lineage docs (e.g. to GitHub Pages) so the current model's structure is always
one click away, not just in someone's head.

### 4. Slim CI as the project grows

At the current size a full rebuild every PR is fine (~40s). Once the model
is bigger, the standard next step is dbt's **state comparison**: store the
`manifest.json` from the last successful `main` build as an artifact, and run
`dbt build --select state:modified+` in PRs — only the models actually
changed (plus what depends on them) get rebuilt and tested, not the whole
DAG. `--defer` lets unbuilt upstream models resolve against `main`'s tables
instead of needing a full rebuild in the PR's own schema.

### 5. The GenAI layer in CI

`genai/evaluate.py` (execution accuracy on the gold set) is a natural gate
too: run it after `dbt build` on every PR that touches `snowflake/ddl/04_semantic_view.sql`
or a mart the semantic view depends on, and fail the PR if accuracy drops
below the 80% threshold already in the script. This catches "I renamed a
column and broke 6 gold questions" before it ships.

### 6. Secrets and least privilege

The GitHub Actions secrets would authenticate as `RB_TRANSFORMER` specifically
(not `ACCOUNTADMIN`) — the same least-privilege role dbt already runs as
locally. CI can rebuild `STAGING`/`INTERMEDIATE`/`MARTS` and create its own
throwaway CI schemas; it cannot touch `RAW`, grant roles, or alter the RBAC
policy. A compromised CI credential is scoped to "can rebuild the model,"
not "can read raw data or change who sees what."

### Summary: what changes between now and production

| | Now (this repo) | Production |
|---|---|---|
| Trigger | push / PR | same |
| Checks | ruff, mypy, pytest | + `dbt build` in isolated schema, + GenAI eval gate |
| Isolation | N/A (no Snowflake in CI) | `CI_<run_id>` schema per PR, torn down after |
| Promotion | N/A | merge to `main` → rebuild real `STAGING`/`MARTS`, publish docs |
| Rebuild scope | full (small project) | `state:modified+` once the DAG is large |
| Credential scope | none needed | `RB_TRANSFORMER`, not `ACCOUNTADMIN` |
