# Changelog

All notable changes to this solution will be documented here.  
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] — 2026-05-18

### Added
- Initial release
- Intune Diagnostic Settings configuration script
- Log Analytics Workspace integration
- 5 Azure Monitor Scheduled Query Alert Rules:
  - Enrollment Success (Sev3)
  - Enrollment Failure (Sev2)
  - Device Wipe (Sev1)
  - Device Retire (Sev1)
  - Fresh Start / Autopilot Reset (Sev2)
- Logic App with Teams Adaptive Card notifications
- Action Group with email + Logic App receivers
- Bicep templates (main, logicapp, actiongroup, alert-rules)
- PowerShell deployment, diagnostic settings, and validation scripts
- GitHub Actions CI/CD pipeline
- Troubleshooting guide and architecture documentation
