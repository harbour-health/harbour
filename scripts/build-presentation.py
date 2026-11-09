#!/usr/bin/env python3
"""Build Touying slides plus an offline HTML scene using actual app captures and video."""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--recording',type=Path,required=True,help='Passed capture directory from record-presentation.py')
p.add_argument('--output',type=Path,default=ROOT/'docs/presentation')
a=p.parse_args();(ROOT/'build').mkdir(exist_ok=True);out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
slides=json.loads((ROOT/'presentation/slides.json').read_text());recording=json.loads((a.recording/'walkthrough.json').read_text())
if sum(s['seconds'] for s in slides)!=600:raise SystemExit('This version must retain the requested 10-minute timing.')
for folder in ['slides','captures','media']:(out/folder).mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='harbour-slides-',dir=ROOT/'build') as tmp:
 tmp=Path(tmp)
 base=['typst','compile','--root',str(ROOT),'--package-cache-path',str(ROOT/'build/typst-packages')]
 subprocess.run(base+['--format','svg',str(ROOT/'presentation/harbour.typ'),str(tmp/'slide-{n}.svg')],check=True)
 pages=sorted(tmp.glob('slide-*.svg'),key=lambda p:int(p.stem.split('-')[-1]))
 if len(pages)!=len(slides):raise SystemExit(f'Slide count mismatch: {len(pages)} SVGs / {len(slides)} content records.')
 for i,page in enumerate(pages,1):shutil.copy2(page,out/'slides'/f'slide-{i:02}.svg')
 subprocess.run(base+['--input','print=true',str(ROOT/'presentation/harbour.typ'),str(out/'harbour.pdf')],check=True)
shutil.copy2(a.recording/'harbour-walkthrough.mp4',out/'media/harbour-walkthrough.mp4')
shutil.copy2(a.recording/'walkthrough.json',out/'media/walkthrough.json')
def scene(name,capture,layers):
 source=ROOT/'docs/screenshots'/f'{capture}.png'
 if not source.exists():raise SystemExit(f'Missing genuine screenshot: {source}')
 shutil.copy2(source,out/'captures'/source.name)
 return {'image':f'captures/{source.name}','screen':{'width':402,'height':874},'layers':layers}
def layer(rect,to,title,detail):return {'rect':dict(zip(['x','y','w','h'],rect)),'to':dict(zip(['x','y','w','h'],to)),'title':title,'detail':detail}
scenes={
 'home':scene('home','233-guided-simple-home',[
  layer([24,196.667,354,146],[650,300,640,264],'Voice conversation','A large entry point for spoken requests.'),
  layer([24,362.667,354,84],[710,620,590,140],'Freeform chat','The local model chooses the appropriate tool.'),
  layer([24,466.667,354,84],[760,820,540,128],'Doctor visit','Record once, then review the proposed changes.')]),
 'readings':scene('readings','237-guided-readings',[
  layer([24,258.333,164,58],[720,290,480,170],'Read-only tool','The model selected list_readings.'),
  layer([24,316.333,164,114],[650,500,420,292],'Stored measurements','Dates and values are fetched from saved records.'),
  layer([24,555,164,28],[730,850,420,72],'Shared records','The caregiver interface uses the same readings.')]),
 'medication':scene('medication','244-guided-medicine-confirmation',[
  layer([25,278,352,100],[670,300,600,170],'Name and ingredients','An exact database identity follows a deliberate choice.'),
  layer([23.363,456.955,355.274,84.818],[710,570,570,136],'Product check','The user checks the product before it can be saved.'),
  layer([314.944,190.02,59.852,34.567],[930,820,160,92],'Nothing saved yet','Save remains disabled until the product is checked.')]),
 'visit':scene('visit','247-guided-visit-review',[
  layer([31,478,340,30],[670,300,600,53],'Proposed change','A saved demo proposal, not a live extraction claim.'),
  layer([31,510,340,115],[650,450,600,203],'Directions','Dose, frequency and time remain separate.'),
  layer([31,685,340,96],[700,760,600,169],'Confirmation','The proposal stays unsaved until reviewed.')])}
for part,radius in zip(scenes['home']['layers'],[30,26,26]):part['radius']=radius
scenes['visit']['layers'][2]['radius']=22
manifest={'slides':slides,'recording':recording,'scenes':scenes,'source':'Touying 0.7.3, native XCTest screenshots and unaccelerated Simulator footage','cropUnits':'Logical points on the captured 402 × 874 screen. Visible card bounds are clipped to their real edges; AX bounds can include clipped decorative artwork.'}
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
for filename in ['styles.css','player.js']:shutil.copy2(ROOT/'presentation'/filename,out/filename)
html=(ROOT/'presentation/index.html').read_text().replace('__MANIFEST__',json.dumps(manifest,ensure_ascii=False).replace('</','<\\/'))
(out/'index.html').write_text(html)
(out/'speaker-notes.md').write_text('# Harbour — 10-minute presenter notes\n\n'+'\n\n'.join(f'## {i+1}. {s["title"]} · {s["seconds"]} seconds\n\n{s["notes"]}' for i,s in enumerate(slides)))
print(f'Built {len(slides)} slides, offline HTML, native video and PDF backup in {out}')
