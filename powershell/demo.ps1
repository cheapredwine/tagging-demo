#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Cloudflare Resource Tagging — Live Demo Script (PowerShell)

.DESCRIPTION
    Walks through the "Production Fleet Audit" use case end-to-end.

.PARAMETER Cleanup
    Remove all demo tags and workers (skips demo).

.PARAMETER SkipDeploy
    Skip Worker deployment if they already exist.
#>
[CmdletBinding()]
param(
    [switch]$Cleanup,
    [switch]$SkipDeploy,
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: demo.ps1 [-Cleanup] [-SkipDeploy]"
    Write-Host ""
    Write-Host "  -Cleanup     Remove all demo tags and workers (skips demo)"
    Write-Host "  -SkipDeploy  Skip Worker deployment if they already exist"
    Write-Host "  -Help        Show this help"
    exit 0
}

$ErrorActionPreference = 'Stop'

$DEMO_DIR = Split-Path -Parent $PSScriptRoot

# ─── Load credentials ────────────────────────────────────────
$EnvPath = Join-Path $DEMO_DIR '.env'
if (Test-Path $EnvPath) {
    Get-Content $EnvPath | ForEach-Object {
        if ($_ -match '^\s*([^#\s][^=]*)\s*=\s*(.*)\s*$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

$ZONE_ID = $env:ZONE_ID

# ─── Colors ──────────────────────────────────────────────────
$RED = "`e[0;31m"
$GREEN = "`e[0;32m"
$YELLOW = "`e[1;33m"
$BLUE = "`e[0;34m"
$CYAN = "`e[0;36m"
$NC = "`e[0m"
$BRIGHT = "`e[1;37m"

function say($msg) { Write-Host "${CYAN}▶ $msg${NC}" }
function warn($msg) { Write-Host "${YELLOW}▶ $msg${NC}" }
function ok($msg) { Write-Host "${GREEN}✓ $msg${NC}" }
function header($msg) {
    Write-Host ""
    Write-Host "${BLUE}════════════════════════════════════════════════════════════${NC}"
    Write-Host "${BLUE}$msg${NC}"
    Write-Host "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

function Show-Request($method, $url, $body) {
    $redactedAccount = if ($env:ACCOUNT_ID) { $env:ACCOUNT_ID.Substring(0, [Math]::Min(4, $env:ACCOUNT_ID.Length)) + '****' + $env:ACCOUNT_ID.Substring($env:ACCOUNT_ID.Length - 4) } else { '****' }
    $displayUrl = $url -replace '\{account_id\}', $redactedAccount
    $redactedToken = if ($env:API_TOKEN) { $env:API_TOKEN.Substring(0, [Math]::Min(4, $env:API_TOKEN.Length)) + '****' + $env:API_TOKEN.Substring($env:API_TOKEN.Length - 4) } else { '****' }

    Write-Host ""
    Write-Host "${BRIGHT}  ┌─ HTTP Request ──────────────────────────────────────────┐${NC}"
    Write-Host "${BRIGHT}  │ $method $displayUrl${NC}"
    Write-Host "${BRIGHT}  │ Authorization: Bearer $redactedToken${NC}"
    if ($body) {
        Write-Host "${BRIGHT}  │ Content-Type: application/json${NC}"
        $body | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10 | ForEach-Object {
            Write-Host "${BRIGHT}  │ $_${NC}"
        }
    }
    Write-Host "${BRIGHT}  └────────────────────────────────────────────────────────┘${NC}"
    Write-Host ""
}

function Show-Wrangler($cmd) {
    $redactedAccount = if ($env:ACCOUNT_ID) { $env:ACCOUNT_ID.Substring(0, [Math]::Min(4, $env:ACCOUNT_ID.Length)) + '****' + $env:ACCOUNT_ID.Substring($env:ACCOUNT_ID.Length - 4) } else { '****' }
    Write-Host ""
    Write-Host "${BRIGHT}  ┌─ Wrangler Command ──────────────────────────────────────┐${NC}"
    Write-Host "${BRIGHT}  │ $cmd${NC}"
    Write-Host "${BRIGHT}  │ CLOUDFLARE_ACCOUNT_ID=$redactedAccount${NC}"
    Write-Host "${BRIGHT}  └────────────────────────────────────────────────────────┘${NC}"
    Write-Host ""
}

function Invoke-CfApi($url) {
    $headers = @{
        'Authorization' = "Bearer $($env:API_TOKEN)"
        'Content-Type' = 'application/json'
    }
    $method = if ($args[0]) { $args[0] } else { 'Get' }
    $body = if ($args[1]) { $args[1] } else { $null }

    if ($body) {
        return Invoke-RestMethod -Uri $url -Method $method -Headers $headers -Body $body
    } else {
        return Invoke-RestMethod -Uri $url -Method $method -Headers $headers
    }
}

function Test-WorkerExists($name) {
    # Use the tagging API (same token) instead of Workers API
    # which requires a separate Workers:Read permission.
    try {
        $resp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags?resource_type=worker&resource_id=$name"
        # success=true means the worker exists (even if it has no tags)
        return $resp.success -eq $true
    } catch {
        return $false
    }
}

function Pause-Prompt {
    Write-Host ""
    Read-Host -Prompt "Press [Enter] to continue..."
    Write-Host ""
}

function Invoke-Cleanup {
    header "Cleanup"
    foreach ($w in @('tagging-demo-api', 'tagging-demo-batch', 'tagging-demo-cache')) {
        say "Removing tags from ${w}..."
        $delBody = @{ resource_type = 'worker'; resource_id = $w } | ConvertTo-Json -Compress
        Show-Request 'DELETE' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags' $delBody

        try {
            $null = Invoke-WebRequest -Uri "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags" `
                -Method Delete -Headers @{
                    'Authorization' = "Bearer $($env:API_TOKEN)"
                    'Content-Type' = 'application/json'
                } -Body $delBody
            ok "  Tags removed"
        } catch {
            warn "  Delete failed: $($_.Exception.Message)"
        }

        say "Deleting ${w}..."
        Push-Location (Join-Path $DEMO_DIR 'worker')
        try {
            $env:CLOUDFLARE_ACCOUNT_ID = $env:ACCOUNT_ID
            npx wrangler delete $w --force 2>&1 | Out-Null
            ok "  ${w} cleaned up"
        } catch {
            ok "  ${w} cleaned up (or not found)"
        } finally {
            Pop-Location
        }
    }

    if ($ZONE_ID) {
        say "Removing tags from zone..."
        $delBody = @{ resource_type = 'zone'; resource_id = $ZONE_ID } | ConvertTo-Json -Compress
        Show-Request 'DELETE' 'https://api.cloudflare.com/client/v4/zones/{zone_id}/tags' $delBody

        try {
            $null = Invoke-WebRequest -Uri "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/tags" `
                -Method Delete -Headers @{
                    'Authorization' = "Bearer $($env:API_TOKEN)"
                    'Content-Type' = 'application/json'
                } -Body $delBody
            ok "  Zone tags removed"
        } catch {
            warn "  Zone tag delete failed: $($_.Exception.Message)"
        }
    }
}

# ═════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════

# ─── 1. PREREQS ──────────────────────────────────────────────
header "STEP 0  —  Environment Check"

if (-not $env:ACCOUNT_ID -or -not $env:API_TOKEN) {
    Write-Host "${RED}❌  Missing credentials.${NC}"
    Write-Host ""
    Write-Host "Set them as environment variables or create a .env file:"
    Write-Host ""
    Write-Host "    cp .env.example .env"
    Write-Host "    # edit .env with your ACCOUNT_ID and API_TOKEN"
    Write-Host ""
    Write-Host "Or export directly:"
    Write-Host "    `$env:ACCOUNT_ID = 'your-account-id'"
    Write-Host "    `$env:API_TOKEN = 'your-api-token'"
    Write-Host ""
    Write-Host "Token needs Account > Resource Tagging > Edit permission."
    Write-Host "Create one at: https://dash.cloudflare.com/profile/api-tokens"
    exit 1
}

ok "Checking token..."
try {
    $me = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags?resource_type=worker&resource_id=demo-validation-test"
    if ($me.success -ne $true) {
        Write-Host $me.errors[0].message
        Write-Host ""
        Write-Host "Make sure your token has: Account > Resource Tagging > Edit"
        exit 1
    }
} catch {
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Make sure your token has: Account > Resource Tagging > Edit"
    exit 1
}
ok "Token valid"

if ($Cleanup) {
    Invoke-Cleanup
    exit 0
}

# ─── 2. THE SETUP ────────────────────────────────────────────
header "THE SCENARIO"

say "You run 3 critical services in production:"
say "  • tagging-demo-api    — public API gateway"
say "  • tagging-demo-batch  — background job processor"
say "  • tagging-demo-cache  — edge cache layer"

if ($ZONE_ID) {
    say "You also manage a DNS zone on Cloudflare."
}

say "Each is owned by a different team and has a different reliability tier."
say "Today a CVE is announced. Leadership wants a list of ALL production"
say "resources owned by the Platform team so they can schedule a patch window."

Pause-Prompt

# ─── 3. CREATE DEMO WORKERS ──────────────────────────────────
header "STEP 1  —  Deploy the Demo Workers"

say "Wrangler bundles your code, uploads it to Cloudflare, and publishes"
say "the Worker to the edge network. Here's what that looks like:"

# Check wrangler auth
$wranglerWhoami = npx wrangler whoami 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "${RED}❌  Wrangler is not authenticated.${NC}"
    Write-Host "    Run: npx wrangler login"
    Write-Host "    Or set CLOUDFLARE_API_TOKEN with Workers:Edit permission."
    exit 1
}

foreach ($worker in @('tagging-demo-api', 'tagging-demo-batch', 'tagging-demo-cache')) {
    Write-Host ""

    if ($SkipDeploy -and (Test-WorkerExists $worker)) {
        ok "  ${worker} already exists — skipping deploy"
        continue
    }

    Write-Host "${BLUE}  ▓▓▓ Deploying ${worker} ▓▓▓${NC}"
    Push-Location (Join-Path $DEMO_DIR 'worker')

    Show-Wrangler "npx wrangler deploy --name ${worker}"

    $env:CLOUDFLARE_ACCOUNT_ID = $env:ACCOUNT_ID
    $deployOutput = npx wrangler deploy --name $worker 2>&1
    $deployOk = $LASTEXITCODE -eq 0

    if ($deployOk) {
        $deployOutput | Select-String '(Published|URL|Route|Worker)' | ForEach-Object { Write-Host "  $_" }
        ok "  ${worker} deployed ✓"
    } else {
        warn "  ${worker} deploy failed:"
        Write-Host $deployOutput
    }

    Pop-Location
}

Pause-Prompt

# ─── 4. TAG EVERYTHING ───────────────────────────────────────
header "STEP 2  —  Tag the Fleet"

say "Now we attach metadata. This is the 'tag' action."
say "Tags are plain key-value strings. We'll use:"
say "  • environment: production | staging"
say "  • team: platform | data | infra"
say "  • tier: critical | standard"

$apiJson = @{ resource_type = 'worker'; resource_id = 'tagging-demo-api'; tags = @{ environment = 'production'; team = 'platform'; tier = 'critical' } } | ConvertTo-Json -Compress
$batchJson = @{ resource_type = 'worker'; resource_id = 'tagging-demo-batch'; tags = @{ environment = 'production'; team = 'data'; tier = 'standard' } } | ConvertTo-Json -Compress
$cacheJson = @{ resource_type = 'worker'; resource_id = 'tagging-demo-cache'; tags = @{ environment = 'production'; team = 'platform'; tier = 'critical' } } | ConvertTo-Json -Compress

say "Tagging tagging-demo-api  →  prod / platform / critical"
Show-Request 'PUT' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags' $apiJson
try {
    $apiResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags" Put $apiJson
    $apiResp | ConvertTo-Json -Depth 10
    ok "  Tagged"
} catch {
    warn "  Failed: $($_.Exception.Message)"
}

say "Tagging tagging-demo-batch →  prod / data / standard"
Show-Request 'PUT' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags' $batchJson
try {
    $batchResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags" Put $batchJson
    $batchResp | ConvertTo-Json -Depth 10
    ok "  Tagged"
} catch {
    warn "  Failed: $($_.Exception.Message)"
}

say "Tagging tagging-demo-cache →  prod / platform / critical"
Show-Request 'PUT' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags' $cacheJson
try {
    $cacheResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags" Put $cacheJson
    $cacheResp | ConvertTo-Json -Depth 10
    ok "  Tagged"
} catch {
    warn "  Failed: $($_.Exception.Message)"
}

say ""
say "Notice: PUT is replace-all. If you omit a key, it disappears."
say "This makes the API idempotent — great for GitOps / Terraform."
ok "Fleet tagged."
Pause-Prompt

# ─── 4b. TAG A ZONE (optional) ──────────────────────────────
if ($ZONE_ID) {
    header "STEP 2b  —  Tag a Zone"

    say "Zones are zone-level resources. They use a different endpoint:"
    say "  /zones/{zone_id}/tags  instead of  /accounts/{account_id}/tags"

    $zoneJson = @{
        resource_type = 'zone'
        resource_id = $ZONE_ID
        tags = @{ environment = 'production'; team = 'platform'; tier = 'critical' }
    } | ConvertTo-Json -Compress

    say "Tagging zone ${ZONE_ID} →  prod / platform / critical"
    Show-Request 'PUT' 'https://api.cloudflare.com/client/v4/zones/{zone_id}/tags' $zoneJson
    try {
        $zoneResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/tags" Put $zoneJson
        $zoneResp | ConvertTo-Json -Depth 10
        ok "  Zone tagged"
    } catch {
        warn "  Failed: $($_.Exception.Message)"
    }

    Pause-Prompt
}

# ─── 5. READ BACK ────────────────────────────────────────────
header "STEP 3  —  Read Tags Back"

say "Any resource can be inspected. Let's look at the API worker:"
Show-Request 'GET' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags?resource_type=worker&resource_id=tagging-demo-api'
Write-Host "  Response:"
try {
    $readResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags?resource_type=worker&resource_id=tagging-demo-api"
    $readResp | ConvertTo-Json -Depth 10
} catch {
    warn "  Failed: $($_.Exception.Message)"
}
Pause-Prompt

# ─── 6. FILTER ───────────────────────────────────────────────
header "STEP 4  —  Filter: 'Show me all production resources'"

say "This is where tags pay off. Instead of spreadsheets, we query the API."
say "Query: environment=production"
Show-Request 'GET' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags/resources?tag=environment=production'
try {
    $filterResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags/resources?tag=environment=production"
    Write-Host "  Response:"
    $filterResp | ConvertTo-Json -Depth 10
} catch {
    warn "  Failed: $($_.Exception.Message)"
}

Pause-Prompt

# ─── 7. COMBINED FILTER ──────────────────────────────────────
header "STEP 5  —  Filter: 'Production AND Platform team'"

say "Now the real question from leadership:"
say "  Which production resources are owned by the Platform team?"
say "Query: team=platform AND environment=production"
Show-Request 'GET' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags/resources?tag=team=platform&tag=environment=production'
try {
    $filterResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags/resources?tag=team=platform&tag=environment=production"
    Write-Host "  Response:"
    $filterResp | ConvertTo-Json -Depth 10
    $platformCount = if ($filterResp.result) { $filterResp.result.Count } else { 0 }
    ok "Result: $platformCount resource(s) — platform team, production."
} catch {
    warn "  Failed: $($_.Exception.Message)"
}
Pause-Prompt

# ─── 8. NEGATION + GET-MERGE-PUT ─────────────────────────────
header "STEP 6  —  Filter: 'Everything EXCEPT staging'"

say "Let's say tagging-demo-batch gets demoted to staging."
say "We need to change its environment tag without wiping the others."
say "This is the GET-merge-PUT pattern:"

# 1. GET existing tags
Show-Request 'GET' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags?resource_type=worker&resource_id=tagging-demo-batch'
try {
    $getResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags?resource_type=worker&resource_id=tagging-demo-batch"
    Write-Host "  Response:"
    $getResp.result.tags | ConvertTo-Json -Depth 10
    $existingTags = $getResp.result.tags
} catch {
    warn "  Failed: $($_.Exception.Message)"
    $existingTags = $null
}

# 2. Merge new tag value
$merged = [ordered]@{}
if ($existingTags) {
    foreach ($key in $existingTags.PSObject.Properties.Name) {
        $merged[$key] = $existingTags.$key
    }
}
$merged['environment'] = 'staging'

# 3. PUT merged tags
$stagingBody = @{
    resource_type = 'worker'
    resource_id = 'tagging-demo-batch'
    tags = $merged
} | ConvertTo-Json -Compress

Show-Request 'PUT' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags' $stagingBody
try {
    $stagingResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags" Put $stagingBody
    $stagingResp | ConvertTo-Json -Depth 10
    ok "  tagging-demo-batch moved to staging"
} catch {
    warn "  Failed: $($_.Exception.Message)"
}

say ""
say "Query: NOT environment=staging"
Show-Request 'GET' 'https://api.cloudflare.com/client/v4/accounts/{account_id}/tags/resources?tag=environment!=staging'
try {
    $negResp = Invoke-CfApi "https://api.cloudflare.com/client/v4/accounts/$($env:ACCOUNT_ID)/tags/resources?tag=environment!=staging"
    Write-Host "  Response:"
    $negResp | ConvertTo-Json -Depth 10
    $notStagingCount = if ($negResp.result) { $negResp.result.Count } else { 0 }
    ok "Result: $notStagingCount resource(s) — staging worker excluded."
} catch {
    warn "  Failed: $($_.Exception.Message)"
}
Pause-Prompt

header "Demo Complete"
say "Use case shown: Fleet audit with environment + team + tier tags."
say "Key takeaway: Tags turn 'grep through spreadsheets' into a 1-line API call."
Write-Host ""
say "To clean up demo resources: .\demo.ps1 -Cleanup"
