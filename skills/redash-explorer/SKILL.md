---
name: redash-explorer
description: Explore and execute queries, dashboards, and data sources on a Redash instance via the REST API. Use when the user asks about saved queries, dashboards, Redash metrics, wants to run ad-hoc SQL against a data source, or wants to persist queries/dashboards as a project-local spec. Activates for prompts mentioning redash, query/queries, dashboard, data source, execute, refresh, save, persist, saved metric, recurring report.
---

# Redash Explorer

Skill for operating against a Redash instance through its REST API. Combines a generic wrapper (`bin/redash-api`), a data-source resolver (`bin/redash-resolve-ds`), `/redash:*` slash commands, and a project-local spec format for persisting queries/dashboards.

## Mandatory guardrails

- **Credentials**: use `REDASH_URL` and `REDASH_API_KEY` env vars (via `bin/redash-api`). Never hardcode or print the API key.
- **SQL mutations** (`INSERT/UPDATE/DELETE/DROP/TRUNCATE/ALTER/CREATE/GRANT/REVOKE`) in `/redash:run` require explicit confirmation in the current turn. Most analytics data sources are read-only, but do not assume.
- **Mutating Redash itself** (`/redash:save`, `/redash:apply`) requires a dry-run preview + explicit confirmation before the API call. `--prune` requires a second confirmation listing exactly what gets deleted.
- **Scale**: real instances have thousands of data sources and queries. Never list them all without a filter — always use `q=` server-side or the resolver's local cache for DS.
- **CSV/JSON/XLSX exports**: when authenticated via the `Authorization: Key` header (the wrapper does this), no `?api_key=` is needed. **Never** print URLs that embed any API key.
- **Per-query `api_key`** field: every query detail response (`GET /api/queries/<id>`, `/api/queries/recent`, `/api/queries/my`, etc.) includes a per-query `api_key` string. **Never surface it to the user, in chat, in logs, or in saved files.** Always strip it from `jq` selectors when rendering.
- **Technical identifiers in English** (id, slug, type); user-facing prose can match the user's language.

## Runtime defaults

- URL: `REDASH_URL` (no trailing slash, no `/api`).
- Auth: `Authorization: Key <REDASH_API_KEY>` header (User API Key).
- Polling timeout: `REDASH_TIMEOUT` (default 60s).
- Project state directory: `${REDASH_STATE_DIR:-$PWD/.claude/redash}` — holds `cache/`, `recents.json`, and `specs/`. Project-local and gitignored.

## Data source resolution (the resolver)

`bin/redash-resolve-ds` is the single entry point for any DS lookup. **Never** hardcode a numeric id in a slash command; always pass the user's input through the resolver.

```bash
# Numeric id, exact name, or multi-token substring search.
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve "orders prod readonly"
#   exit 0 → stdout = numeric id
#   exit 1 → stderr JSON {error:"no_match", query, suggestions[]}
#   exit 2 → stderr JSON {error:"ambiguous", query, count, candidates[]}

# Recently used in this project (max 10).
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds recents 5

# Record a DS as recently used (call after a successful run/save).
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds remember 1904

# Force-refresh the catalog cache (TTL 1h by default).
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds refresh
```

Resolution flow for a `--ds` argument:
1. Pass to the resolver. If `exit 0`, use the id.
2. On `exit 1` or `exit 2`, parse the JSON from stderr and present `suggestions` / `candidates` to the user. Stop and ask them to refine.
3. If `--ds` is absent, call `recents` and present the list.

## Spec-based persistence (`.claude/redash/specs/`)

A spec is a `.md` file describing a dashboard plus the queries it contains. It is the **source of truth** — `/redash:apply` reads it and creates/updates Redash entities to match. After the first apply, IDs are written back into the spec for idempotency.

Lifecycle:
1. `/redash:plan <name>` — create or extend a spec from queries validated in this conversation.
2. `/redash:diff <name>` — preview what would change in Redash (read-only).
3. `/redash:apply <name>` — materialize the spec (create/update). Idempotent.
4. Re-run `/redash:diff` / `/redash:apply` whenever the spec changes.

Spec frontmatter shape (canonical):

```yaml
spec_version: 1
dashboard:
  name: "..."
  slug: ""              # filled after first apply
  redash_id: null       # filled after first apply
  tags: []
  publish: false
queries:
  - key: <machine_key>
    name: "..."
    redash_id: null     # filled after first apply
    data_source: { name: "...", id: <int> }
    parameters: []
    visualization: { type: table|counter|chart|pivot, name: "...", options: {} }
layout:
  - { query: <machine_key>, row: 0, col: 0, sizeX: 12, sizeY: 6 }
```

