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

# ─── 2. Gather credentials ───────────────────────────────────
if [[ -f .env ]]; then
  source .env
fi

if [[ -z "${ACCOUNT_ID:-}" || -z "${API_TOKEN:-}" ]]; then
  echo ""
  echo "📝  Credentials needed."
  echo ""
  echo "You'll need an Account Owned Token with:"
  echo "  Account > Resource Tagging > Edit"
  echo ""
  echo "⚠️  This is NOT the same as Cloudflare Access tags."
  echo "     Look for 'Resource Tagging' specifically."
  echo ""
  echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
  echo ""

  read -rp "Account ID: " ACCOUNT_ID
  read -rsp "API Token:  " API_TOKEN
  echo ""
fi

# ─── 3. Validate token BEFORE writing anything ───────────────
echo ""
echo "🔑  Validating API token ..."

# The tagging API requires resource_type + resource_id on GET.
# We use a dummy worker name; "not found" is fine — it proves auth works.
TAGS_RESPONSE=$(curl -sS -X GET \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags?resource_type=worker&resource_id=demo-validation-test" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" || true)

# A valid token returns success:true (even if the dummy worker doesn't exist).
# An invalid token returns success:false with auth errors.
if [[ $(echo "$TAGS_RESPONSE" | jq -r '.success // false') != "true" ]]; then
  ERR_MSG=$(echo "$TAGS_RESPONSE" | jq -r '.errors[0].message // "unknown error"')
  echo "❌  Token validation failed: $ERR_MSG"
  echo ""
  echo "Your token needs: Account > Resource Tagging > Edit"
  echo ""
  echo "⚠️  Common mistake: using a token with 'Cloudflare Access > Tags:Edit'"
  echo "     That is a different product. You need 'Resource Tagging' specifically."
  echo ""
  echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
  exit 1
fi

echo "✅  Token valid — Resource Tagging API is available"

# ─── 4. Write .env only after validation ─────────────────────
if [[ ! -f .env ]]; then
  cat > .env <<EOF
# Cloudflare Resource Tagging Demo — Environment Variables
# .env is gitignored and will never be committed.

ACCOUNT_ID=${ACCOUNT_ID}
API_TOKEN=${API_TOKEN}
EOF
  echo "✅  .env created"
fi

# ─── 5. Done ─────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "🚀  Setup complete! Next step:"
echo ""
echo "    ./demo.sh"
echo ""
echo "─────────────────────────────────────────────────────────────"
