# Phonon-2.5 English versus Moonshine Small Streaming

25 October 2026. Local synthetic comparison; simulators only.

## Recommendation

Keep **Moonshine Small Streaming for the current demo**, and fix the extraction
and conversation flow before replacing STT. **Unbiased Phonon-2.5 English is a
promising candidate for the next hardware trial**, especially for preserving
optical readings. These tests do not establish that it is the better production
choice for both phones.

Phonon preserved all 18 numeric receive readings in the transcripts, compared
with 17 for Moonshine. However, both produced only 17 correct reading candidates
through the current form parser. Moonshine also finalized sooner after speech
ended, because it processes speech as it arrives. Phonon's faster processing of
an already complete clip did not produce a faster conversational response.

Defer fine-tuning until we have real engineer recordings and a held-out test
set. First fix the demonstrated parser gap, reject conflicting measurements,
and verify that additional speech after “anything else” enters the same saved
summary. The latter is a conversation-flow check, not something these isolated
recognizer tests establish.

No Flutter provider, model package, entitlement, report or APK was changed by
this comparison. The existing demo continues using Moonshine.

## Accuracy

31 distinct synthetic clips, 423 normalized reference words, two synthetic
voices. Accuracy below uses the first pass; the second pass supplies additional
timings and a repeatability check. Repeated audio is not counted as additional
independent accuracy evidence.

| Runtime | Recognizer | Normalized WER | Exact signed dBm reading in transcript | Correct reading candidate in form |
| --- | --- | ---: | ---: | ---: |
| iOS simulator | Moonshine, existing app hints | 4.02% | 17/18 | 17/18 |
| iOS simulator, experimental port | Phonon, no hints | 3.31% | 18/18 | 17/18 |
| Android ARM64 emulator | Moonshine, existing app hints | 4.02% | 17/18 | 17/18 |
| Android ARM64 emulator | Phonon, no hints | 3.07% | 18/18 | 17/18 |

All four configurations retained all 36 checked engineering-term occurrences
and all three asset references after the shared asset normalizer. They left
the receive-reading field empty in all four “not measured” or splice-loss-only
controls. The noise-only control produced empty text. Each configuration
matched 42/43 expected form-field checks. All 31 second-pass transcripts matched
their respective first-pass transcripts within each platform/configuration.

Phonon with the same vocabulary list at bias strength 2.0 was tested separately.
It scored 3.07% normalized WER on both platforms but preserved only 17/18 signed
readings. A lower WER did not mean better preservation of critical numbers.
The two engines' numeric hint-strength settings have different semantics.

### Three failures that explain the recommendation

| Configuration and case | Recognized text | Consequence |
| --- | --- | --- |
| Moonshine, `rx-08-v0` | “Optical receive reading 8.2 dBm was -8.2 dBm.” | Conflicting values. The raw parser proposed +8.2; this is not evidence that a wrong value was submitted. Validation and engineer confirmation occur later. |
| Unbiased Phonon, `rx-178-v9` | “The optical received measurement was minus 17.8 dBm.” | The number and unit were correct, but the existing parser did not recognize the context phrase and left the field missing. |
| Hinted Phonon, `rx-191-v0` | “The optical receive reading was 19.1 dBm.” | The minus sign was lost. Never silently restore a sign from an expected operating range. |

The unbiased Phonon result demonstrates an extraction defect independently of
STT accuracy. The current compact parser is scored before form validation and
engineer confirmation. Needle3 only enriches eligible qualitative gaps in the
app; it does not supply missing measurements. No extraction model or parser was
changed to improve one recognizer's ranking during this experiment.

## Response time after speech

These controlled replays use known fixture endpoints and identical pause
allowances. Moonshine receives 320 ms chunks in real time; Phonon runs on the
completed utterance. Times include the specified pause allowance and recognition
finalization, but **exclude microphone capture, natural VAD decisions,
extraction, TTS and playback**. They are not full voice-bot latency or physical
phone timings. The small sample is reported as a range rather than a latency
guarantee.

| Runtime | Recognizer | Short reading answer, 450 ms pause (2 clips) | S1 summary, 1.8 s pause (3 clips) |
| --- | --- | ---: | ---: |
| iOS simulator | Moonshine | 0.453–0.457 s | 1.805–1.807 s |
| iOS simulator, experimental port | Unbiased Phonon | 0.661–0.665 s | 2.491–2.796 s |
| Android ARM64 emulator | Moonshine | approximately 0.452 s | 1.808–1.810 s |
| Android ARM64 emulator | Unbiased Phonon | 0.795–0.804 s | 2.885–3.337 s |

Both recognizers preserved the reading in all three paced S1 summaries and both
short-answer clips on each platform. The three S1 variants include a clean
summary, synthetic noise and pauses between sentences. The fixtures intentionally
omit an asset identifier and explicit follow-on instruction; the recognizer
must not invent them.

For this workload, turn-end policy is a major part of the wait. Shortening it
blindly can cut off a six-sentence summary or an additional answer. Test narrative
capture and short guided answers separately, keep inference warm, and measure
the actual end-to-end app loop before claiming instant replies.

### Complete-clip processing, a different measurement

62 warm timed recognitions per configuration (31 clips, two passes), after an
excluded warm-up. P50/P95 use linear interpolation between sorted observations.
Moonshine runs the app's streaming schedule over the available audio, including
partial decoding; Phonon performs one complete-utterance inference. This is a
comparison of those execution paths, not interchangeable batch APIs.

