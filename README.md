# Intune Monitor — Azure Monitor Alerting Solution

Automated alerting for Microsoft Intune events using Azure Monitor, Log Analytics, and Logic Apps with Teams and email notifications.

## What This Solution Deploys

| Component | Purpose |
|---|---|
| **Log Analytics Workspace** | (existing) Stores and queries Intune logs |
| **Logic App** | Transforms Azure Monitor payload into Teams Adaptive Card |
| **Action Group** | Routes alerts to Logic App + email |
| **6 Alert Rules** | Per-event detection for enrollment, wipe, retire, delete, reset |

### Monitored Events

| Event | Log Table | Severity |
|---|---|---|
| Enrollment Success | `IntuneOperationalLogs` | Sev3 |
| Enrollment Failure | `IntuneOperationalLogs` | Sev2 |
| Device Wipe | `IntuneAuditLogs` | Sev1 |
| Device Retire | `IntuneAuditLogs` | Sev1 |
| Device Delete | `IntuneAuditLogs` | Sev1 |
| Fresh Start / Autopilot Reset | `IntuneAuditLogs` | Sev2 (disabled by default — see Post-Deployment Notes) |

---

## Prerequisites

| Requirement | Details |
|---|---|
| Windows workstation | Windows 10/11 or Windows Server 2019+ |
| PowerShell 7 | Required — do **not** use Windows PowerShell 5.1. [Install](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) via `winget install Microsoft.PowerShell` |
| Azure CLI ≥ 2.50 | [Install](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows) — Bicep is included |
| Az PowerShell module | `Install-Module Az -Scope CurrentUser` (run in PowerShell 7) |
| Azure subscription | Contributor or Owner role |
| Microsoft 365 E5 license | Required for Intune Diagnostic Settings |
| Existing Log Analytics Workspace | Must already have Intune logs flowing — Resource ID required during deployment |
| Intune Administrator or Global Admin role | To configure Diagnostic Settings |
| Teams channel | For webhook configuration |

> **Note:** All scripts, README commands, and the CI/CD pipeline use **PowerShell 7 syntax exclusively**. No bash, WSL, or Linux tooling is required. Always launch PowerShell 7 via `pwsh` or the Start menu — not Windows PowerShell (5.1).

> **Note:** This solution assumes MFA is enforced for all admin accounts. Follow the authentication steps exactly — skipping or reordering them will cause deployment failures.

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
│   ├── alert-rules.bicep              # All 6 alert rules
│   └── parameters/
│       ├── parameters.example.json    # Parameter file template (safe to commit)
│       └── parameters.json            # Your parameters (gitignored — never commit)
├── alert-rules/
│   ├── kql-enrollment-success.kql
│   ├── kql-enrollment-failure.kql
│   ├── kql-device-wipe.kql
│   ├── kql-device-retire.kql
│   └── kql-device-reset.kql
├── scripts/
│   ├── deploy.ps1                     # Main deployment script
│   ├── configure-diagnostic-settings.ps1
│   └── validate-data-flow.ps1
└── docs/
    ├── architecture.md
    ├── troubleshooting.md
    └── test-payload.json              # Logic App manual test payload
```

---

## Deployment Guide

### Step 1 — Install Prerequisites

Open **PowerShell 7** (`pwsh`) and run:

```powershell
# Install Azure CLI (if not already installed)
winget install Microsoft.AzureCLI

# Install Az PowerShell module
Install-Module Az -Scope CurrentUser -Force

