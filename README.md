# Intune Monitor — Azure Monitor Alerting Solution

Automated alerting for Microsoft Intune events using Azure Monitor, Log Analytics, and Logic Apps with Teams and email notifications.

## What This Solution Deploys

| Component | Purpose |
|---|---|
| **Diagnostic Settings** | Streams Intune logs to Log Analytics |
| **Log Analytics Workspace** | (existing) Stores and queries Intune logs |
| **5 Alert Rules** | Per-event detection for enrollment, wipe, retire, reset |
| **Logic App** | Transforms Azure Monitor payload into Teams Adaptive Card |
| **Action Group** | Routes alerts to Logic App + email |

### Monitored Events

| Event | Log Table | Severity |
|---|---|---|
| Enrollment Success | `IntuneOperationalLogs` | Sev3 |
| Enrollment Failure | `IntuneOperationalLogs` | Sev2 |
| Device Wipe | `IntuneAuditLogs` | Sev1 |
| Device Retire | `IntuneAuditLogs` | Sev1 |
| Fresh Start / Autopilot Reset | `IntuneAuditLogs` | Sev2 |

---

## Prerequisites

| Requirement | Details |
|---|---|
| Windows workstation | Windows 10/11 or Windows Server 2019+ |
| PowerShell 5.1 or PowerShell 7+ | PowerShell 7 recommended — [Install](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) |
| Azure CLI ≥ 2.50 | [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows) — includes Bicep |
| Az PowerShell module | `Install-Module Az -Scope CurrentUser` |
| Azure subscription | Contributor or Owner role |
| Microsoft 365 E5 license | Required for Intune Diagnostic Settings |
| Existing Log Analytics Workspace | Resource ID required during deployment |
| Intune Administrator or Global Admin role | To configure Diagnostic Settings |
| Teams channel | For webhook configuration |

> **Note:** All scripts, README commands, and the CI/CD pipeline use **PowerShell syntax exclusively**. No bash, WSL, or Linux tooling is required.

---

## Repository Structure

```
intune-monitor/
├── README.md                          # This file — full deployment guide
├── CHANGELOG.md                       # Version history
├── .github/
│   └── workflows/
│       └── deploy.yml                 # Optional: CI/CD pipeline
├── arm-templates/
│   ├── main.bicep                     # Main orchestration template
│   ├── logicapp.bicep                 # Logic App definition
│   ├── actiongroup.bicep              # Action Group definition
│   ├── alert-rules.bicep              # All 5 alert rules
│   └── parameters/
│       ├── parameters.example.json    # Parameter file template
│       └── parameters.json            # Your parameters (gitignored)
├── alert-rules/
│   ├── kql-enrollment-success.kql
│   ├── kql-enrollment-failure.kql
│   ├── kql-device-wipe.kql
│   ├── kql-device-retire.kql
│   └── kql-device-reset.kql
├── scripts/
│   ├── deploy.ps1                     # PowerShell deployment script
│   ├── configure-diagnostic-settings.ps1
│   └── validate-data-flow.ps1
└── docs/
    ├── architecture.md
    └── troubleshooting.md
```

---

## Deployment Guide

### Step 1 — Clone the Repository

```powershell
git clone https://github.com/<your-org>/intune-monitor.git
Set-Location intune-monitor
```

### Step 2 — Configure Teams Incoming Webhook

> **Note:** Microsoft is migrating from legacy Office 365 Connectors to Workflows-based webhooks.  
> Use the **Workflows** method below unless your tenant still supports legacy connectors.

#### Method A — Teams Workflows (Recommended)
1. Open the target Teams channel
2. Click **...** → **Workflows**
3. Search for **"Post to a channel when a webhook request is received"**
4. Click **Add** → follow the wizard
5. Copy the generated webhook URL

#### Method B — Legacy Connector (if still available)
1. Open the target Teams channel
2. Click **...** → **Manage channel** → **Connectors**
3. Search for **Incoming Webhook** → **Add**
4. Give it a name (e.g., `Intune Alerts`) → **Create**
5. Copy the generated webhook URL

Save the webhook URL — you will need it in Step 4.

---

### Step 3 — Prepare Parameters File

Copy the example parameters file:

```powershell
Copy-Item arm-templates\parameters\parameters.example.json arm-templates\parameters\parameters.json
```

Edit `parameters.json` with your values:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "logAnalyticsWorkspaceResourceId": {
      "value": "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>"
    },
    "teamsWebhookUrl": {
      "value": "https://your-tenant.webhook.office.com/..."
    },
    "alertEmailAddress": {
      "value": "intune-admins@yourdomain.com"
    },
    "resourceGroupName": {
      "value": "rg-intune-monitoring"
    },
    "location": {
      "value": "westeurope"
    },
    "logicAppName": {
      "value": "la-intune-alerts"
    },
    "actionGroupName": {
      "value": "ag-intune-admins"
    }
  }
}
```

> ⚠️ `parameters.json` is gitignored to prevent webhook URLs and email addresses from being committed. Never commit this file.

---

### Step 4 — Deploy via PowerShell Script

```powershell
# Login to Azure
az login

