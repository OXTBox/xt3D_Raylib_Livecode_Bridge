#!/usr/bin/env python3
"""xt3d_mcp.py - MCP tool server: lets a local model (LM Studio) or Claude Desktop work
with the xt3d bridge and the running LiveCode IDE.

Speaks MCP over stdio (JSON-RPC 2.0, one message per line). Python standard library only.
LiveCode is reached through the xt3d dev server (testbench/xt3d_devserver.livecodescript),
via Windows' curl.exe because WSL2 cannot reach Windows' 127.0.0.1.

LM Studio (C:\\Users\\<you>\\.cache\\lm-studio\\mcp.json):
  {"mcpServers": {"xt3d": {"command": "wsl.exe",
     "args": ["-d", "Ubuntu", "-e", "python3", "/home/igame3d/projects/xt3D_Raylib_Livecode_Bridge/llm/xt3d_mcp.py"]}}}

Tools that change things in LiveCode (livecode_run, bench_load_model, bench_run_checks)
run real code in the IDE. LM Studio asks before each tool call unless told not to.
Test without a model:  python3 llm/xt3d_mcp.py --selftest
"""
import base64, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
PRIMER = os.path.join(HERE, 'livecode_primer.md')
MANIFEST = os.path.join(REPO, 'xt3d_raylib_manifest.json')
TOKEN_FILE = '/mnt/c/xt3d/.xt3d_devtoken'
ERROR_FILE = '/mnt/c/xt3d/livecode_errors.txt'
CHECKS_FILE = '/mnt/c/xt3d/bench_checks.txt'
SNAP_FILE = 'C:/xt3d/snap.png'
NOT_RUNNING = ('The LiveCode dev server is not running. Ask the user to open the xt3d test bench '
               '(File > Open Stack > C:\\xt3d\\testbench\\xt3d_testbench.livecodescript); it starts the server.')


def win_to_wsl(path):
    p = path.replace('\\', '/')
    if len(p) > 1 and p[1] == ':':
        return '/mnt/' + p[0].lower() + p[2:]
    return p


class NotRunning(Exception):
    pass


def dev(method, route, body=None, timeout=60):
    """one request to the dev server; returns (ok, text)"""
    try:
        token, port = [l.strip() for l in open(TOKEN_FILE).read().splitlines()[:2]]
    except (OSError, ValueError):
        raise NotRunning()
    cmd = ['curl.exe', '-sS', '-m', str(timeout), '-w', '\n%{http_code}', '-H', 'X-Token: ' + token]
    if method == 'POST':
        cmd += ['-X', 'POST', '-H', 'Expect:', '-H', 'Content-Type: text/plain; charset=utf-8', '--data-binary', '@-']
    cmd.append('http://127.0.0.1:%s%s' % (port, route))
    try:
        r = subprocess.run(cmd, input=(body or '').encode('utf-8'), capture_output=True, timeout=timeout + 5)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise NotRunning() from e
    out = r.stdout.decode('utf-8', 'replace').replace('\r', '')
    if r.returncode != 0 or '\n' not in out:
        raise NotRunning()
    text, code = out.rsplit('\n', 1)
    return code.strip() == '200', text


def lc_quote(s):
    if '"' in s or '\n' in s:
        raise ValueError('text may not contain double quotes or line breaks')
    return '"' + s + '"'


# ---------------------------------------------------------------- tools

def t_primer(_):
    return open(PRIMER, encoding='utf-8').read()


