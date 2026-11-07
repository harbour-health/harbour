#!/usr/bin/env python3
"""Local, temporary ONNX voice audition UI. See docs/voice-lab.md."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse
from urllib.request import urlopen
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--assets', type=Path, required=True)
parser.add_argument('--port', type=int, default=8766)
args = parser.parse_args()
root = args.assets.resolve()
outputs = root / 'samples'
outputs.mkdir(exist_ok=True)
token = secrets.token_urlsafe(24)
jobs, engines = {}, {}
lock = threading.Lock()
executor = ThreadPoolExecutor(max_workers=1)


def catalog():
    import numpy as np
    with np.load(root / 'voices-v1.0.bin', allow_pickle=False) as voices:
        names = sorted(voices.files)
    return {'models': [
        {'id': 'kokoro', 'name': 'Kokoro', 'size': '82M · ONNX',
         'voices': names, 'defaultVoice': 'af_heart', 'preferredVoices': ['af_heart', 'am_liam'],
         'languages': [{'id': 'en-us', 'name': 'English (US)', 'prefixes': ['af_', 'am_']},
                       {'id': 'en-gb', 'name': 'English (UK)', 'prefixes': ['bf_', 'bm_']},
                       {'id': 'fr-fr', 'name': 'Français', 'prefixes': ['ff_']}],
         'note': 'Apache 2.0 model. Local CPU inference.'},
        {'id': 'supertonic', 'name': 'Supertonic 3', 'size': '99M · ONNX',
         'voices': [f'{gender}{i}' for gender in ['F', 'M'] for i in range(1, 6)],
         'defaultVoice': 'F1', 'languages': [{'id': 'en', 'name': 'English'}, {'id': 'fr', 'name': 'Français'}],
         'note': 'OpenRAIL-M model; includes medical-advice restrictions. Archived upstream.'}
    ]}


def preset(voice):
    path = root / 'supertonic/assets/voice_styles' / f'{voice}.json'
    if path.exists():
        return path
    info = json.loads((root / 'supertonic-model-info.json').read_text())
    filename = f'voice_styles/{voice}.json'
    entry = next(item for item in info['siblings'] if item['rfilename'] == filename)
    url = f"https://huggingface.co/{info['id']}/resolve/{info['sha']}/{filename}"
    with urlopen(url, timeout=60) as response:
        data = response.read()
    expected = entry.get('lfs', {}).get('sha256')
    if expected and hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('Voice preset checksum mismatch')
    json.loads(data)
    path.write_bytes(data)
    return path


def synthesize(job_id, request):
    import soundfile as sf
    with lock:
        jobs[job_id]['state'] = 'generating'
    started = time.monotonic()
    try:
        model = request['model']
        voice, speed, language = request['voice'], float(request['speed']), request['language']
        if model == 'kokoro':
            if model not in engines:
                from kokoro_onnx import Kokoro
                engines[model] = Kokoro(str(root / 'kokoro-v1.0.onnx'), str(root / 'voices-v1.0.bin'))
            wav, rate = engines[model].create(request['text'], voice=voice, speed=speed, lang=language)
        else:
            sys.path.insert(0, str(root / 'supertonic/py'))
            from helper import load_text_to_speech, load_voice_style
            style_path = preset(voice)
            if model not in engines:
                engines[model] = load_text_to_speech(str(root / 'supertonic/assets/onnx'), False)
            engine = engines[model]
            style = load_voice_style([str(style_path)], verbose=False)
            wave, duration = engine(request['text'], language, style, int(request['steps']), speed)
            rate = engine.sample_rate
            wav = wave[0, :int(rate * duration[0].item())]
        output = outputs / f'{job_id}.wav'
        sf.write(output, wav, rate)
        with lock:
            jobs[job_id].update(state='ready', audio=f'/audio/{job_id}.wav',
                               seconds=round(time.monotonic() - started, 2),
                               duration=round(len(wav) / rate, 2))
    except Exception as error:
        with lock:
            jobs[job_id].update(state='failed', error=str(error))


class Handler(BaseHTTPRequestHandler):
    def reply(self, value, code=200, mime='application/json'):
        data = json.dumps(value).encode() if mime == 'application/json' else value
        self.send_response(code)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/':
            page = Path(__file__).with_name('voice-lab.html').read_text().replace('__TOKEN__', token)
            return self.reply(page.encode(), mime='text/html; charset=utf-8')
        if path == '/api/catalog':
            return self.reply(catalog())
        if path.startswith('/api/jobs/'):
            with lock:
                job = dict(jobs.get(path.rsplit('/', 1)[-1], {}))
            return self.reply(job, 200 if job else 404)
        if path.startswith('/audio/'):
            name = path.rsplit('/', 1)[-1]
            if len(name) == 36 and all(c in '0123456789abcdef.wav' for c in name):
                file = outputs / name
                if file.is_file():
                    return self.reply(file.read_bytes(), mime='audio/wav')
        self.reply({'error': 'Not found'}, 404)

    def do_POST(self):
        if self.headers.get('X-Voice-Lab') != token:
            return self.reply({'error': 'Invalid session'}, 403)
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 16000:
                raise ValueError('Request too large')
            request = json.loads(self.rfile.read(size))
            if self.path == '/api/play':
                job_id = request['job']
                with lock:
                    job = jobs.get(job_id, {})
                if job.get('state') != 'ready':
                    raise ValueError('Generate a sample first')
                # Fixed executable and internally generated filename, never a shell command.
                subprocess.Popen(['/usr/bin/afplay', str(outputs / f'{job_id}.wav')])
                return self.reply({'playing': True})
            if self.path != '/api/generate':
                return self.reply({'error': 'Not found'}, 404)
            model = next((m for m in catalog()['models'] if m['id'] == request.get('model')), None)
            if not model or request.get('voice') not in model['voices']:
                raise ValueError('Unknown model or voice')
            if request.get('language') not in [lang['id'] for lang in model['languages']]:
                raise ValueError('Unsupported language')
            speed = float(request.get('speed', 1))
            if not 0.6 <= speed <= 1.5:
                raise ValueError('Speed must be between 0.6 and 1.5')
            steps = int(request.get('steps', 8))
            if not 1 <= steps <= 32:
                raise ValueError('Steps must be between 1 and 32')
            if not isinstance(request.get('text'), str) or not 1 <= len(request['text'].strip()) <= 2000:
                raise ValueError('Enter 1–2,000 characters')
            with lock:
                if sum(j['state'] in ('queued', 'generating') for j in jobs.values()) >= 4:
                    return self.reply({'error': 'Please wait for the current samples'}, 429)
                job_id = uuid.uuid4().hex
                jobs[job_id] = {'state': 'queued', 'request': request}
            executor.submit(synthesize, job_id, request)
            self.reply({'id': job_id}, 202)
        except (ValueError, KeyError, TypeError) as error:
            self.reply({'error': str(error)}, 400)


print(f'Voice lab: http://127.0.0.1:{args.port}/', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
