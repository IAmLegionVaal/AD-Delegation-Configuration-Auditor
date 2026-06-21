# AD Delegation Configuration Auditor

A PowerShell toolkit for auditing Active Directory delegation exposure and applying selected guarded delegation repairs.

## Repair

Preview a change:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\AD_Delegation_Repair_Toolkit.ps1 -Identity APP01 -ObjectType Computer -DisableUnconstrainedDelegation -DryRun
```

Examples:

```powershell
.\AD_Delegation_Repair_Toolkit.ps1 -Identity APP01 -ObjectType Computer -DisableUnconstrainedDelegation
.\AD_Delegation_Repair_Toolkit.ps1 -Identity svcLegacy -ObjectType User -ClearConstrainedDelegation
.\AD_Delegation_Repair_Toolkit.ps1 -Identity FILE01 -ObjectType Computer -ClearResourceBasedConstrainedDelegation
```

## Repair behavior

- Requires elevation and the RSAT Active Directory module.
- Modifies only one explicitly selected user or computer per run.
- Can disable unconstrained delegation, clear `msDS-AllowedToDelegateTo`, or clear resource-based constrained delegation.
- Exports the complete selected AD object to CLIXML before any modification.
- Refuses domain controllers and protected administrative users.
- Supports `-DryRun`, confirmation or `-Yes`, timestamped action logs, post-change verification and distinct exit codes.

Exit codes are `0` success, `2` invalid or unsafe input, `3` missing privileges or prerequisites, `4` cancelled, `5` action failure and `6` verification failure.

## Safety

Delegation changes can break applications, scheduled tasks and tiered administration. Confirm service dependencies and retain the generated backup before applying a change. The tool does not automatically restore delegation values or make bulk changes from audit results.

## Author

Dewald Pretorius — L2 IT Support Engineer
