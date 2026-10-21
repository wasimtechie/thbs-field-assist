# Native runtime manifest

Specification: Field Engineer Assist PRD 3.0. Framework: Flutter 3.44.8 stable, framework `058e0af2c2`, Dart 3.12.2. Host verification: Apple Silicon macOS 27.2, build 26B5091g; Xcode 27.0 / 27A266a. No physical phone/OS combination has been verified yet.

## Pinned components

| Component | Pin / source | Integration and status |
| --- | --- | --- |
| Needle 3 | Hugging Face revision `93e88ede867e4311c39151285e74df513e4b835b` | One full shipped configuration; no dynamic layer selection or second model. Exact `needle.h` inspected. iOS ARM64, iOS simulator ARM64, Android ARM64, and macOS ARM64 archives acquired with hashes. |
| Whistle | Hugging Face revision `ca5287601bef25af26dcf2e1b2bdc0843a7c19e5` | Same Cactus engine. Verified C signature takes 16 kHz mono float PCM. Flutter records PCM16 mono/16 kHz and converts to float without uploading it. |
| Kokoro | Official sherpa-onnx `kokoro-int8-en-v0_19` archive | Archive SHA-256 `c9f0dd393615805b0bab050c340834d5e684e732aec91c0e860cd30e982c08bd`. Includes model, voices, tokens and local eSpeak data. |
| sherpa_onnx | 1.13.8 | Installed Dart source inspected: `OfflineTts`, `OfflineTtsKokoroModelConfig`, `OfflineTtsModelConfig`, `OfflineTtsConfig`, `generate`, and `free`. Uses local CPU inference with debug logging off. |
| SQLCipher | `sqflite_sqlcipher` 3.4.1; iOS SQLCipher 4.10.0 via FMDB | Native dependency version inspected. Application refuses an empty `PRAGMA cipher_version`. Device encryption/recovery tests remain pending. |
| Secure storage / presence | `flutter_secure_storage` 11.2.0; `local_auth` 3.0.2 | iOS keys use device-only, unlocked accessibility. Android backups are disabled. Local authentication runs before opening the account database. This demo does not claim cryptographic key-use gating against an already compromised process/device. |
| Lease signatures | server `jose` 6.1.3; Dart `jose` 0.3.5+2 | ES256 and pinned `kid`/EC P-256 key explicitly allowlisted. Shared signed fixtures pass in Dart. The initially inspected cryptography library did not implement ECDSA verification on the Dart VM; it was replaced before delivery. |
| Android | minSdk 31, compileSdk/targetSdk 36, NDK 28.2.13676358, JDK 21, AGP 9.0.1 | ARM64 only. ELF 16 KiB alignment verification script is supplied; passing Android hardware/page-size compatibility requires actual evidence. |
| iOS | deployment target 18.0, Runner shared scheme | CocoaPods used for SQLCipher. Pod deployment targets are aligned to iOS 18 for the installed Xcode SDK. Unsigned device build has passed; signing and execution on a phone have not. |

Exact dependency resolution is retained in `package-lock.json`, both `pubspec.lock` files, and `apps/mobile/ios/Podfile.lock`.

## Integrity and provenance

`fixtures/voice/model-sources.lock.json` records exact model/revision URLs, byte lengths and SHA-256 hashes. `fixtures/voice/asset-manifest.json` lists each of 362 required files (210,201,890 bytes total). Model files remain outside version control. Run `python3 scripts/provision-models.py` to reproduce acquisition; it verifies upstream hashes before installation.

Important weight hashes:

- Needle `needle3.cact`, 35,335,380 bytes: `c9d915eca282ed42d1a09b143b592adb4cc6744ffe2d294adf5cfc5548170c38`.
- Whistle `whistle.cact`, 16,919,407 bytes: `b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb`.
- iOS ARM64 `libneedle.a`: `e1dd5a4c59dc78aea54bcef91f4ba751ee30382adb92b8831ed2832833d76837`.
- Android ARM64 `libneedle.a`: `9be8b4b185ef1710f57179e3cc68835ac67fca8470bdbc6915d6966646d95385`.

The server catalog does not assert device readiness. Each device verifies local length/hash, installed schema/hash, signed entitlement, writable encrypted database and local speech smoke test. Missing binaries/assets fail explicitly. Partial transfers are resumable and do not replace verified files. The last good package remains installed.

## Verified C API and memory ownership

