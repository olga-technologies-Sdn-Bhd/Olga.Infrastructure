# Mobile sign-up and sign-in with Microsoft Entra External ID

This runbook is for the OLGA React Native/Expo application. It documents the existing Microsoft-hosted email OTP flow and the infrastructure prerequisite for replacing its **No account? Create one** branch with a native-authentication flow. The mobile application must never generate, send, log, persist, or validate OTP values itself; it may collect an OTP only to submit it directly to Microsoft Entra during native authentication.

The mobile source code is not in this repository, so the client-side steps must be completed in the mobile repository. `bootstrap/external-directory` enables public-client flows and the native authentication APIs on the mobile registration. The infrastructure values shown here are the tested `dev` values. Production must use its own tenant, registrations, user flow, build configuration, and redirect scheme; do not copy the dev values into a production build.

## 1. Use the dev runtime values

Add these non-secret values to the mobile app's dev environment:

```dotenv
EXPO_PUBLIC_ENTRA_CLIENT_ID=e8db01a0-3a93-48e0-86fa-68123e026088
EXPO_PUBLIC_ENTRA_TENANT_ID=d6b05a66-a3b7-442c-b56f-d4d7a9e154ba
EXPO_PUBLIC_ENTRA_AUTHORITY=https://olgaconnectdev.ciamlogin.com/
EXPO_PUBLIC_ENTRA_REDIRECT_URI=olga-dev://auth
EXPO_PUBLIC_OLGA_API_SCOPE=api://733db389-f55d-4a33-8cd6-18a14393e3d9/access_as_user
```

These values are public identifiers, not credentials. Never add a client secret to a mobile build. Keep OTPs, authorization codes, access tokens, refresh tokens, and Microsoft Graph credentials out of `EXPO_PUBLIC_*` variables.

For future environments, obtain the values from the matching infrastructure deployment:

```powershell
terraform output EXPO_PUBLIC_ENTRA_CLIENT_ID
terraform output EXPO_PUBLIC_ENTRA_TENANT_ID
terraform output EXPO_PUBLIC_ENTRA_AUTHORITY
terraform output EXPO_PUBLIC_ENTRA_REDIRECT_URI
terraform output EXPO_PUBLIC_OLGA_API_SCOPE
```

Run those commands from an already initialized root Terraform working directory for the required environment. Do not mix outputs from different states.

## 2. Register the native callback in Expo

The native application must claim the same URI scheme that is registered in Entra. For dev, add the scheme to `app.json`:

```json
{
  "expo": {
    "scheme": "olga-dev",
    "plugins": ["expo-secure-store"]
  }
}
```

Keep the mobile project's existing `ios.bundleIdentifier`, `android.package`, and other Expo settings. The resulting callback must be exactly `olga-dev://auth`.

Use an Expo development build or a standalone app to test the native callback. Expo Go generates an `exp://` callback instead of claiming `olga-dev://`, so it is not the correct end-to-end test for this registration.

## 3. Add the mobile dependencies

From the mobile repository, install the Expo-compatible packages:

```bash
npx expo install expo-auth-session expo-crypto expo-web-browser expo-secure-store
```

`expo-auth-session` opens the Microsoft-hosted page and manages state and PKCE. `expo-secure-store` stores session tokens using platform-protected storage. No OTP package and no email provider are required.

## 4. Create and validate the auth configuration

Create a small configuration module such as `src/auth/entraConfig.ts`:

```ts
const required = (value: string | undefined, name: string): string => {
  if (!value) throw new Error(`Missing required mobile setting: ${name}`);
  return value;
};

export const entraConfig = {
  clientId: required(
    process.env.EXPO_PUBLIC_ENTRA_CLIENT_ID,
    'EXPO_PUBLIC_ENTRA_CLIENT_ID',
  ),
  tenantId: required(
    process.env.EXPO_PUBLIC_ENTRA_TENANT_ID,
    'EXPO_PUBLIC_ENTRA_TENANT_ID',
  ),
  authority: required(
    process.env.EXPO_PUBLIC_ENTRA_AUTHORITY,
    'EXPO_PUBLIC_ENTRA_AUTHORITY',
  ),
  redirectUri: required(
    process.env.EXPO_PUBLIC_ENTRA_REDIRECT_URI,
    'EXPO_PUBLIC_ENTRA_REDIRECT_URI',
  ),
  apiScope: required(
    process.env.EXPO_PUBLIC_OLGA_API_SCOPE,
    'EXPO_PUBLIC_OLGA_API_SCOPE',
  ),
};

if (!['dev', 'prd'].includes(process.env.EXPO_PUBLIC_ENVIRONMENT ?? '')) {
  throw new Error('EXPO_PUBLIC_ENVIRONMENT must be dev or prd');
}

if (process.env.EXPO_PUBLIC_ENVIRONMENT === 'dev' &&
    entraConfig.redirectUri !== 'olga-dev://auth') {
  throw new Error('The dev build must use olga-dev://auth');
}
```

