---
description: [redash] Compare a dashboard spec against what currently exists in Redash. Shows what /redash:apply would change.
argument-hint: <spec-name>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-resolve-ds:*), Bash(jq:*), Read
---

The user wants to diff a spec against Redash. Arguments: **$ARGUMENTS**

Read-only counterpart of `/redash:apply` — does not mutate anything.

1. **Locate and parse the spec** the same way as `/redash:apply` Phase 0.

2. **Resolve data sources** for any query whose `data_source.id` is null (Phase 1).

3. **For each query**:
   - If `redash_id` is null → `WOULD CREATE` (show name, ds, first 5 lines of SQL).
   - If `redash_id` set:
     - `GET /api/queries/<id>` and compare:
       - `name`, `data_source_id`, `query` (SQL string), `options.parameters[]`.
     - For each diff field, show `current → spec`.
     - If the query is `is_archived: true` upstream, flag it loudly.

4. **For the dashboard**:
   - If `redash_id` null → `WOULD CREATE`.
   - Else `GET /api/dashboards/<slug>` and compare `name`, `tags`, `is_draft`.

5. **For widgets**:
   - List spec layout entries with their target `visualization_id` (resolved from each query's vizes).
   - Compare with `dashboard.widgets[]`. Show widgets that would be created, updated (position changed), or — if `--prune` were used — deleted.

6. **Render** as three sections (Queries / Dashboard / Widgets), each with a table of changes. Use icons or symbols sparingly: `+` create, `~` update, `-` delete (only with `--prune` warning).

7. End with: "Run `/redash:apply <spec-name>` to apply these changes (or `--dry-run` for a write-protected preview)."

8. **Never** print `$REDASH_API_KEY`.
