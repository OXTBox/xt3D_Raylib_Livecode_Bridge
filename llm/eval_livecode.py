#!/usr/bin/env python3
"""eval_livecode.py - score a local model on small LiveCode tasks, in several ways of asking.

    python3 llm/eval_livecode.py [--model spark-x2.6-4b] [--repeats 2] [--modes plain-low,schema-low,plain-medium]

Every answer is checked automatically:
  must    patterns the correct LiveCode needs (regex, case-insensitive)
  never   JavaScript/Python habits that are never LiveCode
Prints a table and writes every answer to llm/eval_results.json for reading by eye.
The model gets llm/livecode_primer.md as its system prompt, as in real use.
Modes: plain = free text; schema = JSON {"handler", "uses", "unsure"} enforced by LM Studio.
"""
import argparse, json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
URL = 'http://127.0.0.1:1234/v1/chat/completions'
NEVER = [r'\.split\(', r'^\s*\w+\s*=\s*[^=]', r'[{};]\s*$', r'\bprint\(', r'messageBox\(', r'\bvar\s', r'\bdef\s',
         r'\.length\b', r'\+\+', r'\breturn\s*\(', r'\bfunction\s+\w+\s*\(']
TASKS = [
    ('third word', 'Write a command handler showWord that puts the third word of the second line of the variable tText into the message box. Assume tText is a script local.',
     [r'word\s+3\s+of\s+line\s+2\s+of\s+tText', r'^\s*on\s+showWord', r'end\s+showWord']),
    ('sum items', 'Write a function sumItems that takes a comma separated list like "3,4,5" and returns the total.',
     [r'function\s+sumItems\s+p\w+', r'repeat\s+(for\s+each\s+item|with)', r'\badd\b|\+', r'return\s+t\w+', r'end\s+sumItems']),
    ('global score', 'Write a mouseUp handler for a button that adds 1 to the global gScore and shows the new score in field "Score".',
     [r'global\s+gScore', r'add\s+1\s+to\s+gScore', r'field\s+"Score"', r'end\s+mouseUp']),
    ('count errors', 'Write a command countErrors that counts how many lines of field "Log" contain the word ERROR and puts the count into the message box.',
     [r'(repeat\s+for\s+each\s+line|repeat\s+with)', r'contains\s+"ERROR"|"ERROR"', r'field\s+"Log"', r'end\s+countErrors']),
    ('xt3d sphere', 'Write a command drawFrame that draws a red sphere of radius 0.5 at position 0,1,0 with xt3d into render texture sTarget, using camera sCamera, on a dark background.',
     [r'xt3d_BeginTextureMode\s+sTarget', r'xt3d_BeginMode3D\s+sCamera', r'xt3d_DrawSphere\s+0\s*,\s*1\s*,\s*0\s*,\s*0\.5\s*,\s*255\s*,\s*0\s*,\s*0\s*,\s*255',
      r'xt3d_EndMode3D', r'xt3d_EndTextureMode', r'end\s+drawFrame']),
    ('reverse items', 'Write a function reverseItems that returns the items of a comma separated list in reverse order, still comma separated.',
     [r'function\s+reverseItems\s+p\w+', r'(down\s+to\s+1|repeat\s+for\s+each\s+item)', r'item\s+\w+\s+of', r'return', r'end\s+reverseItems']),
    ('word counts', 'Write a function wordCounts that returns an array with how many times each word occurs in a text.',
     [r'function\s+wordCounts\s+p\w+', r'repeat\s+for\s+each\s+word', r'add\s+1\s+to\s+t\w+\[', r'return\s+t\w+', r'end\s+wordCounts']),
]
SCHEMA = {'type': 'json_schema', 'json_schema': {'name': 'livecode_answer', 'strict': True, 'schema': {
    'type': 'object', 'additionalProperties': False, 'required': ['handler', 'uses', 'unsure'],
    'properties': {'handler': {'type': 'string', 'description': 'the complete LiveCode Script code'},
                   'uses': {'type': 'array', 'items': {'type': 'string'}, 'description': 'LiveCode commands/functions used'},
                   'unsure': {'type': 'string', 'description': 'what you are not sure about, or empty'}}}}}


