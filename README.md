# SMIUNotes Contributors App

Dedicated Android Flutter app for approved SMIUNotes note contributors.

## Scope

- Student ID + password login through existing `https://smiunotes.com` login flow
- Contributor-only workspace using existing `/staff` server authorization
- Dashboard, note upload/management, profile, and approval/rejection notifications are the planned native modules
- No admin or updates editor functions

## Current status

**Prototype only:** the first version embeds the existing web workspace in a WebView. It is **not yet a native contributor experience**, and PDF upload and mobile device behavior have **not been verified**. Server-side authorization must be confirmed before release. The existing website/database remain unchanged.

## Setup

Requires Flutter SDK and Android SDK:

```sh
flutter create --platforms=android --org com.smiunotes .
flutter pub get
flutter analyze
flutter run
```

Ensure `android.permission.INTERNET` is included in AndroidManifest.xml.

## Security

Never commit passwords, credentials, Supabase service-role keys, or R2 secrets. Only the production server can authorize contributor access. Do not treat WebView navigation filtering as an authorization boundary.
