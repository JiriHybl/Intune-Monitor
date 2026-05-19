# Architecture

## Solution Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ Microsoft Intune (Tenant Admin)                                  │
│                                                                  │
│  Diagnostic Settings                                            │
│  ├── AuditLogs          (Wipe, Retire, Fresh Start, Reset)      │
│  └── OperationalLogs    (Enrollment Success / Failure)          │
└──────────────────────────┬──────────────────────────────────────┘
                           │ 5–15 min ingestion delay
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Log Analytics Workspace (existing)                               │
│                                                                  │
│  Tables:                                                        │
│  ├── IntuneAuditLogs                                            │
│  ├── IntuneOperationalLogs                                      │
│  └── DeviceComplianceOrg                                        │
└──────────────────────────┬──────────────────────────────────────┘
                           │ Evaluated every 5 min
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Azure Monitor — Scheduled Query Alert Rules (5 rules)           │
│                                                                  │
│  ├── intune-enrollment-success   (Sev3)                         │
│  ├── intune-enrollment-failure   (Sev2)                         │
│  ├── intune-device-wipe          (Sev1)                         │
│  ├── intune-device-retire        (Sev1)                         │
│  └── intune-device-reset         (Sev2)                         │
└──────────────────────────┬──────────────────────────────────────┘
                           │ On threshold exceeded (>0 rows)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Action Group: ag-intune-admins                                   │
│                                                                  │
│  ├── Email → intune-admins@domain.com                           │
│  └── Logic App → la-intune-alerts                               │
└─────────────┬───────────────────────────────────────────────────┘
              │                          │
              ▼                          ▼
┌─────────────────────┐    ┌────────────────────────────────────┐
│ Admin Email Inbox   │    │ Logic App: la-intune-alerts        │
│                     │    │                                    │
│ Azure Monitor       │    │  1. Parse Common Alert Schema      │
│ standard email      │    │  2. Set severity colour/emoji      │
│ format              │    │  3. POST Adaptive Card             │
└─────────────────────┘    └────────────────┬───────────────────┘
                                            │ HTTP POST
                                            ▼
                           ┌────────────────────────────────────┐
                           │ Microsoft Teams                    │
                           │                                    │
                           │  Adaptive Card with:              │
                           │  • Alert rule name                │
                           │  • Severity (colour-coded)        │
                           │  • Fired timestamp                │
                           │  • KQL query                      │
                           │  • Link to Log Analytics          │
                           └────────────────────────────────────┘
```

## Key Design Decisions

### Common Alert Schema
All alert rules and the Action Group use the **Common Alert Schema**. This ensures:
- Consistent JSON structure regardless of alert type
- Single Logic App handles all 5 alert rules
- Forward-compatible with additional alert rules added later

### Per-Event Alerting
All rules use `threshold: 0` (alert on any result > 0 rows). This is intentional for:
- Lab and pilot environments
- High-impact events (Wipe, Retire) where every occurrence is significant

For production, enrollment success alerts should be reviewed for noise and potentially converted to hourly digest alerts using Alert Processing Rules.

### Logic App — Consumption Plan
The Consumption (multi-tenant) Logic App tier is used because:
- Cost is negligible at low trigger frequency
- No infrastructure management required
- Sufficient for alert notification workloads

### autoMitigate: false
All alert rules set `autoMitigate: false`. This means alerts remain in **Fired** state until manually resolved. This is intentional — device wipe and retire events are discrete actions, not conditions that resolve themselves.

## Component Dependencies

```
main.bicep
├── logicapp.bicep          (no dependencies)
├── actiongroup.bicep       (depends on: logicapp.bicep output)
└── alert-rules.bicep       (depends on: actiongroup.bicep output)
```

Bicep module outputs are passed as parameters between modules, ensuring correct deployment order.
