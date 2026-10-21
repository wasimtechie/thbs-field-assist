/** Shared frame-based cues for the Player, burned-in captions and SRT export. */
export function createCaptionCues(narration, seconds, fps = 30) {
  const normalized=narration.replace(/\bT H B S\b/g,'THBS').replace(/\bA I\b/g,'AI');
  const tokens=normalized.split(/\s+/).filter(Boolean).map(text=>({text,weight:text==='THBS'?4:text==='AI'?2:1}));
  const total=tokens.reduce((sum,token)=>sum+token.weight,0);
  const groups=[];let words=[];let weight=0;
  for(const token of tokens) {
    if(words.length&&(weight+token.weight>12||[...words,token.text].join(' ').length>78)) {
      groups.push({text:words.join(' '),weight});words=[];weight=0;
    }
    words.push(token.text);weight+=token.weight;
  }
  if(words.length)groups.push({text:words.join(' '),weight});
  let consumed=0;
  return groups.map(group=>{
    const startFrame=18+Math.round(seconds*fps*consumed/total);
    consumed+=group.weight;
    const endFrame=18+Math.round(seconds*fps*consumed/total);
    const parts=group.text.split(' ');let lines=[group.text];
    if(group.text.length>58) {
      let best=Infinity;
      for(let i=1;i<parts.length;i++) {
        const candidate=[parts.slice(0,i).join(' '),parts.slice(i).join(' ')];
        const score=Math.max(...candidate.map(line=>line.length));
        if(score<best){best=score;lines=candidate;}
      }
    }
    return {startFrame,endFrame,text:group.text,lines};
  });
}
