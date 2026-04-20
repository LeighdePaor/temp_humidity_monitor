param(
    [string]$SensitiveFilePath = "$HOME/temp_humidity_monitor/sensitive.json",
    [switch]$Persist
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SensitiveFilePath)) {
    throw "Sensitive file not found: $SensitiveFilePath"
}

$sensitive = Get-Content -LiteralPath $SensitiveFilePath -Raw | ConvertFrom-Json
$requiredProps = @('domain', 'app_user', 'pi_ip_address')

foreach ($prop in $requiredProps) {
    if (-not ($sensitive.PSObject.Properties.Name -contains $prop)) {
        throw "Missing required property '$prop' in $SensitiveFilePath"
    }
}

$env:DOMAIN = [string]$sensitive.domain
$env:APP_USER = [string]$sensitive.app_user
$env:PI_IP = [string]$sensitive.pi_ip_address

if ($sensitive.PSObject.Properties.Name -contains 'thingsboard_host') {
    $env:THINGSBOARD_HOST = [string]$sensitive.thingsboard_host
}

if ($sensitive.PSObject.Properties.Name -contains 'access_token') {
    $env:ACCESS_TOKEN = [string]$sensitive.access_token
}

Write-Host "Loaded DOMAIN, APP_USER, PI_IP into current PowerShell session."

$profilePath = $PROFILE.CurrentUserAllHosts
$beginMarker = '# >>> temp_humidity_monitor env >>>'
$endMarker = '# <<< temp_humidity_monitor env <<<'

$profileText = ''
if (Test-Path -LiteralPath $profilePath) {
    $profileText = Get-Content -LiteralPath $profilePath -Raw
}

$hasPersistentSection = $profileText -like "*$beginMarker*"
if ($hasPersistentSection) {
    Write-Host "Persistent profile section already exists in $profilePath"
    return
}

$shouldAdd = $Persist.IsPresent
if (-not $shouldAdd) {
    $response = Read-Host "Persistent profile section not found in $profilePath. Add it now? [y/N]"
    $shouldAdd = $response -match '^(y|yes)$'
}

if (-not $shouldAdd) {
    Write-Host "Skipped profile update. Run again with -Persist to add it without prompt."
    return
}

$profileDir = Split-Path -Parent $profilePath
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$escapedSensitivePath = $SensitiveFilePath.Replace("'", "''")
$profileBlock = @"
$beginMarker
`$__tempHumiditySensitivePath = '$escapedSensitivePath'
if (Test-Path -LiteralPath `$__tempHumiditySensitivePath) {
    `$__s = Get-Content -LiteralPath `$__tempHumiditySensitivePath -Raw | ConvertFrom-Json
    `$env:DOMAIN = [string]`$__s.domain
    `$env:APP_USER = [string]`$__s.app_user
    `$env:PI_IP = [string]`$__s.pi_ip_address
    if (`$__s.PSObject.Properties.Name -contains 'thingsboard_host') { `$env:THINGSBOARD_HOST = [string]`$__s.thingsboard_host }
    if (`$__s.PSObject.Properties.Name -contains 'access_token') { `$env:ACCESS_TOKEN = [string]`$__s.access_token }
}
$endMarker
"@

if ((Test-Path -LiteralPath $profilePath) -and ((Get-Item -LiteralPath $profilePath).Length -gt 0)) {
    Add-Content -LiteralPath $profilePath -Value "`n$profileBlock"
} else {
    Set-Content -LiteralPath $profilePath -Value $profileBlock
}

Write-Host "Added persistent env section to $profilePath"
Write-Host "Restart PowerShell or run: . $profilePath"
