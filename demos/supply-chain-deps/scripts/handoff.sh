#!/usr/bin/env bash
# Everything above this point was automatable. Everything below is the person's.
# An agent relays this block verbatim and stops. See AGENTS.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
GXR_STEP=handoff
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env "$DEMO_DIR"
rows=$(cat "$DEMO_DIR/.verified_rows" 2>/dev/null || echo "?")
desktop="not detected"; kineviz_desktop_installed && desktop="detected"

cat <<EOF

✅ Demo ready: supply-chain-deps
   Kineviz (formerly GraphXR)

   Dataset:   ${GCP_PROJECT}.${BQ_DATASET}   (${DEPS_SYSTEM}, top ${TOP_N_PACKAGES} packages)
   Graph:     ${BQ_GRAPH} — 2 node labels (Package, Project), 2 edge labels
   Verified:  GQL query returned ${rows} row(s)
   Desktop:   ${desktop}

   Last step — connect Kineviz (about 60 seconds):
     Open Kineviz Desktop → Create Project
       → Database Type: BigQuery
       → Upload key:    your service account JSON
       → Database:      ${BQ_DATASET}
       → Region:        ${BQ_LOCATION}
       → Graph:         ${BQ_GRAPH}
     Walkthrough + screenshots: ../../connect/README.md
     Need a key?                ../../connect/service-account.md

     Prefer to keep everything inside your own GCP project? Deploy GraphXR
     Explorer for BigQuery from Marketplace — see ../../connect/README.md.

   Then try:
     1. Which packages does everything depend on?      queries/01-fan-in.gql
     2. Which of those sit on an under-resourced repo? queries/02-bus-factor.gql
     3. What is one package's blast radius?            queries/03-transitive-blast-radius.gql
     4. Which packages secretly share a repo?          queries/04-shared-project.gql

     Run 3 in Kineviz rather than the CLI — the shape is the finding.

   Cost so far: ~\$0.05.  Tear down with:  ./gxr down supply-chain-deps

EOF
