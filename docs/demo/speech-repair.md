# Offline correction and auto-fill update — 25 October 2026

The app continues using Moonshine Small Streaming English 0.1.5. No speech-model
weights were changed or fine-tuned in this update. The changes interpret explicit
spoken corrections locally, after transcription and before form mapping.

## Resulting behavior

- “Hello I'm Waseem from local, sorry I stay here, sorry I'm Waseem from
  Bangalore” resolves to “I'm Waseem from Bangalore.”
- “The reading is 18.2, no no sorry the readings is -18.19” resolves to **-18.19**.
  Bare corrections also work while answering the optical-reading question.
- “Optical received measurement” maps to the receive-reading field. Decimal
  groups such as “point nineteen” are accepted alongside “point one nine.”
- Conflicting values without an explicit repair, such as “8.2 dBm was -8.2 dBm,”
  remain unanswered. A minus sign is never supplied from an expected range.
- The compact form can establish dBm for an explicitly labelled, unitless reading
  because it has exactly one numeric measurement field. An explicit dB instead
  of dBm still requires unit confirmation. Other numeric fields are not inferred.
- Additions after “anything else” retain the original summary, replace a clearly
  corrected reading, fill newly supplied fields and proceed only to remaining
  missing/invalid fields. The bot does not treat an interim “No…” as a completed
  addition after a short 450 ms pause. Pending correction/decimal cues get extra
  speaking time.
- Recognized text is not discarded solely because a speech-activity flag is
  absent. Streaming finalization gets an opportunity to capture the last words;
  initial silence still starts guided questions instead of asking “anything else.”

The displayed Work done answer uses the resolved wording. Original speech,
discarded/replacement phrases and corrected source spans remain in local
provenance and submitted source evidence. Manual answers remain protected.
An invalid replacement cannot silently leave the old inferred reading in place.
Qualitative extraction also receives the resolved text and grounds evidence back
to the original transcript.

The correction resolver handles explicit supported restarts. It is not a new
general language model and cannot reconstruct words or numbers the recognizer
did not hear correctly. Unsupported or unclear statements still need a question
or engineer review. The bot does not submit on its own.

## Validation

136 relevant Flutter tests passed, covering corrections, raw-source retention,
reading ambiguity, narrative pauses, delayed additions, hesitant “No” responses,
missing-field selection, manual-value protection and submission flow. Flutter
analysis reported no issues. Four server-contract tests passed, including
retaining bounded correction provenance and rejecting unknown fields.

Three fresh synthetic audio clips passed through the actual local Moonshine
runtime and streaming capture on the Mac:

1. “18.2 dBm, no no sorry … -18.19 dBm” produced **-18.19** in the form.
2. “Optical received measurement … -17.8 dBm” produced **-17.8**.
3. An additional asset/follow-up response beginning after 4.5 seconds of silence
   retained both the asset reference and next action.

The frozen Moonshine transcripts from each earlier simulator comparison now
produce 17 correct readings, one explicit clarification and four correctly
absent readings. The formerly accepted conflicting +8.2 proposal is now missing,
so the bot must ask for the measurement. The historical A/B report remains
unchanged; these are new parser results, not a new STT accuracy claim.

Local API/browser checks verified corrected values and raw speech evidence in
the dashboard, stable retry receipts, conflict rejection, engineer/organisation
isolation and unchanged operational closure. Temporary synthetic test accounts
and records were cleaned up. These checks are not real engineer microphone or
physical phone testing.

## Test build and training preparation

The Android test artifact is `.local/demo-builds/field-assist-demo-v0.3.1-arm64.apk`,
version **0.3.1**, build 19, Android split version code 2019. It remains an ARM64
debug demo with the existing offline model bundle. APK contents/model checksums
and v2 signing verify; installation over the previous Android emulator app
preserves its data. The superseded 0.3.0 APK was removed after verification.
Adjacent JSON and SHA-256 files identify the delivered binary.

The [Indian/UK English training setup](moonshine-training.md) contains a 72-script
recording pack and speaker/session-disjoint dataset preparation. It is prepared,
not trained: verified real audio and a CUDA training trial are still required.
Training tools do not modify the current model package or app authentication.

Evidence: [synthetic native replays and validation record](../../fixtures/voice/benchmarks/speech-repair-20261025.json).
