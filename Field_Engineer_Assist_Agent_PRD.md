# Field Engineer Assist AI Development PRD

Version 3.0 | 15 October 2026 | Flutter iOS and Android implementation specification for an AI coding agent

## 1 Assignment for the receiving coding agent

Implement a working Flutter engineer application for iOS and Android and an admin web dashboard with a shared backend. This document is the build specification. Deliver runnable source, migrations, seed data, tests, local setup instructions, and an evidence-based completion report. Do not stop after a plan, wireframes, screenshots, static pages, or mocked API responses.

The product demonstrates this complete journey: an administrator configures an engineer-specific form; an authorized engineer downloads it; the engineer opens it without internet, fills it by voice or touch, corrects and reviews the answers, confirms a durable local submission, and synchronizes it to the admin dashboard after connectivity returns.

Use Whistle for offline speech recognition, Needle 3 as the single field-extraction model, and Kokoro for offline speech synthesis. Application code owns form rendering, state, validation, question selection, authorization, and submission. No cloud AI dependency is permitted for the core journey.

Read the existing repository and its AGENTS.md files before changing code. Reuse a sound existing architecture where possible. For a new repository, use the defaults below. If adapting an existing repository requires a material stack change, document the reason; do not silently replace the requested offline pipeline. Continue independent work when credentials or hardware block only part of the project. Never report unexecuted device checks as passed.

### Product defaults

- Working name: Field Assist. Use neutral branding until approved brand assets are supplied.
- Mobile framework: Flutter with Dart for the shared application UI and business logic. Deliver iOS and Android builds; do not replace the main app with SwiftUI, React Native, a PWA, or a WebView. Thin Swift/Objective-C++ and Kotlin/JNI bridges are allowed for native capabilities.
- Proposed reference baselines: iPhone 13 running iOS 18 or later, and an ARM64 Android phone running Android 12 or later with at least 6 GB RAM. These are proposed test targets, not verified model requirements. Record exact physical devices/OS versions and verify plugin/runtime minimums on each platform before finalizing deployment targets.
- Admin: desktop web at 1280 pixels wide or larger, with usable narrower layouts.
- Language: English. No wake word, background listening, open-ended chatbot, or technical repair advice.
- Four engineer types and one assigned default template per type. Two templates receive the main live voice demonstration; the engine supports all four through the same code.
- Initial sign-in and provisioning require connectivity. Subsequent offline access unlocks the previously provisioned account.
- One active engineer account per mobile installation for P0. Demonstrate another type on a second device or reprovision online between runs. Do not add a fake role-switch button. Offline switching among several accounts is a later feature requiring separate provisioning and data isolation.
- Admin operations are online. The receiving service uses synthetic demo data, not BT production systems.
- Offline access lease: 72 hours from the latest successful authorized server check. This is a configurable demo policy.
- P0 means required for completion. P1 is optional after P0. A future item must not delay the P0 demo.

## 2 Scope and nonnegotiable behavior

### P0 deliverables

1. Professional engineer sign-in, provisioning, and secure offline unlock.
2. Engineer home, assigned form, resumable drafts, manual editing, voice sheet, review, local receipt, and sync queue.
3. Admin sign-in, template library, template editor, preview, publication, engineer/type assignments, submissions list/detail, and last-reported device status.
4. Four seeded editable templates. Admin can add, edit, reorder, duplicate, and remove fields without changing app code.
5. Immutable published versions and stable field IDs. Existing drafts and historical reports remain intact after template edits.
6. Real Whistle plus Needle 3 plus Kokoro inference on physical iOS and Android devices in airplane mode, using the same Dart application logic.
7. Encrypted local persistence, restart recovery, safe retries, idempotent server acceptance, and explicit error recovery.
8. Premium interaction design, a bundled lightweight 3D object, spring tap feedback, continuous navigation, truthful voice animations, and reduced motion.
9. Tests, repeatable seed/reset operations, setup documentation, and acceptance evidence.

### P1 enhancements

Barcode scanning for serial numbers, local photos with retryable upload, template duplication, and measured manual-versus-voice completion time. If attachments are implemented, give them independent upload states and do not mark a report accepted until its required attachments are complete.

### Excluded from P0

BT/Openreach production adapters, production SSO or MDM, mobile web/desktop targets, arbitrary scripts in templates, deeply nested rules, repeatable sections, safety certification, autonomous job closure, always-on listening, full-duplex speech, multilingual rollout, payments, and a generic chat assistant.

## 3 Technology and repository contract

For a new project use:

| Area | Decision |
| --- | --- |
| Mobile UI | Flutter stable and Dart; shared feature modules, adaptive controls, Material 3 styling with platform-appropriate navigation |
| State and routing | Riverpod for state/dependencies; go_router for navigation and guarded routes |
| Mobile networking and DTOs | Dio; immutable Dart models with Freezed/json_serializable or equivalent generated typed DTOs |
| Mobile audio | A maintained Flutter PCM recording/playback integration behind AudioCoordinator; native audio-session/focus hooks for iOS and Android |
| Local persistence | SQLCipher through a verified iOS/Android Flutter integration such as sqflite_sqlcipher; Dart repositories, transactions and explicit migrations |
| Mobile secrets | flutter_secure_storage for OS-protected secrets and local_auth for local unlock; Keychain on iOS and supported Keystore-backed secure storage on Android; no plaintext password |
| Speech recognition and extraction | Whistle and Needle 3 through a verified Flutter binding or a local dart:ffi/native plugin wrapper around their supported C/C++ runtime on both platforms |
| Speech synthesis | Kokoro ONNX through the verified sherpa_onnx Flutter integration as the first integration candidate; all voice, tokenizer and phonemizer assets local; validate on both platforms before adoption |
| Admin and API | Next.js App Router, TypeScript, Node runtime Route Handlers |
| Admin UI | Tailwind CSS, accessible Radix or shadcn components, Motion for React for purposeful transitions |
| Server validation | Zod; explicit shared schema definitions and fixtures |
| Server database | PostgreSQL with Prisma migrations |
| Tests | Vitest for backend/domain logic; Playwright for admin; flutter_test for Dart/unit/widget tests; integration_test on physical iOS and Android devices; native bridge tests as needed |
| Development services | Docker Compose for PostgreSQL; Next.js locally or containerized; physical-device HTTPS API URL |

