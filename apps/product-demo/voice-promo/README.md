# Field Assist — voice promo

A 96-second, 1920×1080, 30 fps narrated promo for the proposed embedded voice
closure assistant. Synthetic UI animation demonstrates a five-field narrative,
missing-only clarification, spoken reading corrections and engineer review.
The film also covers offline capture, integration and scoped domain fine-tuning.
The soundtrack includes an original background score and 43 timed pop, reveal,
correction and transition accents, ducked beneath speech. The product reveal
settles into a clean lockup around 10 seconds. Visible benchmark labels use
generic speech-recognition wording, with the measured ≈0.45-second scope retained.

## Watch

From the repository root, `npm run demo` opens the Player at
`http://127.0.0.1:3001/`. The previous full product walkthrough remains at
`http://127.0.0.1:3001/?film=product`. Ten chapter buttons allow scene navigation.
The film is exported as `Field-Assist-Voice-Promo.mp4` in the repository root,
with an adjacent poster, SRT and SHA-256 file. No video is published externally.

## Build

With the existing verified Kokoro assets and `.local/voice-lab/.venv` narration
environment available, run:

```sh
sh apps/product-demo/voice-promo/build.sh
```

Or, from `apps/product-demo`:

```sh
npm ci --workspaces=false
npx remotion browser ensure
npm run promo:audio
npm run promo:stills
npm run promo:render
npm run promo:verify
```

Remotion's local Chrome and FFprobe are used. Full raw-frame verification uses
`imageio-ffmpeg==0.6.0` from the existing local Python media environment (install
with `pip install -r voice-promo/requirements-media.txt` in that environment).
No system FFmpeg installation or cloud renderer is required. Narration uses the already bundled
Kokoro English v0.19 model, not an online speech service. A native Moonshine
readback utility is in `scripts/promo-voice-check.dart`. Its results concern the
synthetic film audio only and are not additional product benchmark evidence.

## Editable source

- `src/voice-promo/story.json`: words, speaker choices and minimum scene lengths.
- `scripts/promo-audio.py`: local TTS, original score, foley, two-pass mastering,
  audio-derived timing and SRT generation. Generated speaker clips are cached.
- `src/voice-promo/timing.json`: frame timings generated from real audio lengths.
- `src/voice-promo/VoicePromo.tsx`: master composition and ten scenes.
- `src/voice-promo/PhoneScreen.tsx`: explicitly illustrative synthetic app UI.
- `public/voice-promo/*.svg`: original code-drawn product artwork.
- `src/components/snap-cn/`: all requested owned components, used as follows:

| Component | Use |
| --- | --- |
| Word Gather | Opening sentence assembling into the promise |
| Portal Intro | Voice picture chip expanding into the brand reveal |
| Phone Frame | Framed capture, follow-up and correction screens |
| Screen Recording | Cropped portrait animation inside the phone |
| Dot Bloom | Scene transitions at capture, benchmark, integration and close |
| Channel Thread | Assistant / engineer dialogue, with typing and stepped scrolling |
| Capture Reveal | Review preparation and confirmation headline |
| Announce Title | Four-shot closing launch title |
| Reel Collage | Forms, terminology, voices and reading artwork |

`out/voice-promo/` contains keyframes, contact sheet, voice readback and media
verification. Frames showing Channel Thread, Reel Collage and the intermediate
Announce Title are exported separately so none is validated only by an import.
The Player and export use bundled OFL fonts with no render-time font download.

## Claims

`FACTS.md` records the 0.45-second figure and its exact scope: two synthetic
short-answer recognitions on an Android emulator, including a configured pause,
excluding capture, natural endpoint detection, extraction, TTS and playback.
It is not a full-bot or physical-phone claim. UI animation is edited for pacing
and labelled accordingly. Integration and fine-tuning remain scoped proposals;
no deployed Openreach integration, trained checkpoint, measured time saving,
battery endurance or universal device qualification is asserted.

`CREDITS.md` lists component, font, avatar and voice provenance. The earlier
product walkthrough and mobile/backend application code are preserved.