The Cactus Flutter package was inspected as a candidate, but its general LLM API does not establish support for these selected models. The local package therefore wraps the published `needle_load`, `needle_init`, `needle_complete`, `needle_transcribe`, `needle_last_error`, and `needle_reset` interfaces, preserving native error returns. The call sequence was also compared with the official Python wrapper.

The native API is process-global and not thread-safe. A persistent owning Dart worker serializes calls. Input/output buffers are allocated and released per operation; loaded weight buffers remain allocated for the process lifetime because the published API cannot unload weights. `unload` clears conversation/TTS state; replacing bound model weights requires restarting the app. Cancellation invalidates a generation/request, discards late results and prevents the next operation from using them. Raw recordings/transcripts remain in memory for the active turn; persisted values retain bounded provenance, not audio.

`NEEDLE_TELEMETRY=0` and `DO_NOT_TRACK=1` are set in the native shim before loading the engine. No cloud AI fallback or model-driven submission API exists.

## Extraction findings and adaptation

The first full-form extraction schema used nested optional fields. The real pinned model returned suppressed calls with confidence 0, so that approach was not used in the app. Its observations are retained in `docs/evidence/extraction-probe.json`.

The application now compiles one flat field-specific tool at a time from the current published schema, using the same single Needle model. Quantities extract an amount, then application code requires an explicit allowed unit or a unit already established by the current question. A narrow explicit numeric correction normalizer preserves the last stated value; alternatives remain unresolved. An exact, unambiguous select-label mention can be presented to the model in that field's canonical option-ID phrasing. Unknown/malformed outputs, low confidence, ungrounded results and non-voice fields never update the form. Missing required fields and clarification limits are computed in Dart.

This adapter produces `12 m` and `not_tested` for the tested correction/negation case on the Mac. Uncertain description/action fields remain unresolved. This is a bounded host observation, not a 95% accuracy claim. Per-field inference increases latency with field count; device optimization/evaluation is still required. No model fine-tuning or retraining was performed.

## Measured host smoke

Actual output: `docs/evidence/native-host-smoke.json`. Latest run happened alongside Android compilation under disk/memory pressure: model load 5,530 ms; field extraction 5,234 ms; cold synthesis 18,145 ms; ASR 298 ms; peak process RSS 422,281,216 bytes. Whistle transcribed actual Kokoro-generated 24 kHz audio resampled to 16 kHz as `Replaced 20 meters actually 12, I have not tested the line.` A prior lighter-load run is not substituted for these recorded measurements.

These timings exceed the proposed interaction targets and are not phone measurements or p95 estimates. Warm/cold isolated runs, optimization, the 100-utterance evaluation, 20 reports and the 30-minute session remain required on both platforms. Device baselines remain proposed rather than proven.

## Licence records

Needle/Whistle and their published artifacts: upstream Apache-2.0 licence copies are in `docs/licenses`. Kokoro archive and sherpa-onnx licence copies are also retained. The bundled eSpeak phonemizer/data has its own upstream GPL-3.0 notice; see `docs/licenses/espeak-ng-COPYING` and the upstream source at https://github.com/espeak-ng/espeak-ng. Do not treat the complete voice package as uniformly Apache-2.0. Distribution packaging must retain all upstream notices and corresponding source requirements; this local synthetic demonstration has not been published.

The auth object is a procedural torus mesh projected and depth-sorted with CustomPainter (960 triangles), with an animated rotation only when visible and unconstrained. A static rendering is used for reduced motion, low power or thermal constraints; no WebView or remote 3D asset is involved. Touch feedback uses a real Flutter SpringSimulation, and capture/playback indicators derive from microphone amplitudes and generated playback samples.

Platform verification and unresolved gates are tracked in `docs/progress.md`.

## iOS simulator result

The real Flutter app has run on iPhone 17 Pro / iOS 26.5 (23F77), under Xcode 27 Device Hub. Its native readiness check reported SQLCipher 4.10.0 active and completed Whistle silence recognition, explicit Needle tool extraction and Kokoro synthesis from the verified local package. This establishes simulator feasibility only; it is not recorded speech accuracy or physical-device acceptance. A separate native storage integration test passed draft reopen, identical frozen-payload retry after an intentionally lost accepted response, stable receipt recovery, encrypted database header and account namespace isolation. That test opens the repository directly without authenticating device-user presence; interactive authentication is a separate operator-observed check. See `docs/evidence/ios-simulator-integration.txt` and the simulator JSON evidence.
