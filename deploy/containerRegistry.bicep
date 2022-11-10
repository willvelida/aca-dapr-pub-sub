@description('The name of the Azure Container Registry')
param containerRegistryName string = 'acr${uniqueString(resourceGroup().id)}'

@description('The location to deploy our resources to. Default is location of resource group')
param location string = resourceGroup().location

var tags = {
  DemoName: 'ACA-Dapr-Pub-Sub-Demo'
  Language: 'C#'
  Environment: 'Production'
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}
