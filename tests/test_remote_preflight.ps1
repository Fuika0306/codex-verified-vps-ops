$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot `
    '..\skills\verified-vps-ops\scripts\remote-preflight.ps1'
$scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

$identityPlaceholder = 'C:\PATH\SSH_KEY'
$rawDryRun = & $scriptPath `
    -HostName 'example.invalid' `
    -User 'root' `
    -IdentityFile $identityPlaceholder `
    -Service 'app.service' `
    -DryRun | Out-String
$dryRun = $rawDryRun | ConvertFrom-Json

if ($dryRun.IdentityFileProvided -ne $true) {
    throw 'Dry-run must report only that an identity file was provided.'
}
if ($dryRun.PSObject.Properties.Name -contains 'IdentityFile') {
    throw 'Dry-run must not expose the identity-file path property.'
}
if ($rawDryRun -match 'SSH_KEY|C:\\PATH') {
    throw 'Dry-run leaked the identity-file path.'
}

function Assert-HealthUrlRejected {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedMessage
    )

    try {
        & $scriptPath `
            -HostName 'example.invalid' `
            -User 'root' `
            -Service 'app.service' `
            -HealthUrl $Url `
            -DryRun | Out-Null
    }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "Unexpected rejection for $Url`: $($_.Exception.Message)"
        }
        return
    }

    throw "Health URL was accepted but must be rejected: $Url"
}

Assert-HealthUrlRejected `
    -Url 'ftp://example.invalid/health' `
    -ExpectedMessage 'HealthUrl must use http or https.'
Assert-HealthUrlRejected `
    -Url 'https://user:pass@example.invalid/health' `
    -ExpectedMessage 'HealthUrl must not contain embedded credentials.'
Assert-HealthUrlRejected `
    -Url 'https://example.invalid/health?token=PLACEHOLDER' `
    -ExpectedMessage 'HealthUrl must not contain a query string.'
Assert-HealthUrlRejected `
    -Url 'https://example.invalid/health#fragment' `
    -ExpectedMessage 'HealthUrl must not contain a fragment.'

Write-Output 'PASS: PowerShell helper security boundaries'
