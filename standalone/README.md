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
