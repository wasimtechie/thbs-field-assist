# THBS Field Assist website — 15 October 2026

The website is now presented as a Torry Harris team demonstration under the product name **THBS Field Assist**. The shared header/sidebar/login/footer lockup and browser metadata use the new name. The existing indigo, teal, warm light canvas, radio mark and robot are retained. This is a product wordmark, not a recreated corporate logo. The Flutter application and package identifiers are unchanged by this website request.

## Home page

The existing field-reporting hero, workflow controls, product principles and workspace destinations remain. New content introduces Torry Harris Business Solutions, its industry experience, four capability areas, a client delivery journey and an explanation of how this demo applies connected engineering to field reporting.

The four capabilities are integration/APIs, cloud modernization, data/intelligent automation and digital platforms/ecosystems. Selecting a row changes the highlighted SVG nodes, outcome caption and link to the corresponding official service page. Every capability description remains readable without selecting a row. The delivery journey describes Understand, Architect, Engineer and Evolve in plain language; it does not claim to be a named proprietary THBS methodology.

The demo description states that reports flow into the THBS Field Assist workspace. It does not imply an ERP/CRM integration or client deployment that this demo does not implement. No customer endorsements, client logos, ROI metrics or invented company statistics were added.

## Motion and accessibility

The supplied prompt is used as a motion/style reference. The user's explicit request to add company content and retain the existing colors governs the edit. The reference's proposed navy/cyan palette and corporate-site rewrite are not applied.

The existing Motion library drives selected-node springs, restrained pointer tilt and scroll-progress SVG connection drawing. CSS sequences the hero headline and supporting copy. All text remains in server-rendered HTML. Scroll remains natural; no pinned sequence or scroll interception is introduced. The isometric figures are original SVG code inspired by the reference's visual language, not imported Hairline components. No GSAP, Hairline, 3D framework or runtime dependency was added.

Pointer tilt is mouse-only and anchored to the illustration panel. Capability buttons work through normal click/tap and keyboard activation. Existing workflow arrow-key navigation remains intact. Reduced Motion disables CSS entrances, SVG tilt/node translation and line drawing, while preserving full content. Matching first-render markup avoids hydration errors when Reduced Motion is enabled before the page loads. New primary text uses an existing muted indigo tone with at least 4.65:1 contrast on its section backgrounds.

## Company sources

Content is paraphrased from official Torry Harris pages inspected on 15 October 2026. These links are also available from the relevant website sections:

- [Corporate overview](https://www.torryharris.com/about-us/corporate-overview)
- [Application integration and orchestration](https://www.torryharris.com/services/application-integration-and-orchestration)
- [Managed cloud and governance](https://www.torryharris.com/services/managed-cloud-and-governance)
- [Data, intelligence and agentic AI](https://www.torryharris.com/services/data-intelligence-and-agentic-ai)
- [Digital marketplace implementation](https://www.torryharris.com/services/digital-marketplace-implementation)
- [Conceptualization and build](https://www.torryharris.com/global-capability-center/conceptualization-build)
- [Operational excellence](https://www.torryharris.com/global-capability-center/operational-excellence)
- [Hairline visual reference](https://github.com/lucasmarkes/hairline)

## Verification

- TypeScript check and production build pass. Build evidence: `../evidence/thbs-{typecheck,production-build}.log`.
- Inspected 1440 px desktop and 390 px mobile layouts. Also checked 320 px header/content bounds without horizontal overflow or overlapping header links.
- All four capability selections were exercised across click and keyboard activation; captions and official links update correctly. Existing reporting tabs respond to Arrow Down.
- Reduced Motion was enabled before a fresh load: hero animation and illustration transform are `none`, mascot motion is inactive, content remains available and no hydration errors are logged. The temporary media preference was restored after testing.
- Scroll drawing changed from a `0.15 1` to `1 1` stroke dash array as the section was scrolled. No measured animation frame-rate claim is made.
- Workspace sign-in navigation reaches the existing authenticated dashboard with the new shared brand. The current user's session was retained.
- Local preview only. No backend, report data, account access or external deployment was changed by this website edit.

Browser screenshots are saved as `../evidence/thbs-home-{desktop,mobile}.jpg`, `thbs-company-desktop.jpg`, `thbs-capabilities-{desktop,mobile}.jpg` and `thbs-delivery-mobile.jpg`.
