// ============================================================
// actiongroup.bicep — Azure Monitor Action Group
// Targets: Logic App (Teams) + Email
// ============================================================

param actionGroupName string
param actionGroupShortName string
param alertEmailAddress string
param logicAppResourceId string

@secure()
param logicAppCallbackUrl string

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: {
    solution: 'intune-monitor'
    component: 'alerting'
  }
  properties: {
    groupShortName: actionGroupShortName
    enabled: true

    emailReceivers: [
      {
        name: 'IntunAdminEmail'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]

    logicAppReceivers: [
      {
        name: 'IntuneAlertsTeams'
        resourceId: logicAppResourceId
        callbackUrl: logicAppCallbackUrl
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────

output actionGroupResourceId string = actionGroup.id
output actionGroupName string = actionGroup.name
