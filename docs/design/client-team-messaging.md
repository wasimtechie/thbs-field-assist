# THBS client, squad and communication demo

## Connected workflow

Sales or an administrator creates a client with contact details, site/address, internal notes and a responsible squad. A squad has a department and a named lead. Administrators place engineers and employees into a primary squad from their account’s Manage form. A lead may oversee several squads; their team channels include the current members plus that lead.

From Clients → View jobs → Assign job, the client is preselected and the engineer picker is restricted to its squad. The API independently rejects a mismatched squad, paused client, inactive engineer or missing assigned published form. Sales assignments must be linked to a client and a routed squad. Leads may assign only their own squads’ engineers. A new or edited brief starts **Pending acceptance**, with a new assignment generation on edits.

The assigned engineer accepts or declines from the Flutter visit brief or limited dashboard. Declining requires a reason. Responses are distinct from execution status: Assigned → Awaiting review → Follow-up / Completed remains the existing report/supervisor workflow. The dashboard has an engineer-response filter and shows the reason. Reissuing the brief resets the response to Pending; the previous response and original brief are retained as immutable history. A report records its assignment generation and an earlier brief cannot silently be submitted against a revised assignment.

Existing pre-feature jobs were migrated as accepted so their already-downloaded drafts and queued reports can finish. The seven newly seeded client visits require a real user response; they were not pre-accepted. A client’s routing controls new assignments; existing jobs retain their assigned squad and audit history when the client or employee later moves.

## Roles and data boundaries

| Role | Operational scope | Management |
| --- | --- | --- |
| Administrator | Organisation | Accounts, roles, squads, clients, jobs, forms and report decisions |
| Operations Manager | Organisation | Clients, job assignments and report decisions; no credential/form administration |
| Team Lead | Led squads | Assign own squad engineers, read routed clients, review own squad reports |
| Sales | Organisation clients and client-linked jobs | Client intake/routing and client-linked squad assignments; no report evidence or approvals |
| Field Engineer | Own jobs, linked clients, reports and asset visits | Respond to own assignments; dashboard and mobile sign-in |
| Template Manager | Forms/types and engineer/device directory | Form/type administration; no operational evidence or assignments |
| Viewer | Organisation operational read views | No operational changes or approvals |

Every active role can look up active organisation colleagues and send messages. Direct messages require participation even for administrators. Team-channel access uses current membership or lead ownership; leaving a squad blocks new server access to its channel. Previously downloaded messages remain part of the device’s encrypted history. There is no implicit administrator access to private conversations. Cross-organisation IDs, filters and searches cannot widen access. User-provided permission lists are not accepted.

## Messaging and alerts

The dashboard now has Clients, Teams & squads, Messages, Alerts and People directory. Search uses PostgreSQL trigram matching across name, email, department, designation, role and squad, with exact/close matches ranked first. The directory shows department, squad and responsible lead so users can find the right person, then open a direct chat. Squad channels and direct chats show unread counts; message reads advance a monotonic sequence watermark. Message content is plain text, rendered as text rather than HTML.

The Flutter top bar has Messages and Alerts. Messages & team includes squad/lead shortcuts, chats, organisation search and an Outbox for queued or blocked actions. The conversation composer stays above the keyboard. New job/message alerts are durable recipient-only records. The open, unlocked app refreshes about every 12 seconds and shows a short in-app banner for a new unread alert. Dashboard chat refresh is approximately 8 seconds, alerts 10 seconds and job views 15 seconds while visible.

**Closed-app push is not configured.** The implementation does not claim APNs/FCM delivery, background execution or immediate delivery to a disconnected phone. No external email, SMS or real employee message was sent during verification; message tests used isolated synthetic accounts.

Messages and assignment responses are committed to the account’s SQLCipher database before the app presents them as queued. Stable client message/request IDs prevent duplicate records after a lost response. The queue processes assignment responses before dependent report uploads. A report stays queued while its response is unsent or blocked. Network failures preserve actions; permanent conflicts are visible in Outbox with Retry and explicit Discard. Discarding an action does not delete saved reports. A changed assignment generation remains a visible conflict, not an automatic rewrite of field evidence.

The encrypted database migrates v1/v2 to v3, preserving existing drafts and frozen reports. Each account has its own database and key. Latest 100 alerts/conversations and up to 100 messages per downloaded thread are cached; earlier message pages can be loaded online. New conversations/organisation search need connectivity, while existing downloaded threads and pending actions remain available offline. Browser sends retain unsent text for retry on the current page and use stable IDs; browser-local offline persistence is not claimed.

## Demo accounts

All requested accounts retain password **123456**. The seven field accounts can now also use the limited dashboard. Additional synthetic dashboard accounts:

