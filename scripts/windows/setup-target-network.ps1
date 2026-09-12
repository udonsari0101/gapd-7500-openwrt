[CmdletBinding()]
param(
    [string]$EthernetAlias,
    [string]$WifiAlias = 'Wi-Fi'
)

& (Join-Path $PSScriptRoot 'enable-gapd-network.ps1') -EthernetAlias $EthernetAlias -WifiAlias $WifiAlias
exit $LASTEXITCODE

