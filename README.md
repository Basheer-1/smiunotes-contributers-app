# SMIUNotes Contributors — Android

Native Android Flutter application connected to the existing SMIUNotes student identity, notes database, and private Cloudflare R2 media storage.

## Current implementation

- Native Student ID/password and Cloudflare Turnstile login through existing SMIUNotes mobile authentication.
- Encrypted persistent session with lazy JWT refresh and in-memory access tokens. A temporary server outage never erases the saved login; explicit sign-out erases local credentials.
- Server-enforced approved contributor or administrator roles.
- Native dashboard, own-note counts, draft creation, scoped subject picker, draft edit/delete (with confirmation), original PDF picker, watermark and WebP page conversion (Android PdfRenderer), progress/reset/private preview.
- Native profile, account avatar, contributions history, notifications (read, clear), pull-to-refresh.
- No admin publishing UI. **Only administrators can approve/publish through the existing website.**

## Backend deployment matrix

| API | Production | Source |
| --- | --- | --- |
| `/api/mobile/v1/auth`, `/session` | Live | Existing SMIUNotes |
| `/api/mobile/v1/contributor-workspace` GET + POST | Live | `fix/contributor-native-login-gateway` |
| `/api/mobile/v1/notifications`, `/avatar` | Live | Existing SMIUNotes |
| `/api/mobile/v1/contributor-media` | **Not deployed** | `feat/contributor-native-media-validation` |
| `/api/mobile/v1/contributor-render` | **Not deployed** | `feat/contributor-native-media-validation` |
| `/api/mobile/v1/contributor-notes/[id]` | **Not deployed** | `feat/contributor-native-media-validation` |

**Do not claim the native PDF pipeline is fully working until these server endpoints are deployed, a real contributor account passes upload/convert/preview/review QA, and an administrator confirms publication.** The native media branch is isolated because Vercel hit its Free deployment limit on 22 November 2026. Never bypass this or alter plan/billing without owner approval.

## Android QA

The workflow [Contributors Android QA APK](.github/workflows/android-apk.yml) uses Flutter 3.50.1 to run analysis, tests, and a **debug** APK build. Download the APK from the corresponding completed GitHub Actions run's artifact. Debug signing is not appropriate for production release.

On a test phone:

1. Sign in with a verified contributor/admin account.
2. Force-stop/reopen the app; verify persistent session without a second login.
3. Check dashboard, own-note list, profile and inbox; verify data is current after Refresh.
4. Once media APIs deploy, create private draft and upload a PDF under 20 MiB with 1–60 pages.
5. Verify watermarked WebP pages, privacy, page preview, conversion reset, draft editing/deletion and admin review.
6. Test expired token recovery, offline restart, explicit logout, unauthorized roles, and own-note-only access.

If a backend API is missing, treat it as a **server deployment blocker**, not a bad password.

## Security and restrictions

The app never contains R2 secret keys, Supabase service-role keys or Turnstile secrets. The mobile API and Postgres RLS must validate every user and ownership, including admins' own notes. Signed R2 URLs are short-lived; the private original is never publicly readable. Testers must not paste session tokens or passwords into issue reports.

## Build

With Flutter + Android SDK installed locally:

```sh
flutter create --platforms=android --org com.smiunotes .
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Add `android.permission.INTERNET` to the manifest; the CI workflow handles generation. For production, use a dedicated package identifier, release key, and Play/App Signing configuration; do not distribute debug build as final.
