[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Identity,
    [ValidateSet('User','Computer')][string]$ObjectType='Computer',
    [switch]$DisableUnconstrainedDelegation,
    [switch]$ClearConstrainedDelegation,
    [switch]$ClearResourceBasedConstrainedDelegation,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$LogDirectory="$env:ProgramData\IAmLegionVaal\ADDelegationRepair"
)

$ErrorActionPreference='Stop'
$ExitInvalidInput=2; $ExitPrerequisite=3; $ExitCancelled=4; $ExitActionFailure=5; $ExitVerificationFailure=6
function Test-Admin {$p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent());$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
function Write-Log([string]$Message){$line="{0:u} {1}" -f (Get-Date),$Message;Write-Host $line;Add-Content -LiteralPath $script:LogPath -Value $line}
function Invoke-Step([string]$Description,[scriptblock]$Action){if($DryRun){Write-Log "[DRY-RUN] $Description"}else{Write-Log "[ACTION] $Description";& $Action}}

if(-not($DisableUnconstrainedDelegation -or $ClearConstrainedDelegation -or $ClearResourceBasedConstrainedDelegation)){Write-Error 'Select at least one repair action.';exit $ExitInvalidInput}
if(-not(Test-Admin)){Write-Error 'Run from an elevated PowerShell session.';exit $ExitPrerequisite}
try{Import-Module ActiveDirectory -ErrorAction Stop}catch{Write-Error "ActiveDirectory module unavailable: $($_.Exception.Message)";exit $ExitPrerequisite}

New-Item -ItemType Directory -Path $LogDirectory -Force|Out-Null
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$script:LogPath=Join-Path $LogDirectory "ADDelegationRepair_$stamp.log";$backupPath=Join-Path $LogDirectory "ADDelegationObject_$stamp.xml"
try{
    if($ObjectType -eq 'Computer'){$target=Get-ADComputer -Identity $Identity -Properties TrustedForDelegation,TrustedToAuthForDelegation,msDS-AllowedToDelegateTo,msDS-AllowedToActOnBehalfOfOtherIdentity,PrimaryGroupID,DistinguishedName}
    else{$target=Get-ADUser -Identity $Identity -Properties TrustedForDelegation,TrustedToAuthForDelegation,msDS-AllowedToDelegateTo,msDS-AllowedToActOnBehalfOfOtherIdentity,AdminCount,DistinguishedName}
}catch{Write-Error "Unable to resolve $ObjectType '$Identity': $($_.Exception.Message)";exit $ExitInvalidInput}
if($ObjectType -eq 'Computer' -and ($target.PrimaryGroupID -eq 516 -or $target.DistinguishedName -match '(?i)OU=Domain Controllers')){Write-Error 'Domain controllers are excluded from automated delegation repair.';exit $ExitInvalidInput}
if($ObjectType -eq 'User' -and $target.AdminCount -eq 1){Write-Error 'Protected administrative users are excluded from automated delegation repair.';exit $ExitInvalidInput}
$target|Export-Clixml -LiteralPath $backupPath
Write-Log "Saved delegation backup to $backupPath"

$actions=@();if($DisableUnconstrainedDelegation){$actions+='disable unconstrained delegation'};if($ClearConstrainedDelegation){$actions+='clear constrained-delegation targets'};if($ClearResourceBasedConstrainedDelegation){$actions+='clear resource-based constrained delegation'}
if(-not $DryRun -and -not $Yes){$answer=Read-Host ("Proceed for {0} {1}: {2}? [y/N]" -f $ObjectType,$Identity,($actions -join '; '));if($answer -notmatch '^(?i)y(es)?$'){Write-Log '[CANCELLED] No changes were made.';exit $ExitCancelled}}

try{
    if($DisableUnconstrainedDelegation){
        if($ObjectType -eq 'Computer'){Invoke-Step "Disable unconstrained delegation on '$Identity'" {Set-ADComputer -Identity $target.DistinguishedName -TrustedForDelegation $false}}
        else{Invoke-Step "Disable unconstrained delegation on '$Identity'" {Set-ADUser -Identity $target.DistinguishedName -TrustedForDelegation $false}}
    }
    if($ClearConstrainedDelegation){Invoke-Step "Clear msDS-AllowedToDelegateTo on '$Identity'" {Set-ADObject -Identity $target.DistinguishedName -Clear 'msDS-AllowedToDelegateTo'}}
    if($ClearResourceBasedConstrainedDelegation){Invoke-Step "Clear resource-based constrained delegation on '$Identity'" {Set-ADObject -Identity $target.DistinguishedName -Clear 'msDS-AllowedToActOnBehalfOfOtherIdentity'}}
}catch{Write-Log "[FAILED] $($_.Exception.Message)";exit $ExitActionFailure}
if($DryRun){Write-Log '[COMPLETE] Dry-run completed.';exit 0}

$verifyFailed=$false
try{
    if($ObjectType -eq 'Computer'){$after=Get-ADComputer -Identity $target.DistinguishedName -Properties TrustedForDelegation,msDS-AllowedToDelegateTo,msDS-AllowedToActOnBehalfOfOtherIdentity}
    else{$after=Get-ADUser -Identity $target.DistinguishedName -Properties TrustedForDelegation,msDS-AllowedToDelegateTo,msDS-AllowedToActOnBehalfOfOtherIdentity}
    Write-Log ("[VERIFY] TrustedForDelegation={0}; ConstrainedTargets={1}; RBCDPresent={2}" -f $after.TrustedForDelegation,@($after.'msDS-AllowedToDelegateTo').Count,[bool]$after.'msDS-AllowedToActOnBehalfOfOtherIdentity')
    if($DisableUnconstrainedDelegation -and $after.TrustedForDelegation){$verifyFailed=$true}
    if($ClearConstrainedDelegation -and @($after.'msDS-AllowedToDelegateTo').Count -gt 0){$verifyFailed=$true}
    if($ClearResourceBasedConstrainedDelegation -and $after.'msDS-AllowedToActOnBehalfOfOtherIdentity'){$verifyFailed=$true}
}catch{Write-Log "[VERIFY-FAILED] $($_.Exception.Message)";$verifyFailed=$true}
if($verifyFailed){exit $ExitVerificationFailure}
Write-Log '[COMPLETE] Delegation repair and verification completed.'
exit 0
