# xt3d: a raylib bridge for LiveCode

xt3d lets LiveCode Script drive the raylib 3D engine. Game logic is written in LiveCode; the scene is rendered by raylib and shown either inside a LiveCode stack (as an image that ordinary controls can sit on top of) or in raylib's own window.

It grew out of iGame3D, a 2007 Revolution/LiveCode 3D engine and editor. The `ig3d_` external commands of that project are the ancestor of the `xt3d_` handlers here; the goal now is a thin, modern bridge that the xTalk community and their AI agents can build on, not a rebuild of the old editor.

Tested with LiveCode Community 9.6.3 (64-bit, Windows) and raylib 6.2.

## How it fits together

```
LiveCode Script  ──calls──▶  xt3d.lcb  ──binds to──▶  xt3d.dll  ──statically links──▶  raylib
 (your stacks)               LiveCode Builder          xt3d_shim.c +
                             library                   xt3d_generated.inc
```

- `gen_xt3d.py` reads `raylib.h` and writes `xt3d_generated.inc`, `xt3d.lcb` and `xt3d_raylib_manifest.json`. Those three are generated; change the generator, not the output.
- `xt3d_shim.c` is hand-written: handle tables, the text-result buffer, helpers for things raylib exposes only through struct fields or pointers, and the conversion of a rendered frame into LiveCode `imageData`.

## Layout

| Path | What it is |
| --- | --- |
| `gen_xt3d.py` | Generator. `python3 gen_xt3d.py path/to/raylib.h` |
| `xt3d_shim.c` | Hand-written C side of the bridge |
| `xt3d_generated.inc` | Generated: one flat C wrapper per raylib function (493 of 619) |
| `xt3d.lcb` | Generated: LiveCode Builder library, one public `xt3d_` handler per wrapper and helper |
| `xt3d_raylib_manifest.json` | Generated: every raylib function with its `xt3d_` name, parameters, return shape and description, the reason for each skipped one, plus raylib's enums and colours |
| `build.bat` | Windows build and install into the extension folder |
| `testbench/xt3d_testbench.livecodescript` | Test bench: a script-only stack (File > Open Stack) with model browser, orbit camera, render switches, animation controls and a "Run checks" self-test |
| (sibling) `~/projects/LIB_MCP` | Optional. Dev server, compile checks, error log, MCP server: lets Claude Code or a local model drive LiveCode. The bench starts it when present. |
| `mcp/xt3d_tools.py` | xt3d tool pack for LIB_MCP's MCP server: handler search, load models, bench checks |
| `demos/xt3d_view_demo.livecodescript.txt` | Model viewer rendered into a LiveCode image |
| `demos/xt3d_window_demo.livecodescript.txt` | Same scene in raylib's own window |
| `demos/xt3d_diagnostic.livecodescript.txt` | Step-by-step self-test that logs before each call |
| `tools/make_skinned_test.py` | Blender script that builds `test_models/skinned_bend.glb`, a small skinned, animated test model |
| `tools/fbx_to_glb.py` | Blender script: rigged FBX (e.g. Mixamo) to a GLB raylib can animate, with the armature transform baked in |
| `test_models/` | Test assets |
| `3DModels/` | Sample models by format, for import testing |
| `reference/ig3d_2007_api_manifest.json` | The 176 original iGame3D external handlers, for reference |
| `docs/STATUS.md` | What is proven, known issues, next steps |
| `CLAUDE.md` | Working notes for Claude Code in this repository |

## Calling conventions

- Handler names are raylib's with an `xt3d_` prefix: `DrawCube` is `xt3d_DrawCube`.
- Vectors, rectangles and matrices are spread into separate numbers. Colours are four integers 0-255.
- Images, textures, render textures, models, meshes, materials, shaders, fonts, sounds, music and cameras are positive integer handles; 0 means invalid. `xt3d_Unload...` releases the handle.
- Functions that return a struct return a comma-separated string: `xt3d_GetMousePosition()` gives `12.5,-3`.
- Cameras are created with `xt3d_CameraCreate` and passed by handle.
- 126 raylib functions are not wrapped: those needing raw pointers, arrays, callbacks or variable arguments, and raylib's string utilities. The manifest lists each with the reason.

## Build (Windows)

Requirements: Visual Studio 2022 with "Desktop development with C++", and a prebuilt raylib for MSVC (for example `raylib-6.2_win64_msvc16`) unpacked at `C:\xt3d\raylib-6.2_win64_msvc16`.

1. Close LiveCode.
2. Double-click `build.bat` (this folder's copy, or one placed in `C:\xt3d`). It finds Visual Studio by itself, copies the sources to `C:\xt3d` (from the WSL project folder when run from `C:\xt3d`), compiles `xt3d.dll`, and installs the DLL and `xt3d.lcb` into `C:\xt3d\extension`. The window stays open so you can read the result.
4. In LiveCode: Tools → Extension Builder → open `C:\xt3d\extension\xt3d.lcb` → Test.
5. In the message box: `put xt3d_Version()` should answer `xt3d 0.1.0 / raylib 6.2`.

Set `XT3D_SRC`, `XT3D_WORK` or `XT3D_RAYLIB` before running `build.bat` to use other folders. The DLL must match LiveCode's bitness (`put the processor`).

The compile command, for reference:

```
cl /nologo /O2 /MD /LD /TC xt3d_shim.c /I <raylib>\include /Fe:xt3d.dll /link <raylib>\lib\raylib.lib opengl32.lib gdi32.lib winmm.lib user32.lib shell32.lib
```

## Running the demos

Paste a demo file into the card script of a new stack, click Apply, and type its start command in the message box.

| Demo | Start | Stop |
| --- | --- | --- |
| View demo | `xt3dStart` (asks for a model file) | `xt3dStop` |
| Window demo | `xt3dWinStart` | `xt3dWinStop` |
| Diagnostic | `xt3dDiag2` | runs once; log in `C:\xt3d\diag_log.txt` |

Stop one demo before starting another.

## Rules that will save you a crash

- Call `xt3d_InitWindow` or `xt3d_InitHidden` before anything that draws or loads GPU resources. Most of raylib crashes if called without a window.
- Make every call from LiveCode's main thread (normal script execution does).
- A handle is only valid until it is unloaded or the window is closed.
- On displays scaled above 100%, set the stack's `scaleFactor` to `1 / the screenPixelScale` and size the view in real pixels, as the view demo does. Otherwise LiveCode stretches the image and edges look rough.
