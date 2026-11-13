# Phone-first voice demonstration

## Current Android APK — version 0.3.6 / build 24 · no demo expiration

The current demo is `output/android/Field-Assist-v0.3.6-arm64.apk`
(468,530,452 bytes; 468.5 MB), Android version code 2024, for ARM64 Android 12+.
Install it over the previous demo to retain encrypted drafts and queued reports.

The synthetic closure demo now has **no offline expiration**. It uses an
explicitly authorised ES256-signed grant with `expiresAt: null` and no JWT `exp`,
rather than a distant expiry date or an ignored signature. Existing timed demo
installations switch to the bundled grant on their first updated launch, without
clearing their workspace. Profile → Offline readiness shows
**Demo access · No expiration**. Voice capture, forms and saved work need no
periodic connection for renewal. Delivering reports to the dashboard still needs
a connection; online sessions and account permissions are unchanged.

This is limited to the explicit debug/bundled `closure@fieldassist.demo` account,
its synthetic organisation and closure form. The local backend opt-in is
`NON_EXPIRING_SYNTHETIC_DEMO=true`; the default example setting remains false.
Apply database migrations and regenerate the Prisma client before starting an
updated backend, then run `node --import tsx scripts/prepare-offline-demo.ts`
to prepare a newly signed bundle. Normal account provisioning keeps its 72-hour
lease, and another engineer cannot request the non-expiring grant.

Verification: 131 selected Flutter regressions and 143 contract checks passed;
Flutter analysis, dashboard typechecking and its production build passed. Live
API checks verified the signed grant in 2050, its null server-side expiry,
ordinary 72-hour provisioning and rejection of another engineer's opt-in.
All 369 model files and 169 voice prompts verified inside the APK. The APK
signature matches the previous demo; native math linkage and ZIP/ELF 16 KiB
alignment passed. Physical-phone microphone and battery acceptance remain
separate checks. The default current local API is `http://192.168.1.9:3002/api/v1/`;
change Profile → Demo dashboard connection when the Mac changes networks.

## Previous Android APK — version 0.3.5 / build 23

The installable demo is `output/android/Field-Assist-v0.3.5-arm64.apk`
(468,525,160 bytes; 468.5 MB), with Android version code 2023. It requires
ARM64 Android 12 / API 31 or later and uses the same signing certificate as
the previous demo. Install it as an update to retain encrypted drafts.
Adjacent JSON and SHA-256 files record the build and verification results.

This build includes the fifteen-field S1 summary, grounded ONT location and
installation mapping, optical-reading punctuation/correction handling, and
capture of additions after “anything else.” The offline bundle contains eight
synthetic visits, including **S1 · 15-field voice test**, and the unchanged
Moonshine/Silero, Needle3 and Kokoro models. No asset-reference question returns.

Normal backend provisioning renewed the signed offline demo access until
**14 November 2026 at 13:34 IST**. No access checks were bypassed. The default
phone API is `http://192.168.5.79:3002/api/v1/`; phone and Mac need a shared
local network for delivery and renewal. Change the address under
**Profile → Demo dashboard connection** when the Mac changes networks.

Verification passed: 89 selected Flutter regressions, static analysis,
369 model-file hashes, 169 voice-prompt hashes, APK signature v2, native math
linkage, and ZIP/ELF 16 KiB alignment. The APK updated the existing Android
emulator installation and launched its normal activity. Physical-phone
microphone, speaker, accuracy and battery testing remain pending.

## Previous Android APK — version 0.3.4 / build 22

The current artifact is `.local/demo-builds/field-assist-demo-v0.3.4-arm64.apk`
(468,519,812 bytes; 468.5 MB), a signed debug demo for ARM64 Android 12 / API 31
or later, split version code 2022. Its signing identity matches the previous
demo, so install it as an update to retain local data. The superseded 0.3.1 APK
was removed after verification. Adjacent JSON and SHA-256 files record this build.

This APK includes the five-field summary without an asset-reference question,
transcript editing, contextual answer repair and four selectable offline voices.
All 369 model-file hashes and 169 voice-prompt hashes passed package verification;
APK signature v2 and the native math-library dependency passed inspection.
The refreshed offline bundle and access suite passed 19 checks. Physical-phone
microphone and speaker testing remains for the presentation devices.

The synthetic offline account was renewed through normal backend provisioning;
its signed access expires **28 October 2026 at 20:55 IST**. Offline capture and
queued submissions work during that lease. Reconnection to the configured demo
backend is needed for renewal and dashboard delivery. No expiry or signature
check was bypassed. The previous version sections below describe their historical
builds.

## Five-field visit summary — version 0.3.4 / build 22

The short summary no longer includes or asks for an asset reference. Its five
answers are work done, visit outcome, optical receive reading, test result and
follow-up. Older editable drafts are projected into those five fields when
opened, so their removed reference cannot re-enter the question queue or a new
submission. Original spoken narratives and historical submitted payloads remain
available. Historical dashboard receipts can still display a previously
recorded reference; new summaries have no empty reference row. The separate full
operational checklist is unchanged.

The five-field capture, missing-question, measurement-confirmation, edit and
submission checks passed (57 Flutter checks and six API contract tests). Static
analysis and dashboard typechecking passed. The submission contract also accepts
the bounded original-speech audit metadata retained by the transcript editor.

## Context, transcript editing and voice choice — version 0.3.3 / build 21

The offline form now accepts the reported **past / passed** homophone in a
test-result answer and an explicit service-test sentence. Negatives,
qualifications, alternatives and references to something being in the past
remain unresolved. In an asset question, **Paul / Paule** can identify the pole
type and **chambe / chemba** the chamber type. A number or reference is still
needed: the assistant asks for that part aloud and can combine it with the
previous spoken type. It retains both source turns. Asset prefixes are parsed
longest first and explicit leading zeros are preserved. A person's name in an
unrelated narrative is not rewritten into a pole identifier.