# Verify Azure CLI version
az version
```

> If `Install-Module` fails, your PowerShell module path may be on OneDrive causing load errors. Install PowerShell 7 fresh via `winget install Microsoft.PowerShell` and retry in the new `pwsh` window.

---

### Step 2 — Authenticate to Azure

> ⚠️ **MFA with Conditional Access is assumed.** Standard `az login` is not sufficient — your tenant likely enforces MFA specifically for Azure Resource Manager (ARM) operations. Follow the steps below exactly.

#### Step 2a — Initial login

```powershell
az logout
az login
```

Complete the MFA prompt in the browser. Set your subscription:

```powershell
az account set --subscription "<your-subscription-id>"
az account show --query "{Name:name, Id:id}" -o table
```

#### Step 2b — Satisfy the ARM Conditional Access claim

Even after a successful `az login`, your tenant's Conditional Access policy requires an additional MFA claim specifically scoped to Azure Resource Manager. This claim is only triggered when you first attempt an ARM write operation.

**The reliable way to obtain it:**

1. Run the resource group creation command:
```powershell
az group create --name rg-intune-monitoring --location eastus
```

2. It will fail with `AADSTS50076` and print an `az login` command, for example:
```
az login --tenant "<tenant-id>" --scope "https://management.azure.com//.default" --claims-challenge "<token>"
```

3. **Copy and run that exact command** — including the `--claims-challenge` value. A browser window will open for MFA.

4. After completing MFA, run the resource group creation again:
```powershell
az group create --name rg-intune-monitoring --location eastus
```

5. Verify it succeeded:
```powershell
az group show --name rg-intune-monitoring --query "{Name:name, State:properties.provisioningState}" -o table
```

Expected output: `provisioningState: Succeeded`

> The `--claims-challenge` token is dynamic and changes every time — it cannot be pre-documented. Always copy it from the error output.

> **Token expiry:** ARM tokens typically last 60–90 minutes. If you see `AADSTS50076` again mid-deployment, repeat Step 2b. Do not close the PowerShell window between authentication and deployment.

---

### Step 3 — Clone the Repository

```powershell
git clone https://github.com/<your-org>/intune-monitor.git
Set-Location intune-monitor
```

---

### Step 4 — Configure Teams Incoming Webhook

> Microsoft has migrated from legacy Office 365 Connectors to Workflows-based webhooks. Use the Workflows method below.

1. Open the target Teams channel
2. Click **...** → **Workflows**
3. Click **Create** tab → search for **"webhook"**
4. Select **"Post to a channel when a webhook request is received"** (also shown as **"Send webhook alerts"**)
5. Name it (e.g., `Intune Alerts`) → select your team and channel → **Create**
6. Click **Copy webhook link**

> If the template is not visible in Teams, go to **[make.powerautomate.com](https://make.powerautomate.com)** → **My flows** → **New flow** → **Template** → search **"webhook"** → select the template there instead.

The webhook URL will look like:
```
https://prod-xx.xx.logic.azure.com:443/workflows/...
```
or
```
https://<tenant>.environment.api.powerplatform.com:443/powerautomate/...
```

Both formats are valid — save the URL for the next step.

---

### Step 5 — Prepare Parameters File

```powershell
Copy-Item arm-templates\parameters\parameters.example.json arm-templates\parameters\parameters.json
```

Open `parameters.json` in VS Code or Notepad and fill in your values:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "logAnalyticsWorkspaceResourceId": {
      "value": "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>"
    },
    "teamsWebhookUrl": {
      "value": "https://<your-webhook-url>"
    },
    "alertEmailAddress": {
      "value": "intune-admins@yourdomain.com"
    },
    "location": {
      "value": "eastus"
    },
    "logicAppName": {
      "value": "la-intune-alerts"
    },
    "actionGroupName": {
      "value": "ag-intune-admins"
    },
    "actionGroupShortName": {
      "value": "IntuneAdmin"
    }
  }
}
```

**Finding your Log Analytics Workspace Resource ID:**

```powershell
az monitor log-analytics workspace list `
  --query "[].{Name:name, ResourceId:id}" -o table
```

Copy the full `ResourceId` value — it is the ARM path, not the Workspace ID (GUID).

> ⚠️ `parameters.json` is gitignored. Never commit it — it contains your webhook URL and email address.

---

### Step 6 — Deploy

Run the deployment script immediately after authentication — do not wait or close the window:

```powershell
.\scripts\deploy.ps1 `
  -ParametersFile "arm-templates\parameters\parameters.json" `
  -SubscriptionId "<your-subscription-id>"
```

The script will:
1. Validate prerequisites and parameters
2. Validate Bicep templates
3. Deploy Logic App, Action Group, and 6 Alert Rules
4. Output the Logic App trigger URL and Action Group ID

Expected completion time: 2–3 minutes.

If you see `AADSTS50076` or `InteractionRequired` during deployment, re-authenticate (Step 2) and retry.

---

### Step 8 — Configure Intune Diagnostic Settings

> Skip this step if Intune logs are already flowing to your Log Analytics Workspace (verify by checking if `IntuneAuditLogs` and `IntuneOperationalLogs` tables exist in your workspace).

#### Option A — Portal (recommended)
1. Go to [Intune Admin Center](https://intune.microsoft.com)
2. Navigate to **Tenant Administration** → **Diagnostic Settings**
3. Click **+ Add diagnostic setting**
4. Configure:
   - **Name:** `intune-to-log-analytics`
   - **Logs:** Check `AuditLogs` and `OperationalLogs`
   - **Destination:** Send to Log Analytics Workspace → select your workspace
5. Click **Save**

#### Option B — PowerShell
```powershell
.\scripts\configure-diagnostic-settings.ps1 `
  -WorkspaceResourceId "<log-analytics-workspace-resource-id>" `
  -SubscriptionId "<your-subscription-id>"
