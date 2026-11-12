# ClaudeRead: what Claude has read, and what was worth keeping

Items here have been read. Each entry says what it is, what was taken from it, and
what is worth remembering. Newest first.

---

## LiveCode_Claude_Kit/ (read 2026-11-11)

**What it is.** The working kit from the owner's other project, a vector-wireframe
3D engine written in pure LiveCode script (games Canyon, Hunter, Demo; LM Studio
integration). Three parts:

| File | What it is |
| --- | --- |
| `kit/scripts/cards/LIB_DEVSERVER.livecodescript` | HTTP server inside the IDE: Claude sends LiveCode code, gets results and compile errors back |
| `kit/tools/lc.sh` | Command-line client for it (bash + curl) |
| `kit/CLAUDE.md` | That project's working notes: the edit/push/test loop, LiveCode gotchas, engine layout |

**Taken into xt3d.** `LIB_DEVSERVER` became `testbench/xt3d_devserver.livecodescript`,
and `lc.sh` became `tools/xt3d_dev.sh` (commit 5dfb3f5). Changes for xt3d:
- a script-only library stack instead of a LIB_ card
- the token file is `C:/xt3d/.xt3d_devtoken`, and the port is 8766, so it doesn't
  clash with the vector engine's 8765
- new routes: `reload` (reopen the bench from its file) and `snap` (PNG for Claude to look at)
- requests go through Windows' `curl.exe`, because WSL2 can't reach Windows' 127.0.0.1

**Worth remembering**

- *Security model.* Answer only 127.0.0.1, require a custom `X-Token` header with a
  fresh 32-character token per start, and write the token to a file only local tools
  can read. The custom header also stops web pages from calling in. Development only:
  it runs any code it is sent.
- *The working loop* (from its CLAUDE.md), proven on a ~8000-line stack script:
  1. pull the live script first, because the owner edits in the IDE too
  2. make targeted edits to the text file, never regenerate a whole script
  3. push, which answers `OK` or `COMPILE ERROR: line,col`
  4. test with run/eval, then commit
  5. leave look-and-feel judgements to the owner, and offer a standalone button
     script before risky engine changes

  xt3d's bench is a script-only file, so step 1 isn't needed here. Steps 2 to 5 apply.
- *LiveCode 9.6.3 gotchas* (learned the hard way there; most apply anywhere):
  - `does not begin with` is not LiveCode: use `not (x begins with y)`.
  - A one-line `if c then x` followed by an `else` line takes that `else` as its own.
    Use block form.
  - Reserved words that break as variable names: `engine`, `pi`, `size`, `mode`.
  - `create stack` changes the defaultStack: save and restore it.
  - Custom property names must start with a letter. Always set `customPropertySet`
    back to empty after using a set.
  - `post` and `get url` block until the `socketTimeoutInterval` (10 s): use tsNet
    async (`tsNetPost`) for anything slow.
  - A library stack sits in every message path: no openCard or mouseUp handlers in
    library scripts, and no references to fields or buttons.
  - Setting a group's rect moves its contents.
  - Only top-level groups can be `place`d. Delete groups from `closeCard`, with
    `cantDelete` false.
  - Card scripts can't see stack-script locals.
  - Preparing a card: `lock screen` and `lock messages`, then go back.
- *LM Studio* runs at `http://localhost:1234` (OpenAI-style API) on the owner's
  machine. The kit asks it for cheap bulk work, and its LIB_LLM is an async tsNet
  client. Relevant to the planned MCP link "for a local model".
- *Style the owner uses:* Dotted.Case handler names. Prefixes: `t` for locals, `p`
  for parameters, `s` for script locals, `g` for globals, `b` for booleans. `##`
  comments explain why.

**Not taken.** The engine-specific parts of its CLAUDE.md: stack layout, game card
hooks, Rebuild, mesh generators, +Y-down world axes. They belong to the vector
engine, not xt3d.

---

## LCHarvest2.livecodescript (read 2026-11-11: header, options and handler list)

**STALE COPY.** The current harvester is `~/projects/XTJSON/xtjson/LCHarvest2.livecodescript`. That one writes `layer` and has the `tExt` -> `tSuffix` fix; this copy still has the `tExt` compile error. Use the XTJSON one.

**What it is.** A pure-script LiveCode 9.6.3 exporter that turns a whole stack, one
card or one control into JSON for LLMs and GUI generators. It replaces the 2007/2021
iGame3D "Controls Harvester". The stack it harvests is only read, never changed.

**API**
- `harvestStack [stack], [outFolder], [options]`
- `harvestCard [card], ...`
- `harvestCardJSON(card)`, `harvestControlJSON(control)`: JSON in memory, no files
- `harvestTypeDefaultsJSON()`, `harvestErrors()`

**Output.** `manifest.json` plus `stack_<Name>.json` (stack, then cards, then
controls, with groups nested). Alongside: `scripts/*.livecodescript` (one per scripted
object, with a handler index and line numbers), `assets/` (embedded images) and
`blobs/` (oversize values).

**Main options**
- `sparse`: only properties that differ from a fresh object of that type
- `dedupeShared`: background groups are written in full once
- `scripts`: `files`, `inline` or `none`
- `ideProps`: keep the IDE's own `cREV*` properties
- `maxInline`: size above which text goes to `blobs/`

**Worth remembering.** This is how Claude could "see" a LiveCode stack's layout
and scripts as text without screenshots: a sparse JSON is small enough to read
whole. Two possible uses in xt3d:
1. A dev-server route (`/harvest`) answering `harvestCardJSON` for the bench or any
   stack the owner is building. Claude could then read layouts and fix them.
2. An MCP tool for the same, so a local model can understand a stack before
   editing it.

Not used yet. The rest of the file (property defaults, JSON writer helpers) was not
read line by line.
