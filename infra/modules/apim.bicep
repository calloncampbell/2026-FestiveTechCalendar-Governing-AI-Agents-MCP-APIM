targetScope = 'resourceGroup'

// API Management (Standard v2): Santa Workshop APIs, MCP servers, model API, products, policies.
// MCP servers: https://learn.microsoft.com/azure/api-management/export-rest-mcp-server
//              https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server
param location string
param tags object = {}
param apimName string
param publisherEmail string
param publisherName string
param appInsightsId string
param appInsightsConnectionString string
param functionAppHostName string
param foundryOpenAiEndpoint string
param contentSafetyEndpoint string
param chatDeployment string
param embeddingDeployment string = ''

@description('Primary: validate-jwt with the Foundry project managed identity. Fallback: APIM subscription key.')
@allowed(['jwt', 'key'])
param mcpAuthMode string = 'jwt'
@description('App ID URI (audience) of the Entra app registration that represents the Santa MCP gateway.')
param jwtAudience string = 'api://santa-workshop-mcp'
param jwtRequiredRole string = 'Workshop.Invoke'

param enableSemanticCache bool = false
param redisName string = ''
param redisHostName string = ''

var keyMode = mcpAuthMode == 'key'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// ---------- Telemetry ----------
resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appInsightsId
    credentials: {
      connectionString: appInsightsConnectionString
    }
  }
}

// Frontend/backend payload bytes MUST be 0: logging MCP response bodies buffers the stream and breaks MCP.
resource diagnostics 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    sampling: { samplingType: 'fixed', percentage: 100 }
    verbosity: 'information'
    logClientIp: true
    httpCorrelationProtocol: 'W3C'
    frontend: {
      request: { body: { bytes: 0 } }
      response: { body: { bytes: 0 } }
    }
    backend: {
      request: { body: { bytes: 0 } }
      response: { body: { bytes: 0 } }
    }
    metrics: true
  }
}

// ---------- Named values ----------
resource nvTenant 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'tenantId'
  properties: { displayName: 'tenantId', value: tenant().tenantId }
}

resource nvAudience 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'jwtAudience'
  properties: { displayName: 'jwtAudience', value: jwtAudience }
}

resource nvRole 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'jwtRequiredRole'
  properties: { displayName: 'jwtRequiredRole', value: jwtRequiredRole }
}

// Secrets are NOT in the repo. Placeholders are replaced by scripts/set-function-keys.ps1 (azd postdeploy).
resource nvFunctionKey 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'functionKey'
  properties: { displayName: 'functionKey', secret: true, value: 'set-by-postdeploy' }
}

resource nvMcpKey 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'mcpExtensionKey'
  properties: { displayName: 'mcpExtensionKey', secret: true, value: 'set-by-postdeploy' }
}

// ---------- Backends ----------
resource functionsBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'santa-functions-backend'
  properties: {
    protocol: 'http'
    url: 'https://${functionAppHostName}/api'
  }
}

resource foundryBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'foundry-backend'
  properties: {
    protocol: 'http'
    url: '${foundryOpenAiEndpoint}/openai'
  }
}

resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'content-safety-backend'
  properties: {
    protocol: 'http'
    url: contentSafetyEndpoint
    credentials: {
      // Accepted by the service (portal "Managed identity" auth) but missing from the published type definition.
      #disable-next-line BCP037
      managedIdentity: {
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

// Semantic cache plumbing, emitted only when enabled.
resource embeddingsBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = if (enableSemanticCache) {
  parent: apim
  name: 'embeddings-backend'
  properties: {
    protocol: 'http'
    url: '${foundryOpenAiEndpoint}/openai/deployments/${embeddingDeployment}/embeddings'
  }
}

resource redisDb 'Microsoft.Cache/redisEnterprise/databases@2025-04-01' existing = if (enableSemanticCache) {
  name: '${redisName}/default'
}

resource externalCache 'Microsoft.ApiManagement/service/caches@2024-05-01' = if (enableSemanticCache) {
  parent: apim
  name: 'default'
  properties: {
    useFromLocation: 'default'
    connectionString: '${redisHostName}:10000,password=${redisDb!.listKeys().primaryKey},ssl=True,abortConnect=False'
    description: 'Azure Managed Redis (RediSearch) for llm-semantic-cache'
  }
}

// ---------- Policy fragments (invariant base) ----------
resource fragAuth 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'santa-auth'
  dependsOn: [ nvTenant, nvAudience, nvRole ]
  properties: {
    format: 'rawxml'
    value: keyMode ? loadTextContent('../apim/policies/fragments/auth-key.xml') : loadTextContent('../apim/policies/fragments/auth-jwt.xml')
  }
}

resource fragMcpBase 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'santa-mcp-base'
  dependsOn: [ fragAuth, functionsBackend ]
  properties: {
    format: 'rawxml'
    value: loadTextContent('../apim/policies/fragments/mcp-base.xml')
  }
}

resource fragModelBase 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: apim
  name: 'santa-model-base'
  dependsOn: [ foundryBackend ]
  properties: {
    format: 'rawxml'
    value: loadTextContent('../apim/policies/fragments/model-base.xml')
  }
}

