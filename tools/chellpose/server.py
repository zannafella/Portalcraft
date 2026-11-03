r"""Ending Arms: pose Minecraft's arms on Chell's first-person arms in Portal 2's ending, export them to the game.

    python tools/chellpose/server.py [--port 5077] [--no-browser]     (or Ending-Arms.bat in the repo root)

A small local web app (http://127.0.0.1:5077): the page (ui/) shows the ending's body - headless_player.mdl and its
animations, decoded from your own Portal 2 install by p2model.py - with Minecraft's arms on it, and saves what you pose
in pose.json (next to this file: only your offsets and keyframes, nothing of Portal 2's). Export bakes every frame of
every animation (the page works the arms out exactly as it shows them) into portalcraft-ending-arms.json in the config
folder of the Minecraft instances it finds: the Modrinth App's "Portalcraft" profile and the dev client's mc/run. That
file is made from Portal 2's animations, so it stays on your machine (it's not in the repo or the mod's jar).
"""
import argparse
import glob
import io
import json
import os
import struct
import sys
import threading
import webbrowser
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import p2model  # noqa: E402

UI = os.path.join(HERE, 'ui')
PROJECT = os.path.join(HERE, 'pose.json')
EXPORT_NAME = 'portalcraft-ending-arms.json'
APPDATA = os.environ.get('APPDATA', '')
HOME = os.path.expanduser('~')


def export_dirs():
    """Config folders of the Minecraft instances that run Portalcraft."""
    out = []
    for d in (os.path.join(APPDATA, 'ModrinthApp', 'profiles', 'Portalcraft', 'config'), os.path.join(ROOT, 'mc', 'run', 'config')):
        if os.path.isdir(d):
            out.append(d)
    return out


def find_skin(slim):
    """Minecraft's default Steve skin, from a Minecraft 26.x client jar on this machine."""
    want = 'assets/minecraft/textures/entity/player/%s/steve.png' % ('slim' if slim else 'wide')
    jars = glob.glob(os.path.join(HOME, '.gradle', 'caches', 'fabric-loom', '26.*', 'minecraft-client.jar'))
    jars += glob.glob(os.path.join(APPDATA, 'ModrinthApp', 'meta', 'versions', '26.*', '26.*.jar'))
    jars += glob.glob(os.path.join(APPDATA, '.minecraft', 'versions', '26.*', '26.*.jar'))
    for j in jars:
        try:
            with zipfile.ZipFile(j) as z:
                if want in z.namelist():
                    return z.read(want)
        except (OSError, zipfile.BadZipFile):
            continue
    return None


class State:
    body = None
    lock = threading.Lock()

    @classmethod
    def get(cls):
        with cls.lock:
            if cls.body is None:
                cls.body = p2model.Body()
            return cls.body


def body_json():
    b = State.get()
    pos, weights, indices = b.base.mesh(b.vvd, b.vtx)
    skin_index, skin_weight = [], []
    for ws in weights:
        ws = sorted(ws, key=lambda x: -x[1])[:4]
        tot = sum(w for _, w in ws) or 1.0
        idx = [i for i, _ in ws] + [0] * (4 - len(ws))
        wt = [w / tot for _, w in ws] + [0.0] * (4 - len(ws))
        skin_index.extend(idx)
        skin_weight.extend(round(w, 5) for w in wt)
    bones = []
    for bn in b.base.bones:
        bones.append({'name': bn.name, 'parent': bn.parent, 'poseToBone': [round(v, 6) for row in bn.pose_to_bone for v in row]})
    atts = {k: {'bone': v['bone'], 'matrix': [round(x, 6) for row in v['matrix'] for x in row]} for k, v in b.base.attachments.items()}
    return {
        'model': p2model.BODY + '.mdl',
        'bones': bones,
        'attachments': atts,
        'sequences': [{'name': s['name'], 'frames': s['frames'], 'fps': s['fps'], 'loop': s['loop']} for s in b.sequences],
        'mesh': {'positions': [round(v, 4) for p in pos for v in p], 'skinIndex': skin_index, 'skinWeight': skin_weight, 'indices': indices},
    }


