#!/usr/bin/env python3
"""Plan an upstream Small Streaming LoRA run; execution is explicit, on CUDA."""
import argparse
import importlib.metadata
import json
import subprocess
import sys
from pathlib import Path
from dataset import sha

ROOT = Path(__file__).resolve().parents[2]
LOCK = json.loads((ROOT / 'fixtures/voice/training/sources.lock.json').read_text())


def training_args(data, base, output, work):
    report = json.loads((data / 'dataset-report.json').read_text())
    for name, expected in {**report['manifestSha256'], **report['audioSha256']}.items():
        if sha(data / name) != expected:
            raise ValueError(f'Data changed since validation: {name}')
    return ['--model', str(base), '--train-manifest', str(data / 'train-dev.jsonl'),
            '--eval-manifest', str(data / 'test.jsonl'), '--data-root', str(data),
            '--output-dir', str(output), '--work-dir', str(work),
            '--adapt', 'lora', '--sites', 'both', '--rank', '8', '--lr', '1e-4',
            '--batch-size', '4', '--max-steps', '3000', '--patience', '4',
            '--dev-hours', str(report['devHours']), '--text-mode', 'none',
            '--replay-ratio', '0.5', '--eval', '--canary', '--device', 'cuda', '--seed', '42']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dataset', type=Path)
    parser.add_argument('--base-dir', type=Path, default=ROOT / '.local/moonshine-training/base-small')
    parser.add_argument('--output', type=Path, default=ROOT / '.local/moonshine-training/candidate-both')
    parser.add_argument('--stage-base', action='store_true', help='Download only the pinned official checkpoint; no recordings are uploaded')
    parser.add_argument('--execute', action='store_true', help='Actually train; requires validated human audio and a CUDA training environment')
    args = parser.parse_args()
    base, output = args.base_dir.resolve(), args.output.resolve()
    if args.stage_base:
        if base.exists(): raise ValueError('Choose a new base directory; do not overwrite a checkpoint')
        from huggingface_hub import snapshot_download
        snapshot_download(LOCK['baseModel'], revision=LOCK['baseRevision'], local_dir=base,
                          allow_patterns=['*.json', '*.safetensors', '*.txt', '*.model'])
        (base / 'field-assist-source.json').write_text(json.dumps(LOCK, indent=2) + '\n')
        print('Pinned Small checkpoint staged. No training has run.')
        return
    if args.dataset is None: parser.error('--dataset is required, or use --stage-base')
    data = args.dataset.resolve()
    fingerprint = sha(data / 'dataset-report.json')[:16]
    cmd_args = training_args(data, base, output, output.parent / ('work-' + fingerprint))
    cmd = [sys.executable, '-m', 'moonshine_voice.lora', *cmd_args]
    plan = {'status': 'planned_not_trained', 'baseModel': LOCK['baseModel'], 'revision': LOCK['baseRevision'],
            'dataReportSha256': sha(data / 'dataset-report.json'), 'command': cmd}
    print(json.dumps(plan, indent=2))
    if not args.execute: return
    if output.exists(): raise ValueError('Choose a fresh output directory; existing runs are retained')
    staged = json.loads((base / 'field-assist-source.json').read_text())
    if staged != LOCK: raise ValueError('Base checkpoint does not match the pinned Small model')
    if importlib.metadata.version('moonshine-voice') != LOCK['runtimeVersion']:
        raise ValueError('Install the pinned training environment first')
    import torch
    if not torch.cuda.is_available(): raise ValueError('Use a CUDA GPU training environment; this Mac is for offline inference and data preparation')
    subprocess.run(cmd, check=True)
    # A trained checkpoint is still a candidate, never an automatically shipped model.
    (output / 'field-assist-training-plan.json').write_text(json.dumps({**plan, 'status': 'trained_candidate_requires_evaluation_and_export'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
