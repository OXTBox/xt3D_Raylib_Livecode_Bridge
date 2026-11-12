# Vector 3D game engine in LiveCode 9.6.3

A primitive 3D engine/editor written entirely in LiveCode script, drawing
1983 Star Wars arcade / Vectrex style wireframes with LiveCode line graphics.
Games: Canyon (3D canyon run, port of the 2D "Defensive"), Hunter (FPS gem
hunter, "Pac-man meets Halo"), Demo. Local LLM (LM Studio) integration through
LIB_LLM. The owner develops in the LiveCode IDE and plays the games; Claude writes
and debugs engine and game code.

## The loop: how to work on this project

LiveCode is running with `LIB_DEVSERVER` started (APP.init starts it in the IDE).
`tools/lc.sh` talks to it; the scripts live as text files under `scripts/`:

| target            | file                                        |
|-------------------|---------------------------------------------|
| `stack`           | `scripts/stack.livecodescript` (the ENGINE) |
| `card:Play.<game>`| `scripts/cards/Play.<game>.livecodescript`  |
| `card:LIB_<name>` | `scripts/cards/LIB_<name>.livecodescript`   |

1. **`tools/lc.sh pull-all` first, every session and before editing a file.** The
   owner edits in the IDE too; the running stack is the truth, not the files.
   Then `git diff` shows what they changed since last time: read it, keep it.
2. Make **targeted edits** (Edit tool) to the file. Never regenerate a whole
   script from memory: the stack script is ~8000 lines and holds the owner's
   own fixes.
3. `tools/lc.sh push <file>` -> `OK` or `COMPILE ERROR: <line>,<col> ...`. Fix
   and push again until OK. Play./Edit_ cards are saved to their custom property
   set automatically; LIB_ cards are reloaded as libraries.
4. Test: `tools/lc.sh run 'Game.Rebuild "Hunter"'`, `tools/lc.sh eval 'the
   number of controls of this card'`, `tools/lc.sh report 'Play.*'`.
   Pushing the stack script resets its script locals: `tools/lc.sh run APP.init`.
5. Commit with git when something works.

Things only the owner can judge (how it looks, how it plays, frame rate feel):
ask them to look. When unsure whether a change is safe for the stack script,
offer a **standalone button script** to try first (the owner prefers testing
that way before the engine is changed).

LM Studio runs at `http://localhost:1234` (OpenAI API). `tools/lc.sh llm '...'`
asks it directly, useful for cheap bulk work (generating test data, level recipes).

## LiveCode 9.6.3 gotchas (all learned the hard way)

- Setting a group's rect MOVES its contents. Never set the rect of a group that
  holds placed objects; put children's rects back afterwards.
- A group can only be deleted with `cantDelete` false; delete groups from
  `closeCard` (Menu.Purge runs there).
- Only top-level groups can be `place`d. AudioPlayers lives INSIDE the Viewport
  background group and is never placed on its own.
- `does not begin with` is not LiveCode: use `not (x begins with y)` or char ranges.
- A one-line `if c then x` followed by an `else` line takes that else as its own.
  Use block form when in doubt.
- Reserved words: `engine` (engine graphics use custom property `Entity` = true),
  `pi`/`pI` (use pIter), `size`, `mode`.
- Custom property names must start with a letter ("1983" -> "Preset_1983").
- Always set the customPropertySet back to empty after using a set.
- Array custom properties in sets: `do "set the" && tName && "of tObj to tV"`.
- `the keys of the outerGlow of x` can't be inline: read into a variable first.
  Graphic effects are set one key at a time; outerGlow blendMode "normal"
  (colorDodge is invisible on black).
- Card scripts can't see stack-script locals; use globals or handlers.
- `create stack` changes the defaultStack: save and restore it.
- `post`/`get url` block and time out after the socketTimeoutInterval (10 s
  default); use tsNet async (`tsNetPost`) for anything slow.
- A library stack sits in every message path: no openCard/mouseUp etc. in LIB_
  scripts, and no references to fields/buttons.
- Visiting a card to prepare it: `lock screen` + `lock messages`, go back after.
- FPS look: screenMouseLoc / lockCursor.
- `relayer control id N to front of group "G"` moves a control into a group.

## Stack layout

Cards:
- `Developer`: code and break things. Every exit and error goes back here,
  never to a game card.
