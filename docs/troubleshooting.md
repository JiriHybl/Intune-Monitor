# Troubleshooting Guide

## Issue 1 — IntuneAuditLogs / IntuneOperationalLogs tables are empty

**Symptoms:** KQL queries return no results after configuring Diagnostic Settings.

**Checks:**
1. Go to **Intune Admin Center → Tenant Administration → Diagnostic Settings**
2. Confirm the setting exists and shows `AuditLogs` and `OperationalLogs` enabled
3. Confirm the correct Log Analytics Workspace is selected
4. Wait at least **15 minutes** — initial ingestion delay is expected

**If still empty after 30 minutes:**
- Verify the workspace resource ID in your parameters file matches the actual workspace
- Check the workspace is in the same Azure AD tenant as Intune
- Confirm your account has at least **Log Analytics Contributor** on the workspace

---

## Issue 2 — OperationName values don't match alert rule KQL

**Symptoms:** Alert rules never fire, even when wipe/retire actions are performed.

**Resolution:**
Run this query in Log Analytics after performing a test wipe or retire action:

```kql
IntuneAuditLogs
| where TimeGenerated > ago(1h)
| summarize count() by OperationName
| order by count_ desc
```

Compare the actual `OperationName` values returned against those in `alert-rules.bicep`. Update the KQL queries to match, then redeploy.

**Known variation:** Some tenants use `wipeDevice` instead of `DeviceAction_wipe`. Always validate from live data.

---

## Issue 3 — Logic App run fails

**Symptoms:** Alert fires, email is received, but Teams card is not posted.

**Checks:**
1. Go to **Azure Portal → Logic Apps → la-intune-alerts → Run History**
2. Click the failed run and expand each step to identify the failing action
3. Check the `Post_Teams_Adaptive_Card` step output for HTTP error codes

**Common causes:**

| Error | Cause | Fix |
|---|---|---|
| `404 Not Found` | Teams webhook URL expired or invalid | Regenerate webhook URL, redeploy |
| `400 Bad Request` | Adaptive Card schema error | Check Logic App body JSON, validate against adaptivecards.io/designer |
| `401 Unauthorized` | Teams Workflow webhook requires specific headers | Switch to Workflows-based webhook |

---

## Issue 4 — Logic App trigger URL changes after redeployment

**Symptoms:** Action Group stops triggering Logic App after a redeploy.

**Cause:** Each deployment generates a new SAS token for the HTTP trigger URL.

**Resolution:** After each deployment, re-run the Action Group update step or redeploy the action group module. The `deploy.ps1` script handles this automatically.

---

## Issue 5 — Alert fires but no email received

**Checks:**
1. Check spam/junk folder
2. Go to **Azure Monitor → Alerts → Action Groups → ag-intune-admins**
3. Click **Test** and select the email receiver
4. Check if the email address in parameters matches exactly

---

## Issue 6 — GitHub Actions deployment fails on Bicep validation

**Symptoms:** `az bicep build` fails in CI pipeline.

**Common cause:** Bicep version mismatch between local and CI.

**Resolution:**
```yaml
- name: Install specific Bicep version
  run: az bicep install --version v0.26.54
```

---

## Useful Diagnostic Queries

```kql
// Check last 50 audit log entries
IntuneAuditLogs
| top 50 by TimeGenerated desc
| project TimeGenerated, OperationName, ActorUPN, ActivityResultType

// Check for specific device
IntuneAuditLogs
| where TargetDisplayNames contains "DEVICE-NAME"
| order by TimeGenerated desc

// Check enrollment events last 4 hours
IntuneOperationalLogs
| where TimeGenerated > ago(4h)
| where OperationName =~ "Enrollment"
| extend P = parse_json(Properties)
| project TimeGenerated, State=tostring(P.EnrollmentState), Device=tostring(P.DeviceName), User=tostring(P.UserPrincipalName)
```
