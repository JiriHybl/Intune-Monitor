# ==============================================================
# validate-data-flow.ps1
# Validates that Intune logs are flowing into Log Analytics.
# Also discovers OperationName values for alert rule tuning.
#
# Usage:
#   .\scripts\validate-data-flow.ps1 `
#     -WorkspaceName "<workspace-name>" `
#     -ResourceGroupName "<resource-group>"
# ==============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Connect ────────────────────────────────────────────────────

if ($SubscriptionId) {
    Connect-AzAccount -Subscription $SubscriptionId | Out-Null
}

# ── Helper: Run KQL Query ──────────────────────────────────────

function Invoke-KqlQuery {
    param(
        [string]$WorkspaceId,
        [string]$Query,
        [string]$Label
    )

    Write-Host "`n  Running: $Label" -ForegroundColor Gray

    $result = Invoke-AzOperationalInsightsQuery `
        -WorkspaceId $WorkspaceId `
        -Query $Query `
        -ErrorAction SilentlyContinue

    return $result
}

# ── Get Workspace ──────────────────────────────────────────────

Write-Host "`nResolving Log Analytics Workspace..." -ForegroundColor Cyan

$workspace = Get-AzOperationalInsightsWorkspace `
    -ResourceGroupName $ResourceGroupName `
    -Name $WorkspaceName

$workspaceId = $workspace.CustomerId
Write-Host "[✓] Workspace ID: $workspaceId" -ForegroundColor Green

# ── Check 1: OperationalLogs ───────────────────────────────────

Write-Host "`n[1/4] Checking IntuneOperationalLogs..." -ForegroundColor Cyan

$opLogsResult = Invoke-KqlQuery `
    -WorkspaceId $workspaceId `
    -Query "IntuneOperationalLogs | summarize Count=count() | project Count" `
    -Label "IntuneOperationalLogs row count"

$opCount = ($opLogsResult.Results | Select-Object -First 1).Count

if ([int]$opCount -gt 0) {
    Write-Host "[✓] IntuneOperationalLogs: $opCount rows found" -ForegroundColor Green
} else {
    Write-Host "[!] IntuneOperationalLogs: No data yet. Wait 10-15 min after configuring Diagnostic Settings." -ForegroundColor Yellow
}

# ── Check 2: AuditLogs ─────────────────────────────────────────

Write-Host "`n[2/4] Checking IntuneAuditLogs..." -ForegroundColor Cyan

$auditLogsResult = Invoke-KqlQuery `
    -WorkspaceId $workspaceId `
    -Query "IntuneAuditLogs | summarize Count=count() | project Count" `
    -Label "IntuneAuditLogs row count"

$auditCount = ($auditLogsResult.Results | Select-Object -First 1).Count

if ([int]$auditCount -gt 0) {
    Write-Host "[✓] IntuneAuditLogs: $auditCount rows found" -ForegroundColor Green
} else {
    Write-Host "[!] IntuneAuditLogs: No data yet." -ForegroundColor Yellow
}

# ── Check 3: Discover OperationNames ──────────────────────────

Write-Host "`n[3/4] Discovering OperationName values in AuditLogs..." -ForegroundColor Cyan
Write-Host "      (Used to validate and tune alert rule KQL queries)" -ForegroundColor Gray

$opNamesResult = Invoke-KqlQuery `
    -WorkspaceId $workspaceId `
    -Query "IntuneAuditLogs | summarize Count=count() by OperationName | order by Count desc" `
    -Label "OperationName discovery"

if ($opNamesResult.Results.Count -gt 0) {
    Write-Host "`n  OperationName values found in your tenant:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor Gray
    $opNamesResult.Results | ForEach-Object {
        Write-Host ("  {0,-50} {1,8} events" -f $_.OperationName, $_.Count) -ForegroundColor White
    }

    # Check for expected OperationNames
    $expectedOps = @(
        "DeviceAction_wipe",
        "DeviceAction_retire",
        "DeviceAction_freshStart",
        "DeviceAction_autopilotReset"
    )

    Write-Host "`n  Alert rule OperationName validation:" -ForegroundColor Cyan
    foreach ($op in $expectedOps) {
        $found = $opNamesResult.Results | Where-Object { $_.OperationName -eq $op }
        if ($found) {
            Write-Host "  [✓] $op" -ForegroundColor Green
        } else {
            Write-Host "  [?] $op — not yet seen in logs (may need to trigger action or check tenant)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  [!] No OperationName data available yet." -ForegroundColor Yellow
}

# ── Check 4: Enrollment Events ────────────────────────────────

Write-Host "`n[4/4] Checking recent enrollment events..." -ForegroundColor Cyan

$enrollResult = Invoke-KqlQuery `
    -WorkspaceId $workspaceId `
    -Query @"
IntuneOperationalLogs
| where TimeGenerated > ago(24h)
| where OperationName =~ "Enrollment"
| extend ParsedProperties = parse_json(Properties)
| summarize
    Success = countif(tostring(ParsedProperties.EnrollmentState) =~ "Enrolled"),
    Failed  = countif(tostring(ParsedProperties.EnrollmentState) =~ "Failed")
"@ `
    -Label "Enrollment events in last 24 hours"

if ($enrollResult.Results.Count -gt 0) {
    $r = $enrollResult.Results | Select-Object -First 1
    Write-Host "  Last 24h — Success: $($r.Success)   Failed: $($r.Failed)" -ForegroundColor White
} else {
    Write-Host "  [!] No enrollment events found in last 24 hours." -ForegroundColor Yellow
}

# ── Summary ────────────────────────────────────────────────────

Write-Host @"

════════════════════════════════════════════════
 Data Flow Validation Complete
════════════════════════════════════════════════

 If any checks showed [!], wait 10-15 minutes
 and re-run this script.

 If tables remain empty after 30 minutes:
   → Check Diagnostic Settings in Intune portal
   → Verify workspace ID in parameters.json
   → See: docs/troubleshooting.md

 If OperationName values differ from expected:
   → Update KQL queries in alert-rules.bicep
   → Redeploy: .\scripts\deploy.ps1
"@ -ForegroundColor Cyan
