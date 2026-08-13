#!/usr/bin/env bash
# Create the dataset, materialize a bounded slice of deps.dev, build the graph.
#
# Idempotent: CREATE OR REPLACE throughout, so re-running after a partial
# failure converges instead of duplicating.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
GXR_STEP=setup
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Setup — building the graph"

load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION DEPS_SYSTEM TOP_N_PACKAGES MAX_BYTES_BILLED

# Substitute placeholders in a .sql file. Deliberately explicit rather than
# envsubst, so it is obvious which values reach the query.
render() {
  sed -e "s|\${PROJECT}|$GCP_PROJECT|g" \
      -e "s|\${DATASET}|$BQ_DATASET|g" \
      -e "s|\${GRAPH}|$BQ_GRAPH|g" \
      -e "s|\${SYSTEM}|$DEPS_SYSTEM|g" \
      -e "s|\${TOP_N}|$TOP_N_PACKAGES|g" \
      "$1"
}

# Every query is capped. Never raise MAX_BYTES_BILLED to make one pass.
run_sql() {
  bq --project_id="$GCP_PROJECT" query \
     --use_legacy_sql=false --quiet --format=none \
     --maximum_bytes_billed="$MAX_BYTES_BILLED" \
     < "$1"
}

if bq --project_id="$GCP_PROJECT" show --dataset "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  info "dataset $BQ_DATASET already exists"
else
  bq --project_id="$GCP_PROJECT" mk --dataset \
     --location="$BQ_LOCATION" \
     --description="Kineviz supply-chain demo. Safe to delete." \
     "$GCP_PROJECT:$BQ_DATASET" >/dev/null
  ok "created dataset $BQ_DATASET in $BQ_LOCATION"
fi

info "materializing top $TOP_N_PACKAGES $DEPS_SYSTEM packages from deps.dev (~1 min)"
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
render "$DEMO_DIR/sql/01_materialize.sql" > "$tmp"
run_sql "$tmp" || die "Materialization failed." \
  "Check the output above. If it mentions maximum_bytes_billed, lower TOP_N_PACKAGES in .env rather than raising the cap."
ok "materialized 4 tables"

info "creating property graph $BQ_GRAPH"
render "$DEMO_DIR/sql/02_property_graph.sql" > "$tmp"
run_sql "$tmp" || die "CREATE PROPERTY GRAPH failed." \
  "BigQuery Graph is pre-GA and may require an Enterprise reservation. See docs/PREVIEW_NOTES.md."
ok "created property graph $BQ_GRAPH"

ok "setup complete"
