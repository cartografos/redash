# redash

Claude Code plugin for working with a Redash instance via its REST API — list and execute saved queries, refresh dashboards, run ad-hoc SQL, save queries, and **persist dashboards as project-local specs** that can be applied idempotently.

Reads credentials from `REDASH_*` env vars, exposes `/redash:*` slash commands, an auto-activating skill, and a subagent for analysis. State (catalog cache, recent data sources, dashboard specs) lives in `<project>/.claude/redash/`.

## Requirements

- **`curl`** (bundled with macOS).
- **`jq`** (required): `brew install jq`.
- A reachable Redash instance and a **User API Key** (Settings → Account → API Key).

## Configuration (env vars)

Export in your shell (`~/.zshrc`):

```bash
# Required
export REDASH_URL="https://redash.example.com"   # no trailing slash, no /api
export REDASH_API_KEY="..."                       # User API Key — never commit

# Optional
export REDASH_TIMEOUT=60                          # job polling timeout in seconds
export REDASH_STATE_DIR="$PWD/.claude/redash"     # override state dir
export REDASH_DS_CACHE_TTL=3600                   # data source catalog cache TTL
```

You **do not** need a default data source env var. The plugin resolves data sources per call by id, exact name, or fuzzy multi-token substring search, and falls back to recently used ones.

## Installation

```
/plugin marketplace add cartografos/redash
/plugin install redash
```

Restart Claude Code (or `/plugin reload`) and verify with `/help` that `/redash:*` shows up.

## Project state directory

Per-project state lives at `<project>/.claude/redash/`:

```
.claude/redash/
├── cache/
│   └── data_sources.json     # catalog cache, TTL 1h
├── recents.json              # last 10 data sources used in this project
└── specs/
    └── <name>.md             # dashboard/query specs (versionable)
```

`.claude/` is gitignored by default in most setups, so credentials-free metadata stays local. `specs/*.md` can be checked in if you want to track them across machines.

## Available commands

### Connectivity

| Command | What it does |
|---|---|
| `/redash:check` | Verify auth, show user, org, and accessible data sources |

### Search and exploration

| Command | What it does |
|---|---|
| `/redash:queries [text] [--mine\|--recent\|--archived] [--page N]` | List/search saved queries (search, mine, recent, archived) |
| `/redash:dashboards [text \| <id>]` | List dashboards or show widgets of one |
| `/redash:data-sources [text] [--type X] [--recent] [--refresh-cache]` | Filter data sources, see recents, refresh cache |
| `/redash:schema <ds-id\|text> [table-substring]` | Tables and columns of a data source |
| `/redash:search <text>` | Cross-search across queries and dashboards |
| `/redash:describe <query_id>` | SQL, parameters, schedule, last result |

### Execution

| Command | What it does |
|---|---|
| `/redash:run <SQL> [--ds <id\|text>] [--export csv\|json\|xlsx]` | Ad-hoc SQL; resolver picks the DS by id or fuzzy text |
| `/redash:query <id> [--param k=v ...] [--export csv\|json\|xlsx]` | Execute a saved query (uses cache when fresh) |
| `/redash:refresh <id> [--param k=v ...]` | Force re-execution (ignores cache) |
| `/redash:format <SQL>` | Format SQL with Redash's built-in formatter |

### Persistence (writes to Redash)

| Command | What it does |
|---|---|
| `/redash:save <SQL> --name "..." [--ds <id\|text>] [--format]` | Save a query to Redash (draft by default) |
| `/redash:fork <query_id>` | Clone an existing query as a draft you own |
| `/redash:archive <query_id>` | Archive (soft-delete) a query — double confirmation |
| `/redash:plan <spec-name>` | Create/extend a project-local spec from queries in conversation |
| `/redash:diff <spec-name>` | Preview what `/redash:apply` would change (read-only) |
| `/redash:apply <spec-name> [--dry-run] [--no-publish] [--prune]` | Materialize a spec into Redash (idempotent) |

## Auto-activating skill

- **`redash-explorer`** — activates when the user asks about saved queries, dashboards, Redash metrics, wants to run ad-hoc SQL, or persist queries/dashboards. Owns the resolver patterns, polling, and spec lifecycle.

## Subagent

