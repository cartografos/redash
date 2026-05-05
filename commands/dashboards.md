---
description: [redash] List dashboards. Supports text search and pagination. With an id, shows widgets.
argument-hint: [search text | <dashboard_id>] [--page N] [--page-size N]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*)
---

The user wants to list dashboards or view one: **$ARGUMENTS**

1. If `$ARGUMENTS` is an integer → detail mode. Jump to step 4.

2. List mode. Parse free text + `--page N` (default 1) + `--page-size N` (default 25).

   ```bash
   QS="page=${PAGE:-1}&page_size=${PAGE_SIZE:-25}"
   [[ -n "${SEARCH:-}" ]] && QS="${QS}&q=$(printf '%s' "$SEARCH" | jq -sRr @uri)"
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/dashboards?${QS}"
   ```

3. Markdown table: `id | slug | name | user | updated_at | tags | is_archived`. If there are more pages, mention it.

4. **Detail mode** (`/redash:dashboards <id>`):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/dashboards/$ID"
   ```

   Show:
   - Header: `name`, `slug`, `user.name`, `updated_at`, `tags`.
   - List of widgets with `id`, `visualization.query.id`, `visualization.query.name`, `visualization.type`, `visualization.name`, position (row/col/sizeX/sizeY).
   - Canonical URL: `${REDASH_URL}/dashboards/<slug>`.
   - Suggest: `/redash:query <query_id>` to execute any widget; `/redash:describe <query_id>` to see the SQL.
