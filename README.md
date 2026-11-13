# THBS Field Assist

The narrated product demo lives in [apps/product-demo](apps/product-demo/README.md). Run `npm run demo` for the local Player at `http://localhost:3001/`, with 13 feature chapters and fullscreen presentation controls. `npm run demo:render` exports the 1080p MP4 and English subtitles; it does not build an APK.

Flutter engineer app for **iOS and Android**, Next.js operations dashboard, and a shared PostgreSQL API. Implements the updated **PRD 3.0**, rather than the earlier SwiftUI specification. All records in this workspace are synthetic.

The product landing page is available locally at **http://localhost:3000**, with workspace sign-in at **http://localhost:3000/login**, while the development server is running. Generated login credentials are in `.local/credentials.txt`; they are not committed. The seed provides `admin@fieldassist.demo` and four engineer accounts: `fibre`, `repair`, `business`, and `survey` at `fieldassist.demo`.

The requested THBS demo accounts, role matrix and management workflow are documented in [Accounts and RBAC](docs/design/accounts-rbac.md). Use `admin@thbs.com` / `123456` to manage Field engineers and IT employees. Waseem is Operations Manager; test is Viewer. All seven requested field logins use `123456` and their assigned form. These explicitly requested local demo credentials are distinct from the generated legacy accounts.

Clients, squads, Sales/Team Lead access, limited engineer dashboard, private/team messaging, fuzzy colleague search, in-app alerts and encrypted message/response queues are described in [Client-to-team demo](docs/design/client-team-messaging.md). The current manual Android APK is build **2014**, including scan-first cable guidance, confirmed numeric estimates, populated voice forms, the Android native voice-library repair, notification-friendly audio focus, automatic speech completion and the location-permission preflight. Its sign-in Connection settings can use a reachable server or shared local Wi-Fi address without USB. New dashboard demo logins are `lead1@thbs.com`, `lead2@thbs.com` and `sales@thbs.com`, password `123456`. Alerts refresh while the app is open; closed-app push is not configured.

## Openreach FTTP demonstration

Run `npm run demo:fttp` after local database setup, then sign in to Flutter with `fttp@fieldassist.demo` / `123456`. Two synthetic UK assignments demonstrate a completed installation and a blocked-duct handover, guided stages, encrypted photo evidence, completion gates, offline delivery and supervisor review. See [the presentation rehearsal](docs/demo/openreach-fttp.md) for setup, credentials, evidence limits and verification. This demo is not connected to or endorsed by Openreach.

## Local setup

Requirements: Node 20.20 or newer, npm, PostgreSQL 17 or Docker, Flutter 3.44.8 / Dart 3.12.2. iOS requires Xcode, CocoaPods, and a physical iPhone for acceptance. Android requires JDK 21, SDK 36, NDK 28.2.13676358, and a physical ARM64 phone for acceptance. Keep several GB free for native build tools.

```sh
npm ci
npm run setup
npm run db:start
npm run db:generate
npm run db:migrate
npm run db:seed
npm run dev
```

`db:start` uses installed PostgreSQL tools and keeps its cluster in `.local/postgres` on port 54329; it does not modify another database service. Alternatively, after setup, `docker compose --env-file .env up -d postgres` starts the provided PostgreSQL service on that port. Do not run both at once. `npm run db:stop` stops only the project-local native cluster.

The setup command preserves an existing `.env`. It generates random account passwords and an ES256 signing key. Never commit `.env`, `.local`, secure account keys, production records, or model weights.

## Dashboard

```sh
npm run build
npm run dev
```

The public landing page introduces the product, offers a keyboard-accessible three-step workflow, and links into sign-in. Protected routes: `/dashboard`, `/templates`, `/templates/:id/edit`, `/engineers`, `/engineer-types`, `/devices`, `/submissions`, and `/submissions/:id`. The editor supports field creation, editing, deletion, duplication, drag ordering, keyboard move buttons, sections, constraints, conditional visibility, voice questions, preview, optimistic saves, and immutable publication. Engineer types select published defaults. Device status explicitly reflects the last contact.

New operations pages: `/work-orders`, `/review-inbox` and `/asset-history`. Engineers download briefs and feedback from **My jobs** in Flutter. See [Operations demo and competitor findings](docs/design/operations-demo.md) for the full assignment-to-approval rehearsal.

