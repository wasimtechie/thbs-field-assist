# Mobile storage and hardware sizing

## Current streaming build — 0.3.0

The offline package uses Moonshine Small Streaming English with embedded Silero VAD, the existing Needle3 model for source-validated extraction, and Kokoro. Qwen weights and the llama/ggml native runtime are excluded. The signed ARM64 debug APK is **453,089,062 bytes (453.1 MB)**, compared with **867,079,008 bytes** for 0.2.2: **413,989,946 bytes / 47.75% smaller**. Exact inventories are recorded in `fixtures/voice/benchmarks/needle-mobile-footprint-20261023.json`; artifact checks are in `.local/demo-builds/field-assist-demo-v0.3.0-arm64.json`.

| Bundled model data | Exact bytes | Decimal MB |
| --- | ---: | ---: |
| Moonshine Small Streaming (8 files) | 142,300,974 | 142.3 |
| Needle3 | 35,335,380 | 35.3 |
| Kokoro | 134,186,977 | 134.2 |
| Kokoro voices | 5,755,904 | 5.8 |
| Phonemizer and tokenizer | 18,004,222 | 18.0 |
| **Total: 369 files** | **335,583,457** | **335.6** |

The 91 prepared prompts and these model files are already inside the APK. Model chunks occupy **261,521,169 compressed bytes** in the download and extract to 335.6 MB in private storage. Native libraries account for **104,175,936 bytes**, the debug Dart kernel for **29,352,291 compressed bytes**, and prepared prompts for **17,064,705 compressed bytes**. Debug tooling, Flutter, Android code and other assets account for the rest. These are download/ZIP inventories, not installed storage or RAM measurements.

The application preserves saved reports when upgraded. An old model package may remain cached alongside the new one, so upgrading does not imply that all old on-device model storage disappears. Runtime RAM for this new package has not been measured on a physical phone. Removing Qwen reduces bundled weights but does not establish a supported RAM minimum.

Use **3 GB free storage** as a provisional allowance for a fresh installation, temporary update space and working data; allow more for retained model caches, photos and reports. Validate ARM64 **Android 12+ with 6 GB RAM or more; 8 GB preferred**. A 4 GB emulator is a diagnostic environment, not a certified phone minimum. iPhone builds require iOS 18+; iPhone 13/A15 or newer is a practical qualification target. Simulator/debug timings do not establish phone performance. The build retains the earlier speech-capture fixes and passes 149 targeted regressions. Live accents, site noise, battery and repeated-turn thermals still require presentation-device testing.

## Historical measurements — previous voice stack

The app contains **88 prepared speech-only Kokoro recordings**: 79 field questions and nine conversation prompts. VibeVoice's 0.5B weights and the Mac research environments are not installed on a phone. Whistle recognises speech locally, Needle 3 proposes report values, and Kokoro supplies the same fixed voice for prepared prompts and live fallback. The proposed direct-TTS route has not replaced prepared playback yet. Mac premium has been removed. The voice journey advances automatically after a clear spoken answer or a selected option; final closure still needs human review.

## Offline voice files

These are exact logical file sizes from `fixtures/voice/asset-manifest.json`. MB means 1,000,000 bytes.

| Component | MB |
| --- | ---: |
| Whistle speech recognition | 16.9 |
| Needle 3 extraction | 35.3 |
| Kokoro model | 134.2 |
| Kokoro voices | 5.8 |
| Phonemizer, dictionaries and tokenizer | 18.0 |
| **Additional offline voice files** | **210.2** |

The current prepared Kokoro pack is **16.7 MB in source assets** (16,702,740 bytes including its index). The older measured builds below contained a 21.8 MB VibeVoice pack. Rebuild before quoting a current app size; replacing the pack alone does not establish the installed-size difference. A bundled pack is already inside the compiled app and must not be counted twice. The compiled app also includes Flutter, native inference libraries, OCR and ordinary assets. Forms, encrypted reports, photographs, OS caches and retained model versions add variable storage.

## Measured builds with the hands-free assistant

| Build | App files, MB | Additional voice files, MB | Combined files, MB |
| --- | ---: | ---: | ---: |
| Android ARM64 release APK, unsigned sizing artifact | 103.1 | 210.2 | **313.3** |
| Android ARM64 debug APK, signed local demo | 218.5 | 210.2 | **428.7** |
| iOS ARM64 release `.app`, unsigned logical bundle | 81.1 | 210.2 | **291.3** |

The Android release ZIP contents total 103.5 MB before voice files; debug ZIP contents total 261.4 MB. These are payload inventories, rather than measurements of Android's installed storage. The iOS row is an uncompressed app bundle, rather than an IPA download. Use **1 GB for app and working-data planning**, and keep **2 GB free for installation and updates**. More retained evidence or model versions require more storage.

## Runtime memory

Earlier user-driven iPhone simulator debug snapshots ranged from about 269 MB to 605 MB RSS. A separate snapshot during native automatic-advance replay, with the same Whistle/Needle/Kokoro inference stack, was **1247.4 MB RSS**. The latter preceded the optimisation that replaced ordinary live acknowledgements with prepared clips. These are different workloads and moments; they do not establish idle memory, lifetime peak, physical-phone memory, release performance or a memory leak.

Allow approximately **1.5 GB of process-memory headroom provisionally** when planning qualification. This is an engineering allowance, rather than a measured peak or supported minimum. Test the release/profile app on a phone through model loading, long recognition turns, extraction, fallback speech, evidence capture and repeated turns, including OS memory pressure and thermals. [Flutter's profiling guidance](https://docs.flutter.dev/perf/ui-performance) explains why simulator/debug measurements do not establish physical-device performance.

## Devices to validate

| Platform | Enforced build requirements | Suggested validation target |
| --- | --- | --- |
| Android | ARM64, Android 12 / API 31 or newer | Modern midrange or better CPU, 6 GB RAM or more; 8 GB gives more headroom |
| iPhone | ARM64, iOS 18 or newer | iPhone 13 / A15 or newer as a practical test target |
| Storage | Compiled app plus models, reports and evidence | Keep at least 2 GB free during installation, model repair/updates and working use |

These targets are recommendations for validation, rather than a certified minimum-device matrix. [Apple lists iPhone 13's A15 hardware](https://support.apple.com/en-us/111872) and [iOS 18 compatibility](https://support.apple.com/en-ae/104985); those specifications do not certify this app's voice performance. Older supported-OS phones may work, but have not passed device acceptance. Protected offline use needs a device passcode/biometrics, microphone permission and initial online provisioning.

## Interpreting the measurements

APK download bytes, uncompressed ZIP contents, installed storage and RAM measure different things. Android can retain the APK and create additional compiled/extracted data. An unsigned iOS `.app` measures bundle contents, rather than App Store download bytes. Signing, thinning and distribution affect delivered size. Debug builds include development tooling. See [Flutter's app-size guide](https://docs.flutter.dev/perf/app-size).

Exact bytes, build types, hashes and measurement scope are in `fixtures/voice/benchmarks/mobile-footprint.json`. The separately saved Android debug APK is the installable local-network rehearsal artifact. The unsigned release artifacts measure size and compilation; iPhone signing and physical-device voice acceptance remain outstanding.