// ---------- Source REST APIs (imported from OpenAPI) ----------
resource naughtyNiceApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'santa-naughty-nice'
  properties: {
    displayName: 'Naughty or Nice API'
    path: 'naughty-nice'
    protocols: [ 'https' ]
    format: 'openapi'
    value: loadTextContent('../../openapi/naughty-nice.yaml')
    serviceUrl: 'https://${functionAppHostName}/api'
    subscriptionRequired: keyMode
  }
}

resource sleighApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'santa-sleigh'
  properties: {
    displayName: 'Sleigh Logistics API'
    path: 'sleigh-logistics'
    protocols: [ 'https' ]
    format: 'openapi'
    value: loadTextContent('../../openapi/sleigh-logistics.yaml')
    serviceUrl: 'https://${functionAppHostName}/api'
    subscriptionRequired: keyMode
  }
}

var mcpBaselinePolicy = replace(loadTextContent('../apim/policies/mcp-baseline.xml'), '__KEY_NV__', 'functionKey')
var mcpExistingBaselinePolicy = replace(loadTextContent('../apim/policies/mcp-baseline.xml'), '__KEY_NV__', 'mcpExtensionKey')

resource naughtyNicePolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: naughtyNiceApi
  name: 'policy'
  dependsOn: [ fragMcpBase, nvFunctionKey ]
  properties: { format: 'rawxml', value: mcpBaselinePolicy }
}

resource sleighPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: sleighApi
  name: 'policy'
  dependsOn: [ fragMcpBase, nvFunctionKey ]
  properties: { format: 'rawxml', value: mcpBaselinePolicy }
}

// ---------- MCP server 1 & 2: REST API exported as MCP (operationId => tool name) ----------
resource naughtyNiceMcp 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'santa-naughty-nice-mcp'
  dependsOn: [ naughtyNiceApi ]
  properties: {
    displayName: 'Naughty or Nice MCP'
    description: 'Look up whether a child is on the nice list and submit list reviews.'
    type: 'mcp'
    path: 'naughty-nice-mcp'
    protocols: [ 'https' ]
    subscriptionRequired: keyMode
  }
}

var naughtyNiceTools = [
  { name: 'getKidByName', description: 'Look up a child by exact full name and return their naughty/nice status, score and region.' }
  { name: 'listKids', description: 'List children, optionally filtered by status. Paged: pageSize is capped at 50.' }
  { name: 'submitReview', description: 'WRITE: submit a list review for a child (simulated). Naughty children cannot be promoted to Nice.' }
]

resource naughtyNiceTool 'Microsoft.ApiManagement/service/apis/tools@2025-09-01-preview' = [for t in naughtyNiceTools: {
  parent: naughtyNiceMcp
  name: t.name
  dependsOn: [ naughtyNiceApi ]
  properties: {
    displayName: t.name
    description: t.description
    operationId: '/apis/santa-naughty-nice/operations/${t.name}'
  }
}]

resource sleighMcp 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'santa-sleigh-mcp'
  dependsOn: [ sleighApi ]
  properties: {
    displayName: 'Sleigh Logistics MCP'
    description: 'List delivery slots and schedule gift deliveries.'
    type: 'mcp'
    path: 'sleigh-mcp'
    protocols: [ 'https' ]
    subscriptionRequired: keyMode
  }
}

