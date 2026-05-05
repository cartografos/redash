---
description: [redash] Force re-execution of a saved query (ignores cache). Returns fresh results.
argument-hint: <query_id> [--param k=v ...] [--max-rows N]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*), Bash(sleep:*)
---

The user wants to refresh query: **$ARGUMENTS**

Same as `/redash:query` but with `max_age: 0` to force re-computation.

1. Validate `query_id` and parse `--param k=v` and `--max-rows N`.

2. POST forcing a re-run:

   ```bash
   BODY='{"max_age": 0'"${PARAMS_JSON:+, $PARAMS_JSON}"'}'
   echo "$BODY" | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST "/api/queries/$ID/results" -d @-
   ```

3. The response will always come back as `job` (no valid cache with `max_age=0`). Poll the same way as `/redash:query`:
   - `GET /api/jobs/<id>` every 2s.
   - `status=3` → `GET /api/query_results/<query_result_id>`.
   - `status=4|5` → show `job.error`.

4. Present results just like `/redash:query` (header + table + runtime).

5. Mention current `runtime` versus the previously cached one (if known from `/redash:describe`) to flag performance regressions.
