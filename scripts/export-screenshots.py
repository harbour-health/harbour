#!/usr/bin/env python3
"""Export numbered, genuine XCTest attachments into the local review gallery."""
import argparse
import html
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

TITLES = {
    '01-today': 'Today', '02-symptoms': 'Symptoms', '03-medicines': 'Medicines',
    '04-readings': 'Readings', '05-add-reading': 'Add a reading',
    '06-medicine-catalog': 'Medicine catalogue', '07-medicine-details': 'Medicine confirmation',
    '08-symptom-intake': 'Symptom entry', '09-symptom-review': 'Symptom review',
    '10-chat-conversation': 'Chat conversation', '11-chat-empty': 'New chat',
    '12-topics': 'Chat topics', '13-chat-topic': 'Selected topic',
    '14-models': 'Models and effort', '15-model-download': 'Model download',
    '16-settings': 'Settings', '17-evaluation': 'Evaluation', '18-export': 'Export records',
    '19-appointment-note': 'Appointment note', '20-interactions': 'Medicine interactions',
    '21-emergency-review': 'Emergency review', '22-symptom-detail': 'Saved symptom',
    '23-blood-pressure': 'Blood pressure entry', '24-temperature': 'Temperature entry',
    '25-manual-medicine': 'Unlisted medicine', '26-health-access': 'Apple Health access',
    '27-delete-confirmation': 'Delete confirmation', '28-chat-keyboard': 'Chat with keyboard',
    '29-evaluation-results': 'Evaluation results',
    '30-health-permission': 'Apple Health permission',
    '31-today-dark': 'Today · Dark', '32-chat-dark': 'New chat · Dark',
    '33-symptoms-dark': 'Symptoms · Dark', '34-medicines-dark': 'Medicines · Dark',
    '35-readings-dark': 'Readings · Dark', '36-topics-dark': 'Topics · Dark',
    '37-models-dark': 'Models · Dark', '38-settings-dark': 'Settings · Dark',
    '39-note-dark': 'Appointment note · Dark', '40-appearance-light': 'Appearance · Light',
    '41-appearance-dark': 'Appearance · Dark', '42-chat-result-dark': 'Interaction result · Dark',
    '43-system-dark': 'System appearance · Dark', '44-chat-medicines': 'Medicines in chat',
    '45-chat-medicines-dark': 'Medicines in chat · Dark', '46-chat-readings': 'Readings in chat',
    '47-chat-readings-dark': 'Readings in chat · Dark', '48-add-reading-dark': 'Reading entry · Dark',
    '49-catalog-dark': 'Medicine catalogue · Dark', '50-confirm-medicine-dark': 'Medicine confirmation · Dark',
    '51-symptom-entry-dark': 'Symptom entry · Dark', '52-symptom-review-dark': 'Symptom review · Dark',
    '53-selected-topic-dark': 'Selected topic · Dark',
    '54-app-lock-settings': 'App lock', '55-pin-setup': 'Set PIN',
    '56-pin-lock': 'Locked app', '57-pin-retry-delay': 'PIN retry delay',
    '58-generated-chat-title': 'Generated chat title',
    '59-current-pin': 'Confirm current PIN', '60-import-records': 'Import records',
    '61-pin-mismatch': 'PIN mismatch', '62-face-id-unavailable': 'Face ID unavailable',
    '63-health-access-reminder': 'Apple Health access reminder',
    '64-records': 'Records', '65-records-dark': 'Records · Dark',
    '66-floating-navigation': 'Floating navigation · scrolled',
    '67-visits': 'Visits', '68-visit-recorder': 'Visit recorder',
    '69-visit-notes': 'Visit notes', '70-visit-summary': 'Local visit summary',
    '71-visit-medicine-review': 'Visit medicine confirmation', '72-visit-transcript': 'Visit transcript',
    '142-visit-medicine-review-dark': 'Visit medicine confirmation · Dark',
    '73-visit-recording': 'Recording · audio-only simulator', '74-visit-paused': 'Paused · audio-only simulator',
    '75-visit-audio': 'Playback · audio-only simulator', '76-visits-dark': 'Visits · Dark',
    '77-visit-recorder-dark': 'Visit recorder · Dark', '78-visit-summary-dark': 'Visit summary · Dark',
    '79-reading-landscape': 'Reading drawer · Landscape', '80-pin-drawer-dark': 'PIN drawer · Dark',
    '81-reading-keyboard': 'Reading drawer · Keyboard', '82-reading-keyboard-dark': 'Reading drawer · Keyboard · Dark',
    '83-visit-notes-drawer': 'Visit notes drawer', '84-drawer-large-text': 'Reading drawer · Large text',
    '85-interactions-drawer-dark': 'Interaction drawer · Dark', '86-evaluation-drawer-dark': 'Evaluation drawer · Dark',
    '87-new-visit-notes': 'New visit notes', '88-new-visit-notes-dark': 'New visit notes · Dark',
    '89-chat-small-phone': 'Chat · Small phone', '90-reading-small-phone': 'Reading drawer · Small phone',
    '91-label-scan': 'Recognized medicine label', '92-medicine-schedule': 'Medicine schedule',
    '93-reminder': 'Reminder', '94-dose-log': 'Log a dose', '95-agenda': 'Today · Agenda',
    '96-timeline': 'Health timeline', '97-timeline-search': 'Search health history',
    '98-appointment-preparation': 'Appointment preparation', '99-agenda-dark': 'Agenda · Dark',
    '100-timeline-dark': 'Health timeline · Dark', '101-preparation-dark': 'Appointment preparation · Dark',
    '102-schedule-dark': 'Medicine schedule · Dark', '103-dose-later-dark': 'Remind later · Dark',
    '104-voice-options': 'Voice options', '105-chat-reminder-review': 'Chat · Reminder confirmation',
    '106-chat-reminders': 'Reminders in chat', '107-chat-schedule-review': 'Chat · Schedule confirmation',
    '108-chat-dose-review': 'Chat · Dose confirmation', '109-chat-history': 'Health history in chat',
    '110-chat-question-review': 'Chat · Appointment question', '111-chat-label-scan': 'Chat · Label entry',
    '112-label-entry': 'Medicine label entry', '113-voice-mode': 'Voice conversation',
    '114-voice-input-error': 'On-device voice unavailable', '115-notification-setting': 'Reminder notifications', '116-today-large-text': 'Today · Largest text',
    '117-french-today': 'Aujourd’hui · Français', '118-french-chat': 'Conversation · Français',
    '119-french-records': 'Dossier · Français', '120-french-visits': 'Consultations · Français',
    '121-french-today-dark': 'Aujourd’hui · Français · Sombre', '122-french-chat-dark': 'Conversation · Français · Sombre',
    '123-french-records-dark': 'Dossier · Français · Sombre', '124-french-visits-dark': 'Consultations · Français · Sombre',
    '125-french-settings': 'Réglages · Français', '126-french-appearance': 'Apparence · Français',
    '127-french-pin-draft': 'NIP · Français', '128-french-medicine-search': 'Recherche de médicaments · Français',
    '129-french-reading-comma': 'Température · Français', '130-french-symptom-draft': 'Symptôme · Français',
    '131-french-emergency-review': 'Soins d’urgence · Français', '132-french-topics': 'Sujets · Français',
    '133-french-models': 'Modèles · Français', '134-french-visit-notes-draft': 'Notes de consultation · Français',
    '135-french-reminder-draft': 'Rappel · Français', '136-french-preparation-draft': 'Préparation · Français',
    '137-french-chat-controls': 'Écrire un message · Français',
    '138-french-model-medicines-title': 'Médicaments et titre local · Français',
    '139-french-model-readings': 'Relevés dans la conversation · Français',
    '140-french-model-symptom-review': 'Symptôme dans la conversation · Français',
    '141-french-model-reminder-review': 'Rappel dans la conversation · Français',
}

