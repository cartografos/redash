---
description: [redash] Execute a saved query by id and return its results (uses cache when fresh; force re-run with /redash:refresh). Supports --export.
argument-hint: <query_id> [--param k=v ...] [--max-rows N] [--export csv|json|xlsx [--out path]]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/redash-api:*), Bash(jq:*), Bash(sleep:*)
---

The user wants to execute saved query: **$ARGUMENTS**

1. If `$ARGUMENTS` does not include an integer `query_id`, ask for it and stop.

2. Parse flags:
   - `--param k=v` (repeatable) → build JSON `{"parameters": {"k":"v", ...}}`.
   - `--max-rows N` (default 50): how many rows to render to the user.
   - `--export FORMAT` (`csv`/`json`/`xlsx`) → after running, download to file instead of/in addition to rendering.
   - `--out PATH` → output path for `--export` (default `./redash_<id>_<timestamp>.<ext>`).

3. Fetch the detail first (useful for display + to know if there's already a `latest_query_data_id`):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries/$ID" > /tmp/redash_q_$ID.json
   ```

   **Never** surface `api_key` from this payload.

4. **Trigger execution**:

   ```bash
   BODY='{"max_age": 3600'"${PARAMS_JSON:+, $PARAMS_JSON}"'}'
   echo "$BODY" | ${CLAUDE_PLUGIN_ROOT}/bin/redash-api POST "/api/queries/$ID/results" -d @- > /tmp/redash_run_$ID.json
   ```

   - `query_result` inline → fresh cache hit; jump to step 6.
   - `job` → poll.

5. **Poll** the job (max 60s or `REDASH_TIMEOUT`):

   ```bash
   JOB_ID=$(jq -r '.job.id' /tmp/redash_run_$ID.json)
   for i in $(seq 1 30); do
     ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/jobs/$JOB_ID" > /tmp/redash_job_$ID.json
     STATUS=$(jq -r '.job.status' /tmp/redash_job_$ID.json)  # 1=pending 2=started 3=success 4=failure 5=canceled
     case "$STATUS" in
       3) RESULT_ID=$(jq -r '.job.query_result_id' /tmp/redash_job_$ID.json); break ;;
       4|5) jq '.job' /tmp/redash_job_$ID.json; exit 1 ;;
     esac
     sleep 2
   done
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/query_results/$RESULT_ID" > /tmp/redash_result_$ID.json
   ```

6. **Render** the results:
   - Header: query name, `runtime`, `retrieved_at`, total row count.
   - Markdown table with `data.columns` as headers and the first `--max-rows` of `data.rows`.
   - If there are more rows than the limit, say how many are missing and offer `--export csv` (or larger `--max-rows`).
   - On error, show `job.error` and suggest checking parameters or DS permissions.

7. **Export** if requested:

   ```bash
   EXT="${FORMAT}"   # csv | json | xlsx
   OUT="${OUT_PATH:-./redash_${ID}_$(date +%Y%m%d_%H%M%S).${EXT}}"
   # Endpoint: /api/queries/<id>/results.<ext> returns the latest cached result.
   ${CLAUDE_PLUGIN_ROOT}/bin/redash-api GET "/api/queries/$ID/results.${EXT}" -o "$OUT"
   echo "exported: $OUT ($(stat -f %z "$OUT" 2>/dev/null || stat -c %s "$OUT") bytes)"
   ```

   - `404 "No cached result found"` → the query has no cached result yet; tell the user to run it first (`/redash:query <id>` without `--export` populates the cache).
   - For `xlsx`, the wrapper still works because Redash determines content type from the URL extension; the file is binary, so always use `--out` to write to disk and never pipe to stdout.

8. **Never** print `$REDASH_API_KEY` or any per-query `api_key`. Never embed keys in URLs you show to the user.
