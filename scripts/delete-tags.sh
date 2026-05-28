#!/usr/bin/env bash
set -euo pipefail

# Load credentials from .env if present
if [[ -f .env ]]; then
  source .env
fi

usage() {
  cat <<'EOF'
Usage: delete-tags.sh -t <resource_type> -r <resource_id> [-z <zone_id>]

Deletes ALL tags on a resource.

Examples:
  delete-tags.sh -t worker -r my-api
  delete-tags.sh -t zone -r <zone_id> -z <zone_id>
EOF
  exit 1
}

RESOURCE_TYPE=""
RESOURCE_ID=""
ZONE_ID=""

while getopts "t:r:z:h" opt; do
  case $opt in
    t) RESOURCE_TYPE="$OPTARG" ;;
    r) RESOURCE_ID="$OPTARG" ;;
    z) ZONE_ID="$OPTARG" ;;
    h|*) usage ;;
  esac
done

if [[ -z "$RESOURCE_TYPE" || -z "$RESOURCE_ID" ]]; then
  usage
fi

echo "🗑️   Deleting ALL tags for: type=$RESOURCE_TYPE  id=$RESOURCE_ID"

BODY=$(jq -n \
  --arg rt "$RESOURCE_TYPE" \
  --arg rid "$RESOURCE_ID" \
  '{resource_type: $rt, resource_id: $rid}')

if [[ -n "$ZONE_ID" ]]; then
  URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/tags"
else
  URL="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags"
fi

DEL_FULL=$(curl -sS -X DELETE \
  "$URL" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  -w "\nHTTP_STATUS:%{http_code}")

HTTP_CODE=$(echo "$DEL_FULL" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
RESPONSE=$(echo "$DEL_FULL" | sed '/HTTP_STATUS:/d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "✅  Tags deleted (HTTP $HTTP_CODE)"
else
  echo "❌  Failed to delete tags (HTTP $HTTP_CODE):"
  if [[ -n "$RESPONSE" ]]; then
    echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
  fi
  exit 1
fi
