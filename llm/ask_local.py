#!/usr/bin/env python3
"""ask_local.py - ask a local LM Studio model a question, letting it use the xt3d tools.

    python3 llm/ask_local.py "Which xt3d command draws a sphere?"
    python3 llm/ask_local.py --model qwen2.5-7b-instruct-1m --no-tools "..."

Runs the tool loop itself (the same tools as llm/xt3d_mcp.py), so it works through
LM Studio's plain chat API without the LM Studio app's MCP support. Prints each tool
call, then the answer. LM Studio is reached through Windows' curl.exe.
"""
import argparse, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xt3d_mcp

URL = 'http://127.0.0.1:1234/v1/chat/completions'
SYSTEM = ('You help with the xt3d project: raylib 3D for LiveCode 9.6.3. You can call tools to look up '
          'xt3d handlers, read a LiveCode primer, and run code in the user\'s LiveCode test bench. '
          'Read livecode_primer before writing any LiveCode Script; LiveCode is not JavaScript or Python. '
          'Use xt3d_find_handlers to look up exact xt3d names and parameters instead of guessing. '
          'Answer briefly.')


def chat(model, messages, tools, effort):
    body = {'model': model, 'messages': messages, 'temperature': 0.2, 'max_tokens': 2048}   # thinking included; caps runaways
    if effort:
        body['reasoning_effort'] = effort
    if tools:
        body['tools'] = tools
    r = subprocess.run(['curl.exe', '-sS', '-m', '600', URL, '-H', 'Content-Type: application/json',
                        '--data-binary', '@-'], input=json.dumps(body).encode('utf-8'), capture_output=True)
    if r.returncode != 0:
        sys.exit('LM Studio not answering at %s: %s' % (URL, r.stderr.decode(errors='replace')))
    d = json.loads(r.stdout.decode('utf-8', 'replace'))
    if 'choices' not in d:
        sys.exit('LM Studio error: %s' % d)
    return d['choices'][0]['message']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('question')
    ap.add_argument('--model', default='spark-x2.6-4b')
    ap.add_argument('--effort', default='low', help='reasoning effort: low/medium/high, or "" to omit')
    ap.add_argument('--no-tools', action='store_true')
    ap.add_argument('--max-steps', type=int, default=8)
    a = ap.parse_args()
    tools = None if a.no_tools else [
        {'type': 'function', 'function': {'name': n, 'description': d, 'parameters': s}}
        for n, _, d, s in xt3d_mcp.TOOLS if n != 'bench_snapshot']   # text-only models
    messages = [{'role': 'system', 'content': SYSTEM}, {'role': 'user', 'content': a.question}]
    for _ in range(a.max_steps):
        m = chat(a.model, messages, tools, a.effort)
        calls = m.get('tool_calls') or []
        if not calls:
            print(m.get('content') or '(no answer)')
            return
        messages.append({'role': 'assistant', 'content': m.get('content') or '', 'tool_calls': calls})
        for c in calls:
            name = c['function']['name']
            try:
                args = json.loads(c['function'].get('arguments') or '{}')
            except ValueError:
                args = {}
            content, err = xt3d_mcp.call_tool(name, args)
            text = '\n'.join(x.get('text', '') for x in content)
            print('[tool] %s %s -> %s' % (name, json.dumps(args), text[:160].replace('\n', ' | ')), file=sys.stderr)
            messages.append({'role': 'tool', 'tool_call_id': c.get('id', ''), 'content': text})
    print('(stopped after %d steps)' % a.max_steps)


if __name__ == '__main__':
    main()
