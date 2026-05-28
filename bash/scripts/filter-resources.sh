#!/usr/bin/env bash
set -euo pipefail

# Load credentials from .env if present
if [[ -f ../.env ]]; then
  source ../.env
fi

usage() {
  cat <<'EOF'
Usage: filter-resources.sh [-t <resource_type>] <tag_filter>...

Filter syntax (one tag filter per argument):
  key=value           key equals value
  key=value1,value2   key equals value1 OR value2
  key                 key exists (any value)
  !key                key does NOT exist
  key!=value          key does NOT equal value

Multiple filters combine with AND logic.

Examples:
  filter-resources.sh environment=production
  filter-resources.sh -t worker team=platform environment=production
  filter-resources.sh -t worker environment!=staging
  filter-resources.sh -t worker cost-center
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

# Build URL with multiple tag params
URL="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tags/resources"

FIRST=1
for FILTER in "$@"; do
  if [[ $FIRST -eq 1 ]]; then
    URL="${URL}?tag=$(jq -sRr '@uri' <<< "$FILTER")"
    FIRST=0
  else
    URL="${URL}&tag=$(jq -sRr '@uri' <<< "$FILTER")"
  fi
done

if [[ -n "$RESOURCE_TYPE" ]]; then
  URL="${URL}&type=$RESOURCE_TYPE"
fi

echo "🔎  Filtering resources"
if [[ -n "$RESOURCE_TYPE" ]]; then
  echo "    Type:  $RESOURCE_TYPE"
fi
echo "    Filters: $*"
echo ""

RESPONSE=$(curl -sS -X GET "$URL" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json")

if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
  COUNT=$(echo "$RESPONSE" | jq '.result // [] | length')
  echo "✅  Found $COUNT resource(s)"
  echo ""
  echo "$RESPONSE" | jq '.result // []'
else
  echo "❌  Query failed:"
  echo "$RESPONSE" | jq
  exit 1
fi
