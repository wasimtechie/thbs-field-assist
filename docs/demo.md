# Reproduce the THBS Field Assist demonstration

## Connected sample data (THBS walkthrough)

Start with [Demo · Fibre rollout](http://localhost:3000/work-orders?boardId=d56c3e6b-d298-4a11-a518-4bda356ffb3e). The connection is: **Sales creates/routes the client → squad and lead → board → assigned engineer → acceptance → site visit and report → supervisor decision**. Each work-order card opens its parties, client, squad, board, asset, response history, report and site visits. The Operations pulse above the cards shows all permitted workspace totals; the board filter narrows the cards below it.

| Client | Squad | Team lead | Engineer logins | Board |
| --- | --- | --- | --- | --- |
| Demo · Orion Broadband | Fibre Delivery | lead1@thbs.com | fibre1@thbs.com, fibre2@thbs.com | [Fibre rollout](http://localhost:3000/work-orders?boardId=d56c3e6b-d298-4a11-a518-4bda356ffb3e) |
| Demo · City Network | Fault Response | lead2@thbs.com | repair1@thbs.com, repair2@thbs.com | [City Network repairs](http://localhost:3000/work-orders?boardId=925a4e17-8553-421c-ab29-a3aae2610da8) |
| Demo · Nexus Business Park | Business Connections | lead2@thbs.com | business1@thbs.com, business2@thbs.com | [Nexus circuit rollout](http://localhost:3000/work-orders?boardId=2ed2d04e-e635-4454-a46e-28182a1e4e17) |
| Demo · Future Sites | Site Planning | lead1@thbs.com | site-survey@thbs.com | [Future Sites surveys](http://localhost:3000/work-orders?boardId=3998fa68-515b-4f55-af3f-689b0012be24) |

The requested local demo accounts retain password `123456`. Use admin@thbs.com for the full workspace and sales@thbs.com for intake and client delivery tracking. Engineers can use the app or their limited dashboard. Account passwords, profiles, role assignments and prior records were preserved.

| Fibre example | Connection to inspect |
| --- | --- |
| F01 | New assignment to fibre1; Pending acceptance; no report yet |
| F02 | fibre2 declined because a sample entry permit is unavailable; reason and original brief remain in Response history |
| F03 | fibre1 accepted; received completed report; still Awaiting review. [Open original report](http://localhost:3000/submissions/5543df6e-8c8e-46d3-ad51-006d223e1c7f). Site visit is 25 minutes: 20 working, 5 on break |
| F04 | fibre2 recorded a partial installation and no test; lead requested a return visit. [Open follow-up report](http://localhost:3000/submissions/32d55488-cfda-4c93-a535-4c206c7ae195) |
| F05 | fibre1 has an earlier partial report and a later approved completion report; both original receipts are retained |
| F06 | fibre2 accepted; ready for a deliberate check-in and a new report |

Open **Asset history**, search `DEMO-ORION-CBL-1042`, then choose that exact reference to see F04 and F05 plus their three original reports. Open **Time tracking** to see nine closed sample visits with working/break/site durations and simulated arrival/departure fixes. No active visit is seeded, so testing a real check-in remains possible.

Open **Messages** as admin@thbs.com to see the admin ↔ lead1 explanation. Sign in as lead1@thbs.com for squad discussions, the Sales handover and the private fibre2 exchange. A participant-only conversation stays private; the administrator does not gain access to other people's chats. All 14 seeded messages start with `[SYNTHETIC DEMO]`.

From the Fibre board, choose **Ask AI → Daily brief** for a board-scoped summary of pending, declined, follow-up and review stages. From F03/F04's report, use **Review with AI** to inspect the original form answers and a possible follow-up draft. AI does not save changes automatically. On the phone, refresh online against this laptop's backend to download the engineer's own new assignments and alerts; this data update requires no new APK.

There are 12 added jobs, 9 synthetic reports, 9 closed site visits and 14 sample messages across four existing clients/squads and four boards (three boards were added; Fibre rollout was reused). Every report is marked as demo data, all locations are simulated and all fixture decisions/responses are explicitly labelled. They are examples, not evidence of real work or attendance.

The repeatable local command is `node --import tsx scripts/seed-connected-demo.ts`. It refuses production/nonlocal databases, validates the published forms, creates missing fixture records once, preserves user edits and does not duplicate messages or visits. Record links/counts are in `docs/evidence/connected-demo.json`; initial and repeat logs are retained beside it.

The explicitly requested Android build **2011** is available at `Field-Assist-Android-Test.apk`. It includes the latest account-entry and workspace UI. Future APK generation still requires an explicit user request; finishing other work does not trigger a build.

Normal app, website and dashboard screens now use THBS product/feature wording without third-party vendor credits. Required notices remain under **Legal notices**. The updated mobile provisioning/settings wording is included in build 2011.

The signed-in Flutter workspace now follows the supplied assistant/rounded-card references, with Home / Jobs / Reports / Team / Profile navigation, a clearer report launcher, report filters and grouped settings. Sign-in and Get access retain their existing design. See the [current mobile design and preview guide](design/mobile-refresh.md). This update is included in build 2011.

Flutter sign-in and the administrator-guided **Get access** screen now follow the supplied reference layouts while retaining the existing videos and appearance choices. See the [account-entry walkthrough and light/dark previews](design/auth-entry.md). These screens are included in build 2011.

To demonstrate employee connections, open [Organisation](http://localhost:3000/organisation), select a person, and switch between **Organisation** and **About**. The Fibre Delivery lead profile joins its Fibre and Survey squads. Everyone can browse these professional details; operational access still follows their role. Edit your own full name from **Account settings → Edit your profile**. See the [organisation walkthrough](design/organisation.md) for how administrators set squad/lead connections.


Start with [Client, squad and messaging rehearsal](design/client-team-messaging.md) for Sales intake, engineer acceptance, lead replies, new credentials and phone connection settings.

For the requested field/dashboard test logins and account creation, profile updates, pause/removal and role demonstrations, see [Accounts and RBAC](design/accounts-rbac.md).

For the expanded assignment → offline capture → supervisor review → follow-up journey, see [Operations demo](design/operations-demo.md). It includes competitor findings, the new work-order/asset-history pages and the exact verification limits.

For the new speech-first conversation and a short client rehearsal, see [Guided voice and demo rehearsal](design/voice-demo.md). It also explains automatic foreground delivery and the distinction between locally saved drafts, confirmed queued reports and server receipts.

For the camera-assisted cable/drum label demo, see [Cable label scanning](design/cable-label-scan.md). Sync the published fibre form and start a new version-4 report to see the camera entry point.

Use synthetic accounts and records only. Run the README setup, models, migration and seed commands. Sign in to the dashboard with the generated administrator credential. Configure a reachable HTTPS API URL and rebuild the Flutter app with the pinned public signing key. Complete this sequence independently on an iPhone and an ARM64 Android phone. Record the exact model, OS, app build, runtime artifact hashes, template/version IDs, dates and observations.

1. Sign in to the Flutter app as the seeded fibre engineer. Approve OS authentication. Provision online and inspect each component. A missing runtime, hash mismatch, storage/key failure, or failed local speech check must not show voice ready. Manual entry remains available after a valid lease/form/store are installed.
2. In the dashboard, open the fibre template. Add a single-select field, label it `Site access status`, and use stable options such as `available:Available`, `restricted:Restricted`, `unavailable:Unavailable`. Enable voice and enter a meaningful question and description. Save, preview and publish. The revision check must reject a stale editor.
3. Tap Sync in the app. Verify the installed version and new field. Start a draft and note its pinned version. Publish a later version and refresh; the existing draft must retain its original schema and hash.
4. Enable airplane mode yourself. Terminate the app using the OS. Reopen it and authenticate locally. Confirm the correct assigned form and saved draft recover. No engineer/type selector should appear. A never-provisioned installation must require online sign-in.
5. Dictate `Replaced twenty metres actually twelve. I have not tested the line.` in a fault-repair run on a separately provisioned account/device. Verify 12 m and `not_tested`, with ambiguous fields left unchanged. The application adapts the same Needle model to flat field-specific schemas; exact correction normalization and explicit unit validation run in application code. The adapter is deliberately conservative. Failed cases stay visible.
6. Try `twelve or fifteen metres`, a missing unit, a non-replacement statement, an explicit manual-value correction, and Undo. Try an identifier marked voice-disabled. The model must never submit a report or execute a job action. Two failed clarifications should result in a manual-entry prompt.
7. Complete every required field by touch if necessary. Review included values and exclusions. Confirm using the checkbox/button. Observe `Saved on this device`, then `Queued`, only after the encrypted transaction commits. Note the local reference. Terminate/reopen and verify the same frozen report remains.
8. Reconnect to the backend and keep the app open/unlocked. Confirmed queued reports retry automatically, subject to backoff; Retry/Sync is also available. Show one stable server receipt and the corresponding historical version in the dashboard. Repeat a lost-response retry through the API test. For safe reopen, first resolve status and cancel/fence the old attempt online. A winning old upload must return its receipt, never a second report.
9. Repeat on the other platform and another engineer type. Sign out with pending work, reprovision a different account, and prove account isolation. Reauthenticate the original account and recover its work. Test expiry/clock rollback, microphone denial, biometric unavailability, backgrounding/calls, route loss, corrupt assets, low storage and interrupted saves.
10. Test large text, Reduce Motion, VoiceOver and TalkBack. Record tap responsiveness and cold/warm latency. Run at least 100 held-out utterances with the required accent/noise/negation coverage, 20 complete reports and a 30-minute mixed session on each platform. Record actual memory, battery and thermal behavior. A Mac result or short test does not pass these device gates.

Device integration tests are a supplement to this script. Do not mark airplane-mode, OS interruption, restart, biometrics, or performance checks passed without real-device evidence.

Project boards, profile avatars and site time walkthrough: [guide](design/boards-profiles-time.md).
