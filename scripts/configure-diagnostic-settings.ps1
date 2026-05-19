# ==============================================================
# configure-diagnostic-settings.ps1
# Configures Intune Diagnostic Settings to stream logs to
# an existing Log Analytics Workspace.
#
# Requires:
#   - Az PowerShell module (Az.Monitor, Az.Resources)
#   - Intune Administrator or Global Administrator role
#   - Log Analytics Contributor role on target workspace
#
# Usage:
#   .\scripts\configure-diagnostic-settings.ps1 `
#     -WorkspaceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>" `
#     -SubscriptionId "<your-subscription-id>"
# ==============================================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceResourceId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$DiagnosticSettingName = "intune-to-log-analytics"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Check Az Module ────────────────────────────────────────────

Write-Host "Checking Az PowerShell modules..." -ForegroundColor Cyan

$requiredModules = @('Az.Accounts', 'Az.Monitor')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module" -ForegroundColor Yellow
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    }
}

# ── Connect ────────────────────────────────────────────────────

Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount -Subscription $SubscriptionId | Out-Null
Write-Host "[✓] Connected to subscription: $SubscriptionId" -ForegroundColor Green

# ── Intune Resource ID ─────────────────────────────────────────
# Intune diagnostic settings are applied at the tenant/device management scope.
# The resource provider for Intune diagnostics is Microsoft.Intune/deviceManagement.

$intuneResourceId = "/providers/Microsoft.Intune"

# Log categories to enable
$logCategories = @(
    "AuditLogs",
    "OperationalLogs",
    "DeviceComplianceOrg"
)

Write-Host "`nConfiguring Diagnostic Settings..." -ForegroundColor Cyan
Write-Host "  Setting Name : $DiagnosticSettingName"
Write-Host "  Workspace    : $WorkspaceResourceId"
Write-Host "  Log Categories: $($logCategories -join ', ')"

# ── Build Log Settings ─────────────────────────────────────────

$logSettings = $logCategories | ForEach-Object {
    New-AzDiagnosticSettingLogSettingsObject `
        -Category $_ `
        -Enabled $true
}

# ── Apply Diagnostic Setting via REST API ──────────────────────
# Az.Monitor cmdlets may not cover Intune resource provider directly.
# We use the REST API via Invoke-AzRestMethod as a reliable alternative.

$uri = "https://management.azure.com$($intuneResourceId)/providers/Microsoft.Insights/diagnosticSettings/$($DiagnosticSettingName)?api-version=2021-05-01-preview"

$body = @{
    properties = @{
        workspaceId = $WorkspaceResourceId
        logs        = $logCategories | ForEach-Object {
            @{
                category = $_
                enabled  = $true
                retentionPolicy = @{
                    enabled = $false
                    days    = 0
                }
            }
        }
    }
} | ConvertTo-Json -Depth 5

Write-Host "`nApplying diagnostic setting via REST API..." -ForegroundColor Cyan

if ($PSCmdlet.ShouldProcess($intuneResourceId, "Set Diagnostic Settings")) {
    $response = Invoke-AzRestMethod -Method PUT -Uri $uri -Payload $body

    if ($response.StatusCode -in 200, 201) {
        Write-Host "[✓] Diagnostic settings configured successfully." -ForegroundColor Green
    } else {
        Write-Host "[✗] Failed to configure diagnostic settings." -ForegroundColor Red
        Write-Host "    HTTP Status : $($response.StatusCode)"
        Write-Host "    Response    : $($response.Content)"
        exit 1
    }
}

# ── Verify ─────────────────────────────────────────────────────

Write-Host "`nVerifying configuration..." -ForegroundColor Cyan

$verifyUri = "https://management.azure.com$($intuneResourceId)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
$verifyResponse = Invoke-AzRestMethod -Method GET -Uri $verifyUri
$settings = ($verifyResponse.Content | ConvertFrom-Json).value

if ($settings | Where-Object { $_.name -eq $DiagnosticSettingName }) {
    Write-Host "[✓] Diagnostic setting '$DiagnosticSettingName' confirmed." -ForegroundColor Green
} else {
    Write-Host "[!] Could not confirm setting — verify manually in Intune Admin Center." -ForegroundColor Yellow
}

Write-Host @"

════════════════════════════════════════════════
 Diagnostic Settings Configuration Complete
════════════════════════════════════════════════

 Log categories enabled:
   - AuditLogs         (Device Wipe, Retire, Reset)
   - OperationalLogs   (Enrollment Success/Failure)
   - DeviceComplianceOrg

 Expected data flow delay: 10-15 minutes

 Next step: Run validate-data-flow.ps1 to confirm
            data is arriving in Log Analytics.
"@ -ForegroundColor Cyan
