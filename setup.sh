#!/usr/bin/env bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Cloudflare Resource Tagging — Demo Setup             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [[ -z "${ACCOUNT_ID:-}" ]]; then
  echo "❌  ACCOUNT_ID is not set."
  echo "    export ACCOUNT_ID=\"<your-account-id>\""
  exit 1
fi

if [[ -z "${API_TOKEN:-}" ]]; then
  echo "❌  API_TOKEN is not set."
  echo "    export API_TOKEN=\"<your-api-token>\""
  exit 1
fi

for cmd in curl jq; do
  if ! command -v $cmd &>/dev/null; then
    echo "❌  Required tool '$cmd' not found. Please install it."
    exit 1
  fi
done
echo "✅  curl and jq found"

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

echo ""
echo "─────────────────────────────────────────────────────────────"
echo "🚀  Setup complete! Next steps:"
echo ""
echo "    1. Tag a resource:"
echo "       ./scripts/tag-resource.sh -t worker -r my-worker env prod team sre"
echo ""
echo "    2. Read tags back:"
echo "       ./scripts/get-tags.sh -t worker -r my-worker"
echo ""
echo "    3. Filter by tag:"
echo "       ./scripts/filter-resources.sh env prod"
echo ""
echo "─────────────────────────────────────────────────────────────"