parser = argparse.ArgumentParser()
parser.add_argument('results', nargs='+', type=Path)
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'docs/screenshots')
parser.add_argument('--update-readme', action='store_true', help='Refresh every captured screen in the root README (requires the repository screenshot directory).')
args = parser.parse_args()
repository = Path(__file__).resolve().parents[1]
if args.update_readme and args.output.resolve() != (repository / 'docs/screenshots').resolve():
    parser.error('--update-readme requires the repository screenshot directory')
args.output.mkdir(parents=True, exist_ok=True)
provenance = {}
if (args.output / 'manifest.json').exists():
    provenance = json.loads((args.output / 'manifest.json').read_text())
for result in args.results:
    with tempfile.TemporaryDirectory(prefix='harbour-captures-') as temporary:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', temporary], check=True, stdout=subprocess.DEVNULL)
        for test in json.loads((Path(temporary) / 'manifest.json').read_text()):
            for attachment in test['attachments']:
                match = re.match(r'(\d{2,3}-[a-z-]+)_', attachment['suggestedHumanReadableName'])
                if not match or not attachment['exportedFileName'].endswith('.png'):
                    continue
                stem = match.group(1)
                if stem == '26-health-access' and 'testHealthPermissionScreenshot' in test['testIdentifier']:
                    stem = '30-health-permission'
                shutil.copyfile(Path(temporary) / attachment['exportedFileName'], args.output / (stem + '.png'))
                provenance[stem] = {key: attachment[key] for key in ['deviceName', 'deviceId', 'timestamp', 'suggestedHumanReadableName']}
                provenance[stem]['test'] = test['testIdentifier']
                provenance[stem]['resultBundle'] = result.name
