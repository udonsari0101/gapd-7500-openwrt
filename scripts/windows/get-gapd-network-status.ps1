[CmdletBinding()]
param(
    [string]$EthernetAlias,
    [string]$InterfaceGuid,
    [string]$WifiAlias = 'Wi-Fi',
    [string]$TargetAddress = '192.168.219.1',
    [string]$SourceAddress = '192.168.219.100',
    [ValidateRange(1, 32)]
    [int]$PrefixLength = 24,
    [string]$StatePath,
    [string]$LogDirectory,
    [switch]$DetailedTests,
    [switch]$WriteSnapshot,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gapd-network-common.ps1')

if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Get-GapdDefaultStatePath }
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = Get-GapdDefaultLogDirectory }

$interfaceIndexHint = 0
$stateFilePresent = Test-Path -LiteralPath $StatePath
if ($stateFilePresent) {
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($InterfaceGuid)) { $InterfaceGuid = [string]$state.InterfaceGuid }
    if ([string]::IsNullOrWhiteSpace($EthernetAlias)) { $EthernetAlias = [string]$state.EthernetAliasAtEnable }
    $interfaceIndexHint = [int]$state.EthernetInterfaceIndexAtEnable
    if (-not $PSBoundParameters.ContainsKey('WifiAlias')) { $WifiAlias = [string]$state.WifiAlias }
    if (-not $PSBoundParameters.ContainsKey('TargetAddress')) { $TargetAddress = [string]$state.TargetAddress }
    if (-not $PSBoundParameters.ContainsKey('SourceAddress')) { $SourceAddress = [string]$state.SourceAddress }
    if (-not $PSBoundParameters.ContainsKey('PrefixLength')) { $PrefixLength = [int]$state.PrefixLength }
}

$status = Get-GapdNetworkStatus -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $interfaceIndexHint -WifiAlias $WifiAlias `
    -TargetAddress $TargetAddress -SourceAddress $SourceAddress -PrefixLength $PrefixLength
$status | Add-Member -NotePropertyName AutomationStateFilePresent -NotePropertyValue $stateFilePresent

if ($DetailedTests) {
    $internet = Test-NetConnection 1.1.1.1 -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue
    $target = Test-NetConnection $TargetAddress -Port 80 -InformationLevel Detailed -WarningAction SilentlyContinue
    $status | Add-Member -NotePropertyName InternetTcp443Succeeded -NotePropertyValue ([bool]$internet.TcpTestSucceeded)
    $status | Add-Member -NotePropertyName InternetInterfaceAlias -NotePropertyValue ([string]$internet.InterfaceAlias)
    $status | Add-Member -NotePropertyName InternetSourceAddress -NotePropertyValue (Get-GapdTestConnectionSourceAddress -TestConnectionResult $internet)
    $status | Add-Member -NotePropertyName TargetTcp80Succeeded -NotePropertyValue ([bool]$target.TcpTestSucceeded)
    $status | Add-Member -NotePropertyName TargetInterfaceAlias -NotePropertyValue ([string]$target.InterfaceAlias)
    $status | Add-Member -NotePropertyName TargetSourceAddress -NotePropertyValue (Get-GapdTestConnectionSourceAddress -TestConnectionResult $target)
}

if ($WriteSnapshot) {
    $logFile = New-GapdLogFile -LogDirectory $LogDirectory -Operation 'status'
    Write-GapdSnapshot -LogFile $logFile -Label 'STATUS SNAPSHOT'
    Write-GapdLog -LogFile $logFile -Message (($status | ConvertTo-Json -Depth 5 -Compress))
    $status | Add-Member -NotePropertyName SnapshotLog -NotePropertyValue $logFile
}

if ($AsJson) { $status | ConvertTo-Json -Depth 5 } else { $status | Format-List }