The dashboard now includes an [AI operations assistant](http://localhost:3000/assistant), report evidence review, and a visit brief writer. They run on demand using permitted records and keep all changes under human control. See [Dashboard AI](docs/design/dashboard-ai.md) for demo steps, data scope and limits. To enable AI without saving a key to disk, stop the existing dev server and run:

```sh
python3 scripts/dev-with-ai.py
```

Enter your OpenAI project key at the hidden prompt. The helper checks a tiny synthetic request and starts the server with the key in its process environment. Re-enter it after restarting; ordinary `npm run dev` also accepts a key supplied by your deployment's secret environment. Never use `NEXT_PUBLIC_` for this key.

The dashboard reads actual database counts. The sample receipts visible after verification were accepted through the real API by `scripts/smoke.ts`. There are no fixed submission arrays or fake analytics.

## Flutter app

```sh
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

Entry point: `apps/mobile/lib/main.dart`. iOS shared scheme: **Runner**. Android application ID: `dev.fieldassist.field_assist`; debug/profile/release variants use Flutter's standard build modes. Release signing is deliberately not configured with a development key.

`npm run setup` creates `.local/mobile-config.json` with a public signing key and an explicit local-development HTTP exception. If an older `.env` already exists, run `node scripts/mobile-config.mjs` to regenerate only this public build configuration. For a physical phone, edit `API_BASE_URL` in that file to a reachable **HTTPS** development endpoint ending in `/api/v1/`; use a certificate the phone trusts. A phone's localhost is the phone itself. Do not disable certificate verification or publish this service without authorization.

```sh
cd apps/mobile
flutter devices
flutter run -d DEVICE_ID --dart-define-from-file=../../.local/mobile-config.json
flutter build ios --debug --no-codesign --dart-define-from-file=../../.local/mobile-config.json
flutter build apk --debug --target-platform android-arm64 --split-per-abi --dart-define-from-file=../../.local/mobile-config.json
```

An iPhone 17 Pro simulator running iOS 26.5 is installed on this laptop and has launched the real Flutter sign-in screen. Its localhost can reach this Mac's local API. The installed Xcode 27 exposes simulators through **Device Hub**, at `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`. Launch it to interact with the simulated phone. A simulator device-authentication prompt accepts test input; it does not require your Mac password. Simulator results do not replace the PRD's physical iOS/Android gates.

If the host Flutter configuration points to a different Android SDK, reuse an installed matching NDK for this project without changing global settings:

```sh
FIELD_ASSIST_NDK_PATH=/absolute/path/to/android/sdk/ndk/28.2.13676358 \
  flutter build apk --debug --target-platform android-arm64 --split-per-abi \
  --dart-define-from-file=../../.local/mobile-config.json
```

This app has no role-switch control. Sign in with an assigned engineer account, approve the real OS local-auth prompt, and provision online. Account databases are encrypted and isolated. Manual fields remain usable if voice assets or inference fail. Drafts pin their installed form version. Confirmation commits a frozen outbox entry before showing the local receipt. Sync reuses exact bytes, reconciles uncertain acceptance, and requires a server cancellation fence before reopening a frozen report.

## Offline voice assets

The current phone demo is **0.3.0**, with Moonshine Small Streaming English, embedded Silero VAD, source-validated local Needle3 extraction and fixed-speaker Kokoro. Qwen and its native runtime are excluded. The signed ARM64 debug APK is **453,089,062 bytes (453.1 MB)**, down **47.75%** from 0.2.2. It retains the summary capture, added-detail merging and reading-confirmation fixes. Build number **18** (versionCode **2018**) upgrades the previous demo without uninstalling. Setup, test speech, storage requirements and the signed demo access window are in the [current voice demo guide](docs/demo/voice-demo.md).

### Historical voice baseline

An accuracy repair is now verified in source and awaits the next explicitly requested APK. It restores full captured audio and the pre-2014 recorder configuration, allows a natural pause and asks for clarification when completion speech is unclear. All 156 current Flutter tests, analysis and five native generated-speech cases pass; physical-phone retesting remains pending. The installer and phone still have **2014**, which has a reported recognition regression. See [accuracy repair evidence](docs/evidence/voice-accuracy-repair.json).

Build **2014** includes automatic completion from microphone PCM, a separate cached Saved acknowledgment, notification ducking that retains capture and permission-before-GPS location confirmation. It retains the Android audio-focus handoff repair, preventing the recorder from interrupting its own speech session when listening starts. Shared-session callbacks still pause for external interruptions and headset removal. All 150 Flutter tests pass and analysis is clean. It also includes the earlier voice-library repair: `libfield_voice.so` declares `libm.so` and its source linker rejects undefined symbols. The packaged APK passes `python3 scripts/check-android-voice-linkage.py Field-Assist-Android-Test.apk`, original certificate continuity, ARM64-only packaging and 16 KiB ZIP/ELF checks. Full physical-phone microphone/camera acceptance remains a separate rehearsal. Initial sign-in/provisioning requires a reachable backend; no hosted server is configured. Install over the existing app to retain local data rather than uninstalling.

For the current version-code convention, `--split-per-abi --build-number=14 --target-platform android-arm64` produces ARM64 versionCode 2014. Use the existing project Gradle cache (`GRADLE_USER_HOME=/Users/wasim/Desktop/btxopen/.local/gradle`) on this laptop. Only generate another APK after an explicit user request.

```sh
python3 scripts/provision-models.py
```

This downloads pinned official Whistle and Needle 3 weights and ARM64 runtime archives plus the official sherpa-onnx Kokoro English package. It verifies source hashes, emits per-file hashes and byte lengths, and writes `fixtures/voice/model-sources.lock.json`. Large files live in ignored directories; source and licence records are included. The Flutter app downloads assets from authenticated, resumable API routes, verifies each file, and activates only a completely verified package after a local speech smoke test.

The local `packages/field_voice` package uses Flutter's supported `package_ffi` build hooks. The actual pinned C header was inspected. Native inference runs on one persistent worker isolate; the same single Needle 3 configuration is used throughout. Kokoro uses sherpa_onnx 1.13.8 with local ONNX, voices, tokens, and phonemizer data. There is no OS speech/TTS or cloud-model fallback.

See [runtime manifest](docs/runtime-manifest.md) for the measured integration findings, memory ownership, model activation limitations, and platform verification status.

## Verification

```sh
npm test
npm run typecheck
npm run test:api
npm run test:e2e
cd apps/mobile
flutter analyze
flutter test
```

The API and browser suites require the running local server and seeded PostgreSQL database. Playwright uses installed Chrome. Tests make synthetic writes: they publish versions, add a supported field, record a clearly identified API-test device, and accept sample reports. They preserve previous drafts and versions. The seed can run repeatedly without overwriting work.

Physical-device integration entry point:

```sh
cd apps/mobile
flutter test integration_test/device_journey_test.dart -d DEVICE_ID --no-uninstall \
  --dart-define-from-file=../../.local/mobile-config.json \
  --dart-define=TEST_ENGINEER_EMAIL=ENGINEER_EMAIL \
  --dart-define=TEST_ENGINEER_PASSWORD=LOCAL_TEST_PASSWORD
```

The operator must handle real OS biometric prompts. This test does not pretend to toggle airplane mode or force-terminate itself. Follow [the device demo](docs/demo.md) for those checks. Do not put real passwords into shared shell history; use a private local define file for device test credentials.

The focused native storage/delivery integration test has passed on the iPhone simulator. It uses real SQLCipher, secure storage and HTTP to check draft reopen, interrupted-upload recovery, identical frozen-byte retry, stable receipts and account namespace isolation. It opens the repository directly without a local-auth prompt and therefore does not certify biometric access, airplane mode, UI entry, or process termination. Normal application entry still requires device authentication.

```sh
# From the repository root; writes ignored, owner-readable test credentials.
node scripts/mobile-test-config.mjs
cd apps/mobile
flutter test integration_test/persistence_sync_test.dart -d DEVICE_ID --no-pub --no-uninstall \
  --dart-define-from-file=../../.local/mobile-test-config.json
```

After a simulator integration run, rebuild/run `lib/main.dart` using **mobile-config.json**, not the private test configuration, to return to the normal app.

Use `--no-uninstall` for native integration tests on this shared demo simulator. Flutter otherwise uninstalls the test app at completion, removing its downloaded form, models and local database while its Keychain identity remains. That leaves the next normal app launch requiring online provisioning again.

Actual results, screenshots, native build logs, and remaining gates are recorded in [progress and acceptance evidence](docs/progress.md) and `docs/evidence/`. A source build or host smoke test does not establish physical iOS/Android acceptance, a 100-utterance score, or full-shift endurance.

## API and operations

[OpenAPI 3.1 contract](docs/openapi.json) describes `/api/v1`. Shared TypeScript/Dart fixtures cover canonical hashes, typed values, false/zero/missing distinctions, both visibility operators, conditional required fields, and signed offline entitlements.

```sh
# Explicit, destructive development reset; refuses production/nonlocal databases.
npm run db:reset -- --confirm-delete-demo-data
```

No public hosting, production adapters, real customer data, messaging, or production SSO are configured. Pending device evidence and any incomplete requirements are listed explicitly in the progress report.

Project boards, profile avatars and site time walkthrough: [guide](docs/design/boards-profiles-time.md).

Connected dummy-data walkthrough: [client → squad → lead → engineer → report → review](docs/demo.md#connected-sample-data-thbs-walkthrough). Includes 12 jobs across four boards, original report history, closed site visits and clearly labelled sample conversations. Re-run `node --import tsx scripts/seed-connected-demo.ts` locally without duplicating existing fixtures. Generate an APK only when explicitly requested by the user.

### Manager-defined FTTP closure MVP

The five-scenario closure assistant and prepared 15-type catalogue are described in [the presentation runbook](docs/demo/closure-mvp.md). Seed the separate engineer and seven stage-specific assignments with `npm run demo:closure`; validate the local API with `npm run test:closure`.

The offline phone voice workflow, prepared VibeVoice questions and VibeVoice/Ming evaluation are covered in [the voice demonstration guide](docs/demo/voice-demo.md).
