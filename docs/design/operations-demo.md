# THBS Field Assist: assignment to supervisor review

## Competitor findings and scope

Reviewed official product pages on 15 October 2026. MaintainX describes assigned/prioritized work orders, execution records and approval workflows in [work order management](https://www.getmaintainx.com/use-cases/work-order-management), and maintenance logs and asset context in [asset management](https://www.getmaintainx.com/use-cases/equipment-and-asset-management). Its [AI features](https://www.getmaintainx.com/use-cases/ai-powered-maintenance-operations) already include voice-note summaries and natural-language reporting. Voice alone is not an exclusive claim we should make.

UpKeep also provides [work-order assignment and tracking](https://upkeep.com/product/work-order-management/) and [offline checklists with cached assignments](https://help.onupkeep.com/en/articles/4712557-how-to-use-upkeep-offline). Limble's [product suite](https://limble.com/products) includes work orders, analytics, preventive maintenance, inventory and a technician app; its [asset-management page](https://limble.com/products/asset-maintenance-management) emphasizes visit history and asset context.

Our largest gap was the surrounding operating workflow. The previous demo captured and delivered reports but had no assigned job, due date, human approval or revisit loop. This increment adds that journey while retaining the established Flutter/Next.js architecture and colors.

| Demo capability | Dashboard | Flutter app |
| --- | --- | --- |
| Work assignment | Engineer, priority, due date, site, reference, instructions; status board, search and overdue filter | Downloaded My jobs, priority ordering, visit brief, draft resume |
| Human review | Inbox, original report inspection, required follow-up note, explicit approval | Feedback and review state after refresh; separate follow-up report |
| Operational visibility | Real open/overdue/completed counts, pending reviews, team workload, seven UTC days of received reports | Explicit queue/draft status and last-downloaded timestamp |
| Asset context | Exact-reference visit timeline, original reports and review decisions | Other downloaded visits assigned to this engineer for the same reference |

The presentation should show a telecom field visit: a downloaded brief, on-device guided voice, cable-label OCR, validated structured answers, captured report location, durable offline queue, then a supervisor decision and traceable follow-up. These are implemented behaviors, not a claim of exclusive features or full competitor parity. Inventory/procurement, automatic preventive recurrence, QR lookup, customer signatures, photo attachments, production integrations and push notifications remain future scope.

## Rehearsal

1. Open **Work orders** at `/work-orders`. The seed adds two clearly synthetic assignments for each active demo engineer without replacing existing work. An additional **Demo · THBS showcase rehearsal** assignment is available to the existing Waseem Demo account.
2. Create or edit an open assignment. Set engineer, priority, local due date/time, site and an asset/cable reference such as `CBL-2026-0042`. Reuse the exact reference for later visits. Reassigning a downloaded job can conflict with an offline draft; the draft is preserved and flagged at delivery.
3. Install Android build **2008**, or use the restored normal iPhone simulator app. Sign in/provision online, then choose **My jobs → Refresh assignments**. The displayed download timestamp is the snapshot time. Supervisor updates and new assignments require refresh; there is no push/background-location service.
4. Open the visit brief and choose **Start job report**. Repeat entry resumes the same local draft. Use manual fields, guided voice or **Scan cable label**, review and confirm with a fresh location. Downloaded jobs/forms and encrypted drafts work offline while the existing lease is valid.
5. A confirmed report is queued locally. With the backend reachable and the app open/unlocked, it retries using identical frozen bytes. The work-order identity is part of those hashed bytes. A server receipt moves the job to **Awaiting review**, never automatically to completed.
6. Open **Review inbox → Inspect report**. Check the original values/location. **Request follow-up** requires a useful note and a confirmation step. **Approve work** records explicit supervisor approval and completes the linked job inside this demo. A standalone report review does not create an assignment.
7. Refresh My jobs. A returned job shows the supervisor's note and **Start follow-up report**. This creates a separate report; the original answers, location and receipt stay intact. Once the follow-up arrives and is approved, the job moves to Completed.
8. Open **Asset history**, select the same exact reference and show the earlier/follow-up reports and their decisions. References are supplied by the administrator, not verified against a manufacturer registry. History is not a computed asset-health score.
9. Show the overview's **Operations pulse**. It reads real records, including synthetic test records; totals are not hardcoded. Open jobs means assigned or follow-up; overdue excludes work already awaiting review. Workload also includes submitted jobs. Completion percentage is completed/total assigned jobs, not an SLA or first-time-fix claim.

## Persistence and access

New nullable `Report.workOrderId` preserves legacy payload compatibility. `WorkOrder` tracks the operational lifecycle; `ReportReview` records an immutable human decision. Original accepted report values and receipts are never rewritten. Serializable acceptance and review transactions prevent concurrent conflicting updates. Identical upload and review retries return the original result. A different decision for an already reviewed report is rejected; correction proceeds through a new follow-up report.

The app's SQLCipher database migrates v1 to v2 in place, adds a nullable work-order link and a partial unique index allowing only one unaccepted report per job/account. Downloaded jobs and latest 40 feedback decisions live in encrypted metadata. All active assigned jobs and up to 200 recent history rows are cached. Existing standalone drafts/queues retain their payloads. An engineer downloads only their own assignments and reviews; administrators operate only within their organization.

Dashboard job/review lists paginate at 50; asset lookup shows up to 100 recently active exact references and 100 visits for a selected reference. Search/filtering happens on the server. Dashboard polling is 15 seconds; app refresh is explicit or follows successful provisioning/delivery. Offline changes are not represented as live server activity.

Initial login/provisioning and first assignment download still need a reachable backend. This manual APK uses the existing laptop-loopback endpoint. An independently connected phone needs forwarding or a rebuild against a reachable trusted endpoint. No tunnel, public deployment or external customer integration was created.

## Verification

- 62 shared tests; 91 Flutter tests; final Flutter analysis has no issues; TypeScript and production dashboard build pass.
- 32 real local workflow checks plus four read-only filter regression checks cover role/assignment isolation, revision checks, conditional form validation, frozen retry stability, human follow-up/approval, preserved originals, asset history and database-enforced immutable review decisions.
- Native iPhone simulator integration creates an isolated encrypted v1 store, upgrades it, verifies the original draft, caches a brief and feedback, blocks a duplicate active job, confirms/freezes a synthetic report and recovers its unchanged payload/hash after an interrupted upload. No presence, physical GPS or airplane-mode claim is made.
- Browser checks cover an actual synthetic assignment through the UI, filtered board, asset timeline with both report links, mandatory follow-up notes and confirmation/cancellation, plus desktop and narrow layouts.
- Android build 2008: original debug signature, ARM64 packaging, bundled OCR and supplied videos, 16 KiB ZIP and ELF alignment verified. The regular simulator app was restored after testing. Physical device performance, permissions, camera/GPS and OS airplane-mode acceptance remain pending.

Evidence: `docs/evidence/operations-*`, with test data explicitly marked synthetic. APK metadata/checksum: `docs/evidence/android-manual-apk.json` and the root `.apk.sha256` file.

To repeat API verification, run `npx tsx scripts/check-operations.ts` against the local server. It creates synthetic jobs/reports/decisions and revokes only its test sessions. To repeat native migration verification, prepare `node scripts/cable-label-test-config.mjs`, then run `flutter test integration_test/operations_native_test.dart -d <device-id> --dart-define-from-file=../../.local/cable-native-test-config.json` from `apps/mobile`. Restore `lib/main.dart` with the public `mobile-config.json` afterwards.
