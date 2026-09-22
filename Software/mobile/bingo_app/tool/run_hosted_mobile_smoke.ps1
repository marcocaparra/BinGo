[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-RequiredEnvironmentVariable {
  param([Parameter(Mandatory = $true)][string]$Name)

  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Variável obrigatória ausente: $Name"
  }
  return $value
}

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$projectRefPath = Join-Path $repositoryRoot 'supabase\.temp\project-ref'
$supabaseCli = Join-Path $repositoryRoot 'node_modules\.bin\supabase.cmd'

$null = Get-RequiredEnvironmentVariable 'BINGO_MOBILE_TEST_EMAIL'
$null = Get-RequiredEnvironmentVariable 'BINGO_MOBILE_TEST_PASSWORD'

if (-not (Test-Path -LiteralPath $projectRefPath)) {
  throw 'Projeto Supabase vinculado não encontrado.'
}
if (-not (Test-Path -LiteralPath $supabaseCli)) {
  throw 'Supabase CLI local não encontrado.'
}

$projectRef = (Get-Content -Raw -LiteralPath $projectRefPath).Trim()
$projectsRaw = & $supabaseCli projects list --output json
if ($LASTEXITCODE -ne 0) {
  throw 'Falha ao consultar o projeto Supabase vinculado.'
}
$projects = $projectsRaw | ConvertFrom-Json
$linkedProject = $projects | Where-Object { $_.ref -eq $projectRef } |
  Select-Object -First 1
if ($null -eq $linkedProject -or $linkedProject.name -ne 'bingo-dev') {
  throw 'O projeto Supabase vinculado não é bingo-dev.'
}

$expectedUrl = "https://$projectRef.supabase.co"
$supabaseUrl = [Environment]::GetEnvironmentVariable('SUPABASE_URL')
$publishableKey = [Environment]::GetEnvironmentVariable(
  'SUPABASE_PUBLISHABLE_KEY'
)

$keysRaw = & $supabaseCli projects api-keys `
  --project-ref $projectRef `
  --reveal `
  --output json
if ($LASTEXITCODE -ne 0) {
  throw 'Falha ao obter as chaves de smoke do projeto DEV.'
}
$keys = $keysRaw | ConvertFrom-Json
$secretKey = ($keys |
    Where-Object { $_.type -eq 'secret' -and $_.name -eq 'default' } |
    Select-Object -First 1).api_key

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or
    [string]::IsNullOrWhiteSpace($publishableKey)) {
  $publishableKey = ($keys |
      Where-Object { $_.type -eq 'publishable' } |
      Select-Object -First 1).api_key
  $supabaseUrl = $expectedUrl
}

if ($supabaseUrl.TrimEnd('/') -ne $expectedUrl) {
  throw 'SUPABASE_URL não aponta para o projeto bingo-dev vinculado.'
}
if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  throw 'Chave pública do projeto não encontrada.'
}
if ([string]::IsNullOrWhiteSpace($secretKey)) {
  throw 'Chave administrativa de smoke do projeto DEV não encontrada.'
}

$previousSmokeFlag = [Environment]::GetEnvironmentVariable(
  'BINGO_HOSTED_SMOKE'
)
$previousUrl = [Environment]::GetEnvironmentVariable('SUPABASE_URL')
$previousKey = [Environment]::GetEnvironmentVariable(
  'SUPABASE_PUBLISHABLE_KEY'
)
$previousSecretKey = [Environment]::GetEnvironmentVariable(
  'BINGO_DEV_SECRET_KEY'
)

try {
  $env:BINGO_HOSTED_SMOKE = '1'
  $env:SUPABASE_URL = $supabaseUrl
  $env:SUPABASE_PUBLISHABLE_KEY = $publishableKey
  $env:BINGO_DEV_SECRET_KEY = $secretKey

  Push-Location $appRoot
  try {
    & flutter test test/hosted_mobile_smoke_test.dart
    if ($LASTEXITCODE -ne 0) {
      throw 'Smoke hospedado do Mobile falhou.'
    }
  }
  finally {
    Pop-Location
  }
}
finally {
  $env:BINGO_HOSTED_SMOKE = $previousSmokeFlag
  $env:SUPABASE_URL = $previousUrl
  $env:SUPABASE_PUBLISHABLE_KEY = $previousKey
  $env:BINGO_DEV_SECRET_KEY = $previousSecretKey
}
