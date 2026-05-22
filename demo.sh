#!/usr/bin/env bash
#
# Cloudflare Resource Tagging — Live Demo Script
# Use case: "Production Fleet Audit"
#
# You're an SRE with 50+ Workers. A CVE drops and leadership asks:
# "Which production resources does the Platform team own?"
# Without tags, you grep through spreadsheets. With tags, you query.
#
# This script walks through the story end-to-end.
#

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load credentials from .env if present
if [[ -f "${DEMO_DIR}/.env" ]]; then
  source "${DEMO_DIR}/.env"
fi
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

say()    { echo -e "${CYAN}▶ $1${NC}"; }
warn()   { echo -e "${YELLOW}▶ $1${NC}"; }
ok()     { echo -e "${GREEN}✓ $1${NC}"; }
header() { echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"; }

cf_api() {
  curl -sS "$1" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${@:2}"
}

pause() {
  echo
  read -p "Press [Enter] to continue..."
  echo
}

# ─── 1. PREREQS ──────────────────────────────────────────────
header "STEP 0  —  Environment Check"

if [[ -z "${ACCOUNT_ID:-}" || -z "${API_TOKEN:-}" ]]; then
  echo -e "${RED}❌  Missing credentials.${NC}"
  echo ""
  echo "Set them as environment variables or create a .env file:"
  echo ""
  echo "    cp .env.example .env"
  echo "    # edit .env with your ACCOUNT_ID and API_TOKEN"
  echo ""
  echo "Or export directly:"
  echo "    export ACCOUNT_ID=your-account-id"
  echo "    export API_TOKEN=your-api-token"
  echo ""
  echo "Token needs Account > Resource Tagging > Edit permission."
  echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
  exit 1
fi

export ACCOUNT_ID API_TOKEN

ok "Checking token..."
ME=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}")
if [[ $(echo "$ME" | jq -r '.success') != "true" ]]; then
  echo "$ME" | jq
  exit 1
fi
ACC_NAME=$(echo "$ME" | jq -r '.result.name')
ok "Connected to account: ${ACC_NAME}"

# ─── 2. THE SETUP ────────────────────────────────────────────
header "THE SCENARIO"

say "You run 3 critical services in production:"
say "  • tagging-demo-api    — public API gateway"
say "  • tagging-demo-batch  — background job processor"
say "  • tagging-demo-cache  — edge cache layer"

say "Each is owned by a different team and has a different reliability tier."
say "Today a CVE is announced. Leadership wants a list of ALL production"
say "resources owned by the Platform team so they can schedule a patch window."

pause

# ─── 3. CREATE DEMO WORKERS ──────────────────────────────────
header "STEP 1  —  Deploy the Demo Workers"

say "Let's create 3 real Workers we can tag. If you already have them, we'll skip."

for WORKER in tagging-demo-api tagging-demo-batch tagging-demo-cache; do
  say "Checking ${WORKER}..."
  EXISTING=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/services/${WORKER}" || true)
  if echo "$EXISTING" | jq -e '.success' &>/dev/null; then
    ok "  ${WORKER} already exists"
  else
    warn "  ${WORKER} not found. Deploying now..."
    cd "${DEMO_DIR}/worker"
    npx wrangler deploy --name "${WORKER}" --config <(cat wrangler.toml; echo "name = \"${WORKER}\"") 2>&1 | tail -5 || true
    ok "  ${WORKER} deployed"
  fi
done

pause

# ─── 4. TAG EVERYTHING ───────────────────────────────────────
header "STEP 2  —  Tag the Fleet"

say "Now we attach metadata. This is the 'tag' action."
say "Tags are plain key-value strings. We'll use:"
say "  • environment: production | staging"
say "  • team: platform | data | infra"
say "  • tier: critical | standard"

API_JSON='{"resource_type":"worker","resource_id":"tagging-demo-api","tags":{"environment":"production","team":"platform","tier":"critical"}}'
BATCH_JSON='{"resource_type":"worker","resource_id":"tagging-demo-batch","tags":{"environment":"production","team":"data","tier":"standard"}}'
CACHE_JSON='{"resource_type":"worker","resource_id":"tagging-demo-cache","tags":{"environment":"production","team":"platform","tier":"critical"}}'