| Agent | For |
|---|---|
| `redash:redash-analyst` | Multi-query analysis, dashboard reconciliation, dependency audits, open-ended exploration |

```
@agent-redash:redash-analyst find every query using the orders table on data source 1904
@agent-redash:redash-analyst reconcile GMV between dashboard X and dashboard Y
```

## Data source resolution

The plugin never hardcodes a data source. Three ways to point at one:

1. **Numeric id**: `--ds 1904`.
2. **Fuzzy text**: `--ds "orders prod"` — multi-token AND substring match against the cached catalog. If unique → use; if ambiguous → list candidates and ask.
3. **Recents**: omit `--ds` and the plugin offers the most recently used data sources in this project.

Aliases-by-namespace can be layered on later as a flat JSON file in `.claude/redash/aliases.json` if you want short shortcuts (`--ds gco` → `1904`).

## Spec lifecycle

A "spec" is a `.md` file under `.claude/redash/specs/<name>.md` with YAML frontmatter (dashboard + queries + layout) and SQL bodies. Round trip:

1. Run ad-hoc SQL with `/redash:run` until it's right.
2. `/redash:plan dashboard-name` — append the validated SQL to the spec, fill in metadata.
3. `/redash:diff dashboard-name` — preview changes against Redash.
4. `/redash:apply dashboard-name` — create/update everything; IDs are written back into the spec.
5. Edit the spec by hand later; re-apply for updates. Idempotent.

## Dashboard pipeline (end-to-end)

The full, well-defined pipeline for going from "I need a dashboard" to a live, idempotent dashboard in Redash.

### Phase 1 — Discover the data

Pick the data source and learn its schema before writing any SQL.

```
/redash:check                        # confirm auth and accessible data sources
/redash:data-sources orders          # filter the catalog (fuzzy, multi-token)
/redash:schema "orders prod" orders  # tables/columns; second arg filters tables
```

Outcome: you know the data source name (or id) and the tables/columns you'll query.

### Phase 2 — Prototype each query

Iterate ad-hoc until the SQL is correct and shaped the way the visualization will need it.

```
/redash:run "select date_trunc('day', created_at) d, count(*) n from orders group by 1 order by 1" --ds "orders prod"
/redash:format "<SQL>"               # optional: match Redash's UI formatter
```

Run it as many times as needed. Use `--export csv` if you want to eyeball the full result. **Do not save anything yet** — the spec is the source of truth, not an early `/redash:save`.

### Phase 3 — Capture in a spec

Once a query is right, append it to a project-local spec. Repeat per query.

```
/redash:plan gmv-daily --add-last    # adds the last /redash:run SQL
/redash:plan gmv-daily               # interactive: pick which validated queries to add
/redash:plan gmv-daily --from-query 1234   # pull an existing saved query into the spec
```

For each query you'll be asked for: `key` (machine name, e.g. `orders_daily_total`), `name` (human label), `data_source` (resolved by name or id), `visualization` (`table` | `counter` | `chart` | `pivot`), and `parameters[]` if the SQL has `{{...}}`.

Outcome: `.claude/redash/specs/gmv-daily.md` exists with frontmatter + one `## Query: <key>` SQL block per query. `redash_id` fields are still `null`.

### Phase 4 — Define visualizations and layout

Edit the spec by hand to refine details the planner left as defaults:

- **`visualization.options`** per query (chart type, x/y columns, counter target column, pivot rows/cols).
- **`layout[]`** — a list of `{ query: <key>, row, col, sizeX, sizeY }` entries. Default grid is 12 columns wide.
- **`dashboard.tags`**, **`dashboard.publish`** (keep `false` until reviewed).

The spec is plain markdown + YAML; commit it to the repo if you want it tracked across machines.

### Phase 5 — Preview the change

```
/redash:diff gmv-daily               # read-only: what would /redash:apply do?
/redash:apply gmv-daily --dry-run    # same idea, runs the apply pipeline up to the diff
```

Shows per-query `CREATE` vs `UPDATE`, dashboard create/update, widgets to add/move, and any data-source resolution failures. **Stop here and fix the spec if anything looks wrong.**

### Phase 6 — Apply (materialize into Redash)

```
/redash:apply gmv-daily              # asks for explicit confirmation before mutating
```

