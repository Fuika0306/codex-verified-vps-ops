[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._:-]+$')]
    [string]$HostName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_.-]*$')]
    [string]$User,

    [ValidateRange(1, 65535)]
    [int]$Port = 22,

    [string]$IdentityFile,

    [ValidatePattern('^[A-Za-z0-9_.@-]*$')]
    [string]$Service = '',

    [string]$ComposeDir = '',

    [ValidateScript({
        if (-not $_.IsAbsoluteUri) { throw 'HealthUrl must be absolute.' }
        if ($_.Scheme -notin @('http', 'https')) { throw 'HealthUrl must use http or https.' }
        if ($_.UserInfo) { throw 'HealthUrl must not contain embedded credentials.' }
        if ($_.Query) { throw 'HealthUrl must not contain a query string.' }
        if ($_.Fragment) { throw 'HealthUrl must not contain a fragment.' }
        return $true
    })]
    [uri]$HealthUrl,

    [switch]$IncludeJournal,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-Base64Utf8 {
    param([AllowEmptyString()][string]$Value)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

$destination = '{0}@{1}' -f $User, $HostName
$templatePath = Join-Path $PSScriptRoot 'remote-preflight.sh'

if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Remote preflight template not found: $templatePath"
}

$identityPath = $null
if ($IdentityFile) {
    if ($DryRun) {
        $identityPath = $IdentityFile
    }
    else {
        $identityPath = (Resolve-Path -LiteralPath $IdentityFile -ErrorAction Stop).Path
    }
}

$healthValue = if ($null -eq $HealthUrl) { '' } else { $HealthUrl.AbsoluteUri }
$journalValue = if ($IncludeJournal) { '1' } else { '0' }
$remoteScript = [IO.File]::ReadAllText($templatePath, [Text.Encoding]::UTF8)
$remoteScript = $remoteScript.Replace(
    '__SERVICE_B64__',
    (ConvertTo-Base64Utf8 -Value $Service)
).Replace(
    '__COMPOSE_B64__',
    (ConvertTo-Base64Utf8 -Value $ComposeDir)
).Replace(
    '__HEALTH_B64__',
    (ConvertTo-Base64Utf8 -Value $healthValue)
).Replace(
    '__JOURNAL_B64__',
    (ConvertTo-Base64Utf8 -Value $journalValue)
)

if ($remoteScript -match '__[A-Z_]+__') {
    throw 'An unresolved placeholder remains in remote-preflight.sh.'
}

$sshArguments = @(
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', 'ConnectTimeout=10',
    '-p', [string]$Port
)

if ($identityPath) {
    $sshArguments += @('-i', $identityPath)
}

if ($DryRun) {
    [pscustomobject]@{
        Mode          = 'dry-run'
        Destination   = $destination
        Port          = $Port
        IdentityFileProvided = [bool]$identityPath
        Service       = $Service
        ComposeDir    = $ComposeDir
        HealthUrl     = $healthValue
        IncludeJournal = $IncludeJournal.IsPresent
        RemoteCommand = 'base64 --decode --ignore-garbage | bash'
        Checks        = @(
            'host',
            'listening_ports',
            'systemd_service',
            'docker',
            'caddy',
            'health'
        )
    } | ConvertTo-Json -Depth 3
    exit 0
}

$sshCommand = Get-Command ssh -ErrorAction Stop
$payload = ConvertTo-Base64Utf8 -Value $remoteScript
$payload | & $sshCommand.Source @sshArguments $destination 'base64 --decode --ignore-garbage | bash'
$sshExit = $LASTEXITCODE

if ($sshExit -ne 0) {
    throw "SSH preflight failed with exit code $sshExit."
}