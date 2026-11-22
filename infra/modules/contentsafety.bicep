targetScope = 'resourceGroup'

// Azure AI Content Safety, used by llm-content-safety (Prompt Shields). Entra auth only.
param location string
param tags object = {}
param name string

resource contentSafety 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'ContentSafety'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

output name string = contentSafety.name
output id string = contentSafety.id
// llm-content-safety requires the https://<name>.cognitiveservices.azure.com form
output endpoint string = 'https://${contentSafety.name}.cognitiveservices.azure.com'