Runs in fixed phases: resolve data sources → create/update queries → create/update non-table visualizations → create/update dashboard → place widgets → optional publish → **write IDs back into the spec** (`dashboard.redash_id`, `dashboard.slug`, `queries[].redash_id`). After a successful apply, the spec is the idempotent source of truth.

The final report ends with the dashboard URL: `${REDASH_URL}/dashboards/<slug>`.

### Phase 7 — Iterate

Edit the spec — change SQL, swap a chart for a counter, move a widget — and re-run `/redash:apply`. Because IDs are written back, every subsequent apply is an update, not a duplicate.

```
/redash:diff gmv-daily               # preview the delta
/redash:apply gmv-daily              # apply the delta
/redash:apply gmv-daily --prune      # also delete widgets that are no longer in the spec (double-confirm)
```

### Phase 8 — Publish

When you're ready for the dashboard to leave draft state, set `dashboard.publish: true` (and per-query `publish: true` for queries that should be visible to others) and re-apply. Use `--no-publish` to apply changes without flipping the publish bit.

### Cheat sheet

```
discover    /redash:check  →  /redash:data-sources  →  /redash:schema
prototype   /redash:run (loop)  →  /redash:format
capture     /redash:plan <spec> --add-last  (per query)
preview     /redash:diff <spec>   or   /redash:apply <spec> --dry-run
apply       /redash:apply <spec>
iterate     edit spec  →  /redash:diff  →  /redash:apply  [--prune]
publish     set publish: true in spec  →  /redash:apply
```

## Direct wrapper (for Bash)

```bash
# List queries
${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries?page_size=10" | jq '.results[] | {id, name}'

# Resolve a data source by name → id
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve "orders prod readonly"

# Recent data sources in this project
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds recents 5

# Execute saved query with 1h cache
echo '{"max_age": 3600}' | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/queries/123/results -d @-

# Ad-hoc
DS=$(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve "orders prod readonly")
echo "{\"query\":\"select 1\",\"data_source_id\":$DS,\"max_age\":0}" \
  | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/query_results -d @-
```

## Critical rules

- **Read-only by default**. SQL mutations in `/redash:run` and any Redash entity changes (`/redash:save`, `/redash:apply`) require explicit confirmation.
- **`--prune`** in `/redash:apply` requires a second confirmation listing what gets deleted.
- **Never print** `$REDASH_API_KEY` or export URLs with the key embedded.
- **Cache vs refresh**: default to `max_age: 3600`. Use `max_age: 0` only when the user wants fresh data.
- **Verify the SQL before trusting a query name** — names can lie; the SQL doesn't.

## Plugin layout

```
redash/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── bin/
│   ├── redash-api                 # curl wrapper with auth
│   └── redash-resolve-ds          # data source resolver (cache + recents + fuzzy match)
├── commands/                      # /redash:* slash commands
│   ├── check.md
│   ├── queries.md, dashboards.md, data-sources.md, schema.md, search.md
│   ├── describe.md, query.md, refresh.md, run.md, format.md
│   ├── save.md, fork.md, archive.md
│   ├── plan.md, apply.md, diff.md
├── skills/
│   └── redash-explorer/
│       └── SKILL.md
├── agents/
│   └── redash-analyst.md
└── hooks/
    ├── hooks.json
    └── check-envars.sh            # SessionStart: warns on missing env vars
```

## Troubleshooting

- **`Missing env var REDASH_URL` / `REDASH_API_KEY`**: export the env vars before launching Claude Code (or restart the terminal after editing `~/.zshrc`).
- **`401 Unauthorized`**: API key is invalid or was revoked. Regenerate it in Redash → Settings → Account → API Key.
- **`403 Forbidden`** on a data source/dashboard: your user lacks permission. Check with `/redash:check` which groups you belong to.
- **`404 Not Found`**: archived query/dashboard or wrong id. Search with `/redash:search`.
- **Resolver returns "ambiguous"**: add more tokens to your `--ds "..."`, or pick by id from the candidate list.
- **Resolver cache stale**: `/redash:data-sources --refresh-cache` (or `bin/redash-resolve-ds refresh`).
- **Job timeout**: query is slow. Bump `REDASH_TIMEOUT` or schedule a refresh in the Redash UI instead.
