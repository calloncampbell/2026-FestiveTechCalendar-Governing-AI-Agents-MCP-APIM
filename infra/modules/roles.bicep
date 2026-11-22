targetScope = 'resourceGroup'

// APIM managed identity -> Foundry (chat/embeddings) and Content Safety.
param apimPrincipalId string
param foundryAccountName string
param contentSafetyName string

var cognitiveServicesUser = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var cognitiveServicesOpenAIUser = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource contentSafety 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: contentSafetyName
}

resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, apimPrincipalId, cognitiveServicesUser)
  scope: foundry
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUser)
  }
}

resource foundryOpenAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, apimPrincipalId, cognitiveServicesOpenAIUser)
  scope: foundry
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUser)
  }
}

resource contentSafetyUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(contentSafety.id, apimPrincipalId, cognitiveServicesUser)
  scope: contentSafety
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUser)
  }
}
