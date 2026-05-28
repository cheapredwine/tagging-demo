# Cloudflare Resource Tagging Demo — Agent Context

## Project Overview

Live demo for Cloudflare Resource Tagging API. Two implementations:
- `bash/` — Original bash scripts
- `powershell/` — PowerShell port (in progress)

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

### 🚧 In Progress / Not Yet Done
- [ ] **Test PowerShell scripts** — none have been run yet
  - Test `setup.ps1` with real credentials
  - Test `demo.ps1` basic flow
  - Test each helper script individually
- [ ] **Fix any PowerShell bugs found during testing**
- [ ] **Update Makefile** for dual structure (or delete if not needed)
- [ ] **Syntax validation** — run `pwsh` syntax checks on all `.ps1` files

### 📝 Known Issues / Decisions
- Zone tagging requires Zone ID as `resource_id` (not domain name) — documented in README
- Bash scripts reference `../.env` since they're now in `bash/scripts/`
- PowerShell scripts use same pattern: compute root dir from `$PSScriptRoot`
- `Find-Resources.ps1` uses `[System.Web.HttpUtility]::UrlEncode` — may need `System.Web` assembly loaded

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

1. **Test PowerShell setup.ps1** — validate token flow, .env creation
2. **Test PowerShell demo.ps1** — full dry run or real run
3. **Fix any runtime bugs** in PowerShell scripts
4. **Delete Makefile** or update it for both bash and PowerShell
5. **Consider adding CI/tests** for both implementations
6. **Tag v2** when PowerShell is fully working

## Environment

- macOS (darwin), arm64
- PowerShell 7.4.6 at `~/.local/bin/pwsh`
- Repo: https://github.com/cheapredwine/tagging-demo
- Current tag: `v1` (bash only)
