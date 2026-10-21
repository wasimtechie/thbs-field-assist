# Report location — 15 October 2026

Field Assist requires a fresh foreground device location when a user confirms a report. Android requests coarse/fine location; iOS requests When In Use access. Precise access gives a better fix, but approximate access is accepted and its reported accuracy remains visible. No background permission, periodic tracking or third-party location SDK is used.

## Capture and recovery

The review screen explains why location is required. Confirm with location requests one fix and freezes latitude, longitude, accuracy in metres, UTC capture time and the platform's simulated/mock signal alongside the existing answers. Native capture is bounded to 60 seconds, and Dart has a 75-second fallback. Coordinates, accuracy and freshness are validated before confirmation. A cancelled request, denied permission, disabled service, stale fix or timeout leaves the encrypted draft intact. Settings and retry actions are available for permission/service failures. Returning from Settings may require unlocking again. A locked or changed account cannot complete the pending confirmation.

The existing encrypted SQLCipher database stores the location inside the immutable frozen JSON payload; no local database migration is needed. The payload hash covers location as well as answers. Queue retries send the original bytes, so moving after confirmation does not change the recorded position. Backend validation compares capture time to confirmation time, not upload time, allowing a delayed offline upload. Old clients/queues without location remain accepted and show Not captured.

## Sync and dashboard

An online confirmation starts the existing outbox immediately. Offline reports retry while the app is open and unlocked, using the existing bounded backoff. Internet connectivity alone is insufficient if the configured API cannot be reached. Locking/backgrounding stops the foreground pump; reopening and unlocking restarts it.

Overview's recent reports and Submissions have a Location column. Submissions refreshes every 10 seconds while visible, and Overview every 15 seconds. Open a report to see the location card, accuracy, UTC capture time and Open map link. The map URL is opened only on a user's click; no embedded map or reverse-geocoding request runs automatically. This is the report's captured position, not a live engineer-tracking view.

The PostgreSQL migration `202610150003_report_location` adds nullable Report.location JSONB and is applied locally. The same migration must be deployed alongside server code in another environment. Shared schemas and OpenAPI describe the new fields.

## Verification

- Shared TypeScript suite: 52 tests pass, including 12 location contract cases covering coordinate/accuracy ranges, stale/future fixes, delayed upload and legacy compatibility.
- Flutter suite: 58 tests pass, including seven channel/model location cases. Additional focused controller tests cover denied permission followed by a successful retry and locking during capture, preserving answers and draft state.
- Local HTTP check: 12 checks pass for location persistence, stable receipt on retry, list/detail/overview responses, invalid coordinates/accuracy/time rejection and old payload compatibility. The test uses explicitly synthetic Bengaluru coordinates and records; it is not evidence of an actual visit.
- Dashboard location card inspected at 1440 px and 390 px widths; the narrow page has no horizontal overflow. Evidence: `../evidence/location-dashboard.jpg` and `../evidence/location-dashboard-mobile.jpg`.
- Android manual APK: versionCode 2006, ARM64, Android 12 or newer, 149,992,120 bytes. Foreground location permissions, original debug certificate/v2 signature, bundled authentication video hashes and 16 KiB ZIP/ELF alignment pass. SHA-256: `04fb010fb928660f63cdf9c3db42f1b4eb6845bd720292086db46a44678c4357`. Package evidence is recorded under `../evidence/location-*`.
- iPhone simulator build succeeds, including the Core Location implementation and When In Use usage description (`../evidence/location-ios-build.log`). This verifies compilation, not a hardware GPS or permission-dialog test.

Physical Android/iPhone GPS capture, OS permission dialogs and airplane-mode recovery have not yet been tested on hardware. Simulator/synthetic evidence does not establish positioning accuracy or background operation.

## Device rehearsal

1. Install the updated app. Sign in/provision through a reachable API and download the voice assets if needed.
2. Enable device Location Services. Fill a report, review it and select Confirm with location. Allow location while using the app; choose Precise for the best result.
3. With the API reachable, wait for Accepted. Open dashboard → Submissions → the report → Report location. Compare capture time and accuracy with the expected visit.
4. With location still enabled, disconnect internet and confirm another report outdoors. It should become Queued with captured coordinates. Reconnect internet and keep the app open/unlocked until Accepted; verify that the original coordinates and one receipt are retained.
5. Deny location or turn Location Services off. Confirmation should offer recovery and keep all answers. Re-enable, unlock if needed and retry.

The local test APK still uses `http://127.0.0.1:3000/api/v1/`. On an unconnected physical phone this address refers to the phone, so sign-in and uploads cannot reach the laptop. A reachable trusted API endpoint and a rebuild are required for independent remote-device testing; this change does not publish the backend.
