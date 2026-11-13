#!/usr/bin/env python3
"""Validate human-labelled speech and build portable, speaker-disjoint inputs."""
import argparse
import array
import hashlib
import json
import math
import re
import shutil
import sys
import wave
from collections import defaultdict
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def validate(manifest, speakers):
    plan = {s['speaker_id']: s for s in speakers}
    if len(plan) != len(speakers):
        raise ValueError('Duplicate speaker IDs in the speaker plan')
    rows, ids, hashes, sessions, groups = [], set(), {}, {}, defaultdict(set)
    for row in jsonl(manifest):
        ident = row.get('id', '')
        if not isinstance(ident, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', ident) or ident in ids:
            raise ValueError('Every clip needs a unique safe ID')
        ids.add(ident)
        speaker = plan.get(row.get('speaker_id'))
        if speaker is None or row.get('accent') != speaker['accent']:
            raise ValueError(f'{ident}: unknown speaker or accent mismatch')
        split, accent = speaker['split'], speaker['accent']
        if split not in ['train', 'dev', 'test'] or accent not in ['en-IN', 'en-GB']:
            raise ValueError(f'{ident}: unsupported split/accent')
        if row.get('human_verified') is not True or row.get('training_allowed') is not True or row.get('synthetic') is not False:
            raise ValueError(f'{ident}: use human-verified, authorised, real recordings')
        text = row.get('text')
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f'{ident}: verified verbatim transcript is required')
        session = row.get('session_id')
        if not isinstance(session, str) or not session.strip():
            raise ValueError(f'{ident}: session_id is required')
        if session in sessions and sessions[session] != split:
            raise ValueError(f'{ident}: a recording session crosses splits')
        sessions[session] = split
        audio = (manifest.parent / row['audio']).resolve()
        with wave.open(str(audio), 'rb') as f:
            if (f.getframerate(), f.getnchannels(), f.getsampwidth(), f.getcomptype()) != (16000, 1, 2, 'NONE'):
                raise ValueError(f'{ident}: expected 16 kHz mono PCM16 WAV')
            seconds = f.getnframes() / 16000
            if not 1 <= seconds <= 35:
                raise ValueError(f'{ident}: keep each clip between 1 and 35 seconds')
            samples = array.array('h', f.readframes(f.getnframes()))
            if sys.byteorder != 'little': samples.byteswap()
        rms = math.sqrt(sum(x * x for x in samples) / len(samples)) / 32768
        if rms < .001 or sum(abs(x) >= 32760 for x in samples) / len(samples) > .01:
            raise ValueError(f'{ident}: recording is near-silent or heavily clipped; inspect/re-record')
        digest = sha(audio)
        if digest in hashes:
            raise ValueError(f'{ident}: duplicate audio; do not leak/repeat clips across splits')
        hashes[digest] = split
        groups[split, accent].add(speaker['speaker_id'])
        rows.append({**row, 'audio': audio, 'split': split, 'seconds': seconds, 'sha256': digest})
    for split in ['train', 'dev', 'test']:
        for accent in ['en-IN', 'en-GB']:
            if not groups[split, accent]:
                raise ValueError(f'Missing {split} speakers/recordings for {accent}')
    return rows


def build(manifest, speakers_path, output):
    speakers = json.loads(speakers_path.read_text())
    rows = validate(manifest, speakers)
    output.mkdir(parents=True, exist_ok=False)
    (output / 'audio').mkdir()
    compiled = []
    for row in rows:
        relative = f'audio/{row["id"]}.wav'
        shutil.copyfile(row['audio'], output / relative)
        compiled.append({**row, 'audio': relative, 'speaker': row['speaker_id']})
    by_split = {s: [r for r in compiled if r['split'] == s] for s in ['train', 'dev', 'test']}
    # Upstream reserves a tail slice for early stopping. Append the dedicated
    # dev speakers after train; use their exact duration to keep this disjoint.
    for name, values in [('train-dev', by_split['train'] + by_split['dev']), ('test', by_split['test']), ('all', compiled)]:
        (output / f'{name}.jsonl').write_text(''.join(json.dumps(r) + '\n' for r in values))
    dev_seconds = sum(r['seconds'] for r in by_split['dev'])
    report = {'status': 'validated_data_not_a_trained_model', 'clips': len(rows),
              'hoursBySplit': {s: sum(r['seconds'] for r in rs) / 3600 for s, rs in by_split.items()},
              'clipsByAccentAndSplit': {f'{s}/{a}': sum(r['accent'] == a for r in rs) for s, rs in by_split.items() for a in ['en-IN', 'en-GB']},
              'speakersBySplit': {s: sorted({r['speaker_id'] for r in rs}) for s, rs in by_split.items()},
              'devHours': max(0, (dev_seconds - 1e-6) / 3600),
              'splitPolicy': 'Whole speakers and sessions held out; duplicate audio rejected; dedicated dev speakers occupy the training manifest tail.',
              'audioSha256': {r['audio']: r['sha256'] for r in compiled},
              'manifestSha256': {n: sha(output / n) for n in ['train-dev.jsonl', 'test.jsonl', 'all.jsonl']}}
    (output / 'dataset-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'clips', 'hoursBySplit', 'clipsByAccentAndSplit']}))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--speakers', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.manifest.resolve(), args.speakers, args.output)
