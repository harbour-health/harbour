#!/usr/bin/env python3
"""Record real native actions and export an unaccelerated MP4 plus genuine UI bounds."""
import argparse,json,os,re,signal,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--simulator-id',required=True)
p.add_argument('--derived-data',type=Path,default=Path('/private/tmp/harbour-launch'))
p.add_argument('--output',type=Path,default=ROOT/'build/presentation')
p.add_argument('--skip-build',action='store_true')
p.add_argument('--export-only',action='store_true',help='Reuse a passed native capture; never rerun or replace its test.')
a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)
env=dict(os.environ);env.setdefault('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer')
def run(cmd,**kw):return subprocess.run(cmd,cwd=ROOT,env=env,check=True,**kw)
base=['xcodebuild','-project','Harbour.xcodeproj','-scheme','Harbour','-destination',f'platform=iOS Simulator,id={a.simulator_id}','-derivedDataPath',str(a.derived_data),'-parallel-testing-enabled','NO','-only-testing:HarbourUITests/PresentationWalkthroughUITests/testGuidedWalkthrough','DEVELOPMENT_TEAM=8SZZPTG649','CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-']
result=a.output/'walkthrough.xcresult';raw=a.output/'native-walkthrough.mov'
if not a.export_only:
 if result.exists():p.error('Choose a fresh output directory, or --export-only for a passed capture.')
 if not a.skip_build:
  with (a.output/'build.log').open('w') as f:run(base+['build-for-testing'],stdout=f,stderr=subprocess.STDOUT)
 run(['xcrun','simctl','status_bar',a.simulator_id,'override','--time','9:41','--batteryState','charged','--batteryLevel','100'])
 recorder=None
 try:
  with (a.output/'recording.log').open('w') as f:
   recorder=subprocess.Popen(['xcrun','simctl','io',a.simulator_id,'recordVideo','--codec=h264','--force',str(raw)],env=env,stdout=f,stderr=subprocess.STDOUT)
   time.sleep(1)
   with (a.output/'test.log').open('w') as log:
    test=subprocess.Popen(base+['test-without-building','-resultBundlePath',str(result)],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    for line in test.stdout:
     log.write(line);log.flush()
     if 'WALKTHROUGH_CHAPTER' in line or 'error:' in line:print(line.strip(),flush=True)
    code=test.wait()
   if code:raise SystemExit(f'Native test failed ({code}); diagnostics retained. No success video exported.')
 finally:
  if recorder and recorder.poll() is None:
   recorder.send_signal(signal.SIGINT)
   try:recorder.wait(timeout=20)
   except subprocess.TimeoutExpired:recorder.terminate();recorder.wait(timeout=10)
  subprocess.run(['xcrun','simctl','status_bar',a.simulator_id,'clear'],env=env,check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
text=(a.output/'test.log').read_text()
if not re.search(r'\*\* TEST (?:EXECUTE )?SUCCEEDED \*\*',text):raise SystemExit('Capture has no passed native test; refusing to export it as a completed walkthrough.')
# Simulator starts the MOV when the capture file is created. Retain the basis explicitly.
started=raw.stat().st_birthtime
chapters=[{'name':name,'sourceSeconds':max(0,float(at)-started)} for name,at in re.findall(r'WALKTHROUGH_CHAPTER (\S+) ([0-9.]+)',text)]
if not chapters:raise SystemExit('No native chapters found.')
regions=[json.loads(line) for line in re.findall(r'WALKTHROUGH_REGIONS (\{[^\n]+\})',text)]
start=max(0,chapters[0]['sourceSeconds']-1);end=chapters[-1]['sourceSeconds']+2
video=a.output/'harbour-walkthrough.mp4'
with (a.output/'export.log').open('w') as log:
 run(['ffmpeg','-y','-i',str(raw),'-vf',f'fps=30,trim=start={start}:end={end},setpts=PTS-STARTPTS,scale=-2:1440','-an','-c:v','libx264','-crf','21','-preset','fast','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],stdout=log,stderr=subprocess.STDOUT)
measured=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',str(video)],text=True))
if abs(measured-(end-start))>0.25:raise SystemExit('Encoded timeline differs from the native source trim; do not use this export.')
for chapter in chapters:chapter['videoSeconds']=max(0,chapter['sourceSeconds']-start)
metadata={'source':'Real native iOS Simulator video driven by XCTest','fixture':'Fictional saved records and authored visit summaries; real local chat tool inference','audio':'Silent; microphone and speech output are not evaluated','timing':'Real time, no accelerated waits; timestamp origin is MOV file creation','video':video.name,'chapters':chapters,'nativeRegions':regions,'edits':[{'sourceStart':start,'sourceEnd':end,'speed':1,'outputStart':0}],'durationSeconds':end-start}
(a.output/'walkthrough.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(f'Exported {video} ({end-start:.1f}s). Raw capture and native test retained.',flush=True)
