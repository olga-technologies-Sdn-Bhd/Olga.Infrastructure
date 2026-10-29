[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        if ($_ -cnotin @('dev', 'prd')) {
            throw 'Environment must be exactly dev or prd.'
        }
        $true
    })]
    [string]$Environment,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

$credentialVariables = [ordered]@{
    'twilio-api-key-secret'      = 'OLGA_TWILIO_API_KEY_SECRET'
    'phone-auth-jwt-signing-key' = 'OLGA_PHONE_AUTH_JWT_SIGNING_KEY'
}

$credentialValues = @{}
foreach ($entry in $credentialVariables.GetEnumerator()) {
    $value = [Environment]::GetEnvironmentVariable($entry.Value)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required GitHub Environment secret '$($entry.Value.Replace('OLGA_', ''))' is not configured."
    }
    $credentialValues[$entry.Key] = $value
}

if ($credentialValues['twilio-api-key-secret'].Length -lt 16 -or $credentialValues['twilio-api-key-secret'] -match '\s') {
    throw 'TWILIO_API_KEY_SECRET must be a non-whitespace credential of at least 16 characters.'
}
if ($credentialValues['phone-auth-jwt-signing-key'].Length -lt 32 -or $credentialValues['phone-auth-jwt-signing-key'] -match '\s') {
    throw 'PHONE_AUTH_JWT_SIGNING_KEY must be a non-whitespace signing key of at least 32 characters.'
}

$terraformEnvironment = if ($Environment -ceq 'prd') { 'prod' } else { 'dev' }
$vaultQuery = "[?tags.product=='olga-connect' && tags.environment=='$terraformEnvironment'].{id:id,name:name}"
$vaultJson = & az keyvault list `
    --subscription $SubscriptionId `
    --query $vaultQuery `
    --output json `
    --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enumerate the environment Key Vault through the Azure control plane.'
}

$vaultJsonText = $vaultJson -join [Environment]::NewLine
$vaults = @($vaultJsonText | ConvertFrom-Json)
if ($vaults.Count -ne 1) {
    throw "Expected exactly one OLGA Key Vault tagged for '$terraformEnvironment'; found $($vaults.Count)."
}

$vault = $vaults[0]
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("olga-twilio-" + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporaryDirectory)

try {
    foreach ($entry in $credentialValues.GetEnumerator()) {
        $bodyPath = Join-Path $temporaryDirectory ("$($entry.Key).json")
        @{
            properties = @{
                value = $entry.Value
            }
        } | ConvertTo-Json -Compress | Set-Content -LiteralPath $bodyPath -Encoding utf8NoBOM -NoNewline

        $secretResourceUri = "$($vault.id)/secrets/$($entry.Key)?api-version=2023-07-01"
        & az rest `
            --method put `
            --uri $secretResourceUri `
            --body "@$bodyPath" `
            --output none `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Azure rejected the Key Vault secret update for '$($entry.Key)'."
        }
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
    foreach ($name in $credentialVariables.Values) {
        [Environment]::SetEnvironmentVariable($name, $null)
    }
    $credentialValues.Clear()
}

Write-Output "Configured two Twilio Verify secret versions in Key Vault '$($vault.name)' for '$Environment'."
