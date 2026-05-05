---
description: [redash] Run ad-hoc SQL against a data source. Resolves --ds by name (fuzzy multi-token) or id; falls back to recents. Supports --export.
argument-hint: <SQL> [--ds <id|text>] [--max-rows N] [--export csv|json|xlsx [--out path]]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(jq:*), Bash(sleep:*)
---

The user wants to run ad-hoc SQL: **$ARGUMENTS**

1. If `$ARGUMENTS` is empty, ask for the SQL and stop.

2. **Resolve the data source.** Order:

   1. If the args contain `--ds <value>`, pass `<value>` to the resolver:

      ```bash
      ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve "<value>"
      ```

      - exit `0` → stdout is the numeric id. Use it.
      - exit `1` (no_match) → show `suggestions` from the JSON to the user, ask them to refine. Stop.
      - exit `2` (ambiguous) → show the numbered `candidates` list (`name`, `id`, `type`) to the user and ask them to pick one (by id or with a more specific `--ds` substring). Stop.

   2. If `--ds` is absent, fall back to recents:

      ```bash
      ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds recents 5
      ```

      - If non-empty: present the list (id, name, type, `last_used_at`) and ask the user to pick — or to provide `--ds <text>`/`<id>`. Stop and wait for the answer.
      - If empty: tell the user there's no recent DS in this project; suggest `/redash:data-sources <text>` to find one or `/redash:run "<SQL>" --ds <text-or-id>`. Stop.

   3. `REDASH_DATA_SOURCE_ID` env var is honored as a last resort if set (still subject to user confirmation in the first turn).

3. **Safety check.** If the SQL contains `INSERT`, `UPDATE`, `DELETE`, `DROP`, `TRUNCATE`, `ALTER`, `CREATE`, `GRANT`, or `REVOKE`, **stop** and ask for explicit confirmation in the current turn before continuing. Most analytics data sources are read-only, but do not assume.

4. **Build body and trigger**:

   ```bash
   jq -n --arg q "$SQL" --argjson ds "$DS_ID" \
     '{query: $q, data_source_id: $ds, max_age: 0}' \
     | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/query_results -d @- > /tmp/redash_adhoc.json
   ```

5. **Poll** the same way as `/redash:query`:
   - Inline `query_result` → render.
   - `job` → poll `GET /api/jobs/<id>` every 2s until `status=3`, then `GET /api/query_results/<id>`.
   - `status=4|5` → show `job.error` and abort.
   - **Capture** the resulting `RESULT_ID` (you'll need it for `--export`).

6. **Remember the DS** so future runs can fall back to recents:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds remember "$DS_ID" >/dev/null
   ```

7. **Render**:
   - Executed SQL (```sql block).
   - Markdown table with the first `--max-rows` (default 50) rows.
   - Total row count and `runtime` in seconds.
   - If the query is slow (>10s) or returns >1000 rows, suggest persisting it with `/redash:save` for scheduling/cache.

8. **Export** if requested:

   ```bash
   EXT="${FORMAT}"   # csv | json | xlsx
   OUT="${OUT_PATH:-./redash_adhoc_$(date +%Y%m%d_%H%M%S).${EXT}}"
   # Endpoint: /api/query_results/<result_id>.<ext> downloads this specific result.
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/query_results/${RESULT_ID}.${EXT}" -o "$OUT"
   echo "exported: $OUT ($(stat -f %z "$OUT" 2>/dev/null || stat -c %s "$OUT") bytes)"
   ```

   For `xlsx` always pipe to a file (`-o`) — never stdout.

9. **Never** print `$REDASH_API_KEY` and never put SQL in the URL as a query string.
