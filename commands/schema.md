---
description: [redash] Show tables and columns of a data source. Filter by table-name substring to narrow huge schemas.
argument-hint: <ds-id|text> [table-substring]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(jq:*)
---

The user wants the schema of a data source. Arguments: **$ARGUMENTS**

1. **Resolve the data source** (id or fuzzy text) via the resolver:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve "<value>"
   ```

   - Exit 0 → numeric id.
   - Exit 1/2 → present suggestions/candidates and stop.

2. **Fetch the schema** (this can be huge on production data sources — sometimes thousands of tables):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/data_sources/$DS_ID/schema" > /tmp/redash_schema_$DS_ID.json
   ```

3. **Filter** if the user provided a table substring:

   ```bash
   # Tables matching the substring (case-insensitive)
   jq --arg q "$TABLE_FILTER" '
     .schema
     | map(select(.name | ascii_downcase | contains($q | ascii_downcase)))
     | sort_by(.name)
   ' /tmp/redash_schema_$DS_ID.json
   ```

   If no filter, show only the **table names** first (a list) plus the total count, and tell the user to re-run with a substring to drill into columns.

4. **Render**:
   - If filtered to ≤20 tables: show each table with its columns as a markdown sub-list:
     ```
     ### <table_name>
     - column_a: type
     - column_b: type
     ```
   - If filtered to >20 tables: list table names only and tell the user to narrow the filter further.
   - If the schema is empty (`schema: []`), the data source might not support introspection (some types — e.g. mongo — only return collections, others return nothing). Mention it.

5. **Remember the DS** (it counts as a use):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds remember "$DS_ID" >/dev/null
   ```

6. Suggest follow-ups: `/redash:run` for ad-hoc against this DS, `/redash:queries <table_name>` to find existing queries that touch the table.

7. Some Redash versions have `POST /api/data_sources/<id>/schema?refresh=true` to force re-introspection. If the schema looks stale, mention this option (do NOT call it without explicit user request — it can be slow on big DBs).