SQL goes in fenced ```sql blocks below, each preceded by `## Query: <key>`.

## Execution workflow

1. **Verify env vars** before any command: `printenv | grep -E '^REDASH_(URL|TIMEOUT|STATE_DIR)='` (do not print API_KEY).
2. **Search before executing** — if the user references a metric by name, use `/redash:search` or `/redash:queries` to find the right id rather than guessing.
3. **Cache vs refresh**: `POST /api/queries/<id>/results` with `max_age: 3600` reuses cache; `max_age: 0` forces a re-run. Default to cache when the user just wants to "see" a query.
4. **Job polling**: if the POST returns `{"job": {...}}`, poll `GET /api/jobs/<id>` every 2s until `status=3` (success) or `4|5` (failure/canceled). Then `GET /api/query_results/<query_result_id>`.
5. **Pagination**: most listings paginate (`page`, `page_size`, default 25, max 250). Mention totals and how to fetch the next page.
6. **Always remember** the DS after a successful run or save: `redash-resolve-ds remember <id>`.

## Key endpoints

| Endpoint | Use |
|---|---|
| `GET /api/session` | Auth test + current user info |
| `GET /api/data_sources` | Fetched once per project per hour by the resolver |
| `GET /api/data_sources/<id>/schema` | Tables + columns of a data source (`/redash:schema`) |
| `GET /api/queries?q=<text>&page=N&page_size=N` | Search queries |
| `GET /api/queries/my` | Queries owned by the current user (paginated) |
| `GET /api/queries/recent?limit=N` | Recently viewed/edited queries (flat array) |
| `GET /api/queries/archive` | Archived queries (paginated) |
| `GET /api/queries/<id>` | Detail: SQL, params, schedule, last result, visualizations |
| `POST /api/queries` | **Create** a new query (draft) |
| `POST /api/queries/<id>` | **Update** a query (or publish: `{"is_draft": false}`) |
| `DELETE /api/queries/<id>` | **Archive** (soft-delete) a query — used by `/redash:archive` |
| `POST /api/queries/<id>/fork` | Clone a query as draft owned by current user |
| `POST /api/queries/format` | Format SQL using Redash's parser (`/redash:format`) |
| `POST /api/queries/<id>/results` | Execute saved query |
| `GET /api/queries/<id>/results.<csv\|json\|xlsx>` | Download cached saved-query results (`--export` in `/redash:query`) |
| `POST /api/query_results` | Ad-hoc SQL |
| `GET /api/jobs/<id>` | Job status (polling) |
| `GET /api/query_results/<id>` | Full results |
| `GET /api/query_results/<id>.<csv\|json\|xlsx>` | Download ad-hoc results (`--export` in `/redash:run`) |
| `POST /api/visualizations` | Create a non-default viz attached to a query |
| `POST /api/visualizations/<id>` | Update a viz |
| `GET /api/dashboards?q=<text>` | Search dashboards |
| `GET /api/dashboards/<slug>` | Widgets + positions |
| `POST /api/dashboards` | Create dashboard (draft) |
| `POST /api/dashboards/<slug>` | Update dashboard / publish |
| `POST /api/widgets` | Add a widget to a dashboard |
| `POST /api/widgets/<id>` | Update widget position/options |
| `DELETE /api/widgets/<id>` | Remove widget (only used with `--prune`) |

## Result rendering rules

- **≤20 rows**: full markdown table with `data.columns[].friendly_name` as headers.
- **>20 rows**: first 10–50 (default `--max-rows 50`) + total + suggestion to export or persist.
- **Types**: respect `data.columns[].type` when formatting (`string`, `integer`, `float`, `datetime`, `boolean`).
- **Currency / duration**: right-align and apply thousand separators where obvious.
- **Runtime**: always include `query_result.runtime` (seconds) and `retrieved_at` so the user knows freshness.

## Common errors

- `401 Unauthorized` → invalid or revoked API key. Suggest regenerating it in Settings → Account.
- `403 Forbidden` → user lacks permission on that data source/query/dashboard. Show `permissions` from `/api/session`.
- `404 Not Found` → wrong id or archived entity.
- Job `status=4` with `error: "..."` → SQL error from the data source. Show the error verbatim.
- Resolver `exit 2` (ambiguous) → present candidates; ask user to pick by id or refine substring.
- Resolver `exit 1` (no_match) → show soft-match suggestions; ask user to fix the input.

## For multi-query analysis

Delegate to `@agent-redash:redash-analyst` when the user asks to:
- Compare results across multiple queries.
- Reconcile discrepancies between dashboards.
- Find every query that touches a specific table.
- Audit which dashboards depend on a given data source.
