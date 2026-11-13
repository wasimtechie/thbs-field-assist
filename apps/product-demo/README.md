# THBS Field Assist product film

The current Player opens the **96-second voice promo**. Its source, nine Snapcn
animations, build commands, claim limits and delivery files are documented in
[voice-promo/README.md](voice-promo/README.md). Open `?film=product` for the earlier
full walkthrough described below. `npm run promo:render` exports the voice promo;
the existing `npm run render` continues to export the earlier walkthrough.

A 2:42, 1920 × 1080, 30 fps narrated product walkthrough with 13 navigable chapters and visible English captions. Uses the requested Snapcn **Orb Swarm**, **Channel Thread**, **Phone Frame**, and **Word Wheel** as owned Remotion source. The original purple/teal palette is retained. This standalone project does not add runtime video dependencies to the dashboard or Flutter app.

## Watch and edit

From the repository root:

```sh
npm run demo
```

Open **http://localhost:3001/**. The preview listens only on laptop loopback. Use **Present fullscreen**, normal playback controls, or the chapter buttons to jump to a feature.

```sh
npm run demo:studio
npm run demo:render
```

Studio exposes the Remotion composition and timeline. Rendering writes `THBS-Field-Assist-Demo.mp4` and its `.srt` beside the repository README. The MP4 has H.264 picture, AAC narration and burned-in English captions, so they appear automatically in every player. The separate SRT remains editable; a second embedded subtitle track is omitted to prevent duplicate captions in players that automatically enable it. Captions use a dark high-contrast panel, a maximum of two lines, and the same frame cues in the preview and export. Scene footer metadata is hidden while a caption is visible to avoid overlap; operational notes remain readable. No cloud renderer or publishing service is used. The local Remotion browser is required (`npx remotion browser ensure` from this directory on a fresh setup). FFmpeg must be available on PATH.

For a fresh dependency installation, use `npm ci --prefix apps/product-demo --workspaces=false` from the root. This project has its own package lock and is intentionally separate from the application workspaces.

## Story and benefit

| Chapter | Why it helps |
| --- | --- |
| Intro / Orb Swarm | Establishes one connected client-to-field journey. |
| Client to assignment | Routes client work to a squad and named engineer with a clear brief, priority and due date. |
| Engineer workspace / Phone Frame | Gives the engineer a focused assignment list and makes acceptance or decline visible to the lead. |
| Site time and location | Adds check-in, breaks, check-out and arrival/departure context to a visit. |
| Cable scanning / Phone Frame | Reduces retyping of printed cable identifiers while retaining review and correction. |
| Guided voice / Phone Frame | Guides relevant work questions and saves validated answers locally. |
| Offline to received | Explains encrypted drafts, explicit confirmation, stable queued delivery and separate review. |
| Messaging / Channel Thread | Connects engineers and colleagues through direct/squad conversations and fuzzy discovery. |
| Supervisor review | Keeps human approval and follow-up decisions linked to original evidence and asset visits. |
| Operations AI | Provides source-linked summaries, editable visit briefs and evidence-gap suggestions. |
| People and access | Makes departments, squads and reporting lines discoverable while keeping operational access scoped. |
| Feature reel / Word Wheel | Brings together reusable forms, profiles, themes and project structure. |
| Closing | Recaps clear ownership, connected teams and traceable evidence. |

## Source map

- `src/Film.tsx`: scenes, workflow illustrations, actual product screenshots, composition registration.
- `src/visuals.tsx`: shared THBS palette, typography, screen framing, entrances and callouts.
- `src/components/snap-cn/`: the four installed Snapcn components.
- `src/lib/snap-cn-ui/`: installed helpers; font loading adapted to bundled open-licensed Inter files.
- `src/story.json`: chapter order and narration text.
- `src/narration-timings.json`: actual generated audio durations; the timeline leaves room for every line.
- `src/timeline.ts`: deterministic scene boundaries.
- `src/Captions.tsx` and `src/caption-cues.mjs`: visible captions and shared frame timing for the Player, video and SRT; abbreviations display as THBS/AI.
- `src/main.tsx`: responsive Player, chapter navigation and fullscreen action.
- `public/screens/`: existing screenshots, with origins/hashes in `asset-manifest.json`.
- `public/audio/`: narration generated with the existing local voice engine; no microphone or external account used.
- `scripts/`: still capture, local rendering, subtitle export and Player checks.

Narration can be regenerated with `dart run tool/product_demo_narration.dart <model-assets-path> <absolute-product-demo-path>` from `apps/mobile`. Re-render after changing narration so the audio, timeline and subtitles stay aligned. Subtitle timing is distributed by words within each synthesized chapter, rather than forced word alignment.

## Evidence and scope

TypeScript/production build, all chapter navigation, local assets, 390 px layout and still renders are checked. `out/player-check.json` and `out/stills/` hold preview evidence; `out/chapters.json` records timing. The final media verification is recorded in `docs/evidence/product-demo.json`.

The film uses synthetic demo records, existing product screenshots and clearly illustrative time/chat/workflow scenes. It is a product explainer, not a new physical-device acceptance test or a screen recording of a live end-to-end session. Initial provisioning needs a reachable backend; local voice/OCR operates after setup. Confirmed delivery retries while the app is open/unlocked with a reachable server. Receipt does not mean approval. Closed-app push is not configured. Dashboard AI requires internet/server configuration and cannot take operational decisions.

The installed Android build remains 2014. The separately verified voice-accuracy source repair still awaits the user's next explicit APK request. This work does not generate or install an APK or reset reports.

See `THIRD_PARTY.md` for component, font and avatar provenance.
