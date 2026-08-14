#!/usr/bin/env bash
# Generate synthetic audit logs, load them, and build the graph.
# Idempotent: the generator is seeded and every table uses CREATE OR REPLACE.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=setup
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Setup — generating logs and building the graph"

load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION \
            AUDIT_DAYS AUDIT_PRINCIPALS AUDIT_EVENTS AUDIT_SEED MAX_BYTES_BILLED

GEN_DIR="$DEMO_DIR/data/generated"

info "generating synthetic audit logs (seed $AUDIT_SEED — same seed, same graph)"
python3 "$DEMO_DIR/data/generate.py" \
  --out "$GEN_DIR" --seed "$AUDIT_SEED" \
  --days "$AUDIT_DAYS" --principals "$AUDIT_PRINCIPALS" --events "$AUDIT_EVENTS" \
  || die "Log generation failed." "Check that python3 is 3.9 or later: python3 --version"
ok "generated $(wc -l < "$GEN_DIR/events.ndjson" | tr -d ' ') events"

if bq --project_id="$GCP_PROJECT" show --dataset "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  info "dataset $BQ_DATASET already exists"
else
  bq --project_id="$GCP_PROJECT" mk --dataset \
     --location="$BQ_LOCATION" \
     --description="Kineviz audit-access demo. Synthetic data. Safe to delete." \
     "$GCP_PROJECT:$BQ_DATASET" >/dev/null
  ok "created dataset $BQ_DATASET in $BQ_LOCATION"
fi

# --replace makes the load idempotent; autodetect is fine for our flat schema.
load() {
  bq --project_id="$GCP_PROJECT" load --replace --quiet \
     --source_format=NEWLINE_DELIMITED_JSON --autodetect \
     "$GCP_PROJECT:$BQ_DATASET.$1" "$2" \
    || die "Failed to load $1." "Re-run setup — the load is idempotent."
}
info "loading into BigQuery"
load raw_principals    "$GEN_DIR/principals.ndjson"
load raw_impersonations "$GEN_DIR/impersonations.ndjson"
load raw_events        "$GEN_DIR/events.ndjson"
ok "loaded 3 raw tables"

render() {
  sed -e "s|\${PROJECT}|$GCP_PROJECT|g" \
      -e "s|\${DATASET}|$BQ_DATASET|g" \
      -e "s|\${GRAPH}|$BQ_GRAPH|g" "$1"
}
# bq echoes every statement it runs, which buries the actual progress output.
# Capture it and surface it only when something fails.
run_sql() {
  local out
  if ! out=$(bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --quiet \
       --format=none --maximum_bytes_billed="$MAX_BYTES_BILLED" < "$1" 2>&1); then
    printf '%s\n' "$out" >&2
    return 1
  fi
  return 0
}

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
info "shaping node and edge tables"
render "$DEMO_DIR/sql/01_build_tables.sql" > "$tmp"
run_sql "$tmp" || die "Building node/edge tables failed." "Check the output above, then re-run."
ok "built 4 tables"

info "creating property graph $BQ_GRAPH"
render "$DEMO_DIR/sql/02_property_graph.sql" > "$tmp"
run_sql "$tmp" || die "CREATE PROPERTY GRAPH failed." \
  "BigQuery Graph is pre-GA and may require an Enterprise reservation. See docs/PREVIEW_NOTES.md."
ok "created property graph $BQ_GRAPH"
ok "setup complete"
