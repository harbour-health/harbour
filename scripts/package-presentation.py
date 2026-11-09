#!/usr/bin/env python3
"""Package the playable presentation and editable source without local test/build logs."""
import argparse,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--directory',type=Path,default=ROOT/'docs/presentation')
p.add_argument('--output',type=Path,default=ROOT/'build/harbour-presentation.zip')
a=p.parse_args();a.output.parent.mkdir(parents=True,exist_ok=True)
if not (a.directory/'harbour-demo.mp4').exists():p.error('Export the finished widescreen video first.')
source_scripts=['build-presentation.py','serve-presentation.py','record-presentation.py','export-presentation-video.cjs']
readme='''# Harbour presentation\n\nOpen index.html for offline slides and embedded video. Arrow keys navigate; Explain lifts actual UI pixels out of the phone. The PDF is a static backup.\n\nEditable source is in source/presentation and source/scripts. To rebuild from this bundle (requires Typst 0.14.2+):\n\n    python3 source/scripts/build-presentation.py --recording media --output rebuilt\n\nThe source files use pinned Touying 0.7.3. Edit harbour.typ for slides, slides.json for notes/timing, player.js/styles.css for animations, and build-presentation.py for actual-capture crops/callouts. The 10-minute timing totals 600 seconds.\n\nLive capture and re-recording require the full Harbour repo, the prepared QA simulator and Xcode. The native footage is real; records and saved visit summaries are fictional fixtures. Text chat uses actual local inference. Speech and clinical summary accuracy are not demonstrated by the saved fixture.\n'''
with zipfile.ZipFile(a.output,'w',compression=zipfile.ZIP_DEFLATED) as archive:
 for file in sorted(a.directory.rglob('*')):
  if file.is_file() and file.suffix!='.zip':archive.write(file,file.relative_to(a.directory))
 for file in sorted((ROOT/'presentation').glob('*')):
  if file.is_file():archive.write(file,Path('source/presentation')/file.name)
 for name in source_scripts:archive.write(ROOT/'scripts'/name,Path('source/scripts')/name)
 for file in (a.directory/'captures').glob('*.png'):archive.write(file,Path('source/docs/screenshots')/file.name)
 archive.writestr('README.md',readme)
print(f'Packaged {a.output} ({a.output.stat().st_size:,} bytes)')
