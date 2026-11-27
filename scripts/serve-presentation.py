#!/usr/bin/env python3
"""Serve the local presentation and capture the actual QA Simulator on demand."""
import argparse,base64,json,os,subprocess,tempfile
from functools import partial
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--directory',type=Path,default=ROOT/'docs/presentation')
p.add_argument('--port',type=int,default=8766)
p.add_argument('--simulator-id',required=True)
p.add_argument('--mirror-url',default='',help='Exact optional local serve-sim URL for interactive mirroring')
a=p.parse_args();directory=a.directory.resolve()
if a.mirror_url and (urlparse(a.mirror_url).scheme!='http' or urlparse(a.mirror_url).hostname not in ['localhost','127.0.0.1']):p.error('Mirror must be a local Simulator URL.')
env=dict(os.environ);env.setdefault('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer')
class Handler(SimpleHTTPRequestHandler):
 def allowed(self):return self.headers.get('X-Harbour-Presentation')=='1' and self.headers.get('Sec-Fetch-Site','none') in ['same-origin','none']
 def data(self,value,status=200):
  body=json.dumps(value).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def do_GET(self):
  if self.path=='/api/config':return self.data({'mirrorURL':a.mirror_url})
  if self.path=='/api/capture':
   if not self.allowed():return self.data({'error':'Same-origin presentation capture required'},403)
   try:
    with tempfile.TemporaryDirectory(prefix='harbour-live-capture-') as tmp:
     image=Path(tmp)/'capture.png'
     subprocess.run(['xcrun','simctl','io',a.simulator_id,'screenshot',str(image)],env=env,check=True,timeout=15,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
     return self.data({'image':'data:image/png;base64,'+base64.b64encode(image.read_bytes()).decode(),'source':'Actual current Simulator screen; select the region manually'})
   except (OSError,subprocess.SubprocessError):return self.data({'error':'Simulator capture unavailable; check the selected booted device'},503)
  if self.path.startswith('/api/'):return self.data({'error':'Not found'},404)
  return super().do_GET()
 def do_POST(self):
  if self.path!='/api/simulator' or not self.allowed():return self.data({'error':'Unavailable'},403)
  subprocess.run(['open','-a','Simulator','--args','-CurrentDeviceUDID',a.simulator_id],check=True,timeout=10)
  self.data({'opened':True})
 def end_headers(self):
  self.send_header('X-Content-Type-Options','nosniff');super().end_headers()
server=ThreadingHTTPServer(('127.0.0.1',a.port),partial(Handler,directory=str(directory)))
print(f'Harbour presentation: http://127.0.0.1:{a.port}/ (local only)',flush=True)
try:server.serve_forever()
except KeyboardInterrupt:pass
finally:server.server_close()