Set `EXPO_PUBLIC_ENVIRONMENT=dev` in the dev build. When production is provisioned, add an explicit `prd` branch with the production redirect URI. Never silently fall back to production values.

The dev OpenID issuer and discovery document are:

```text
https://olgaconnectdev.ciamlogin.com/d6b05a66-a3b7-442c-b56f-d4d7a9e154ba/v2.0
https://olgaconnectdev.ciamlogin.com/d6b05a66-a3b7-442c-b56f-d4d7a9e154ba/v2.0/.well-known/openid-configuration
```

Let the library read the authorization, token, and logout endpoints from the discovery document. Do not build those endpoints with the management tenant ID `9972baa6-9591-43d7-8b13-59da8e6f1a72`; that is not the customer External ID tenant.

## 5. Implement the browser-delegated login

Create a hook such as `src/auth/useEntraLogin.ts`. The PKCE code exchange and secure-storage steps are explicit:

```ts
import { useEffect, useMemo, useRef, useState } from 'react';
import * as AuthSession from 'expo-auth-session';
import * as SecureStore from 'expo-secure-store';
import * as WebBrowser from 'expo-web-browser';
import { entraConfig } from './entraConfig';

WebBrowser.maybeCompleteAuthSession();

const SESSION_KEY = 'olga.entra.session';

export function useEntraLogin() {
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const exchangedCode = useRef<string | null>(null);
  const issuer = `${entraConfig.authority}${entraConfig.tenantId}/v2.0`;
  const discovery = AuthSession.useAutoDiscovery(issuer);
  const redirectUri = AuthSession.makeRedirectUri({
    native: entraConfig.redirectUri,
  });
  const scopes = useMemo(
    () => [
      'openid',
      'profile',
      'email',
      'offline_access',
      entraConfig.apiScope,
    ],
    [],
  );

  const [request, response, promptAsync] = AuthSession.useAuthRequest(
    {
      clientId: entraConfig.clientId,
      redirectUri,
      responseType: AuthSession.ResponseType.Code,
      scopes,
      usePKCE: true,
    },
    discovery,
  );

  useEffect(() => {
    if (response?.type !== 'success' || !response.params.code) return;
    if (!discovery || !request?.codeVerifier) return;
    if (exchangedCode.current === response.params.code) return;
    exchangedCode.current = response.params.code;

    void (async () => {
      const tokens = await AuthSession.exchangeCodeAsync(
        {
          clientId: entraConfig.clientId,
          code: response.params.code,
          redirectUri,
          extraParams: { code_verifier: request.codeVerifier },
        },
        discovery,
      );

      await SecureStore.setItemAsync(
        SESSION_KEY,
        JSON.stringify({
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          idToken: tokens.idToken,
          issuedAt: tokens.issuedAt,
          expiresIn: tokens.expiresIn,
          tokenType: tokens.tokenType,
          scope: tokens.scope,
        }),
        { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY },
      );

      setAccessToken(tokens.accessToken);
    })().catch(() => {
      // Show a generic login failure. Do not log the response, code, or tokens.
      setAccessToken(null);
    });
  }, [discovery, redirectUri, request?.codeVerifier, response]);

  return {
    accessToken,
    loginEnabled: Boolean(request && discovery),
    login: () => promptAsync(),
  };
}
```

Connect `login()` to the app's **Sign up or sign in with email** button and disable the button while `loginEnabled` is false. Both new-customer sign-up and existing-customer sign-in use this one user flow:

