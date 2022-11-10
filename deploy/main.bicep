@description('The location to deploy our resources to. Default is location of resource group')
param location string = resourceGroup().location

@description('The name of the Azure Container Registry')
param containerRegistryName string = 'acr${uniqueString(resourceGroup().id)}'

@description('The name of the Log Analytics workspace to deploy')
param logAnalyticsWorkspaceName string = 'law${uniqueString(resourceGroup().id)}'

@description('The name of the App Insights workspace')
param appInsightsName string = 'appins${uniqueString(resourceGroup().id)}'

@description('The name of the Container App Environment')
param containerEnvironmentName string = 'env${uniqueString(resourceGroup().id)}'

@description('The name of the Service Bus namespace')
param serviceBusName string = 'sb${uniqueString(resourceGroup().id)}'

@description('The image name of the checkout service')
param checkoutImage string

@description('The image name of the order processor service')
param orderProcessorImage string

var checkoutName = 'checkout'
var orderProcessorName = 'orderprocessor'

var tags = {
  DemoName: 'ACA-Dapr-Pub-Sub-Demo'
  Language: 'C#'
  Environment: 'Production'
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
   retentionInDays: 30
   features: {
    searchVersion: 1
   }
   sku: {
    name: 'PerGB2018'
   } 
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' existing = {
  name: containerRegistryName
}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: serviceBusName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource serviceBusAuthRules 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-01-01-preview' existing = {
  name: 'RootManageSharedAccessKey'
  parent: serviceBus
}

resource env 'Microsoft.App/managedEnvironments@2022-06-01-preview' = {
  name: containerEnvironmentName
  location: location
  tags: tags
  properties: {
   daprAIConnectionString: appInsights.properties.ConnectionString
   daprAIInstrumentationKey: appInsights.properties.InstrumentationKey
   appLogsConfiguration: {
    destination: 'log-analytics'
    logAnalyticsConfiguration: {
      customerId: logAnalytics.properties.customerId
      sharedKey: logAnalytics.listKeys().primarySharedKey
    }
   } 
  }
}

resource daprComponent 'Microsoft.App/managedEnvironments/daprComponents@2022-06-01-preview' = {
  name: 'acadaprpubsub'
  parent: env
  properties: {
   componentType: 'pubsub.azure.servicebus' 
   version: 'v1'
   secrets: [
    {
      name: 'service-bus-connection-string'
      value: serviceBusAuthRules.listKeys().primaryConnectionString
    }
   ]
   metadata: [
    {
      name: 'connectionString'
      secretRef: 'service-bus-connection-string'
    }
   ]
   scopes: [
    'checkout'
    'orderprocessor'
   ]
  }
}

resource checkout 'Microsoft.App/containerApps@2022-06-01-preview' = {
  name: checkoutName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Multiple'
      ingress: {
        external: false
        transport: 'http'
        targetPort: 80
        allowInsecure: true
      }
      dapr: {
        enabled: true
        appPort: 80
        appId: checkoutName
        enableApiLogging: true
      }
      secrets: [
        {
          name: 'container-registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: '${containerRegistry.name}.azurecr.io'
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'container-registry-password'
        }
      ]
    }
    template: {
      containers: [
        {
          image: checkoutImage
          name: checkoutName
          env: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Development'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 5
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource orderProcessor 'Microsoft.App/containerApps@2022-06-01-preview' = {
  name: orderProcessorName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Multiple'
      ingress: {
        external: false
        transport: 'http'
        targetPort: 80
        allowInsecure: false
      }
      dapr: {
        enabled: true
        appPort: 80
        appId: orderProcessorName
        enableApiLogging: true
      }
      secrets: [
        {
          name: 'container-registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: '${containerRegistry.name}.azurecr.io'
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'container-registry-password'
        }
      ]
    }
    template: {
      containers: [
        {
          image: orderProcessorImage
          name: orderProcessorName
          env: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Development'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 5
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}
