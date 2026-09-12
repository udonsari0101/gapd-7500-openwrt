[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Test1-WifiOnly', 'Test2-BothConnected', 'Test3-EthernetDisconnected', 'Test4-EthernetReconnected')]
    [string]$Scenario,
    [string]$EthernetAlias,
    [string]$InterfaceGuid,
    [string]$WifiAlias = 'Wi-Fi',
    [string]$TargetAddress = '192.168.219.1',
    [string]$SourceAddress = '192.168.219.100',
    [string]$StatePath,
    [string]$LogDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gapd-network-common.ps1')

if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Get-GapdDefaultStatePath }
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = Get-GapdDefaultLogDirectory }

$interfaceIndexHint = 0
if (Test-Path -LiteralPath $StatePath) {
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($InterfaceGuid)) { $InterfaceGuid = [string]$state.InterfaceGuid }
    if ([string]::IsNullOrWhiteSpace($EthernetAlias)) { $EthernetAlias = [string]$state.EthernetAliasAtEnable }
    $interfaceIndexHint = [int]$state.EthernetInterfaceIndexAtEnable
}

$logFile = New-GapdLogFile -LogDirectory $LogDirectory -Operation $Scenario
Write-GapdLog -LogFile $logFile -Message ("Starting verification scenario {0}." -f $Scenario)
Write-GapdSnapshot -LogFile $logFile -Label $Scenario

$status = Get-GapdNetworkStatus -EthernetAlias $EthernetAlias -InterfaceGuid $InterfaceGuid -InterfaceIndexHint $interfaceIndexHint -WifiAlias $WifiAlias `
    -TargetAddress $TargetAddress -SourceAddress $SourceAddress -PrefixLength 24
$internet = Test-NetConnection 1.1.1.1 -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue
$target = Test-NetConnection $TargetAddress -Port 80 -InformationLevel Detailed -WarningAction SilentlyContinue

$httpTitle = $null
$httpError = $null
try {
    $request = [Net.HttpWebRequest]::Create(("http://{0}/" -f $TargetAddress))
    $request.Timeout = 10000
    $request.ReadWriteTimeout = 10000
    $request.AllowAutoRedirect = $true
    $response = $request.GetResponse()
    $memory = New-Object IO.MemoryStream
    try {
        $response.GetResponseStream().CopyTo($memory)
        $content = [Text.Encoding]::UTF8.GetString($memory.ToArray())
    }
    finally {
        $memory.Dispose()
        $response.Dispose()
    }
    if ($content -match '(?is)<title[^>]*>\s*(.*?)\s*</title>') {
        $httpTitle = (($matches[1] -replace '\s+', ' ').Trim())
    }
}
catch {
    $httpError = $_.Exception.Message
}

$expectsEthernet = $Scenario -in @('Test2-BothConnected', 'Test4-EthernetReconnected')
$internetOk = [bool]$internet.TcpTestSucceeded -and $internet.InterfaceAlias -eq $WifiAlias
$targetOk = [bool]$target.TcpTestSucceeded
if ($expectsEthernet) {
    $routeOk = $status.DesiredState -eq 'EthernetTargetActive' -and $status.TargetHostRouteCorrect -and
        $target.InterfaceAlias -eq $status.EthernetAlias
}
else {
    $routeOk = $status.EthernetTargetHostRouteCount -eq 0 -and $status.PersistentTargetHostRouteCount -eq 0 -and $target.InterfaceAlias -eq $WifiAlias
}
$passed = $status.Compliant -and $internetOk -and $targetOk -and $routeOk

$result = [pscustomobject]@{
    Scenario                    = $Scenario
    Passed                      = $passed
    DesiredState                = $status.DesiredState
    EthernetStatus              = $status.EthernetStatus
    HostRouteCorrect            = $status.TargetHostRouteCorrect
    EthernetHostRouteCount      = $status.EthernetTargetHostRouteCount
    InternetTcp443Succeeded     = [bool]$internet.TcpTestSucceeded
    InternetInterfaceAlias      = [string]$internet.InterfaceAlias
    InternetSourceAddress       = Get-GapdTestConnectionSourceAddress -TestConnectionResult $internet
    TargetTcp80Succeeded        = [bool]$target.TcpTestSucceeded
    TargetInterfaceAlias        = [string]$target.InterfaceAlias
    TargetSourceAddress         = Get-GapdTestConnectionSourceAddress -TestConnectionResult $target
    HttpTitle                   = $httpTitle
    HttpError                   = $httpError
    LogFile                     = $logFile
}

Write-GapdLog -LogFile $logFile -Message (($result | ConvertTo-Json -Depth 5 -Compress))
$result | Format-List

if (-not $passed) {
    Write-Error "Scenario $Scenario did not meet all route and connectivity expectations. See $logFile"
    exit 1
}
