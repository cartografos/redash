---
description: [redash] Cross-search across queries and dashboards by text.
argument-hint: <text>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*)
---

The user wants to search: **$ARGUMENTS**

1. If `$ARGUMENTS` is empty, ask for text and stop.

2. URL-encode the text and run both calls in parallel:

   ```bash
   Q=$(printf '%s' "$ARGUMENTS" | jq -sRr @uri)
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries?q=${Q}&page_size=10" > /tmp/redash_search_q.json &
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/dashboards?q=${Q}&page_size=10" > /tmp/redash_search_d.json &
   wait
   ```

3. Show two sections:

   **Queries** (top 10 by Redash relevance):
   ```bash
   jq '[.results[] | {id, name, data_source_id, user: .user.name, updated_at}]' /tmp/redash_search_q.json
   ```

   **Dashboards** (top 10):
   ```bash
   jq '[.results[] | {id, slug, name, user: .user.name, updated_at}]' /tmp/redash_search_d.json
   ```

4. In each section include the total `count` returned by the API. If there are more matches, explain how to paginate (`/redash:queries <text> --page 2`, `/redash:dashboards <text> --page 2`).

5. Suggest the next step based on what the user seems to want (description → `/redash:describe`, execution → `/redash:query`, dashboard → `/redash:dashboards <id>`).
