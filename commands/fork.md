---
description: [redash] Fork a saved query — creates a copy you own as draft, ready to edit.
argument-hint: <query_id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(jq:*)
---

The user wants to fork query: **$ARGUMENTS**

1. If `$ARGUMENTS` is not an integer, ask for a `query_id` and stop.

2. **Show what's about to be forked** (small preview to confirm intent):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries/$ARGUMENTS" \
     | jq '{id, name, data_source_id, user: .user.name, is_archived, tags, query_first_lines: (.query | split("\n") | .[:5])}'
   ```

   If `is_archived: true`, warn the user but allow it.

3. **Confirm with the user** before mutating (forking creates a new entity in Redash).

4. **Fork**:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST "/api/queries/$ARGUMENTS/fork" -d '{}' > /tmp/redash_fork.json
   NEW_ID=$(jq -r '.id' /tmp/redash_fork.json)
   ```

5. **Remember the DS** of the fork:

   ```bash
   DS_ID=$(jq -r '.data_source_id' /tmp/redash_fork.json)
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds remember "$DS_ID" >/dev/null 2>&1 || true
   ```

6. Report:
   - New `query_id`.
   - URL: `${REDASH_URL}/queries/<id>` (do NOT include `?api_key=`).
   - Visibility: forks are created as draft.
   - Suggest: `/redash:describe <new_id>` to inspect, `/redash:query <new_id>` to run, `/redash:save` is not needed (already saved).

7. **Never** print the `api_key` field from the response; it's the per-query key and must stay private.
