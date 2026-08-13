#!/usr/bin/env bash
# Create the dataset, materialize a bounded slice of deps.dev, build the graph.
#
# Idempotent: CREATE OR REPLACE throughout, so re-running after a partial
# failure converges instead of duplicating.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=setup
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Setup — building the graph"

load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION DEPS_SYSTEM DEPS_SNAPSHOT DEPS_SEEDS DEPS_MAX_DEPTH DEPS_PROJECT_LOOKUP_LIMIT MAX_BYTES_BILLED

# DEPS_SEEDS is a bare comma-separated list in .env; SQL needs it quoted.
SEEDS_SQL=$(printf '%s' "$DEPS_SEEDS" | awk -F, '{for(i=1;i<=NF;i++){gsub(/^ +| +$/,"",$i); printf "%s'"'"'%s'"'"'", (i>1?",":""), $i}}')

# Substitute placeholders in a .sql file. Deliberately explicit rather than
# envsubst, so it is obvious which values reach the query.
render() {
  sed -e "s|\${PROJECT}|$GCP_PROJECT|g" \
      -e "s|\${DATASET}|$BQ_DATASET|g" \
      -e "s|\${GRAPH}|$BQ_GRAPH|g" \
      -e "s|\${SYSTEM}|$DEPS_SYSTEM|g" \
      -e "s|\${SNAPSHOT}|$DEPS_SNAPSHOT|g" \
      -e "s|\${SEEDS}|$SEEDS_SQL|g" \
      -e "s|\${MAX_DEPTH}|$DEPS_MAX_DEPTH|g" \
      -e "s|\${PROJECT_LOOKUP_LIMIT}|$DEPS_PROJECT_LOOKUP_LIMIT|g" \
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

info "materializing $DEPS_SYSTEM deps for: $DEPS_SEEDS (snapshot $DEPS_SNAPSHOT)"
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
render "$DEMO_DIR/sql/01_materialize.sql" > "$tmp"
run_sql "$tmp" || die "Materialization failed." \
  "If it mentions maximum_bytes_billed, shorten DEPS_SEEDS or lower DEPS_MAX_DEPTH rather than raising the cap."
ok "materialized packages and dependency edges"

# Read the focus names back out and bake them in as LITERALS. BigQuery only
# prunes a clustered column against literal values, so this round trip is what
# keeps the project lookup at ~1 GB instead of ~6.6 GB.
info "selecting the top $DEPS_PROJECT_LOOKUP_LIMIT packages for repo lookup"
FOCUS_SQL=$(bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --format=csv --quiet \
  --maximum_bytes_billed="$MAX_BYTES_BILLED" \
  "SELECT id FROM \`$GCP_PROJECT.$BQ_DATASET.nodes_package\`
   ORDER BY is_seed DESC, dependents_in_graph DESC
   LIMIT $DEPS_PROJECT_LOOKUP_LIMIT" 2>/dev/null \
  | tail -n +2 | awk 'NF{gsub(/\r/,""); printf "%s'"'"'%s'"'"'", (NR>1?",":""), $0}')

[ -n "$FOCUS_SQL" ] || die "Could not read package names back from BigQuery." \
  "Re-run setup — it is idempotent."

info "looking up backing repos"
sed -e "s|\${PROJECT}|$GCP_PROJECT|g" -e "s|\${DATASET}|$BQ_DATASET|g" \
    -e "s|\${SYSTEM}|$DEPS_SYSTEM|g" -e "s|\${SNAPSHOT}|$DEPS_SNAPSHOT|g" \
    -e "s|\${FOCUS}|$FOCUS_SQL|g" "$DEMO_DIR/sql/02_projects.sql" > "$tmp"
run_sql "$tmp" || die "Project lookup failed." \
  "If it mentions maximum_bytes_billed, lower DEPS_PROJECT_LOOKUP_LIMIT rather than raising the cap."
ok "materialized project nodes and edges"

info "creating property graph $BQ_GRAPH"
render "$DEMO_DIR/sql/03_property_graph.sql" > "$tmp"
run_sql "$tmp" || die "CREATE PROPERTY GRAPH failed." \
  "BigQuery Graph is pre-GA and may require an Enterprise reservation. See docs/PREVIEW_NOTES.md."
ok "created property graph $BQ_GRAPH"

ok "setup complete"
