#!/usr/bin/env bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Cloudflare Resource Tagging — Demo Setup             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ─── 1. Check dependencies ───────────────────────────────────
for cmd in curl jq; do
  if ! command -v $cmd &>/dev/null; then
    echo "❌  Required tool '$cmd' not found. Please install it."
    exit 1
  fi
done
echo "✅  curl and jq found"

# ─── 2. Bootstrap .env if missing ────────────────────────────
if [[ ! -f .env ]]; then
  echo ""
  echo "📝  No .env file found. Let's create one."
  echo ""
  echo "You'll need an Account Owned Token with Account > Resource Tagging > Edit."
  echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
  echo ""

  read -rp "Account ID: " ACCOUNT_ID
  read -rsp "API Token:  " API_TOKEN
  echo ""

  cat > .env <<EOF
# Cloudflare Resource Tagging Demo — Environment Variables
# .env is gitignored and will never be committed.

ACCOUNT_ID=${ACCOUNT_ID}
API_TOKEN=${API_TOKEN}
EOF

  echo ""
  echo "✅  .env created"
fi

# ─── 3. Load credentials ─────────────────────────────────────
source .env

if [[ -z "${ACCOUNT_ID:-}" || -z "${API_TOKEN:-}" ]]; then
  echo "❌  .env is missing ACCOUNT_ID or API_TOKEN."
  echo "    Please edit .env and re-run ./setup.sh"
  exit 1
fi

# ─── 4. Validate token ───────────────────────────────────────
echo ""
echo "🔑  Validating API token ..."
RESPONSE=$(curl -sS -X GET \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json")

if [[ $(echo "$RESPONSE" | jq -r '.success') != "true" ]]; then
  echo "❌  Token validation failed:"
  echo "$RESPONSE" | jq -r '.errors'
  exit 1
fi

ACCOUNT_NAME=$(echo "$RESPONSE" | jq -r '.result.name')
echo "✅  Token valid — connected to account: $ACCOUNT_NAME"

# ─── 5. Check Tagging API ────────────────────────────────────
echo ""
echo "🔎  Checking Resource Tagging API availability ..."
TAGS_RESPONSE=$(curl -sS -X GET \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags?limit=1" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" || true)

if [[ $(echo "$TAGS_RESPONSE" | jq -r '.success // false') == "true" ]]; then
  echo "✅  Resource Tagging API is available"
else
  echo "⚠️   Resource Tagging API returned an error (expected if no tags exist yet):"
  echo "$TAGS_RESPONSE" | jq -r '.errors // .messages // .' 2>/dev/null || echo "$TAGS_RESPONSE"
fi

# ─── 6. Done ─────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "🚀  Setup complete! Next step:"
echo ""
echo "    ./demo.sh"
echo ""
echo "─────────────────────────────────────────────────────────────"
