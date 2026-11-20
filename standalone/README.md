# xt3d bench standalone

The xt3d test bench as a Windows application, with the LIB_MCP server inside (port 8768),
so Claude can load models, render LIB_MAP levels and take snapshots without the IDE.

## How xt3d gets in

The bench loads the xt3d extension itself when it runs in a standalone: from
`C:\xt3d\extension\module.2.lcm`, with `the revLibraryMapping["xt3d"]` pointing at
`C:\xt3d\extension\code\x86_64-win32\xt3d.dll` (both put there by `build.bat` and the
Extension Builder's Test). So the standalone always uses the latest xt3d build and needs
no inclusion settings. (Including the extension at build time did not work: the builder
left it out even after Install.)

## Build (done 2026-11-11; only changes to launcher.livecodescript need a rebuild)

1. New stack `xt3d_Bench`; paste `launcher.livecodescript` as its stack script; save it
   here as `standalone\xt3d_Bench.livecode`.
2. File > Save as Standalone Application (Windows). The build lands in
   `standalone\xt3d_Bench\xt3d_Bench.exe`. LiveCode cannot overwrite a running copy: quit
   it first (close its small status window), or the build goes to a new folder.

The launcher walks up from the .exe to find `testbench/xt3d_testbench.livecodescript` and
the sibling `LIB_MCP` project, starts LIB_MCP on port 8768 and opens the bench. Both load
from their files, so changes to them need no rebuild.

## Use

`tools/bench ping | run | eval | snap | reload | checks` starts it when needed.
Close its small status window to quit it.

# The games bench standalone (xt3d_Bench_LibMCP)

The bench with games (`testbench/xt3d_testBench_lib_mcp.livecodescript`): everything the
bench does, plus a **Games** button that lists the Vibecode3D game card scripts in
`../LIB_GAMES/Vibecode3D_Games` and plays them in the 3D view. An **Editor** button lists LIB_EDITOR's
example cards (`../LIB_EDITOR/examples`, E01..E13, e.g. E13 Walk The Map) and plays them the same way. LIB_MCP runs on port **8770**.

## Build

1. New stack `xt3d_Bench_LibMCP`; paste `launcher_lib_mcp.livecodescript` as its stack
   script; save it here as `standalone\xt3d_Bench_LibMCP.livecode`.
2. File > Save as Standalone Application (Windows). The build lands in
   `standalone\xt3d_Bench_LibMCP\xt3d_Bench_LibMCP.exe`.

As with the plain bench, the launcher finds the bench, LIB_MCP and xt3d from their files,
so changes to them need no rebuild. `tools/gamebench ping | run | eval | snap` starts and
drives it.

## How a game runs

Clicking a game puts its script into the bench's card (like a `Play.<Game>` card) and
loads `testbench/vibe_engine_xt3d.livecodescript`: the owner's whole Vibecode3D engine,
made by `tools/make_vibe_xt3d.py` from the newest script in `Vibecode3D/livecode`, with
the LiveCode drawing swapped for xt3d (`testbench/vibe_xt3d_overrides.livecodescript`).
Each mesh becomes one xt3d model of lines; the HUD, particles and lasers are 2D lines.
After saving a new engine script, run `python3 tools/make_vibe_xt3d.py` again.
