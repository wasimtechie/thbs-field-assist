# Flutter account entry

The sign-in screen now uses a video welcome area above a rounded form panel, taking the layout direction from the two supplied references. It keeps the existing THBS purple/teal palette, bundled `dark.mp4` and `light.mp4`, and Light / Dark / System appearance controls. The website login is outside this change.

The shared `AuthLayout` supplies the branded header, appearance control, welcome text and scrollable lower panel. Sign-in has icon fields, password visibility, a pill action, busy state, validation, administrator password-reset guidance and the existing connection settings. Existing tactile feedback and reduced-motion behavior remain in use. The layout scrolls as one surface to keep fields and actions reachable with the keyboard or larger text.

## Get access

The user chose to keep administrator-created accounts. **New to Field Assist? → Get access** opens a matching screen with an illustrative avatar strip and three steps: contact the administrator, receive account/server details and make the initial online connection. **I have my details** and the header back arrow return to sign-in, retaining entered credentials and concealing the password. This screen does not create an account, submit a request, send a message or change the server address. Password help explains the existing administrator reset process.

Account roles, sign-in API, online provisioning, encrypted local storage and offline/sync behavior are unchanged. The initial sign-in still requires a reachable backend. Connection settings validates and saves an address only after the user explicitly saves it.

## Verification and preview

- `flutter test --no-pub`: passed (116 tests reported; the opt-in image capture body runs only when `CAPTURE_AUTH_UI=true`).
- Focused sign-in, video and journey tests with capture enabled: all 9 passed.
- Journey coverage includes theme switching, password visibility, password guidance, retained inputs, keyboard submission, exact password preservation, busy/duplicate-submit blocking, form validation, and 320px layouts with 1.6 text scaling and a keyboard inset in both themes.
- Existing video tests verify mute-before-play, looping, lifecycle/visibility pause and poster fallback.
- `flutter analyze --no-pub`: no issues.

Actual Flutter widget renders: [sign-in](../evidence/auth-redesign-signin.png) and [Get access](../evidence/auth-redesign-access.png). Each preview shows light and dark at 390 × 844 logical pixels, side by side. Capture uses the supplied poster frames through the reduced-motion fallback; these are not new native-device or video-playback acceptance results.

To regenerate the previews from `apps/mobile`, run:

```sh
flutter test --no-pub --dart-define=CAPTURE_AUTH_UI=true test/widget_test.dart test/auth_video_background_test.dart test/auth_entry_journey_test.dart
```

The opt-in preview helper reads fonts from the installed Homebrew Flutter SDK. Adjust that test-only SDK path if using another Flutter installation.

These account-entry changes are now included in the explicitly requested build 2011, together with the subsequent signed-in workspace redesign. The sole installer is `Field-Assist-Android-Test.apk`, SHA-256 `435223d79c4eeed55a2f8433a1ed881351591b695d5d678ecf005bddac8f4966`. Package verification is recorded in `docs/evidence/android-latest-apk-package.json`; future APKs still require an explicit request.
