targetScope = 'resourceGroup'

// Azure Managed Redis with RediSearch, only deployed when enableSemanticCache = true.
// https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching
param location string
param tags object = {}
param name string

resource redis 'Microsoft.Cache/redisEnterprise@2025-04-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: 'Balanced_B0' }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

resource db 'Microsoft.Cache/redisEnterprise/databases@2025-04-01' = {
  parent: redis
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    port: 10000
    clusteringPolicy: 'EnterpriseCluster' // required for RediSearch
    evictionPolicy: 'NoEviction' // required for RediSearch
    accessKeysAuthentication: 'Enabled' // APIM external cache registration uses a connection string
    modules: [
      { name: 'RediSearch' }
    ]
  }
}

output hostName string = redis.properties.hostName
output redisId string = redis.id
output databaseId string = db.id
