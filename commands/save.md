---
description: [redash] Save a query to Redash (creates a new persisted query, draft by default). Optionally format the SQL first.
argument-hint: <SQL> --name "Query Name" [--ds <id|text>] [--description "..."] [--publish] [--tags a,b,c] [--format]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(jq:*)
---

The user wants to persist an ad-hoc query into Redash. Arguments: **$ARGUMENTS**

1. **Required**: `<SQL>` (positional or fenced) and `--name "..."`.
   - If either is missing, ask for it and stop.
   - Optional: `--description`, `--tags a,b,c`, `--publish` (otherwise saves as draft), `--ds <id|text>`, `--format`.

2. **Resolve the data source** with the same logic as `/redash:run`:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve "<value>"
   ```

   - If `--ds` is missing, fall back to recents and ask the user to pick.

3. **Format the SQL** if `--format` is present:

   ```bash
   FORMATTED=$(jq -n --arg q "$SQL" '{query: $q}' \
     | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/queries/format -d @- \
     | jq -r '.query')
   SQL="$FORMATTED"
   ```

   Show the user the before/after diff (or just the formatted version) before continuing.

4. **Show a dry-run** to the user before creating:
   - Resolved DS: `id`, `name`, `type`.
   - Query name, description, tags.
   - Visibility: `draft` or `published`.
   - First 5 lines of the (final) SQL.

   Wait for explicit confirmation in the current turn.

5. **Create the query**:

   ```bash
   jq -n \
     --arg name "$NAME" \
     --arg desc "$DESCRIPTION" \
     --arg q "$SQL" \
     --argjson ds "$DS_ID" \
     --argjson tags "$TAGS_JSON" \
     '{name:$name, description:$desc, query:$q, data_source_id:$ds, tags:$tags, options:{parameters:[]}}' \
     | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/queries -d @- > /tmp/redash_save.json

   QUERY_ID=$(jq -r '.id' /tmp/redash_save.json)
   ```

6. **Publish** if requested (Redash creates queries as draft by default):

   ```bash
   echo '{"is_draft": false}' \
     | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST "/api/queries/$QUERY_ID" -d @-
   ```

7. **Remember the DS** for recents:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds remember "$DS_ID" >/dev/null
   ```

8. Report:
   - Created `query_id`.
   - URL: `${REDASH_URL}/queries/<id>` (do NOT embed the API key).
   - Visibility: draft / published.
   - Suggest `/redash:query <id>` to run it now, `/redash:fork <id>` to clone, or `/redash:plan` to add it to a dashboard spec.

9. **Never** print `$REDASH_API_KEY` or any per-query `api_key` from the response.