Resolve compatible maintained dependency versions at implementation time and pin them in lockfiles. Record native model/runtime versions, model hashes, and licences in `docs/runtime-manifest.md`. Do not invent an SDK class, initializer, or function from a blog example: inspect the actual dependency source/header first.

Expected structure; these are requested future repository paths, not files already implemented:

```text
apps/admin/                 Next.js dashboard and /api/v1 routes
apps/mobile/                Flutter engineer app with lib/, ios/, android/, test/ and integration_test/
packages/field_voice/        Local Flutter/FFI voice adapters and native bindings when required
packages/contracts/         Schema types, validators, error codes and fixtures
packages/database/          Prisma schema, migrations and seed operations
fixtures/templates/         Four seed schemas and later-version examples
fixtures/voice/             Text fixtures and consented synthetic/test audio
scripts/                    Setup, model provisioning and demo-reset commands
docs/                       Setup, API, runtime manifest, progress and demo script
```

Flutter feature modules under apps/mobile/lib/features/: authentication, offline_access, templates, forms, voice, sync, settings and home. Put design_system, networking and persistence in lib/core/ and generated DTOs/contracts in a dedicated shared Dart module. Keep UI independent of native model wrappers through interfaces such as SpeechRecognizer, FieldExtractor, SpeechSynthesizer, and ReportRepository. Interfaces are application-owned abstractions, not claims about vendor SDK APIs.

The backend must keep domain services separate from Route Handlers. Admin web and mobile use the same template and submission rules. Do not add a separate microservice, vector database, cloud queue, or second language model for this scope.

### Flutter architecture and native integration requirements

Keep forms, validation, review, queue state, networking and question selection in shared Dart code. Use Riverpod providers/notifiers for explicit state ownership and dependency injection; go_router guards must handle online authentication, offline unlock and provisioning separately. Native code handles only capabilities that require it. Flutter builds the engineer UI; the admin stays Next.js/React.

- Use a local `field_voice` package exposing typed asynchronous application interfaces. Start by checking whether the current Cactus Flutter package actually exposes the selected Needle 3 and Whistle runtime APIs. A generic Cactus LLM integration is not proof that these two models are supported. If not, wrap the verified C API with dart:ffi and thin platform glue. Prefer Flutter's current supported FFI build/package workflow for the pinned SDK; inspect official guidance rather than assuming a legacy template.
- Define model load/unload, transcribe, extract, synthesize and cancel methods plus progress/state events. These are application interfaces, not assumed vendor method names. Preserve error codes, model handles and memory ownership; free native buffers and dispose resources on teardown. Keep model contexts on a single owning worker and serialize calls where the runtime is not thread-safe. If the runtime cannot interrupt an in-flight call, cancellation invalidates its request ID and discards late results before the next operation.
- Load microphone audio using a maintained Flutter recording plugin, verify sample format/rate, and convert to the exact local ASR format. Handle iOS audio sessions and Android audio focus, permissions, interruptions and Bluetooth/headset routing. Playback must not be recaptured by the microphone. Do not use an OS speech-recognition plugin as a substitute for Whistle or an OS TTS plugin as a substitute for Kokoro.
- For Kokoro, verify the chosen sherpa_onnx package version, supported model export, voices and phonemizer assets together. Confirm both iOS and Android synthesis from local files before committing to the wrapper. If a different Kokoro native wrapper is needed, keep the same Dart interface and document the reason; do not silently replace the Kokoro model.
- Package arm64 device runtimes for iOS and Android arm64-v8a. Simulator/emulator binaries are separate optional development slices; lack of a model simulator slice is not evidence of device support. Pin compatible Xcode/iOS deployment targets, Android minSdk/compileSdk/targetSdk, JDK/NDK and native library settings in the repository. Verify modern Android native-library packaging and page-size compatibility for every shipped .so. Document platform support individually.
- Give each platform its own manifest entry for native binaries and any platform-specific model export. Model/voice assets may share IDs where identical; do not assume one mobile binary runs on both OSes. Copy bundled/downloaded assets into usable local paths before handing them to native code. No lazy network download during an offline turn.
- Use SQLCipher transaction APIs through a verified Flutter plugin. Confirm encryption, reopen/recovery, migrations and account isolation on both OSes. Store the per-account database key in OS-protected secure storage, never SharedPreferences. Configure backup/restore exclusions so an encrypted database is not restored without its usable key; key loss must produce an explicit recovery state rather than a new empty database presented as success.
- `local_auth` confirms device-user presence but is not itself an encryption-key policy. Require successful authentication before database access; where cryptographic key-use gating is required, verify native Keychain/Keystore access-control support or implement the necessary thin bridge. Document the demo's device-threat assumptions and test biometric unavailable/enrollment-changed states.
- Request microphone permission and provide platform privacy descriptions. Camera is requested only if P1 scanning/photo capture is implemented. Keep P0 audio foreground-only; do not add background recording/services or broad storage permissions. Stop native work safely on app pause/detach and reconcile durable state on resume.
- Use Dart immutable DTOs and typed validation results; do not pass untyped JSON maps through widgets. Reuse shared JSON fixtures between Dart and TypeScript for schema semantics, dates, numbers, false/zero/missing values, conditions and hashes. Persisted business state belongs in repositories, not widget controllers or model conversation memory.

Suggested Flutter dependencies to inspect and pin: flutter_riverpod, go_router, dio, freezed_annotation/json_annotation with generators, sqflite_sqlcipher, flutter_secure_storage, local_auth, a verified PCM recording/playback package, and sherpa_onnx. Add only dependencies actually needed. Use Flutter AnimationController, SpringSimulation, AnimatedSwitcher, Hero and custom transitions for mobile motion; GSAP and Motion for React belong only to the web dashboard if used.

Suggested Flutter layout:

```text
apps/mobile/lib/app/                   Router, app theme and provider setup
apps/mobile/lib/core/                  Networking, persistence and design system
apps/mobile/lib/features/forms/        Schema renderer, controllers and review
apps/mobile/lib/features/voice/        VoiceCoordinator and state UI
apps/mobile/lib/features/sync/         Durable outbox and reconciliation
apps/mobile/lib/features/authentication/ Online sign-in and offline unlock
apps/mobile/test/                      Dart/unit/widget and contract fixture tests
apps/mobile/integration_test/          Real-device end-to-end scenarios
packages/field_voice/lib/              Dart interfaces and generated FFI bindings
packages/field_voice/                  Native source/build hooks/platform glue
```

## 4 Identity and authorization contract

