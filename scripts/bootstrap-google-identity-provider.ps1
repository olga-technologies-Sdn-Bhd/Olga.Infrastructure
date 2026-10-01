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
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$')]
    [string]$TenantSubdomain,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$')]
    [string]$GoogleClientId
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$graphRoot = 'https://graph.microsoft.com/v1.0'
$secretEnvironmentVariable = 'OLGA_GOOGLE_CLIENT_SECRET'
$accessToken = $null
$clientSecret = $null
$secretPointer = [IntPtr]::Zero

function Get-SafeHttpStatus {
    param([Parameter(Mandatory)]$Exception)

    if ($null -ne $Exception.Response -and $null -ne $Exception.Response.StatusCode) {
        return [int]$Exception.Response.StatusCode
    }

    return $null
}

function Invoke-SafeGraphRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [hashtable]$Body
    )

    try {
        $parameters = @{
            Method      = $Method
            Uri         = $Uri
            Headers     = @{ Authorization = "Bearer $Token" }
            ErrorAction = 'Stop'
        }
        if ($null -ne $Body) {
            $parameters.ContentType = 'application/json'
            $parameters.Body = $Body | ConvertTo-Json -Depth 5 -Compress
        }

        return Invoke-RestMethod @parameters
    }
    catch {
        $status = Get-SafeHttpStatus -Exception $_.Exception
        if ($null -ne $status) {
            $safePath = ([Uri]$Uri).AbsolutePath
            throw "Microsoft Graph $Method $safePath failed with HTTP status $status. Response details were suppressed to protect credentials and tokens."
        }
        throw 'Microsoft Graph request failed. Error details were suppressed to protect credentials and tokens.'
    }
}

function ConvertFrom-JwtPayload {
    param([Parameter(Mandatory)][string]$Token)

    $segments = $Token.Split('.')
    if ($segments.Count -lt 2) {
        throw 'Azure CLI returned an invalid Microsoft Graph access token.'
    }

    $payload = $segments[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
    }

    try {
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    }
    catch {
        throw 'Azure CLI returned an unreadable Microsoft Graph access token.'
    }
}

if ($Environment -ceq 'dev' -and -not $TenantSubdomain.EndsWith('dev', [StringComparison]::Ordinal)) {
    throw "The dev external tenant subdomain must end in 'dev'."
}
if ($Environment -ceq 'prd' -and $TenantSubdomain.EndsWith('dev', [StringComparison]::Ordinal)) {
    throw "The prd external tenant subdomain must not use the dev suffix."
}

if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Authenticate to the matching external tenant before running this script.'
}

