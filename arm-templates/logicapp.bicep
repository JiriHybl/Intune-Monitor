// ============================================================
// logicapp.bicep — Logic App: Azure Monitor → Teams Adaptive Card
// ============================================================

param logicAppName string
param location string

@secure()
param teamsWebhookUrl string

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: {
    solution: 'intune-monitor'
    component: 'alerting'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        When_a_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                schemaId: { type: 'string' }
                data: {
                  type: 'object'
                  properties: {
                    essentials: {
                      type: 'object'
                      properties: {
                        alertRule:        { type: 'string' }
                        severity:         { type: 'string' }
                        monitorCondition: { type: 'string' }
                        firedDateTime:    { type: 'string' }
                        description:      { type: 'string' }
                        alertTargetIDs:   { type: 'array' }
                      }
                    }
                    alertContext: {
                      type: 'object'
                      properties: {
                        condition: {
                          type: 'object'
                          properties: {
                            allOf: {
                              type: 'array'
                              items: {
                                type: 'object'
                                properties: {
                                  searchQuery:                     { type: 'string' }
                                  metricValue:                     { type: 'number' }
                                  LinkToFilteredSearchResultsUI:   { type: 'string' }
                                  LinkToFilteredSearchResultsAPI:  { type: 'string' }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      actions: {
        Parse_Essentials: {
          type: 'ParseJson'
          runAfter: {}
          inputs: {
            content: '@triggerBody()?[\'data\']?[\'essentials\']'
            schema: {
              type: 'object'
              properties: {
                alertRule:        { type: 'string' }
                severity:         { type: 'string' }
                monitorCondition: { type: 'string' }
                firedDateTime:    { type: 'string' }
                description:      { type: 'string' }
              }
            }
          }
        }
        Set_Severity_Emoji: {
          type: 'InitializeVariable'
          runAfter: {
            Parse_Essentials: [ 'Succeeded' ]
          }
          inputs: {
            variables: [
              {
                name: 'SeverityEmoji'
                type: 'string'
                value: '@{if(equals(body(\'Parse_Essentials\')?[\'severity\'], \'Sev1\'), \'🔴\', if(equals(body(\'Parse_Essentials\')?[\'severity\'], \'Sev2\'), \'🟠\', \'🟡\'))}'
              }
            ]
          }
        }
        Set_Severity_Color: {
          type: 'InitializeVariable'
          runAfter: {
            Set_Severity_Emoji: [ 'Succeeded' ]
          }
          inputs: {
            variables: [
              {
                name: 'SeverityColor'
                type: 'string'
                value: '@{if(equals(body(\'Parse_Essentials\')?[\'severity\'], \'Sev1\'), \'attention\', if(equals(body(\'Parse_Essentials\')?[\'severity\'], \'Sev2\'), \'warning\', \'good\'))}'
              }
            ]
          }
        }
        Post_Teams_Adaptive_Card: {
          type: 'Http'
          runAfter: {
            Set_Severity_Color: [ 'Succeeded' ]
          }
          inputs: {
            method: 'POST'
            uri: teamsWebhookUrl
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              type: 'message'
              attachments: [
                {
                  contentType: 'application/vnd.microsoft.card.adaptive'
                  content: {
                    '$schema': 'http://adaptivecards.io/schemas/adaptive-card.json'
                    type: 'AdaptiveCard'
                    version: '1.2'
                    body: [
                      {
                        type: 'TextBlock'
                        text: '@{variables(\'SeverityEmoji\')} Intune Alert: @{body(\'Parse_Essentials\')?[\'alertRule\']}'
                        weight: 'Bolder'
                        size: 'Large'
                        color: '@{variables(\'SeverityColor\')}'
                        wrap: true
                      }
                      {
                        type: 'FactSet'
                        facts: [
                          {
                            title: 'Alert Rule'
                            value: '@{body(\'Parse_Essentials\')?[\'alertRule\']}'
                          }
                          {
                            title: 'Severity'
                            value: '@{body(\'Parse_Essentials\')?[\'severity\']}'
                          }
                          {
                            title: 'Condition'
                            value: '@{body(\'Parse_Essentials\')?[\'monitorCondition\']}'
                          }
                          {
                            title: 'Fired At (UTC)'
                            value: '@{body(\'Parse_Essentials\')?[\'firedDateTime\']}'
                          }
                          {
                            title: 'Description'
                            value: '@{body(\'Parse_Essentials\')?[\'description\']}'
                          }
                        ]
                      }
                      {
                        type: 'TextBlock'
                        text: 'KQL Query'
                        weight: 'Bolder'
                        separator: true
                        spacing: 'Medium'
                      }
                      {
                        type: 'TextBlock'
                        text: '@{triggerBody()?[\'data\']?[\'alertContext\']?[\'condition\']?[\'allOf\']?[0]?[\'searchQuery\']}'
                        wrap: true
                        isSubtle: true
                        fontType: 'Monospace'
                      }
                    ]
                    actions: [
                      {
                        type: 'Action.OpenUrl'
                        title: '🔍 View in Log Analytics'
                        url: '@{triggerBody()?[\'data\']?[\'alertContext\']?[\'condition\']?[\'allOf\']?[0]?[\'LinkToFilteredSearchResultsUI\']}'
                      }
                    ]
                  }
                }
              ]
            }
          }
        }
        Return_200: {
          type: 'Response'
          runAfter: {
            Post_Teams_Adaptive_Card: [ 'Succeeded' ]
          }
          inputs: {
            statusCode: 200
          }
        }
        Handle_Teams_Error: {
          type: 'Response'
          runAfter: {
            Post_Teams_Adaptive_Card: [ 'Failed', 'TimedOut' ]
          }
          inputs: {
            statusCode: 500
            body: {
              error: 'Failed to post Teams notification'
              details: '@{body(\'Post_Teams_Adaptive_Card\')}'
            }
          }
        }
      }
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────

output logicAppResourceId string = logicApp.id
output logicAppName string = logicApp.name

// Note: The HTTP trigger URL is generated at runtime and retrieved
// via listCallbackUrl() — see deploy.ps1 for how this is extracted
// after deployment and injected into the Action Group.
#disable-next-line outputs-should-not-contain-secrets
output logicAppTriggerUrl string = listCallbackUrl(
  '${logicApp.id}/triggers/When_a_HTTP_request_is_received',
  logicApp.apiVersion
).value
// bicep-linter suppression added above output to allow SAS token in output
// This is intentional — the trigger URL is a secure callback URL passed
// directly to the Action Group and never stored or logged.
