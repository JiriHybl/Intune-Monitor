// ============================================================
// main.bicep — Intune Monitor Solution
// Orchestrates: Logic App, Action Group, Alert Rules
// ============================================================

targetScope = 'resourceGroup'

// ── Parameters ──────────────────────────────────────────────

@description('Resource ID of the existing Log Analytics Workspace')
param logAnalyticsWorkspaceResourceId string

@description('Teams Incoming Webhook URL for alert notifications')
@secure()
param teamsWebhookUrl string

@description('Email address for alert notifications')
param alertEmailAddress string

@description('Azure region for all deployed resources')
param location string = resourceGroup().location

@description('Name for the Logic App resource')
param logicAppName string = 'la-intune-alerts'

@description('Name for the Action Group resource')
param actionGroupName string = 'ag-intune-admins'

@description('Short name for the Action Group (max 12 chars)')
param actionGroupShortName string = 'IntuneAdmin'

// ── Modules ──────────────────────────────────────────────────

module logicApp 'logicapp.bicep' = {
  name: 'deploy-logicapp'
  params: {
    logicAppName: logicAppName
    location: location
    teamsWebhookUrl: teamsWebhookUrl
  }
}

module actionGroup 'actiongroup.bicep' = {
  name: 'deploy-actiongroup'
  params: {
    actionGroupName: actionGroupName
    actionGroupShortName: actionGroupShortName
    alertEmailAddress: alertEmailAddress
    logicAppResourceId: logicApp.outputs.logicAppResourceId
    logicAppCallbackUrl: logicApp.outputs.logicAppTriggerUrl
  }
}

module alertRules 'alert-rules.bicep' = {
  name: 'deploy-alert-rules'
  params: {
    location: location
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: actionGroup.outputs.actionGroupResourceId
  }
}

// ── Outputs ───────────────────────────────────────────────────

output logicAppName string = logicApp.outputs.logicAppName
output logicAppTriggerUrl string = logicApp.outputs.logicAppTriggerUrl
output actionGroupResourceId string = actionGroup.outputs.actionGroupResourceId
