#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Get tags for a Cloudflare resource.

.PARAMETER ResourceType
    The type of resource.

.PARAMETER ResourceId
    The ID of the resource.

.PARAMETER ZoneId
    Optional zone ID for zone-level resources.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceType,

    [Parameter(Mandatory)]
    [string]$ResourceId,

    [string]$ZoneId
)

# ─── Load credentials ────────────────────────────────────────
$ScriptDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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
    Write-Error "Missing ACCOUNT_ID or API_TOKEN."
    exit 1
}

Write-Host "🔍  Fetching tags for: type=$ResourceType  id=$ResourceId"

# ─── Determine endpoint ──────────────────────────────────────
if ($ZoneId) {
    $Url = "https://api.cloudflare.com/client/v4/zones/$ZoneId/tags?resource_type=$ResourceType&resource_id=$ResourceId"
} else {
    $Url = "https://api.cloudflare.com/client/v4/accounts/$AccountId/tags?resource_type=$ResourceType&resource_id=$ResourceId"
}

# ─── Make request ────────────────────────────────────────────
try {
    $Response = Invoke-RestMethod -Uri $Url -Method Get `
        -Headers @{
            'Authorization' = "Bearer $ApiToken"
            'Content-Type' = 'application/json'
        }

    Write-Host ""
    Write-Host "📋  Tags:"
    $Response.result.tags | ConvertTo-Json -Depth 10
} catch {
    $err = $_
    Write-Host "❌  Failed to fetch tags:"
    if ($err.ErrorDetails) {
        $err.ErrorDetails | ConvertFrom-Json | ConvertTo-Json -Depth 10
    } else {
        Write-Host $err.Exception.Message
    }
    exit 1
}
