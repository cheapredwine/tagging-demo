#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Tag a Cloudflare resource.

.DESCRIPTION
    Sets key-value tags on a Cloudflare resource using the Resource Tagging API.

.PARAMETER ResourceType
    The type of resource (e.g., worker, zone).

.PARAMETER ResourceId
    The ID of the resource.

.PARAMETER ZoneId
    Optional zone ID for zone-level resources.

.PARAMETER Tags
    Key-value pairs as arguments (e.g., environment production team platform).

.EXAMPLE
    .\Tag-Resource.ps1 -ResourceType worker -ResourceId my-api -Tags environment,production,team,platform
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceType,

    [Parameter(Mandatory)]
    [string]$ResourceId,

    [string]$ZoneId,

    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [string[]]$Tags
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
    Write-Error "Missing ACCOUNT_ID or API_TOKEN. Create a .env file or set environment variables."
    exit 1
}

# ─── Validate tag pairs ──────────────────────────────────────
if ($Tags.Count % 2 -ne 0) {
    Write-Error "Tags must be key-value pairs."
    exit 1
}

# ─── Build tags hashtable ────────────────────────────────────
$TagsObj = @{}
for ($i = 0; $i -lt $Tags.Count; $i += 2) {
    $TagsObj[$Tags[$i]] = $Tags[$i + 1]
}

$Body = @{
    resource_type = $ResourceType
    resource_id = $ResourceId
    tags = $TagsObj
} | ConvertTo-Json -Depth 10 -Compress

Write-Host "🏷️   Tagging resource: type=$ResourceType  id=$ResourceId"
Write-Host "    Tags: $Body"

# ─── Determine endpoint ──────────────────────────────────────
if ($ZoneId) {
    $Url = "https://api.cloudflare.com/client/v4/zones/$ZoneId/tags"
} else {
    $Url = "https://api.cloudflare.com/client/v4/accounts/$AccountId/tags"
}

# ─── Make request ────────────────────────────────────────────
try {
    $Response = Invoke-RestMethod -Uri $Url -Method Put `
        -Headers @{
            'Authorization' = "Bearer $ApiToken"
            'Content-Type' = 'application/json'
        } -Body $Body

    Write-Host "✅  Tags applied successfully"
} catch {
    $err = $_
    Write-Host "❌  Failed to apply tags:"
    if ($err.ErrorDetails) {
        $err.ErrorDetails | ConvertFrom-Json | ConvertTo-Json -Depth 10
    } else {
        Write-Host $err.Exception.Message
    }
    exit 1
}
