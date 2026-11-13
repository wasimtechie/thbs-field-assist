# Source and asset provenance

The new voice-focused promo adds Word Gather, Screen Recording, Portal Intro,
Dot Bloom, Capture Reveal, Announce Title and Reel Collage to the existing Phone
Frame and Channel Thread. All nine were installed through `shadcn@4.22.1` using
the requested Snapcn registry. Fonts were adapted to bundled Inter; all registry
placeholder imagery and copy are replaced. See `voice-promo/CREDITS.md` for the
new film's complete provenance and `voice-promo/FACTS.md` for claim evidence.

- The four Snapcn components and their UI helpers were installed with `npx shadcn@4.22.0 add @snapcn/orb-swarm @snapcn/channel-thread @snapcn/phone-frame @snapcn/word-wheel`. Official docs: [Orb Swarm](https://snapcn.dev/docs/scenes/orb-swarm), [Channel Thread](https://snapcn.dev/docs/social/channel-thread), [Phone Frame](https://snapcn.dev/docs/screens/phone-frame), [Word Wheel](https://snapcn.dev/docs/text/word-wheel). The component source stays in `src/components/snap-cn/`. Project adaptations use THBS colours and bundled fonts; no default ride map or sample marketing copy appears in the film.
- Remotion 4.0.536 supplies the deterministic composition, Player and renderer. Package notices remain in `node_modules`; [Remotion licensing](https://www.remotion.dev/license) governs its use. No licence entitlement is asserted by this project.
- Inter and Inter Tight are bundled from the Google Fonts URLs recorded in `font-sources.json`. Their SIL Open Font License notices are retained in `public/fonts/*-OFL.txt`.
- Three existing avatar assets were copied from this application's bundled Alohe catalogue. The original MIT copyright/permission notice is retained at `public/avatars/LICENSE.txt`. There are no vendor captions in the product film.
- Product screenshots originate from existing local UI verification with synthetic data. `asset-manifest.json` records each source and SHA-256 hash. The illustrative sample chat and time events do not send messages or create attendance records.
- Narration is synthesized locally from `src/story.json` with the application's existing voice package. The model weights are not bundled into this demo project or sent to a cloud provider.