| Runtime | Recognizer | Complete-clip P50 | Complete-clip P95 | Bulk process peak RSS |
| --- | --- | ---: | ---: | ---: |
| iOS simulator | Moonshine | 1.275 s | 5.165 s | 495 MiB |
| iOS simulator, experimental port | Unbiased Phonon | 0.186 s | 0.667 s | 747 MiB |
| Android ARM64 emulator | Moonshine | 2.767 s | 12.291 s | 482 MiB |
| Android ARM64 emulator | Unbiased Phonon | 0.331 s | 1.160 s | 704 MiB |

RSS is the isolated process high-water mark, including runtime, weights and
scratch buffers. It excludes Flutter, extraction, TTS and the rest of the app;
it cannot establish a minimum phone RAM requirement. Phonon uses two CPU threads.
Moonshine uses its published runtime default, matching the app's load options.
Neither model was tuned for these timings.

## Exact models and offline execution

Moonshine is the existing SDK 0.1.5 Small Streaming English model (123M), with
embedded Silero VAD and the app's engineering vocabulary list. Its eight weight,
configuration and tokenizer files total **142.30 MB**.

Phonon is [FermionResearch/Phonon-2.5-English](https://huggingface.co/FermionResearch/Phonon-2.5-English)
at revision `cea043a0a125d6535d473645ad5fa90847a6b001`, using the published packed
CPU encoder and TDT decoder. The download is **157.62 MB**, unpacking to
**177.76 MB**. The diagnostic's prepared tensors occupy **199.84 MB** because
support tensors are unpacked; this is not a predicted APK size. The original
packed encoder records and quantized decoder codes are preserved without
requantization. Numerical readings are never supplied as vocabulary hints.

The shared frontend was checked against the official `fermion-research==0.2.15`
Torch frontend on the same noisy S1 PCM: maximum absolute feature difference
`3.95e-5`, mean difference `3.41e-7`. The native S1 smoke transcript matched the
official CPU reference transcript. This is a smoke/parity check, not exhaustive
proof of equivalence on all audio.

Android uses the publisher's
[ARM64 native runtime 0.2.11](https://github.com/fermionresearch/phonon/releases/tag/android-arm64-v8a-0.2.11),
with CPU feature checks before choosing the optimized or base library tier.
All three Android phases ran with airplane mode on, Wi-Fi off and mobile data
off. Previous radio settings were restored after each phase. Checksums matched
for all 49 local/remote files consumed by the Android diagnostic.

**The exact Phonon-2.5 iOS result is experimental.** The published CoreML model
inspected was Phonon-2, a different model, so it was not substituted. For the
requested initial simulator comparison, copies of the pinned macOS ARM64 CPU
kernels had their Mach-O platform metadata changed to iOS Simulator and were
ad-hoc signed. Their instruction sections match the originals. This worked in
the simulator but is not a vendor-supported or qualified physical-iPhone build.
Do not package these experimental libraries into a shipping app.

Both native runners read staged models and PCM from local files. They have no
HTTP, socket or model-download code. The iOS simulator's host connectivity was
not disabled. No engineer recording, account or report was sent to a service.
This verifies isolated local inference, not a new offline production app flow.

The host was an Apple M2 Pro Mac with 10 CPU cores and 16 GiB RAM. The iOS runtime
was the iPhone 18 Pro simulator on iOS 27. Android used an API 37 ARM64 emulator
with two virtual cores and 3 GiB configured memory. These share the Mac's CPU;
their timing and memory results must not be presented as real-device performance.

## Next decision gate

1. Extend measurement-context recognition for the observed phrase, and detect
   contradictory values before proposing a field. Keep source evidence and ask
   for clarification rather than inferring sign, unit or test success.
2. Replay complete narratives and “anything else” additions through the actual
   conversation and submission flow. Confirm that only genuinely missing fields
   are asked and that captured additions persist into the submitted payload.
3. Compare both engines on real engineer recordings, including accents,
   background noise, clipped speech, spelled identifiers and corrections. Keep
   development and evaluation speakers separate. The small TTS corpus here is a
   regression screen, not real-world accuracy evidence.
4. Qualify the exact Phonon-2.5 runtime on physical Android and iPhone, measuring
   end-to-end delay, battery/thermal behavior, memory and package size. Switch
   only if it improves critical-field accuracy without harming the hands-free
   interaction. A supported iPhone runtime is still required.

## Evidence and reproduction

The comparison completed **392 recognitions**: 372 bulk runs and 20 paced runs.
Four scorer tests passed, Dart analysis found no issues, Python compilation
passed, and reference texts had no expected-field mismatches in the frozen
parser. The tests cover signed units, conflicting values, common ASR
orthography and timing percentiles. They do not replace live speech or full-app
acceptance testing.

- [Full synthetic results, corpus, timings, source hashes and run metadata](../../fixtures/voice/benchmarks/phonon-vs-moonshine-20261025.json)
- [Pinned Phonon artifacts](../../fixtures/voice/phonon-ab-sources.lock.json)
- [Reproduction instructions](../../scripts/stt-ab/README.md)

WER normalization is shared across engines: case, punctuation, spelled
acronyms, fibre/fiber and numeric orthography. Spoken “dash one zero” and a
hyphenated identifier can still differ in WER, which is why exact field metrics
are also reported. Results are descriptive; no significance claim is made from
423 synthetic reference words, and run order was not randomized.
