#!/usr/bin/env bash
set -euo pipefail

# Load credentials from .env if present
if [[ -f ../.env ]]; then
  source ../.env
fi

usage() {
  cat <<'EOF'
Usage: bulk-tag.sh <resource_type> <tag_key> <tag_value> [resource_id ...]

Applies the same tag to multiple resources in one shot.

Example:
  bulk-tag.sh worker environment production worker-a worker-b worker-c
EOF
  exit 1
}

if [[ $# -lt 4 ]]; then
  usage
fi

RESOURCE_TYPE="$1"; TAG_KEY="$2"; TAG_VALUE="$3"
shift 3

echo "🏷️   Bulk-tagging $# resource(s)"
echo "    Type:  $RESOURCE_TYPE"
echo "    Tag:   $TAG_KEY = $TAG_VALUE"
echo ""

FAILED=0
for RID in "$@"; do
  BODY=$(jq -n \
    --arg rt "$RESOURCE_TYPE" \
    --arg rid "$RID" \
    --arg k "$TAG_KEY" \
    --arg v "$TAG_VALUE" \
    '{resource_type: $rt, resource_id: $rid, tags: {($k): $v}}')

  RESPONSE=$(curl -sS -X PUT \
    "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY")

  if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
    echo "  ✅  $RID"
  else
    echo "  ❌  $RID — $(echo "$RESPONSE" | jq -r '.errors[0].message // "unknown error"')"
    ((FAILED++)) || true
  fi
done

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "✅  All resources tagged successfully"
else
  echo "⚠️   $FAILED resource(s) failed"
  exit 1
fi
