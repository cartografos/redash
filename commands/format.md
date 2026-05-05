---
description: [redash] Format SQL using Redash's built-in formatter (matches the UI's Format button).
argument-hint: <SQL>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*)
---

The user wants to format SQL: **$ARGUMENTS**

1. If `$ARGUMENTS` is empty, ask for the SQL and stop.

2. **POST to the formatter**:

   ```bash
   jq -n --arg q "$SQL" '{query: $q}' \
     | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST /api/queries/format -d @- \
     | jq -r '.query'
   ```

3. **Render** the formatted SQL inside a ```sql block. Keep it terse — no commentary unless the user asked for analysis.

4. Suggest: `/redash:save <SQL> --name "..."` to persist the formatted version, or copy/paste back into the editor.

5. The formatter is server-side and uses Redash's own SQL parser, so it matches what the UI's Format button produces. It does not validate the SQL or check schema — it only re-indents and normalizes whitespace.
