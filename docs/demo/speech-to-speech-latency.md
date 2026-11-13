# Current-app speech-to-speech timing

Primary run completed 2026-10-26T18:24:13.958121+00:00. App source version 0.3.4+22, iOS simulator debug,
Apple M2 Pro, 16 GiB RAM.
30 completed controlled turns through the production compact form and voice journey
(25 primary turns plus 5 harness-validation turns).
Validation completed 2026-10-26T18:29:38.090989Z.

## Results

| Turn | Samples | Median | Observed range | Expected fields matched |
| --- | ---: | ---: | ---: | ---: |
| Short optical answer | 6 | 1.196 s | 1.110–1.235 s | 6/6 |
| Short choice (Passed) | 6 | 1.135 s | 0.878–1.227 s | 6/6 |
| Spoken optical correction | 6 | 11.320 s | 11.053–13.952 s | 0/6 |
| Full S1 summary → Anything else? | 6 | 2.361 s | 2.271–2.442 s | 6/6 |
| Added detail after Anything else? → next question | 6 | 2.412 s | 2.363–2.522 s | 6/6 |

Do not use the earlier 0.45-second STT result as full conversational latency.
These new results include the app's actual endpoint decision, transcript finalization,
structured form interpretation, signed access checks, encrypted saving, question
preparation and native playback start. Short answers retain the configured 450 ms
pause; summaries/additions retain the configured 1800 ms thinking pause.

The preliminary runs are also retained in the JSON. One preliminary short optical
turn measured 1.923 s; those incomplete pilot runs are separate from the complete
repeat-run table above. Do not treat the repeat-run maximum as a guaranteed ceiling.

## Slow or unmatched replies

The raw data retains the displayed assistant question, source transcript and
expected-field match for every reply. The corrected-reading sentence may lead to
clarification rather than acceptance of the corrected value; consult its match
count above. Its delay still counts as a reply and is not removed from the data.

Event breakdowns distinguish speech-end → capture stop, post-save reply preparation,
and native play request → first voiced output cursor. A long post-save gap on an
uncached clarification is consistent with the live synthesis fallback in
QuestionVoice; this phase is measured as a whole, not as an isolated TTS timer.

## Measurement boundary

Start: delivery of the last voiced 20 ms synthetic input frame at real-time pace.
Finish: the native AVAudioPlayer is playing and its actual cursor reaches the first
voiced 20 ms reply frame. A simulator-only read-only native getter supplies that cursor.
The Dart animation meter is not used to determine reply onset.

The full CompactClosureScreen and AppController run, including the actual
Moonshine/Silero streaming path, StructuredVisitExtractor, default QuestionVoice /
PromptAudioCache, Keychain/ES256 authorization and SQLCipher draft writes.
Every measured turn records whether the expected field values match. Unmatched
or clarification replies remain in the timing data; a quick reply must not be
presented as successful auto-fill. The post-Anything-else
case first speaks a separate initial narrative and waits for the real invitation
and reopened listening turn before adding the measured detail.

All network transport is rejected by the test adapter; blocked background
attempts are retained in the JSON. All inputs are synthetic. No report is submitted. A separate simulator
keeps the presentation app and its reports untouched.

Primary run status: **25 measured turns completed; post-run empty-request-list assertion failed**. All 25 turn records completed.
The original final assertion expected an empty attempted-request list and found
one rejected auth/login attempt. That post-run harness assertion was corrected;
the original log and source snapshot are retained. It does not establish a
successful login or cloud inference: the adapter throws before network I/O.

A subsequent five-turn validation of the corrected harness **passed**, including
final evidence export and teardown. Those five turns are retained separately in
the JSON; they do not replace or dilute the primary 25 measurements.

The overview combines both runs because the measured implementation was unchanged;
only the post-run request-list assertion changed. The validation correction reply
took 13.952 s and is included in the combined range rather than omitted.


## Limits on the meeting claim

Use the medians/ranges above as **controlled end-to-end software measurements on
the iOS simulator**. They are not a physical-phone or acoustic speech-to-speech
claim. Microphone capture is replaced by paced PCM, and speaker/route buffering
is outside the measured boundary. The 20 ms energy windows and 10 ms polling
also limit onset precision.

Models are already loaded. Default voice/rate uses the normal prepared question
path; app startup, a new custom TTS prompt, alternative settings and background
noise require separate checks. Five repeated samples of a synthetic phrase are
repeatability checks, not five independent engineers. Do not promise an instant
reply or a fleet-wide maximum from this run.

For a physical-phone claim, repeat through live microphone capture on the target
iPhone and Android devices, and independently record engineer speech and audible
bot output on one acoustic timeline. Count the gap from final engineer speech to
first bot speech, report short answers and long summaries separately, and retain
failures, noise conditions, first/warm turns and headset/speaker route details.

## Reproduce

Run on an isolated iOS simulator with the bundled synthetic demo configuration:

```sh
cd apps/mobile
../../.local/toolchain/flutter/bin/flutter test integration_test/speech_to_speech_latency_test.dart \
  -d 037B382A-4CED-4EC7-917F-2B95EEDFA214 --no-uninstall --no-pub \
  --dart-define-from-file=../../.local/mobile-demo-config.json --reporter expanded \
  > ../../.local/speech-to-speech-ios-20261026.log 2>&1
cd ../..
python3 scripts/summarize-speech-turns.py
```

Raw samples, event breakdowns, host metadata and source SHA-256 values:
`fixtures/voice/benchmarks/speech-to-speech-ios-simulator-20261026.json`.
Local full run log: `.local/speech-to-speech-ios-20261026.log`.
The native playback-position getter exists only in simulator builds; this measurement
adds no speech logging or runtime configuration change to release builds.
