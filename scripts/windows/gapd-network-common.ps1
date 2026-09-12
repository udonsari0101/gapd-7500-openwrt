Set-StrictMode -Version Latest

$script:GapdTargetPrefix = '192.168.219.1/32'
$script:GapdTaskName = 'GAPD-7500 Network Route Watcher'

function Get-GapdStateRoot {
    if ([string]::IsNullOrWhiteSpace($env:ProgramData)) {
        throw 'ProgramData is not available.'
    }
    Join-Path $env:ProgramData 'GAPD-7500-Network'
}

function Get-GapdDefaultStatePath {
    Join-Path (Get-GapdStateRoot) 'state.json'
}

function Get-GapdDefaultLogDirectory {
    Join-Path (Get-GapdStateRoot) 'logs'
}

function Test-GapdAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-GapdAdministrator {
    if (-not (Test-GapdAdministrator)) {
        throw 'Administrator rights are required. Open PowerShell with Run as administrator and run this script again.'
    }
}

function New-GapdLogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    Join-Path $LogDirectory ("{0}-{1}.log" -f $stamp, $Operation)
}

function Write-GapdLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Write-GapdSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Add-Content -LiteralPath $LogFile -Value "`r`n===== $Label =====" -Encoding UTF8
    Add-Content -LiteralPath $LogFile -Value ('Timestamp: {0}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK')) -Encoding UTF8

    $captures = @(
        @{ Name = 'Get-NetAdapter'; Command = { Get-NetAdapter | Format-Table -Auto Name, InterfaceDescription, Status, LinkSpeed, ifIndex, MacAddress | Out-String -Width 240 } },
        @{ Name = 'Get-NetIPConfiguration'; Command = { Get-NetIPConfiguration | Format-List InterfaceAlias, InterfaceIndex, IPv4Address, IPv4DefaultGateway, DNSServer | Out-String -Width 240 } },
        @{ Name = 'Get-NetRoute -AddressFamily IPv4'; Command = { Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix, RouteMetric | Format-Table -Auto ifIndex, InterfaceAlias, DestinationPrefix, NextHop, RouteMetric, Protocol, PolicyStore, State | Out-String -Width 240 } },
        @{ Name = 'Get-NetNeighbor -AddressFamily IPv4'; Command = { Get-NetNeighbor -AddressFamily IPv4 | Sort-Object InterfaceIndex, IPAddress | Format-Table -Auto ifIndex, InterfaceAlias, IPAddress, LinkLayerAddress, State, PolicyStore | Out-String -Width 240 } },
        @{ Name = 'route print -4'; Command = { route.exe print -4 | Out-String -Width 240 } }
    )

    foreach ($capture in $captures) {
        Add-Content -LiteralPath $LogFile -Value ("`r`n--- {0} ---" -f $capture.Name) -Encoding UTF8
        try {
            $text = & $capture.Command
            Add-Content -LiteralPath $LogFile -Value $text -Encoding UTF8
        }
        catch {
            Add-Content -LiteralPath $LogFile -Value ('CAPTURE ERROR: {0}' -f $_.Exception.Message) -Encoding UTF8
        }
    }
}

