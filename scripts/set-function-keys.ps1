<#
.SYNOPSIS
  azd postdeploy: copy the Function App keys into APIM secret named values.
  Keys are read at deploy time and never written to the repo or azd env.
#>
$ErrorActionPreference = 'Stop'
$rg = $env:AZURE_RESOURCE_GROUP
$func = $env:FUNCTION_APP_NAME
$apim = $env:APIM_NAME
if (-not ($rg -and $func -and $apim)) { throw 'Run via azd (needs AZURE_RESOURCE_GROUP, FUNCTION_APP_NAME, APIM_NAME).' }

$keys = az functionapp keys list -g $rg -n $func -o json | ConvertFrom-Json
$hostKey = $keys.functionKeys.default
if (-not $hostKey) { $hostKey = $keys.masterKey }
$mcpKey = $keys.systemKeys.mcp_extension
if (-not $mcpKey) { throw 'mcp_extension system key not found. Deploy the app first and make sure the host has started once.' }

$sub = az account show --query id -o tsv
$base = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apim/namedValues"
function Set-NamedValue($name, $value) {
    $body = @{ properties = @{ displayName = $name; secret = $true; value = $value } } | ConvertTo-Json -Compress
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $body -Encoding utf8
    az rest --method put --url "$base/$name`?api-version=2024-05-01" --body "@$tmp" --output none
    Remove-Item $tmp
    Write-Host "Updated APIM named value '$name'"
}
Set-NamedValue 'functionKey' $hostKey
Set-NamedValue 'mcpExtensionKey' $mcpKey
