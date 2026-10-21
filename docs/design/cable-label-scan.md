# Cable label capture and form assistance

The first section of the fibre report is now **Cable identification**. Its **Scan cable label** button opens the rear camera only after an engineer chooses it. Capture the printed cable or drum label before opening the packaging, review the recognized values, then choose **Apply to report**. The form acknowledges success only after encrypted autosave commits. The original indigo/teal palette, Light/Dark/System settings, manual entry and guided voice remain available.

Voice entry also introduces this section when mapped label details are missing. Choose **Scan label**, **Enter details**, or **Not available**. After a reviewed scan, the summary offers only missing details for additional entry, then **Continue to work questions**. Enter details lets the engineer select missing fields; spoken prompts accompany exact touch entry and each Save & next awaits local persistence. This guided step never enables dictation for fields whose published schema disables voice. It does not mark an absent label as a manufacturer value or populate an unavailable identifier. Optional cable progress is displayed separately from required job fields.

## Mapped fields

| Printed detail | Form field | Handling |
| --- | --- | --- |
| Cable ID / serial number | `label_cable_id` | Preserve leading zeros and identifier spelling |
| Drum / reel ID | `label_drum_id` | Keep distinct from cable ID |
| Manufactured by / manufacturer | `label_manufacturer` | Use explicitly labelled text; no manufacturer lookup |
| Batch / lot number | `label_batch` | Short text |
| Cable type / specification | `label_specification` | Short text, e.g. `24F SM G.652D` |
| Fibre / core count | `label_fibre_count` | Integer, 1–4096 |
| Printed cable length | `label_declared_length` | Explicit m/km unit; separate from actual cable installed |
| Manufacture date | `label_manufactured_date` | Unambiguous YYYY-MM-DD; edit other formats manually |

These optional fields are voice-disabled because their content is best read from the label. Work outcome, installed quantity and testing results still come from the engineer. The scanner never fills those from a manufacturer's label.

Published schemas define the mappings with `scan: { kind: "cable_label", target: "..." }`. Administrators can change compatible mappings in **Form templates → field properties → Cable label camera mapping**. Each role can occur once per schema. Shared and Flutter validation reject duplicate/type-incompatible mappings. Duplicating a field clears its mapping.

## Recognition, review and storage

Android uses bundled ML Kit Latin text recognition; iOS uses Apple Vision. There is no cloud OCR or language-model request. Clear English/Latin labels with headings are the supported demo input. Brand logos, damaged/curved printing, ambiguous dates, unlabelled numbers and other scripts may need manual entry. Identifiers are never automatically corrected between O/0 or I/1. Conflicting readings are left unresolved. Review offers editable values, selection checkboxes, the photo and expandable recognized text. Existing values are unselected for replacement until the engineer explicitly chooses them.

The camera does not request audio or gallery access. Photos stay temporarily in the private app cache; they are removed on normal exit, retake and foreground interruption. This feature reclaims its own abandoned cache images older than 15 minutes at the next capture after a crash. The photo is not attached to the report or uploaded. Reviewed values use the existing SQLCipher repository and bounded provenance history (`camera_ocr_reviewed`). **Undo last assisted change** also supports the scan application.

Scanning and draft saving work offline after the account/form have been provisioned. Drafts remain local until the engineer reviews and confirms the report with its required location. Confirmed reports enter the existing frozen, hashed outbox. Foreground retry runs while the app is open/unlocked and the backend is reachable. Retries keep the original report values/location and stable receipt; reconnecting does not submit an unconfirmed draft.

## Demo rehearsal

