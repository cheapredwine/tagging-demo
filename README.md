# Cloudflare Resource Tagging — Live Demo

**Use case: Production Fleet Audit**

You're an SRE managing 50+ Workers. A CVE drops and leadership asks:
> *"Which production resources does the Platform team own?"*

Without tags, you grep through spreadsheets. With tags, you query.

This demo walks you through that story end-to-end — deploying real Workers, tagging them, and querying them with the Resource Tagging API.

## Preflight: Get a Token

The demo needs an **Account Owned Token** with `Tag:Edit` permission.

1. Go to **Dash → Manage Account → Account API Tokens**
2. Create a token with:
   - **Account** `Resource Tagging` permission (Edit)
   - Account resources: include your account
3. Copy the token and your Account ID for the next step.

## One-Command Start

```bash
git clone <repo>
cd tagging-demo
./setup.sh   # creates .env and validates your token
./demo.sh
```

All scripts automatically load `.env`. You can also use environment variables if you prefer.

## What Happens in the Demo

| Step | Action | Talk Track |
|------|--------|------------|
| 0 | Env check | "First, we need an Account Owned Token..." |
| 1 | Deploy 3 Workers | "You run 3 critical services in production..." |
| 2 | Tag the fleet | "Now we attach metadata: environment, team, tier..." |
| 3 | Read tags back | "Any resource can be inspected..." |
| 4 | Filter by env | "Show me all production resources" |
| 5 | Combined filter | "Production AND Platform team" — the real question |
| 6 | Bulk tag | "A 4th worker comes online, tag it + the cache" |
| 7 | Negation | "Everything EXCEPT staging" |
| 8 | Cleanup | Optional teardown |

## Demo Workers

Three Workers are deployed (if they don't already exist):

| Worker | Tags |
|--------|------|
| `tagging-demo-api` | `environment=production`, `team=platform`, `tier=critical` |
| `tagging-demo-batch` | `environment=production`, `team=data`, `tier=standard` |
| `tagging-demo-cache` | `environment=production`, `team=platform`, `tier=critical` |

...and optionally a 4th (`tagging-demo-events`) for bulk-tagging.

## Prerequisites

- `curl` and `jq` installed
- `npx wrangler` available (for Worker deployment)
- A Cloudflare account with Resource Tagging enabled
- An **Account Owned Token** with `Tag:Edit` permission (see Preflight above)

## Manual Mode

If you prefer to run steps individually instead of `demo.sh`:

```bash
# Using .env file (recommended)
./setup.sh   # creates .env and validates token
./scripts/tag-resource.sh -t worker -r my-api environment production team platform

# Or using environment variables
export ACCOUNT_ID="..."
export API_TOKEN="..."
./scripts/tag-resource.sh -t worker -r my-api environment production team platform

# Read tags back
./scripts/get-tags.sh -t worker -r my-api

# Filter resources
./scripts/filter-resources.sh -t worker "team:platform AND environment:production"

# Delete tags
./scripts/delete-tags.sh -t worker -r my-api
```

## API Summary

| Action | Method | Endpoint |
|--------|--------|----------|
| Set tags | `PUT` | `/accounts/{id}/tags` |
| Get tags | `GET` | `/accounts/{id}/tags?resource_type=X&resource_id=Y` |
| Delete tags | `DELETE` | `/accounts/{id}/tags?resource_type=X&resource_id=Y` |
| Filter resources | `GET` | `/accounts/{id}/tags?resource_type=X&filter=...` |

### Filter Syntax

- `environment:production` — exact match
- `team:platform AND environment:production` — AND logic
- `team:platform OR team:sre` — OR logic
- `NOT environment:staging` — negation
- `cost-center` — key exists

## Key Takeaway

> Tags turn "grep through spreadsheets" into a one-line API call.

## Resources

- [Resource Tagging docs](https://developers.cloudflare.com/resource-tagging/)
- [Public Beta announcement](https://developers.cloudflare.com/changelog/post/2026-04-27-resource-tagging-public-beta/)
- [Supported resource types](https://developers.cloudflare.com/resource-tagging/reference/resource-types/)
