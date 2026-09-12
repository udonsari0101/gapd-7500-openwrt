[CmdletBinding()]
param([string]$EthernetAlias)

& (Join-Path $PSScriptRoot 'disable-gapd-network.ps1') -EthernetAlias $EthernetAlias
exit $LASTEXITCODE