try {
    $tokenJson = & az account get-access-token --tenant $TenantId --resource-type ms-graph --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($tokenJson -join ''))) {
        throw 'Unable to obtain a Microsoft Graph token for the matching external tenant.'
    }

    $tokenResult = ($tokenJson -join '') | ConvertFrom-Json
    $accessToken = [string]$tokenResult.accessToken
    $claims = ConvertFrom-JwtPayload -Token $accessToken
    if ([string]$claims.tid -ne $TenantId) {
        throw 'The Microsoft Graph token tenant does not match TenantId.'
    }
    $delegatedPermissions = @([string]$claims.scp -split ' ')
    $applicationPermissions = @($claims.roles | ForEach-Object { [string]$_ })
    $hasIdentityProviderPermission =
        $delegatedPermissions -contains 'IdentityProvider.ReadWrite.All' -or
        $applicationPermissions -contains 'IdentityProvider.ReadWrite.All'
    $hasOrganizationReadPermission =
        $delegatedPermissions -contains 'Organization.Read.All' -or
        $applicationPermissions -contains 'Organization.Read.All'
    $hasEventListenerPermission =
        $delegatedPermissions -contains 'EventListener.ReadWrite.All' -or
        $applicationPermissions -contains 'EventListener.ReadWrite.All'
    if (-not $hasIdentityProviderPermission -or -not $hasOrganizationReadPermission -or -not $hasEventListenerPermission) {
        throw 'The Microsoft Graph token must contain IdentityProvider.ReadWrite.All, Organization.Read.All, and EventListener.ReadWrite.All as delegated scopes or application roles.'
    }

    $organization = Invoke-SafeGraphRequest -Method GET -Uri "$graphRoot/organization?`$select=id,verifiedDomains" -Token $accessToken
    if (@($organization.value).Count -ne 1 -or [string]$organization.value[0].id -ne $TenantId) {
        throw 'Microsoft Graph did not return the expected external tenant organization.'
    }

    $expectedDomain = "$TenantSubdomain.onmicrosoft.com"
    $verifiedDomains = @($organization.value[0].verifiedDomains | ForEach-Object { [string]$_.name })
    if ($verifiedDomains -notcontains $expectedDomain) {
        throw "TenantSubdomain does not match a verified domain in the authenticated external tenant."
    }

    $clientSecret = [Environment]::GetEnvironmentVariable($secretEnvironmentVariable, 'Process')
    if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        $secureSecret = Read-Host "Enter the Google OAuth client secret (or set $secretEnvironmentVariable in this process)" -AsSecureString
        $secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
        $clientSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
        $secureSecret.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        throw "The Google OAuth client secret is required through $secretEnvironmentVariable or secure interactive input."
    }

    $providers = @()
    $nextLink = "$graphRoot/identity/identityProviders"
    while ($null -ne $nextLink) {
        if (-not $nextLink.StartsWith("$graphRoot/identity/identityProviders", [StringComparison]::Ordinal)) {
            throw 'Microsoft Graph returned an unexpected identity-provider pagination URL.'
        }
        $page = Invoke-SafeGraphRequest -Method GET -Uri $nextLink -Token $accessToken
        $providers += @($page.value)
        $nextLink = $page.'@odata.nextLink'
    }

    $googleProviders = @($providers | Where-Object { [string]$_.identityProviderType -eq 'Google' })
    if ($googleProviders.Count -gt 1) {
        throw 'Multiple Google identity providers exist in the target external tenant. Resolve the conflict in Entra before rerunning this script.'
    }

    $createBody = @{
        '@odata.type'        = '#microsoft.graph.socialIdentityProvider'
        displayName          = 'Google'
        identityProviderType = 'Google'
        clientId             = $GoogleClientId
        clientSecret         = $clientSecret
    }
    $updateBody = @{
        '@odata.type' = '#microsoft.graph.socialIdentityProvider'
        displayName   = 'Google'
        clientId      = $GoogleClientId
        clientSecret  = $clientSecret
    }

    if ($googleProviders.Count -eq 0) {
        $provider = Invoke-SafeGraphRequest -Method POST -Uri "$graphRoot/identity/identityProviders" -Token $accessToken -Body $createBody
        $providerId = [string]$provider.id
    }
    else {
        $providerId = [string]$googleProviders[0].id
        if ($providerId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            throw 'The existing Google identity provider has an invalid object ID.'
        }
        $null = Invoke-SafeGraphRequest -Method PATCH -Uri "$graphRoot/identity/identityProviders/$providerId" -Token $accessToken -Body $updateBody
    }

    if ($providerId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw 'Microsoft Graph did not return a valid Google identity-provider object ID.'
    }

    $expectedFlowName = "olga_signup_signin_$Environment"
    $flows = @()
    $nextLink = "$graphRoot/identity/authenticationEventsFlows"
    while ($null -ne $nextLink) {
        if (-not $nextLink.StartsWith("$graphRoot/identity/authenticationEventsFlows", [StringComparison]::Ordinal)) {
            throw 'Microsoft Graph returned an unexpected user-flow pagination URL.'
        }
        $page = Invoke-SafeGraphRequest -Method GET -Uri $nextLink -Token $accessToken
        $flows += @($page.value)
        $nextLink = $page.'@odata.nextLink'
    }

    $matchingFlows = @($flows | Where-Object { [string]$_.displayName -ceq $expectedFlowName })
    if ($matchingFlows.Count -ne 1) {
        throw "Expected exactly one $expectedFlowName user flow in the target external tenant."
    }

    $flowId = [string]$matchingFlows[0].id
    if ($flowId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw 'The existing customer user flow has an invalid object ID.'
    }

    $flowProvidersUri = "$graphRoot/identity/authenticationEventsFlows/$flowId/microsoft.graph.externalUsersSelfServiceSignUpEventsFlow/onAuthenticationMethodLoadStart/microsoft.graph.onAuthenticationMethodLoadStartExternalUsersSelfServiceSignUp/identityProviders"
    $originalFlowProviderIds = @($matchingFlows[0].onAuthenticationMethodLoadStart.identityProviders | ForEach-Object { [string]$_.id })
    if ($originalFlowProviderIds -notcontains 'EmailOtpSignup-OAUTH') {
        throw 'The existing customer user flow does not contain Email OTP; refusing to modify its identity-provider associations.'
    }

    if ($originalFlowProviderIds -notcontains $providerId) {
        $referenceBody = @{
            '@odata.id' = "$graphRoot/identityProviders/$providerId"
        }
        $null = Invoke-SafeGraphRequest -Method POST -Uri "$flowProvidersUri/`$ref" -Token $accessToken -Body $referenceBody
    }

    $verifiedFlow = Invoke-SafeGraphRequest -Method GET -Uri "$graphRoot/identity/authenticationEventsFlows/$flowId" -Token $accessToken
    $verifiedFlowProviderIds = @($verifiedFlow.onAuthenticationMethodLoadStart.identityProviders | ForEach-Object { [string]$_.id })
    if ($verifiedFlowProviderIds -notcontains $providerId) {
        throw 'Microsoft Graph did not confirm the configured Google provider association on the existing customer user flow.'
    }
    foreach ($originalFlowProviderId in $originalFlowProviderIds) {
        if ($verifiedFlowProviderIds -notcontains $originalFlowProviderId) {
            throw 'An existing identity-provider association was not retained; manual review is required.'
        }
    }

    Write-Output $providerId
}
finally {
    $clientSecret = $null
    $accessToken = $null
    $createBody = $null
    $updateBody = $null
    $referenceBody = $null
    $tokenJson = $null
    $tokenResult = $null
    Remove-Item "Env:$secretEnvironmentVariable" -ErrorAction SilentlyContinue
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
}
