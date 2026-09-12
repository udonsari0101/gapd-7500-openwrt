[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Slot0CopyA,

    [Parameter(Mandatory = $true)]
    [string]$Slot0CopyB,

    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = 'Stop'
$expectedOldSha = '5a0a92472ecef64b32621ce5503e7e7f45d4f1e9792e649b6d8287511c50e6f3'
$copyAPath = (Resolve-Path $Slot0CopyA).Path
$copyBPath = (Resolve-Path $Slot0CopyB).Path
$copyA = [IO.File]::ReadAllBytes($copyAPath)
$copyB = [IO.File]::ReadAllBytes($copyBPath)

if ($copyA.Length -ne 524288 -or $copyB.Length -ne 524288) {
    throw 'BOOTCONFIG backup size mismatch.'
}
$copyASha = (Get-FileHash -LiteralPath $copyAPath -Algorithm SHA256).Hash.ToLowerInvariant()
$copyBSha = (Get-FileHash -LiteralPath $copyBPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($copyASha -ne $expectedOldSha -or $copyBSha -ne $expectedOldSha) {
    throw 'BOOTCONFIG backup SHA-256 mismatch.'
}
for ($i = 0; $i -lt $copyA.Length; $i++) {
    if ($copyA[$i] -ne $copyB[$i]) {
        throw "BOOTCONFIG backup copies differ at offset $i."
    }
}
if (($copyA[0..3] -join ',') -ne '160,161,162,163') {
    throw 'BOOTCONFIG start magic mismatch.'
}
if ([BitConverter]::ToUInt32($copyA, 8) -ne 8) {
    throw 'BOOTCONFIG entry count mismatch.'
}
if ([Text.Encoding]::ASCII.GetString($copyA, 132, 16).Trim([char]0) -ne 'rootfs') {
    throw 'BOOTCONFIG rootfs entry mismatch.'
}
if ([BitConverter]::ToUInt32($copyA, 148) -ne 0) {
    throw 'BOOTCONFIG rootfs primaryboot is not slot 0.'
}
if (($copyA[332..335] -join ',') -ne '176,177,178,179') {
    throw 'BOOTCONFIG end magic mismatch.'
}
if (Test-Path -LiteralPath $Output) {
    throw "Refusing to overwrite existing output: $Output"
}

$target = [byte[]]$copyA.Clone()
[BitConverter]::GetBytes([uint32]1).CopyTo($target, 148)
[IO.File]::WriteAllBytes($Output, $target)

$diffs = for ($i = 0; $i -lt $copyA.Length; $i++) {
    if ($copyA[$i] -ne $target[$i]) { $i }
}
if ($diffs.Count -ne 1 -or $diffs[0] -ne 148 -or $target[148] -ne 1) {
    throw 'Generated BOOTCONFIG differs outside the expected selection byte.'
}

[pscustomobject]@{
    Output = (Resolve-Path $Output).Path
    Bytes = (Get-Item -LiteralPath $Output).Length
    OldSHA256 = $copyASha
    NewSHA256 = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash.ToLowerInvariant()
    ChangedOffset = 148
    OldValue = 0
    NewValue = 1
    DifferingByteCount = $diffs.Count
}
