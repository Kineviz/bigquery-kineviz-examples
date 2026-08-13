#!/usr/bin/env bash
# Run the fortune500 pipeline against a small ticker list, then point Kineviz at
# the graph it produces.
#
# This demo ORCHESTRATES rather than forks. Kineviz/fortune500 already does the
# scraping, parsing, and Gemini extraction; duplicating that code here would mean
# two copies to keep in step. What this repo adds is the part fortune500 lacks:
# preflight checks, a cost bound, verification, and a teardown that actually
# deletes what was created.
#
# The upstream commit is pinned in demo.yaml so the demo cannot drift.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=setup
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Setup — running the SEC pipeline"

load_env "$DEMO_DIR"
require_env GCP_PROJECT GCS_BUCKET BQ_DATASET BQ_GRAPH BQ_LOCATION SEC_TICKERS GEMINI_MODEL

UPSTREAM_REPO=$(sed -n 's/^  repo: *//p' "$DEMO_DIR/demo.yaml" | tr -d '"')
UPSTREAM_PIN=$(sed -n 's/^  commit: *//p' "$DEMO_DIR/demo.yaml" | tr -d '"')
WORK="$DEMO_DIR/.upstream"

[ -n "$UPSTREAM_PIN" ] || die "No upstream commit pinned in demo.yaml." \
  "This demo must pin the fortune500 commit it was verified against."

if [ -d "$WORK/.git" ]; then
  info "upstream already cloned"
else
  info "cloning $UPSTREAM_REPO at ${UPSTREAM_PIN:0:8}"
  git clone -q "$UPSTREAM_REPO" "$WORK" \
    || die "Could not clone $UPSTREAM_REPO." "Check network access and that the repo is reachable."
fi

git -C "$WORK" fetch -q origin
git -C "$WORK" checkout -q "$UPSTREAM_PIN" \
  || die "Pinned commit ${UPSTREAM_PIN:0:8} not found upstream." \
         "It may have been force-pushed away. Open an issue — the pin needs updating and re-verifying."
ok "upstream pinned at ${UPSTREAM_PIN:0:8}"

if [ -f "$WORK/requirements.txt" ]; then
  info "installing upstream Python dependencies into a local venv"
  python3 -m venv "$WORK/.venv" >/dev/null 2>&1 || true
  # shellcheck disable=SC1091
  . "$WORK/.venv/bin/activate"
  pip install -q -r "$WORK/requirements.txt" \
    || die "Could not install upstream dependencies." "See $WORK/requirements.txt"
  ok "dependencies installed"
fi

[ -x "$WORK/00_run_full_pipeline.sh" ] || chmod +x "$WORK/00_run_full_pipeline.sh" 2>/dev/null || true
[ -f "$WORK/00_run_full_pipeline.sh" ] || die "Upstream pipeline script not found." \
  "Expected 00_run_full_pipeline.sh at the pinned commit. The pin may need updating."

warn "This step calls Gemini and will bill your project (~\$1 per company)."
info "processing: $SEC_TICKERS"

(
  cd "$WORK"
  GCP_PROJECT="$GCP_PROJECT" \
  BQ_DATASET="$BQ_DATASET" \
  GCS_BUCKET="$GCS_BUCKET" \
  GEMINI_MODEL="$GEMINI_MODEL" \
  ./00_run_full_pipeline.sh "$SEC_TICKERS"
) || die "The upstream pipeline failed." \
        "Its output is above. The pipeline is documented at $UPSTREAM_REPO — re-run this step once fixed, it is safe to repeat."

ok "pipeline complete"

# The upstream pipeline creates the property graph itself, so confirm rather than
# recreate it — building it twice would diverge from what fortune500 defines.
if bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --format=csv --quiet \
     --maximum_bytes_billed="$MAX_BYTES_BILLED" \
     "SELECT property_graph_name FROM \`$GCP_PROJECT.$BQ_DATASET.INFORMATION_SCHEMA.PROPERTY_GRAPHS\`" \
     2>/dev/null | tail -n +2 | grep -qx "$BQ_GRAPH"; then
  ok "property graph $BQ_GRAPH exists"
else
  die "The pipeline ran but no property graph named '$BQ_GRAPH' exists in $BQ_DATASET." \
      "Check BQ_GRAPH in .env matches what the upstream DDL creates (default SecGraph)."
fi
ok "setup complete"
