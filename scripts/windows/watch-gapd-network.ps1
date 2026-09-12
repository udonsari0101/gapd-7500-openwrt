[CmdletBinding()]
param(
    [string]$EthernetAlias,
    [string]$InterfaceGuid,
    [int]$InterfaceIndexHint = 0,
    [string]$WifiAlias = 'Wi-Fi',
    [string]$TargetAddress = '192.168.219.1',
    [string]$SourceAddress = '192.168.219.100',
    [ValidateRange(1, 32)]
    [int]$PrefixLength = 24,
    [ValidateRange(1, 9999)]
    [int]$RouteMetric = 1,
    [ValidateRange(1, 60)]
    [int]$PollSeconds = 1,
    [string]$LogDirectory,
    [switch]$Once,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gapd-network-common.ps1')

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Get-GapdDefaultLogDirectory
}
$defaultStatePath = Get-GapdDefaultStatePath
if ([string]::IsNullOrWhiteSpace($InterfaceGuid) -and (Test-Path -LiteralPath $defaultStatePath)) {
    $savedState = Get-Content -LiteralPath $defaultStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $InterfaceGuid = [string]$savedState.InterfaceGuid
    if ([string]::IsNullOrWhiteSpace($EthernetAlias)) { $EthernetAlias = [string]$savedState.EthernetAliasAtEnable }
    $InterfaceIndexHint = [int]$savedState.EthernetInterfaceIndexAtEnable
}
$logFile = New-GapdLogFile -LogDirectory $LogDirectory -Operation 'watch'

if ($DryRun) {
    $status = Get-GapdNetworkStatus -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $InterfaceIndexHint -WifiAlias $WifiAlias `
        -TargetAddress $TargetAddress -SourceAddress $SourceAddress -PrefixLength $PrefixLength
    $status | Format-List
    if ($status.DesiredState -eq 'EthernetTargetActive' -and -not $status.TargetHostRouteCorrect) {
        Write-Host 'DRY RUN: the active-store Ethernet host route would be added.'
    }
    elseif ($status.DesiredState -eq 'WifiFallback' -and $status.EthernetTargetHostRouteCount -gt 0) {
        Write-Host 'DRY RUN: the Ethernet host route would be removed.'
    }
    else {
        Write-Host 'DRY RUN: no host-route transition is needed.'
    }
    exit 0
}

Assert-GapdAdministrator

$createdNew = $false
$mutex = New-Object Threading.Mutex($true, 'Global\Gapd7500NetworkRouteWatcher', [ref]$createdNew)
if (-not $createdNew) {
    Write-GapdLog -LogFile $logFile -Level WARN -Message 'Another watcher instance is already running; this instance will exit.'
    $mutex.Dispose()
    exit 0
}

Write-GapdLog -LogFile $logFile -Message ("Watcher started. PollSeconds={0}; InterfaceGuid={1}; target={2}." -f $PollSeconds, $InterfaceGuid, $script:GapdTargetPrefix)
$lastSummary = $null

try {
    do {
        try {
            $status = Invoke-GapdRouteReconcile -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $InterfaceIndexHint `
                -WifiAlias $WifiAlias -TargetAddress $TargetAddress -SourceAddress $SourceAddress `
                -PrefixLength $PrefixLength -RouteMetric $RouteMetric -LogFile $logFile

            $summary = '{0}|{1}|{2}|{3}|{4}' -f $status.DesiredState, $status.EthernetStatus, `
                $status.RequiredIPv4Present, $status.Layer2ProbeSucceeded, $status.TargetHostRouteCorrect
            if ($summary -ne $lastSummary) {
                Write-GapdLog -LogFile $logFile -Message ("State transition: desired={0}; adapter={1}; addressOk={2}; l2={3}; route={4}; compliant={5}." -f `
                    $status.DesiredState, $status.EthernetStatus, $status.RequiredIPv4Present, `
                    $status.Layer2ProbeSucceeded, $status.TargetHostRouteCorrect, $status.Compliant)
                $lastSummary = $summary
            }
        }
        catch {
            Write-GapdLog -LogFile $logFile -Level ERROR -Message ('Reconcile failed: {0}' -f $_.Exception.Message)
            try {
                $adapter = Resolve-GapdEthernetAdapter -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $InterfaceIndexHint -SourceAddress $SourceAddress
                $count = Remove-GapdHostRoute -Adapter $adapter -LogFile $logFile
                Write-GapdLog -LogFile $logFile -Level WARN -Message ("Fail-closed cleanup removed {0} target host route(s)." -f $count)
            }
            catch {
                Write-GapdLog -LogFile $logFile -Level ERROR -Message ('Fail-closed cleanup also failed: {0}' -f $_.Exception.Message)
            }
        }

        if (-not $Once) { Start-Sleep -Seconds $PollSeconds }
    } while (-not $Once)
}
finally {
    if (-not $Once) {
        try {
            $adapter = Resolve-GapdEthernetAdapter -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $InterfaceIndexHint -SourceAddress $SourceAddress
            $count = Remove-GapdHostRoute -Adapter $adapter -LogFile $logFile
            Write-GapdLog -LogFile $logFile -Level WARN -Message ("Watcher shutdown cleanup removed {0} target host route(s)." -f $count)
        }
        catch {
            Write-GapdLog -LogFile $logFile -Level ERROR -Message ('Watcher shutdown cleanup failed: {0}' -f $_.Exception.Message)
        }
    }
    Write-GapdLog -LogFile $logFile -Message 'Watcher stopped.'
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