1. The app opens the system browser.
2. The customer enters an email address on the Microsoft-hosted page.
3. For a new address, the customer selects **No account? Create one**.
4. Microsoft sends the code to that email address.
5. The customer enters the code on the Microsoft-hosted page.
6. Entra validates the code and redirects to `olga-dev://auth`.
7. `expo-auth-session` checks the returned OAuth state.
8. The app exchanges the authorization code with the PKCE verifier and no client secret.
9. The app stores the resulting tokens in `expo-secure-store`.

This browser-delegated implementation cannot remove step 3. To provide a single email entry with no separate account-creation confirmation, replace this client flow with Microsoft Entra Native Authentication. Initiate authentication with the `registration_required` capability. For an existing identity, continue the email-OTP sign-in challenge; when Entra requires registration, continue directly into the email-OTP sign-up challenge without asking the customer to select **Create one** or re-enter the email. Keep the outward response identical for both paths to avoid exposing whether an email address is already registered. Create the customer identity only after Entra accepts the OTP, then use the returned continuation token to sign the customer in automatically.

In the browser-delegated flow, do not render an OTP input in OLGA or intercept the OTP. In the native-authentication flow, the app may collect the OTP only in memory and submit it directly to Entra through the supported native SDK or API. Never add a custom `/send-otp` or `/verify-otp` endpoint, and never put OTP/token values in logs, crash reports, analytics, Redux persistence, AsyncStorage, or SQLite.

## 6. Restore and refresh the session

On startup, read the secure session. If its access token is still fresh, keep it in memory. If it is expired and a refresh token exists, refresh it through the discovered token endpoint:

```ts
const refreshed = await AuthSession.refreshAsync(
  {
    clientId: entraConfig.clientId,
    refreshToken: stored.refreshToken,
    scopes: [
      'openid',
      'profile',
      'email',
      'offline_access',
      entraConfig.apiScope,
    ],
  },
  discovery,
);

const nextRefreshToken = refreshed.refreshToken ?? stored.refreshToken;
```

Write the refreshed session back to the same secure-store key, including `nextRefreshToken`. Microsoft can rotate refresh tokens, so always replace the stored value when a new one is returned. If refresh fails with an OAuth error, delete the local session and require an interactive login; do not loop indefinitely.

Treat the stable external identity as the combination of token issuer (`iss`) and subject (`sub`). Do not use email address, mobile number, or display name as proof of identity or as the permanent account key.

## 7. Send the access token to Core API

Add the access token only to authenticated-session requests:

```ts
const response = await fetch(`${coreApiUrl}/v1/...`, {
  headers: {
    Authorization: `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  },
});
```

Current MVP limitation: Core API does not yet validate this header, and Core API and NLP API remain directly callable without authentication. Email OTP currently protects only the mobile sign-up/sign-in experience. Do not hide this limitation in the mobile UI or documentation, and do not treat a successful login as server-side authorization. The deferred enforcement work is recorded in [SECURITY_DEBT.md](SECURITY_DEBT.md).

## 8. Sign out

Sign-out must first delete every locally stored token and clear in-memory identity state:

```ts
await SecureStore.deleteItemAsync('olga.entra.session');
setAccessToken(null);
```

For a full Entra browser-session sign-out, open the `endSessionEndpoint` returned by discovery and return through an environment-specific registered post-logout URI. Do not hard-code a logout endpoint that was not returned by discovery. Local sign-out is still required even if browser-session sign-out fails.

## 9. Handle outcomes without leaking data

Handle these cases explicitly:

- `success`: exchange the code once, securely persist the session, and navigate into the app.
- `cancel`, `dismiss`, or browser close: keep the user signed out and allow retry.
- OAuth error: show a generic message and a retry button; record only a safe error category/correlation ID.
- callback mismatch: verify the build claims `olga-dev` and that the exact request URI is `olga-dev://auth`.
- missing refresh token: confirm that `offline_access` is requested; otherwise require interactive login after access-token expiry.

Never log the authorization response object because it can contain a code or tokens. Ensure HTTP/network inspectors, telemetry processors, and crash-report breadcrumbs redact the `Authorization` header and all token values.

## 10. End-to-end dev verification

Use a real development build on a device, then verify both paths:

