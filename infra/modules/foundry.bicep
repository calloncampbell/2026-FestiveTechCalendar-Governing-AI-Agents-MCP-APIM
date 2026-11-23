targetScope = 'resourceGroup'

// Foundry resource (AIServices) + project + chat model + embeddings model.
// https://learn.microsoft.com/azure/foundry/how-to/create-resource-template
param location string
param tags object = {}
param accountName string
param projectName string
param chatModelName string = 'gpt-4.1-mini'
param chatModelVersion string = '2025-04-14'
param chatCapacity int = 50
param embeddingModelName string = 'text-embedding-3-small'
param embeddingModelVersion string = '1'
param embeddingCapacity int = 50
param deployEmbeddings bool = false

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: accountName
    allowProjectManagement: true
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'Santa Workshop'
    description: 'Elf agent project for the Governing AI Agents with MCP + APIM demo'
  }
}

resource chat 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: chatModelName
  sku: {
    name: 'GlobalStandard'
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
  }
}

// Serialized after the chat deployment: Cognitive Services rejects parallel deployment writes.
resource embeddings 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployEmbeddings) {
  parent: account
  name: embeddingModelName
  dependsOn: [ chat ]
  sku: {
    name: 'Standard'
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
  }
}

output accountName string = account.name
output accountId string = account.id
output endpoint string = account.properties.endpoint
output openAiEndpoint string = 'https://${account.name}.openai.azure.com'
output projectName string = project.name
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output projectPrincipalId string = project.identity.principalId
output chatDeployment string = chat.name
output embeddingDeployment string = deployEmbeddings ? embeddings.name : ''
