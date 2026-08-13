#!/usr/bin/env bash
#
# Prove a BigQuery property graph is reachable and queryable — before involving
# Kineviz at all. If this passes and Kineviz still cannot see your graph, the
# problem is the connection settings, not BigQuery.
#
#   ./verify.sh --project my-project --dataset my_dataset --graph MyGraph
#
# Creates nothing. Reads only. Bounded by --max-bytes.

set -euo pipefail

PROJECT=""; DATASET=""; GRAPH=""; MAX_BYTES=1000000000; JSON=0

usage() {
  cat <<'EOF'
Usage: ./verify.sh --project <id> --dataset <name> --graph <name> [options]

  --project      Google Cloud project that owns the dataset
  --dataset      BigQuery dataset holding the property graph
  --graph        Property graph name (from CREATE PROPERTY GRAPH)
  --max-bytes    Query ceiling in bytes (default 1000000000 = 1 GB)
  --json         Machine-readable output
EOF
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)   PROJECT="${2:-}"; shift 2 ;;
    --dataset)   DATASET="${2:-}"; shift 2 ;;
    --graph)     GRAPH="${2:-}"; shift 2 ;;
    --max-bytes) MAX_BYTES="${2:-}"; shift 2 ;;
    --json)      JSON=1; shift ;;
    -h|--help)   usage 0 ;;
    *)           echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

_c_reset=$'\033[0m'; _c_red=$'\033[31m'; _c_green=$'\033[32m'; _c_dim=$'\033[2m'
[ -t 1 ] || { _c_reset=""; _c_red=""; _c_green=""; _c_dim=""; }

die() {
  if [ "$JSON" = 1 ]; then
    printf '{"ok":false,"error":"%s","remediation":"%s"}\n' "$1" "$2" >&2
  else
    printf '\n  %s✗%s %s\n    REMEDIATION: %s\n\n' "$_c_red" "$_c_reset" "$1" "$2" >&2
  fi
  exit 1
}
ok()   { [ "$JSON" = 1 ] || printf '  %s✓%s %s\n' "$_c_green" "$_c_reset" "$1"; }
note() { [ "$JSON" = 1 ] || printf '    %s%s%s\n' "$_c_dim" "$1" "$_c_reset"; }

[ -n "$PROJECT" ] && [ -n "$DATASET" ] && [ -n "$GRAPH" ] || \
  die "Missing required arguments." "Run ./verify.sh --help"

command -v bq >/dev/null 2>&1 || \
  die "'bq' not found on PATH." "Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"

[ "$JSON" = 1 ] || printf '\nChecking %s.%s → graph %s\n\n' "$PROJECT" "$DATASET" "$GRAPH"

# 1 — dataset exists, and capture its location. A region mismatch between the
# dataset and what you enter in Kineviz is the most common "graph not found".
location=$(bq --project_id="$PROJECT" show --format=prettyjson "$PROJECT:$DATASET" 2>/dev/null \
           | sed -n 's/.*"location": "\([^"]*\)".*/\1/p' | head -1) || true
[ -n "$location" ] || die "Dataset '$DATASET' not found in project '$PROJECT', or you cannot read it." \
  "Check the name, and that your account has roles/bigquery.dataViewer on the project that OWNS the dataset."
ok "dataset found (location: $location)"
note "if step 6 lists no graphs, set this as 'Select location' in Kineviz"

# 2 — the property graph is registered
if ! bq --project_id="$PROJECT" query --use_legacy_sql=false --format=csv --quiet \
        --maximum_bytes_billed="$MAX_BYTES" \
        "SELECT property_graph_name FROM \`$PROJECT.$DATASET.INFORMATION_SCHEMA.PROPERTY_GRAPHS\`" \
        2>/dev/null | tail -n +2 | grep -qx "$GRAPH"; then
  die "No property graph named '$GRAPH' in $PROJECT.$DATASET." \
      "List what exists: bq query --use_legacy_sql=false \"SELECT property_graph_name FROM \\\`$PROJECT.$DATASET.INFORMATION_SCHEMA.PROPERTY_GRAPHS\\\`\""
fi
ok "property graph '$GRAPH' is registered"

# 3 — it actually answers a GQL query. This is the check that matters: steps 1
# and 2 only prove the graph is *registered*, not that it can be read.
#
# Two things learned the hard way here. bq writes query errors to stdout rather
# than stderr, so both streams have to be captured or the diagnostic is lost and
# every failure reports "unknown error". And the smoke query has to be valid GQL
# — an earlier version used an empty backtick identifier, which BigQuery rejects
# with "Invalid empty identifier", making this step fail against a perfectly
# healthy graph.
out=$(bq --project_id="$PROJECT" query --use_legacy_sql=false --format=csv --quiet \
        --maximum_bytes_billed="$MAX_BYTES" \
        "GRAPH \`$PROJECT.$DATASET.$GRAPH\` MATCH (n) RETURN COUNT(n) AS node_count" 2>&1) || {
  err=$(printf '%s' "$out" | tr '\n' ' ')
  case "$err" in
    *eservation*|*dition*|*n-demand*)
      die "GQL query rejected on edition or reservation grounds." \
          "Some projects need an Enterprise or Enterprise Plus reservation for GQL while BigQuery Graph is pre-GA. See https://docs.cloud.google.com/bigquery/docs/graph-overview" ;;
    *"Invalid empty identifier"*|*"Syntax error"*)
      die "The verification query itself is invalid: ${err}" \
          "This is a bug in verify.sh, not in your graph. Please open an issue." ;;
    *)
      die "GQL query failed: ${err:-no error text returned}" \
          "Confirm the graph's node tables are readable, then re-run." ;;
  esac
}

nodes=$(printf '%s\n' "$out" | tail -n +2 | head -1 | tr -d ' \r')
ok "GQL query succeeded (graph has ${nodes:-?} nodes)"

if [ "$JSON" = 1 ]; then
  printf '{"ok":true,"project":"%s","dataset":"%s","graph":"%s","location":"%s","nodes":%s}\n' \
    "$PROJECT" "$DATASET" "$GRAPH" "$location" "${nodes:-0}"
else
  cat <<EOF

  ${_c_green}Ready to connect.${_c_reset} In Kineviz Desktop → Create Project:

    Database Type            : BigQuery Property Graph
    Upload Service Account   : your service account JSON
    Select Database          : $DATASET
    Select location (Optional): $location
    Select Graph Database    : $GRAPH

  Walkthrough with screenshots: connect/README.md § 3 · Connect

EOF
fi