(args.output / 'manifest.json').write_text(json.dumps(provenance, indent=2) + '\n')
files = sorted((path for path in args.output.glob('*.png') if re.match(r'\d{2,3}-', path.name)), key=lambda p: int(p.stem.split('-', 1)[0]))
entries = [{'file': path.name, 'title': TITLES.get(path.stem, path.stem.split('-', 1)[1].replace('-', ' ').capitalize())} for path in files]
for entry in entries:
    entry['src'] = entry['file'] + '?v=' + str((args.output / entry['file']).stat().st_mtime_ns)
figures = ''.join(f'<figure><button class="capture" data-index="{i}" aria-label="Open {html.escape(entry["title"])}"><img src="{entry["src"]}" alt="{html.escape(entry["title"])}" loading="lazy"></button><figcaption>{html.escape(entry["title"])}</figcaption><a href="{entry["file"]}" download>Download PNG</a></figure>' for i, entry in enumerate(entries))
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Harbour — iOS screenshots</title>
<style> *{box-sizing:border-box}body{margin:0;background:#f7f7f7;color:#141414;font:16px -apple-system,BlinkMacSystemFont,sans-serif}header{padding:48px 5vw 28px}h1{margin:0 0 12px;font-size:34px;font-weight:650}header p{color:#666;line-height:1.6}main{display:flex;flex-wrap:wrap;gap:48px 32px;padding:16px 5vw 64px}figure{margin:0;width:260px;max-width:100%}.capture{display:block;width:100%;padding:0;border:0;background:transparent;cursor:zoom-in}.capture img{display:block;width:100%;border-radius:24px}figcaption{font-weight:600;margin:16px 0 8px}a{color:#666;font-size:14px}button{font:inherit}dialog{border:0;border-radius:20px;padding:16px;background:#fff;max-width:96vw;max-height:96vh}dialog::backdrop{background:#000b}.viewer-controls{display:flex;gap:12px;align-items:center;margin-bottom:12px;position:sticky;top:0;background:white;padding:4px 0}.viewer-controls strong{flex:1}.viewer-controls button{border:0;border-radius:10px;padding:10px;background:#eee;cursor:pointer}#full{display:block;max-width:88vw;width:500px;height:auto;margin:auto}button:focus-visible,a:focus-visible{outline:3px solid #555;outline-offset:4px}@media(max-width:600px){header{padding-top:28px}main{justify-content:center}figure{width:320px}} </style>
<header><h1>Harbour for iOS</h1><p>COUNT native screenshots · iPhone simulators<br>Fictional records. Select a screen to view it larger or download the original.</p></header><main>FIGURES</main>
<dialog id="viewer"><div class="viewer-controls"><button id="previous" aria-label="Previous screenshot">←</button><strong id="name"></strong><button id="next" aria-label="Next screenshot">→</button><button id="close">Close</button></div><img id="full" alt=""></dialog>
<script>const entries=ENTRIES;let selected=0;const viewer=document.getElementById('viewer');function show(index){selected=(index+entries.length)%entries.length;const entry=entries[selected];document.getElementById('name').textContent=entry.title;const full=document.getElementById('full');full.src=entry.src;full.alt=entry.title;}document.querySelectorAll('.capture').forEach(button=>button.addEventListener('click',()=>{show(Number(button.dataset.index));viewer.showModal();}));document.getElementById('close').onclick=()=>viewer.close();document.getElementById('previous').onclick=()=>show(selected-1);document.getElementById('next').onclick=()=>show(selected+1);document.addEventListener('keydown',event=>{if(viewer.open&&event.key==='ArrowRight')show(selected+1);if(viewer.open&&event.key==='ArrowLeft')show(selected-1);});</script></html>'''
(args.output / 'index.html').write_text(page.replace('COUNT', str(len(entries))).replace('FIGURES', figures).replace('ENTRIES', json.dumps(entries)))

try:
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 22)
    for offset in range(0, len(files), 9):
        batch = files[offset:offset + 9]
        overview = Image.new('RGB', (1056, 820 * ((len(batch) + 2) // 3)), '#f7f7f7')
        draw = ImageDraw.Draw(overview)
        for index, path in enumerate(batch):
            screenshot = Image.open(path).convert('RGB')
            screenshot.thumbnail((304, 720))
            x, y = 24 + (index % 3) * 352, 18 + (index // 3) * 820
            overview.paste(screenshot, (x + (304 - screenshot.width) // 2, y))
            caption_lines = ['']
            for word in TITLES.get(path.stem, path.stem).split():
                candidate = (caption_lines[-1] + ' ' + word).strip()
                if caption_lines[-1] and draw.textlength(candidate, font=font) > 304:
                    caption_lines.append(word)
                else:
                    caption_lines[-1] = candidate
            draw.multiline_text((x, y + 742), '\n'.join(caption_lines), font=font, spacing=4, fill='#141414')
        overview.save(args.output / f'overview-{offset // 9 + 1}.jpg', quality=90)
    preview_files = ['01-today.png', '64-records.png', '11-chat-empty.png', '31-today-dark.png']
    if all((args.output / name).exists() for name in preview_files):
        preview = Image.new('RGB', (1440, 900), '#f7f7f7')
        labels = ['Today', 'Records', 'New chat', 'Today · Dark']
        painter = ImageDraw.Draw(preview)
        for index, name in enumerate(preview_files):
            shot = Image.open(args.output / name).convert('RGB')
            shot.thumbnail((320, 810))
            x = 20 + index * 360
            preview.paste(shot, (x + (320 - shot.width) // 2, 16))
            painter.text((x + 8, 850), labels[index], font=font, fill='#24211e')
        preview.save(args.output / 'preview.jpg', quality=92)
except ImportError:
    print('Pillow not installed; full-resolution gallery exported without overview sheets.')
if args.update_readme:
    groups = {
        'Today': {1, 31, 43, 66, 116},
        'Chat': {10, 11, 12, 13, 28, 32, 36, 42, 44, 45, 46, 47, 53, 58, 89},
        'Records': {2, 3, 4, 22, 33, 34, 35, 64, 65},
        'Entry and review': {5, 6, 7, 8, 9, 20, 21, 23, 24, 25, 48, 49, 50, 51, 52, 79, 81, 82, 84, 85, 90},
        'Doctor visits': set(range(67, 79)) | {83, 87, 88, 142},
        'Settings, models, and notes': {14, 15, 16, 18, 19, 27, 37, 38, 39, 40, 41, 60},
        'App lock': {54, 55, 56, 57, 59, 61, 62, 80},
        'Health permissions': {26, 30, 63},
        'Evaluation': {17, 29, 86},
        'Reminders, schedules, and preparation': set(range(91, 104)),
        'Voice and care tools in chat': set(range(104, 116)),
        'Canadian French': set(range(117, 142)),
    }
    sections = {name: [] for name in groups}
    for entry in entries:
        number = int(entry['file'].split('-', 1)[0])
        group = next((name for name, numbers in groups.items() if number in numbers), 'Additional screens')
        sections.setdefault(group, []).append(entry)
    start = '<!-- screenshot-gallery:start -->'
    end = '<!-- screenshot-gallery:end -->'
    lines = [start, '## All screens', '', f'{len(entries)} native captures. Select any image to open the original PNG. Capture dates and workflow provenance are in [the screenshot manifest](docs/screenshots/manifest.json).', '']
    for name, captures in sections.items():
        if not captures:
            continue
        lines.extend([f'### {name}', '', '| | |', '| :---: | :---: |'])
        for offset in range(0, len(captures), 2):
            cells = []
            for entry in captures[offset:offset + 2]:
                title = html.escape(entry['title'])
                path = 'docs/screenshots/' + entry['file']
                cells.append(f'<strong>{title}</strong><br>[<img src="{path}" alt="{title}" width="220">]({path})')
            if len(cells) == 1:
                cells.append('')
            lines.append('| ' + ' | '.join(cells) + ' |')
        lines.append('')
    lines.append(end)
    section = '\n'.join(lines) + '\n'
    readme = repository / 'README.md'
    existing = readme.read_text()
    if start in existing and end in existing:
        existing = existing[:existing.index(start)] + section + existing[existing.index(end) + len(end):].lstrip('\n')
    else:
        existing = existing.rstrip() + '\n\n' + section
    readme.write_text(existing)
print(f'Exported {len(entries)} native screenshots to {args.output}')
