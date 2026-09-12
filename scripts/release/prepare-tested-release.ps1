[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InitramfsPath,

    [Parameter(Mandatory = $true)]
    [string]$FactoryPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

$expected = @(
    [pscustomobject]@{
        Path = (Resolve-Path -LiteralPath $InitramfsPath).Path
        Name = 'openwrt-qualcommax-ipq60xx-lg_gapd-7500-initramfs-uImage.itb'
        Bytes = 14802824
        SHA256 = '7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400'
    },
    [pscustomobject]@{
        Path = (Resolve-Path -LiteralPath $FactoryPath).Path
        Name = 'openwrt-qualcommax-ipq60xx-lg_gapd-7500-squashfs-factory.ubi'
        Bytes = 13762560
        SHA256 = 'fe306d8fab0eb96c47649dadd3ee9fb731bdbbbcb587a45a5a8f00722edb892b'
    }
)

foreach ($item in $expected) {
    $file = Get-Item -LiteralPath $item.Path
    $hash = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $item.Bytes -or $hash -ne $item.SHA256) {
        throw "Refusing non-tested artifact: $($file.Name)"
    }
}

$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) {
    if (@(Get-ChildItem -LiteralPath $output -Force).Count -gt 0) {
        throw "Output directory is not empty: $output"
    }
}
else {
    New-Item -ItemType Directory -Path $output | Out-Null
}

$sumLines = foreach ($item in $expected) {
    Copy-Item -LiteralPath $item.Path -Destination (Join-Path $output $item.Name)
    '{0}  {1}' -f $item.SHA256, $item.Name
}
$sumLines | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS') -Encoding ascii

$expected | Select-Object Name, Bytes, SHA256 | Format-Table -AutoSize
Write-Host "Tested release package prepared at $output"
Write-Host 'No sysupgrade image was copied.'