```

Allow 10–15 minutes for data to begin flowing after saving.

---

### Step 9 — Validate OperationName Values

> ⚠️ This step is mandatory. Alert rule KQL queries use `OperationName` values that vary by tenant. The default values may not match your tenant and must be verified before alerts will fire correctly.

Run this query in Log Analytics (Azure Portal → your workspace → Logs):

```kql
IntuneAuditLogs
| where TimeGenerated > ago(30d)
| where OperationName contains "ManagedDevice"
| summarize Count=count() by OperationName
| order by Count desc
```

Compare the results against the values in `arm-templates\alert-rules.bicep`:

| Alert Rule | Default OperationName | Verify against your results |
|---|---|---|
| Device Wipe | `Wipe ManagedDevice` | |
| Device Retire | `Retire ManagedDevice` | |
| Device Delete | `Delete ManagedDevice` | |
| Fresh Start / Reset | `FreshStart ManagedDevice` | (rule disabled by default) |

If any values differ, update `alert-rules.bicep` and redeploy:

```powershell
# Example: fix a single OperationName
(Get-Content "arm-templates\alert-rules.bicep") `
  -replace '"Wipe ManagedDevice"', '"<correct-value>"' |
  Set-Content "arm-templates\alert-rules.bicep"

# Redeploy
.\scripts\deploy.ps1 `
  -ParametersFile "arm-templates\parameters\parameters.json" `
  -SubscriptionId "<your-subscription-id>"
```

---

### Step 10 — Test the Solution

#### Test Logic App (Teams card)
1. **Azure Portal → Logic Apps → `la-intune-alerts`**
2. Click **Overview → Run Trigger → With Payload**
3. Paste the contents of `docs\test-payload.json`
4. Click **Run**
5. Verify the Adaptive Card appears in your Teams channel

#### Test Action Group (email + Teams)
1. **Azure Portal → Monitor → Alerts → Action Groups**
2. Open `ag-intune-admins`
3. Click **Test** → select sample type **Log Alert V2**
4. Verify email and Teams notification are both received

#### End-to-end test
Perform a real action in Intune (e.g., enroll a test device). Within 5–10 minutes the corresponding alert rule will evaluate and fire.

---

## Post-Deployment Notes

### Fresh Start / Autopilot Reset Rule
Rule 5 is deployed but **disabled by default** because these OperationNames were not observed in the reference tenant. To enable it:
1. Confirm the correct OperationName in your tenant logs
2. Update `alert-rules.bicep` with the correct value
3. Change `enabled: false` to `enabled: true`
4. Redeploy

### Alert Noise — Enrollment Success
Per-event alerting on enrollment success is suitable for lab and pilot deployments. In production environments with high enrollment volume, consider switching to a threshold-based or aggregated alert to reduce noise.

### Cost Estimate (approximate)

| Component | Cost |
|---|---|
| Log Analytics ingestion | ~€2–5/GB depending on region and tier |
| Logic App runs | €0.000025/action (Consumption) — negligible |
| Alert rule evaluations | ~€0.10/rule/month (6 rules ≈ €0.60/month) |

---

## CI/CD Pipeline (GitHub Actions)

The pipeline runs entirely on `windows-latest` using PowerShell 7. No bash or Linux tooling required.

### Required GitHub Secrets

Configure under **Repository → Settings → Secrets and variables → Actions**:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal App ID |
| `AZURE_CLIENT_SECRET` | Service principal secret |
| `AZURE_TENANT_ID` | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `TEAMS_WEBHOOK_URL` | Teams Incoming Webhook URL |
| `ALERT_EMAIL_ADDRESS` | Admin notification email |
| `LA_WORKSPACE_RESOURCE_ID` | Full Log Analytics Workspace Resource ID (ARM path) |

### Create the Service Principal (run once)

```powershell
az ad sp create-for-rbac `
  --name "sp-intune-monitor-deploy" `
  --role Contributor `
  --scopes /subscriptions/<subscription-id> `
  --output json
```

Use the output to populate `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `AZURE_TENANT_ID`.

### Pipeline Jobs

| Job | Trigger | Purpose |
|---|---|---|
| `validate` | Every push | Bicep lint + deployment validation |
| `whatif` | `whatif=true` input | Preview changes without deploying |
| `deploy` | `whatif=false` (default) | Full deployment |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-change`
3. Commit: `git commit -m 'Add: description'`
4. Push and open a Pull Request

---

## License

MIT — see [LICENSE](LICENSE)
