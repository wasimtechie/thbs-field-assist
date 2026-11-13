import json
import random
import shutil
import struct
import tempfile
import unittest
import wave
from pathlib import Path
from dataset import build, validate
from train import training_args


class DatasetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.speakers, self.rows = [], []
        for accent in ['en-IN', 'en-GB']:
            for split in ['train', 'dev', 'test']:
                ident = accent + '-' + split
                self.speakers.append({'speaker_id': ident, 'accent': accent, 'split': split})
                rng = random.Random(ident)
                with wave.open(str(self.root / (ident + '.wav')), 'wb') as f:
                    f.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                    f.writeframes(b''.join(struct.pack('<h', rng.randint(-1000, 1000)) for _ in range(32000)))
                self.rows.append({'id': ident, 'audio': ident + '.wav', 'speaker_id': ident,
                                  'accent': accent, 'session_id': ident, 'text': 'The reading was minus 18.19 dBm.',
                                  'human_verified': True, 'training_allowed': True, 'synthetic': False})
        self.manifest = self.root / 'recordings.jsonl'
        self.plan = self.root / 'speakers.json'
        self.plan.write_text(json.dumps(self.speakers))
        self.save()

    def save(self):
        self.manifest.write_text(''.join(json.dumps(r) + '\n' for r in self.rows))

    def test_valid_portable_data_has_disjoint_dev_tail_and_pinned_model_argument(self):
        out = self.root / 'compiled'
        report = build(self.manifest, self.plan, out)
        rows = [json.loads(l) for l in (out / 'train-dev.jsonl').read_text().splitlines()]
        self.assertEqual([r['split'] for r in rows], ['train', 'train', 'dev', 'dev'])
        # Reproduce the upstream trainer's tail selection; no train speaker enters dev.
        seconds, held = 0, []
        for r in reversed(rows):
            if seconds >= report['devHours'] * 3600: break
            seconds += r['seconds']; held.append(r)
        self.assertTrue(all(r['split'] == 'dev' for r in held))
        self.assertEqual(len(held), 2)
        args = training_args(out, self.root / 'base-small', self.root / 'run', self.root / 'cache')
        self.assertEqual(args[args.index('--model') + 1], str(self.root / 'base-small'))
        self.assertNotIn('--no-replay', args)

    def test_duplicate_audio_is_rejected(self):
        shutil.copyfile(self.root / self.rows[0]['audio'], self.root / self.rows[-1]['audio'])
        with self.assertRaisesRegex(ValueError, 'duplicate audio'):
            validate(self.manifest, self.speakers)

    def test_session_leakage_is_rejected(self):
        self.rows[-1]['session_id'] = self.rows[0]['session_id']; self.save()
        with self.assertRaisesRegex(ValueError, 'session crosses splits'):
            validate(self.manifest, self.speakers)

    def test_missing_accent_in_any_split_is_rejected(self):
        self.rows.pop(); self.save()
        with self.assertRaisesRegex(ValueError, 'Missing test.*en-GB'):
            validate(self.manifest, self.speakers)

    def test_unverified_or_unauthorised_data_is_rejected(self):
        for key in ['human_verified', 'training_allowed']:
            self.rows[0][key] = False; self.save()
            with self.assertRaisesRegex(ValueError, 'human-verified'):
                validate(self.manifest, self.speakers)
            self.rows[0][key] = True

    def test_modified_data_cannot_start_training(self):
        out = self.root / 'compiled'
        build(self.manifest, self.plan, out)
        with (out / 'test.jsonl').open('a') as f: f.write('{}\n')
        with self.assertRaisesRegex(ValueError, 'Data changed'):
            training_args(out, self.root / 'base-small', self.root / 'run', self.root / 'cache')

    def test_duplicate_speaker_id_cannot_cross_splits(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate speaker'):
            validate(self.manifest, self.speakers + [{**self.speakers[0], 'split': 'test'}])


if __name__ == '__main__': unittest.main()
