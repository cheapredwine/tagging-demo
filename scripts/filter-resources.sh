#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: filter-resources.sh [-t <resource_type>] <filter_expression>

Filter expressions:
  key:value           exact match
  key:value AND key2:value2
  key:value OR key2:value2
  NOT key:value
  key                 key exists

Examples:
  filter-resources.sh environment production
  filter-resources.sh -t worker "team:platform AND environment:production"
  filter-resources.sh -t zone "NOT environment:staging"
  filter-resources.sh -t worker "cost-center"
EOF
  exit 1
}

RESOURCE_TYPE=""

while getopts "t:h" opt; do
  case $opt in
    t) RESOURCE_TYPE="$OPTARG" ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -lt 1 ]]; then
  usage
fi

FILTER="$1"

URL="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags"
if [[ -n "$RESOURCE_TYPE" ]]; then
  URL="$URL?resource_type=$RESOURCE_TYPE&filter=$FILTER"
else
  URL="$URL?filter=$FILTER"
fi

echo "🔎  Filtering resources"
if [[ -n "$RESOURCE_TYPE" ]]; then
  echo "    Type:  $RESOURCE_TYPE"
fi
echo "    Filter: $FILTER"
echo ""

RESPONSE=$(curl -sS -X GET "$URL" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json")

if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
  COUNT=$(echo "$RESPONSE" | jq '.result | length')
  echo "✅  Found $COUNT resource(s)"
  echo ""
  echo "$RESPONSE" | jq '.result // []'
else
  echo "❌  Query failed:"
  echo "$RESPONSE" | jq
  exit 1
fi
