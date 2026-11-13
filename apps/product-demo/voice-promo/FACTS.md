# Claims and limits

| Film claim | Evidence / interpretation |
| --- | --- |
| Five short-summary fields; no asset reference | `apps/mobile/lib/features/closure/compact_closure_screen.dart`, version 0.3.4. |
| Missing-only conversation, spoken repairs, additions, review | Production voice/closure source and 57 passing focused Flutter checks recorded in `.local/five-field-regression.log`. Live performance varies. |
| Approximately 0.45 s short-answer recognition | `fixtures/voice/benchmarks/phonon-vs-moonshine-20261025.json`, Android ARM64 emulator, Moonshine, paced focused pass, two samples, median 452.2888145 ms. Includes configured 450 ms pause, excludes microphone, natural endpoint detection, extraction, TTS and playback. Not a complete-app or physical-phone result. |
| Offline processing | Existing bundled Moonshine / embedded Silero / Needle3 / Kokoro. Authorized provisioned offline access is time-limited; approved records need backend connectivity for delivery. |
| Corrected −18.19 reading | Source-grounded parser and synthetic regression/native replay in `fixtures/voice/benchmarks/speech-repair-20261025.json`. Film UI is illustrative and edited for pacing. |
| Existing-app integration | Proposed SDK/native bridge/API adapters, subject to each host application's interfaces and permissions. No deployed Openreach integration is claimed. |
| Domain fine-tuning | A scoped future engagement based on approved recordings and device validation. Recording/training preparation is in `docs/demo/moonshine-training.md`; no fine-tuned checkpoint or accuracy improvement is claimed. |

No invented time savings, battery measurements, universally best-model claim,
automatic operational approval or guaranteed device minimum appears in the film.

Newer full-app software timing evidence is in
`docs/demo/speech-to-speech-latency.md`: 30 paced synthetic iOS simulator turns
measured speech end to the native voiced playback cursor. Routine answers have
medians near 1.2 s and summaries/additions near 2.4 s. A corrected-reading
clarification path had a median about 11.3 s (observed 11–14 s) and did not accept the corrected value.
These results neither turn the film's 0.45 s recognition number into full-bot
latency nor validate the edited correction animation as measured live behavior.
Physical-phone and acoustic timing remain pending.
