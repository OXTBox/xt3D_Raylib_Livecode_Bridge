"""xt3d tool pack for LIB_MCP's MCP server (and lib_mcp.ask_local).

    python3 ~/projects/LIB_MCP/python/lib_mcp/mcp_server.py --tools ~/projects/xt3D_Raylib_Livecode_Bridge/mcp/xt3d_tools.py

Adds: xt3d_find_handlers (search the manifest), bench_list_models, bench_load_model,
bench_run_checks. The bench tools need the xt3d test bench open in LiveCode (it starts
LIB_MCP's server on port 8766). The server puts lib_mcp on the import path before
loading this file.
"""
import json, os
from lib_mcp.client import Client, win_to_local, IDE_PORT

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, 'xt3d_raylib_manifest.json')
CHECKS_FILE = 'C:/xt3d/bench_checks.txt'
MODEL_TYPES = ('.glb', '.gltf', '.obj', '.iqm', '.m3d', '.vox')
_manifest = None


def lc_quote(s):
    if '"' in s or '\n' in s:
        raise ValueError('text may not contain double quotes or line breaks')
    return '"' + s + '"'


def find_handlers(args):
    global _manifest
    if _manifest is None:
        _manifest = json.load(open(MANIFEST, encoding='utf-8'))
    words = (args.get('query') or '').lower().split()
    limit = int(args.get('limit') or 20)
    hits = []
    for f in _manifest['functions']:
        if f.get('status') not in ('wrapped', 'helper'):
            continue
        if all(w in (f['xt3d'] + ' ' + (f.get('description') or '')).lower() for w in words):
            hits.append('%s %s  -> %s.  %s%s' % (
                f['xt3d'], ', '.join(p['name'] for p in f.get('params', [])), f.get('returns_type', ''),
                f.get('description', ''), '  (needs the window)' if f.get('needs_window') else ''))
    if not hits:
        return 'No xt3d handler matches %r.' % ' '.join(words)
    more = '' if len(hits) <= limit else '\n... %d more; narrow the query.' % (len(hits) - limit)
    return ('Commands are called as  xt3d_Name a, b, c ; functions as  put xt3d_Name(a, b) into tX .\n'
            'Vectors are separate numbers, colours are 4 numbers 0-255, models/textures are handle numbers.\n\n'
            + '\n'.join(hits[:limit]) + more)


def list_models(args):
    folder = (args.get('folder') or 'C:/xt3d/test_models').replace('\\', '/')
    try:
        names = sorted(n for n in os.listdir(win_to_local(folder)) if n.lower().endswith(MODEL_TYPES))
    except OSError as e:
        return 'Cannot list %s: %s' % (folder, e)
    return '\n'.join(folder.rstrip('/') + '/' + n for n in names) or 'No model files in ' + folder


def load_model(args):
    c = Client(IDE_PORT)
    c.request('POST', '/run', 'xbLoadModel ' + lc_quote(args['path'].replace('\\', '/')), timeout=120)
    return c.eval('field "info"')[1]


def run_checks(_):
    Client(IDE_PORT).request('POST', '/run', 'xbRunChecks', timeout=300)
    try:
        lines = open(win_to_local(CHECKS_FILE), encoding='utf-8', errors='replace').read().replace('\r', '').splitlines()
    except OSError:
        return 'Checks ran but %s was not found.' % CHECKS_FILE
    return '\n'.join(l.strip() for l in lines if 'PASS' in l or 'FAIL' in l)


def _schema(props=None, required=None):
    return {'type': 'object', 'properties': props or {}, 'required': required or []}


S = {'type': 'string'}
TOOLS = [
    ('xt3d_find_handlers', find_handlers, 'Search the xt3d handlers (raylib for LiveCode: xt3d_DrawCube, xt3d_LoadModel, ...) '
     'by words in their name or description. Returns how to call each one.',
     _schema({'query': dict(S, description='words to look for, e.g. "draw cube" or "texture load"'),
              'limit': {'type': 'integer', 'description': 'most results (default 20)'}}, ['query'])),
    ('bench_list_models', list_models, 'List the 3D model files the xt3d test bench can load.',
     _schema({'folder': dict(S, description='Windows folder, default C:/xt3d/test_models')})),
    ('bench_load_model', load_model, 'Load a 3D model into the xt3d test bench and return its summary: meshes, '
     'materials, bones, size, animations.',
     _schema({'path': dict(S, description='Windows path, e.g. C:/xt3d/test_models/skinned_bend.glb')}, ['path'])),
    ('bench_run_checks', run_checks, 'Run the xt3d test bench self-test (crash guards, test models, frame copy) '
     'and return PASS/FAIL lines.', _schema()),
]
