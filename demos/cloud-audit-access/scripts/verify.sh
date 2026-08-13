#!/usr/bin/env bash
# Prove the graph works AND that the planted escalation paths are findable.
# Asserts, does not describe.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=verify
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Verify — running the escalation-path query"

load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH MAX_BYTES_BILLED

err_file=$(mktemp); trap 'rm -f "$err_file"' EXIT

# Deliberately the demo's headline query, not a trivial smoke test: if this
# returns nothing, the demo is pointless even though the graph "works".
out=$(bq --project_id="$GCP_PROJECT" query \
        --use_legacy_sql=false --format=csv --quiet \
        --maximum_bytes_billed="$MAX_BYTES_BILLED" \
        "GRAPH \`$GCP_PROJECT.$BQ_DATASET.$BQ_GRAPH\`
         MATCH (actor:Principal)-[:CAN_IMPERSONATE]->(proxy:Principal)-[:ACCESSED]->(r:Resource)
         WHERE r.sensitivity IN ('high', 'critical')
         RETURN actor.name AS actor, proxy.name AS impersonates, r.name AS reaches
         ORDER BY actor
         LIMIT 10" 2>"$err_file") || {
  e=$(tr '\n' ' ' < "$err_file")
  case "$e" in
    *eservation*|*dition*|*n-demand*)
      die "GQL rejected — this is the pre-GA reservation requirement." \
          "BigQuery Graph needs an Enterprise or Enterprise Plus reservation for GQL. See docs/PREVIEW_NOTES.md. Your data is built; only the query is blocked." ;;
    *)
      die "Verification query failed: ${e:-unknown error}" \
          "Re-run './gxr up cloud-audit-access' — setup is idempotent. If it persists, open an issue with this output." ;;
  esac
}

rows=$(printf '%s\n' "$out" | tail -n +2 | grep -c . || true)
[ "${rows:-0}" -ge 1 ] || die "No escalation paths found — the demo's central finding is missing." \
  "The data is seeded, so this should not happen. Re-run setup; if it persists, open an issue."

ok "found $rows escalation path(s) — the demo's headline finding is present"
[ "$GXR_JSON" = 1 ] || printf '%s\n' "$out" | column -s, -t | sed 's/^/      /'
echo "$rows" > "$DEMO_DIR/.verified_rows"
