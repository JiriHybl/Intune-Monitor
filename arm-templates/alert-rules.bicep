// ============================================================
// alert-rules.bicep — Azure Monitor Log Search Alert Rules
// Rules: Enrollment Success, Failure, Wipe, Retire, Reset
//
// IMPORTANT: OperationName values in KQL queries must be validated
// against your tenant data before production deployment.
// Run: IntuneAuditLogs | summarize count() by OperationName
// See: README.md § Post-Deployment Notes
// ============================================================

param location string
param logAnalyticsWorkspaceId string
param actionGroupResourceId string

// Evaluation frequency and window for all rules
var evaluationFrequency = 'PT5M'   // evaluate every 5 minutes
var windowSize          = 'PT5M'   // look back 5 minutes

// ── Rule 1: Enrollment Success ────────────────────────────────

resource alertEnrollmentSuccess 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'intune-enrollment-success'
  location: location
  tags: {
    solution: 'intune-monitor'
    event: 'enrollment-success'
  }
  properties: {
    displayName: 'Intune — Device Enrollment Success'
    description: 'Fires when a device successfully enrolls into Intune. Covers all platforms.'
    severity: 3
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [ logAnalyticsWorkspaceId ]
    criteria: {
      allOf: [
        {
          query: '''
IntuneOperationalLogs
| where TimeGenerated > ago(5m)
| where OperationName =~ "Enrollment"
| extend ParsedProperties = parse_json(Properties)
| where tostring(ParsedProperties.EnrollmentState) =~ "Enrolled"
| project
    TimeGenerated,
    DeviceName        = tostring(ParsedProperties.DeviceName),
    UserPrincipalName = tostring(ParsedProperties.UserPrincipalName),
    OS                = tostring(ParsedProperties.OS),
    EnrollmentType    = tostring(ParsedProperties.EnrollmentType)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [ actionGroupResourceId ]
      customProperties: {
        EventType: 'EnrollmentSuccess'
      }
    }
    autoMitigate: false
  }
}

// ── Rule 2: Enrollment Failure ────────────────────────────────

resource alertEnrollmentFailure 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'intune-enrollment-failure'
  location: location
  tags: {
    solution: 'intune-monitor'
    event: 'enrollment-failure'
  }
  properties: {
    displayName: 'Intune — Device Enrollment Failure'
    description: 'Fires when a device enrollment fails. Covers all platforms.'
    severity: 2
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [ logAnalyticsWorkspaceId ]
    criteria: {
      allOf: [
        {
          query: '''
IntuneOperationalLogs
| where TimeGenerated > ago(5m)
| where OperationName =~ "Enrollment"
| extend ParsedProperties = parse_json(Properties)
| where tostring(ParsedProperties.EnrollmentState) =~ "Failed"
| project
    TimeGenerated,
    DeviceName        = tostring(ParsedProperties.DeviceName),
    UserPrincipalName = tostring(ParsedProperties.UserPrincipalName),
    OS                = tostring(ParsedProperties.OS),
    FailureReason     = tostring(ParsedProperties.FailureReason)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [ actionGroupResourceId ]
      customProperties: {
        EventType: 'EnrollmentFailure'
      }
    }
    autoMitigate: false
  }
}

// ── Rule 3: Device Wipe ───────────────────────────────────────

resource alertDeviceWipe 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'intune-device-wipe'
  location: location
  tags: {
    solution: 'intune-monitor'
    event: 'device-wipe'
  }
  properties: {
    displayName: 'Intune — Device Wipe Initiated'
    description: 'Fires when a Wipe action is initiated on a device. High severity — immediate attention required.'
    severity: 1
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [ logAnalyticsWorkspaceId ]
    criteria: {
      allOf: [
        {
          query: '''
IntuneAuditLogs
| where TimeGenerated > ago(5m)
| where OperationName =~ "DeviceAction_wipe"
| project
    TimeGenerated,
    DeviceName  = tostring(TargetDisplayNames[0]),
    InitiatedBy = ActorUPN,
    Result      = ActivityResultType,
    Category
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [ actionGroupResourceId ]
      customProperties: {
        EventType: 'DeviceWipe'
      }
    }
    autoMitigate: false
  }
}

// ── Rule 4: Device Retire ─────────────────────────────────────

resource alertDeviceRetire 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'intune-device-retire'
  location: location
  tags: {
    solution: 'intune-monitor'
    event: 'device-retire'
  }
  properties: {
    displayName: 'Intune — Device Retire Initiated'
    description: 'Fires when a Retire action is initiated on a device. Corporate data will be removed.'
    severity: 1
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [ logAnalyticsWorkspaceId ]
    criteria: {
      allOf: [
        {
          query: '''
IntuneAuditLogs
| where TimeGenerated > ago(5m)
| where OperationName =~ "DeviceAction_retire"
| project
    TimeGenerated,
    DeviceName  = tostring(TargetDisplayNames[0]),
    InitiatedBy = ActorUPN,
    Result      = ActivityResultType,
    Category
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [ actionGroupResourceId ]
      customProperties: {
        EventType: 'DeviceRetire'
      }
    }
    autoMitigate: false
  }
}

// ── Rule 5: Fresh Start / Autopilot Reset ─────────────────────

resource alertDeviceReset 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'intune-device-reset'
  location: location
  tags: {
    solution: 'intune-monitor'
    event: 'device-reset'
  }
  properties: {
    displayName: 'Intune — Device Fresh Start or Autopilot Reset'
    description: 'Fires when Fresh Start or Autopilot Reset is initiated on a device.'
    severity: 2
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [ logAnalyticsWorkspaceId ]
    criteria: {
      allOf: [
        {
          query: '''
IntuneAuditLogs
| where TimeGenerated > ago(5m)
| where OperationName in~ (
    "DeviceAction_freshStart",
    "DeviceAction_autopilotReset",
    "DeviceAction_resetPasscode"
  )
| project
    TimeGenerated,
    Action      = OperationName,
    DeviceName  = tostring(TargetDisplayNames[0]),
    InitiatedBy = ActorUPN,
    Result      = ActivityResultType
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [ actionGroupResourceId ]
      customProperties: {
        EventType: 'DeviceReset'
      }
    }
    autoMitigate: false
  }
}

// ── Outputs ───────────────────────────────────────────────────

output alertRuleIds array = [
  alertEnrollmentSuccess.id
  alertEnrollmentFailure.id
  alertDeviceWipe.id
  alertDeviceRetire.id
  alertDeviceReset.id
]
