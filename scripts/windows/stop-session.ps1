[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stopped = [DateTimeOffset]::Now

Write-Host "Stopping transcript: $($stopped.ToString('o'))"
try {
    Stop-Transcript | Out-Null
    Write-Host 'Transcript stopped.'
} catch {
    throw "No active transcript exists in this PowerShell session. Start and stop must run in the same console. $($_.Exception.Message)"
}