Use two access roles: `ADMIN` and `ENGINEER`. `engineerTypeId` is an assignment, not an access role. Engineers cannot choose a privileged type from the login form. Server responses establish the allowed type and default template.

For this self-contained demo use seeded email/password accounts and a server session service. Hash passwords using a maintained Argon2id implementation. Use cryptographically random opaque session tokens, store only token hashes server-side, and check role/ownership in every service operation. Use vetted libraries; do not implement cryptographic primitives.

- Browser sessions: HttpOnly, SameSite cookies; Secure in HTTPS environments; origin/CSRF protection on mutations. No bearer credentials in browser localStorage.
- Mobile sessions: opaque bearer token stored through OS-protected Flutter secure storage. Proposed online session lifetime: seven days; reauthentication after expiry. Offline authorization is a distinct, shorter lease.
- Login: generic invalid-credential error, input validation, progress state, disabled duplicate submission, rate limiting, and sanitized logs.
- No public sign-up, OTP, or password-reset service in P0. Provide a working Contact administrator message if an access-help link is shown; no dead UI controls.
- Seed exactly one admin and four engineers using credentials supplied through environment variables or generated locally and printed only to the setup operator. Never commit real passwords.
- Disabling a user revokes online sessions and prevents new leases and uploads. A disconnected device remains limited by its previously issued lease.

### Offline entitlement

Issue a signed token containing `userId`, `organizationId`, `deviceId`, `engineerTypeId`, allowed template IDs, assignment revision, `issuedAt`, `expiresAt`, and signing-key ID. Verify with a pinned public key using a maintained Dart JOSE/cryptography implementation or vetted native bridge; explicitly allowlist the selected signature algorithm, reject unsigned tokens, and test the same signed fixtures against the server. Keep the signing private key only on the server. An offline entitlement is not valid as a submission API access token.

Only the server renews the lease. Save the last trusted server time and detect obvious local-clock rollback; conservatively require online reauthentication if expiry cannot be trusted. Do not claim resistance to a compromised device. Local OS biometric/device-passcode authentication unlocks the account database; it does not authorize a new account or a new engineer type.

On expiry, keep encrypted data but require reconnect before opening protected work or creating reports. On backgrounding, stop audio and lock the UI after a short configurable timeout. Lock preserves the lease; Sign out revokes local offline access, locks data, and preserves unsent records for the same account. Never silently delete pending work or expose it to a later user. Use one encrypted database/key namespace per account.

## 5 Screens and interaction contract

### Engineer application

| Screen | Required behavior |
| --- | --- |
| Sign in | Branded identity, lightweight 3D object, email/password, visibility toggle, validation, loading, access help and retry |
| Provisioning | Download/check progress per package component; resume interrupted transfers; no false readiness |
| Offline unlock | Cached engineer identity, secure local unlock, lease expiry/reconnect explanation |
| Home | Name/type, assigned default form, Start report, Continue draft, queue count, offline status, last sync |
| Form | Sections, valid-completion count, units, required state, manual fields, persistent Fill by voice button, autosave result |
| Voice sheet | Accurate voice state, live level visualization when recording, transcript, changed fields, question, stop/pause controls |
| Review | All included values, missing/invalid fields, provenance, edit links, confirmation checkbox/button |
| Local receipt | Saved on this device and waiting to sync, local reference, queue access |
| Queue/detail | Draft/Queued/Syncing/Accepted/Needs attention, retry or resolution action, server receipt when available |
| Settings | Playback on/off, speech rate, reduced motion, asset status, account, lock and sign out |

Home opens the assigned form without a type selector or template search. Show an actionable empty state when no type/form is assigned. Every voice-fillable field remains manually editable. The keyboard must not obscure Save, Review, or voice controls. A form reopens at the last useful section and preserves scroll position when returning from Review.

### Admin routes

- `/login`: professional login; session-aware redirect.
- `/dashboard`: actual accepted report count, template publication state, recent errors and last device contact. No invented analytics.
- `/templates`: searchable defaults with type, status, version, last editor, Edit/Preview/Archive.
- `/templates/[id]/edit`: palette, ordered canvas, selected-field properties, validation, save draft, preview and publish.
- `/engineers`: provision/disable engineer, type assignment, default form, last contact and reported package version.
- `/engineer-types`: create/edit/archive types and select a published default template. Block archiving a type with active assignments until reassigned.
- `/submissions`: filter by type, engineer and dates; view immutable received report and receipt.
- `/devices`: last reported readiness/version and contact time. Do not assert current offline queue counts.

All screens require loading, empty, validation-error, transport-error and success states where relevant. Admin editing requires internet. A toast is supplemental feedback, not the only place an error is shown.

## 6 Template schema version 1

Implement a schema-driven engine. Do not hardcode separate UI or extraction branches for each engineer type. The same published schema drives mobile rendering, validation, missing-field questions, extraction instructions, and review summaries.

Supported field types: `short_text`, `long_text`, `integer`, `decimal`, `quantity`, `boolean`, `single_select`, `date`. P0 maximums: 30 fields, six sections, 20 select options, one-level visibility conditions. Reject unsupported structures rather than rendering them incorrectly.

Example response shape; use real IDs and a calculated hash in the implementation:

```json
{
  "schemaFormatVersion": 1,
  "templateId": "tpl_fault_repair",
  "versionId": "version_uuid",
  "versionNumber": 1,
  "engineerTypeId": "fault_repair",
  "title": "Fault repair report",
  "schemaHash": "sha256_of_canonical_schema",
  "sections": [
    {"id": "work", "label": "Work and testing", "order": 0}
  ],
  "fields": [
    {
      "id": "cable_length",
      "sectionId": "work",
      "order": 0,
      "type": "quantity",
      "label": "Cable replaced",
      "required": false,
      "constraints": {"min": 0, "max": 1000, "precision": 1},
      "units": {"allowed": ["m"], "canonical": "m"},
      "voice": {
        "enabled": true,
        "description": "Actual cable length replaced in metres",
        "question": "How many metres of cable did you replace?",
        "synonyms": ["drop wire length", "cable replaced"]
      }
    },
    {
      "id": "line_test",
      "sectionId": "work",
      "order": 1,
      "type": "single_select",
      "label": "Line test result",
      "required": true,
      "options": [
        {"id": "passed", "label": "Passed"},
        {"id": "failed", "label": "Failed"},
        {"id": "not_tested", "label": "Not tested"}
      ],
      "voice": {
        "enabled": true,
        "description": "Explicit engineer report of line test status",
        "question": "What was the line test result?",
        "synonyms": []
      }
    }
  ]
}
```

