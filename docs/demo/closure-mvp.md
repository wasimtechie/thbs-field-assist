# FTTP closure assistant — manager's MVP

This is a synthetic presentation build for field engineering and service delivery. The manager's documents describe proposals, not approved Openreach forms, working procedures, test limits or deployed integration contracts. No Openreach system is updated and no messages are sent to another team.

## Delivered scope

The Flutter app implements the five FTTP scenarios: standard provision, blocked underground duct, missing/incorrect CBT, ONT fitted without active service, and a remote multi-stage build. The original five banks retain 125 unique question IDs and bank version 1. Shared questions are captured once; the executable form contains 87 canonical facts, including explicit controls that resolve ambiguous source pseudocode. Published policy revisions and schema hashes pin the exact rules used for each report.

The broader catalogue is **prepared**, not enabled as 15 operational workflows: 15 job types, 251 source fields and 70 proposed rules. View it through the library button in the closure screen. The original supplied text/TSV files and SHA-256 provenance are retained under `fixtures/closure-mvp/source/` and `catalogue.json`. Incomplete allowed-value sets and illustrative “Completed” defaults are preserved as source material, not silently promoted to closure policy.

## Start and sign in

```sh
npm run db:migrate
npm run demo:closure
npm run build
npm run start -w @field-assist/admin -- --hostname 0.0.0.0 --port 3002
```

The interface above permits the presentation phones to reach the API on the trusted local network. Use `127.0.0.1` instead for a simulator-only rehearsal. Stop this project's existing server before starting another on port 3002. Stop it before rebuilding its checkout. The seed is local-development-only, preserves other accounts/jobs/reports and does not reset completed demonstration assignments. Repeated seeding reuses the published policy when its hash matches. Rule changes require a new immutable policy version; superseded synthetic prototype versions are disabled for new submissions. Existing accepted records and receipts remain available.

- Engineer: **closure@fieldassist.demo / 123456**
- Supervisor: **admin@thbs.com / 123456**
- Dashboard: **http://localhost:3002**
- Earlier `fttp@fieldassist.demo` account and its rehearsal draft remain separate and intact.

```sh
cd apps/mobile
flutter run -d DEVICE_ID --dart-define-from-file=../../.local/mobile-config.json
```

On this Mac the SDK is `.local/toolchain/flutter/bin/flutter`; CocoaPods requires `RUBYOPT=-rlogger` and `~/.gem/ruby/2.6.0/bin` on PATH. The simulator's test passcode is `123456`, not the Mac password. Choose Reconnect and sign in online when switching from the earlier account. Download assignments and verify offline readiness before disconnecting.

Seven pre-accepted assignments cover S1–S4 and three distinct S5 work orders: survey, civils and network acceptance. Scenario and work stage come from the assigned job pack and are pinned by the server. A closure report must link to an assigned work order.

## Rehearse the core story

The phone now defaults to a **six-field demo summary**: work done, visit outcome, asset reference, optical reading, test result and follow-up. The voice bot fills this short form and asks only for its remaining answers. Human review and submission queue a separate visit summary. For a fully completed outcome, **Complete visit & submit → Done** opens **My jobs → Completed**, labelled **Visit completed** with its delivery state. Supervisor approval remains separate. Choose **Open full closure checks** for the detailed five-scenario walkthrough below. Full draft values, closure gates and frozen reports are preserved.

Check-in is a separate site-time action and is optional in this synthetic demo. The report shows **Check-in not recorded** when missing, or the saved arrival time when resuming. Checking in explicitly records the current timestamp and location; opening or resuming a report never invents an arrival time. An actual mandatory check-in policy needs to be agreed before operational use.

Normally submit the visit summary locally before checking out. If leaving earlier is necessary, **Check out with reason** records an explicit departure exception and retains the unfinished report. A server receipt is not needed for departure: offline local confirmation counts. Saving and submitting locally require no server connection once the offline package and valid access are available; a connection is needed for dashboard delivery. Reports distinguishes compact drafts, locally submitted summaries waiting to sync, and actual dashboard receipts. Submission opens a dedicated receipt and removes the review/form routes from the navigation stack.

