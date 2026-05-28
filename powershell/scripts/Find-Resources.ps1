#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Filter Cloudflare resources by tags.

.PARAMETER ResourceType
    Optional resource type filter.

.PARAMETER Filters
    Tag filters as positional arguments.

.EXAMPLE
    .\Find-Resources.ps1 team=platform environment=production
    .\Find-Resources.ps1 -ResourceType worker environment!=staging
#>
[CmdletBinding()]
param(
    [string]$ResourceType,

    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [string[]]$Filters
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

# ─── Build URL ───────────────────────────────────────────────
$Url = "https://api.cloudflare.com/client/v4/accounts/$AccountId/tags/resources"
$QueryParts = @()

foreach ($Filter in $Filters) {
    $Encoded = [System.Web.HttpUtility]::UrlEncode($Filter)
    $QueryParts += "tag=$Encoded"
}

if ($ResourceType) {
    $QueryParts += "type=$ResourceType"
}

if ($QueryParts.Count -gt 0) {
    $Url = $Url + "?" + ($QueryParts -join '&')
}

Write-Host "🔎  Filtering resources"
if ($ResourceType) {
    Write-Host "    Type:  $ResourceType"
}
Write-Host "    Filters: $($Filters -join ', ')"
Write-Host ""

# ─── Make request ────────────────────────────────────────────
try {
    $Response = Invoke-RestMethod -Uri $Url -Method Get `
        -Headers @{
            'Authorization' = "Bearer $ApiToken"
            'Content-Type' = 'application/json'
        }

    $Count = if ($Response.result) { $Response.result.Count } else { 0 }
    Write-Host "✅  Found $Count resource(s)"
    Write-Host ""
    $Response.result | ConvertTo-Json -Depth 10
} catch {
    $err = $_
    Write-Host "❌  Query failed:"
    if ($err.ErrorDetails) {
        $err.ErrorDetails | ConvertFrom-Json | ConvertTo-Json -Depth 10
    } else {
        Write-Host $err.Exception.Message
    }
    exit 1
}
