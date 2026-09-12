[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ImagePath,
    [string]$SourceAddress = '192.168.219.100',
    [string]$TargetAddress = '192.168.219.1',
    [string]$RequestedName = 'gapd-initramfs.itb',
    [string]$NcatPath = 'C:\Program Files (x86)\Nmap\ncat.exe',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$expectedBytes = 14802824
$expectedHash = '7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400'

$image = Get-Item -LiteralPath $ImagePath -ErrorAction Stop
if ($image.Length -ne $expectedBytes) {
    throw "Refusing an unexpected image size: $($image.Length)"
}
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $image.FullName).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw "Refusing an unexpected image SHA-256: $actualHash"
}
if (-not (Test-Path -LiteralPath $NcatPath -PathType Leaf)) {
    throw "Ncat is missing: $NcatPath"
}

$sourceIp = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $SourceAddress -ErrorAction Stop |
    Select-Object -First 1
$route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix ($TargetAddress + '/32') -ErrorAction SilentlyContinue |
    Where-Object InterfaceIndex -eq $sourceIp.InterfaceIndex |
    Select-Object -First 1
if ($null -eq $route) {
    throw 'The exact wired /32 route is missing. Let the GAPD route watcher restore it first.'
}
$conflict = Get-NetUDPEndpoint -LocalPort 69 -ErrorAction SilentlyContinue |
    Where-Object LocalAddress -in @($SourceAddress, '0.0.0.0', '::') |
    Select-Object -First 1
if ($null -ne $conflict) {
    throw "UDP port 69 is already in use by PID $($conflict.OwningProcess)."
}

$helper = (Resolve-Path (Join-Path $PSScriptRoot 'tftp-serve-ncat.py')).Path
$execCommand = @(
    'python', ('"' + $helper + '"'),
    '--file', ('"' + $image.FullName + '"'),
    '--requested-name', $RequestedName,
    '--expected-sha256', $expectedHash,
    '--expected-bytes', [string]$expectedBytes,
    '--expected-client', $TargetAddress
) -join ' '

Write-Host 'Validated official OpenWrt GAPD initramfs TFTP server'
Write-Host ("Image: {0}" -f $image.FullName)
Write-Host ("Bytes: {0}; SHA-256: {1}" -f $expectedBytes, $expectedHash)
Write-Host ("Bind: {0}:69; requested name: {1}; client: {2}" -f $SourceAddress, $RequestedName, $TargetAddress)
if ($ValidateOnly) {
    Write-Host 'Validation-only mode passed; no listener was started.'
    return
}
Write-Host 'No router request has been made. Press Ctrl+C to stop the listener.'

& $NcatPath -u -l $SourceAddress 69 --exec $execCommand
if ($LASTEXITCODE -ne 0) {
    throw "The one-shot TFTP listener failed (exit=$LASTEXITCODE)."
}

Write-Host 'One hash-pinned TFTP transfer completed.'
