[CmdletBinding()]
param(
    [string]$Purpose = 'GAPD-7500 investigation',
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

if (-not $OutputDirectory) {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $OutputDirectory = Join-Path $repositoryRoot '.work\sessions'
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $resolvedOutput -Force)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$path = Join-Path $resolvedOutput "$timestamp-powershell-transcript.txt"

Start-Transcript -Path $path -IncludeInvocationHeader -NoClobber | Out-Null

Write-Host "Transcript started: $path"
Write-Host "Purpose: $Purpose"
Write-Host "Started: $([DateTimeOffset]::Now.ToString('o'))"
Write-Warning 'The raw transcript may contain MAC addresses, cookies, tokens, or credentials. Keep it outside Git.'

[pscustomobject]@{
    Transcript = $path
    Purpose    = $Purpose
    Started    = [DateTimeOffset]::Now
}