def sequence_bytes(i):
    """frames x bones x 12 float32: each bone's model-space 3x4 matrix, row-major."""
    b = State.get()
    s = b.sequences[i]
    out = io.BytesIO()
    for f in range(s['frames']):
        for m in b.bone_matrices(i, f):
            out.write(struct.pack('<12f', *m[0], *m[1], *m[2]))
    return out.getvalue()


_seq_cache = {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype='application/json'):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode('utf-8')
        elif isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split('?')[0]
        query = self.path.split('?')[1] if '?' in self.path else ''
        try:
            if path == '/api/body':
                return self.send(200, body_json())
            if path.startswith('/api/seq/'):
                i = int(path.rsplit('/', 1)[1])
                if i not in _seq_cache:
                    _seq_cache[i] = sequence_bytes(i)
                return self.send(200, _seq_cache[i], 'application/octet-stream')
            if path == '/api/skin':
                png = find_skin('slim=1' in query)
                if png is None:
                    return self.send(404, {'error': 'no Minecraft 26.x client jar found for the default skin - load a skin PNG instead'})
                return self.send(200, png, 'image/png')
            if path == '/api/project':
                if os.path.exists(PROJECT):
                    return self.send(200, open(PROJECT, 'rb').read())
                return self.send(200, {})
            if path == '/api/targets':
                return self.send(200, {'dirs': export_dirs(), 'name': EXPORT_NAME})
            # the page
            rel = 'index.html' if path in ('/', '') else path.lstrip('/')
            full = os.path.normpath(os.path.join(UI, rel))
            if not full.startswith(UI) or not os.path.isfile(full):
                return self.send(404, 'not found', 'text/plain')
            ctype = {'.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css'}.get(os.path.splitext(full)[1], 'application/octet-stream')
            return self.send(200, open(full, 'rb').read(), ctype + '; charset=utf-8')
        except Exception as e:  # noqa: BLE001 - shown to the user in the page
            return self.send(500, {'error': '%s: %s' % (type(e).__name__, e)})

    def do_POST(self):
        path = self.path.split('?')[0]
        try:
            data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            if path == '/api/project':
                json.loads(data)  # (valid JSON only)
                tmp = PROJECT + '.tmp'
                open(tmp, 'wb').write(data)
                os.replace(tmp, PROJECT)
                return self.send(200, {'saved': PROJECT})
            if path == '/api/export':
                baked = json.loads(data)
                if baked.get('model') != p2model.BODY + '.mdl' or not isinstance(baked.get('sequences'), list):
                    return self.send(400, {'error': 'not an ending arms bake'})
                text = json.dumps(baked, separators=(',', ':'))
                written = []
                for d in export_dirs():
                    p = os.path.join(d, EXPORT_NAME)
                    open(p + '.tmp', 'w', encoding='utf-8').write(text)
                    os.replace(p + '.tmp', p)
                    written.append(p)
                if not written:
                    return self.send(404, {'error': 'no Minecraft instance found (Modrinth profile "Portalcraft" or mc/run)'})
                return self.send(200, {'written': written, 'bytes': len(text)})
            return self.send(404, {'error': 'unknown'})
        except Exception as e:  # noqa: BLE001
            return self.send(500, {'error': '%s: %s' % (type(e).__name__, e)})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=5077)
    ap.add_argument('--no-browser', action='store_true')
    a = ap.parse_args()
    State.get()  # (fails early if Portal 2 isn't there)
    srv = ThreadingHTTPServer(('127.0.0.1', a.port), Handler)
    url = 'http://127.0.0.1:%d/' % a.port
    print('Ending Arms at', url, '(Ctrl+C to stop)')
    if not a.no_browser:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
