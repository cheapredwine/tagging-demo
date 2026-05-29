# Cloudflare Resource Tagging — Live Demo

**Use case: Production Fleet Audit**

You're an SRE managing 50+ Workers. A CVE drops and leadership asks:
> *"Which production resources does the Platform team own?"*

Without tags, you grep through spreadsheets. With tags, you query.

This demo walks you through that story end-to-end — deploying real Workers, tagging them, and querying them with the Resource Tagging API.

## Quick Start

Pick your shell:

### Bash

```bash
git clone <repo>
cd tagging-demo
bash/setup.sh         # creates .env and validates your token
bash/demo.sh
```

### PowerShell

```powershell
git clone <repo>
cd tagging-demo
powershell/setup.ps1  # creates .env and validates your token
powershell/demo.ps1
```

Both read from the same `.env` file at the project root. You can also use environment variables.

## Project Structure

```
tagging-demo/
├── bash/              # Bash scripts
│   ├── demo.sh
│   ├── setup.sh
│   └── scripts/
├── powershell/        # PowerShell scripts
│   ├── demo.ps1
│   ├── setup.ps1
│   └── scripts/
├── worker/            # Shared demo Worker source
├── .env.example       # Copy to .env and fill in credentials
└── README.md
```

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

**Note for zone tagging:** Your token also needs **Zone > Resource Tagging > Edit** permission for the specific zone.

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

## Skip Deployments

If the Workers already exist, skip deployment:

```bash
bash/demo.sh --skip-deploy
```

```powershell
powershell/demo.ps1 -SkipDeploy
```

## Cleanup

Remove all demo tags and Workers:

```bash
bash/demo.sh --cleanup
```

```powershell
powershell/demo.ps1 -Cleanup
```

## Manual Mode (Bash)

```bash
bash/setup.sh
bash/scripts/tag-resource.sh -t worker -r my-api environment production team platform
bash/scripts/get-tags.sh -t worker -r my-api
bash/scripts/filter-resources.sh -t worker team=platform environment=production
bash/scripts/delete-tags.sh -t worker -r my-api
bash/scripts/bulk-tag.sh worker environment production w1 w2 w3
```

## Manual Mode (PowerShell)

```powershell
# From PowerShell interactive shell:
powershell/scripts/Tag-Resource.ps1 -ResourceType worker -ResourceId my-api environment production team platform
powershell/scripts/Get-Tags.ps1 -ResourceType worker -ResourceId my-api
powershell/scripts/Find-Resources.ps1 -ResourceType worker team=platform environment=production
powershell/scripts/Remove-Tags.ps1 -ResourceType worker -ResourceId my-api
powershell/scripts/Add-BulkTags.ps1 -ResourceType worker -TagKey environment -TagValue production w1 w2 w3
```

**Note:** Parameters marked `ValueFromRemainingArguments` (`Tags`, `Filters`, `ResourceIds`) must be passed as positional trailing arguments — do not use the parameter name (e.g., `-Tags` or `-ResourceIds`).

On macOS or Linux, use the `pwsh` binary directly:

```bash
~/.local/bin/pwsh -File powershell/scripts/Tag-Resource.ps1 -ResourceType worker -ResourceId my-api environment production team platform
```

## API Summary

### Account-level resources (Workers, R2, D1, etc.)

| Action | Method | Endpoint |
|--------|--------|----------|
| Set tags | `PUT` | `/accounts/{id}/tags` |
| Get tags | `GET` | `/accounts/{id}/tags?resource_type=X&resource_id=Y` |
| Delete tags | `DELETE` | `/accounts/{id}/tags` |
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
