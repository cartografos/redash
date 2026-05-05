---
description: [redash] Archive (soft-delete) a saved query. Requires double confirmation.
argument-hint: <query_id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*)
---

The user wants to archive query: **$ARGUMENTS**

Archiving is a soft-delete in Redash — the query becomes invisible from default lists but still exists. Dashboards using it will break visually until widgets are removed. This is **destructive enough** to warrant double confirmation.

1. If `$ARGUMENTS` is not an integer, ask for a `query_id` and stop.

2. **Show full impact** before asking:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries/$ARGUMENTS" \
     | jq '{id, name, data_source_id, user: .user.name, is_archived, schedule, tags}'
   ```

   - If already `is_archived: true`, tell the user and stop (no-op).
   - If it has a `schedule`, warn loudly that archiving disables the schedule.
   - If it powers any dashboard widgets, warn that those widgets will show errors.

3. **First confirmation**: ask the user to type the query name (or "ARCHIVE <id>") to proceed. Stop and wait for them.

4. **Second confirmation**: list once more what will happen (entity, id, name) and ask for a final yes.

5. **Archive**:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api -X DELETE "/api/queries/$ARGUMENTS"
   ```

   Note: the wrapper takes the method as the first arg, so:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api DELETE "/api/queries/$ARGUMENTS"
   ```

6. Report:
   - Archived `query_id` and name.
   - Recovery: tell the user it can be unarchived in Redash via the UI by going to `${REDASH_URL}/queries/archive` (only admins can typically restore).

7. **Never** print the `api_key` field from any of the responses.
