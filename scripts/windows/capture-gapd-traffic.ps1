[CmdletBinding()]
param(
    [string]$EthernetAlias = 'Ethernet 12',
    [ValidateRange(5, 3600)]
    [int]$DurationSeconds = 120,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

$tshark = Get-Command tshark.exe -ErrorAction SilentlyContinue
if (-not $tshark) {
    throw 'tshark.exe is not installed or not in PATH. No capture was started.'
}

$adapter = Get-NetAdapter -Name $EthernetAlias -ErrorAction Stop
if ($adapter.Status -ne 'Up') {
    throw "Adapter '$EthernetAlias' is not Up. No capture was started."
}

$guidText = $adapter.InterfaceGuid.ToString('D')
$interfaces = & $tshark.Source -D
$match = $interfaces | Where-Object { $_ -match [regex]::Escape($guidText) }
if (@($match).Count -ne 1 -or $match -notmatch '^\s*(\d+)\.') {
    throw "Could not map '$EthernetAlias' uniquely to a TShark interface. No capture was started."
}
$captureInterface = $Matches[1]

if (-not $OutputDirectory) {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $OutputDirectory = Join-Path $repositoryRoot 'artifacts\pcap'
}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$pcap = Join-Path ([System.IO.Path]::GetFullPath($OutputDirectory)) "$timestamp-gapd-ethernet.pcapng"
$metadata = [System.IO.Path]::ChangeExtension($pcap, '.metadata.txt')

@(
    "Started=$([DateTimeOffset]::Now.ToString('o'))"
    "InterfaceAlias=$EthernetAlias"
    "DurationSeconds=$DurationSeconds"
    'CaptureFilter=host 192.168.219.1'
    'SuggestedDisplayFilter=dns || http || tls'
    'ContainsSensitiveData=possible; do not commit the PCAP'
) | Set-Content -LiteralPath $metadata -Encoding UTF8

& $tshark.Source -i $captureInterface -a "duration:$DurationSeconds" -f 'host 192.168.219.1' -w $pcap
if ($LASTEXITCODE -ne 0) {
    throw "TShark exited with code $LASTEXITCODE."
}

Add-Content -LiteralPath $metadata -Value "Completed=$([DateTimeOffset]::Now.ToString('o'))" -Encoding UTF8
Add-Content -LiteralPath $metadata -Value "SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $pcap).Hash.ToLowerInvariant())" -Encoding UTF8
Write-Host "Capture complete: $pcap"
Write-Warning 'The PCAP may contain credentials, tokens, MAC addresses, DNS names, and device identifiers. Do not commit it.'