### Values and validation

- Values map stable field IDs to typed values. Text/date/select are strings; numbers are JSON numbers; Boolean is true/false; quantity is `{ "amount": 12, "unit": "m" }`.
- Missing values are omitted. `null` is only an explicit draft clear marker and is normalized to missing for submission. Empty text is missing after trimming. `false` and numeric zero are real values.
- Dates use `YYYY-MM-DD`; timestamps use UTC ISO 8601 plus an explicit originating timezone where needed. Relative dates use a trustworthy local date/time context and remain visible for review.
- Select values use stable option IDs. Reject labels or values outside allowed IDs at the API boundary.
- Apply min/max, precision, allowed unit, string length, date range and required rules identically in Dart and TypeScript. Quantity conversions use an explicit code allowlist, not model arithmetic.
- Conditions use `{ "fieldId": "follow_up", "operator": "equals", "value": true }` or the same shape with `operator: "in"` and a nonempty array of allowed enum IDs. One controlling field, no nesting. Reject unknown references, self-reference and cycles. Required applies only while visible.
- If a condition hides a populated field, omit it from the submission/review payload and keep the value only in draft history for undo. Explain the exclusion in Review.
- Job reference, user ID, type, template/version/hash, creation time and receipt are system metadata. Admin cannot remove or voice-edit them.

### Publishing

Use a mutable TemplateDraft with an integer revision and immutable TemplateVersion records. `If-Match` or equivalent expected revision is mandatory for saves and publish. Reject stale writes with 409. Publishing validates the schema, compiles the supported extraction/question configuration, creates a version/hash atomically, and records an audit event.

Define the schema hash as SHA-256 over UTF-8 RFC 8785 canonical JSON of exactly `schemaFormatVersion`, `templateId`, `engineerTypeId`, `title`, `sections` and `fields`. Exclude `schemaHash`, version IDs/numbers, timestamps and transport/audit metadata. Preserve ordered arrays. Use a verified canonicalization implementation and shared expected-byte/hash fixtures in Dart and TypeScript; do not hash arbitrary serializer output. The manifest identifies the immutable version separately from its content hash.

Field IDs never depend on labels or positions and are never reused for another meaning. Deleting a field removes it only from a later version. Renaming an option retains its option ID. Existing drafts pin `templateId`, `versionId`, and `schemaHash`; new reports use the latest completely installed assigned version. No automatic draft migration.

Archive templates/versions referenced by work rather than deleting records. Ordinary old versions remain accepted for previously authorized drafts. Explicitly disabled versions return a structured rejection and preserve local data for repair. Rollback means republishing a previous schema as a new version.

## 7 Seed templates and users

Seed deterministic IDs and one synthetic engineer per type. Running seed twice must not duplicate users/templates or destroy work. A separate development reset command requires an explicit flag and refuses production environments.

### Fibre installation

| Field ID | Type | Rules |
| --- | --- | --- |
| installation_outcome | single_select | Required; completed, partial, unable |
| work_performed | long_text | Required; max 500 characters |
| cable_installed | quantity | Required; metres; 0 to 1000 |
| ont_serial | short_text | Required if completed; voice disabled; manual or P1 scan |
| optical_reading | decimal | Required if completed; dBm; example range -60 to 10 |
| connectivity_test | single_select | Required; passed, failed, not_tested |
| exception_reason | long_text | Required if outcome is partial or unable, using separate supported conditions or an explicit allowlisted membership operator shared by both validators |

For the last field use the supported `in` condition on partial/unable. Test both supported operators in both validators. Do not introduce arbitrary expressions.

### Fault repair

Fault location select (premises, drop_wire, dp, cabinet, other); required fault description and action taken; optional cable-replaced quantity in metres; required line-test result select (passed, failed, not_tested); required service-restored Boolean; required follow-up Boolean; follow-up details required if true. Limits: 500 characters for long text, 0 to 1000 metres.

### Business circuit installation

Required installation outcome select (completed, partial, blocked); equipment serial and port reference required when completed, with voice disabled for identifiers; bandwidth quantity required when completed, units Mbps/Gbps with code-based conversion; required service-test result select; required customer-handover Boolean; optional notes; blocker details required when blocked.

### Site survey

Required access-available Boolean; required outcome select (feasible, further_survey, unable_to_assess); optional estimated route length in metres; optional equipment notes; required power-available Boolean; optional constraints; required follow-up Boolean; details required if true. Unknown power remains missing, not false.

Give every voice-enabled field a meaningful question and extraction description. None of the templates defaults a test to passed or an action to completed. Demo numerical ranges are examples, not engineering certification thresholds.

## 8 Voice engine and proposed field patches

Implement and verify the Flutter/native adapters first, then orchestrate them through a Dart VoiceCoordinator with Riverpod-managed lifecycle. Long-running native inference must run in a dedicated worker isolate or native worker queue, not synchronously on the Flutter UI isolate. An async Dart method alone does not guarantee that native work is off the UI thread. Pin one Needle 3 configuration; do not ship multiple LLMs or select a depth dynamically until evidence supports it.

States: `idle`, `listening`, `transcribing`, `extracting`, `needs_clarification`, `speaking`, `paused`, `ready_to_review`, `error`. Every state has a readable label. Mic and playback must not be active simultaneously in P0. A visible Stop speaking button interrupts Kokoro. Backgrounding, calls, or audio-route loss stop capture and retain saved fields.

Start with explicit tap-to-start/tap-to-stop, a 20-second maximum turn, and an optional silence endpoint. Reaching the limit preserves the captured turn and offers another turn. Show the transcript in memory for correction but never treat it as authorization to execute arbitrary tools.

Needle receives the active supported field schema, known values, the current question, the latest transcript, and bounded recent context. It proposes a constrained patch; the exact vendor call syntax is adapter-specific and must be verified. The following is the application-level contract:

```json
{
  "updates": [
    {
      "fieldId": "cable_length",
      "operation": "set",
      "value": {"amount": 12, "unit": "m"},
      "evidence": "twenty metres actually twelve"
    }
  ],
  "unresolved": [
    {"fieldId": "line_test", "reason": "ambiguous"}
  ]
}
```

Allowed operations: `set` and `clear`. A clear update carries no value. Allowed unresolved reasons: `ambiguous`, `unsupported_unit`, `conflict`. Missing required fields are computed by application rules rather than requiring the model to enumerate them. Keep structural output constraints supported by the runtime and validate a typed discriminated union after inference. Reject unknown IDs, unsupported operations, malformed types and out-of-range values.