# Run the deployment script
.\scripts\deploy.ps1 -ParametersFile "arm-templates/parameters/parameters.json" -SubscriptionId "<your-sub-id>"
```

Or deploy manually using PowerShell + Azure CLI:

```powershell
# Create resource group (if it doesn't exist)
az group create --name rg-intune-monitoring --location westeurope

# Deploy main template
az deployment group create `
  --resource-group rg-intune-monitoring `
  --template-file arm-templates\main.bicep `
  --parameters arm-templates\parameters\parameters.json
```

---

### Step 5 — Configure Intune Diagnostic Settings

> This step cannot be automated via ARM and must be performed manually in the Intune portal, or via the provided PowerShell script.

#### Option A — Portal
1. Go to [Intune Admin Center](https://intune.microsoft.com)
2. Navigate to **Tenant Administration** → **Diagnostic Settings**
3. Click **+ Add diagnostic setting**
4. Configure:
   - **Name:** `intune-to-log-analytics`
   - **Logs:** Check `AuditLogs` and `OperationalLogs`
   - **Destination:** Send to Log Analytics Workspace → select your workspace
5. Click **Save**

#### Option B — PowerShell Script
```powershell
.\scripts\configure-diagnostic-settings.ps1 `
  -WorkspaceId "<log-analytics-workspace-id>" `
  -SubscriptionId "<your-sub-id>"
```

---

### Step 6 — Validate Data Flow

Wait 10–15 minutes after configuring Diagnostic Settings, then run:

```powershell
.\scripts\validate-data-flow.ps1 -WorkspaceName "<workspace-name>" -ResourceGroupName "rg-intune-monitoring"
```

Or run these KQL queries manually in Log Analytics:

```kql
// Verify operational logs
IntuneOperationalLogs
| take 10

// Verify audit logs
IntuneAuditLogs
| take 10

// Check what OperationNames exist (important for tuning alert rules)
IntuneAuditLogs
| summarize Count=count() by OperationName
| order by Count desc
```

> ⚠️ If tables are empty after 15 minutes, refer to [Troubleshooting](docs/troubleshooting.md).

---

### Step 7 — Test the Logic App

1. Go to **Azure Portal** → **Logic Apps** → `la-intune-alerts`
2. Click **Run Trigger** → **With Payload**
3. Paste the test payload from `docs/test-payload.json`
4. Verify the Adaptive Card appears in your Teams channel

---

### Step 8 — Test an Alert Rule End-to-End

1. **Azure Monitor** → **Alerts** → select one of the deployed alert rules
2. Click **... → Fire test alert**
3. Verify:
   - Teams card received
   - Email received
   - Logic App run history shows success

---

## Post-Deployment Notes

### OperationName Validation
Alert rules use `OperationName` values that **must be validated** against your tenant's actual log data. After data flows in, run:

```kql
IntuneAuditLogs
| summarize count() by OperationName
| order by count_ desc
```

Compare results against the values used in the alert rule KQL queries and adjust if needed. See [alert-rules/](alert-rules/) for all queries.

### Alert Noise Consideration
Per-event alerting on enrollment success is intentional for lab/pilot use. In production, consider:
- Switching enrollment success to a **summary alert** (e.g., hourly digest)
- Adding **alert processing rules** to suppress outside business hours

### Cost Estimate (approximate)
| Component | Cost |
|---|---|
| Log Analytics ingestion | ~€2–5/GB depending on region/tier |
| Logic App runs | €0.000025/action (Consumption) — negligible |
| Alert rule evaluations | ~€0.10/rule/month (5 rules = €0.50/month) |

---


## CI/CD Pipeline (GitHub Actions)

The pipeline runs entirely on `windows-latest` using PowerShell. No bash or Linux tooling required.

### Required GitHub Secrets

Configure these under **Repository → Settings → Secrets and variables → Actions**:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal App ID |
| `AZURE_CLIENT_SECRET` | Service principal secret |
| `AZURE_TENANT_ID` | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `TEAMS_WEBHOOK_URL` | Teams Incoming Webhook URL |
| `ALERT_EMAIL_ADDRESS` | Admin notification email |
| `LA_WORKSPACE_RESOURCE_ID` | Full Log Analytics Workspace resource ID |

### Create the Service Principal (run once from your workstation)

```powershell
az ad sp create-for-rbac `
  --name "sp-intune-monitor-deploy" `
  --role Contributor `
  --scopes /subscriptions/<subscription-id> `
  --output json
```

Use the output values to populate `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `AZURE_TENANT_ID`.

### Pipeline Jobs

| Job | Trigger | Purpose |
|---|---|---|
| `validate` | Every run | Bicep lint + deployment validation |
| `whatif` | `whatif=true` input | Preview changes without deploying |
| `deploy` | `whatif=false` (default) | Full deployment |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-change`
3. Commit your changes: `git commit -m 'Add: description'`
4. Push and open a Pull Request

---

## License

MIT — see [LICENSE](LICENSE)