def ask(model, primer, task, mode, max_tokens):
    plain = mode.startswith('plain')
    effort = mode.split('-', 1)[1]
    body = {'model': model, 'temperature': 0.2, 'max_tokens': max_tokens, 'reasoning_effort': effort,
            'messages': [{'role': 'system', 'content': primer},
                         {'role': 'user', 'content': task + (' Code only.' if plain else '')}]}
    if not plain:
        body['response_format'] = SCHEMA
    t0 = time.time()
    r = subprocess.run(['curl.exe', '-sS', '-m', '600', URL, '-H', 'Content-Type: application/json', '--data-binary', '@-'],
                       input=json.dumps(body).encode(), capture_output=True)
    secs = time.time() - t0
    try:
        d = json.loads(r.stdout.decode('utf-8', 'replace'))
        m = d['choices'][0]['message']
        usage = d.get('usage', {})
    except (ValueError, KeyError):
        return {'error': r.stdout.decode(errors='replace')[:300] or r.stderr.decode(errors='replace')[:300], 'secs': secs}
    content = (m.get('content') or '').strip()
    extra = {}
    if plain:
        f = re.findall(r'```[a-zA-Z]*\n(.*?)```', content, re.S)
        code = f[0] if f else content
    else:
        try:
            j = json.loads(content)
            code, extra = j.get('handler', ''), {'uses': j.get('uses'), 'unsure': j.get('unsure')}
        except ValueError:
            code, extra = content, {'bad_json': True}
    return {'code': code, 'raw': content, 'secs': round(secs, 1), **extra,
            'reasoning_tokens': usage.get('completion_tokens_details', {}).get('reasoning_tokens'),
            'completion_tokens': usage.get('completion_tokens')}


def score(code, must):
    missing = [p for p in must if not re.search(p, code, re.I | re.M)]
    bad = [p for p in NEVER if re.search(p, code, re.M)]
    return missing, bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', default='spark-x2.6-4b')
    ap.add_argument('--repeats', type=int, default=2)
    ap.add_argument('--modes', default='plain-low,schema-low,plain-medium')
    ap.add_argument('--medium-repeats', type=int, default=1)
    ap.add_argument('--max-tokens', type=int, default=2048, help='cap per answer, thinking included (stops runaways)')
    ap.add_argument('--pause', type=float, default=8, help='seconds of rest for the GPU between requests')
    a = ap.parse_args()
    primer = open(os.path.join(HERE, 'livecode_primer.md'), encoding='utf-8').read()
    results = []
    for mode in a.modes.split(','):
        reps = a.medium_repeats if mode.endswith('medium') else a.repeats
        for name, task, must in TASKS:
            for rep in range(reps):
                res = ask(a.model, primer, task, mode, a.max_tokens)
                if 'error' in res:
                    ok, missing, bad = False, ['(request failed)'], []
                else:
                    missing, bad = score(res['code'], must)
                    ok = not missing and not bad
                results.append({'mode': mode, 'task': name, 'rep': rep, 'pass': ok, 'missing': missing, 'bad': bad, **res})
                print('%-13s %-14s %s  %5.1fs  think=%s%s' % (mode, name, 'PASS' if ok else 'fail', res.get('secs', 0),
                      res.get('reasoning_tokens'), ('  missing:' + ' | '.join(missing) if missing else '') +
                      ('  bad:' + ' | '.join(bad) if bad else '')), flush=True)
                json.dump(results, open(os.path.join(HERE, 'eval_results.json'), 'w'), indent=1)  # kept if stopped
                time.sleep(a.pause)   # let the GPU cool between requests
    json.dump(results, open(os.path.join(HERE, 'eval_results.json'), 'w'), indent=1)
    print('\nSUMMARY  (mode: passed/total, median seconds, median thinking tokens)')
    for mode in a.modes.split(','):
        rs = [r for r in results if r['mode'] == mode]
        med = lambda xs: sorted(xs)[len(xs) // 2] if xs else 0
        print('%-13s %d/%d  %.0fs  %s' % (mode, sum(r['pass'] for r in rs), len(rs), med([r.get('secs', 0) for r in rs]),
                                         med([r.get('reasoning_tokens') or 0 for r in rs])))


if __name__ == '__main__':
    main()
