#!/usr/bin/env bash
set -euo pipefail

# Load credentials from .env if present
if [[ -f ../.env ]]; then
  source ../.env
fi

usage() {
  cat <<'EOF'
Usage: tag-resource.sh -t <resource_type> -r <resource_id> [-z <zone_id>] [key value]...

Examples:
  tag-resource.sh -t worker -r my-api environment production team platform
  tag-resource.sh -t zone -r <zone_id> -z <zone_id> customer acme-corp
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
shift $((OPTIND - 1))

if [[ -z "$RESOURCE_TYPE" || -z "$RESOURCE_ID" ]]; then
  usage
fi

if (( $# % 2 != 0 )); then
  echo "❌  Tags must be key-value pairs."
  usage
fi

TAGS_JSON="{}"
while (( $# > 0 )); do
  KEY="$1"; VALUE="$2"; shift 2
  TAGS_JSON=$(echo "$TAGS_JSON" | jq --arg k "$KEY" --arg v "$VALUE" '. + {($k): $v}')
done

echo "🏷️   Tagging resource: type=$RESOURCE_TYPE  id=$RESOURCE_ID"
echo "    Tags: $TAGS_JSON"

BODY=$(jq -n \
  --arg rt "$RESOURCE_TYPE" \
  --arg rid "$RESOURCE_ID" \
  --argjson tags "$TAGS_JSON" \
  '{resource_type: $rt, resource_id: $rid, tags: $tags}')

if [[ -n "$ZONE_ID" ]]; then
  URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/tags"
else
  URL="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags"
fi

RESPONSE=$(curl -sS -X PUT \
  "$URL" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY")

if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
  echo "✅  Tags applied successfully"
else
  echo "❌  Failed to apply tags:"
  echo "$RESPONSE" | jq
  exit 1
fi
