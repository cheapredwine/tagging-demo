#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Delete all tags from a Cloudflare resource.

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
    Write-Error "Missing ACCOUNT_ID or API_TOKEN."
    exit 1
}

Write-Host "🗑️   Deleting ALL tags for: type=$ResourceType  id=$ResourceId"

$Body = @{
    resource_type = $ResourceType
    resource_id = $ResourceId
} | ConvertTo-Json -Depth 10 -Compress

# ─── Determine endpoint ──────────────────────────────────────
if ($ZoneId) {
    $Url = "https://api.cloudflare.com/client/v4/zones/$ZoneId/tags"
} else {
    $Url = "https://api.cloudflare.com/client/v4/accounts/$AccountId/tags"
}

# ─── Make request ────────────────────────────────────────────
try {
    $Response = Invoke-WebRequest -Uri $Url -Method Delete `
        -Headers @{
            'Authorization' = "Bearer $ApiToken"
            'Content-Type' = 'application/json'
        } -Body $Body

    Write-Host "✅  Tags deleted (HTTP $($Response.StatusCode))"
} catch {
    $err = $_
    Write-Host "❌  Failed to delete tags:"
    if ($err.ErrorDetails) {
        $err.ErrorDetails | ConvertFrom-Json | ConvertTo-Json -Depth 10
    } else {
        Write-Host $err.Exception.Message
    }
    exit 1
}
