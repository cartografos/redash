---
description: [redash] Show full detail of a query — SQL, parameters, schedule, data source, last result.
argument-hint: <query_id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*)
---

The user wants the detail of query: **$ARGUMENTS**

1. If `$ARGUMENTS` is not an integer, ask for a valid `query_id` and stop.

2. Fetch the detail:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries/$ARGUMENTS"
   ```

3. Present to the user:
   - **Header**: `id`, `name`, `data_source_id`, `user.name`, `updated_at`, `is_archived`, `is_draft`, `tags`.
   - **Schedule**: if present, translate `interval` (seconds) into a human-readable cadence (e.g. `3600` → "every 1h"). If absent, say "manual".
   - **Parameters**: list of `options.parameters[]` with `name`, `type`, default `value`. If none, "no parameters".
   - **SQL**: ```sql block with the `query` field.
   - **Last result**: `latest_query_data_id` if present, with `runtime` and `retrieved_at`.

4. Suggest: `/redash:query <id>` to execute, `/redash:refresh <id>` to force re-run.
