# MitiMaiti

Sindhi community matrimony & dating app. One backend, one admin web app, three native clients (iOS Swift, Android Kotlin, Flutter for cross-platform).

## Repo layout

```
backend/        Express + TypeScript API (Node 22, Supabase, Redis, Socket.IO)
admin/          Next.js admin dashboard
mobile/         Flutter app (iOS + Android + web targets from one codebase)
ios/            Native SwiftUI app (XcodeGen-managed)
android/        Native Kotlin + Jetpack Compose app
.github/        CI workflows (iOS, Android, Flutter, backend, admin all build on every PR)
```

`COLLABORATOR_GUIDE.md` is the older, narrative onboarding doc. This README is the practical reference.

## Prerequisites

| Tool | Used by | Install |
|---|---|---|
| Node 22 + npm | backend, admin | `brew install node` |
| JDK 17 | android | `brew install openjdk@17` |
| Xcode 16 | ios | App Store |
| XcodeGen | ios | `brew install xcodegen` |
| CocoaPods | ios (transitively) | `brew install cocoapods` |
| Android SDK | android | `brew install --cask android-studio` (then run once to install SDK), or `brew install --cask android-commandlinetools` |
| Flutter (stable) | mobile | `brew install --cask flutter` |
| Redis | backend | `brew install redis && brew services start redis` |
| gh CLI | git auth | `brew install gh` then `gh auth login` |

After installing JDK 17:
```bash
export JAVA_HOME=/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

## First-time setup

```bash
git clone https://github.com/techygarry/mitimaiti.git
cd mitimaiti

# Backend env (dev mode accepts OTP 123456 without Twilio/Supabase)
cp .env.example backend/.env
# Edit backend/.env: NODE_ENV=development is enough to boot; fill Supabase
# vars to actually persist data

# Backend deps
(cd backend && npm install)

# Admin deps
(cd admin && npm install)

# Flutter deps
(cd mobile && flutter pub get)

# iOS project (regenerate after pulling, after editing project.yml,
# or after adding new Swift files)
(cd ios && xcodegen generate && xcodebuild -resolvePackageDependencies -project MitiMaiti.xcodeproj)

# Android SDK location (only needed once, command-line tools install)
echo "sdk.dir=/usr/local/share/android-commandlinetools" > android/local.properties
```

## Run each app

### Backend
```bash
cd backend
npm run dev          # ts-node + nodemon, port 4000
npm run typecheck    # tsc --noEmit
npm run build        # emits dist/
```

The OpenAPI spec is served at `GET /v1/openapi.yaml` once the backend is running. Drop it into Swagger UI / Postman / Insomnia.

**Auth providers:**
- **Phone OTP** is delivered via Supabase Auth (Twilio under the hood).
- **Email OTP** is delivered via Supabase Auth's built-in SMTP. The built-in is rate-limited to ~2 emails/hour; production must configure a custom SMTP provider in the Supabase dashboard (**Resend free tier** is sufficient — 100 emails/day, 3000/month). Without this, `/v1/auth/email/login` will succeed for the first 1–2 requests per hour and silently rate-limit beyond that.
- **Google Sign-In** uses Credential Manager + Sign in with Google on Android. Backend verifies the ID token with `google-auth-library` against `GOOGLE_WEB_CLIENT_ID` (the Web OAuth Client ID from Google Cloud Console), then mints a Supabase session via `signInWithIdToken`. Android passes the same Client ID to Credential Manager as `serverClientId` (built into the APK via `-PgoogleWebClientId=...` or the `GOOGLE_WEB_CLIENT_ID` env var at build time). Supabase Auth dashboard → Providers → Google must also be enabled and configured with the same Client ID.

### Admin
```bash
cd admin
npm run dev          # next dev, port 3001
npm run build
```

### Flutter
```bash
cd mobile

# Mock data mode (default in debug)
flutter run -d chrome              # web
flutter run -d <ios-simulator-id>
flutter run -d <android-emulator-id>

# Real backend
flutter run --dart-define=USE_MOCK_DATA=false \
            --dart-define=API_BASE_URL=http://localhost:4000 \
            --dart-define=WS_URL=http://localhost:4001 \
            -d chrome
```

### iOS native
```bash
cd ios
open MitiMaiti.xcodeproj
# ⌘R to build and run on simulator. Default DEBUG build uses
# http://localhost:4000/v1 with mocks ON. To hit real backend:
# Xcode → scheme → Edit → Run → Arguments → Environment Variables:
#   API_BASE_URL=http://localhost:4000/v1
#   WS_URL=http://localhost:4001
#   USE_MOCK_DATA=false
```

### Android native
```bash
cd android
./gradlew assembleDebug              # builds debug APK with USE_MOCK_DATA=true
./gradlew installDebug               # installs to connected emulator/device
./gradlew assembleRelease            # USE_MOCK_DATA=false; needs signing config
```

## Mock data vs real backend

Every client supports a `useMockData` flag. When `true` (default for dev builds), services return canned data after a `sleep`. When `false`, services hit the real backend.

| Platform | Where it's set |
|---|---|
| iOS | `AppConfig.useMockData` — env var `USE_MOCK_DATA` or `#if DEBUG` default |
| Android | `BuildConfig.USE_MOCK_DATA` — defined per buildType in `app/build.gradle.kts` |
| Flutter | `ApiConfig.useMockData` — `--dart-define=USE_MOCK_DATA=...` at run time |

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push/PR to `main`:
- **Backend** — `tsc --noEmit` + `tsc` build
- **Admin** — `next build`
- **Flutter** — `flutter analyze`
- **iOS** — `xcodebuild` (simulator, unsigned)
- **Android** — `./gradlew assembleDebug`

Cold runs take ~5 min; cached runs ~2 min.

## Auth & secrets

- Push uses `gh` CLI as credential helper. After `gh auth login`, run `gh auth setup-git`.
- Don't put tokens in remote URLs. If you see a `ghp_…` in `git remote -v`, fix it: `git remote set-url origin https://github.com/techygarry/mitimaiti.git`.
- `.env` is gitignored. `android/local.properties` is gitignored. Don't commit either.

## Common gotchas

- **iOS "Cannot find X in scope"** — usually means you added/renamed a Swift file and didn't run `xcodegen generate`. Run it from `ios/`.
- **iOS SPM package errors** — after editing `project.yml` packages, also run `xcodebuild -resolvePackageDependencies -project MitiMaiti.xcodeproj`.
- **Android emulator can't reach localhost backend** — emulator's loopback to host is `10.0.2.2`, not `127.0.0.1`. Default debug `BASE_URL` already uses this.
- **Flutter dev tries https on a fresh install** — defaults are prod URLs. Pass `--dart-define=USE_MOCK_DATA=true` (mock) or override the URLs.
- **Backend boots but every API call fails** — Supabase env vars are missing. Dev mode (`NODE_ENV=development`) lets auth succeed without Supabase but DB-backed endpoints will still fail.
- **Push notifications don't fire** — Firebase isn't configured. The clients have FCM token registration wired but you need `google-services.json` (Android), `GoogleService-Info.plist` (iOS), and `flutterfire configure` (Flutter). Run `gh auth setup-git` first if you need to push from this machine.