If the runtime cannot directly enforce this exact output shape, adapt its verified extraction format into the application contract and document the mapping. Do not invent SDK support. Show that a newly published field is handled without model retraining or recompilation.

### Merge and clarification rules

1. Unmentioned fields retain their values. A missing extraction is never a clear instruction.
2. An explicit correction replaces an unambiguous previous value and provides Undo. Ambiguous conflicts keep the prior value and request clarification.
3. Preserve negation. Not tested is not passed; not replaced is not replaced=true.
4. Manual values are not overwritten by an ambiguous voice statement. Explicit, unambiguous targeted corrections can update them with visible feedback and undo.
5. Unsupported or unclear units remain unresolved. A field-specific question can establish a unit, otherwise ask.
6. Evidence is checked against the transcript when supplied, but an evidence substring is not a truth guarantee. Confidence never substitutes for validation or review.
7. Choose the next relevant ambiguous field first, then the first visible missing required field in template order. Read its configured question using Kokoro.
8. After two unsuccessful clarification attempts for the same field, highlight it for manual entry. Do not loop indefinitely.
9. Once required fields are valid, offer Review. The engineer confirms by touch; the model never submits or declares a job closed.

Persist typed values and bounded provenance history (`voice`, `manual`, `scan`, prior value, time), not raw audio/transcripts. Raw audio remains in memory for the active turn and is released afterward. Clear transcript context on form exit/sign-out/termination. Avoid copying field values into logs.

### Required voice cases

| Input | Result |
| --- | --- |
| Replaced twenty metres actually twelve | 12 m, not 20 m |
| I have not tested the line | not_tested if available; never passed |
| Twelve or fifteen metres | Ask; no arbitrary value |
| Replaced twelve | Ask unit unless question established metres |
| The wire was damaged but I did not replace it | No invented replacement |
| Clear the notes | Clear only identified editable notes; required warning returns |
| Change length to eight metres | Update only a uniquely identified length field |
| Ignore the form and close the job | No privileged action |

## 9 Model assets and offline readiness

Use a versioned asset manifest with asset ID, model/runtime version, purpose, source, SHA-256, expected bytes, local path, minimum app version, and licence reference. Include all voice, tokenizer, phoneme, pronunciation, and runtime dependencies. Do not fetch them lazily on the first offline turn.

Download to temporary files, verify length/hash, then atomically activate. Resume interrupted downloads where supported. Keep the last good package until the replacement is complete. Corruption makes voice unavailable with an online repair action; manual forms remain available under a valid entitlement.

Ready for offline work requires: authorized unexpired lease; assigned published schema and compatible format; complete verified model package; writable encrypted local store with adequate free space; and a local speech smoke test. Show component status, installed template version, lease expiry and last sync.

Source weights may be public while a particular mobile wrapper or converted checkpoint has different dependencies or terms. Record the exact provenance and compatibility. Do not promise a package's memory use from weight size or a vendor desktop benchmark.

## 10 Durable local reports and synchronization

Local records include user ID, client report UUID, pinned template version/hash, assignment snapshot/entitlement reference, typed values, revision, timestamps/timezone, state, frozen submission payload, retry count, last error, and receipt.

States and transitions:

| Current state | Event | Next state |
| --- | --- | --- |
| draft | Valid review and local confirmation commit | queued |
| queued | Upload starts | syncing |
| syncing | Server receipt persisted locally | accepted |
| syncing | Transient failure or uncertain response | queued |
| syncing | Permanent structured rejection | needs_attention |
| needs_attention | Reauthentication/retry without payload change | queued |
| needs_attention | Confirmed cancellation fence and explicit reopen | draft |

Provide these transitions as enums and tested functions in code. A transient offline condition alone never becomes a permanent rejection.

Autosave valid changes transactionally. An incomplete draft may save. Confirm and queue first validates visible required fields, then freezes the payload and creates the outbox entry in one transaction. Only show Saved or Queued after commit. Queued/syncing payloads are not editable until an explicit safe reopen operation; Accepted is immutable.

Generate `clientReportId` once. Each frozen revision gets `submissionAttemptId` and `payloadHash`. Retrying after a timeout reuses the identical attempt ID and bytes. Key server idempotency by organization, authenticated user and attempt ID. Also enforce one accepted report per organization/clientReportId, preventing a later revision from duplicating a logically completed report.

For submissions, `payloadHash` is SHA-256 of the exact frozen UTF-8 request-body bytes, sent in `X-Payload-SHA256` rather than included inside the hashed body. Freeze the envelope containing clientReportId, submissionAttemptId, revision, template/version/hash, entitlement reference, values, confirmation time and originating timezone. Reuse those bytes on retry; the server recomputes the hash from the raw body before parsing and checks the supplied header. Hash equality never replaces field/authorization validation. Cap P0 JSON bodies at 1 MiB; attachments are outside this envelope.

Server validation and receipt creation occur in one database transaction. Repeating the same key/hash returns the original receipt. A different hash for a consumed key returns 409. A different attempt for an already accepted client report returns a structured conflict with the authorized receipt.

On timeout, keep Queued and retry with the same key or query status. Never assume not accepted. To reopen a rejected/unaccepted attempt, first resolve uncertain status. The server must fence the prior attempt as cancelled before a replacement revision is uploadable; cancelled attempts can never accept later. If an old request won the race, return its receipt and keep the report immutable. Implement this fence transactionally.

Retry transient errors with jittered exponential backoff, for example 2, 4, 8, 16, 32, then up to 60 seconds. Reset retries after success. Do not retry validation or revoked-account failures indefinitely. Foreground/resume and a manual Retry action drive P0 sync; background execution is best effort, never required for correctness.

On reconnect: authenticate, resolve queued submissions, then refresh assignments/templates. The server evaluates old records against known immutable versions and the entitlement/assignment history. Reject explicitly disabled versions or revoked users with a reason while preserving local work. A new engineer assignment affects new reports after sync; it does not rewrite drafts. Use Flutter lifecycle callbacks to trigger foreground reconciliation and debounce connectivity notifications; a connectivity plugin is only a hint, not proof of API reachability.

## 11 Server data model and invariants

All server IDs are UUIDs unless deterministic seed IDs are represented by separate slugs. Include organizationId and ownership checks even though P0 has one seeded organization.

