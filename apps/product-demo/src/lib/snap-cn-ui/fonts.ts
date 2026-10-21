"use client";
import {continueRender, delayRender, staticFile} from "remotion";

// Project adaptation: one bundled Inter face, no network font requests at render.
if (typeof document !== "undefined" && typeof FontFace !== "undefined") {
  const handle = delayRender("Load bundled product-demo font");
  const face = new FontFace("Inter", `url(${staticFile("fonts/inter.woff2")}) format("woff2")`, {weight: "100 900"});
  face.load().then((loaded) => { document.fonts.add(loaded); continueRender(handle); }).catch((error) => { console.error(error); continueRender(handle); });
}
export const FONTS: Record<string, string> = {Inter: "Inter"};
export const DEFAULT_FONT = "Default";
export const FONT_NAMES = [DEFAULT_FONT, ...Object.keys(FONTS)];
export const resolveFont = (name?: string): string | undefined => !name || name === DEFAULT_FONT ? undefined : (FONTS[name] ?? name);