var sleighTools = [
  { name: 'listSlots', description: 'List sleigh delivery slots, optionally by region.' }
  { name: 'scheduleDelivery', description: 'WRITE: schedule a gift delivery for a nice-list child in a slot (simulated).' }
  { name: 'getDelivery', description: 'Get a scheduled delivery by id.' }
]

resource sleighTool 'Microsoft.ApiManagement/service/apis/tools@2025-09-01-preview' = [for t in sleighTools: {
  parent: sleighMcp
  name: t.name
  dependsOn: [ sleighApi ]
  properties: {
    displayName: t.name
    description: t.description
    operationId: '/apis/santa-sleigh/operations/${t.name}'
  }
}]

resource naughtyNiceMcpPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: naughtyNiceMcp
  name: 'policy'
  dependsOn: [ fragMcpBase, nvFunctionKey ]
  properties: { format: 'rawxml', value: mcpBaselinePolicy }
}

resource sleighMcpPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: sleighMcp
  name: 'policy'
  dependsOn: [ fragMcpBase, nvFunctionKey ]
  properties: { format: 'rawxml', value: mcpBaselinePolicy }
}

// ---------- MCP server 3: existing MCP server (the Function's native MCP extension endpoint) ----------
resource existingMcp 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'santa-existing-mcp'
  properties: {
    displayName: 'Santa Workshop (existing MCP server)'
    description: 'Native Functions MCP endpoint fronted by API Management.'
    type: 'mcp'
    path: 'santa-existing-mcp'
    protocols: [ 'https' ]
    serviceUrl: 'https://${functionAppHostName}/runtime/webhooks'
    subscriptionRequired: keyMode
    mcpProperties: {
      transportType: 'streamable'
      endpoints: [
        { name: 'mcp', uriTemplate: '/mcp' }
      ]
    }
  }
}

resource existingMcpPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: existingMcp
  name: 'policy'
  dependsOn: [ fragMcpBase, nvMcpKey ]
  properties: { format: 'rawxml', value: mcpExistingBaselinePolicy }
}

// ---------- Model API (Foundry via APIM) ----------
resource modelApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'santa-model'
  properties: {
    displayName: 'Santa Model API (Foundry)'
    description: 'Azure OpenAI-compatible chat completions and embeddings, governed by LLM policies.'
    path: 'santa-model'
    protocols: [ 'https' ]
    serviceUrl: '${foundryOpenAiEndpoint}/openai'
    subscriptionRequired: true
    subscriptionKeyParameterNames: { header: 'api-key', query: 'subscription-key' }
  }
}

resource chatOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: modelApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [ { name: 'deployment-id', required: true, type: 'string' } ]
  }
}

resource embedOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: modelApi
  name: 'embeddings'
  properties: {
    displayName: 'Embeddings'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/embeddings'
    templateParameters: [ { name: 'deployment-id', required: true, type: 'string' } ]
  }
}

resource modelPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: modelApi
  name: 'policy'
  dependsOn: [ fragModelBase, chatOp, embedOp ]
  properties: { format: 'rawxml', value: loadTextContent('../apim/policies/model-baseline.xml') }
}

// ---------- Product + subscription for the elf agent ----------
resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: 'santa-elves'
  properties: {
    displayName: 'Santa Elves'
    description: 'Elf agents: Santa MCP servers and the governed model API.'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productModel 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: modelApi.name
}

resource productNaughty 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: naughtyNiceMcp.name
}

resource productSleigh 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: sleighMcp.name
}

resource productExisting 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: existingMcp.name
}

resource elfSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'elf-agent'
  dependsOn: [ productModel, productNaughty, productSleigh, productExisting ]
  properties: {
    displayName: 'Elf agent'
    scope: product.id
    state: 'active'
  }
}

output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId
output chatDeploymentName string = chatDeployment
output mcpNaughtyNiceUrl string = '${apim.properties.gatewayUrl}/naughty-nice-mcp/mcp'
output mcpSleighUrl string = '${apim.properties.gatewayUrl}/sleigh-mcp/mcp'
output mcpExistingUrl string = '${apim.properties.gatewayUrl}/santa-existing-mcp/mcp'
output modelApiUrl string = '${apim.properties.gatewayUrl}/santa-model'