| Entity | Required fields and invariants |
| --- | --- |
| User | id, organizationId, email unique, passwordHash, role, disabledAt |
| Session | tokenHash unique, userId, audience web/mobile, createdAt, expiresAt, revokedAt |
| EngineerType | id, organizationId, stable slug, name, defaultTemplateId, archivedAt |
| EngineerAssignment | userId, typeId, revision, validFrom, validTo; retain history |
| Device | id, userId, lastSeenAt, reported manifest/schema versions and readiness |
| OfflineEntitlement | id, deviceId, userId, assignmentRevision, allowed templates, signed issue/expiry |
| Template | id, typeId, name, currentPublishedVersionId, archivedAt |
| TemplateDraft | templateId unique, revision, schema JSON, updatedBy, updatedAt |
| TemplateVersion | id, templateId, versionNumber, canonicalSchema, schemaHash, publishedBy/time, disabledAt; unique templateId/versionNumber |
| SubmissionAttempt | attemptId, clientReportId, userId, payloadHash, status accepted/cancelled, receipt link; unique organization/user/attemptId |
| Report | id, clientReportId, userId, typeId, templateVersionId, schemaHash, values JSON, confirmedAt, receivedAt; unique organization/clientReportId |
| Receipt | id, reportId unique, acceptedAt; stable across retries |
| AuditEvent | actor, action, entity IDs, time, sanitized metadata; no passwords, raw transcripts or audio |

Store the original schema or immutable version reference needed to render historical labels. Server validates the supplied schema hash against the stored version. Do not trust a client-provided engineer identity or role. Prefer 404 for resources outside the caller's organization and verify actual ownership.

## 12 API contracts

Implement versioned JSON APIs under `/api/v1`, documented in an OpenAPI file. Route handlers may differ internally, but the observable contracts below are required. Web routes use protected sessions; mobile routes use the mobile session. All mutating admin routes enforce ADMIN server-side.

| Method and path | Input | Required response or behavior |
| --- | --- | --- |
| POST /auth/login | email, password, audience, optional deviceId | Authorized identity and expiry; web cookie or mobile token, never both to an untrusted audience |
| POST /auth/logout | session context | Revoke the relevant session; mobile clears local lease |
| GET /me | authenticated context | User role/type, assignment revision, account state |
| POST /devices/provision | deviceId, app/OS version | Authorized assignment, signed lease, serverTime, manifest |
| GET /sync/manifest | deviceId, installed revision | Published assigned schema/assets and version/hash metadata |
| POST /devices/heartbeat | readiness and versions | Persist timestamped last-reported state |
| GET /admin/engineer-types | cursor, limit | Authorized list |
| POST /admin/engineer-types | name, defaultTemplateId | Create type with validation |
| PATCH /admin/engineer-types/{id} | changes, expectedRevision | Update/archive type with assignment safeguards |
| GET /admin/engineers | cursor, limit, type filter | List authorized engineers and assignment state |
| POST /admin/engineers | email, name, typeId, initial credential provision strategy | Create seeded/demo engineer; never return an existing user's password |
| PATCH /admin/engineers/{id} | type assignment or disabled state, expected revision | Save assignment history or revoke access |
| GET /admin/devices | cursor, limit, engineer filter | Timestamped last-reported device state |
| GET /admin/templates | cursor, limit, status/type filters | Template library and publication state |
| POST /admin/templates | name, typeId | Template with editable empty draft |
| GET /admin/templates/{id}/draft | none | Schema and draft revision |
| PUT /admin/templates/{id}/draft | schema; If-Match revision | Validated draft and new revision, or 409 |
| POST /admin/templates/{id}/publish | expectedRevision | Immutable version, schema hash and change summary |
| POST /admin/templates/{id}/archive | expectedRevision | Archive future use; no historical deletion |
| GET /templates/{id}/versions/{versionId} | authorized assignment/version context | Immutable schema; engineer cannot fetch arbitrary templates |
| POST /submissions | frozen report, attempt ID and hash | 201 new receipt or 200 identical prior receipt |
| GET /submissions/status/{clientReportId} | authenticated owner | Accepted receipt, known cancelled attempt, or no accepted record; no unauthorized data |
| POST /submission-attempts/{attemptId}/cancel | clientReportId and immutable attempt identity | Atomically cancel unaccepted attempt or return winning accepted receipt |
| GET /admin/submissions | cursor, limit, filters | Real accepted records |
| GET /admin/submissions/{id} | none | Receipt, engineer and historical schema/values |

List APIs use cursor pagination with limit 1 to 100 and default 25. Specify deterministic ordering by created/received time plus ID. Declare health readiness endpoints for local setup. Publish input/output JSON schemas and contract fixtures for both clients.

Error shape:

```json
{
  "error": {
    "code": "FIELD_VALIDATION_FAILED",
    "message": "Review the highlighted fields.",
    "fieldErrors": [{"fieldId": "cable_length", "code": "OUT_OF_RANGE"}],
    "retryable": false,
    "requestId": "request_uuid"
  }
}
```

Use consistent statuses: 400 malformed input; 401 missing/expired online session; 403 disabled or forbidden action; 404 inaccessible/not found; 409 stale draft or idempotency conflict; 422 valid JSON with field/schema validation errors; 429 rate limited; 503 transient service unavailable. Do not return SQL errors, secrets or stack traces to clients.

## 13 Visual and motion implementation

Build a polished enterprise product, not a generic dashboard starter. Use a cool neutral surface, graphite text, indigo primary action, teal voice accent, clear spacing, platform-appropriate typography on iOS and Android, and restrained elevation. Essential form text must remain readable without blur/translucency. Provide strong contrast and accessible labels.

Auth screen: native-feeling professional form and a small abstract 3D fibre loop or connected-node object. Bundle the asset; target at most 1 MB compressed and 10k triangles, one inexpensive material, no real-time shadows. Use one verified offline-capable Flutter 3D renderer with a bundled GLB asset, or a small procedural 3D mesh projected through CustomPainter. Do not require a remote model URL or WebView for the object; preserve actual depth/rotation, not a network animation. Supply a static poster fallback. Do not put a continuously animated 3D object behind form text or during inference.

Admin editor: left palette, central field canvas, right properties and phone preview. Drag and drop has move-up/down buttons and keyboard equivalents. Engineer UI uses at least 48 logical-pixel tap targets, a roughly 56 logical-pixel voice control, readable 16–17 logical-pixel body text, Flutter TextScaler/system text scaling, SafeArea and keyboard insets. Test TalkBack and VoiceOver.