_manifest = None
def t_find(args):
    global _manifest
    if _manifest is None:
        _manifest = json.load(open(MANIFEST, encoding='utf-8'))
    q = (args.get('query') or '').lower().split()
    limit = int(args.get('limit') or 20)
    hits = []
    for f in _manifest['functions']:
        if f.get('status') not in ('wrapped', 'helper'):
            continue
        hay = (f['xt3d'] + ' ' + (f.get('description') or '')).lower()
        if all(w in hay for w in q):
            params = ', '.join(p['name'] for p in f.get('params', []))
            hits.append('%s %s  -> %s.  %s%s' % (
                f['xt3d'], params, f.get('returns_type', ''), f.get('description', ''),
                '  (needs the window)' if f.get('needs_window') else ''))
    if not hits:
        return 'No xt3d handler matches %r.' % ' '.join(q)
    more = '' if len(hits) <= limit else '\n... %d more; narrow the query.' % (len(hits) - limit)
    return ('Commands are called as  xt3d_Name a, b, c ; functions as  put xt3d_Name(a, b) into tX .\n'
            'Vectors are separate numbers, colours are 4 numbers 0-255, models/textures are handle numbers.\n\n'
            + '\n'.join(hits[:limit]) + more)


def t_status(_):
    ok, text = dev('GET', '/ping', timeout=10)
    return text


def t_run(args):
    ok, text = dev('POST', '/run', args['code'])
    return text or '(done, nothing returned)'


def t_eval(args):
    ok, text = dev('POST', '/eval', args['expression'])
    return text


def t_load(args):
    path = args['path'].replace('\\', '/')
    ok, text = dev('POST', '/run', 'xbLoadModel ' + lc_quote(path), timeout=120)
    ok2, info = dev('POST', '/eval', 'field "info"')
    return info if ok2 else text


def t_models(args):
    folder = (args.get('folder') or 'C:/xt3d/test_models').replace('\\', '/')
    try:
        names = sorted(n for n in os.listdir(win_to_wsl(folder))
                       if n.lower().endswith(('.glb', '.gltf', '.obj', '.iqm', '.m3d', '.vox')))
    except OSError as e:
        return 'Cannot list %s: %s' % (folder, e)
    return '\n'.join(folder.rstrip('/') + '/' + n for n in names) or 'No model files in ' + folder


def t_checks(_):
    dev('POST', '/run', 'xbRunChecks', timeout=300)
    try:
        lines = open(CHECKS_FILE, encoding='utf-8', errors='replace').read().replace('\r', '').splitlines()
    except OSError:
        return 'Checks ran but ' + CHECKS_FILE + ' was not found.'
    return '\n'.join(l.strip() for l in lines if 'PASS' in l or 'FAIL' in l)


def t_errors(args):
    n = int(args.get('count') or 5)
    try:
        text = open(ERROR_FILE, encoding='utf-8', errors='replace').read().replace('\r', '')
    except OSError:
        return 'No LiveCode errors logged yet.'
    entries = ['==== ' + e for e in text.split('==== ') if e.strip()]
    return ''.join(entries[-n:]) or 'No LiveCode errors logged yet.'


def t_snap(_):
    ok, text = dev('GET', '/snap')
    if not ok:
        return text
    data = open(win_to_wsl(SNAP_FILE), 'rb').read()
    return [{'type': 'text', 'text': 'Snapshot of the xt3d test bench (%d bytes PNG).' % len(data)},
            {'type': 'image', 'data': base64.b64encode(data).decode('ascii'), 'mimeType': 'image/png'}]


def schema(props=None, required=None):
    return {'type': 'object', 'properties': props or {}, 'required': required or []}