function Resolve-GapdEthernetAdapter {
    param(
        [string]$EthernetAlias,
        [string]$InterfaceGuid,
        [int]$InterfaceIndexHint = 0,
        [string]$SourceAddress = '192.168.219.100',
        [string]$AdapterDescription = 'Realtek USB GbE Family Controller #2'
    )

    $allAdapters = @(Get-NetAdapter -ErrorAction Stop)

    if (-not [string]::IsNullOrWhiteSpace($InterfaceGuid)) {
        $normalized = $InterfaceGuid.Trim('{}')
        $matches = @($allAdapters | Where-Object { $_.InterfaceGuid.ToString().Trim('{}') -ieq $normalized })
        if ($matches.Count -eq 1) { return $matches[0] }

        if ($InterfaceIndexHint -le 0) {
            $defaultStatePath = Get-GapdDefaultStatePath
            if (Test-Path -LiteralPath $defaultStatePath) {
                $savedState = Get-Content -LiteralPath $defaultStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$savedState.InterfaceGuid -eq $InterfaceGuid) {
                    $InterfaceIndexHint = [int]$savedState.EthernetInterfaceIndexAtEnable
                    if ([string]::IsNullOrWhiteSpace($EthernetAlias)) {
                        $EthernetAlias = [string]$savedState.EthernetAliasAtEnable
                    }
                }
            }
        }

        if ($InterfaceIndexHint -gt 0) {
            return [pscustomobject]@{
                Name          = if ([string]::IsNullOrWhiteSpace($EthernetAlias)) { 'GAPD Ethernet adapter (not present)' } else { $EthernetAlias }
                ifIndex       = $InterfaceIndexHint
                Status        = 'NotPresent'
                InterfaceGuid = $InterfaceGuid
            }
        }
        throw "No unique network adapter has InterfaceGuid $InterfaceGuid, and no saved interface-index hint is available."
    }

    if (-not [string]::IsNullOrWhiteSpace($EthernetAlias)) {
        $matches = @($allAdapters | Where-Object { $_.Name -eq $EthernetAlias })
        if ($matches.Count -eq 1) { return $matches[0] }
        throw "No unique network adapter has alias '$EthernetAlias'."
    }

    $addressMatches = @()
    foreach ($address in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        if ($address.IPAddress -eq $SourceAddress) {
            $addressMatches += @($allAdapters | Where-Object { $_.ifIndex -eq $address.InterfaceIndex })
        }
    }
    $addressMatches = @($addressMatches | Sort-Object ifIndex -Unique)
    if ($addressMatches.Count -eq 1) { return $addressMatches[0] }

    $descriptionMatches = @($allAdapters | Where-Object { $_.InterfaceDescription -eq $AdapterDescription })
    if ($descriptionMatches.Count -eq 1) { return $descriptionMatches[0] }

    throw 'Unable to resolve the GAPD Ethernet adapter. Pass -EthernetAlias explicitly.'
}

function Get-GapdWifiDefaultRoutes {
    param([string]$WifiAlias = 'Wi-Fi')
    @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -eq $WifiAlias })
}

function Get-GapdEthernetDefaultRoutes {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [ValidateSet('ActiveStore', 'PersistentStore')]
        [string]$PolicyStore = 'ActiveStore'
    )
    @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -PolicyStore $PolicyStore -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceIndex -eq $Adapter.ifIndex })
}

function Get-GapdHostRoutes {
    param(
        [ValidateSet('ActiveStore', 'PersistentStore')]
        [string]$PolicyStore = 'ActiveStore'
    )
    @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $script:GapdTargetPrefix -PolicyStore $PolicyStore -ErrorAction SilentlyContinue)
}

function Test-GapdLayer2Presence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetAddress,

        [Parameter(Mandatory = $true)]
        [string]$SourceAddress
    )

    if (-not ('GapdNativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GapdNativeMethods
{
    [DllImport("iphlpapi.dll", ExactSpelling = true)]
    public static extern int SendARP(uint destinationIp, uint sourceIp, byte[] macAddress, ref int physicalAddressLength);
}

'@
    }

    $targetBytes = [Net.IPAddress]::Parse($TargetAddress).GetAddressBytes()
    $sourceBytes = [Net.IPAddress]::Parse($SourceAddress).GetAddressBytes()
    $target = [BitConverter]::ToUInt32($targetBytes, 0)
    $source = [BitConverter]::ToUInt32($sourceBytes, 0)
    $mac = New-Object byte[] 32
    $length = 32
    $returnCode = [GapdNativeMethods]::SendARP($target, $source, $mac, [ref]$length)

    [pscustomobject]@{
        Succeeded  = ($returnCode -eq 0 -and $length -gt 0)
        ReturnCode = $returnCode
        MacAddress = if ($returnCode -eq 0 -and $length -gt 0) {
            (($mac[0..($length - 1)] | ForEach-Object { $_.ToString('X2') }) -join '-')
        }
        else { $null }
    }
}

function Get-GapdTestConnectionSourceAddress {
    param([Parameter(Mandatory = $true)]$TestConnectionResult)

    $source = @($TestConnectionResult.SourceAddress | Select-Object -First 1)
    if ($source.Count -eq 0 -or $null -eq $source[0]) { return '' }
    if ($source[0] -is [string]) { return [string]$source[0] }
    if ($null -ne $source[0].PSObject.Properties['IPAddress']) {
        return [string]$source[0].IPAddress
    }
    return [string]$source[0]
}

