#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Bulk-tag multiple Cloudflare resources.

.PARAMETER ResourceType
    The type of resource.

.PARAMETER TagKey
    The tag key.

.PARAMETER TagValue
    The tag value.

.PARAMETER ResourceIds
    One or more resource IDs.

.EXAMPLE
    .\Add-BulkTags.ps1 -ResourceType worker -TagKey environment -TagValue production -ResourceIds worker-a, worker-b, worker-c
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceType,

    [Parameter(Mandatory)]
    [string]$TagKey,

    [Parameter(Mandatory)]
    [string]$TagValue,

    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [string[]]$ResourceIds
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

Write-Host "🏷️   Bulk-tagging $($ResourceIds.Count) resource(s)"
Write-Host "    Type:  $ResourceType"
Write-Host "    Tag:   $TagKey = $TagValue"
Write-Host ""

$Failed = 0
foreach ($Rid in $ResourceIds) {
    $Body = @{
        resource_type = $ResourceType
        resource_id = $Rid
        tags = @{ $TagKey = $TagValue }
    } | ConvertTo-Json -Depth 10 -Compress

    $Url = "https://api.cloudflare.com/client/v4/accounts/$AccountId/tags"

    try {
        $null = Invoke-RestMethod -Uri $Url -Method Put `
            -Headers @{
                'Authorization' = "Bearer $ApiToken"
                'Content-Type' = 'application/json'
            } -Body $Body
        Write-Host "  ✅  $Rid"
    } catch {
        $errMsg = if ($_.ErrorDetails) {
            ($_.ErrorDetails | ConvertFrom-Json).errors[0].message
        } else {
            $_.Exception.Message
        }
        Write-Host "  ❌  $Rid — $errMsg"
        $Failed++
    }
}

Write-Host ""
if ($Failed -eq 0) {
    Write-Host "✅  All resources tagged successfully"
} else {
    Write-Host "⚠️   $Failed resource(s) failed"
    exit 1
}
