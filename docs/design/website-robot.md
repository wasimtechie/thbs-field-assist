# Website robot mascot

The landing page uses `RobotMascot` from `apps/admin/src/components/robot-mascot.tsx`. The ivory shell, indigo visor and teal details match Field Assist. The raster visor has no baked eyes: two independent glowing SVG eye shapes provide the expression and gaze.

```tsx
<RobotMascot
  size={240}
  placement="inline"
  colors={{eyes: '#b1ffe6', glow: '#159c8b', halo: '#dcd5f5'}}
/>
```

`size` accepts pixels or a CSS length; `placement` accepts `inline`, `bottom-left`, or `bottom-right`. `className`, `label`, `bodyHue`, and `animate` are optional. The landing page uses a responsive anchored wrapper: 245 px on desktop, 215 px on tablet and 180 px on mobile. Customize the live eye and halo colors with `colors`; use `bodyHue` for a hue adjustment to the rendered body.

Pointer movement uses each eye's own center, constrained travel, and eased `requestAnimationFrame` updates that stop when settled. Touch down/move updates the gaze; release returns it to neutral. Nearby pointers produce a small tilt around the base without moving the component's anchor. CSS handles subtle breathing and randomized blinks. A keyboard accessible pause button is revealed on hover/focus and shown on touch devices. Reduced motion, offscreen visibility and hidden tabs stop the motion. Unmounting clears listeners, observers, frames and timers. No new animation dependency was added.

Artwork: `apps/admin/public/mascot/field-assist-robot.png`, generated with the built-in image generation tool using the user's robot image as a visual reference. It is a 1254 × 1254 RGBA transparent PNG. The generation prompt follows.

```text
Use case: stylized-concept.
Asset type: transparent 3D robot body for an interactive website mascot.
Input image 1 is a visual style reference, not an edit target. Create a rounded friendly robot inspired by its smooth ivory shell, oversized glossy oval visor, small ear modules, compact floating body and one raised arm waving.
Adapt the palette to Field Assist: warm ivory #f7f5ef shell, deep indigo #30276f visor with a lavender #6452c4 edge, restrained teal #159c8b chest and ear accents. Soft warm studio lighting, polished premium toy render, smooth satin material, subtle realistic depth and highlights.
IMPORTANT: the visor must be completely blank, without eyes, pupils, eyebrows, mouth, icons or facial graphics. The website will overlay two live glowing SVG eyes. Keep the visor approximately front-facing and symmetrical, spanning x=27–73% and y=24–46% of the square canvas; the robot head upright. One gently waving arm at viewer's right, the other relaxed. Full body centered with modest clear padding, no cropping. Transparent background with clean alpha. No colored backdrop, ground plane, text, logos, extra objects or baked eye glow.
```

## Verification

- `npm run typecheck` passed.
- Browser inspection and screenshots at 1440 × 1000 and 390 × 844 confirmed asset loading, eye alignment, anchored size and mobile layout without horizontal overflow.
- Pointer input produced independent offsets: left `(-7.347, -3.441)`, right `(-7.499, -3.249)`, inside the permitted travel.
- Enter on the pause control set `aria-pressed=true`, stopped motion and reset both eyes to zero. Enter resumed it.
- Emulated reduced motion stopped CSS animations and reset both eyes. The browser preference override and viewport override were cleared afterward.
- Touch pointer handlers are implemented, but this in-app browser does not expose touch dispatch; a physical touch-device interaction was not verified.
- Evidence: `docs/evidence/website-robot-desktop.jpg`, `docs/evidence/website-robot-mobile.jpg`, `docs/evidence/robot-typecheck.log`.
