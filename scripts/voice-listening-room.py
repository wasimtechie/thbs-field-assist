#!/usr/bin/env python3
"""Build a local listening page from measured samples; no external resources."""
import html
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT/'.local/voice-lab'


def main():
    panels = []
    for path in sorted((LAB/'results').glob('*/metrics.json')):
        m = json.loads(path.read_text())
        rows = m['records']
        warm = [r for r in rows if r['round'] > 1] or rows[1:] or rows
        warm_label = 'Warm first PCM' if any(r['round'] > 1 for r in rows) else 'Initial PCM · no warm sample'
        clips = []
        for r in rows:
            if r['round'] != 1:
                continue
            clips.append(f'<article><span>{html.escape(r["promptId"].upper())}</span><p>{html.escape(r["text"])}</p><audio controls preload="none" src="results/{path.parent.name}/{r["audioFile"]}"></audio></article>')
        panels.append(f'''<section><span class="eyebrow">SYNTHETIC FTTP PROMPTS · {html.escape(path.parent.name)}</span><h2>{html.escape(m['model'])}</h2><p>Voice: {html.escape(m['voice'])} · Revision {html.escape(str(m['revision'])[:12])} · {len(rows)} completed samples</p><p>{html.escape(json.dumps(m.get('settings',{})))}</p>
        <div class="stats"><div><strong>{statistics.median(r['firstChunkMs'] for r in warm):,.0f} ms</strong>{warm_label}</div><div><strong>{statistics.median(r['realTimeFactor'] for r in warm):.2f}</strong>Generation / audio duration ↓</div><div><strong>{max(r['peakRssMB'] for r in rows):,.0f} MB</strong>Process peak RSS</div></div>
        <details><summary>Listen to {len(clips)} shared prompts</summary>{''.join(clips)}</details></section>''')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Field Assist · Voice studio</title><style>
    *{box-sizing:border-box}body{margin:0;background:#f5f5fa;color:#252b3d;font:16px/1.55 system-ui,sans-serif}main{max-width:1000px;padding:60px 24px;margin:auto}header{padding-bottom:24px}h1{font-size:clamp(32px,5vw,58px);line-height:1.1;letter-spacing:-2px;margin:18px 0}h2{font-size:22px;overflow-wrap:anywhere}p{color:#68758b}.eyebrow{font-size:11px;letter-spacing:2px;color:#7660d8;font-weight:700}section{background:white;border:1px solid #e2e2f2;border-radius:24px;padding:28px;margin:20px 0}.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin:26px 0}.stats div{background:#f6f3ff;padding:16px;border-radius:16px;color:#6a6680;font-size:13px}strong{display:block;font-size:26px;color:#5540ac}details{border-top:1px solid #e9e5f4;padding-top:20px}summary{cursor:pointer;font-weight:600}article{padding:20px 0;border-bottom:1px solid #efedf5}article span{font-size:11px;letter-spacing:1.5px;color:#7462b8}audio{width:100%}footer{font-size:13px;color:#68758b}.note{background:#eae5fa;border-radius:16px;padding:20px} @media(max-width:600px){.stats{grid-template-columns:1fr}main{padding-top:30px}}
    </style><main><header><span class="eyebrow">THBS FIELD ASSIST / LOCAL VOICE STUDIO</span><h1>A voice that helps<br>finish the visit.</h1><p>Compare the same five prompts. Listen for naturalness, negation, technical pronunciation and a calm pace.</p></header>
    <div class="note">These are labelled, model-generated recordings for listening tests. Playback here uses saved WAV files. It does not demonstrate live model latency or a model running on a phone.</div>'''+''.join(panels)+'''
    <footer><p>Measured on an Apple M2 Pro, 16 GB Mac while the development workspace was active. Exploratory local measurements, not controlled device benchmarks or published model scores. First PCM is the first generated audio buffer, not first audible speech; it excludes model loading, transport and playback. Real-time factor = generation time ÷ audio duration; below one is needed to sustain real time without buffering. Kokoro and Ming return complete utterances. Process RSS and MLX GPU allocation are separate, overlapping measurements.</p><p>The app still needs on-device recognition, grounded conditional questions and engineer confirmation. No microphone recording, customer data or Openreach system is involved in these samples.</p></footer></main></html>'''
    (LAB/'index.html').write_text(page)
    print(LAB/'index.html')


if __name__ == '__main__':
    main()