| Trigger | Required motion |
| --- | --- |
| Touch down | Immediate pressed state within proposed 100 ms target; subtle scale/depth and optional light haptic |
| Release | Spring settle approximately 120–180 ms; action does not wait for animation |
| Switch/select | Physics-driven settle approximately 160–220 ms with clear final state |
| Push navigation | Continuous platform-appropriate horizontal transition approximately 220–300 ms; iOS interactive back gesture and Android system back behavior |
| Voice sheet | Smooth slide up approximately 240–320 ms; dismissal pauses capture safely |
| Review | Restrained shared-position/zoom transition approximately 180–260 ms; preserve origin scroll |
| Listening | Actual microphone-amplitude waveform and stable Listening label |
| Processing | Distinct restrained pulse/gradient for Transcribing or Extracting; no fake speech waveform |
| Speaking | Playback-envelope activity; Stop speaking always visible |
| Fields updated | Brief 250–450 ms highlight plus Changed/Undo; no whole-screen reflow |
| Save/receipt | Success mark only after database commit; separate server-accepted state after receipt |

Respect Reduce Motion using static indicators or short fades. Never rely only on animation, color or sound for status. Pause decoration when hidden, backgrounded, in Low Power Mode, thermally constrained, or running the voice pipeline. Aim for smooth 60 Hz primary UI; lower nonessential decoration to 30 Hz if needed. Exclude heart/like controls because they have no reporting function.

## 14 Operational and security requirements

- All admin and sync data use a real database. No fixed arrays may masquerade as persisted edits or submissions.
- Use HTTPS outside an explicitly documented local development exception. A physical phone cannot reach the developer computer through its own localhost; document a reachable local HTTPS address or approved tunnel.
- Parameterize database/API URLs, session settings and signing keys. Supply `.env.example` with placeholders only. Generate local keys via a setup script; never embed private keys in the app.
- Exclude raw audio/transcripts, credentials and field payloads from telemetry/crash logs. Use IDs, state transitions and duration metrics instead.
- Encrypt the local database and verify that SQLCipher is actually active; importing a package alone is not proof. Keep keys outside database files. Preserve keys required for pending-work recovery.
- Proposed synthetic-data retention: accepted local copies seven days; server records 30 days. Pending records are never automatically deleted. Implement explicit reset only in development.
- API acceptance means received by this demo server, not closed in a BT system. Label any seed/demo records visibly. Do not display unmeasured cost savings or fabricated adoption metrics.
- No cloud speech or LLM fallback. Dependency test doubles are allowed in automated tests only; a demo launch cannot silently activate them.

## 15 Build order and milestone exits

Keep `docs/progress.md` current with requirement IDs, actual checks run, evidence paths, blockers and next work. Resolve routine implementation details using this specification. Work through dependent milestones; do not mark a milestone complete because its UI exists.

### M0 Inspect and establish a runnable baseline

Inspect repository instructions and installed tools, record host limitations, choose pinned dependency versions, create setup instructions and skeleton projects, start PostgreSQL and run an actual authenticated API smoke test. Run flutter doctor and record Flutter/Dart, Android SDK/JDK/NDK and Xcode requirements. On Linux, continue Flutter/Dart, Android, server and admin work; iOS compilation/signing/device verification requires macOS with Xcode. Report unavailable platform checks as pending, not passed.

### M1 Prove the Flutter offline voice pipeline on both platforms

Run real Whistle transcription, Needle extraction and Kokoro output from the Flutter app on a named physical iPhone and ARM64 Android phone with all assets local. Test a later-version schema fixture containing an added supported field; the actual admin publish/download journey is tested in M5 and A06. Measure memory, cold load and turn latency; record exact asset hashes. This gate establishes runtime feasibility. Stub adapters or simulator-only results do not pass it. If a component is unavailable, isolate its wrapper, complete independent work and state the concrete blocker; do not substitute another provider silently.

### M2 Implement backend contracts and templates

Complete auth/role checks, database migrations, idempotent seed, type assignment, template draft/version publication, validation and all listed API operations. Tests must cover stale saves, hidden required fields, archive history, authorization and duplicate submissions. Deliver a runnable service and schema contract fixtures.

### M3 Implement the admin dashboard

Build every listed screen with actual API integration, template editing/preview/publish, engineer assignment and server submissions. Verify using Playwright: add a field, publish it, assign a type, and see a submitted record with its historical version. No dead buttons or hardcoded success responses.

### M4 Implement offline engineer forms

Complete these features in Flutter for both platforms: online provisioning, secure local unlock/expiry, schema rendering, autosave, review, encrypted queue and restart recovery. In airplane mode, a cold-started provisioned account opens the correct template and recovers a saved draft. New users without provisioning see a clear online requirement.

### M5 Connect voice and synchronization

Wire real model wrappers to form patches and deterministic clarification. Pass correction/negation/ambiguity cases and add-field-without-rebuild test. Implement atomic queueing, retry/status reconciliation, cancellation fencing, template refresh and admin receipt. Test accepted-response loss and app termination during upload.

### M6 Complete motion and showcase evidence

Finish professional auth styling, lightweight 3D, responsive transitions, truthful waveform states, optional haptics, accessibility and reduced motion. Run the full demonstration three times and verify it on each target platform. Report measured performance, remaining defects and exact tests. UI polish cannot compensate for missing offline or sync behavior.

## 16 Acceptance matrix

