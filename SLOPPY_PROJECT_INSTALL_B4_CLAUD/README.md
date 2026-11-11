# xt3d bridge, first cut

LiveCode 9.6 ↔ raylib 6.5-dev. Nothing here has been run inside LiveCode or linked against a real raylib build yet; see "Status".

## Files

| File | What it is |
| --- | --- |
| `gen_xt3d.py` | Reads `raylib.h`, writes the three generated files below. Re-run it when raylib changes. |
| `xt3d_shim.c` | The C library LiveCode binds to. Handle tables, helpers, frame conversion. Includes `xt3d_generated.inc`. |
| `xt3d_generated.inc` | One flat C wrapper per raylib function (493 of 619). |
| `xt3d.lcb` | LiveCode Builder library: one public `xt3d_` handler per wrapper and helper. |
| `xt3d_raylib_manifest.json` | Every raylib function with its `xt3d_` name, parameters, return shape, description, and why any skipped one was skipped. Also all raylib enums and colour constants. Feed this to an agent or an MCP tool list. |
| `xt3d_demo.livecodescript` | Spinning cube rendered into a LiveCode image, with picking. |

## Conventions

- Names are raylib's with an `xt3d_` prefix: `DrawCube` → `xt3d_DrawCube`.
- Vectors, rectangles and matrices are spread into separate numbers. Colours are four integers 0–255.
- Images, textures, models, meshes, shaders, sounds, music, fonts and cameras are integer handles. 0 means invalid. `Unload…` releases the handle.
- Functions that return a struct return a comma-separated string: `xt3d_GetMousePosition()` → `12.5,-3`.
- Cameras are created with `xt3d_CameraCreate` and passed by handle, so `xt3d_UpdateCamera` can modify them.

## Build

1. Build raylib 6.5 as a static library for your platform.
2. Compile the shim (commands for Windows, macOS and Linux are at the top of `xt3d_shim.c`). The result must be named `xt3d.dll`, `libxt3d.dylib` or `libxt3d.so`.
3. Use the same bitness as LiveCode: 64-bit LiveCode needs a 64-bit library.
4. Put `xt3d.lcb` in a folder with the library under `code/<platform>/` (for example `code/x86_64-win32/xt3d.dll`), open it in the Extension Builder and install or test it.
5. Run the demo script.

## Status

- Checked: `xt3d_shim.c` compiles cleanly against the supplied `raylib.h` with `-Wall -Wextra` and exports 527 functions. Handle tables, string returns, mesh building and the frame conversion to LiveCode `imageData` layout were tested against a stub raylib.
- Not checked: linking against real raylib, anything on the GPU, and the whole of `xt3d.lcb`, which was generated without a LiveCode compiler to hand.
- First things likely to need adjusting in `xt3d.lcb`: the `binds to` library path for your platform, and the `MCDataCreateWithBytes` binding used by `xt3d_RenderTextureImageData`. If that binding fails, `xt3d_RenderTextureExport` to a PNG plus `set the filename of image` is a slower path that needs no pointer handling.
- Rendering happens with the raylib window hidden and without `BeginDrawing`/`EndDrawing`, so raylib's own frame timer and input polling are idle. Take time and mouse position from LiveCode, as the demo does. For a visible raylib window, use `xt3d_InitWindow` and the normal `BeginDrawing`/`EndDrawing` pair.
