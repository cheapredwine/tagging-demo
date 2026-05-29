# Cloudflare Resource Tagging Demo — Agent Context

## Project Overview

Live demo for Cloudflare Resource Tagging API. Two implementations:
- `bash/` — Original bash scripts
- `powershell/` — PowerShell port (complete and tested)

Shared assets at root: `worker/`, `.env`, `.env.example`

## Current State (Checkpoint)

### ✅ Completed
- [x] Bash scripts moved to `bash/` subdirectory, paths updated
- [x] Zone tagging support added to bash (`-z <zone_id>` flag)
- [x] `--skip-deploy` flag added to bash demo
- [x] PowerShell 7.4.6 installed at `~/.local/bin/pwsh`
- [x] All PowerShell scripts written:
  - `powershell/setup.ps1`
  - `powershell/demo.ps1`
  - `powershell/scripts/Tag-Resource.ps1`
  - `powershell/scripts/Get-Tags.ps1`
  - `powershell/scripts/Remove-Tags.ps1`
  - `powershell/scripts/Find-Resources.ps1`
  - `powershell/scripts/Add-BulkTags.ps1`
- [x] README updated for dual structure
- [x] `.env` has real `ZONE_ID=6bcf8859da225392d8fae3351eb5de3e` (jsherron.com)
- [x] **Syntax validation** — all 7 `.ps1` files pass
- [x] **Makefile deleted** — broken references, no dependents
- [x] **Bug fixes from testing:**
  - `demo.ps1` Step 6: `$existingTags = @{}` → `$null` fallback to avoid hashtable serialization bug
  - `Tag-Resource.ps1`: Added `Position=0/1` to prevent `ZoneId` from stealing positional args
- [x] **`setup.ps1` tested** — token validation works with real credentials
- [x] **`demo.ps1` full run tested** — deploy, tag, filter, GET-merge-PUT, zone tagging all work
- [x] **Helper scripts tested individually** — all 5 work correctly
- [x] **Cleanup flow tested** — removes tags and workers successfully

### 🚧 In Progress / Not Yet Done
- [ ] **Tag v2** when ready

### 📝 Known Issues / Decisions
- Zone tagging requires Zone ID as `resource_id` (not domain name) — documented in README
- Bash scripts reference `../.env` since they're now in `bash/scripts/`
- PowerShell scripts compute root dir via `Split-Path -Parent (Split-Path -Parent $PSScriptRoot)` to reach repo root `.env`
- `ValueFromRemainingArguments` params (`Tags`, `Filters`, `ResourceIds`) must be passed positionally when using `pwsh -File` — documented in README
- `Find-Resources.ps1` uses `[System.Web.HttpUtility]::UrlEncode` — works on PS 7.4.6 without explicit assembly load

## Architecture

### Bash
```
bash/
├── setup.sh          # Interactive setup, writes ../.env
├── demo.sh           # Full demo with --cleanup, --skip-deploy
└── scripts/
    ├── tag-resource.sh      # -t -r [-z] key value...
    ├── get-tags.sh          # -t -r [-z]
    ├── delete-tags.sh       # -t -r [-z]
    ├── filter-resources.sh  # [-t] filter...
    └── bulk-tag.sh          # type key value ids...
```

### PowerShell
```
powershell/
├── setup.ps1         # Interactive setup, writes ../.env
├── demo.ps1          # Full demo with -Cleanup, -SkipDeploy
└── scripts/
    ├── Tag-Resource.ps1     # -ResourceType -ResourceId [-ZoneId] -Tags
    ├── Get-Tags.ps1         # -ResourceType -ResourceId [-ZoneId]
    ├── Remove-Tags.ps1      # -ResourceType -ResourceId [-ZoneId]
    ├── Find-Resources.ps1   # [-ResourceType] -Filters
    └── Add-BulkTags.ps1     # -ResourceType -TagKey -TagValue -ResourceIds
```

## Key Technical Details

### Zone Tagging
- Endpoint: `/zones/{zone_id}/tags`
- `resource_id` must equal the Zone ID (32-char hex)
- Requires token with **Zone > Resource Tagging > Edit**

### Skip Deploy Logic
- Bash: `worker_exists()` queries `/accounts/{id}/workers/scripts/{name}`
- PowerShell: `Test-WorkerExists()` same endpoint

### .env Loading
- Bash: `source ../.env` from scripts, `source .env` from root-level scripts
- PowerShell: Parse `.env` manually (no native `source` equivalent), set process env vars

## Testing PowerShell Locally

```bash
# PowerShell binary location
~/.local/bin/pwsh -Command "Write-Host 'works'"

# Syntax check all scripts
for f in powershell/*.ps1 powershell/scripts/*.ps1; do
  ~/.local/bin/pwsh -Command "Get-Command $f" 2>&1 | head -1
done

# Run a script
~/.local/bin/pwsh -File powershell/setup.ps1
```

## Next Session Priorities

1. **Tag v2** when ready
2. **Consider adding CI/tests** for both implementations

## Environment

- macOS (darwin), arm64
- PowerShell 7.4.6 at `~/.local/bin/pwsh`
- Repo: https://github.com/cheapredwine/tagging-demo
- Current tag: `v1` (bash only) — PowerShell ready for `v2`
