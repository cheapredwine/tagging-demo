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

DEMO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ─── Parse args ──────────────────────────────────────────────
CLEANUP_ONLY=false
SKIP_DEPLOY=false
for arg in "$@"; do
  case "$arg" in
    --cleanup) CLEANUP_ONLY=true ;;
    --skip-deploy) SKIP_DEPLOY=true ;;
    -h|--help)
      echo "Usage: $0 [--cleanup] [--skip-deploy]"
      echo ""
      echo "  --cleanup      Remove all demo tags and workers (skips demo)"
      echo "  --skip-deploy  Skip Worker deployment if they already exist"
      echo "  --help         Show this help"
      exit 0
      ;;
  esac
done

# Load credentials from .env if present
if [[ -f "${DEMO_DIR}/.env" ]]; then
  source "${DEMO_DIR}/.env"
fi

# Optional: ZONE_ID for zone-level tagging demo
ZONE_ID="${ZONE_ID:-}"
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

BRIGHT='\033[1;37m'

show_request() {
  local method="${1:-GET}"
  local url="$2"
  local body="${3:-}"
  local redacted_account="${ACCOUNT_ID:0:4}****${ACCOUNT_ID: -4}"
  local display_url="${url/\{account_id\}/$redacted_account}"
  echo ""
  echo -e "${BRIGHT}  ┌─ HTTP Request ──────────────────────────────────────────┐${NC}"
  echo -e "${BRIGHT}  │ $method $display_url${NC}"
  echo -e "${BRIGHT}  │ Authorization: Bearer ${API_TOKEN:0:4}****${API_TOKEN: -4}${NC}"
  if [[ -n "$body" ]]; then
    echo -e "${BRIGHT}  │ Content-Type: application/json${NC}"
    echo "$body" | jq -c '.' | while IFS= read -r line; do
      echo -e "${BRIGHT}  │ $line${NC}"
    done
  fi
  echo -e "${BRIGHT}  └────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

show_wrangler() {
  local cmd="$1"
  echo ""
  echo -e "${BRIGHT}  ┌─ Wrangler Command ──────────────────────────────────────┐${NC}"
  echo -e "${BRIGHT}  │ $cmd${NC}"
  echo -e "${BRIGHT}  │ CLOUDFLARE_ACCOUNT_ID=${ACCOUNT_ID:0:4}****${ACCOUNT_ID: -4}${NC}"
  echo -e "${BRIGHT}  └────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

run_cleanup() {
  header "Cleanup"
  for W in tagging-demo-api tagging-demo-batch tagging-demo-cache; do
    say "Removing tags from ${W}..."
    DEL_BODY=$(jq -n --arg rt "worker" --arg rid "$W" '{resource_type:$rt, resource_id:$rid}')
    show_request "DELETE" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags" "$DEL_BODY"
    DEL_FULL=$(curl -sS -X DELETE \
      "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$DEL_BODY" \
      -w "\nHTTP_STATUS:%{http_code}" 2>&1)
    HTTP_CODE=$(echo "$DEL_FULL" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
    DEL_RESP=$(echo "$DEL_FULL" | sed '/HTTP_STATUS:/d')
    echo "  Response: (HTTP $HTTP_CODE)"
    if [[ -n "$DEL_RESP" ]]; then
      echo "$DEL_RESP" | jq '.' || echo "$DEL_RESP"
    else
      echo "  (empty body — 204 No Content)"
    fi
    if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
      ok "  Tags removed"
    else
      warn "  Delete failed (HTTP $HTTP_CODE)"
    fi
    say "Deleting ${W}..."
    cd "${DEMO_DIR}/worker"
    npx wrangler delete "${W}" --force 2>&1 || true
    ok "  ${W} cleaned up"
  done

  if [[ -n "${ZONE_ID:-}" ]]; then
    say "Removing tags from zone..."
    DEL_BODY=$(jq -n --arg rt "zone" --arg rid "$ZONE_ID" '{resource_type:$rt, resource_id:$rid}')
    show_request "DELETE" "https://api.cloudflare.com/client/v4/zones/{zone_id}/tags" "$DEL_BODY"
    DEL_FULL=$(curl -sS -X DELETE \
      "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/tags" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$DEL_BODY" \
      -w "\nHTTP_STATUS:%{http_code}" 2>&1)
    HTTP_CODE=$(echo "$DEL_FULL" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
    DEL_RESP=$(echo "$DEL_FULL" | sed '/HTTP_STATUS:/d')
    echo "  Response: (HTTP $HTTP_CODE)"
    if [[ -n "$DEL_RESP" ]]; then
      echo "$DEL_RESP" | jq '.' || echo "$DEL_RESP"
    else
      echo "  (empty body — 204 No Content)"
    fi
    if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
      ok "  Zone tags removed"
    else
      warn "  Zone tag delete failed (HTTP $HTTP_CODE)"
    fi
  fi
}

cf_api() {
  curl -sS "$1" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${@:2}"
}

worker_exists() {
  local name="$1"
  local resp
  resp=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${name}")
  [[ $(echo "$resp" | jq -r '.success') == "true" ]]
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
ME=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&resource_id=demo-validation-test")
if [[ $(echo "$ME" | jq -r '.success') != "true" ]]; then
  echo "$ME" | jq -r '.errors[0].message // "Token invalid"'
  echo ""
  echo "Make sure your token has: Account > Resource Tagging > Edit"
  exit 1
fi
ok "Token valid"

if [[ "$CLEANUP_ONLY" == "true" ]]; then
  run_cleanup
  exit 0
fi

# ─── 2. THE SETUP ────────────────────────────────────────────
header "THE SCENARIO"

say "You run 3 critical services in production:"
say "  • tagging-demo-api    — public API gateway"
say "  • tagging-demo-batch  — background job processor"
say "  • tagging-demo-cache  — edge cache layer"

if [[ -n "$ZONE_ID" ]]; then
  say "You also manage a DNS zone on Cloudflare."
fi

say "Each is owned by a different team and has a different reliability tier."
say "Today a CVE is announced. Leadership wants a list of ALL production"
say "resources owned by the Platform team so they can schedule a patch window."

pause

# ─── 3. CREATE DEMO WORKERS ──────────────────────────────────
header "STEP 1  —  Deploy the Demo Workers"

say "Wrangler bundles your code, uploads it to Cloudflare, and publishes"
say "the Worker to the edge network. Here's what that looks like:"

# Check wrangler auth before trying to deploy
if ! npx wrangler whoami &>/dev/null; then
  echo ""
  echo -e "${RED}❌  Wrangler is not authenticated.${NC}"
  echo "    Run: npx wrangler login"
  echo "    Or set CLOUDFLARE_API_TOKEN with Workers:Edit permission."
  exit 1
fi

for WORKER in tagging-demo-api tagging-demo-batch tagging-demo-cache; do
  echo ""

  if [[ "$SKIP_DEPLOY" == "true" ]] && worker_exists "$WORKER"; then
    ok "  ${WORKER} already exists — skipping deploy"
    continue
  fi

  echo -e "${BLUE}  ▓▓▓ Deploying ${WORKER} ▓▓▓${NC}"
  cd "${DEMO_DIR}/worker"

  show_wrangler "npx wrangler deploy --name ${WORKER}"

  DEPLOY_LOG=$(mktemp)
  if CLOUDFLARE_ACCOUNT_ID="${ACCOUNT_ID}" npx wrangler deploy --name "${WORKER}" > "$DEPLOY_LOG" 2>&1; then
    # Show key wrangler output (URL, routes, etc.)
    grep -E '(Published|URL|Route|Worker)' "$DEPLOY_LOG" | sed 's/^/  /' || true
    ok "  ${WORKER} deployed ✓"
  else
    warn "  ${WORKER} deploy failed:"
    cat "$DEPLOY_LOG"
  fi
  rm -f "$DEPLOY_LOG"
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
show_request "PUT" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags" "$API_JSON"
API_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$API_JSON")
echo "$API_RESP" | jq '.'
if [[ $(echo "$API_RESP" | jq -r '.success') == "true" ]]; then
  ok "  Tagged"
else
  warn "  Failed: $(echo "$API_RESP" | jq -r '.errors[0].message // "unknown error"')"
fi

say "Tagging tagging-demo-batch →  prod / data / standard"
show_request "PUT" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags" "$BATCH_JSON"
BATCH_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$BATCH_JSON")
echo "$BATCH_RESP" | jq '.'
if [[ $(echo "$BATCH_RESP" | jq -r '.success') == "true" ]]; then
  ok "  Tagged"
else
  warn "  Failed: $(echo "$BATCH_RESP" | jq -r '.errors[0].message // "unknown error"')"
fi

say "Tagging tagging-demo-cache →  prod / platform / critical"
show_request "PUT" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags" "$CACHE_JSON"
CACHE_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$CACHE_JSON")
echo "$CACHE_RESP" | jq '.'
if [[ $(echo "$CACHE_RESP" | jq -r '.success') == "true" ]]; then
  ok "  Tagged"
else
  warn "  Failed: $(echo "$CACHE_RESP" | jq -r '.errors[0].message // "unknown error"')"
fi

say ""
say "Notice: PUT is replace-all. If you omit a key, it disappears."
say "This makes the API idempotent — great for GitOps / Terraform."
ok "Fleet tagged."
pause

# ─── 4b. TAG A ZONE (optional) ──────────────────────────────
if [[ -n "$ZONE_ID" ]]; then
  header "STEP 2b  —  Tag a Zone"

  say "Zones are zone-level resources. They use a different endpoint:"
  say "  /zones/{zone_id}/tags  instead of  /accounts/{account_id}/tags"

  # Fetch zone name for display
  ZONE_NAME=$(cf_api "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}" | jq -r '.result.name // "unknown-zone"')

  ZONE_JSON="{\"resource_type\":\"zone\",\"resource_id\":\"${ZONE_ID}\",\"tags\":{\"environment\":\"production\",\"team\":\"platform\",\"tier\":\"critical\"}}"

  say "Tagging zone ${ZONE_NAME} (id: ${ZONE_ID}) →  prod / platform / critical"
  show_request "PUT" "https://api.cloudflare.com/client/v4/zones/{zone_id}/tags" "$ZONE_JSON"
  ZONE_RESP=$(cf_api "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/tags" -X PUT -d "$ZONE_JSON")
  echo "$ZONE_RESP" | jq '.'
  if [[ $(echo "$ZONE_RESP" | jq -r '.success') == "true" ]]; then
    ok "  Zone tagged"
  else
    warn "  Failed: $(echo "$ZONE_RESP" | jq -r '.errors[0].message // "unknown error"')"
  fi

  pause
fi

# ─── 5. READ BACK ────────────────────────────────────────────
header "STEP 3  —  Read Tags Back"

say "Any resource can be inspected. Let's look at the API worker:"
show_request "GET" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags?resource_type=worker&resource_id=tagging-demo-api"
echo "  Response:"
cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&resource_id=tagging-demo-api" | jq '.'
pause

# ─── 6. FILTER ───────────────────────────────────────────────
header "STEP 4  —  Filter: 'Show me all production resources'"

say "This is where tags pay off. Instead of spreadsheets, we query the API."
say "Query: environment=production"
show_request "GET" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags/resources?tag=environment=production"
FILTER_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags/resources?tag=environment=production")
echo "  Response:"
echo "$FILTER_RESP" | jq '.'

pause

# ─── 7. COMBINED FILTER ──────────────────────────────────────
header "STEP 5  —  Filter: 'Production AND Platform team'"

say "Now the real question from leadership:"
say "  Which production resources are owned by the Platform team?"
say "Query: team=platform AND environment=production"
show_request "GET" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags/resources?tag=team=platform&tag=environment=production"
FILTER_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags/resources?tag=team=platform&tag=environment=production")
echo "  Response:"
echo "$FILTER_RESP" | jq '.'

PLATFORM_COUNT=$(echo "$FILTER_RESP" | jq '.result // [] | length')
ok "Result: $PLATFORM_COUNT resource(s) — platform team, production."
pause

# ─── 8. NEGATION + GET-MERGE-PUT ─────────────────────────────
header "STEP 6  —  Filter: 'Everything EXCEPT staging'"

say "Let's say tagging-demo-batch gets demoted to staging."
say "We need to change its environment tag without wiping the others."
say "This is the GET-merge-PUT pattern:"

# 1. GET existing tags
show_request "GET" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags?resource_type=worker&resource_id=tagging-demo-batch"
GET_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags?resource_type=worker&resource_id=tagging-demo-batch")
echo "  Response:"
echo "$GET_RESP" | jq '.result.tags'
EXISTING_TAGS=$(echo "$GET_RESP" | jq '.result.tags // {}')

# 2. Merge new tag value
MERGED=$(echo "$EXISTING_TAGS" | jq '. + {"environment":"staging"}')

# 3. PUT merged tags
BODY=$(jq -n --argjson tags "$MERGED" '{resource_type:"worker",resource_id:"tagging-demo-batch",tags:$tags}')
show_request "PUT" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags" "$BODY"
STAGING_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags" -X PUT -d "$BODY")
echo "$STAGING_RESP" | jq '.'
if [[ $(echo "$STAGING_RESP" | jq -r '.success') == "true" ]]; then
  ok "  tagging-demo-batch moved to staging"
else
  warn "  Failed: $(echo "$STAGING_RESP" | jq -r '.errors[0].message // "unknown error"')"
fi

say ""
say "Query: NOT environment=staging"
show_request "GET" "https://api.cloudflare.com/client/v4/accounts/{account_id}/tags/resources?tag=environment!=staging"
NEG_RESP=$(cf_api "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/tags/resources?tag=environment!=staging")
echo "  Response:"
echo "$NEG_RESP" | jq '.'

NOT_STAGING_COUNT=$(echo "$NEG_RESP" | jq '.result // [] | length')
ok "Result: $NOT_STAGING_COUNT resource(s) — staging worker excluded."
pause

header "Demo Complete"
say "Use case shown: Fleet audit with environment + team + tier tags."
say "Key takeaway: Tags turn 'grep through spreadsheets' into a 1-line API call."
echo ""
say "To clean up demo resources: ./demo.sh --cleanup"
