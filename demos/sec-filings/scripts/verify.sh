#!/usr/bin/env bash
# Prove the graph works with a real GQL query. Asserts, does not describe.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=verify
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Verify — running a real GQL query"

load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH MAX_BYTES_BILLED

err_file=$(mktemp); trap 'rm -f "$err_file"' EXIT

out=$(bq --project_id="$GCP_PROJECT" query \
        --use_legacy_sql=false --format=csv --quiet \
        --maximum_bytes_billed="$MAX_BYTES_BILLED" \
        "GRAPH \`$GCP_PROJECT.$BQ_DATASET.$BQ_GRAPH\`
         MATCH (c:Company)-[:ENTERING]->(m:Market)
         RETURN c.id AS company, m.id AS market
         LIMIT 10" 2>"$err_file") || {
  e=$(tr '\n' ' ' < "$err_file")
  case "$e" in
    *eservation*|*dition*|*n-demand*)
      die "GQL rejected — this is the pre-GA reservation requirement." \
          "BigQuery Graph needs an Enterprise or Enterprise Plus reservation for GQL. See docs/PREVIEW_NOTES.md. Your data is built; only the query is blocked." ;;
    *)
      die "Verification query failed: ${e:-unknown error}" \
          "Confirm the pipeline finished. Its node tables live in $BQ_DATASET." ;;
  esac
}

rows=$(printf '%s\n' "$out" | tail -n +2 | grep -c . || true)
[ "${rows:-0}" -ge 1 ] || die "Graph query returned no rows." \
  "The graph exists but has no Company->Market edges. Gemini may have extracted nothing for these tickers — try different SEC_TICKERS."

ok "GQL query returned $rows row(s)"
[ "$GXR_JSON" = 1 ] || printf '%s\n' "$out" | column -s, -t | sed 's/^/      /'
echo "$rows" > "$DEMO_DIR/.verified_rows"
