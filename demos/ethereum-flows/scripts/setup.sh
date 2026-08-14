#!/usr/bin/env bash
# Materialize one day of Ethereum transfers and build the graph.
# Idempotent: CREATE OR REPLACE throughout.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=setup
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Setup — building the graph"

load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION ETH_DATE TOP_N_ADDRESSES MIN_ETH MAX_BYTES_BILLED

render() {
  sed -e "s|\${PROJECT}|$GCP_PROJECT|g" \
      -e "s|\${DATASET}|$BQ_DATASET|g" \
      -e "s|\${GRAPH}|$BQ_GRAPH|g" \
      -e "s|\${ETH_DATE}|$ETH_DATE|g" \
      -e "s|\${TOP_N}|$TOP_N_ADDRESSES|g" \
      -e "s|\${MIN_ETH}|$MIN_ETH|g" \
      "$1"
}

# bq echoes every statement it runs, which buries the actual progress output.
# Capture it and surface it only when something fails.
run_sql() {
  local out
  if ! out=$(bq --project_id="$GCP_PROJECT" query \
       --use_legacy_sql=false --quiet --format=none \
       --maximum_bytes_billed="$MAX_BYTES_BILLED" < "$1" 2>&1); then
    printf '%s\n' "$out" >&2
    return 1
  fi
  return 0
}

if bq --project_id="$GCP_PROJECT" show --dataset "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  info "dataset $BQ_DATASET already exists"
else
  bq --project_id="$GCP_PROJECT" mk --dataset \
     --location="$BQ_LOCATION" \
     --description="Kineviz Ethereum flows demo. Safe to delete." \
     "$GCP_PROJECT:$BQ_DATASET" >/dev/null
  ok "created dataset $BQ_DATASET in $BQ_LOCATION"
fi

info "materializing $ETH_DATE — top $TOP_N_ADDRESSES addresses, transfers >= $MIN_ETH ETH (~2 min)"
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
render "$DEMO_DIR/sql/01_materialize.sql" > "$tmp"
run_sql "$tmp" || die "Materialization failed." \
  "If it mentions maximum_bytes_billed, choose a lighter ETH_DATE or lower TOP_N_ADDRESSES — do not raise the ceiling."
ok "materialized 6 tables"

info "creating property graph $BQ_GRAPH"
render "$DEMO_DIR/sql/02_property_graph.sql" > "$tmp"
run_sql "$tmp" || die "CREATE PROPERTY GRAPH failed." \
  "BigQuery Graph is pre-GA and may require an Enterprise reservation. See docs/PREVIEW_NOTES.md."
ok "created property graph $BQ_GRAPH"
ok "setup complete"