| Login | Role | Responsible squads |
| --- | --- | --- |
| lead1@thbs.com | Team Lead | Fibre Delivery; Site Planning |
| lead2@thbs.com | Team Lead | Fault Response; Business Connections |
| sales@thbs.com | Sales | Client intake and delivery tracking |

admin@thbs.com remains Administrator, waseem@thbs.com Operations Manager and test@thbs.com Viewer. Fibre1/fibre2 are in Fibre Delivery; repair1/repair2 in Fault Response; business1/business2 in Business Connections; site-survey in Site Planning. Emails are case insensitive. Four explicitly synthetic clients and seven pending visits are supplied.

Run `npx tsx scripts/provision-collaboration-demo.ts` after ordinary setup/seed to create missing demo staff, squads, clients and visits. Existing credentials/details are preserved. Existing team membership is not reset by rerunning it. It refuses production mode. Account creation/changes also remain available through the administrator UI.

## Five-minute rehearsal

1. Sign in as sales@thbs.com. Open Clients and inspect the routed client/squad. Add a clearly synthetic client or open an existing client’s View jobs → Assign job. Verify only that squad’s engineers are selectable.
2. Open the updated Flutter app as fibre1@thbs.com. Connect and provision. Inspect Alerts and the new visit in My jobs, including client, squad, due date and instructions.
3. Accept the visit, or decline it with an access reason. A queued label means saved on the phone; it is not a server acknowledgement. On connectivity, the lead/Sales dashboard reflects the response and alert. An administrator does not respond on behalf of an engineer.
4. Open Messages & team → Message lead. Send a clearly labelled demo question. Sign in as lead1@thbs.com in the dashboard, open Messages and reply. Refresh/open the app thread to show the reply and unread/alert changes.
5. Complete the existing cable scan/manual or voice report flow. Confirm with location and show the stable report receipt. The lead reviews the squad report and records approval/follow-up. Original response history and report evidence remain.
6. Use a different engineer login in the dashboard to show its different restricted data. Use People directory to find another department with an approximate spelling; opening a direct chat does not give access to their operational records.

## Installing and connecting the phone

`Field-Assist-Android-Test.apk` is updated to ARM64 Android 12+ build **2009**, signed with the same debug certificate so it can update the previous demo installation. Sign-in → Connection settings accepts the supplied server URL. HTTPS is the default; this explicitly enabled local demo build also accepts private local HTTP addresses. An existing signed-in account must sign out before changing the server, and its old session token is never forwarded to the new address. Existing encrypted reports remain.

For a laptop demo without USB, both phone and laptop need a shared reachable Wi-Fi/LAN. Enter `http://<laptop-private-address>:3000` in Connection settings; the app normalizes the API path. The server must be running and reachable, and must use the public signing key pinned in the app. A phone on an unrelated network cannot reach laptop loopback/LAN merely because internet is on. No hosted backend or public tunnel is configured.

## Verification

- **104 Flutter tests**, including queued-response generation recovery, mandatory decline reason, light/dark chat layout, safe connection-address handling, account changes during asynchronous uploads/saves, and the queued-to-sent message acknowledgement transition. Flutter analysis: no issues.
- **77 shared contract tests** including role boundaries, message IDs, decline validation and team/client schemas.
- **97 real local collaboration HTTP/PostgreSQL checks** across isolated synthetic organisations: routing/mismatch rejection, owner/lead/Sales scoping, fuzzy search, notifications, response retry/generation conflicts, stale report brief rejection, report review, message privacy/retry/read watermarks, cross-organisation isolation and membership changes.
- **93 account lifecycle regression checks**, including all requested credentials/types, pause/removal/restoration, credential reset/revocation, optimistic revisions, uniqueness, self-protection and concurrent last-administrator protection.
- A native iPhone simulator test demonstrated SQLCipher v2→v3 migration, old draft preservation, encrypted queue recovery after database reopen, simulated unreachable transport, real HTTP lost-message-response deduplication, assignment-before-report ordering, a lead reply, unchanged frozen bytes and account isolation. This is not an OS airplane-mode or physical-device restart/permission test.
- TypeScript, dashboard production build, normal iOS simulator build and Android build pass. APK verification covers build 2009, original debug certificate, ARM64, supplied video hashes, absence of private native test credentials and 16 KiB ZIP/ELF alignment. Physical Android installation, speech/microphone, hardware camera/GPS, thermal/battery, OS interruptions and real 16 KiB-device acceptance remain device checks.

Evidence is in `docs/evidence/collaboration-*`; the native JSON result, API check manifest and APK package manifest state their exact limits. The normal simulator app was restored from lib/main.dart with the public configuration after testing. Private native configuration is ignored and never included in the distributable APK.

Named boards, the expanded profile catalogue and site tracking are documented in [Boards, profiles and time](boards-profiles-time.md). Use the latest build noted there; the earlier build reference above records the collaboration milestone.