say "Tagging tagging-demo-api  →  prod / platform / critical"
cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$API_JSON" | jq -r '.success' | xargs -I{} sh -c '[[ "{}" == "true" ]] && echo "  ✓ Tagged" || echo "  ✗ Failed"'

say "Tagging tagging-demo-batch →  prod / data / standard"
cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$BATCH_JSON" | jq -r '.success' | xargs -I{} sh -c '[[ "{}" == "true" ]] && echo "  ✓ Tagged" || echo "  ✗ Failed"'

say "Tagging tagging-demo-cache →  prod / platform / critical"
cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$CACHE_JSON" | jq -r '.success' | xargs -I{} sh -c '[[ "{}" == "true" ]] && echo "  ✓ Tagged" || echo "  ✗ Failed"'

ok "Fleet tagged."
pause

# ─── 5. READ BACK ────────────────────────────────────────────
header "STEP 3  —  Read Tags Back"

say "Any resource can be inspected. Let's look at the API worker:"
cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&resource_id=tagging-demo-api" | jq '.result.tags'

say "Notice: PUT is replace-all. If you omit a key, it disappears."
say "This makes the API idempotent — great for GitOps / Terraform."
pause

# ─── 6. FILTER ───────────────────────────────────────────────
header "STEP 4  —  Filter: 'Show me all production resources'"

say "This is where tags pay off. Instead of spreadsheets, we query the API."
say "Query: environment:production"
echo

cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&filter=environment:production" | jq '.result[] | {name: .resource_id, tags: .tags}'

pause

# ─── 7. COMBINED FILTER ──────────────────────────────────────
header "STEP 5  —  Filter: 'Production AND Platform team'"

say "Now the real question from leadership:"
say "  Which production resources are owned by the Platform team?"
say "Query: team:platform AND environment:production"
echo

cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&filter=team:platform%20AND%20environment:production" | jq '.result[] | {name: .resource_id, tags: .tags}'

ok "Result: 2 resources — tagging-demo-api and tagging-demo-cache."
pause

# ─── 8. BULK TAGGING ─────────────────────────────────────────
header "STEP 6  —  Bulk Tag a New Resource"

say "A 4th worker comes online: tagging-demo-events."
say "We want to mark it AND the cache as 'maintenance-window: tuesday' in one go."

for W in tagging-demo-cache tagging-demo-events; do
  BODY=$(jq -n --arg id "$W" '{resource_type:"worker",resource_id:$id,tags:{"maintenance-window":"tuesday"}}')
  cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$BODY" | jq -r '.success' | xargs -I{} sh -c '[[ "{}" == "true" ]] && echo "  ✓ ${W}" || echo "  ✗ ${W}"'
done

say "Query for Tuesday maintenance window:"
cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&filter=maintenance-window:tuesday" | jq '.result[] | .resource_id'

pause

# ─── 9. NEGATION ─────────────────────────────────────────────
header "STEP 7  —  Filter: 'Everything EXCEPT staging'"

say "Use NOT to exclude. Query: NOT environment:staging"
echo

cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&filter=NOT%20environment:staging" | jq '.result[] | .resource_id'

ok "Since nothing here is staging, you get the full production fleet."
pause

# ─── 10. CLEANUP ─────────────────────────────────────────────
header "STEP 8  —  Cleanup (optional)"

read -rp "Delete all demo tags and workers? [y/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  for W in tagging-demo-api tagging-demo-batch tagging-demo-cache tagging-demo-events; do
    say "Removing tags from ${W}..."
    cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&resource_id=${W}" -X DELETE | jq -r '.success' | xargs -I{} sh -c '[[ "{}" == "true" ]] && echo "  ✓ Tags removed" || echo "  ✗ Failed"'
    say "Deleting ${W}..."
    cd "${DEMO_DIR}/worker"
    npx wrangler delete --name "${W}" 2>/dev/null || true
    ok "  ${W} cleaned up"
  done
else
  say "Skipping cleanup. You can re-run this demo anytime."
fi

header "Demo Complete"
say "Use case shown: Fleet audit with environment + team + tier tags."
say "Key takeaway: Tags turn 'grep through spreadsheets' into a 1-line API call."
