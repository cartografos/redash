---
description: [redash] Verify connectivity to Redash, authenticate the API key, and show current user info.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(printenv:*), Bash(jq:*)
---

Verify the Redash plugin is correctly configured.

1. Confirm env vars are set (without printing the API key):

```bash
printenv | grep -E '^REDASH_(URL|DATA_SOURCE_ID|TIMEOUT)=' || echo "Missing REDASH_* env vars"
[[ -n "${REDASH_API_KEY:-}" ]] && echo "REDASH_API_KEY=<set>" || echo "REDASH_API_KEY=<missing>"
```

2. Test authentication against `/api/session` (returns the current user):

```bash
${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET /api/session | jq '{user: .user.name, email: .user.email, groups: .user.groups, org: .org_slug}'
```

3. List data sources available to the user:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET /api/data_sources | jq '[.[] | {id, name, type}]'
```

4. Report to the user:
   - ✅/❌ env vars present (URL + API key)
   - ✅/❌ authentication successful (user name + email + org)
   - List of data sources (id, name, type) — useful for `/redash:run`
   - On failure: diagnose (wrong URL, invalid API key, network blocked) and suggest a fix.
