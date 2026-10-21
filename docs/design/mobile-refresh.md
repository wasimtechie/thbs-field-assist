# THBS Field Assist mobile interface

## Current workspace redesign — 16 October 2026

The two supplied assistant/insurance app references guide the signed-in experience: soft surfaces, rounded cards, quiet supporting text, clear primary actions and compact pill controls. The original purple/teal palette and Light / Dark / System preference remain. Sign-in, Get access, video backgrounds and their base theme were left untouched.

A scoped `WorkspaceShell` wraps authenticated routes. Home, Jobs, Reports, Team and Profile have a shared bottom navigation bar. Capture, review, receipt, visit and conversation routes retain their focused layouts; the bar also hides for the keyboard. The workspace theme is inherited by camera and voice routes opened inside it. Account entry keeps the original global theme.

- **Home:** personalised greeting, account/alert actions, a report launcher with a code-drawn purple/teal companion, downloaded job/report/message counts, draft continuation and delivery/readiness details. Start report invokes the same controller action as before. Counts reflect downloaded/local state, not invented live presence or quotas.
- **Jobs:** consistent header/filter controls, quieter site/date metadata, shorter response labels and compact status cards. Assigning/assigned avatars, acceptance/decline, supervisor feedback and site-time actions are retained.
- **Reports:** All / Drafts / Waiting / Received / Needs attention filters. Filtering changes only the visible list. Saved, queued, syncing, attention and server-accepted states retain their existing actions and meanings.
- **Capture/review/receipt:** individual field cards, clearer section headings, pill actions and the shared workspace typography. Required fields, units, validation, save feedback, camera OCR, explicit confirmation, location and frozen receipt behavior retain their existing implementation.
- **Team/messages/alerts:** shared headers and pill tabs, colleague avatars, softer message bubbles and a floating message composer. The send action remains explicit; no messages or notifications were sent by this UI work.
- **Profile/settings:** a profile summary and grouped preferences; avatar selection and offline readiness expand when needed. Appearance, spoken questions, speech rate, motion reduction, repair, lock, sign-out and Legal notices remain accessible. Avatar captions were removed while semantic names remain.
- **Voice:** a matching companion above the live question, pill answer choices and the existing glowing controls below. The companion reacts to actual speech/listening state and level; its idle state has no perpetual animation controller. Existing first question, partial/full/not-completed choices, automatic local answer save, save-failure recovery, pause/end and review-before-send logic remain.

No animation library, runtime model, API, database schema or network/background behavior was changed. Existing press feedback and animated icons are retained. Decorative transitions respect reduced motion; the new companion is vector/code rendered with existing colours.

### Verification and preview

The full Flutter suite passes **120 tests**. Four new in-memory journey checks cover every navigation destination, report filters without changing records, restored account-entry styling, and 320 × 640 layouts with 1.6 text scale and a keyboard inset in both themes. Existing report/location/review/queued-receipt, job and voice-save journeys also pass. Final analysis has no issues. Final navigation checks were repeated after the send-button styling refinement.

Current previews use the actual Flutter app/router/widgets at 390 × 844 logical pixels, with synthetic in-memory work and fake audio. They include no OS status bar and are not new physical-device or native performance acceptance evidence. No live microphone, GPS, API account or employee message was used. Captures are in `docs/evidence/workspace-redesign-{light,dark}-{home,jobs,reports,team,conversation,settings,alerts,form,review,receipt,voice,voice-saved}.png`; logs and the evidence index are alongside them.

To repeat the full verification and capture from `apps/mobile`:

```sh
flutter test --no-pub --dart-define=CAPTURE_WORKSPACE_UI=true --dart-define=CAPTURE_APP_UI=true --dart-define=CAPTURE_VOICE_UI=true
flutter analyze --no-pub
```

