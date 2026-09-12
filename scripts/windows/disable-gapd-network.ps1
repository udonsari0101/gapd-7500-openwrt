[CmdletBinding()]
param(
    [string]$EthernetAlias,
    [string]$StatePath,
    [string]$LogDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gapd-network-common.ps1')

Assert-GapdAdministrator
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Get-GapdDefaultStatePath }
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = Get-GapdDefaultLogDirectory }

$logFile = New-GapdLogFile -LogDirectory $LogDirectory -Operation 'disable'
Write-GapdLog -LogFile $logFile -Message 'Disable/rollback operation started.'
Write-GapdSnapshot -LogFile $logFile -Label 'BEFORE DISABLE'

$state = $null
if (Test-Path -LiteralPath $StatePath) {
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if (Get-ScheduledTask -TaskName $script:GapdTaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $script:GapdTaskName -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Unregister-ScheduledTask -TaskName $script:GapdTaskName -Confirm:$false -ErrorAction Stop
    Write-GapdLog -LogFile $logFile -Message ("Scheduled task '{0}' was removed." -f $script:GapdTaskName)
}

$guid = if ($null -ne $state) { [string]$state.InterfaceGuid } else { $null }
$indexHint = if ($null -ne $state) { [int]$state.EthernetInterfaceIndexAtEnable } else { 0 }
$adapter = Resolve-GapdEthernetAdapter -EthernetAlias $EthernetAlias -InterfaceGuid $guid -InterfaceIndexHint $indexHint
[void](Remove-GapdHostRoute -Adapter $adapter -LogFile $logFile)

if ($null -ne $state) {
    Restore-GapdDefaultRoutes -Adapter $adapter -RouteBackups @($state.RemovedEthernetDefaultRoutes) -LogFile $logFile
    $archiveDirectory = Join-Path (Split-Path -Parent $StatePath) 'history'
    New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
    $archivePath = Join-Path $archiveDirectory ('state-disabled-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Move-Item -LiteralPath $StatePath -Destination $archivePath -Force
    Write-GapdLog -LogFile $logFile -Message ("Rollback state archived at {0}." -f $archivePath)
}

Write-GapdSnapshot -LogFile $logFile -Label 'AFTER DISABLE'
$remaining = @(Get-GapdHostRoutes -PolicyStore ActiveStore | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex })
$persistentRemaining = @(Get-GapdHostRoutes -PolicyStore PersistentStore | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex })
if ($remaining.Count -ne 0 -or $persistentRemaining.Count -ne 0) {
    throw 'Disable verification failed: a target host route remains on the Ethernet adapter.'
}
Write-GapdLog -LogFile $logFile -Message 'Disable/rollback completed; no GAPD target host route remains on Ethernet.'
