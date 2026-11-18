#!/usr/bin/env python3
"""make_vibe_xt3d.py - build the xt3d edition of the Vibecode3D engine.

Reads the owner's newest Vibecode3D stack script (Vibecode3D/livecode/*.livecodescript,
or a file given on the command line) and writes testbench/vibe_engine_xt3d.livecodescript:
a script-only library stack ("VibeEngineXt3d") holding the WHOLE engine unchanged, except:

  * every handler that testbench/vibe_xt3d_overrides.livecodescript also defines is renamed
    Vibe.Orig.<name>, and the overrides file is appended (so its handlers share the engine's
    script locals: sOrigColor, sView, sLoopActive ...);
  * card/stack system messages the bench must not get from a library (openCard, closeCard,
    mouseUp) are renamed Vibe.Unused.<name>;
  * the contract's own calls (LIB_ig3d/livecode/contract_calls.livecodescript, hand-written:
    Camera.SetLook, Entity.Set ...) are appended after the overrides and treated the same way
    (a handler there that the engine has replaces it); one name in both files is an error;
  * the Rename Day aliases (LIB_ig3d/livecode/contract_aliases.livecodescript, written by
    LIB_ig3d/tools/make_names.py from the engine contract) are appended last: the new
    Group.Verb names (Entity.SetPosition, Mesh.Box, Camera.Reset ...) pass to the handlers that
    still have the old names. An alias whose name the engine or the overrides already define
    is left out, so the day the engine takes a new name itself nothing is defined twice.

Run it again after every new save of the engine script; the result is committed so a
standalone build always has it.
    python3 tools/make_vibe_xt3d.py [ENGINE_SCRIPT]
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECTS = os.path.dirname(HERE)
OVERRIDES = os.path.join(HERE, "testbench", "vibe_xt3d_overrides.livecodescript")
OUT = os.path.join(HERE, "testbench", "vibe_engine_xt3d.livecodescript")
ALIASES = os.path.join(PROJECTS, "LIB_ig3d", "livecode", "contract_aliases.livecodescript")
CALLS = os.path.join(PROJECTS, "LIB_ig3d", "livecode", "contract_calls.livecodescript")
UNUSED = {"opencard", "closecard", "mouseup"}
HANDLER = re.compile(r"^(\s*)(private\s+)?(on|function|command|getprop|setprop)(\s+)([A-Za-z0-9_.]+)", re.I)


def newest_engine():
    files = glob.glob(os.path.join(PROJECTS, "Vibecode3D", "livecode", "*.livecodescript"))
    files = [f for f in files if "harvest" not in os.path.basename(f).lower()
             and not os.path.basename(f).startswith("LCHarvest")]
    if not files:
        sys.exit("no engine script in Vibecode3D/livecode")
    return max(files, key=os.path.getmtime)


def handler_names(lines):
    return {m.group(5).lower() for m in (HANDLER.match(l) for l in lines) if m}


def aliases(have):
    """The alias handlers, whole, except those whose name is already in `have` (lower case)."""
    if not os.path.exists(ALIASES):
        return [], [], None
    with open(ALIASES, encoding="utf-8") as f:
        lines = f.read().replace("\r\n", "\n").split("\n")
    out, added, skipped, skip = [], [], [], False
    for line in lines:
        m = HANDLER.match(line)
        if m:
            skip = m.group(5).lower() in have
            (skipped if skip else added).append(m.group(5))
        if not skip:
            out.append(line)
        elif re.match(r"^\s*end\s+[A-Za-z0-9_.]+\s*$", line, re.I):
            skip = False
    return out, added, skipped


def main():
    src_path = sys.argv[1] if len(sys.argv) > 1 else newest_engine()
    with open(src_path, encoding="utf-8", errors="replace") as f:
        src = f.read().replace("\r\n", "\n").replace("\r", "\n").lstrip("﻿").split("\n")
    with open(OVERRIDES, encoding="utf-8") as f:
        over = f.read().replace("\r\n", "\n").split("\n")
    with open(CALLS, encoding="utf-8") as f:
        calls = f.read().replace("\r\n", "\n").split("\n")
    if calls and calls[0].lower().startswith("script "):
        calls = calls[1:]
    if src and src[0].lower().startswith("script "):
        src = src[1:]
    both = handler_names(over) & handler_names(calls)
    if both:
        sys.exit("defined in both the overrides and contract_calls: " + " ".join(sorted(both)))
    replaced = handler_names(over) | handler_names(calls)
    out, renamed, current = [], [], None
    for line in src:
        m = HANDLER.match(line)
        if m:
            name = m.group(5)
            if name.lower() in replaced or name.lower() in UNUSED:
                prefix = "Vibe.Orig." if name.lower() in replaced else "Vibe.Unused."
                current = (name, prefix)
                renamed.append(prefix + name)
                line = line[:m.start(5)] + prefix + name + line[m.end(5):]
            else:
                current = None
        elif current:
            e = re.match(r"^(\s*end\s+)" + re.escape(current[0]) + r"\b", line, re.I)
            if e:
                line = e.group(1) + current[1] + current[0] + line[e.end():]
                current = None
            else:
                # "exit <name>" inside the handler must name it as renamed; "pass <name>"
                # becomes "exit": the replaced message must not travel on
                line = re.sub(r"\bexit\s+" + re.escape(current[0]) + r"(?![\w.])",
                              "exit " + current[1] + current[0], line, flags=re.I)
                line = re.sub(r"\bpass\s+" + re.escape(current[0]) + r"(?![\w.])",
                              "exit " + current[1] + current[0], line, flags=re.I)
        out.append(line)
    missing = sorted(replaced - handler_names(src))
    header = [
        'script "VibeEngineXt3d"',
        "-- GENERATED by xt3d tools/make_vibe_xt3d.py: do not edit; change the overrides file",
        "-- (testbench/vibe_xt3d_overrides.livecodescript) or the engine, then run it again.",
        "-- Engine source: " + os.path.relpath(src_path, PROJECTS),
        "",
    ]
    alias_lines, added, skipped = aliases(handler_names(out) | handler_names(over) | handler_names(calls))
    text = "\n".join(header + out + ["", ""] + over + ["", ""] + calls + ["", ""] + alias_lines).rstrip("\n") + "\n"
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote", os.path.relpath(OUT, HERE), "from", os.path.relpath(src_path, PROJECTS))
    print("renamed:", " ".join(renamed))
    if skipped is None:
        print("NO ALIASES: LIB_ig3d/livecode/contract_aliases.livecodescript not found")
    else:
        print("aliases appended (%d):" % len(added), " ".join(added))
        if skipped:
            print("aliases left out, the engine has the name itself:", " ".join(skipped))
    if missing:
        print("overrides with no engine handler of that name (new handlers):", " ".join(missing))


if __name__ == "__main__":
    main()
