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
def bounds(chapter,identifier):
 matches=[item for item in recording['nativeRegions'] if item['chapter'].startswith(chapter)]
 if not matches or identifier not in matches[0]['regions']:raise SystemExit(f'Missing native bounds: {chapter}/{identifier}. Re-record the updated walkthrough.')
 r=matches[0]['regions'][identifier]
 return [r['x'],r['y'],r['width'],r['height']]
def layer(rect,position,width,title,detail,radius=0,**extra):
 # Preserve aspect ratio and lift complete rendered controls/sections only.
 x,y,w,h=rect
 if min(w,h)<=0 or x<0 or y<0 or x+w>402.5 or y+h>874.5:raise SystemExit(f'Offscreen or incomplete element: {title} {rect}')
 return {'rect':dict(zip(['x','y','w','h'],rect)),'to':{'x':position[0],'y':position[1],'w':width,'h':width*h/w},'title':title,'detail':detail,'radius':radius,**extra}
scenes={
 'home':scene('home','233-guided-simple-home',[
  layer([24,196.667,354,146],[650,290],640,'Voice conversation','Speak naturally. Your words become chat messages, and the reply is spoken aloud.',30),
  layer([24,362.667,354,84],[710,610],590,'Message','Ask questions or request record changes. The local model chooses which tool to use.',26),
  layer([24,466.667,354,84],[760,820],540,'Record a visit','Start recording immediately. Afterwards, review the summary and proposed medication changes.',26)]),
 'readings':scene('readings','237-guided-readings',[
  layer(bounds('237-','chatReadingsTable'),[710,290],520,'Blood pressure',
    'The whole result card comes from saved records.',24,annotations=[
     {'title':'Saved readings','detail':'Dates, units and measurements come from the record store. The model does not invent table values.','anchor':0.12,'labelY':310},
     {'title':'A local tool call','detail':'The request was freeform text. Alex selected list_readings to retrieve these measurements.','anchor':0.48,'labelY':550},
     {'title':'One set of records','detail':'Chat and the caregiver interface read the same data. New readings can be entered in Records.','anchor':0.85,'labelY':790}])]),
 'caregiver':scene('caregiver','250-guided-caregiver-home',[
  # This VStack exposes its label as an AX descendant, not the rendered card bounds.
  layer([24,226.667,354,250.667],[650,290],430,'Latest reading','The most recent measurement, its timestamp and a chart of earlier values.',28,labelY=300),
  # Artwork extends beyond accessibility bounds. Clip each complete tile to its visible rounded edge.
  layer([24,566.667,170,190],[680,650],250,'Medications','Save a medicine’s identity, dose, directions, frequency and scheduled times.',28,edge='top',anchor=0,labelY=565),
  layer([208,566.667,170,190],[1030,650],250,'Symptoms','Keep a dated description, onset, severity and any reported warning signs.',28,anchor=0.7,labelY=815)]),
 'records':scene('records','240-guided-caregiver-records',[
  layer(bounds('240-','record-category-0'),[650,290],620,'Symptoms','Review earlier symptoms and add a new symptom record.',labelY=300),
  layer(bounds('240-','record-category-1'),[670,465],600,'Medications','Edit doses and schedules. Interaction checks cover listed pairs only.',labelY=475),
  layer(bounds('240-','record-category-2'),[690,640],580,'Readings','Save dated blood pressure, pulse, temperature and other readings.',labelY=650),
  layer(bounds('240-','record-category-3'),[710,815],560,'Appointments','Save dates, locations and questions to prepare for a visit.',labelY=825)]),
 'medication':scene('medication','244-guided-medicine-confirmation',[
  layer([8,170,386,696],[770,290],360,'Add medicine','The complete editor stays together.',54,annotations=[
   {'title':'Name and ingredients','detail':'Choose the intended medicine from Health Canada names. A similar-sounding suggestion needs a decision.','anchor':0.22,'labelY':305},
   {'title':'Check the product','detail':'Confirm the exact identity and ingredients against the package. Save stays disabled until checked.','anchor':0.46,'labelY':550},
   {'title':'Directions and schedule','detail':'Store label instructions, frequency and dose times in the same editor. Nothing is saved by a suggestion alone.','anchor':0.82,'labelY':790}])]),
 'visit':scene('visit','247-guided-visit-review',[
  layer([8,380,386,486],[710,290],500,'Medication changes','The complete review drawer stays together.',54,annotations=[
   {'title':'Proposed change','detail':'The review names the medicine and shows its dose, frequency and timing together. This saved example updates amlodipine.','anchor':0.26,'labelY':305},
   {'title':'Review directions','detail':'Open Instructions to check the proposed details. Visit summaries also retain follow-up actions for review.','anchor':0.55,'labelY':550},
   {'title':'Confirm before saving','detail':'Select the intended change and acknowledge the instructions. The saved medication changes only after confirmation.','anchor':0.83,'labelY':790}])])}
for key,shot in scenes.items():
 shot['holdMs']=20000 if key=='records' else 17000
 shot['completeElements']=True
manifest={'slides':slides,'recording':recording,'scenes':scenes,'source':'Touying 0.7.3, native XCTest screenshots and unaccelerated Simulator footage','cropUnits':'Logical points on the captured 402 × 874 screen. Complete native cards, record rows and drawers only. No partial table or individual text fragments. All lifts preserve aspect ratio; artwork overflowing a tile is clipped at its genuine rounded boundary.'}
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
for filename in ['styles.css','player.js']:shutil.copy2(ROOT/'presentation'/filename,out/filename)
html=(ROOT/'presentation/index.html').read_text().replace('__MANIFEST__',json.dumps(manifest,ensure_ascii=False).replace('</','<\\/'))
(out/'index.html').write_text(html)
(out/'speaker-notes.md').write_text('# Harbour — 10-minute presenter notes\n\n'+'\n\n'.join(f'## {i+1}. {s["title"]} · {s["seconds"]} seconds\n\n{s["notes"]}' for i,s in enumerate(slides)))
print(f'Built {len(slides)} slides, offline HTML, native video and PDF backup in {out}')
