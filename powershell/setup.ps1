#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Cloudflare Resource Tagging — Demo Setup (PowerShell)
#>

Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║     Cloudflare Resource Tagging — Demo Setup             ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""

# ─── 1. Check dependencies ───────────────────────────────────
$required = @('curl', 'jq')
foreach ($cmd in $required) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Required tool '$cmd' not found. Please install it."
        exit 1
    }
}
Write-Host "✅  curl and jq found"

# ─── 2. Gather credentials ───────────────────────────────────
$ScriptDir = Split-Path -Parent $PSScriptRoot
$EnvPath = Join-Path $ScriptDir '.env'

if (Test-Path $EnvPath) {
    Get-Content $EnvPath | ForEach-Object {
        if ($_ -match '^\s*([^#\s][^=]*)\s*=\s*(.*)\s*$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

$AccountId = $env:ACCOUNT_ID
$ApiToken = $env:API_TOKEN

if (-not $AccountId -or -not $ApiToken) {
    Write-Host ""
    Write-Host "📝  Credentials needed."
    Write-Host ""
    Write-Host "You'll need an Account Owned Token with:"
    Write-Host "  Account > Resource Tagging > Edit"
    Write-Host ""
    Write-Host "⚠️  This is NOT the same as Cloudflare Access tags."
    Write-Host "     Look for 'Resource Tagging' specifically."
    Write-Host ""
    Write-Host "Create one at: https://dash.cloudflare.com/profile/api-tokens"
    Write-Host ""

    $AccountId = Read-Host -Prompt "Account ID"
    $SecureToken = Read-Host -Prompt "API Token" -AsSecureString
    $ApiToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken))
}

# ─── 3. Validate token BEFORE writing anything ───────────────
Write-Host ""
Write-Host "🔑  Validating API token ..."

$ValidateUrl = "https://api.cloudflare.com/client/v4/accounts/$AccountId/tags?resource_type=worker&resource_id=demo-validation-test"
try {
    $TagResponse = Invoke-RestMethod -Uri $ValidateUrl -Method Get `
        -Headers @{
            'Authorization' = "Bearer $ApiToken"
            'Content-Type' = 'application/json'
        }

    Write-Host "✅  Token valid — Resource Tagging API is available"
} catch {
    $err = $_
    $errMsg = if ($err.ErrorDetails) {
        ($err.ErrorDetails | ConvertFrom-Json).errors[0].message
    } else {
        $err.Exception.Message
    }
    Write-Host "❌  Token validation failed: $errMsg"
    Write-Host ""
    Write-Host "Your token needs: Account > Resource Tagging > Edit"
    Write-Host ""
    Write-Host "⚠️  Common mistake: using a token with 'Cloudflare Access > Tags:Edit'"
    Write-Host "     That is a different product. You need 'Resource Tagging' specifically."
    Write-Host ""
    Write-Host "Create one at: https://dash.cloudflare.com/profile/api-tokens"
    exit 1
}

# ─── 4. Write .env only after validation ─────────────────────
if (-not (Test-Path $EnvPath)) {
    @"
# Cloudflare Resource Tagging Demo — Environment Variables
# .env is gitignored and will never be committed.

ACCOUNT_ID=$AccountId
API_TOKEN=$ApiToken
"@ | Set-Content -Path $EnvPath
    Write-Host "✅  .env created"
}

# ─── 5. Done ─────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────"
Write-Host "🚀  Setup complete! Next step:"
Write-Host ""
Write-Host "    .\demo.ps1"
Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────"
