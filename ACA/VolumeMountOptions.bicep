param location string = resourceGroup().location

param deploymentName string = 'flytzen-mealie'

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: '${replace(deploymentName, '-','')}sa'
  location: location
  sku: {
    name: 'Standard_GRS'
  }
  kind: 'StorageV2'

  resource fileShareService 'fileServices' = {
    name: 'default'
    resource fileShare 'shares' = {
      name: '${deploymentName}-fs'
    }
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${deploymentName}-la'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource acaenvironment 'Microsoft.App/managedEnvironments@2022-06-01-preview' = {
  name: '${deploymentName}-cae'
  location: location
  sku:{
    name: 'Consumption'
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }

    }
  }
  resource sharedFiles 'storages@2022-06-01-preview' = {
    name: '${deploymentName}mount'
    properties: {
      azureFile: {
        accountName: storageAccount.name
        accountKey: storageAccount.listKeys().keys[0].value
        accessMode: 'ReadWrite'
        shareName: storageAccount::fileShareService::fileShare.name
      }
    }
  }
}

resource apicontainer 'Microsoft.App/containerApps@2023-04-01-preview' = {
  location: location
  name: '${deploymentName}-api-aca'
  properties: {
    managedEnvironmentId: acaenvironment.id
    configuration: {
      ingress: {
        external: false
        targetPort: 9000
        allowInsecure: true
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      // revisionSuffix: 'firstrevision'
      containers: [
        {
           name: 'mealie-api'
           image: 'hkotel/mealie:api-v1.0.0beta-5'
           volumeMounts: [
            {
              mountPath:'/app/data'
              volumeName: 'api-volume'
            }
          ]
          resources:{
            memory: '1Gi'
            cpu: json('0.5')
          }
          env: [
            {
              name: 'ALLOW_SIGNUP'
              value: 'true'
            }
            {
              name: 'PUID'
              value: '1000'
            }
            {
              name:'PGID'
              value:'1000'
            }
            {
              name:'TZ'
              value: 'Europe/London'
            }
            {
              name:'MAX_WORKERS'
              value:'1'
            }
            {
              name:'WEB_CONCURRENCY'
              value:'1'
            }
            {
              name:'BASE_URL'
              value: 'https://${deploymentName}-aca.${acaenvironment.properties.defaultDomain}'
            }
          ]
        }
      ]
      volumes:[
        {
          name:'api-volume'
          storageType:'AzureFile'
          storageName:acaenvironment::sharedFiles.name
          mountOptions: 'uid=1000,gid=1000,nobrl,mfsymlinks,cache=none'
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }

  }
} 

resource frontendcontainer 'Microsoft.App/containerApps@2022-06-01-preview' = {
  location: location
  name: '${deploymentName}-frontend-aca'
  properties: {
    managedEnvironmentId: acaenvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3001
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      // revisionSuffix: 'firstrevision'
      containers: [
        {
          name: 'mealie-frontend'
          image: 'hkotel/mealie:frontend-v1.0.0beta-5'
          env: [
            {
              name: 'API_URL'
              value: 'https://${deploymentName}-api-aca.internal.${acaenvironment.properties.defaultDomain}'
            }
          ]
          volumeMounts: [
            {
              mountPath:'/app/data'
              volumeName: 'frontend-volume'
            }
          ]
        }
      ]
      volumes:[
        {
          name:'frontend-volume'
          storageType:'AzureFile'
          storageName:acaenvironment::sharedFiles.name
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}
