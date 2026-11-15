#!/usr/bin/env python3
"""xt3d's check that runs without LiveCode or a C compiler (A-50): gen_xt3d reads raylib's header
lines into functions (name, return type, parameters, module).

    python3 -I tests/run_tests.py
"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import gen_xt3d                             # noqa: E402

CHECKS, FAILS = [0], []


def check(name, ok, got=None):
    CHECKS[0] += 1
    if not ok:
        FAILS.append(name)
        print("FAIL  %s%s" % (name, "" if got is None else "  (got %r)" % (got,)))
    else:
        print("ok    %s" % name)


def done():
    print("\n%d of %d passed" % (CHECKS[0] - len(FAILS), CHECKS[0]))
    return 1 if FAILS else 0


HEADER = """// Window-related functions (Module: core)
RLAPI void InitWindow(int width, int height, const char *title);  // Initialize window
RLAPI bool WindowShouldClose(void);                               // Check if close
// Basic shapes (Module: shapes)
RLAPI void DrawCircle(int centerX, int centerY, float radius, Color color);
RLAPI void TraceLog(int logLevel, const char *text, ...);
"""


def main():
    f = {x['name']: x for x in gen_xt3d.parse(HEADER)}
    check('four functions', sorted(f) == ['DrawCircle', 'InitWindow', 'TraceLog', 'WindowShouldClose'], sorted(f))
    check('parameters with types', f['InitWindow']['params'] == [('int', 'width'), ('int', 'height'), ('const char *', 'title')],
          f['InitWindow']['params'])
    check('void means no parameters', f['WindowShouldClose']['params'] == [] and f['WindowShouldClose']['ret'] == 'bool')
    check('the module comes from the comment above', f['DrawCircle']['module'] == 'shapes' and f['InitWindow']['module'] == 'core')
    check('the doc comment is kept', f['InitWindow']['doc'] == 'Initialize window')
    check('... is kept as a parameter', f['TraceLog']['params'][-1] == ('...', ''))
    return done()


if __name__ == '__main__':
    sys.exit(main())