1. Open **S1 · Standard FTTP provision**, start its report and choose **Fill with voice AI**. The animated conversation opens and the bot greets you first. Describe the work, tests and anything outstanding, then pause. Grounded details fill the editable draft automatically. **Fill manually** remains available. See [the voice guide](voice-demo.md) for rehearsal and offline preparation.
2. The bot speaks each applicable missing question and shows choices beneath it. Answer aloud or select an option; either route saves to the draft and advances automatically. There are no per-question Ask, Confirm or Next taps. Measurements and free text also offer optional typing. Say **repeat**, **skip**, **pause**, **resume** or **open draft**. Unknown answers remain missing and **Not measured** never becomes zero.
3. Review candidates beside their original source text in the draft. Voice-filled answers retain candidate status until the final engineer review; selecting an option records manual provenance. Facts whose branch is inactive remain candidates. The engineer can hold a visit and record an owner, escalation reference and next action. Nothing in the voice conversation submits the job or turns uncertainty into “No”.
4. For a fast presentation, use **Load labelled scenario example**. This explicitly replaces answers with synthetic values, preserves assigned context and retains photographs for review. It is separate from extracting real narrative facts.
5. Add applicable evidence. S1 needs installation and test evidence. Blockage/asset/technical exception branches request their own evidence. The camera is available on supported phones; the simulator offers conspicuously labelled illustrations. Each image is at most 120 KB, with at most four active images, encrypted storage and a checked hash.
6. Open the final review, inspect values, sources and evidence, then explicitly confirm with location. “Saved/queued” remains distinct from server acceptance. Reconnect and sync for a stable receipt. The supervisor sees the disposition, source trace, branch audit and evidence.

Do not close the presentation work orders during a preparation rehearsal unless you want them to become reviewed history. The API verification uses separate synthetic jobs and a temporary account instead.

## Show why the branches matter

- **S1 → blocked duct:** an obstruction opens the S2 follow-on questions. Do not invent ONT serials or optical readings for work that never reached those stages. Record obstruction section/distance, site handover, civils owner, reference and next action.
- **S3:** record the expected asset and what was actually observed, including not found. A suggested alternative needs explicit authorisation. An unsafe asset triggers a hold rather than installation approval.
- **S4:** toggle end-to-end fibre from connected to not connected. Optical/activation questions stop applying; their old answers are cleared from the working draft and retained in change history. Evidence that no longer applies moves to encrypted history. Reopening the branch does not silently restore old readings or count archived test images as current evidence.
- **S5 survey:** permission dependencies can remain for later construction while the assigned survey stage is handed over accurately.
- **S5 civils:** verify design, permissions, completed works, reinstatement, as-built evidence and downstream handoff. Approval closes only that civils work order.
- **S5 network readiness:** prior stages, tests, terminal mapping, as-builts and accepted handoff are required. Network ready is never displayed as customer service live.

“ONT present”, “no light” and a numeric receive level do not imply a passing optical test. Model confidence cannot create measurements, consent, safety clearance or stage acceptance. High-consequence fields require explicit literal evidence or engineer input. No approved optical pass/fail threshold has been invented.

## Source and audit behaviour

The frozen report contains the policy version, authenticated work-order association, original narrative/history, candidate question/field IDs, exact source text, source type, nullable model confidence, acceptance status, question states, branch transitions and timing counters. The engineer's final confirmation marks the applicable provided answers verified; an explicit hold can retain unresolved questions. Corrections remain authoritative subject to deterministic validation.

Draft history is bounded for this demonstration: up to eight source-text pages of 4,000 characters each, 130 current candidates, 200 recent branch transitions and eight archived images; existing per-field change history is also bounded. These are not an agreed operational retention policy. Active evidence is frozen with the payload hash. Queued reports cannot edit their sources or evidence; uncertain retries retain the same receipt.

The supervisor approves completed provision, a completed build stage or network readiness. Holds, blocked/partial visits and referrals require follow-up. Named owner, task reference and next action form an integration handoff draft; they do not prove that Openreach or a civils queue has accepted a ticket. Customer/next-team notification and acceptance answers are engineer attestations pending an approved integration adapter.

## Verification and limits

```sh
npm test
npm run typecheck
npm run test:closure
cd apps/mobile
flutter analyze --no-pub
flutter test --no-pub test/closure_policy_test.dart test/closure_journey_test.dart
flutter test integration_test/closure_native_test.dart -d DEVICE_ID --no-pub --no-uninstall --dart-define-from-file=../../.local/mobile-config.json
```

The shared fixtures cover the manager's 20 decision paths, negative closure conditions, truthful missing-only extraction and catalogue integrity. The API check verifies all five scenarios, evidence/source requirements, assigned context, human review, duplicate receipts and supervisor dispositions. It retains labelled immutable verification records and disables its temporary account afterward. The native test uses a separate encrypted test namespace, verifies schema integrity, branch clearing, evidence archiving, frozen provenance and reopen. It does not modify or submit the presentation jobs.

Elapsed draft time, extraction duration and answer edit events support a future baseline study; they are not realised productivity savings or calibrated speech accuracy. Physical-device microphone/camera quality, on-device AI accuracy across the five full journeys, full-shift offline endurance, official safety/permission controls, approved evidence retention and live MyServices/MyNetwork/ARENA integration still require validation. The wider repository has seven pre-existing Flutter interaction-test failures, reproduced on its unchanged baseline; do not count them as passing.
