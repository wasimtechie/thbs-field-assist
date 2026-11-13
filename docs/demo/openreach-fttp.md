# Openreach FTTP presentation rehearsal

This is a synthetic demonstration for field engineering and service delivery. It is not connected to Openreach systems, endorsed by Openreach, or based on approved Openreach working procedures. Engineering checks and test limits require customer validation before operational use.

## Prepare

Run the normal repository setup, migrations and voice-model provisioning first. With the local API running:

```sh
npm run demo:fttp
```

The seed creates a dedicated engineer type, immutable published FTTP form, account and two accepted assignments. Repeating it preserves existing accounts, credentials, work and reports; it does not reset completed demo jobs.

- Flutter engineer: `fttp@fieldassist.demo` / `123456`
- Dashboard supervisor: `admin@thbs.com` / `123456`
- This workspace's dashboard: `http://localhost:3002`

For a stable presentation server, stop the project's development server, run `npm run build`, then `npm run start -w @field-assist/admin -- --hostname 127.0.0.1 --port 3002`. The prepared workspace is currently running this built version on port 3002. Development can resume later with `npm run dev -w @field-assist/admin -- --port 3002`; do not run a build against the same checkout while the development server is serving a rehearsal.

Use the API address in `.local/mobile-config.json` for the Flutter build. On this Mac, Flutter is installed at `.local/toolchain/flutter/bin/flutter` and CocoaPods at `~/.gem/ruby/2.6.0/bin`; the local Ruby installation needs `RUBYOPT=-rlogger`. An ordinary configured Flutter workstation can use:

```sh
cd apps/mobile
flutter run -d DEVICE_ID --dart-define-from-file=../../.local/mobile-config.json
```

Sign out of another demo account or choose Reconnect and sign in online on the unlock screen. The simulator's test passcode prompt accepts `123456`; this is not a Mac password. Confirm that Profile → Offline readiness reports the verified voice package. Refresh My jobs before disconnecting the API.

## Successful installation

1. Open **FTTP-101 · New fibre installation**. Show the downloaded job pack: appointment, access, route, asset references, previous survey note and equipment.
2. Start the report. Follow **Arrival & access → Installation → Service tests → Handover → Photo evidence**. Answers save in the encrypted account database. Voice capture and reviewed cable-label scanning remain available through the existing controls.
3. For a fast rehearsal, choose **Load synthetic example answers → Successful installation example** and confirm the clearly labelled replacement. Explain that these are demonstration readings, not measurements obtained from a network.
4. Add one image in each category: **Before work**, **Installed equipment**, **Test result**. A phone can use its camera. The simulator can attach visibly labelled demo illustrations; the labels persist in the submitted report and dashboard.
5. Review the details. Missing evidence, an unconfirmed arrival/handover check or a failed/unperformed connectivity test prevents a completed installation from being confirmed. The optical reading is recorded; the app does not assert an Openreach-approved optical pass threshold.
6. Confirm with location. Allow the simulator's location prompt and configure a simulated position if needed. Show **saved/queued** separately from a server receipt. To rehearse offline queuing on this simulator, temporarily stop only the project's API server after downloading jobs, then restore it and sync; the simulator shares the Mac's network.
7. In the supervisor dashboard, open Submissions or Review inbox. Inspect the original values and evidence, then approve. The linked job becomes completed. Repeating the same frozen upload returns the same receipt.

## Blocked installation

1. Open **FTTP-102 · Duct obstruction follow-up** and start a separate report.
2. Choose **Unable to complete**, or load the **Blocked duct handover example**.
3. Record what was inspected, the obstruction, **Civils coordination** as next team, and a specific clearance/access action. Attach blocker evidence.
4. Review and confirm. ONT and optical readings are not required for this honest blocked visit.
5. The supervisor records **Request follow-up**, with clear ownership and instructions. The server refuses an attempt to approve this as a completed installation. The original report remains immutable, and the engineer receives the follow-up on refresh.

## Evidence and verification

Evidence is limited to four JPEG/PNG images of at most 120 KB each for this demo. It is stored inside the encrypted local database, hash-checked, frozen into the report and covered by the existing payload hash and stable-receipt retry mechanism. Accepted evidence is retained in the database and displayed in report detail. The low-resolution demo capture is not an agreed operational evidence standard.

```sh
npm test
npm run typecheck
npm run test:fttp
cd apps/mobile
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test/fttp_evidence_native_test.dart -d DEVICE_ID --no-pub --no-uninstall --dart-define-from-file=../../.local/mobile-config.json
```

The final scoped Flutter checks (FTTP workflow, FTTP screens, jobs and location review) pass, and `flutter analyze` reports no issues. The full pre-existing Flutter suite has seven failures in `workspace_journey_test.dart`, `voice_session_test.dart` and `cable_intake_flow_test.dart`; the same seven failures reproduce from the unchanged Git baseline with this SDK. They are not counted as passing checks.

The API check creates labelled synthetic verification records under a temporary engineer, verifies both outcomes and duplicate receipts, then disables that temporary account. It retains immutable reports/reviews. The native integration uses an isolated encrypted test namespace to check missing-evidence rejection, reopen, frozen bytes and refusal to modify queued evidence. It does not certify user presence, physical-phone operation, actual network loss, speech accuracy or full-shift endurance.

After a native integration test, run normal `lib/main.dart` again with mobile-config.json. No APK, public hosting, SSO integration, live Openreach data or production deployment is produced by this workflow.

On the prepared simulator, FTTP-101 has an editable rehearsal draft with synthetic example answers and three labelled illustrations. Both presentation jobs remain open for a live walkthrough.