function Get-GapdNetworkStatus {
    param(
        [string]$EthernetAlias,
        [string]$InterfaceGuid,
        [int]$InterfaceIndexHint = 0,
        [string]$WifiAlias = 'Wi-Fi',
        [string]$TargetAddress = '192.168.219.1',
        [string]$SourceAddress = '192.168.219.100',
        [int]$PrefixLength = 24,
        [switch]$SkipLayer2Probe
    )

    $adapter = Resolve-GapdEthernetAdapter -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $InterfaceIndexHint -SourceAddress $SourceAddress
    $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $exactAddresses = @($addresses | Where-Object { $_.IPAddress -eq $SourceAddress -and $_.PrefixLength -eq $PrefixLength })
    $adapterUp = ($adapter.Status -eq 'Up')
    $addressOk = ($exactAddresses.Count -eq 1)
    $wifiDefaults = @(Get-GapdWifiDefaultRoutes -WifiAlias $WifiAlias)
    $ethernetDefaults = @(Get-GapdEthernetDefaultRoutes -Adapter $adapter -PolicyStore ActiveStore)
    $persistentEthernetDefaults = @(Get-GapdEthernetDefaultRoutes -Adapter $adapter -PolicyStore PersistentStore)
    $allHostRoutes = @(Get-GapdHostRoutes -PolicyStore ActiveStore)
    $persistentHostRoutes = @(Get-GapdHostRoutes -PolicyStore PersistentStore)
    $localHostRoutes = @($allHostRoutes | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex })
    $persistentLocalHostRoutes = @($persistentHostRoutes | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex })
    $otherHostRoutes = @($allHostRoutes | Where-Object { $_.InterfaceIndex -ne $adapter.ifIndex })
    $persistentOtherHostRoutes = @($persistentHostRoutes | Where-Object { $_.InterfaceIndex -ne $adapter.ifIndex })
    $correctHostRoutes = @($localHostRoutes | Where-Object { $_.NextHop -eq '0.0.0.0' })

    $l2Attempted = $false
    $l2Succeeded = $false
    $l2ReturnCode = $null
    if ($adapterUp -and $addressOk -and -not $SkipLayer2Probe) {
        $l2Attempted = $true
        $probe = Test-GapdLayer2Presence -TargetAddress $TargetAddress -SourceAddress $SourceAddress
        $l2Succeeded = $probe.Succeeded
        $l2ReturnCode = $probe.ReturnCode
    }

    $readyForHostRoute = $adapterUp -and $addressOk -and $l2Succeeded -and
        ($wifiDefaults.Count -gt 0) -and ($otherHostRoutes.Count -eq 0) -and ($persistentOtherHostRoutes.Count -eq 0)
    $routeIsActive = ($localHostRoutes.Count -eq 1 -and $correctHostRoutes.Count -eq 1 -and $persistentLocalHostRoutes.Count -eq 0)
    $routeStateOk = if ($readyForHostRoute) {
        $routeIsActive
    }
    else {
        $localHostRoutes.Count -eq 0 -and $persistentLocalHostRoutes.Count -eq 0
    }
    $compliant = $routeStateOk -and ($ethernetDefaults.Count -eq 0) -and ($persistentEthernetDefaults.Count -eq 0) -and
        ($wifiDefaults.Count -gt 0) -and ($otherHostRoutes.Count -eq 0) -and ($persistentOtherHostRoutes.Count -eq 0)
    $watcherTaskErrors = @()
    $watcherTask = Get-ScheduledTask -TaskName $script:GapdTaskName -ErrorAction SilentlyContinue -ErrorVariable +watcherTaskErrors
    $watcherTaskQuerySucceeded = ($watcherTaskErrors.Count -eq 0)

    [pscustomobject]@{
        Timestamp                      = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK')
        Compliant                      = $compliant
        DesiredState                   = if ($readyForHostRoute) { 'EthernetTargetActive' } else { 'WifiFallback' }
        EthernetAlias                  = $adapter.Name
        EthernetInterfaceGuid          = $adapter.InterfaceGuid.ToString()
        EthernetInterfaceIndex         = $adapter.ifIndex
        EthernetStatus                 = $adapter.Status.ToString()
        RequiredIPv4Present            = $addressOk
        Layer2ProbeAttempted            = $l2Attempted
        Layer2ProbeSucceeded            = $l2Succeeded
        Layer2ProbeReturnCode           = $l2ReturnCode
        WifiDefaultRouteCount           = $wifiDefaults.Count
        EthernetDefaultRouteCount       = $ethernetDefaults.Count
        PersistentEthernetDefaultCount  = $persistentEthernetDefaults.Count
        EthernetTargetHostRouteCount    = $localHostRoutes.Count
        PersistentTargetHostRouteCount  = $persistentLocalHostRoutes.Count
        ConflictingTargetHostRouteCount = $otherHostRoutes.Count + $persistentOtherHostRoutes.Count
        TargetHostRouteCorrect          = $routeIsActive
        AutomationEnabled               = if ($watcherTaskQuerySucceeded) { $null -ne $watcherTask } else { $null }
        WatcherTaskState                = if ($null -ne $watcherTask) {
            $watcherTask.State.ToString()
        }
        elseif ($watcherTaskQuerySucceeded) {
            'NotInstalled'
        }
        else {
            'UnknownAccessDenied'
        }
    }
}

