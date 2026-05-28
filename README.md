# Cloudflare Resource Tagging — Live Demo

**Use case: Production Fleet Audit**

You're an SRE managing 50+ Workers. A CVE drops and leadership asks:
> *"Which production resources does the Platform team own?"*

Without tags, you grep through spreadsheets. With tags, you query.

This demo walks you through that story end-to-end — deploying real Workers, tagging them, and querying them with the Resource Tagging API.

## Preflight: Get a Token

The demo needs an **Account Owned Token** with the **`Resource Tagging`** permission.

**⚠️ This is NOT Cloudflare Access tags.** Make sure you see "Resource Tagging" specifically.

1. Go to **Dash → Manage Account → Account API Tokens**
2. Create a token with:
   - **Account** `Resource Tagging` permission (Edit)
   - Account resources: include your account
3. Copy the token and your Account ID for the next step.

**Optional: Zone Tagging**

If you want to include zone tagging in the demo, also add your `ZONE_ID` to `.env`:

```bash
ZONE_ID=your-zone-id-here
```

Find the Zone ID on the right sidebar of any zone's overview page in the Cloudflare dashboard.

## One-Command Start

```bash
git clone <repo>
cd tagging-demo
./setup.sh   # creates .env and validates your token
./demo.sh
```

**Skip deployments** if the Workers already exist:

```bash
./demo.sh --skip-deploy
```

All scripts automatically load `.env`. You can also use environment variables if you prefer.

## What Happens in the Demo

| Step | Action | Talk Track |
|------|--------|------------|
| 0 | Env check | "First, we need an Account Owned Token..." |
| 1 | Deploy 3 Workers | "You run 3 critical services in production..." |
| 2 | Tag the fleet | "Now we attach metadata: environment, team, tier..." |
| 2b | Tag a zone (optional) | "Zones use zone-level endpoints: /zones/{id}/tags..." |
| 3 | Read tags back | "Any resource can be inspected..." |
| 4 | Filter by env | "Show me all production resources" |
| 5 | Combined filter | "Production AND Platform team" — the real question |
| 6 | Negation + GET-merge-PUT | "Retag one worker to staging, then query everything EXCEPT staging" |
| 7 | Cleanup | Optional teardown |

## Demo Workers

Three Workers are deployed (if they don't already exist):

| Worker | Tags |
|--------|------|
| `tagging-demo-api` | `environment=production`, `team=platform`, `tier=critical` |
| `tagging-demo-batch` | `environment=production`, `team=data`, `tier=standard` |
| `tagging-demo-cache` | `environment=production`, `team=platform`, `tier=critical` |



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

# Tag a zone (zone-level resource)
# Note: for zone resources, resource_id must be the Zone ID, not the domain name
./scripts/tag-resource.sh -t zone -r 6bcf8859da225392d8fae3351eb5de3e -z 6bcf8859da225392d8fae3351eb5de3e environment production team platform

# Or using environment variables
export ACCOUNT_ID="..."
export API_TOKEN="..."
./scripts/tag-resource.sh -t worker -r my-api environment production team platform

# Read tags back
./scripts/get-tags.sh -t worker -r my-api

# Read zone tags back
# Note: for zone resources, resource_id must be the Zone ID
./scripts/get-tags.sh -t zone -r <zone_id> -z <zone_id>

# Filter resources
./scripts/filter-resources.sh -t worker team=platform environment=production

# Delete tags
./scripts/delete-tags.sh -t worker -r my-api

# Delete zone tags
# Note: for zone resources, resource_id must be the Zone ID
./scripts/delete-tags.sh -t zone -r <zone_id> -z <zone_id>
```

## API Summary

### Account-level resources (Workers, R2, D1, etc.)

| Action | Method | Endpoint |
|--------|--------|----------|
| Set tags | `PUT` | `/accounts/{id}/tags` |
| Get tags | `GET` | `/accounts/{id}/tags?resource_type=X&resource_id=Y` |
| Delete tags | `DELETE` | `/accounts/{id}/tags?resource_type=X&resource_id=Y` |
| Filter resources | `GET` | `/accounts/{id}/tags/resources?tag=...` |

### Zone-level resources (zones, DNS records, custom hostnames, etc.)

| Action | Method | Endpoint |
|--------|--------|----------|
| Set tags | `PUT` | `/zones/{id}/tags` |
| Get tags | `GET` | `/zones/{id}/tags?resource_type=X&resource_id=Y` |
| Delete tags | `DELETE` | `/zones/{id}/tags` |

**Note:** For `zone` resources, `resource_id` must be the **Zone ID** (32-char hex string), not the domain name.

### Filter Syntax

- `environment=production` — exact match
- `team=platform` `environment=production` — AND logic (multiple `tag` params)
- `environment=production,staging` — OR logic (comma-separated values)
- `!archived` — key does not exist
- `environment!=staging` — negation (key does not equal value)
- `cost-center` — key exists

## Key Takeaway

> Tags turn "grep through spreadsheets" into a one-line API call.

## Resources

- [Resource Tagging docs](https://developers.cloudflare.com/resource-tagging/)
- [Public Beta announcement](https://developers.cloudflare.com/changelog/post/2026-04-27-resource-tagging-public-beta/)
- [Supported resource types](https://developers.cloudflare.com/resource-tagging/reference/resource-types/)