Recognised but unmatched answers now receive a spoken clarification tailored to
the current question, with continued automatic listening. They no longer force
a manual-form handoff after two mismatches. Hardware, access or inference
failures can still pause capture; typed answers and visible choices remain
optional recovery routes. These changes are bounded interpretation and dialogue
rules; no STT fine-tuning or general-language intelligence improvement is claimed.

**Edit spoken words** is available on the six-field summary and its review page.
Choose the opening summary or a spoken answer, correct its transcript, then
**Save & update form**. Editing the summary remaps its inferred fields while
preserving explicit answers to other questions. Unresolved edited answers
remain missing and ambiguous readings retain their confirmation gate. The
original speech source is retained with the encrypted draft and a new review is
required before submission.

Under **Profile → AI voice**, engineers can preview and choose **George, Emma,
Michael or Sarah**. These use the existing Kokoro English v0.19 model and its
[documented speaker IDs](https://k2-fsa.github.io/sherpa/onnx/tts/all/English/kokoro-en-v0_19.html).
The preference is stored with account settings. Previewing a voice does not
select it. Prepared audio is matched to the selected speaker; a different
speaker's recording cannot be borrowed. The default speech rate uses prepared
clips for the six-field questions in all four voices; other text or a changed
rate uses local synthesis. The output-level processing and speech-only policy
are shared across voices. Fresh and resumed conversations rotate through
three context-appropriate openings using an account-local counter.

Verification: **130 relevant unit/widget checks passed**, followed by **11
focused journey checks** using the reported homophones, transcript editing and
voice preferences. App and voice-package analysis passed and the iOS simulator
build compiled. The four voice packs contain **169 integrity-checked clips**;
the model weights are unchanged. Real microphone accuracy across accents and
site noise still needs the engineer recording pack and phone testing. The
existing Android APK remains version 0.3.1; these changes are running in the
0.3.3 iPhone simulator build and source, not a newly delivered APK.

## iOS playback revision — version 0.3.2 / build 20

iOS prompt output now uses an in-memory AVAudioPlayer instead of the SoLoud
deferred-pause worker seen in the two reported SIGABRT crash stacks. Output is
fully stopped before capture starts; the recorder configures its input after
the previous output session deactivates. Android playback and the offline
Moonshine/Needle3/Kokoro models are unchanged. This remains automatic turn-taking;
it does not add simultaneous speech/interruption detection.

Native simulator audio checks **passed after the Mac restart** on 25 October.
The recorder-only probe received microphone PCM at both 48 kHz and 16 kHz on
iOS 27.1. Eight consecutive native output/input turns passed, followed by
stop/replay and duck/restore checks. The normal 0.3.2 app was then reopened on
the original iOS 27.0 simulator and reached automatic listening after its S1
greeting. These checks establish audio startup and handoff, not recognition
accuracy, end-to-end latency or physical-phone acceptance.

Before the restart, capture stalled or aborted in `AURemoteIO` even in the
recorder-only probe. Host `coreaudiod` logs reported that the built-in microphone
device was not running and an audio-device processing assertion; microphone
authorization was granted. The restart restored capture without further app
code changes. Before/after evidence is recorded in
`fixtures/voice/benchmarks/ios-audio-handoff-20261025.json`; the successful logs
are `.local/ios-capture-after-reboot-20261025.log` and
`.local/ios-handoff-after-reboot-20261025.log` (ignored local diagnostics).

Run integration diagnostics on a dedicated simulator with **`--no-uninstall`**
and back up needed app data first. Flutter's default integration-test cleanup
uninstalled the original simulator app during this investigation, resetting its
local data; server submissions were not changed. The normal demo is reinstalled.
The existing Android APK below remains version 0.3.1 / build 19.

## Offline speech correction demo — version 0.3.1

The current Android artifact is `.local/demo-builds/field-assist-demo-v0.3.1-arm64.apk`, version 0.3.1 / build 19 (split version code 2019). It keeps the existing offline Moonshine/Needle3/Kokoro package and adds explicit spoken-correction handling, improved optical mapping and retained additions after “anything else.” The old 0.3.0 APK was removed after the update verified.

See [speech correction checks](speech-repair.md) for scope and evidence, and [Indian/UK English training preparation](moonshine-training.md) for the recording pack. No fine-tuned checkpoint has been produced yet.

## Earlier offline streaming demo — version 0.3.0

The earlier artifact was `.local/demo-builds/field-assist-demo-v0.3.0-arm64.apk`: **453,089,062 bytes (453.1 MB)**, signed ARM64 debug demo, Android 12 / API 31+, version code **2018**. This is **413,989,946 bytes smaller (47.75%)** than 0.2.2. Its adjacent JSON and SHA-256 files record the checksum and verification scope. Install over the previous demo to retain encrypted drafts and queued submissions. The APK contains 369 verified model files, 21 chunks and 91 prepared prompts. Qwen weights and llama/ggml native libraries are absent.

### Small-model extraction in 0.3.0

The summary uses the existing **35,335,380-byte Needle3** model, shared with the full operational checklist. Direct, explicit phrases and exact measurements map locally; unresolved outcome/test wording is proposed through one narrow enum tool per source clause. Native proposals require confidence of at least 0.7, a valid schema and independent source, uncertainty and negation checks. The model never supplies numeric readings or asset identifiers. Unsupported paraphrases remain follow-up questions: the small model is not a general-language accuracy guarantee, and one native probe left “Everything is now done. The service verification was successful” unresolved. No fine-tuning has been performed.

The longer-summary capture, delayed additional-detail capture, Anything else once, visible auto-fill and dB/dBm confirmation behavior from 0.2.2 are retained. **149 targeted unit/widget checks** passed, including the additional small-model schema and confidence checks. **Nine synthetic native Mac audio replays passed**; evidence is in `fixtures/voice/benchmarks/needle-streaming-replays-20261023.json`, separately from the earlier Qwen baseline. Physical-phone microphone and site-noise acceptance remain outstanding.

### Capturing full summaries in 0.2.2

Opening summaries and additional details now allow **1.8 seconds of neural silence** between phrases. Focused answers retain the **450 ms** silence target, including a short No after Anything else. The invitation to add details waits **8 seconds** for speech to begin. Processing time and recorder setup add to these targets. The listening indicator appears only after the microphone has connected; the playback handoff guard is 40 ms. This remains a turn-taking conversation: microphone capture starts after the bot finishes speaking.

Anything else is asked once. An extra narrative is joined to the original summary and saved, then the bot moves directly to missing fields or review. A speech-positive but empty/noise recognition result asks for the extra detail again instead of treating it as Nothing else. Queued microphone audio is processed before an older quiet update can end the turn. Opening the draft during an addition preserves the existing summary and recognised additional text, then remaps its explicit facts.

The reported **optical receive reading was -18.2 dB** now proposes **−18.2** and requests confirmation of the **dBm unit**. It does not silently equate dB and dBm or infer a receive measurement from unrelated noise/loss readings. **144 targeted unit/widget tests** passed, including progressively arriving sentences separated by 1.2-second pauses, an addition beginning 4.5 seconds after the prompt, empty-result recovery, and both summaries surviving draft exit. **Nine synthetic native Mac replays** passed; the new audio cases cover those sentence pauses and delayed speech. See `fixtures/voice/benchmarks/moonshine-summary-pauses-20261023.json`. These checks do not certify live microphone recognition for the presenter's accent or site noise.

### Auto-fill repair in 0.2.1

Spoken summaries, resumed drafts containing only Work done, and direct edits to Work done all run local structured extraction. Derived fields refresh their visible input values without replacing the engineer's typing controller. Changed summaries update or retract previously inferred facts; explicit manual answers and confirmed readings are preserved. Review runs extraction before validating, so a quick tap cannot race the typing debounce.

The reported transcript “optical receive driven was -18 0.2 dBm” now proposes **−18.2 dBm** with the exact original evidence. Because the number has separate parts, the bot asks **I heard minus 18.2 dBm. Is that correct? Say yes or no.** Yes accepts the proposal; No clears it and asks for the measurement. Both spoken and selected confirmations advance automatically. Manual entry has the same confirmation option, and review is blocked until an ambiguous proposal is confirmed or corrected. A clear “optical receive -18.2 dBm” fills directly. An asset reference is still a missing question when none was stated.

The 0.2.1 baseline passed **139 targeted unit/widget checks**, including the earlier failed transcript, visible input updates, voice Yes/No through final review, preservation of manual corrections, offline submission and completion navigation. Seven synthetic native Mac audio replays also passed with vocabulary bias 2.0 for field terms; numbers are not biased. Its evidence is in `fixtures/voice/benchmarks/moonshine-host-autofill-20261023.json`. Those fixtures did not expose the later sentence-pause capture issue; the 0.2.2 cases above address it. Version 0.2.1 also launched in the iPhone simulator and reached **Offline voice package verified on this device**.

Recognition uses **Moonshine Small Streaming English (123M), SDK 0.1.5**, with **Silero VAD embedded in the native runtime**. Microphone PCM is processed during the answer; the final transcript is extracted once the neural detector observes trailing silence. Focused answers use a 450 ms silence target and the opening narrative uses 1800 ms. Native inference, microphone buffering, saving and playback add time; these targets are not a promise of instantaneous replies. An empty opening moves to guided questions instead of asking “Anything else?”. A short spoken “No” ends the additional-summary turn. Selecting an answer still advances automatically and cancels stale recognition.

The six-field summary combines exact, source-grounded number/asset parsing with **Needle3** proposals for missing qualitative fields. Every proposal must be supported by the transcript. For example, “Reading was minus 18.2DBM” fills **−18.2**, while “Paul. Paul.” cannot become an asset ID. Ambiguous or absent facts remain questions. Spoken responses can populate multiple fields; only unresolved or invalid fields are requested. Human review and submission remain required.

All model files are bundled: **335,583,457 bytes across 369 verified files**, installed from **21 chunks of at most 16 MiB**. The package includes Moonshine, Needle3, Kokoro/voices and phonemizer/tokenizer files. Qwen and Whistle are excluded. All **91 prepared, speech-only Kokoro prompts** retain the same fixed speaker and output-level processing. No Mac voice server or cloud STT/LLM/TTS is used. Model downloads happen only when preparing the build. Older model versions can remain in private device caches after an upgrade; fresh-install model bytes are not a measurement of total upgraded-device storage.

The preceding 0.2.0 native Android test in airplane mode passed five paced speech cases (noisy S1, reading fragment, spelled asset, short “No”, negated result), two structured paraphrase cases and silence/readiness checks. The two Qwen extractions took **1502 ms and 646 ms** on the single-core 4 GB emulator; these are synthetic extraction timings, not live end-to-end phone timings. See `fixtures/voice/benchmarks/moonshine-android-offline-20261023.json` and `moonshine-host-streaming-20261023.json` for that baseline. CPU thread count is bounded by the cores actually available, up to four, to avoid oversubscription. Android bundles CPU modules and excludes unused Vulkan and validation libraries. The model package identity is kept short to fit the iOS phonemizer path limit.

Offline first launch, capture, form filling, saving and queued submission use the bundled verified template and the existing signed demo entitlement. That entitlement expires on **25 October 2026 at 19:22 IST**; renew through the ordinary connected **Profile → Offline readiness → Sync & repair package** flow. Signature, expiry, clock and ownership checks are preserved. A connection is required to deliver confirmed submissions to the dashboard, where they appear under **Submissions → Visit summaries** (`/submissions?view=visits`). A local confirmation remains labelled **Waiting to sync** until a genuine server receipt arrives.

To reproduce the offline voice bundle from pinned sources, run `python3 scripts/provision-moonshine.py`, then `python3 scripts/repack-offline-voice.py`. For a newly authenticated signed account snapshot, use `node_modules/.bin/tsx scripts/prepare-offline-demo.ts`. These commands preserve entitlement checks and verify file hashes; generated binaries, weights, private defines and snapshots stay ignored. Android packages use an isolated Moonshine ONNX runtime dependency because its ELF version requirement differs from the existing speech-output runtime. The reproducible dependency rename and hashes are recorded in `fixtures/voice/moonshine-sources.lock.json`.

For S1, deliberately omit asset reference and follow-up:

> I installed the ONT in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two dBm. The service test passed. The job is fully completed. I showed the customer the equipment.

After **Anything else?**, say **That's everything** or **No**. Only **asset reference** and **next action** should remain. Say **CBT-SYN-10**, then **No further work required**, review the populated fields and submit. Use airplane mode to check local behaviour, then reconnect for dashboard delivery. Synthetic native replay checks do not replace testing the phone microphone with the presenter's voice and site noise.

## Historical offline demo — version 0.1.4

The historical 0.1.4 APK was approximately **344 MB**, ARM64, Android 12 / API 31 or later, version code 2005. It contained 210,201,890 bytes of model data across 362 verified files. Earlier measurements and checks below describe that implementation; the APKs are superseded by 0.2.2 and removed from generated build artifacts.

First launch uses the bundled package without login, provisioning or model-download requests. Models are copied to the normal local voice directory and verified against the same SHA-256 manifest as online provisioning. Existing encrypted drafts and queued confirmations are retained on upgrade. Ordinary accounts and release/profile authentication remain unchanged. The synthetic bundled device record is labelled as a demo fixture; it is not a hardware identity claim.

The server's existing signed offline-access window still applies. This prepared package expires on **25 October 2026 at 19:22 IST**. Use Profile → Offline readiness → Sync & repair package while connected to renew access. Expired bundled access falls back to the ordinary configured demo sign-in when online; the recovery screen also offers **Dashboard connection**. Never extend access by bypassing signature, expiry, device binding or the device-clock checks.

Submitting while offline shows **Saved on this device · Waiting to sync**, without a fabricated server receipt. The encrypted outbox retains each confirmed revision separately, survives reopening, retries transient failures with bounded backoff while the app is open, and displays non-retryable errors for review. New edits do not discard older confirmations. Reports lists these summaries alongside the separate operational drafts. Full policy-validated closure is unchanged.

### Reliability update

Saving and human-confirmed submission both work on-device while the installed offline package and signed access are valid. A server connection is needed for dashboard delivery. **Reports → Drafts** shows saved compact answers and their count. **Submitted on device · Waiting to sync** is a confirmed local submission, with its own device confirmation reference. The separate receipt screen displays the immutable submitted values; tapping a submission in Reports opens that receipt. Submission removes the review/form routes, and Android Back or Done from the summary receipt returns to My jobs. Reopening an already confirmed full report opens its receipt. Empty operational job-context shells are hidden when the compact summary already represents that draft; actual full-checklist answers remain visible separately.

The normal visit flow is **Check in → fill report → submit locally → check out**. Offline queued confirmation counts for checkout; dashboard acceptance is not needed before leaving. If a report has not been submitted for the current visit, **Check out with reason** explicitly records early departure. A report can still be completed after leaving. Check-in remains optional in this synthetic demo, and these departure prompts are proposed app behaviour rather than Openreach policy. Dialog controllers now live until the dialog is removed, with location and settings failures displayed inline. Reports and compact answers are also restored during offline package setup before the ready screen is published.

Voice capture uses the same raw PCM, delivered in 20 ms portions so meter frames have distinct elapsed times. A calibrated ambient-noise floor stops steady background noise from holding a focused answer open indefinitely. Opening words are retained, and release thresholds are independent of loud speech peaks. No PCM denoising or new model is added by the endpoint detector. The voice screen's **Reduce background noise** icon optionally requests native echo cancellation/noise suppression with gain held fixed; device support and microphone quality vary. Switching it restarts the active question and keeps saved answers. The default remains raw capture because some device effects attenuate quiet words.

Short spoken answers are admitted after 80 ms of detected voice activity in the adaptive capture path; a brief yes/no response is no longer discarded by the former 180 ms gate. A three-second no-audio watchdog detects a stalled microphone. Consecutive empty or unmatchable answers pause with a visible recovery message rather than repeating indefinitely. Recognition has a 15-second timeout and ignores late results. Focused select/numeric answers are capped at 12 seconds, long-text answers at 30 seconds and the opening narrative at 60 seconds. A failure while starting the next question cannot relabel an already durable answer as a save failure, and an unclear retry cannot erase a previously valid answer.

The 0.1.4 summary revision maps explicit details from **every spoken response**, including a complete summary given after an individual question or on resuming. Opening voice also extracts missing fields from an older saved work summary, without replacing existing answers or immutable confirmations. Silent, empty or common noise-only opening decodes move to guided questions; they do not save an empty summary or trigger **Anything else?**. That prompt follows a successfully saved, nonempty summary.

The latest scoped run passed **143 unit/widget tests**, including the exact S1 paragraph at opening, after silence/empty/noise recognition, on resume and from an older saved summary. Analysis is clean. A separate native synthetic replay transcribed the exact paragraph and populated work, outcome, optical reading and test result, leaving only asset and follow-up missing. See `fixtures/voice/benchmarks/s1-summary-simulator-20261023.json`. Physical-phone microphone behaviour still needs user testing.

The reliability revision passed 168 distinct scoped unit/widget tests and Flutter analysis with no issues. Pending draft writes continue when navigating to Reports, while workspace ownership checks remain in force. The scoped regression checks include Android-style check-in dialogs, denied location, settings failure, early departure, offline draft restoration, immutable receipt navigation, stalled capture/recognition and post-save native cleanup failure. The native diagnostic additionally passed four Kokoro-generated utterances mixed with deterministic 100 Hz hum and broadband noise, including a negated test and a signed optical reading. See `fixtures/voice/benchmarks/noisy-simulator-20261023.json`. This is a simulator diagnostic, not a live-microphone, field-noise, accent or physical Android accuracy guarantee.

Dashboard delivery needs a reachable server. Configure **Profile → Demo dashboard connection** (default `http://192.168.1.9:3002`). The phone and Mac can use a shared local Wi-Fi network; Internet access is not needed for phone-side voice/forms or a local dashboard server. Find delivered summaries at `http://localhost:3002/submissions?view=visits`.

To regenerate the ignored offline assets from the authorised synthetic account and existing verified model files, run `node_modules/.bin/tsx scripts/prepare-offline-demo.ts` from the repository root before the Flutter build. The private demo define files enable `DEMO_AUTO_LOGIN` and `DEMO_BUNDLED_OFFLINE`; keep them and generated assets out of version control.

The clean-simulator native check rejected every network request. It verified first-launch signed access, all seven jobs, local STT/TTS, the six-sentence S1 rehearsal yielding exactly two missing fields, SQLCipher storage, and unchanged queued payload/identifier after encrypted reopen. Unit/widget checks cover waiting and received states, concurrent confirmations, legacy receipt migration, offline repair of corrupted model files, and safe account-switch fencing. Physical Android microphone/speaker testing remains the presenter's check.

S1 rehearsal (intentionally omit asset reference and next action):

> I installed the ONT in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two dBm. The service test passed. The job is fully completed. I showed the customer the equipment.

After **Anything else?**, say **That's everything**. Answer the two follow-ups with **CBT-SYN-10** and **No further work required**, then review and submit.

The FTTP closure assistant uses one on-device voice route. Recognition, answer interpretation, conditional questions and engineer confirmation stay on the phone. A spoken response never submits a report. Unknown answers remain unanswered, and completing an upstream stage never marks customer service live.

The default demo has **six fields**: work done, visit outcome, asset reference, optical reading, test result and follow-up. Job details remain in the header. **Fill with voice AI** opens the full-screen animated conversation; **Fill manually** edits those same six fields. A spoken summary can populate several fields, and the bot asks only for remaining gaps in this short form. A clear spoken answer or selected option saves and advances automatically. There is no Ask, Finish or per-question confirmation step.

**Review 6-field summary** opens human review. For a completed outcome, **Complete visit & submit** durably queues the six answers and source text in encrypted storage; other outcomes show **Submit visit summary**. It sends them when the server is reachable and the app is open; a server receipt alone marks delivery. **Done** opens **My jobs → Completed** for completed visits, or Active jobs for outstanding work, and removes the form/review routes from the back stack. Completed visits show **Visit completed** and their actual sync status; **Approved & completed** remains the separate supervisor-approved status. Old summaries cannot complete a later assignment revision or a job reopened by a newer supervisor follow-up. Queued confirmations are immutable, and a retry reuses the same payload and identifier. This does not approve operational closure or change the full draft's values. **Open full closure checks** opens the existing complete workflow separately. Existing frozen reports retain their original review. The short form does not hide mandatory operational gates behind its six-field review.

Selectable voice answers accept displayed labels, natural explicit sentences such as **The work is fully completed** / **The service test passed**, and ordinal choices such as **option two**. Whole-answer matching preserves negation and qualifications: **not fully completed**, **probably passed**, and conflicting alternatives stay unresolved and prompt clarification. Check-in remains an optional site-time action in this synthetic demo, visible on the report before starting or resuming voice. A previously recorded arrival is reused; no check-in is generated from opening a report.

**Reset answers** is available on the completed six-field voice screen and on the visit-summary form. The confirmation clears that summary’s answers, source transcripts and reviewed status. Cancelling keeps them. A successful reset from the voice screen starts a fresh greeting automatically; resetting from the form leaves it ready for **Fill with voice AI**. The explicit empty snapshot survives reopening, while the job, full operational draft and closure checks stay intact. A failed write restores the prior summary and allows retry.

Narrative suggestions remain labelled candidates until the final human closure review. Direct speech and selected options retain their original source type. Unclear speech remains unanswered and gets a spoken follow-up; **Not measured** never becomes a fabricated reading. Say **repeat**, **skip**, **pause**, **resume**, **retry** after a failed save, or **open draft**. A spoken pause keeps a foreground microphone open for resume/open draft only; system interruptions stop capture. Reduce-motion settings stop the animation. Late recognition or extraction cannot fill a field after pause, selection or closing.

Offline mode currently plays 91 prepared speech-only Kokoro prompts (79 field questions plus 12 conversation prompts), with an exact text match and checked audio hash. All prompts use the same `bm_george` speaker, ID 9 in the pinned English v0.19 model, at speed 1.05. Live fallback uses that same model, speaker and rate. The former VibeVoice pack is archived outside the app. No music or reference recording is supplied to this generator. Numeric answers remain visible in the draft. The compact conversation moves directly to the next missing question without an extra acknowledgement. The app levels speech within clips, targets active speech RMS of 0.10 and soft-limits peaks to 0.75. These settings measure digital playback, not subjective attentiveness, phone volume or LUFS. A 0.5B VibeVoice model is **not running on the handset**. Recognition and extraction weights total about 52 MB before their runtime; Kokoro and application assets are additional.

Direct on-device TTS is the proposed next voice route, rather than the current primary route. It would allow changing questions and answer readbacks without bundling a matching clip. A fixed speaker and rate, short prompts, model warm-up and a temporary in-memory cache are recommended. Switching to live synthesis alone does not improve delivery; physical-phone synthesis latency and listening acceptance remain unmeasured. Do not promise an instant response from the exploratory Mac results.

The Mac premium selector and remote question-speech client have been removed. No speech server or speech-service token is needed by the mobile app. The Mac scripts remain preparation and comparison tools for generating the bundled recordings.

See [mobile storage and hardware sizing](mobile-footprint.md) for the STT, extraction and TTS breakdown, build measurements and device recommendations.

## Response time in the six-field conversation

The short demo maps explicitly stated narrative facts immediately and retains the original speech transcript. It no longer waits for up to four serial model-enrichment calls. Unknown details become direct follow-up questions; a measurement, test result or outcome is never inferred to save time. The full closure workflow retains optional model enrichment and all operational gates.

Focused answers finish after 700 ms of detected silence; the opening narrative allows 1100 ms. Before recognition, outer silence is trimmed with a lower threshold than endpoint detection, preserving 240 ms around speech and all internal pauses. Prepared prompts are cached in bounded RAM after integrity checking and playback levelling. Closure startup no longer queues live background synthesis on the serial recognition worker. After a durable save the short demo goes straight to the next question, while final completion remains spoken. None of these changes bypass storage failure handling or final review.

`integration_test/voice_latency_test.dart` measures native recognition with padded and trimmed generated speech in both orders, and cold/cached prompt preparation. Its output is a simulator debug diagnostic, not a physical-phone or live-microphone response-time promise. The current generated negative-reading replay measured recognition at 71–188 ms across four runs, checked the signed value on every run, and measured 33 ms for cold prepared-prompt loading and 0 ms for its cached repeat. These timings exclude endpoint waiting, access checks, saving and playback. Exact scope and samples are in `fixtures/voice/benchmarks/simulator-response-time.json`; they do not establish that trimming always improves inference time.

## What was tested

See `fixtures/voice/benchmarks/voice-model-evaluation.json` for measurements and exact source revisions. The runtime is pinned in `scripts/requirements-voice-demo.txt`.

On this Apple M2 Pro, 16 GB Mac, five shared synthetic prompts were tested with Kokoro and VibeVoice, including a measurement, a permission hold and an upstream-stage handover. VibeVoice was also tested with shorter diffusion and complete-utterance settings. Ming-3.0 TTS 0.5B completed one cold sample: about 105 seconds to generate 5.4 seconds of speech. Its remaining run was interrupted; this does not establish its warm performance or performance on another GPU.

VibeVoice's standard streaming profile produced a warm median first PCM buffer near 292 ms, but a warm median real-time factor of 2.155. The shorter diffusion profile reached 1.092 across two warm samples. Below one is required to sustain audio without accumulating a buffer. A CFG=1 experiment failed to stop and hit its generation limit; its apparently faster RTF was rejected. Those earlier comparisons motivated prepared questions for immediate playback. The current speech-only pack uses Kokoro with the same profile as local fallback. It does not claim live 300 ms end-to-end conversation on a phone.

These are exploratory local runs with the development workspace active, not controlled device comparisons or human-speech accuracy scores. The generated samples can be auditioned at **http://127.0.0.1:8044** while the listening server is running. That page plays saved recordings. Numeric quantities, abbreviations, negation and consent still require engineer review. The synthetic speech-to-ASR roundtrip is a diagnostic, not evidence of accuracy across engineer accents, background noise or microphones.

## Prepare and run

Use an isolated Python environment on Apple Silicon. The existing local setup is `.local/voice-lab/.venv`.

```sh
python3 -m venv .local/voice-lab/.venv
.local/voice-lab/.venv/bin/python -m pip install --no-compile -r scripts/requirements-voice-demo.txt
.local/toolchain/flutter/bin/cache/dart-sdk/bin/dart --packages=apps/mobile/.dart_tool/package_config.json scripts/export-closure-prompts.dart
.local/voice-lab/.venv/bin/python scripts/prepare-attentive-voice.py
```

The speech-only generator verifies the local Kokoro files against `fixtures/voice/asset-manifest.json`, uses the archive pin in `fixtures/voice/model-sources.lock.json`, and reads the speaker profile exported from the Dart constants. Earlier VibeVoice/Ming comparison source pins remain in ignored `*-source.json` files. A question pack is generated from the same Dart function used by the conversation, including clear spoken acronyms and distinct stage outcomes. A changed question cannot reuse an old recording. The app validates the WAV format, exact prompt and SHA-256 before playback.

For sign-in, provisioning and report sync, use a trusted shared Wi-Fi network for the Mac API and phones. `.local/mobile-config.json` targets the simulator; `.local/mobile-phone-config.json` targets the Mac's Wi-Fi address. Both are ignored private build configurations. They contain the API address, local transport flag and entitlement verification key. Refresh the API address if the Mac changes networks. Voice works on the phone after offline readiness.

The presentation API uses port 3002 and must listen on the Mac's network interface for physical phones. No public hosting or tunnel is needed.

## Demo entry without authentication prompts

The debug demo build opens the configured synthetic engineer account automatically, skips app-level device authentication, and remains open when backgrounded. Its existing encrypted reports, signed entitlement and server-side authorisation stay in use. It only auto-opens the configured `@fieldassist.demo` account; another saved account is never automatically unlocked. Normal, profile and release builds retain ordinary sign-in and presence checks.

Private, ignored configuration files hold `DEMO_AUTO_LOGIN`, `DEMO_ENGINEER_EMAIL` and `DEMO_ENGINEER_PASSWORD`. Use `.local/mobile-demo-config.json` for this simulator and `.local/mobile-phone-demo-config.json` for phones on the configured Mac network. Never commit these files or reuse the demonstration credentials for production. Run the simulator from `apps/mobile` with:

```sh
../../.local/toolchain/flutter/bin/flutter run --debug --dart-define-from-file=../../.local/mobile-demo-config.json
```

Startup restores the configured account’s valid offline workspace directly. A fresh installation signs in and provisions that demo account automatically. If restoration fails or its entitlement expires, it attempts the configured demo sign-in; a setup failure shows **Open demo** for retry without credential fields. In builds with `DEMO_BUNDLED_OFFLINE=true`, a first installation prepares its synthetic jobs and models from the APK without a server connection. Ordinary builds retain online first provisioning.

## Rehearse on the phone

1. The debug demo opens automatically. In a normal build, sign in as **closure@fieldassist.demo / 123456**. Download the assigned forms, jobs and voice package, then complete Profile → Offline readiness. Allow the initial warm-up to finish before the client arrives.
2. Open an assigned FTTP visit and tap **Fill with voice AI**. The full-screen assistant greets you and speaks before opening the microphone. Describe the visit, tests and outstanding work; pause when finished.
3. After the engineer’s opening summary, the assistant maps and saves the recognised summary, then says **Anything else?**. If no opening summary is heard, it says **Let me ask you the details one at a time**, then starts the guided questions. Add more details, say **that’s everything** / **nothing else**, or leave three seconds of silence. It combines the summary turns, keeps their source text, and asks only the missing questions. Answer aloud or tap one option beneath the question. Either route saves and advances automatically. Measurements and free text have optional typed input; the voice route needs no taps between questions.
4. Try a spoken negative, an uncertain answer and **repeat**, **skip**, **pause**, **resume**. Uncertain speech never becomes a negative or a passing test. A skipped required field remains missing in final review. A failed save is not acknowledged as saved; say **retry** to try again.
5. When the questions finish, the voice session closes automatically and opens **Review visit summary**. Inspect the six answers, then choose **Complete visit & submit** for a completed outcome, or **Submit visit summary** for outstanding work. **Done** returns to My jobs and shows completed visits in the Completed tab. A receipt confirms server acceptance. The dashboard shows it under **Submissions → Visit summaries** (`http://localhost:3002/submissions?view=visits`), including the engineer’s source text. If offline, the answers and confirmed submission stay encrypted on the device. Reconnect and reopen the app for automatic foreground retries, or use Reports → Sync. Reports shows waiting summaries, delivery errors and actual server receipts. A retry of an unchanged reviewed payload returns the same receipt. This summary does not close the work order. For operational closure, use **Open full closure checks** and its separate policy and evidence review.

For the current bundled offline demonstration, install the updated APK and let its local package prepare. The first launch, questions, speech recognition and confirmed-summary queue work without a server connection. The form's conditions choose the next question; the assistant does not manufacture safety clearance, consent or a passing test.

## Platform checks

The project targets iOS 18 or later and Android 12 or later on arm64. Physical microphone, speaker, Bluetooth and noisy-site testing remains required on the actual presentation phones. The simulator verifies app behaviour, not field audio quality.

Android demonstration builds use the existing debug-only local HTTP allowance. Release builds retain their transport configuration. iPhone installation requires an Apple development team and provisioning in Xcode; none is selected in this checkout. Simulator builds do not require a signing team. Do not describe an unsigned iPhone build or an untested APK as a verified physical-device demonstration.

Build from `apps/mobile` with the private phone configuration:

```sh
../../.local/toolchain/flutter/bin/flutter build apk --debug --split-per-abi --target-platform android-arm64 --build-name=0.1.4 --build-number=5 --dart-define-from-file=../../.local/mobile-phone-demo-config.json
../../.local/toolchain/flutter/bin/flutter build ios --debug --no-codesign --dart-define-from-file=../../.local/mobile-phone-demo-config.json
```

On this Mac, Android uses `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home` and `ANDROID_HOME=$HOME/Library/Android/sdk`. iOS uses `RUBYOPT=-rlogger` and the CocoaPods PATH described in the closure guide. The APK is a development demo build for the configured Mac network. The unsigned `build/ios/iphoneos/Runner.app` verifies compilation; it cannot be installed on an iPhone until signed. Open `ios/Runner.xcworkspace`, choose the agreed development team under Runner → Signing & Capabilities, and use `flutter run -d DEVICE_ID --dart-define-from-file=../../.local/mobile-phone-demo-config.json` for the signed device run. Keep the private configuration and the generated binaries out of version control.

Before the visit, check one turn on each phone: speaker playback completes before microphone capture, a spoken negative stays negative, a measurement preserves its sign and is visible in the draft, a spoken pause accepts only control commands, and airplane mode still plays the prepared questions after offline readiness. Reconnect before demonstrating a server acceptance receipt.

Run `flutter analyze`, the closure, voice-turn and question-audio tests, the native encrypted-storage check, and the five-scenario API verification before rehearsal. The broader repository's seven known baseline Flutter interaction-test failures remain separately documented in the closure runbook.

## Verified in this workspace

The 23 October visit-quality revision passed **124 distinct scoped unit/widget tests** across speech matching, automatic advancement, compact/full closure, durable outbox storage, jobs, time tracking and navigation. Flutter analysis is clean. Completed visits remain visible after reopening with either waiting or received delivery state; a new assignment or later supervisor follow-up prevents an old summary from completing the job. The compact check-in panel keeps the voice action above the review footer on a 390 × 844 logical-pixel phone. A native iPhone simulator diagnostic passed ten generated Kokoro → Whistle → selectable-answer cases, including explicit negatives that remain unresolved. This diagnostic does not establish live microphone, accent, field noise or physical-phone performance. The regular app was rebuilt and opened in the existing iPhone simulator, and the current Android APK's 362 model-file hashes and 90 prompt hashes were checked after packaging.

The older Android APK and unsigned release sizing artifacts below predate the six-field summary and consistent-voice revision; they are historical measurements. Use the current 0.1.4 artifact above for phone testing. Physical-phone listening checks are still required.

The earlier signed Android ARM64 debug demo is `.local/demo-builds/field-assist-closure-demo.apk` (218,504,473 bytes, 218.5 MB). Its `.apk.sha256` and `android-build.json` sit beside it. All 88 prepared recordings match their embedded hashes, and only ARM64 native libraries are packaged. With the presentation phone connected and USB debugging authorised, install from the repository root with `adb install -r .local/demo-builds/field-assist-closure-demo.apk`.

The unsigned Android ARM64 release sizing APK and unsigned iOS ARM64 release bundle also compiled successfully. The iOS bundle contains the same 88 verified recordings. These builds do not establish phone installation/signing or physical microphone/speaker acceptance. See [the measured footprint](mobile-footprint.md) for exact build scope and sizes.

Before the fixed-speaker Kokoro revision, the scoped Flutter run passed **89 tests**, including playback levelling across all 88 prompts, peak protection, the six-field voice journey, local summary review/recovery, preserved full closure policy, both voice and selected-option automatic advancement, retained provenance, negation/uncertainty handling, interrupted recognition and failed-save retry. The final analyser reported no issues. Two iPhone simulator integration tests passed: encrypted closure recovery, and prepared VibeVoice playback → native Whistle recognition → automatic draft advancement without taps, followed by an optional selected answer that also advances automatically. The voice fixture supplies generated speech and never records a microphone. The pack test verifies all 88 prepared recordings, including the short acknowledgement. The quality pass also covers summary playback, keyboard layout, spoken Not measured, stale ASR after selection and an interruption during saving. All five scenario API checks passed again with manual-option source trace; the production web build passed earlier. The broader repository's known baseline interaction failures remain outside these scoped passing checks.

The fixed-speaker Kokoro source revision passed **90 scoped Flutter tests** and analysis with no issues. This includes all 88 exact-text/hash checks, matching the live fallback profile, rejection of the old voice pack, and playback-level checks. These checks do not establish phone synthesis latency or listening quality.

## Consistent voice playback

The original VibeVoice recordings varied by about 11 dB in active-frame RMS; their report is archived as `fixtures/voice/benchmarks/voice-output-levels-vibevoice.json`. The playback-level check covers all 88 current Kokoro recordings, with the before/after measurements in `fixtures/voice/benchmarks/voice-output-levels.json`. This measures PCM level and peak protection, rather than subjective naturalness or phone speaker output. The six-field journey test also asserts that normal bot speech uses prepared recordings throughout, including completion. Microphone PCM and the user’s device-volume setting are unchanged.

The response-time revision passed **94 scoped Flutter tests**, analysis with no issues, and **three native iPhone simulator checks**: synthetic latency/negative-reading replay, encrypted closure recovery, and automatic spoken/selected-answer advancement without per-question acknowledgements. Physical microphone and phone checks remain outstanding.

A separate current-build baseline in `integration_test/voice_turn_gap_test.dart` feeds generated PCM in real time through the production meter and assistant, verifies ES256 entitlement checks with isolated Keychain keys, writes the answer to SQLCipher, and waits for the first nonzero native playback-meter frame of the next question. One replay measured **1044 ms** from the final voiced input frame to that output indication, including **39 ms** of recognition, seven access checks at **8–55 ms** each, and **2 ms** of encrypted saving. `fixtures/voice/benchmarks/simulator-turn-gap-baseline.json` records the sample and scope. This excludes real microphone-driver and acoustic output latency, does not reproduce the reported long live-input pause, and is not a general response-time guarantee. No additional voice settings changed in this baseline check.

For the current five-field journey, see [the full-app speech-to-speech timing report](speech-to-speech-latency.md). Its 30 iOS simulator turns (25 primary plus five harness-validation turns) use the production compact screen/controller and a native voiced playback cursor, with controlled real-time PCM in place of a microphone. Medians are approximately 1.2 s for routine short answers and 2.4 s for summaries/additions. The corrected-reading clarification path has an approximately 11.3 s median (observed 11–14 s) and leaves the reading unfilled in these replays. The report retains that result, the raw samples and the post-run harness-check limitation; the subsequent five-turn harness validation passed. These are software measurements on a simulator, not acoustic physical-phone timings; the earlier 0.45 s STT result is not full conversational latency.

The summary-reset revision passed **96 scoped Flutter tests** and analysis with no issues. Checks cover cancellation, clearing/restarting the completed voice journey, rejection of late recognition after a reset, empty-summary recovery, preservation of the full operational draft, and restoration/retry when writing a reset fails.

The demo-entry revision passed **142 scoped Flutter tests**, including normal authentication, account isolation, expired-restore recovery, automatic entry, device-presence configuration, and background behaviour. Simulator launch verification is recorded separately from these unit/widget checks.


## Earlier online-setup summary demo — 22 October 2026

The updated ARM64 Android debug APK is `.local/demo-builds/field-assist-voice-summary-demo-arm64.apk` (218,548,809 bytes, approximately 219 MB). The adjacent `.apk.sha256` and `.json` record the checksum and build scope. APK Signature Scheme v2 verifies; Android 12 / API 31 is the minimum. This build auto-opens the synthetic demo account and points to `http://192.168.1.9:3002/api/v1/`. Keep the phone and Mac on the same Wi-Fi for first setup and submission. The separate offline model download totals 210,201,890 bytes; it is not embedded in the APK. The APK contains all 90 verified, speech-only Kokoro prompts using the fixed `bm_george` voice.

The current compact summary uses local, source-grounded phrase and number mapping after Whistle recognition. It does not wait for serial Needle3 enrichment calls. Unsupported paraphrases, conflicting measurements and uncertain statements lead to follow-up questions. No claim is made that this parser understands every possible narrative or that six fields satisfy Openreach operational closure policy.

A new native simulator test synthesised a seven-sentence, approximately 16-second report and recognised it with Whistle. The punctuation-free result retained “minus 18.2”, the work, completed outcome, passed test and explicit follow-up. An absent asset identifier remained unanswered. One replay measured 912 ms for recognition; this is synthetic audio, excludes microphone capture and playback delays, and is not a live end-to-end latency guarantee. Physical Android and iPhone microphone/speaker testing remains to be done.

Real API and browser checks verified reviewed summary submission, stable retry receipts, conflict rejection, list/detail display, per-engineer and organisation isolation, and unchanged operational report/work-order state. Test data used temporary synthetic accounts and was removed after verification.

Final scoped checks passed: **152 Flutter tests**, **3 visit-summary contract tests**, the native seven-sentence recognition test, real API/browser submission checks, Flutter analysis with no issues, and the production dashboard build.
