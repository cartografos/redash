---
description: [redash] Create or update a dashboard spec file (.claude/redash/specs/<name>.md) capturing queries to materialize later via /redash:apply.
argument-hint: <spec-name> [--add-last] [--from-query <id>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*), Read, Write, Edit
---

The user wants to capture the current work into a dashboard spec. Arguments: **$ARGUMENTS**

A spec is a `.md` file in `.claude/redash/specs/<name>.md` that describes a dashboard and its queries. It's the source of truth: `/redash:apply` reads it and creates/updates the corresponding entities in Redash. After the first apply, IDs are written back into the frontmatter for idempotency.

1. **Resolve the spec path**:

   ```bash
   STATE=$(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds state-dir)
   SPEC_DIR="$STATE/specs"
   mkdir -p "$SPEC_DIR"
   SPEC_FILE="$SPEC_DIR/${SPEC_NAME}.md"
   ```

2. **If `$SPEC_FILE` does not exist**, scaffold it with the canonical template (below). If it does exist, read it and merge new content in.

3. **Mode**:
   - Default: append the SQL queries that have already been validated in this conversation. Ask the user to pick which ones (by short summary) and what `key` to give each.
   - `--from-query <id>`: pull a saved query from Redash (`GET /api/queries/<id>`) and add it to the spec verbatim (SQL, parameters, name).
   - `--add-last`: shortcut for "the last `/redash:run` SQL we executed in this session".

4. **For each query being added**, ask the user:
   - `key` (machine-friendly, e.g. `orders_daily_total`).
   - `name` (human-readable).
   - `data_source` (substring or id — yo lo paso por el resolver y guardo `<id>`+`<name>`).
   - `visualization` type: `table` (default), `counter`, `chart` (with sub-options), `pivot`. Add the minimum options needed.
   - `parameters[]` if the SQL has `{{...}}` placeholders.

5. **Layout**: ask the user (or propose one) — list of `{query: <key>, row, col, sizeX, sizeY}` entries. Default to vertical stacking 12 wide.

6. **Write the spec** with the canonical template:

   ````markdown
   ---
   spec_version: 1
   dashboard:
     name: "<dashboard name>"
     slug: ""              # filled after first apply
     redash_id: null       # filled after first apply
     tags: []
     publish: false
   queries:
     - key: <machine_key>
       name: "<human name>"
       redash_id: null     # filled after first apply
       data_source:
         name: "<resolved DS name>"
         id: <resolved id>
       parameters: []
       visualization:
         type: table
         name: "<viz name>"
         options: {}
   layout:
     - { query: <machine_key>, row: 0, col: 0, sizeX: 12, sizeY: 6 }
   ---

   ## Query: <machine_key>

   ```sql
   <SQL>
   ```
   ````

7. After writing, show the user the path of the spec and the keys included. Suggest `/redash:apply <spec-name>` when they're ready to materialize, or re-run `/redash:plan <spec-name>` to add more queries.

8. The spec lives in `.claude/redash/` which is project-local and gitignored — safe for credentials-free metadata.