function Remove-GapdHostRoute {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    $removed = 0
    foreach ($store in @('PersistentStore', 'ActiveStore')) {
        $routes = @(Get-GapdHostRoutes -PolicyStore $store | Where-Object { $_.InterfaceIndex -eq $Adapter.ifIndex })
        foreach ($route in $routes) {
            Write-GapdLog -LogFile $LogFile -Message ("Removing target host route from {0}, interface {1}: {2} via {3}" -f $store, $Adapter.ifIndex, $route.DestinationPrefix, $route.NextHop)
            Remove-NetRoute -AddressFamily IPv4 -DestinationPrefix $route.DestinationPrefix `
                -InterfaceIndex $Adapter.ifIndex -NextHop $route.NextHop -PolicyStore $store `
                -Confirm:$false -ErrorAction Stop
            $removed++
        }
    }
    $removed
}

function Remove-GapdEthernetDefaultRoute {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    $removed = 0
    foreach ($store in @('PersistentStore', 'ActiveStore')) {
        $routes = @(Get-GapdEthernetDefaultRoutes -Adapter $Adapter -PolicyStore $store)
        foreach ($route in $routes) {
            Write-GapdLog -LogFile $LogFile -Message ("Removing Ethernet default route from {0}, interface {1}: next hop {2}" -f $store, $Adapter.ifIndex, $route.NextHop)
            Remove-NetRoute -AddressFamily IPv4 -DestinationPrefix $route.DestinationPrefix `
                -InterfaceIndex $Adapter.ifIndex -NextHop $route.NextHop -PolicyStore $store `
                -Confirm:$false -ErrorAction Stop
            $removed++
        }
    }
    $removed
}