1. Start with no `olga.entra.session` secure-store entry.
2. Tap **Sign up or sign in with email**.
3. Confirm the browser host is exactly `olgaconnectdev.ciamlogin.com`.
4. Create a customer with an email address not previously used in this dev tenant.
5. Confirm Microsoft delivers the OTP and that OLGA never sees or logs it.
6. Complete the hosted form and confirm the browser returns to the mobile app instead of remaining on the `createuser` page.
7. Confirm an access token and refresh token were obtained without exposing their values in logs.
8. Decode tokens only in a safe local diagnostic tool and verify the tenant/issuer is the dev External ID tenant and the access-token audience is the dev API registration. Do not paste real tokens into tickets or shared websites.
9. Close and reopen the app; confirm the session restores from secure storage.
10. Exercise token refresh and confirm a rotated refresh token replaces the old one.
11. Sign out and confirm the secure-store entry is deleted.
12. Repeat with the same email address and confirm existing-customer sign-in succeeds.
13. Confirm cancel, incorrect/expired OTP, offline, and callback-error paths show safe retry behavior.

For the direct-registration native flow, additionally verify that the customer enters the email only once, an unknown address proceeds directly to the OTP challenge without a **Create one** prompt, the account does not exist before successful OTP verification, registration automatically yields a signed-in session, and the UI does not reveal whether an email was already registered.

The infrastructure-side dev objects expected by this test are:

| Object | Dev value |
| --- | --- |
| External tenant | `olga-connect-dev` |
| Tenant ID | `d6b05a66-a3b7-442c-b56f-d4d7a9e154ba` |
| User flow | `olga_signup_signin_dev` |
| Mobile registration | `olga_mobile_dev` / `e8db01a0-3a93-48e0-86fa-68123e026088` |
| API registration | `olga_api_dev` / `733db389-f55d-4a33-8cd6-18a14393e3d9` |
| Redirect URI | `olga-dev://auth` |

## 11. Production release gate

Do not produce a production build until the separate production External ID tenant and its `olga_signup_signin_prd`, `olga_mobile_prd`, and `olga_api_prd` objects exist and have been tested. The production build must:

- accept only the production output set;
- claim only the production redirect scheme (currently planned as `olga://auth`);
- contain no dev tenant, client, scope, callback, token, or customer data;
- fail its build/config validation when any production value is missing;
- use the same browser-delegated Authorization Code with PKCE flow and secure-storage rules.

Production infrastructure execution remains manual-only. Creating the dev setup does not create or modify the production tenant.

## 12. Mobile team handoff checklist

Before the mobile change is marked complete, confirm that:

- the app uses a supported Entra native-authentication SDK or API and sends the `registration_required` capability;
- an unknown email continues directly into registration without a **Create one** prompt or a second email entry;
- the account is created only after successful Entra OTP verification and the returned continuation token signs the customer in automatically;
- the UI and error handling do not disclose whether the submitted email was already registered;
- the dev build claims `olga-dev://auth` for web fallback and does not contain a production callback;
- the app requests `openid`, `profile`, `email`, `offline_access`, and the dev `access_as_user` scope, and contains no mobile client secret;
- new-customer sign-up and existing-customer sign-in both complete on a physical device;
- access, refresh, and ID tokens are stored only in OS-backed secure storage or kept in memory;
- refresh-token rotation replaces the previous stored refresh token;
- sign-out removes all local token material;
- logs, analytics, crash reports, screenshots, and support tickets contain no OTP, authorization code, or token value;
- Core API requests can include the Bearer token, while the team acknowledges that the API does not yet validate it; and
- the pull request records the tested platform, build version, test date, and sanitized result without including customer data.

## References

- [Expo AuthSession](https://docs.expo.dev/versions/latest/sdk/auth-session/)
- [Expo authentication guide](https://docs.expo.dev/guides/authentication/)
- [Expo SecureStore](https://docs.expo.dev/versions/latest/sdk/securestore/)
- [Microsoft Entra External ID endpoint formats](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-custom-url-domain#configure-your-applications)
- [Microsoft Entra native authentication](https://learn.microsoft.com/en-us/entra/identity-platform/concept-native-authentication)
- [Microsoft Entra native authentication API](https://learn.microsoft.com/en-us/entra/identity-platform/reference-native-authentication-api)
