[CmdletBinding()]
param(
    [string]$EthernetAlias,
    [string]$WifiAlias = 'Wi-Fi',
    [string]$TargetAddress = '192.168.219.1',
    [string]$SourceAddress = '192.168.219.100',
    [ValidateRange(1, 32)]
    [int]$PrefixLength = 24,
    [ValidateRange(1, 9999)]
    [int]$RouteMetric = 1,
    [string]$StatePath,
    [string]$LogDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gapd-network-common.ps1')

Assert-GapdAdministrator
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Get-GapdDefaultStatePath }
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = Get-GapdDefaultLogDirectory }

$stateDirectory = Split-Path -Parent $StatePath
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$logFile = New-GapdLogFile -LogDirectory $LogDirectory -Operation 'enable'
Write-GapdLog -LogFile $logFile -Message 'Enable operation started.'
Write-GapdSnapshot -LogFile $logFile -Label 'BEFORE ENABLE'

$adapter = Resolve-GapdEthernetAdapter -EthernetAlias $EthernetAlias -SourceAddress $SourceAddress
$guid = $adapter.InterfaceGuid.ToString()
$initialStatus = Get-GapdNetworkStatus -InterfaceGuid $guid -WifiAlias $WifiAlias -TargetAddress $TargetAddress -SourceAddress $SourceAddress -PrefixLength $PrefixLength

if ($initialStatus.WifiDefaultRouteCount -lt 1) {
    throw "No IPv4 default route exists on '$WifiAlias'. No route was added."
}
if ($initialStatus.ConflictingTargetHostRouteCount -gt 0) {
    throw "A conflicting $($script:GapdTargetPrefix) route exists on another interface. Remove it explicitly before enabling."
}
if ($initialStatus.DesiredState -ne 'EthernetTargetActive') {
    Write-GapdLog -LogFile $logFile -Level WARN -Message ("Ethernet is not ready for the target route (status={0}; addressOk={1}; l2={2}). Automation will start in Wi-Fi fallback mode." -f `
        $initialStatus.EthernetStatus, $initialStatus.RequiredIPv4Present, $initialStatus.Layer2ProbeSucceeded)
}

$existingState = $null
if (Test-Path -LiteralPath $StatePath) {
    $existingState = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($existingState.InterfaceGuid -ne $guid) {
        throw 'Existing state belongs to a different Ethernet adapter. Run disable-gapd-network.ps1 first.'
    }
}

if ($null -eq $existingState) {
    $defaultBackups = @()
    $hostRouteAudit = @()
    foreach ($store in @('PersistentStore', 'ActiveStore')) {
        $defaultBackups += @(Get-GapdEthernetDefaultRoutes -Adapter $adapter -PolicyStore $store |
            ForEach-Object { Convert-GapdRouteForBackup -Route $_ -PolicyStore $store })
        $hostRouteAudit += @(Get-GapdHostRoutes -PolicyStore $store | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex } |
            ForEach-Object { Convert-GapdRouteForBackup -Route $_ -PolicyStore $store })
    }
    $state = [pscustomobject]@{
        Version                         = 1
        EnabledAt                      = (Get-Date -Format 'o')
        InterfaceGuid                  = $guid
        EthernetAliasAtEnable          = $adapter.Name
        EthernetInterfaceIndexAtEnable = $adapter.ifIndex
        WifiAlias                      = $WifiAlias
        TargetAddress                  = $TargetAddress
        SourceAddress                  = $SourceAddress
        PrefixLength                   = $PrefixLength
        RouteMetric                    = $RouteMetric
        RemovedEthernetDefaultRoutes   = $defaultBackups
        RemovedHostRoutesAuditOnly     = $hostRouteAudit
        Note                            = 'Host routes are recorded for audit but intentionally never restored by disable; stale target /32 routes are unsafe.'
    }
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    Write-GapdLog -LogFile $logFile -Message ("Rollback state saved to {0}." -f $StatePath)
}

try {
    if (Get-ScheduledTask -TaskName $script:GapdTaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $script:GapdTaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $script:GapdTaskName -Confirm:$false -ErrorAction Stop
    }

    # Remove a manual/persistent route first. Reconcile will recreate only ActiveStore.
    [void](Remove-GapdHostRoute -Adapter $adapter -LogFile $logFile)
    [void](Invoke-GapdRouteReconcile -InterfaceGuid $guid -WifiAlias $WifiAlias -TargetAddress $TargetAddress `
        -SourceAddress $SourceAddress -PrefixLength $PrefixLength -RouteMetric $RouteMetric -LogFile $logFile)

    $watcherPath = Join-Path $PSScriptRoot 'watch-gapd-network.ps1'
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $watcherPath),
        '-InterfaceGuid', ('"{0}"' -f $guid),
        '-InterfaceIndexHint', $adapter.ifIndex,
        '-WifiAlias', ('"{0}"' -f $WifiAlias),
        '-TargetAddress', $TargetAddress,
        '-SourceAddress', $SourceAddress,
        '-PrefixLength', $PrefixLength,
        '-RouteMetric', $RouteMetric,
        '-PollSeconds', '1',
        '-LogDirectory', ('"{0}"' -f $LogDirectory)
    ) -join ' '

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $triggers = @(
        (New-ScheduledTaskTrigger -AtStartup),
        (New-ScheduledTaskTrigger -AtLogOn)
    )
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $script:GapdTaskName -Action $action -Trigger $triggers `
        -Principal $principal -Settings $settings `
        -Description 'Fail-closed GAPD-7500 /32 route watcher. Removes the route whenever Ethernet link/address/L2 checks fail.' | Out-Null
    Start-ScheduledTask -TaskName $script:GapdTaskName

    Start-Sleep -Seconds 2
    $finalStatus = Get-GapdNetworkStatus -InterfaceGuid $guid -WifiAlias $WifiAlias -TargetAddress $TargetAddress -SourceAddress $SourceAddress -PrefixLength $PrefixLength
    Write-GapdSnapshot -LogFile $logFile -Label 'AFTER ENABLE'
    $finalStatus | Format-List
    if (-not $finalStatus.Compliant -or -not $finalStatus.AutomationEnabled) {
        throw 'The enabled state did not pass final verification.'
    }
    Write-GapdLog -LogFile $logFile -Message ("Enable completed. Scheduled task '{0}' is installed and running." -f $script:GapdTaskName)
}
catch {
    Write-GapdLog -LogFile $logFile -Level ERROR -Message ('Enable failed: {0}' -f $_.Exception.Message)
    try {
        if (Get-ScheduledTask -TaskName $script:GapdTaskName -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $script:GapdTaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $script:GapdTaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        [void](Remove-GapdHostRoute -Adapter $adapter -LogFile $logFile)
        if (Test-Path -LiteralPath $StatePath) {
            $rollbackState = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            Restore-GapdDefaultRoutes -Adapter $adapter -RouteBackups @($rollbackState.RemovedEthernetDefaultRoutes) -LogFile $logFile
        }
        Write-GapdSnapshot -LogFile $logFile -Label 'AFTER FAILED ENABLE CLEANUP'
    }
    catch {
        Write-GapdLog -LogFile $logFile -Level ERROR -Message ('Enable cleanup failed: {0}' -f $_.Exception.Message)
    }
    throw
}