function Invoke-GapdRouteReconcile {
    param(
        [string]$EthernetAlias,
        [string]$InterfaceGuid,
        [int]$InterfaceIndexHint = 0,
        [string]$WifiAlias = 'Wi-Fi',
        [string]$TargetAddress = '192.168.219.1',
        [string]$SourceAddress = '192.168.219.100',
        [int]$PrefixLength = 24,
        [int]$RouteMetric = 1,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    $adapter = Resolve-GapdEthernetAdapter -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $InterfaceIndexHint -SourceAddress $SourceAddress
    $before = Get-GapdNetworkStatus -EthernetAlias $adapter.Name -InterfaceGuid $adapter.InterfaceGuid.ToString() -InterfaceIndexHint $adapter.ifIndex -WifiAlias $WifiAlias -TargetAddress $TargetAddress -SourceAddress $SourceAddress -PrefixLength $PrefixLength
    $needsHostRoute = ($before.DesiredState -eq 'EthernetTargetActive')
    $routeNeedsChange = if ($needsHostRoute) {
        -not $before.TargetHostRouteCorrect -or $before.EthernetTargetHostRouteCount -ne 1
    }
    else {
        $before.EthernetTargetHostRouteCount -gt 0
    }
    $requiresChange = $routeNeedsChange -or ($before.EthernetDefaultRouteCount -gt 0) -or ($before.PersistentEthernetDefaultCount -gt 0)

    if (-not $requiresChange) {
        $before | Add-Member -NotePropertyName Changed -NotePropertyValue $false
        $before | Add-Member -NotePropertyName Action -NotePropertyValue 'NoChange'
        return $before
    }

    Write-GapdSnapshot -LogFile $LogFile -Label 'BEFORE ROUTE RECONCILE'
    $removedDefaults = Remove-GapdEthernetDefaultRoute -Adapter $adapter -LogFile $LogFile
    $action = 'NoChange'

    if ($needsHostRoute) {
        if ($routeNeedsChange) {
            [void](Remove-GapdHostRoute -Adapter $adapter -LogFile $LogFile)
            Write-GapdLog -LogFile $LogFile -Message ("Adding ACTIVE-STORE on-link route {0} on interface {1}." -f $script:GapdTargetPrefix, $adapter.ifIndex)
            New-NetRoute -AddressFamily IPv4 -DestinationPrefix $script:GapdTargetPrefix `
                -InterfaceIndex $adapter.ifIndex -NextHop '0.0.0.0' -RouteMetric $RouteMetric `
                -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
            $action = 'HostRouteAdded'
        }
    }
    else {
        if ($before.EthernetTargetHostRouteCount -gt 0 -or $before.PersistentTargetHostRouteCount -gt 0) {
            [void](Remove-GapdHostRoute -Adapter $adapter -LogFile $LogFile)
            $action = 'HostRouteRemovedFailClosed'
        }
    }

    if ($removedDefaults -gt 0 -and $action -eq 'NoChange') {
        $action = 'EthernetDefaultRouteRemoved'
    }

    $after = Get-GapdNetworkStatus -EthernetAlias $adapter.Name -InterfaceGuid $adapter.InterfaceGuid.ToString() -InterfaceIndexHint $adapter.ifIndex -WifiAlias $WifiAlias -TargetAddress $TargetAddress -SourceAddress $SourceAddress -PrefixLength $PrefixLength
    $after | Add-Member -NotePropertyName Changed -NotePropertyValue $true
    $after | Add-Member -NotePropertyName Action -NotePropertyValue $action
    Write-GapdLog -LogFile $LogFile -Message ("Reconcile action={0}; desired={1}; compliant={2}." -f $action, $after.DesiredState, $after.Compliant)
    Write-GapdSnapshot -LogFile $LogFile -Label 'AFTER ROUTE RECONCILE'
    $after
}

function Convert-GapdRouteForBackup {
    param(
        [Parameter(Mandatory = $true)]$Route,
        [ValidateSet('ActiveStore', 'PersistentStore')]
        [string]$PolicyStore = 'ActiveStore'
    )
    [pscustomobject]@{
        DestinationPrefix = $Route.DestinationPrefix
        NextHop           = $Route.NextHop
        RouteMetric       = [int]$Route.RouteMetric
        Protocol          = $Route.Protocol.ToString()
        PolicyStore       = $PolicyStore
    }
}

function Restore-GapdDefaultRoutes {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [object[]]$RouteBackups,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    foreach ($backup in @($RouteBackups)) {
        $existing = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $backup.DestinationPrefix -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceIndex -eq $Adapter.ifIndex -and $_.NextHop -eq $backup.NextHop })
        if ($existing.Count -gt 0) { continue }

        $store = if ($backup.PolicyStore -match 'PersistentStore') { 'PersistentStore' } else { 'ActiveStore' }
        Write-GapdLog -LogFile $LogFile -Message ("Restoring original Ethernet default route via {0} in {1}." -f $backup.NextHop, $store)
        New-NetRoute -AddressFamily IPv4 -DestinationPrefix $backup.DestinationPrefix `
            -InterfaceIndex $Adapter.ifIndex -NextHop $backup.NextHop `
            -RouteMetric ([int]$backup.RouteMetric) -PolicyStore $store -ErrorAction Stop | Out-Null
    }
}