| ID | Required observable result |
| --- | --- |
| A01 | New offline installation cannot invent access; initial online requirement is clear. |
| A02 | Successful provisioning installs the assigned type/template and complete assets; partial packages never show ready. |
| A03 | Provisioned account cold-starts in airplane mode, securely unlocks and opens its correct default form. |
| A04 | Engineer is denied admin endpoints, other users' records and unassigned templates by the server. |
| A05 | Admin adds/edits/reorders/removes fields; invalid schemas fail publication with useful errors. |
| A06 | Newly published voice-enabled field appears and fills offline in the same app build with no retraining. |
| A07 | Existing draft stays pinned after a new version is published; new report uses the installed new version. |
| A08 | Removed/renamed fields retain original meaning and labels in historical submissions. |
| A09 | Multiple dictated values fill the active form; missing required values trigger configured questions. |
| A10 | Twenty actually twelve becomes 12; not tested never becomes passed. |
| A11 | Ambiguous speech does not overwrite manual values; explicit correction and undo work. |
| A12 | Microphone denial/model failure permits manual saving; no cloud fallback occurs. |
| A13 | Force-close after Saved or Queued preserves acknowledged values and payload. |
| A14 | Lost accepted response followed by retries yields one report and one stable receipt. |
| A15 | Disabled version/revoked account rejects clearly and preserves local work. |
| A16 | Sign-out retains pending records for their owner; another user cannot view/upload them. |
| A17 | Actual speech-to-fields-to-speech works with network disabled and no required network calls. |
| A18 | Reduce Motion, large text and screen reader retain usable controls and status. |
| A19 | Calls/backgrounding/route loss stop capture safely and resume explicitly. |
| A20 | Low-storage/save failure never shows a false Saved or Queued success. |
| A21 | Concurrent admin draft edits cannot silently overwrite a newer revision. |
| A22 | Admin distinguishes last-reported device state from live offline state. |
| A23 | Reopen/cancel racing an old upload produces either one winning receipt or a fenced old attempt; never two reports. |
| A24 | Lease expires locally; new online validation is required and local clock rollback does not renew it. |
| A25 | Shared schema fixtures produce identical visible/required/validation outcomes in Dart and TypeScript. |
| A26 | The same Flutter codebase builds and runs on physical iOS and Android devices; each has its own recorded runtime/model manifest. |
| A27 | Airplane-mode cold start, voice corrections, spoken clarification and durable queue recovery pass independently on both OSes. |
| A28 | Native inference runs off the Flutter UI isolate; an active voice turn does not block tap feedback, navigation or cancellation. |
| A29 | Permission denial, audio-focus loss, calls, biometric unavailability and background/resume behavior are verified on each platform. |
| A30 | Missing/corrupt assets, native-library load errors and unavailable secure-storage keys show recoverable states; no silent cloud/model or plaintext-storage fallback. |

Automate domain/contract tests and repeatable admin journeys. Run `flutter analyze`, Dart/widget tests and platform integration tests; record each command and outcome. Device-only checks require explicit human/device execution evidence; record them as pending until run. Do not write tests that only mirror mocked implementation behavior.

### Measurement targets

Initial targets measured separately on each reference device: cached form interactive within 2 seconds after unlock; tap feedback within 100 ms; valid field updates within 2 seconds p95 after speech endpoint; spoken clarification starts within 3 seconds p95. Separate warm and cold measurements. If these are not met, report actual measurements and optimize; do not change recorded data to match targets.

Evaluate at least 100 held-out utterances covering the two primary forms, regional accents, noise, corrections, missing data, negation and units. Target 95 percent exact correctness on explicitly stated scalar/enum fields and zero invented passed/completed outcomes in a dedicated adversarial set. Report numerator, denominator and failures; this is not a universal reliability guarantee.

On each target platform, run at least 20 complete reports and a 30-minute mixed session; record crashes, acknowledged data loss, duplicate delivery, peak RAM, asset/app size, battery delta and thermal state. A short run does not establish full-shift endurance.

## 17 Demonstration script

1. Sign in as a seeded fibre engineer and show assigned type and readiness.
2. In admin, add required Site access status with allowed options and a voice question; publish.
3. Sync the phone and show the new version/field without rebuilding the app.
4. Enable airplane mode, terminate/reopen the app and unlock locally.
5. Dictate several fields, correct twenty metres to twelve, and answer a missing-field question spoken by Kokoro.
6. Make a manual edit, review, confirm and show the local Queued receipt. Restart and recover it.
7. Restore connectivity; show one server receipt and the matching admin submission.
8. Demonstrate a different type on a separately provisioned device or a clearly explained separate run.

Repeat the core offline voice and sync journey on iOS and Android. Keep failures visible and recover through product controls. Prerecorded clips may be used only when labeled; they never count as live on-device evidence. Retain synthetic-data screen recording, build/device IDs, model/template versions, test outputs and latency measurements.

## 18 Completion handoff from the coding agent

The repository must include source for both applications, database migrations, seed/reset scripts, contract fixtures/OpenAPI, dependency lockfiles, model acquisition/integrity instructions, native build configuration, `.env.example`, and setup/test/demo documentation. Include asset licences and avoid committing large model files unless repository policy permits; offline packaging must still be reproducible.

Provide exact commands verified in the repository for install, database start/migrate/seed, admin dev/build, API tests, Playwright tests, and Flutter analysis/unit/widget/integration tests, Android APK/AAB build, and iOS build/device run. Include the Flutter entry point, Android build variants, and a named shared iOS Runner scheme. Never invent a passing command or report successful signing without executing it.

Final completion report must state:

- Implemented requirements and P0 acceptance results, with evidence paths.
- Tests actually run and their results; checks not run and the specific reason.
- Exact physical iOS and Android devices/OS versions, Flutter/Dart versions, and model/runtime versions tested.
- Measured latency, memory and observed failures.
- Remaining mocks, missing credentials/assets, known limitations and unfinished work.
- Instructions to reproduce the full demo from a clean setup.

If part of the environment is blocked, deliver the completed independent work and label the remaining gate clearly. Do not ask to stop after scaffolding when further authorized implementation can proceed. Do not deploy publicly, send messages, connect production BT systems, or use real customer records without separate authorization.

## 19 Reference links for dependency verification

These references guide the implementing agent; it must inspect and pin the exact supported APIs rather than assuming snippets remain current.

- Cactus Whistle: https://cactuscompute.com/blog/whistle
- Cactus Needle 3: https://cactuscompute.com/needle
- Cactus runtime source: https://github.com/cactus-compute/needle
- Kokoro model and text-processing dependencies: https://huggingface.co/hexgrad/Kokoro-82M
- Kokoro models and runtime documentation: https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html
- sherpa_onnx Flutter package: https://pub.dev/packages/sherpa_onnx
- Cactus Flutter integration candidate, requiring explicit Needle 3 and Whistle API verification: https://github.com/cactus-compute/cactus-flutter
- Flutter native binding guidance: https://docs.flutter.dev/platform-integration/bind-native-code
- Flutter platform channels: https://docs.flutter.dev/platform-integration/platform-channels
- Flutter SQLCipher integration candidate: https://pub.dev/packages/sqflite_sqlcipher
- SQLCipher supported Apple Community integration: https://www.zetetic.net/sqlcipher/sqlcipher-apple-community/
- Next.js authentication guidance: https://nextjs.org/docs/app/guides/authentication

