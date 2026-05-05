---
description: [redash] Materialize a dashboard spec into Redash — create/update queries, visualizations, dashboard, and widgets. Idempotent.
argument-hint: <spec-name> [--dry-run] [--no-publish] [--prune]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(jq:*), Read, Edit
---

The user wants to apply a spec to Redash. Arguments: **$ARGUMENTS**

This command takes the spec file `.claude/redash/specs/<spec-name>.md` and creates/updates entities in Redash to match. After a successful apply, it writes back the resolved IDs (`query.redash_id`, `dashboard.redash_id`, `dashboard.slug`) into the spec, making future runs idempotent.

## Phase 0 — Locate and parse the spec

```bash
STATE=$(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds state-dir)
SPEC_FILE="$STATE/specs/${SPEC_NAME}.md"
[[ -f "$SPEC_FILE" ]] || { echo "spec not found: $SPEC_FILE"; exit 1; }
```

Read the spec, extract:
- **Frontmatter** (YAML between `---`): `dashboard.{name,slug,redash_id,tags,publish}`, `queries[].{key,name,redash_id,data_source,parameters,visualization}`, `layout[]`.
- **SQL blocks**: each `## Query: <key>` block followed by a fenced ```sql ... ``` block.

If `$SPEC_FILE` is malformed (missing required fields, unknown keys), report the issue and stop.

## Phase 1 — Resolve data sources

For each query whose `data_source.id` is null, run:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve "<data_source.name>"
```

If any resolves with exit `1`/`2`, stop and report. The user must update the spec with a more specific name or an explicit id.

## Phase 2 — Dry-run preview

Show the user a diff-style preview:
- For each query: `CREATE` (no `redash_id`) or `UPDATE` (has `redash_id`); list the changed fields if updating.
- Dashboard: `CREATE` or `UPDATE`; show name, tags, publish state.
- Layout: list widgets to create/update.

If `--dry-run`, print this summary and exit. Otherwise, **stop and ask for explicit confirmation** in the current turn before continuing.

## Phase 3 — Apply queries

For each query in the spec:

```bash
# Build payload.
BODY=$(jq -n \
  --arg name "$Q_NAME" \
  --arg q "$Q_SQL" \
  --argjson ds "$Q_DS_ID" \
  --argjson params "$Q_PARAMS_JSON" \
  '{name:$name, query:$q, data_source_id:$ds, options:{parameters:$params}}')

if [[ -z "$Q_REDASH_ID" || "$Q_REDASH_ID" == "null" ]]; then
  # Create
  RESP=$(echo "$BODY" | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/queries -d @-)
  NEW_ID=$(jq -r '.id' <<<"$RESP")
else
  # Update
  RESP=$(echo "$BODY" | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST "/api/queries/$Q_REDASH_ID" -d @-)
  NEW_ID="$Q_REDASH_ID"
fi
${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds remember "$Q_DS_ID" >/dev/null
```

Capture `NEW_ID` per query — needed for visualizations and widgets.

## Phase 4 — Apply visualizations

Each query has a default `TABLE` visualization auto-created by Redash. To use a non-table viz:

```bash
# Get current visualizations on the query.
${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries/$NEW_ID" | jq '.visualizations'
```

For each spec viz that isn't `table`:
- If a viz with the same `name` exists → `POST /api/visualizations/<viz_id>` to update.
- Else → `POST /api/visualizations` with `{query_id, type, name, options}`.

Save the resulting `visualization_id` per query (needed for widgets).

## Phase 5 — Apply dashboard

```bash
if [[ -z "$D_REDASH_ID" || "$D_REDASH_ID" == "null" ]]; then
  RESP=$(jq -n --arg n "$D_NAME" '{name:$n}' \
    | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/dashboards -d @-)
  D_REDASH_ID=$(jq -r '.id' <<<"$RESP")
  D_SLUG=$(jq -r '.slug' <<<"$RESP")
fi

# Update tags / name if changed.
jq -n --arg n "$D_NAME" --argjson tags "$D_TAGS" '{name:$n, tags:$tags}' \
  | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST "/api/dashboards/$D_SLUG" -d @-
```

## Phase 6 — Apply widgets

For each `layout[]` entry, fetch current widgets via `GET /api/dashboards/<slug>` and:
- If a widget already points at the matching `visualization_id` → `POST /api/widgets/<widget_id>` with new `options.position`.
- Else → `POST /api/widgets` with `{dashboard_id, visualization_id, options:{position:{row,col,sizeX,sizeY}}, width: 1}`.

If `--prune` is set: delete widgets in the dashboard that are not referenced by the spec. Otherwise leave orphans alone and warn.

## Phase 7 — Publish

If `publish: true` in the spec (and not `--no-publish`):

```bash
echo '{"is_draft": false}' \
  | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST "/api/dashboards/$D_SLUG" -d @-
```

Same for queries that have `publish: true` (default false at the query level).

## Phase 8 — Write back IDs to the spec

Edit `$SPEC_FILE` to fill in:
- `dashboard.redash_id`, `dashboard.slug`.
- For each query: `redash_id`.

This is what makes the next `/redash:apply` an update instead of a duplicate.

## Final report

Summarize what changed, with one line per entity (created/updated, id, name, URL). End with the dashboard URL: `${REDASH_URL}/dashboards/<slug>`.

## Safety rules

- **Never** print `$REDASH_API_KEY` or include it in URLs shown to the user.
- **Confirmation** is mandatory before any non-dry-run mutation.
- **`--prune`** requires a second explicit confirmation step listing what will be deleted.
- If any phase fails, stop and report — do not retry destructive operations automatically.
