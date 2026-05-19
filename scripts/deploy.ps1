# ==============================================================
# deploy.ps1 — Intune Monitor Solution Deployment Script
#
# Usage:
#   .\scripts\deploy.ps1 `
#     -ParametersFile "arm-templates/parameters/parameters.json" `
#     -SubscriptionId "<your-subscription-id>"
#
# Optional:
#   -ResourceGroupName "rg-intune-monitoring"   (default used if omitted)
#   -WhatIf                                      (dry run, no changes made)
# ==============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ParametersFile,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] STEP: $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
}

# ── Validate Prerequisites ─────────────────────────────────────

Write-Step "Validating prerequisites"

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Fail "Azure CLI not found. Install from: https://learn.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

$cliVersion = (az version --query '"azure-cli"' -o tsv)
Write-Success "Azure CLI version: $cliVersion"

# Check parameters file exists
if (-not (Test-Path $ParametersFile)) {
    Write-Fail "Parameters file not found: $ParametersFile"
    Write-Warning "Copy arm-templates/parameters/parameters.example.json to parameters.json and fill in your values."
    exit 1
}

Write-Success "Parameters file found: $ParametersFile"

# ── Load Parameters ────────────────────────────────────────────

Write-Step "Loading parameters"

$params = Get-Content $ParametersFile | ConvertFrom-Json

$location          = $params.parameters.location.value
$logicAppName      = $params.parameters.logicAppName.value
$actionGroupName   = $params.parameters.actionGroupName.value

# Resolve resource group name: prefer parameter from file, then CLI arg, then default
if ([string]::IsNullOrEmpty($ResourceGroupName)) {
    if ($params.parameters.PSObject.Properties['resourceGroupName']) {
        $ResourceGroupName = $params.parameters.resourceGroupName.value
    } else {
        $ResourceGroupName = "rg-intune-monitoring"
        Write-Warning "No resource group specified — using default: $ResourceGroupName"
    }
}

Write-Success "Resource Group : $ResourceGroupName"
Write-Success "Location       : $location"
Write-Success "Logic App      : $logicAppName"
Write-Success "Action Group   : $actionGroupName"

# ── Set Subscription ───────────────────────────────────────────

Write-Step "Setting active subscription"

az account set --subscription $SubscriptionId | Out-Null
$currentSub = (az account show --query "name" -o tsv)
Write-Success "Active subscription: $currentSub ($SubscriptionId)"

# ── Create Resource Group ──────────────────────────────────────

Write-Step "Ensuring Resource Group exists: $ResourceGroupName"

$rgExists = (az group exists --name $ResourceGroupName)
if ($rgExists -eq "false") {
    if ($WhatIf) {
        Write-Warning "[WhatIf] Would create resource group: $ResourceGroupName in $location"
    } else {
        az group create --name $ResourceGroupName --location $location | Out-Null
        Write-Success "Resource group created: $ResourceGroupName"
    }
} else {
    Write-Success "Resource group already exists: $ResourceGroupName"
}

# ── Validate Bicep Template ────────────────────────────────────

Write-Step "Validating Bicep templates"

$templateFile = Join-Path $PSScriptRoot "..\arm-templates\main.bicep"
$templateFile = [System.IO.Path]::GetFullPath($templateFile)

$validateResult = az deployment group validate `
    --resource-group $ResourceGroupName `
    --template-file $templateFile `
    --parameters $ParametersFile `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Template validation failed:"
    Write-Host $validateResult -ForegroundColor Red
    exit 1
}

Write-Success "Template validation passed"

# ── Deploy ─────────────────────────────────────────────────────

if ($WhatIf) {
    Write-Step "Running What-If deployment (no changes will be made)"
    az deployment group what-if `
        --resource-group $ResourceGroupName `
        --template-file $templateFile `
        --parameters $ParametersFile
    Write-Success "What-If complete. Review the above changes before deploying."
    exit 0
}

Write-Step "Deploying solution to resource group: $ResourceGroupName"

$deploymentName = "intune-monitor-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployOutput = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroupName `
    --template-file $templateFile `
    --parameters $ParametersFile `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Deployment failed. Check Azure portal for details."
    exit 1
}

Write-Success "Deployment succeeded: $deploymentName"

# ── Extract and Display Outputs ────────────────────────────────

Write-Step "Deployment outputs"

$logicAppName     = $deployOutput.properties.outputs.logicAppName.value
$triggerUrl       = $deployOutput.properties.outputs.logicAppTriggerUrl.value
$actionGroupId    = $deployOutput.properties.outputs.actionGroupResourceId.value

Write-Host ""
Write-Host "  Logic App Name   : $logicAppName" -ForegroundColor White
Write-Host "  Trigger URL      : $triggerUrl" -ForegroundColor White
Write-Host "  Action Group ID  : $actionGroupId" -ForegroundColor White
Write-Host ""
Write-Warning "The Logic App trigger URL above contains a SAS token. Treat it as a secret."

# ── Summary ────────────────────────────────────────────────────

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Deployment Complete" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host " Next steps:" -ForegroundColor White
Write-Host "  1. Configure Intune Diagnostic Settings:" -ForegroundColor White
Write-Host "     .\scripts\configure-diagnostic-settings.ps1" -ForegroundColor Gray
Write-Host "  2. Validate data flow (wait 10-15 min after step 1):" -ForegroundColor White
Write-Host "     .\scripts\validate-data-flow.ps1" -ForegroundColor Gray
Write-Host "  3. Test Logic App manually via Azure Portal" -ForegroundColor White
Write-Host "  4. Fire a test alert from Azure Monitor" -ForegroundColor White
Write-Host ""