1. Install **Field-Assist-Android-Test.apk**, build 2014, on an ARM64 Android 12+ phone. Install over the previous app to retain local data. Initial sign-in still requires a reachable backend. The default points at laptop loopback; sign-in Connection settings can select the supplied HTTPS endpoint or the laptop's private address on shared Wi-Fi in this demo build. No hosted backend is configured.
2. In the app choose **Sync now** while online, then start a **new** fibre report. The local demo publishes cable identification as immutable version 4. Existing drafts retain their earlier schema/version.
3. Open **Cable identification → Scan cable label**, allow camera access, frame the printed label and choose **Take photo & read label**. The torch is available where supported. Use [the synthetic demo label](../evidence/cable-label-demo.jpg) for a controlled rehearsal; it represents no real manufacturer or asset. An [extended test card](../evidence/cable-label-extended-demo.png) also displays ONT serial `DEMO-ONT-1042` and optical reading `-22.4 dBm` as separate references. The current cable scanner maps the eight cable rows only; ONT serial must be typed, and the optical value is answered by voice after choosing Fully completed. The extra rows do not expand the published scan mappings.
4. Check every identifier, edit uncertain values, select which fields to save and choose **Apply to report**. Observe the local save acknowledgement. Existing values require explicit replacement selection.
5. Enter the work details separately. Verify that printed length `1000 m` does not replace actual installed length `12 m`.
6. Review and confirm with location enabled. If offline, the confirmed report remains queued. Reconnect with the app open/unlocked, then check its server receipt.
7. In the dashboard open **Submissions → the report → Cable identification**. Values appear under the historical version used at submission.
8. Before presenting, test your real phone with representative cable labels, permission denial/recovery, retake, dark mode, background interruption, offline save and reconnect. Camera focus, physical permissions, OCR accuracy and real airplane-mode behavior are physical-device acceptance checks.

## Verification

Build 2012's new guided intake and numeric-estimate confirmation pass all 136 Flutter tests and clean analysis. New flow tests exercise scan review through FormScreen, reviewed-source persistence, selection of only missing label details, manual write failure/retry, cancelled scans/Not available, transition into work voice questions and light/dark large-text layouts. Logs: `cable-intake-{focused-tests,all-tests,analyze}.log`; captures: `cable-intake-{light,dark}.png`. Android package and linkage evidence are `android-2012-*`. This verification does not claim new physical camera or microphone acceptance.

The original camera/OCR integration checks below predate the new guided entry step:

- 84 Flutter tests pass, including parser/validation, replacement consent, empty-result handling and light/dark form/review layout. Final Flutter analysis has no issues.
- 58 shared tests pass. The dashboard production build and TypeScript checks pass.
- Eight local HTTP checks verify versioned publication, provisioning, all mapped fields, separation of printed/installed length, same-byte retry receipt stability and dashboard detail. All verification reports and coordinates are explicitly synthetic.
- The real iOS simulator OCR bridge reads all eight values from an original synthetic bitmap; typed mapping, separate installed length, encrypted draft reopen, reviewed provenance and temporary-image cleanup pass. This runs Apple Vision without a mock OCR channel and does not exercise camera hardware. Evidence: `cable-scan-ios-integration.log` and `cable-scan-native-ios.json`.
- Android debug build 2007 and iOS simulator compilation succeed. The delivered APK passes original-debug-certificate signature verification, ARM64 packaging, bundled video hash checks and 16 KiB ZIP/ELF alignment; the OCR model assets are bundled.
- Physical camera capture, Android OCR runtime and real-phone network recovery remain unverified. Logs and widget-rendered previews are under `docs/evidence/cable-scan-*`; widget previews are not hardware camera evidence.

Implementation references: [Flutter camera package](https://pub.dev/packages/camera), [ML Kit Android text recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android), [Apple Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).

Reproduce the native integration from the repository root:

```sh
node scripts/cable-label-test-config.mjs
cd apps/mobile
flutter test integration_test/cable_label_native_test.dart -d <device-id> --dart-define-from-file=../../.local/cable-native-test-config.json
```

The test creates and removes an isolated synthetic account database. Rebuild/run `lib/main.dart` with `mobile-config.json` afterwards to return the device to the regular demo app.
