param([string]$Python = 'python')

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot '.env'
if (Test-Path -LiteralPath $configPath) {
    foreach ($line in Get-Content -LiteralPath $configPath) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) { continue }
        $parts = $entry.Split('=', 2)
        if ($parts.Count -ne 2) { throw 'Invalid .env entry. Use NAME=value.' }
        $name = $parts[0].Trim()
        if ($name -notmatch '^(AWS_[A-Z0-9_]+|GEMINI_[A-Z0-9_]+|BINGO_[A-Z0-9_]+)$') {
            throw 'Unsupported variable in .env. Only AWS_, GEMINI_ and BINGO_ variables are supported.'
        }
        $value = $parts[1].Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
}

$awsReady = $env:AWS_ACCESS_KEY_ID -and $env:AWS_SECRET_ACCESS_KEY
if (-not $awsReady -and -not $env:AWS_PROFILE -and -not $env:GEMINI_API_KEY) {
    throw 'Configure AWS credentials/profile or GEMINI_API_KEY in .env or in the environment first.'
}

Write-Host 'Starting local BinGo vision. Keep this terminal open while testing.'
& $Python (Join-Path $PSScriptRoot 'vision/edge_vision_service.py')
exit $LASTEXITCODE
