# Offline STT comparison harness

This is an isolated diagnostic, not a new Flutter speech provider. It consumes
synthetic PCM fixtures and local model files; it does not access microphones,
accounts, entitlements, reports or network inference APIs. Results and conclusions
are in `docs/demo/stt-comparison.md`.

## Dependencies and preparation

Use an Apple Silicon Mac, Xcode 27, an ARM64 Android emulator and NDK
28.2.13676358. Keep generated files under the ignored `.local/phonon-ab/` directory.
`fixtures/voice/phonon-ab-sources.lock.json` records the exact model and runtime
artifacts and their checksums. Moonshine uses the existing
`fixtures/voice/moonshine-sources.lock.json` assets and native libraries.

The Phonon artifact is **Phonon-2.5 English**, not the older Phonon-2 CoreML
release. Download the pinned `.fsq` and `fermion-research==0.2.15` wheel from the
lock file, verify SHA-256, then unpack the wheel into `wheel-inspection/`.
Install that wheel in a dedicated `.venv` with its CPU speech dependencies. Use
`fermion._speech._fsq.unpack(source, destination)` to unpack the model into
`.local/phonon-ab/model/`; its reader verifies each reconstructed file. Save the
pinned model repository's release `config.json` as `model-release-config.json`.
Unzip the verified Android runtime archive into `android-runtime/`.

From the repository root:

```sh
.local/phonon-ab/.venv/bin/python scripts/stt-ab/prepare.py --tensors-only
.local/voice-lab/.venv/bin/python scripts/stt-ab/prepare.py --audio-only
python3 scripts/stt-ab/build.py macos
python3 scripts/stt-ab/build.py android
python3 scripts/stt-ab/build.py ios-simulator --experimental-simulator-port
```

Audio preparation needs the existing `.local/moonshine-tests/audio/` regression
fixtures and local Kokoro model, `sherpa_onnx`, NumPy and SciPy. It generates the
same text and voice selection for both recognizers. Generated PCM checksums are
recorded in the saved comparison evidence; different synthesis dependency
versions may produce different PCM and require a fresh comparison.

`prepare.py` preserves the original packed encoder records. Original decoder
int6 codes are unpacked to int8 without requantization. The prepared tensor
bundle is larger than the downloadable model; it is a benchmark format, not an
APK size estimate. A frontend parity check against the official Python loader
and an S1 transcript parity check are recorded in the results provenance.

Stage these local runtime layouts (copies/symlinks only):

- `run/moonshine/`: the eight pinned Moonshine weight/config/tokenizer files.
- `run/lib-macos/{enc,tdt}`: the wheel's macOS ARM64 encoder/decoder dylibs;
  `run/lib-macos/moonshine`: the pinned macOS Moonshine dylib, with its original
  adjacent dependencies.
- `lib-android/{enc,tdt,enc-base,tdt-base}`: the Android archive's dotprod and base
  encoder/decoder libraries; `lib-android/moonshine` and `libmoon_ort123.so`: the
  existing isolated Moonshine Android runtime. The runner checks CPU features
  before choosing a library tier.

The iOS build command prepares `run/lib-ios-experimental/{enc,tdt}` from copies of
the wheel's macOS ARM64 kernels by changing their Mach-O platform metadata and
ad-hoc signing them. **This is an experimental simulator-only port, not a
vendor-supported or qualified physical-iPhone runtime.** Kernel instructions and
model weights are unchanged. Never add these files to a shipping app.

For Android, copy `bin/benchmark-android` as `benchmark`, the `run/` contents
(dereferencing the Moonshine symlink), and `lib-android/` as `lib/` to
`/data/local/tmp/field-stt-ab/`. Verify all remote SHA-256 values against the local
files before running. No model download occurs on the emulator.

## Execution and scoring

Run one platform/phase at a time on an otherwise idle host. Replace `booted` with
an explicit simulator UUID when multiple devices are booted. Preserve the same
model settings and corpus for all comparisons.

```sh
python3 scripts/stt-ab/run.py ios-simulator --device booted --phase bulk
python3 scripts/stt-ab/run.py android-emulator --phase bulk
python3 scripts/stt-ab/run.py ios-simulator --device booted --phase paced
python3 scripts/stt-ab/run.py ios-simulator --device booted --phase focused
python3 scripts/stt-ab/run.py android-emulator --phase paced
python3 scripts/stt-ab/run.py android-emulator --phase focused
```

The Android runner disables its radios during recognition and restores their
previous settings in `finally`. The iOS diagnostic has no networking code and
loads only staged local files. Native results are JSONL in
`.local/phonon-ab/results/`. Never run this diagnostic against production reports.

The bulk pass runs all 31 cases twice, after an excluded warm-up. Moonshine uses
the app's published runtime default thread count and existing term hints;
Phonon uses two threads, with and without the same hints. Numerical readings are
never supplied as hints. The hint strengths are engine-specific, so equal
numeric strengths do not imply equal decoder behavior.

The paced pass replays three S1 cases in real time with a fixture-known endpoint
and 1.8-second pause allowance. The focused pass uses two short reading answers
and a 450 ms allowance. Moonshine processes incoming chunks; Phonon processes
the completed utterance. Reported delay excludes microphone capture, natural
VAD/endpoint decisions, extraction, TTS and playback. It is **not** full voice-bot
latency or physical-phone performance. Do not compare bulk processing time to
the time a user waits after speaking.

```sh
cd apps/mobile
../../.local/toolchain/flutter/bin/dart --packages=.dart_tool/package_config.json run ../../scripts/stt-ab/score.dart
../../.local/toolchain/flutter/bin/flutter test test/stt_comparison_scoring_test.dart
```

Scoring keeps literal signed measurements separate from mapping into existing
form fields. WER uses shared orthographic normalization; it does not correct
either model's hypotheses. The compact parser is scored before form validation
and final engineer confirmation. Needle3 and the complete voice conversation
are not benchmarked here. Parser code and model files must remain frozen during
an A/B run; record any later fixes as a separate experiment.

After all timed runs and final source edits, capture provenance from the root:

```sh
python3 scripts/stt-ab/capture.py --android-device emulator-5554
```

This checks all 49 files consumed by the Android runner against their local
copies, verifies pinned artifacts and original native libraries, checks that
the experimental simulator kernels retain the original instruction section,
and saves hashes plus host/dependency versions. Run hashing and test tools
after timing, to avoid CPU contention with the recognizers.