The opt-in capture helpers load fonts from the local Homebrew Flutter SDK. The renderer fixtures are test-only and do not ship in the app. Following the user's explicit build request, Android build 2011 now includes this workspace and the preceding account-entry changes. Its signing certificate matches build 2010; package/ELF alignment, all 133 avatar hashes, their licence, and both supplied video hashes pass. Package details are in `docs/evidence/android-latest-apk-package.json`. Future APKs still require an explicit request.

## Earlier polish — 15 October 2026

Direction: a tactile, focused field workspace. Preserve the original light canvas (#f6f7fb), graphite text (#252a3b), indigo primary (#6554c8), and teal voice accent (#1c9a89), as requested. Dark mode adapts their luminance for legibility; Light remains the default and System follows device appearance.

CRED informs depth, confident type and responsive controls. The Oil UI reference (https://github.com/oil-oil/oil-ui; visual-language.md, motion.md, media.md) informs hierarchy, purposeful motion and screenshot review. Original branding and reporting actions are retained. No third-party animation library, remote animation asset or new runtime dependency was added.

## Changes

- Semantic light/dark colors across sign-in, unlock, provisioning, home, forms, voice sheet, review, receipt, queue and settings.
- Light/Dark/System choices before unlock and in Settings, stored as a device preference in secure storage. Writes are serialized; errors restore the last saved choice and display a message.
- Clearer typography, sculpted fibre material, a dominant assigned-report card and quieter draft/sync entries.
- Shared Material button feedback: spring compression/release, selection haptic, normal focus/ink/disabled semantics and immediate activation. Keyboard presses use the same widget-state path.
- Vector icons slide/turn with pressure (arrows, settings, sync) and cross-fade/scale on actual state changes. They do not invent microphone activity or completion.
- Home sections enter once in reading order; form progress interpolates when valid answers change; receipt check draws only for queued/syncing/accepted records.
- In-app and OS reduced-motion preferences disable decorative movement. The procedural 2,304-triangle fibre object stops when hidden, backgrounded, busy or constrained by the native power/thermal check. No decoration sits behind form inputs or inference.
- Removed the duplicate review heading and kept the report name/version and shortened appearance copy. Kept version, saved/queued/accepted distinctions, validation, provenance and repair states visible.

## Review and evidence

One independent screenshot review of existing-app polish (no score): receipt check was faint, review introduction/padding tall, dark off-switch contrast weak. Corrected these and inspected updated renders. Theme controls wrap at large text sizes.

Flutter suite: 36 passing tests, including 160% sign-in text scaling, light/dark home at 160%, press/release/cancel/disabled behavior, keyboard with reduced motion, persisted appearance, and report journeys through review and local queued receipt. Appearance journeys repeated after fixes. Isolated in-memory report fixtures exist only in test/appearance_journey_test.dart; the shipped main keeps real authentication, encryption and sync. Analysis passed with no issues.

Evidence: docs/evidence/mobile-refresh-{light,dark}-{home,form,review,receipt,queue,settings}.png are Flutter test renders at 390×844 logical pixels with Roboto and Material Icons loaded. Native iPhone simulator captures use mobile-refresh-iphone-* names. Inspected at reading size. Physical Android/iPhone, VoiceOver/TalkBack, live microphone accuracy, phone animation latency/frame rate and endurance remain unverified. No measured performance claim is inferred from screenshots or widget tests.

Native target: iPhone 17 Pro / iOS 26.5. Build and native appearance switching verified. Android package is ARM64 debug for manual testing. Dashboard/backend appearance was not changed by this mobile polish.

## Manual test

Settings → Appearance → Light, Dark or System. Sun/moon icon on sign-in/unlock opens the same options. Reduce motion is in Settings. Updated APK retains the local API endpoint; initial phone login/model provisioning require a reachable backend. No hosted endpoint was configured.

A native update check exposed stale absolute voice-package paths after the iOS sandbox moved. Restore now derives the package directory from the current Application Support root and the existing manifest fingerprint, then verifies every byte/hash before loading. It does not skip integrity checks or silently mark a package ready. A relocation/corruption regression test passes; no model re-download is needed solely because the container path changed.
