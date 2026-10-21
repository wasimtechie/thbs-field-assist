import story from './story.json';
import timings from './narration-timings.json';

export const FPS = 30;
export const WIDTH = 1920;
export const HEIGHT = 1080;
let cursor = 0;
export const chapters = story.map((scene, index) => {
  const voice = timings[scene.id as keyof typeof timings];
  const durationInFrames = Math.ceil(Math.max(scene.minSeconds, voice.seconds + 2) * FPS);
  const result = {...scene, index, from: cursor, durationInFrames};
  cursor += durationInFrames;
  return result;
});
export const DURATION = cursor;
export type Chapter = (typeof chapters)[number];
