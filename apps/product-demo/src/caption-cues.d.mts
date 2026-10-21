export type CaptionCue = {startFrame:number;endFrame:number;text:string;lines:string[]};
export function createCaptionCues(narration:string,seconds:number,fps?:number):CaptionCue[];
