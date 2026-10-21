#!/usr/bin/env python3
"""Inspect shipped ARM64 ELF load alignment. Does not replace a 16 KiB device test."""
import pathlib,sys,zipfile,tempfile,subprocess,re,json,os
root=pathlib.Path(__file__).resolve().parents[1]
apk=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else root/'apps/mobile/build/app/outputs/flutter-apk/app-debug.apk')
sdk=pathlib.Path(os.environ.get('ANDROID_HOME',str(pathlib.Path.home()/'Library/Android/sdk')))
tools=list(sdk.glob('ndk/28.2.13676358/toolchains/llvm/prebuilt/*/bin/llvm-readelf'))
if not tools:raise SystemExit('Install the pinned NDK 28.2.13676358 to inspect ELF headers.')
results=[]
with tempfile.TemporaryDirectory() as directory,zipfile.ZipFile(apk) as archive:
 for name in archive.namelist():
  if not name.startswith('lib/arm64-v8a/') or not name.endswith('.so'):continue
  file=pathlib.Path(directory)/pathlib.Path(name).name;file.write_bytes(archive.read(name))
  output=subprocess.check_output([str(tools[0]),'-lW',str(file)],text=True)
  alignments=[int(line.split()[-1],0) for line in output.splitlines() if line.strip().startswith('LOAD ')]
  result=dict(library=name,loadAlignments=alignments,aligned16KiB=bool(alignments) and all(a>=16384 for a in alignments))
  results.append(result)
report=dict(scope='ELF header inspection only; real 16 KiB Android device validation pending',libraries=results,allAligned=bool(results) and all(r['aligned16KiB'] for r in results))
(root/'docs/evidence/android-native-alignment.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
sys.exit(0 if report['allAligned'] else 1)
