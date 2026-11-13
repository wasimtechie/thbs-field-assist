#!/usr/bin/env python3
"""Summarize the current-app native voice-turn diagnostic, after timing ends."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
LABELS = {
    'short-optical': 'Short optical answer',
    'short-choice': 'Short choice (Passed)',
    'corrected-optical': 'Spoken optical correction',
    's1-summary': 'Full S1 summary → Anything else?',
    'after-anything-else': 'Added detail after Anything else? → next question',
}


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, default=ROOT / '.local/speech-to-speech-ios-20261026.log')
    parser.add_argument('--output', type=Path, default=ROOT / 'fixtures/voice/benchmarks/speech-to-speech-ios-simulator-20261026.json')
    parser.add_argument('--doc', type=Path, default=ROOT / 'docs/demo/speech-to-speech-latency.md')
    parser.add_argument('--allow-postrun-offline-assertion', action='store_true')
    parser.add_argument('--validation-log', type=Path)
    args = parser.parse_args()
    if args.validation_log:
        args.validation_log = args.validation_log.resolve()
    log = args.log.read_text()
    marker = 'SPEECH_TO_SPEECH_EVIDENCE '
    lines = [line.split(marker, 1)[1] for line in log.splitlines() if marker in line]
    if len(lines) == 1 and 'All tests passed!' in log:
        report = json.loads(lines[0])
        report['harnessStatus'] = 'passed'
    elif args.allow_postrun_offline_assertion and "Expected: empty" in log and "Actual: ['auth/login']" in log and log.count('EXCEPTION CAUGHT') == 1:
        rows = [json.loads(line.split('SPEECH_TO_SPEECH_SAMPLE ', 1)[1]) for line in log.splitlines() if 'SPEECH_TO_SPEECH_SAMPLE ' in line]
        assert len(rows) == 25 and log.count('TURN_TIMING_START ') == 25
        for key in LABELS:
            assert sorted(s['iteration'] for s in rows if s['case'] == key) == [1, 2, 3, 4, 5]
        report = {'measuredAt': datetime.fromtimestamp(args.log.stat().st_mtime, timezone.utc).isoformat(),
            'scope': 'iOS simulator debug. All 25 current-app paced PCM/native playback timing samples completed before a post-run assertion rejected a blocked background auth/login attempt. No actual network transport is possible through the rejecting adapter. Native output cursor, not acoustic speaker measurement.',
            'inputFrameMs': 20, 'voicedRmsThreshold': .004, 'outputPollMs': 10,
            'modelsResidentBeforeTurns': True, 'defaultVoice': 'bm_george', 'speechRate': 1,
            'samples': rows, 'networkRequests': ['auth/login'],
            'harnessStatus': '25 measured turns completed; post-run empty-request-list assertion failed',
            'postRunFailure': 'An auth/login attempt was rejected by NoNetworkApi. The final assertion expected no attempted requests, although all transport was blocked. This occurred after every timing sample and did not invalidate their recorded boundaries. The assertion was subsequently corrected; the original log is retained.'}
    else:
        raise SystemExit('No complete timing run. Arbitrary partial/failed runs cannot be summarized.')
    samples = report['samples']
    assert samples
    groups = []
    for key, label in LABELS.items():
        rows = [s for s in samples if s['case'] == key]
        assert rows, key
        values = [s['speechEndToVoicedReplyMs'] for s in rows]
        groups.append({'case': key, 'label': label, 'samples': len(values),
                       'expectedFieldMatches': sum(s['expectedValuesVerified'] for s in rows),
                       'medianMs': statistics.median(values), 'minMs': min(values), 'maxMs': max(values),
                       'medianCaptureStopMs': statistics.median(s['eventsMs']['captureStopRequested'] for s in rows),
                       'medianPlayRequestMs': statistics.median(s['eventsMs']['playRequested'] for s in rows),
                       'medianPostSaveReplyPreparationMs': statistics.median(s['eventsMs']['playRequested'] - s['eventsMs']['saveCompleted'] for s in rows),
                       'medianPlayerStartMs': statistics.median(s['eventsMs']['firstVoicedPlaybackCursor'] - s['eventsMs']['playRequested'] for s in rows)})
    report['summary'] = groups
    report['host'] = {'cpu': command('sysctl', '-n', 'machdep.cpu.brand_string'),
                      'memoryBytes': command('sysctl', '-n', 'hw.memsize'),
                      'os': platform.platform(), 'macos': platform.mac_ver()[0]}
    report['appVersion'] = '0.3.4+22'
    report['simulator'] = {'name': 'Field Assist Voice Timing', 'deviceType': 'iPhone 17',
                           'os': 'iOS 27.0', 'id': '037B382A-4CED-4EC7-917F-2B95EEDFA214'}
    paths = [
        'apps/mobile/integration_test/speech_to_speech_latency_test.dart',
        'apps/mobile/lib/features/voice/streaming_capture.dart',
        'apps/mobile/lib/features/voice/voice_audio.dart',
        'apps/mobile/lib/features/voice/prompt_audio_cache.dart',
        'apps/mobile/lib/features/closure/closure_voice_assistant.dart',
        'apps/mobile/lib/features/closure/compact_closure_screen.dart',
        'apps/mobile/lib/features/closure/structured_visit_extraction.dart',
        'apps/mobile/lib/features/closure/question_voice.dart',
        'apps/mobile/lib/app/app_controller.dart',
        'apps/mobile/ios/Runner/AppDelegate.swift',
        'apps/mobile/assets/voice_questions/index.json',
        'apps/mobile/assets/offline_demo/bootstrap.json',
        'packages/field_voice/lib/field_voice.dart',
        'packages/field_voice/lib/moonshine.dart',
    ]
    report['sourceSha256'] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
    frozen = ROOT / '.local/speech-to-speech-primary-harness-sha256.json'
    if report['harnessStatus'] != 'passed' and frozen.exists():
        source = json.loads(frozen.read_text())
        report['sourceSha256'][source['path']] = source['sha256']
        report['harnessSourceSnapshot'] = '.local/speech-to-speech-primary-harness.dart'
    report['logSha256'] = hashlib.sha256(args.log.read_bytes()).hexdigest()
    report['preliminaryRuns'] = []
    for name in ['navigation', 'correction']:
        pilot = ROOT / f'.local/speech-to-speech-ios-20261026-{name}-partial.log'
        if not pilot.exists():
            continue
        pilot_rows = [json.loads(line.split('SPEECH_TO_SPEECH_SAMPLE ', 1)[1])
                      for line in pilot.read_text().splitlines() if 'SPEECH_TO_SPEECH_SAMPLE ' in line]
        report['preliminaryRuns'].append({'log': str(pilot.relative_to(ROOT)),
            'sha256': hashlib.sha256(pilot.read_bytes()).hexdigest(), 'samples': pilot_rows,
            'scope': 'Verified initial timing samples retained separately. The pilot stopped later because of test navigation or the original field-match assertion. These samples are not pooled with the complete repeat run.'})
    report['limitations'] = [
        'Synthetic clean speech; microphone acquisition is replaced by real-time PCM replay.',
        'Native AVAudioPlayer cursor detects output onset. Actual speaker, acoustic route/buffering and microphone-driver stop latency are not measured.',
        'Input/output voiced frames use RMS 0.004 over 20 ms; native output polling is every 10 ms. These define a software onset estimate, not sample-accurate acoustic timing.',
        'iOS simulator debug on an Apple Silicon Mac. No physical iPhone, Android phone or Android emulator measurement in this run.',
        'Models are resident after normal offline boot/smoke checks and synthetic fixture generation. Application/model startup is excluded.',
        'Default voice/rate and the normal prepared-question/cache path. Uncached dynamic TTS, alternative voices/rates and site noise may behave differently.',
        'Small scenario-specific sample counts; observed ranges are not service guarantees or population tail-latency estimates.',
    ]
    validation_note = ''
    if args.validation_log:
        validation_log = args.validation_log.read_text()
        validation_lines = [line.split(marker, 1)[1] for line in validation_log.splitlines() if marker in line]
        assert len(validation_lines) == 1 and 'All tests passed!' in validation_log
        validation = json.loads(validation_lines[0])
        report['postRunHarnessValidation'] = {
            'status': 'passed', 'samples': validation['samples'],
            'measuredAt': validation['measuredAt'],
            'blockedNetworkAttempts': validation['networkRequests'],
            'log': str(args.validation_log.relative_to(ROOT)),
            'logSha256': hashlib.sha256(args.validation_log.read_bytes()).hexdigest(),
            'harnessSha256': hashlib.sha256((ROOT / paths[0]).read_bytes()).hexdigest(),
            'scope': 'One additional turn per scenario after correcting only the post-run attempted-request assertion. These five validation turns are retained separately, not pooled with the primary 25.'}
        validation_note = '\nA subsequent five-turn validation of the corrected harness **passed**, including\nfinal evidence export and teardown. Those five turns are retained separately in\nthe JSON; they do not replace or dilute the primary 25 measurements.\n'
        combined = samples + validation['samples']
        report['combinedSummary'] = []
        for key, label in LABELS.items():
            rows = [s for s in combined if s['case'] == key]
            times = [s['speechEndToVoicedReplyMs'] for s in rows]
            report['combinedSummary'].append({'case': key, 'label': label, 'samples': len(rows),
                'medianMs': statistics.median(times), 'minMs': min(times), 'maxMs': max(times),
                'expectedFieldMatches': sum(s['expectedValuesVerified'] for s in rows)})
        validation_note += '\nThe overview combines both runs because the measured implementation was unchanged;\nonly the post-run request-list assertion changed. The validation correction reply\ntook 13.952 s and is included in the combined range rather than omitted.\n'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    display_groups = report.get('combinedSummary', groups)
    display_count = sum(s['samples'] for s in display_groups)
    table = '\n'.join(f"| {s['label']} | {s['samples']} | {s['medianMs']/1000:.3f} s | {s['minMs']/1000:.3f}–{s['maxMs']/1000:.3f} s | {s['expectedFieldMatches']}/{s['samples']} |" for s in display_groups)
    doc = f'''# Current-app speech-to-speech timing

Primary run completed {report['measuredAt']}. App source version 0.3.4+22, iOS simulator debug,
{report['host']['cpu'] or 'Apple Silicon Mac'}, {int(report['host']['memoryBytes'] or 0)/2**30:.0f} GiB RAM.
{display_count} completed controlled turns through the production compact form and voice journey
({len(samples)} primary turns plus {display_count-len(samples)} harness-validation turns).
Validation completed {report.get('postRunHarnessValidation', {}).get('measuredAt', 'not provided')}.

## Results

| Turn | Samples | Median | Observed range | Expected fields matched |
| --- | ---: | ---: | ---: | ---: |
{table}

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

Primary run status: **{report['harnessStatus']}**. All {len(samples)} turn records completed.
The original final assertion expected an empty attempted-request list and found
one rejected auth/login attempt. That post-run harness assertion was corrected;
the original log and source snapshot are retained. It does not establish a
successful login or cloud inference: the adapter throws before network I/O.
{validation_note}

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
../../.local/toolchain/flutter/bin/flutter test integration_test/speech_to_speech_latency_test.dart \\
  -d 037B382A-4CED-4EC7-917F-2B95EEDFA214 --no-uninstall --no-pub \\
  --dart-define-from-file=../../.local/mobile-demo-config.json --reporter expanded \\
  > ../../.local/speech-to-speech-ios-20261026.log 2>&1
cd ../..
python3 scripts/summarize-speech-turns.py
```

Raw samples, event breakdowns, host metadata and source SHA-256 values:
`fixtures/voice/benchmarks/speech-to-speech-ios-simulator-20261026.json`.
Local full run log: `.local/speech-to-speech-ios-20261026.log`.
The native playback-position getter exists only in simulator builds; this measurement
adds no speech logging or runtime configuration change to release builds.
'''
    args.doc.parent.mkdir(parents=True, exist_ok=True)
    args.doc.write_text(doc)
    print(json.dumps({'samples': len(samples), 'summary': groups, 'evidence': str(args.output), 'doc': str(args.doc)}, indent=2))


if __name__ == '__main__':
    main()
