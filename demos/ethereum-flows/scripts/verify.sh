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

out=$(bq --project_id="$GCP_PROJECT" query \
        --use_legacy_sql=false --format=csv --quiet \
        --maximum_bytes_billed="$MAX_BYTES_BILLED" \
        "GRAPH \`$GCP_PROJECT.$BQ_DATASET.$BQ_GRAPH\`
         MATCH (a:Address)-[s:SENT]->(b:Address)
         RETURN a.address AS sender, b.address AS recipient, s.total_eth AS eth
         ORDER BY eth DESC
         LIMIT 5" 2>&1) || {
  # bq writes query errors to stdout, not stderr, so capture both streams.
  e=$(printf '%s' "$out" | tr '\n' ' ')
  case "$e" in
    *eservation*|*dition*|*n-demand*)
      die "GQL rejected on edition or reservation grounds." \
          "Uncommon — GQL was verified working on on-demand pricing. If your project does need one, add an Enterprise or Enterprise Plus reservation. Your data is built; only the query is blocked. See docs/PREVIEW_NOTES.md." ;;
    *)
      die "Verification query failed: ${e:-unknown error}" \
          "Re-run './gxr up ethereum-flows' — setup is idempotent. If it persists, open an issue with this output." ;;
  esac
}

rows=$(printf '%s\n' "$out" | tail -n +2 | grep -c . || true)
[ "${rows:-0}" -ge 1 ] || die "Graph query returned no rows." \
  "No wallet-to-wallet transfers survived the filters. Lower MIN_ETH or raise TOP_N_ADDRESSES in .env, then re-run setup."

ok "GQL query returned $rows row(s)"
[ "$GXR_JSON" = 1 ] || printf '%s\n' "$out" | column -s, -t | sed 's/^/      /'
echo "$rows" > "$DEMO_DIR/.verified_rows"