S = {'type': 'string'}
TOOLS = [
    ('livecode_primer', t_primer, 'Read this first if you will write LiveCode Script. A short guide to LiveCode Script syntax '
     '(it is NOT JavaScript or Python) with common mistakes.', schema()),
    ('xt3d_find_handlers', t_find, 'Search the xt3d handlers (raylib for LiveCode: xt3d_DrawCube, xt3d_LoadModel, ...) by words '
     'in their name or description. Returns how to call each one.',
     schema({'query': dict(S, description='words to look for, e.g. "draw cube" or "texture load"'),
             'limit': {'type': 'integer', 'description': 'most results to return (default 20)'}}, ['query'])),
    ('livecode_status', t_status, 'Check that LiveCode is running with the dev server, and which xt3d version is loaded.', schema()),
    ('livecode_run', t_run, 'Run LiveCode Script statements inside the xt3d test bench and return what they put into the '
     'message box and the result. Use "put x" (no "into") to return a value. Script errors are returned translated.',
     schema({'code': dict(S, description='LiveCode Script statements, one per line')}, ['code'])),
    ('livecode_eval', t_eval, 'Evaluate one LiveCode expression in the xt3d test bench and return its value, '
     'e.g.  the number of lines of field "info"  or  xt3d_Version().',
     schema({'expression': dict(S, description='a LiveCode expression')}, ['expression'])),
    ('bench_list_models', t_models, 'List the 3D model files the bench can load (glb, gltf, obj, iqm, m3d, vox).',
     schema({'folder': dict(S, description='Windows folder, default C:/xt3d/test_models')})),
    ('bench_load_model', t_load, 'Load a 3D model into the xt3d test bench and return its summary: meshes, materials, bones, '
     'size, animations.', schema({'path': dict(S, description='Windows path, e.g. C:/xt3d/test_models/skinned_bend.glb')}, ['path'])),
    ('bench_run_checks', t_checks, 'Run the bench self-test (crash guards, test models, frame copy) and return PASS/FAIL lines.', schema()),
    ('livecode_errors', t_errors, 'Read the most recent LiveCode script errors logged by the dev server, translated.',
     schema({'count': {'type': 'integer', 'description': 'how many recent errors (default 5)'}})),
    ('bench_snapshot', t_snap, 'Take a PNG picture of the xt3d test bench window (for models that can see images).', schema()),
]
BY_NAME = {t[0]: t for t in TOOLS}


# ---------------------------------------------------------------- MCP over stdio

def reply(id_, result=None, error=None):
    msg = {'jsonrpc': '2.0', 'id': id_}
    if error is not None:
        msg['error'] = error
    else:
        msg['result'] = result
    sys.stdout.write(json.dumps(msg) + '\n')
    sys.stdout.flush()


def call_tool(name, args):
    if name not in BY_NAME:
        return [{'type': 'text', 'text': 'Unknown tool ' + name}], True
    try:
        out = BY_NAME[name][1](args or {})
        content = out if isinstance(out, list) else [{'type': 'text', 'text': out}]
        return content, False
    except NotRunning:
        return [{'type': 'text', 'text': NOT_RUNNING}], True
    except (KeyError, ValueError) as e:
        return [{'type': 'text', 'text': 'Bad arguments: %s' % e}], True


def handle(msg):
    method, id_ = msg.get('method'), msg.get('id')
    if method == 'initialize':
        ver = (msg.get('params') or {}).get('protocolVersion') or '2024-11-05'
        reply(id_, {'protocolVersion': ver, 'capabilities': {'tools': {}},
                    'serverInfo': {'name': 'xt3d', 'version': '0.1.0'},
                    'instructions': 'Tools for the xt3d raylib bridge running in LiveCode 9.6.3. Call livecode_primer '
                                    'before writing LiveCode Script; call xt3d_find_handlers to look up xt3d commands.'})
    elif method == 'tools/list':
        reply(id_, {'tools': [{'name': n, 'description': d, 'inputSchema': s} for n, _, d, s in TOOLS]})
    elif method == 'tools/call':
        p = msg.get('params') or {}
        content, is_error = call_tool(p.get('name'), p.get('arguments'))
        reply(id_, {'content': content, 'isError': is_error})
    elif method == 'ping':
        reply(id_, {})
    elif id_ is not None:
        reply(id_, error={'code': -32601, 'message': 'method not found: %s' % method})
    # notifications (no id) need no answer


def main():
    if '--selftest' in sys.argv:
        for name, args in [('xt3d_find_handlers', {'query': 'draw cube'}), ('bench_list_models', {}),
                           ('livecode_errors', {'count': 2}), ('livecode_status', {})]:
            content, err = call_tool(name, args)
            print('== %s%s\n%s\n' % (name, ' (error)' if err else '', content[0]['text'][:600]))
        return
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        handle(msg)


if __name__ == '__main__':
    main()
