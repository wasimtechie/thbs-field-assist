import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {bundle} from '@remotion/bundler';
import {selectComposition} from '@remotion/renderer';

export const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
export async function prepare() {
  const serveUrl=await bundle({entryPoint:path.join(project,'src/remotion.ts'),publicDir:path.join(project,'public'),outDir:path.join(project,'.cache/bundle'),webpackOverride:(config)=>({...config,resolve:{...config.resolve,alias:{...config.resolve?.alias,'@':path.join(project,'src')}}})});
  const composition=await selectComposition({serveUrl,id:'THBS-Field-Assist',logLevel:'error'});
  return {serveUrl,composition};
}
