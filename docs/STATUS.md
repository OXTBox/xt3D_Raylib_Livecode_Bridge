# Status

Last updated 2026-11-11.

## Proven on Windows 11, LiveCode Community 9.6.3 (x86_64), raylib 6.2, VS 2022

- The shim compiles with MSVC and links against the prebuilt static raylib (`/MD` is required).
- `xt3d.lcb` compiles and loads in the Extension Builder.
- Integers, decimals and strings pass from LiveCode to raylib correctly, with up to 15 arguments in one call.
- Numbers, booleans and text results come back correctly.
- Rendering to an off-screen texture with the raylib window hidden.
- Copying the frame into a LiveCode image through `xt3d_RenderTextureImageData` at about 60 frames a second (800 x 600).
- LiveCode controls drawn on top of the 3D image.
- Mouse picking against a model (`xt3d_GetScreenToWorldRayEx` + `xt3d_GetRayCollisionModel`).
- Stop and restart within one LiveCode session.
- raylib's own visible window running alongside the LiveCode IDE, with 4x MSAA.
- Loading OBJ (+MTL), GLB and glTF models; bounding boxes; auto-fit.
- Pixel-exact display on a 125% scaled display using the stack `scaleFactor`.
- Supersampled anti-aliasing (render at 2x, shrink with bilinear filtering).

## Built but not yet confirmed on a real machine

- `xt3d_SetBackfaceCulling`, `xt3d_SetCullFace`, `xt3d_SetWireMode`, `xt3d_SetDepthTest`, `xt3d_SetLineWidth`. They bind and are called; the visual result on `thebox.obj` has not been reported. They are guarded to do nothing when no window is open.
- The current `build.bat` (copies sources to `C:\xt3d` and builds there) has not been run.
- Skeletal animation playback (`xt3d_LoadModelAnimations`, `xt3d_UpdateModelAnimation`). The two character files tried had 64 rigid meshes and no skin, so raylib reported 0 bones and 0 animations. Needs a single skinned mesh to test.
- `xt3d_MeshFromText` against real raylib (tested against a stub only).
- Textures on models, shaders, audio, fonts, 2D drawing beyond `DrawText`.
- macOS and Linux builds. On macOS, raylib's window layer and LiveCode may both want the application main loop.

## Known issues and limits

- Calling GPU-touching handlers before a window exists crashes LiveCode. Only the render-state helpers and `InitWindow`/`InitHidden` are guarded so far.
- `thebox.obj` (exported by iGame3D) has its triangles wound the opposite way to raylib's convention, so it looks inside-out with culling on.
- Text results are assembled one byte at a time in LiveCode Builder, and each byte is treated as one character, so non-ASCII text from raylib (for example a monitor name) will be garbled.
- With the stack `scaleFactor` cancelling display scaling, other controls in that stack draw smaller.
- In hidden-window mode raylib's frame timer and input polling are idle; take time and mouse position from LiveCode.
- Raylib's default shader is unlit. Lighting needs a shader.

## Next steps, in rough order

1. Confirm culling on `thebox.obj` and animation on a skinned GLB.
2. Guard every generated wrapper that needs a window, in `gen_xt3d.py`.
3. MCP bridge: a small stdio MCP server that forwards tool calls over a localhost TCP socket to a listener in LiveCode Script, exposing `xt3d_call`, a command list from the manifest, a screenshot tool, and gated script execution. A watched folder as fallback.
4. A standard lighting shader and the helpers to drive it.
5. Package the frame loop, display-scale handling and anti-aliasing as a reusable script library so a stack needs a few lines, not a pasted demo.
6. Importer for the old iGame3D `.wtf` model format using `xt3d_MeshFromText` (the format is plain text; see `CLAUDE.md`).
7. macOS and Linux builds.
