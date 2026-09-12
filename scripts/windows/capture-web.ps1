[CmdletBinding()]
param(
    [uri]$BaseUri = 'http://192.168.219.1/',
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

if ($BaseUri.Scheme -ne 'http' -or $BaseUri.Host -ne '192.168.219.1') {
    throw 'This helper is intentionally restricted to http://192.168.219.1/.'
}

if (-not $OutputDirectory) {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $OutputDirectory = Join-Path $repositoryRoot '.work\web-capture'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$captureRoot = Join-Path ([System.IO.Path]::GetFullPath($OutputDirectory)) $timestamp
$rawRoot = Join-Path $captureRoot 'raw'
[void](New-Item -ItemType Directory -Path $rawRoot -Force)

# These are GET-only resources referenced directly by the public landing page.
# No captcha, login, private-data, apply, or update endpoint is requested.
$paths = @(
    '/',
    '/web/intro.html',
    '/web/js/jquery_api.js',
    '/web/js/aes.js',
    '/web/js/common_util.js',
    '/web/js/ntwk0.1_plugin.js',
    '/web/js/jsbn.js',
    '/web/js/prng4.js',
    '/web/js/rng.js',
    '/web/js/rsa.js',
    '/web/js/web_top_menu.js',
    '/web/js/common_ui.js'
)

$rows = foreach ($path in $paths) {
    $requestUri = [uri]::new($BaseUri, $path)
    $response = Invoke-WebRequest -Uri $requestUri -Method Get -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 10
    $safeName = if ($path -eq '/') { 'root.html' } else { $path.TrimStart('/').Replace('/', '__') }
    $rawPath = Join-Path $rawRoot $safeName
    [System.IO.File]::WriteAllText($rawPath, $response.Content, [System.Text.UTF8Encoding]::new($false))

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $rawPath).Hash.ToLowerInvariant()
    [pscustomobject]@{
        Method      = 'GET'
        Path        = $path
        Status      = [int]$response.StatusCode
        ContentType = [string]$response.Headers['Content-Type']
        Bytes       = (Get-Item -LiteralPath $rawPath).Length
        SHA256      = $hash
    }
}

$reportPath = Join-Path $captureRoot 'sanitized-summary.txt'
$report = @(
    'GAPD-7500 anonymous web capture summary'
    "Captured=$([DateTimeOffset]::Now.ToString('o'))"
    'BaseUri=http://192.168.219.1/'
    'Authentication=none'
    'Method=GET only'
    'Cookies=not persisted or exported'
    ''
    "Method`tPath`tStatus`tContentType`tBytes`tSHA256"
    ($rows | ForEach-Object {
        "{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $_.Method, $_.Path, $_.Status, $_.ContentType, $_.Bytes, $_.SHA256
    })
)
[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.UTF8Encoding]::new($false))

Write-Host "Raw responses (ignored by Git): $rawRoot"
Write-Host "Sanitized metadata: $reportPath"
Write-Warning 'Review every file manually before copying any output into a tracked logs directory.'
$rows