- `Title`: main menu.
- `Play.<game>`: one per game. Viewport (background group) + script from GAME_CARD_SCRIPTS
  + group "User" (the owner's own objects).
- `Edit_HUD` (Game_Huds set), `Edit_Title`/`Edit_Pause`/`Edit_Options` (menu templates
  TemplateTitle/TemplatePause/TemplateOptions, copied in by Menu.Open, removed by
  Menu.Purge), `Edit_Viewport` (adopted into the Viewport), `Edit_Styles` (ViewPresets),
  `Edit_Procedurals`, `Edit_Level`, `Edit_Trace`.
- `LIB_<name>`: library scripts (see Libraries).

Custom property sets on the main stack:
- `GAME_CARD_SCRIPTS[game]`, `EDIT_CARD_SCRIPTS[name]`: the card scripts
  (save.card.script.to.set / load.card.script.from.set).
- `GAME_ENTITIES[game]["GameScripted"|"User"]`: saved for rebuilds.
- `ViewPresets`, `Game_Huds`, `Procedural_Geometry`.

**Rebuild:** `Game.Rebuild game[,goThere]` saves entities, deletes the card,
recreates it from Developer, re-adds the user objects and the script, then
prepares it. The "User" group is ALWAYS card-sized: four invisible 2x2 anchors
ATL/ATR/ABL/ABR in the corners, margins 0, lockLoc true (`Entities.UserGroup`), so
its rect never changes. Capture skips the anchors.

## Engine (stack script) essentials

- World axes: +X right, **+Y DOWN** (up is -Y), +Z away/forward.
- Loop: fixed step, kStepMS = 33. `game.loop.start/stop`, `game.update`, `game.render`.
- Meshes: arrays with count, vx/vy/vz, faces (n-gons, one per line), lines.
  Generators return raw meshes: `MeshBox w,h,d`, `MeshPrism sides,r,h`,
  `MeshPyramid sides,r,h`, `MeshLathe profile,sides`, `MeshSphere r,rings,sides`,
  `MeshLoft`, `MeshExtrude outline,depth`, `MeshGrid cols,rows,spacing`,
  `Mesh.Transform m,rx,ry,rz,tx,ty,tz,scale`, `Mesh.Merge a,b`.
  `Mesh.Define "Name", mesh` caches it (gMeshCache).
- Objects: `put Entity.Spawn(mesh,x,y,z,colour) into tId`, `Entity.Kill tId`,
  `Scene.AddObject`, `SetObjectPosition/Rotation/RotationSpeed/Velocity`,
  `Scene.SetBob`, gObjectTransforms[key]. Drawn in colour batches
  ("Batch_<colour>") with depth bands.
- Collisions: `Collision.SetGroup key,group[,radius]`, `Collision.AddRule a,b`,
  `Collision.ClearRules`; the card gets `Collision.Hit a,b`.
- FX and weapons: `FX.Derez`, `FX.Destroy`, particles, and `Weapon.FireAt`
  (the card gets `Game.OnKill key,x,y,z`).
- HUD (vector font): `HUD.Set/Remove/Clear`.
- Look: `View.UsePreset/SavePreset/Set/Toggle/Apply`.
- Audio: `Sound.Play`, with files from StackDirectory.
- Menus: `Menu.Open/Close/CloseAll/Purge`. `Menu.Threedots.Build` fills the
  Viewport's threedots menu.
- Messages: `UI.Message text` (graphic "Message"), `UI.update.status.display` (graphic "Status").
- Diagnostics: `Report.Compact([cardFilter])`, `Engine.Info`.

**Game card hooks** (dispatched by the engine to the game card):
- `Game.OnStart`, `Game.OnUpdate`
- `Game.OnClick x,y,button`
- `Game.OnKill key,x,y,z`
- `Game.OnPause`, `Game.OnResume`, `Game.OnStop`
- `Collision.Hit a,b`

Game flow: `Game.Select`, `Game.Play`, `Game.Prepare.Card`, `Game.Exit`, `Game.Pause`.

## Libraries

A card named `LIB_<name>` holds a library script. `Lib.Load name` / `Lib.LoadAll`
(stack script) copy it into an unsaved library stack `LIB_<name>_SCRIPT` and
`start using` it.
- **LIB_LLM:** `LLM.Init url,model`, `LLM.SetSystem`, `LLM.Ask(text,target,msg)`
  (async, tsNet; the reply is dispatched as `msg reply,id,error`), `LLM.AskSync`,
  `LLM.Ping()`, `LLM.Set/Get`, `LLM.Clear`, `LLM.Cancel`. Gemma models get the
  system prompt folded into the first user turn.
- **LIB_DEVSERVER:** the bridge used by tools/lc.sh. It runs any code it is sent,
  so it is development only, bound to 127.0.0.1 and token-checked.

## Style of the code

- Handler names are Dotted.Case (`Game.Rebuild`, `Entities.Capture`).
- Locals: `t` prefix; parameters: `p`; script locals: `s`; globals: `g`; booleans: `b`.
- `##` comments explain *why* in plain words.
- Scripts in the IDE use CR line ends. The owner's exported .txt copies have CRLF.

## Current direction

- Bug-hunting the delete-and-rebuild of game cards (working as of 11/10/2026).
- Next: LLM-designed levels. Gemma fills a small, schema-constrained JSON
  "recipe" (LM Studio `response_format` json_schema, grid cells 0-9, enum
  kinds). LiveCode validates and clamps it, and `Hunter.BuildFromRecipe` turns it
  into spawns. Recipes are requested in the background between levels, with
  random generation as the fallback.
- Optional cleanup: the empty duplicate card `Edit_Viewports` (plural) can be deleted.
