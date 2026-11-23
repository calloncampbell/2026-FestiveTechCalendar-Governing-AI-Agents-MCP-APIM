<#
.SYNOPSIS
  Switch the per-beat APIM policy variants on stage. The invariant base (auth, routing, token metrics)
  lives in policy fragments and is included by every variant, so toggling never removes it.

.EXAMPLE
  ./scripts/toggle-policy.ps1 -ResourceGroup rg-santa-dev -ApimName apim-santa-xxxx -Beat ratelimit
  ./scripts/toggle-policy.ps1 -ResourceGroup rg-santa-dev -ApimName apim-santa-xxxx -Beat baseline

  Beats: baseline | ratelimit (MCP APIs) | tokenlimit | contentsafety | semanticcache (model API)
  Switching a model beat replaces the previous model beat. 'baseline' resets BOTH MCP and model APIs.
#>
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [ValidateSet('baseline', 'ratelimit', 'tokenlimit', 'contentsafety', 'semanticcache')] [string] $Beat
)
$ErrorActionPreference = 'Stop'
$policyDir = Join-Path $PSScriptRoot '..\infra\apim\policies'
$sub = az account show --query id -o tsv
$base = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

function Set-ApiPolicy([string] $apiId, [string] $file, [string] $keyNamedValue) {
    $xml = Get-Content (Join-Path $policyDir $file) -Raw
    if ($keyNamedValue) { $xml = $xml.Replace('__KEY_NV__', $keyNamedValue) }
    $body = @{ properties = @{ format = 'rawxml'; value = $xml } } | ConvertTo-Json -Depth 5 -Compress
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $body -Encoding utf8
    az rest --method put --url "$base/apis/$apiId/policies/policy?api-version=2024-05-01" --body "@$tmp" --output none
    Remove-Item $tmp
    Write-Host "  $apiId <- $file"
}

$mcpApis = @{ 'santa-naughty-nice-mcp' = 'functionKey'; 'santa-sleigh-mcp' = 'functionKey'; 'santa-existing-mcp' = 'mcpExtensionKey' }
$mcpFile = if ($Beat -eq 'ratelimit') { 'mcp-ratelimit.xml' } else { 'mcp-baseline.xml' }
$modelFile = switch ($Beat) {
    'tokenlimit'    { 'model-token-limit.xml' }
    'contentsafety' { 'model-content-safety.xml' }
    'semanticcache' { 'model-semantic-cache.xml' }
    'baseline'      { 'model-baseline.xml' }
    default         { $null }
}

Write-Host "Beat: $Beat"
if ($Beat -in 'baseline', 'ratelimit') {
    foreach ($api in $mcpApis.Keys) { Set-ApiPolicy $api $mcpFile $mcpApis[$api] }
}
if ($modelFile) { Set-ApiPolicy 'santa-model' $modelFile $null }
