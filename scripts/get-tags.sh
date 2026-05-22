#!/usr/bin/env bash
set -euo pipefail

# Load credentials from .env if present
if [[ -f .env ]]; then
  source .env
fi

usage() {
  cat <<'EOF'
Usage: get-tags.sh -t <resource_type> -r <resource_id>

Examples:
  get-tags.sh -t worker -r my-api
  get-tags.sh -t zone -r example.com
EOF
  exit 1
}

RESOURCE_TYPE=""
RESOURCE_ID=""

while getopts "t:r:h" opt; do
  case $opt in
    t) RESOURCE_TYPE="$OPTARG" ;;
    r) RESOURCE_ID="$OPTARG" ;;
    h|*) usage ;;
  esac
done

if [[ -z "$RESOURCE_TYPE" || -z "$RESOURCE_ID" ]]; then
  usage
fi

echo "🔍  Fetching tags for: type=$RESOURCE_TYPE  id=$RESOURCE_ID"

RESPONSE=$(curl -sS -X GET \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags?resource_type=$RESOURCE_TYPE&resource_id=$RESOURCE_ID" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json")

if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
  echo ""
  echo "📋  Tags:"
  echo "$RESPONSE" | jq '.result.tags // {}'
else
  echo "❌  Failed to fetch tags:"
  echo "$RESPONSE" | jq
  exit 1
fi
