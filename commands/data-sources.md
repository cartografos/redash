---
description: [redash] List data sources. Filter by name/type, show recents, or refresh the local cache.
argument-hint: [name-substring] [--type postgres|mysql|...] [--recent] [--refresh-cache] [--all]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(jq:*)
---

The user wants to inspect data sources. Arguments: **$ARGUMENTS**

A typical Redash instance has thousands of data sources. **Always** filter — never dump the whole list unless the user explicitly asks with `--all`.

1. **Mode dispatch.** Detect flags in `$ARGUMENTS`:
   - `--recent` → show recently used DSs in this project.
   - `--refresh-cache` → force-refresh the catalog cache and report the count.
   - `--type X` → filter by exact `.type` (e.g. `pg`, `mysql`, `mongodb`, `bigquery`, `snowflake`, `redshift`).
   - `--all` → dump everything (warn if >100 results).
   - Otherwise → free-text substring filter against `.name` (case-insensitive AND on tokens).

2. **`--recent` mode**:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds recents 10
   ```

   Render as `id | name | type | last_used_at`. If empty, say "no recents in this project — use `/redash:run` or `/redash:data-sources <text>` to populate".

3. **`--refresh-cache` mode**:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds refresh
   ```

   Report the cached count and the file path.

4. **Search/filter mode**: use the resolver's local cache (project-local `.claude/redash/cache/data_sources.json`, TTL 1h, auto-refreshed):

   ```bash
   # The cache lives under the resolver's state dir; just call the resolver to ensure it's fresh.
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds resolve __ensure__ >/dev/null 2>&1 || true
   STATE=$(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds state-dir)
   CACHE="$STATE/cache/data_sources.json"

   # Multi-token AND on name (case-insensitive)
   jq --arg q "$SEARCH" '
     ($q | ascii_downcase | split(" ") | map(select(. != ""))) as $toks
     | [.[]
         | (.name | ascii_downcase) as $n
         | select(all($toks[]; . as $t | $n | contains($t)))
         | {id, name, type}]
     | sort_by(.name)
   ' "$CACHE"

   # By type
   jq --arg t "$TYPE" '[.[] | select(.type == $t) | {id, name, type}] | sort_by(.name)' "$CACHE"
   ```

5. Render as a markdown table (`id | name | type`). If there are more than 30 matches, show the first 30 + total and suggest narrowing the filter (or pinning one with `--ds <id>` in `/redash:run`).

6. Mention that the user can pin a DS by id, by exact substring, or rely on recents — no env var needed.
