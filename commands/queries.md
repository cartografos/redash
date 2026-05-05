---
description: [redash] List/search saved queries. Modes: search, --mine, --recent, --archived.
argument-hint: [search text] [--mine | --recent | --archived] [--page N] [--page-size N]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*)
---

The user wants to list/search queries in Redash. Arguments: **$ARGUMENTS**

1. **Mode dispatch** — detect flags first:
   - `--mine` → queries owned by the current user (paginated).
   - `--recent` → queries the user has recently viewed/edited (flat array, not paginated).
   - `--archived` → archived queries the user can see (paginated).
   - Otherwise → text search via `q=` (paginated).

2. Parse `--page N` (default 1) and `--page-size N` (default 25, max 250) for paginated modes.

3. **Build the URL** based on mode:

   ```bash
   case "$MODE" in
     mine)
       URL="/api/queries/my?page=${PAGE:-1}&page_size=${PAGE_SIZE:-25}"
       ;;
     recent)
       URL="/api/queries/recent?limit=${PAGE_SIZE:-20}"
       ;;
     archived)
       URL="/api/queries/archive?page=${PAGE:-1}&page_size=${PAGE_SIZE:-25}"
       ;;
     *)
       QS="page=${PAGE:-1}&page_size=${PAGE_SIZE:-25}"
       [[ -n "${SEARCH:-}" ]] && QS="${QS}&q=$(printf '%s' "$SEARCH" | jq -sRr @uri)"
       URL="/api/queries?${QS}"
       ;;
   esac
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "$URL" > /tmp/redash_queries.json
   ```

4. **Process** with `jq`. Note: `recent` is a flat array, the others have `{count, page, page_size, results}`:

   ```bash
   # Paginated modes
   jq '{count, page, page_size, results: [.results[] | {id, name, data_source_id, user: .user.name, updated_at, is_archived, is_draft, tags}]}' /tmp/redash_queries.json

   # Recent (flat array)
   jq '[.[] | {id, name, data_source_id, user: .user.name, updated_at, is_archived, is_draft, tags}]' /tmp/redash_queries.json
   ```

5. **Render** as a markdown table: `id | name | data_source_id | user | updated_at | tags`.
   - For paginated modes: include `count` total + page indicator + how to fetch the next page.
   - For `--recent`: include the count returned (max ~20).
   - For `--archived`: prefix the name with `[archived]` for clarity.

6. **Never** print the `api_key` field from any query object.

7. Suggest: `/redash:describe <id>` for details, `/redash:query <id>` to execute, `/redash:fork <id>` to clone, `/redash:archive <id>` to soft-delete.
