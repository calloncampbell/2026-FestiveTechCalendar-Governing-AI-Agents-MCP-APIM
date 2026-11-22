targetScope = 'subscription'

@minLength(1)
@maxLength(20)
@description('azd environment name, used to name the resource group and resources.')
param environmentName string

@description('Primary location for all resources.')
param location string

@description('Email shown as the APIM publisher.')
param publisherEmail string

param publisherName string = 'Santa Workshop IT'

@description('Primary MCP auth: project managed identity + validate-jwt. Fallback: APIM subscription key.')
@allowed(['jwt', 'key'])
param mcpAuthMode string = 'jwt'

@description('Audience (App ID URI) expected by validate-jwt.')
param jwtAudience string = 'api://santa-workshop-mcp'

@description('Optional semantic cache: Azure Managed Redis (RediSearch) + embeddings deployment. When false, no cache resources or policies are emitted.')
param enableSemanticCache bool = false

param chatModelName string = 'gpt-4.1-mini'
param chatModelVersion string = '2025-04-14'

var tags = { 'azd-env-name': environmentName, demo: 'santa-workshop' }
var token = toLower(uniqueString(subscription().id, environmentName, location))
var rgName = 'rg-${environmentName}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    workspaceName: 'log-santa-${token}'
    appInsightsName: 'appi-santa-${token}'
  }
}

module functionApp 'modules/function.bicep' = {
  scope: rg
  name: 'function'
  params: {
    location: location
    tags: tags
    functionAppName: 'func-santa-${token}'
    planName: 'plan-santa-${token}'
    storageName: 'stsanta${take(token, 16)}'
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

module foundry 'modules/foundry.bicep' = {
  scope: rg
  name: 'foundry'
  params: {
    location: location
    tags: tags
    accountName: 'ai-santa-${token}'
    projectName: 'santa-workshop'
    chatModelName: chatModelName
    chatModelVersion: chatModelVersion
    deployEmbeddings: enableSemanticCache
  }
}

module contentSafety 'modules/contentsafety.bicep' = {
  scope: rg
  name: 'contentsafety'
  params: {
    location: location
    tags: tags
    name: 'cs-santa-${token}'
  }
}

module redis 'modules/redis.bicep' = if (enableSemanticCache) {
  scope: rg
  name: 'redis'
  params: {
    location: location
    tags: tags
    name: 'redis-santa-${token}'
  }
}

module apim 'modules/apim.bicep' = {
  scope: rg
  name: 'apim'
  params: {
    location: location
    tags: tags
    apimName: 'apim-santa-${token}'
    publisherEmail: publisherEmail
    publisherName: publisherName
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    functionAppHostName: functionApp.outputs.functionAppHostName
    foundryOpenAiEndpoint: foundry.outputs.openAiEndpoint
    contentSafetyEndpoint: contentSafety.outputs.endpoint
    chatDeployment: foundry.outputs.chatDeployment
    embeddingDeployment: foundry.outputs.embeddingDeployment
    mcpAuthMode: mcpAuthMode
    jwtAudience: jwtAudience
    enableSemanticCache: enableSemanticCache
    redisName: enableSemanticCache ? 'redis-santa-${token}' : ''
    redisHostName: enableSemanticCache ? redis!.outputs.hostName : ''
  }
}

module roles 'modules/roles.bicep' = {
  scope: rg
  name: 'roles'
  params: {
    apimPrincipalId: apim.outputs.apimPrincipalId
    foundryAccountName: foundry.outputs.accountName
    contentSafetyName: contentSafety.outputs.name
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_TENANT_ID string = tenant().tenantId
output FUNCTION_APP_NAME string = functionApp.outputs.functionAppName
output FUNCTION_APP_HOSTNAME string = functionApp.outputs.functionAppHostName
output APIM_NAME string = apim.outputs.apimName
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
output APIM_MCP_NAUGHTY_NICE_URL string = apim.outputs.mcpNaughtyNiceUrl
output APIM_MCP_SLEIGH_URL string = apim.outputs.mcpSleighUrl
output APIM_MCP_EXISTING_URL string = apim.outputs.mcpExistingUrl
output APIM_MODEL_API_URL string = apim.outputs.modelApiUrl
output FOUNDRY_ACCOUNT_NAME string = foundry.outputs.accountName
output FOUNDRY_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
output FOUNDRY_PROJECT_PRINCIPAL_ID string = foundry.outputs.projectPrincipalId
output AGENT_MODEL string = foundry.outputs.chatDeployment
output ENABLE_SEMANTIC_CACHE bool = enableSemanticCache
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.appInsightsName
