#!/usr/bin/env bash
set -euo pipefail

# Load credentials from .env if present
if [[ -f .env ]]; then
  source .env
fi

usage() {
  cat <<'EOF'
Usage: delete-tags.sh -t <resource_type> -r <resource_id>

Deletes ALL tags on a resource.

Examples:
  delete-tags.sh -t worker -r my-api
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

echo "🗑️   Deleting ALL tags for: type=$RESOURCE_TYPE  id=$RESOURCE_ID"

RESPONSE=$(curl -sS -X DELETE \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags?resource_type=$RESOURCE_TYPE&resource_id=$RESOURCE_ID" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json")

if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
  echo "✅  Tags deleted"
else
  echo "❌  Failed to delete tags:"
  echo "$RESPONSE" | jq
  exit 1
fi
