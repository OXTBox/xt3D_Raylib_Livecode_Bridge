script "xt3dTestBench"
-- xt3d Test Bench: a script-only stack. In LiveCode: File > Open Stack, pick this
-- file. It builds its own controls each time it opens (nothing is saved but this
-- script), so edits to the file show up the next time it is opened.
--
-- WHEN CLOSING THIS STACK, CHOOSE "DON'T SAVE". This file is the source; saving from the
-- IDE writes LiveCode's in-memory copy back over it, which may be older.
--
-- Needs the xt3d extension loaded first (Extension Builder > open
-- C:\xt3d\extension\xt3d.lcb > Test).
--
--   drag on the view ...... orbit the camera
--   mouse wheel on view ... zoom
--   file list ............. click a model to load it; "Folder..." picks another folder
--   Dev server ............ lets Claude Code drive this bench; starts with it. It is the LIB_MCP
--                           library, found as a sibling project (../LIB_MCP); optional
--   Run checks ............ crash guards, pure functions, the test models, a frame copy;
--                           each step is written to C:/xt3d/bench_checks.txt before it runs
--
-- Layout numbers are in "logical" pixels (as at 100% display scaling). The stack's
-- scaleFactor cancels Windows display scaling so the 3D image is never stretched;
-- px() then scales every control back up so they keep their usual size.

constant kRaylibLog = "C:/xt3d/raylib_log.txt"
constant kCheckLog = "C:/xt3d/bench_checks.txt"
constant kTestModels = "C:/xt3d/test_models"
constant kModelTypes = "(?i)\.(glb|gltf|obj|iqm|m3d|vox)$"
constant kViewW = 720      -- view size in logical pixels
constant kViewH = 540
constant kPanelX = 730     -- left edge of the side panel
constant kPanelW = 250
constant kSample = 2       -- 2 = render at double size and shrink (smooth edges); 1 = off
constant kAnimFPS = 60     -- raylib samples glTF animations at 60 key frames a second
constant kSpin = 30        -- degrees a second when Spin is on
constant kFrameMS = 16     -- milliseconds between frames

-- view and GPU resources
local sScale, sViewW, sViewH, sRunning, sFrameMsg
local sTarget, sBig, sBigTexture, sCamera
-- the loaded model
local sModel, sModelPath, sFit, sLift
local sAnimFirst, sAnimCount, sAnim, sAnimFrames, sAnimFrame
-- camera orbit, spin, timing
local sYaw, sPitch, sDist, sAngle, sLastTick, sDragging, sDragX, sDragY
local sFrames, sFPSTick, sFPS
-- browsing and checks
local sFolder, sSettingSlider, sReport

-------------------------------------------------------------------- open / close

on preOpenStack
   set the defaultStack to the short name of me
   put the screenPixelScale into sScale
   if sScale is empty or sScale <= 0 then put 1 into sScale
   -- one stack unit = one screen pixel, so the 3D image is never stretched
   set the scaleFactor of me to 1 / sScale
   set the title of me to "xt3d Test Bench"
   set the resizable of me to false
   set the destroyStack of me to true   -- closing removes it from memory, so reopening reads the file
   set the width of me to px(kPanelX + kPanelW + 10)
   set the height of me to px(kViewH + 130)
   set the textSize of me to px(12)
   put px(kViewW) into sViewW
   put px(kViewH) into sViewH
   if sFolder is empty then put kTestModels into sFolder
   put 0 into sModel
   put 0 into sAnimCount
   put 0 into sAnimFrames
   put 0 into sLift
   put 1 into sFit
   xbBuildControls
   xbListFolder
   xbPlaceWindow
end preOpenStack

-- centre the window on the main screen; a script-only stack has no saved position,
-- and changing scaleFactor and size can leave it hanging off the screen
command xbPlaceWindow
   set the loc of me to the screenLoc
   if the top of me < 30 then set the top of me to 30
   if the left of me < 0 then set the left of me to 0
end xbPlaceWindow

on openStack
   local tError
   try
      get xt3d_Version()
   catch tError
      put "The xt3d extension is not loaded." & return & return & \
            "Extension Builder > open C:\xt3d\extension\xt3d.lcb > Test," & return & \
            "then close and reopen this stack." into field "info"
      exit openStack
   end try
   xbPlaceWindow
   -- the dev server (and its error log) starts with the bench; untick to stop it
   if not xbDevRunning() then xbDevServer true
   put 45 into sYaw
   put 25 into sPitch
   put 5 into sDist
   xbStartView
   put "Ready. " & xt3d_Version() & return & "Click a model in the list, or Run checks." & return & \
         "Dev server:" && xbDevRunning() & ". Errors go to C:/LIB_MCP/livecode_errors.txt" into field "info"
end openStack

on closeStack
   xbStopView
   set the scaleFactor of me to 1
end closeStack

function px pLogical
   return round(pLogical * sScale)
end px

-------------------------------------------------------------------- controls

command xbBuildControls
   local i, tX, tY
   lock screen
   repeat with i = the number of controls of this card down to 1
      delete control i of this card
   end repeat

   xbMake "image", "view", 0, 0, kViewW, kViewH
   set the lockLoc of image "view" to true
   xbMake "field", "log", 0, kViewH + 6, kViewW, 118
   set the vScrollbar of field "log" to true
   set the textSize of field "log" to px(11)

   put kPanelX into tX
   put 8 into tY
   xbMake "button", "folderBtn", tX, tY, 70, 24, "Folder..."
   xbMake "field", "folder", tX + 76, tY + 2, kPanelW - 76, 22
   set the textSize of field "folder" to px(10)
   add 30 to tY
   xbMake "list", "fileList", tX, tY, kPanelW, 150
   add 156 to tY
   xbMake "button", "loadBtn", tX, tY, 120, 24, "Load file..."
   xbMake "button", "checksBtn", tX + 130, tY, 120, 24, "Run checks"
   add 32 to tY
   xbMake "checkbox", "spinChk", tX, tY, 80, 20, "Spin"
   xbMake "checkbox", "gridChk", tX + 85, tY, 80, 20, "Grid"
   xbMake "checkbox", "tintChk", tX + 170, tY, 80, 20, "Tint"
   add 22 to tY
   xbMake "checkbox", "solidChk", tX, tY, 80, 20, "Solid"
   xbMake "checkbox", "wiresChk", tX + 85, tY, 80, 20, "Wires"
   add 22 to tY
   xbMake "checkbox", "cullChk", tX, tY, 80, 20, "Culling"
   xbMake "checkbox", "frontChk", tX + 85, tY, 160, 20, "Cull front faces"
   set the hilite of button "gridChk" to true
   set the hilite of button "tintChk" to true
   set the hilite of button "solidChk" to true
   set the hilite of button "wiresChk" to true
   add 28 to tY
   xbMake "option", "animMenu", tX, tY, kPanelW, 24
   add 30 to tY
   xbMake "checkbox", "playChk", tX, tY + 2, 60, 20, "Play"
   set the hilite of button "playChk" to true
   xbMake "scrollbar", "frameBar", tX + 62, tY, kPanelW - 62, 22
   add 30 to tY
   xbMake "button", "camBtn", tX, tY, 120, 24, "Reset camera"
   xbMake "button", "unloadBtn", tX + 130, tY, 120, 24, "Unload"
   add 30 to tY
   xbMake "checkbox", "devChk", tX, tY, kPanelW, 20, "Dev server (lets Claude drive this bench)"
   set the hilite of button "devChk" to xbDevRunning()
   add 26 to tY
   xbMake "field", "info", tX, tY, kPanelW, kViewH + 124 - tY
   set the vScrollbar of field "info" to true
   set the textSize of field "info" to px(11)
   xbAnimMenu
   unlock screen
end xbBuildControls

-- xbMake type, name, left, top, width, height [, label]   (logical pixels)
command xbMake pType, pName, pLeft, pTop, pWidth, pHeight, pLabel
   switch pType
      case "image"
         create image pName
         break
      case "field"
      case "list"
         create field pName
         set the lockText of it to true
         set the dontWrap of it to (pType is "list")
         if pType is "list" then
            set the listBehavior of it to true
            set the vScrollbar of it to true
         end if
         break
      case "scrollbar"
         create scrollbar pName
         set the style of it to "scale"
         set the startValue of it to 0
         set the endValue of it to 1
         set the showValue of it to false
         break
      default
         create button pName
         if pType is "checkbox" then
            set the style of it to "checkbox"
         else if pType is "option" then
            set the style of it to "menu"
            set the menuMode of it to "option"
         end if
         if pLabel is not empty then set the label of it to pLabel
   end switch
   set the rect of it to px(pLeft), px(pTop), px(pLeft + pWidth), px(pTop + pHeight)
end xbMake

command xbListFolder
   local tFiles, tOld
   put the defaultFolder into tOld
   set the defaultFolder to sFolder
   if the result is not empty then
      put empty into tFiles
   else
      put the files into tFiles
   end if
   set the defaultFolder to tOld
   filter tFiles with regex pattern kModelTypes
   sort lines of tFiles
   put sFolder into field "folder"
   put tFiles into field "fileList"
end xbListFolder

command xbAnimMenu
   local i, tMenu, tInfo
   if sAnimCount > 0 then
      repeat with i = 0 to sAnimCount - 1
         put xt3d_ModelAnimationInfo(sAnimFirst + i) into tInfo
         -- name,boneCount,keyframeCount (the name may itself hold commas)
         put i & ": " & item 1 to -3 of tInfo & " (" & item -1 of tInfo & " frames)" & return after tMenu
      end repeat
      delete the last char of tMenu
   else
      put "(no animations)" into tMenu
   end if
   set the text of button "animMenu" to tMenu
   set the menuHistory of button "animMenu" to 1
end xbAnimMenu

-------------------------------------------------------------------- events

on mouseUp
   put false into sDragging
   switch the short name of the target
      case "folderBtn"
         answer folder "Choose a folder of models" with sFolder
         if it is not empty then
            put it into sFolder
            xbListFolder
         end if
         break
      case "fileList"
         if the selectedText of field "fileList" is not empty then
            xbLoadModel sFolder & "/" & the selectedText of field "fileList"
         end if
         break
      case "loadBtn"
         answer file "Choose a model file (glb, gltf, obj, iqm, m3d, vox)"
         if it is not empty then xbLoadModel it
         break
      case "checksBtn"
         xbRunChecks
         break
      case "camBtn"
         put 45 into sYaw
         put 25 into sPitch
         put 5 into sDist
         put 0 into sAngle
         break
      case "devChk"
         xbDevServer the hilite of button "devChk"
         break
      case "unloadBtn"
         xbUnloadModel
         put "No model loaded." into field "info"
         break
   end switch
end mouseUp

on mouseRelease
   put false into sDragging
end mouseRelease

on mouseDown
   if the short name of the target is "view" then
      put true into sDragging
      put the mouseH into sDragX
      put the mouseV into sDragY
   end if
end mouseDown

on mouseMove pX, pY
   if sDragging is not true then pass mouseMove
   if the mouse is up then
      put false into sDragging
      exit mouseMove
   end if
   subtract (pX - sDragX) * 0.4 from sYaw
   add (pY - sDragY) * 0.4 to sPitch
   put max(-85, min(85, sPitch)) into sPitch
   put pX into sDragX
   put pY into sDragY
end mouseMove

-- the mouse wheel arrives as raw keys 65308 (down) and 65309 (up)
on rawKeyDown pKey
   if (pKey is 65308 or pKey is 65309) and the mouseLoc is within the rect of image "view" then
      if pKey is 65308 then
         multiply sDist by 1.1
      else
         divide sDist by 1.1
      end if
      put max(0.5, min(200, sDist)) into sDist
   else
      pass rawKeyDown
   end if
end rawKeyDown

on menuPick pItem
   if the short name of the target is "animMenu" and sAnimCount > 0 then
      xbSelectAnim the menuHistory of button "animMenu" - 1
   end if
end menuPick

on scrollbarDrag pValue
   if the short name of the target is "frameBar" and sSettingSlider is not true then
      put pValue into sAnimFrame
      set the hilite of button "playChk" to false
   end if
end scrollbarDrag

-------------------------------------------------------------------- dev server

-- the server is the LIB_MCP library (a separate project), so it survives this bench being reloaded
command xbDevServer pOn
   local tPath
   if pOn then
      put xbFindLibMCP() into tPath
      if tPath is empty then
         put "Dev server: LIB_MCP not found next to this project" & return & \
               "(looked for LIB_MCP/livecode/lib_mcp.livecodescript above" && the effective filename of me & ")" into field "info"
         set the hilite of button "devChk" to false
         exit xbDevServer
      end if
      start using stack tPath
      DevServer.Start 8766, the short name of me
      put the result into field "info"
      set the hilite of button "devChk" to xbDevRunning()
   else
      if xbDevRunning() then DevServer.Stop
      put "Dev server stopped." into field "info"
   end if
end xbDevServer

-- walk up from this file; at each folder look for a LIB_MCP project beside it
function xbFindLibMCP
   local tPath, tTry
   put the effective filename of me into tPath
   set the itemDel to "/"
   repeat 6 times
      delete item -1 of tPath
      if tPath is empty then exit repeat
      put tPath & "/LIB_MCP/livecode/lib_mcp.livecodescript" into tTry
      if there is a file tTry then return tTry
   end repeat
   return empty
end xbFindLibMCP

function xbDevRunning
   local tErr
   try
      return DevServer.Running()
   catch tErr
      return false
   end try
end xbDevRunning

-- called by the dev server: run statements / evaluate an expression in this script,
-- so its handlers and script locals are reachable
command DevServer.Exec pCode
   local tErr
   try
      do pCode
   catch tErr
      DevServer.LogError tErr, "/run in the bench"
      return "ERROR:" & return & DevServer.ErrorText(tErr)
   end try
   return the result
end DevServer.Exec

function DevServer.Eval pExpr
   local tErr
   try
      return value(pExpr)
   catch tErr
      DevServer.LogError tErr, "/eval in the bench"
      return "ERROR:" & return & DevServer.ErrorText(tErr)
   end try
end DevServer.Eval

-------------------------------------------------------------------- view

command xbStartView
   if sRunning is true then exit xbStartView
   -- raylib's own messages go to a file; INFO while loading, WARNING while running
   get xt3d_SetTraceLogFile(kRaylibLog)
   xt3d_SetTraceLogLevel 3
   xt3d_InitHidden sViewW, sViewH, "xt3d test bench"
   put xt3d_LoadRenderTexture(sViewW, sViewH) into sTarget
   put xt3d_LoadRenderTexture(sViewW * kSample, sViewH * kSample) into sBig
   put xt3d_RenderTextureGetTexture(sBig) into sBigTexture
   xt3d_SetTextureFilter sBigTexture, 1     -- 1 = bilinear, for the shrink
   put xt3d_CameraCreate(6,5,6, 0,0.5,0, 0,1,0, 45, 0) into sCamera
   xt3d_SetTraceLogLevel 4
   put 0 into sModel
   put 0 into sAnimCount
   put 0 into sAngle
   put 0 into sFrames
   put 0 into sFPS
   put the milliseconds into sLastTick
   put sLastTick into sFPSTick
   put true into sRunning
   xbShowLog
   xbFrame
end xbStartView

command xbStopView
   if sRunning is not true then exit xbStopView
   put false into sRunning
   if sFrameMsg is not empty then cancel sFrameMsg
   put empty into sFrameMsg
   xbUnloadModel
   xt3d_UnloadRenderTexture sTarget
   xt3d_UnloadRenderTexture sBig
   xt3d_CameraFree sCamera
   xt3d_CloseWindow
end xbStopView

command xbFrame
   if sRunning is not true then exit xbFrame
   local tNow, tSeconds, tYaw, tPitch, tEX, tEY, tEZ, tTint, tWire, tText
   put the milliseconds into tNow
   put (tNow - sLastTick) / 1000 into tSeconds
   put tNow into sLastTick
   add 1 to sFrames
   if tNow - sFPSTick >= 1000 then
      put round(sFrames * 1000 / (tNow - sFPSTick)) into sFPS
      put 0 into sFrames
      put tNow into sFPSTick
   end if
   if the hilite of button "spinChk" then add kSpin * tSeconds to sAngle

   -- animation
   if sModel > 0 and sAnimFrames > 0 then
      if the hilite of button "playChk" then
         add kAnimFPS * tSeconds to sAnimFrame
         repeat while sAnimFrame >= sAnimFrames
            subtract sAnimFrames from sAnimFrame
         end repeat
         put true into sSettingSlider
         set the thumbPosition of scrollbar "frameBar" to trunc(sAnimFrame)
         put false into sSettingSlider
      end if
      xt3d_UpdateModelAnimation sModel, sAnimFirst + sAnim, sAnimFrame
   end if

   -- orbit camera around the model's middle
   put sYaw * pi / 180 into tYaw
   put sPitch * pi / 180 into tPitch
   put sDist * cos(tPitch) * sin(tYaw) into tEX
   put sLift + sDist * sin(tPitch) into tEY
   put sDist * cos(tPitch) * cos(tYaw) into tEZ
   xt3d_CameraSet sCamera, tEX, tEY, tEZ, 0, sLift, 0, 0, 1, 0, 45, 0

   xt3d_BeginTextureMode sBig
   xt3d_ClearBackground 30, 30, 40, 255
   xt3d_BeginMode3D sCamera
   if the hilite of button "gridChk" then xt3d_DrawGrid 10, 1
   if sModel > 0 then
      xt3d_SetBackfaceCulling the hilite of button "cullChk"
      if the hilite of button "frontChk" then
         xt3d_SetCullFace 0
      else
         xt3d_SetCullFace 1
      end if
      if the hilite of button "tintChk" then
         put "255,160,0" into tTint
      else
         put "255,255,255" into tTint
      end if
      if the hilite of button "solidChk" then
         xt3d_DrawModelEx sModel, 0,sLift,0, 0,1,0, sAngle, sFit,sFit,sFit, item 1 of tTint, item 2 of tTint, item 3 of tTint, 255
         put "0,0,0" into tWire
      else
         put tTint into tWire
      end if
      if the hilite of button "wiresChk" then
         xt3d_DrawModelWiresEx sModel, 0,sLift,0, 0,1,0, sAngle, sFit,sFit,sFit, item 1 of tWire, item 2 of tWire, item 3 of tWire, 255
      end if
      xt3d_SetCullFace 1
      xt3d_SetBackfaceCulling true
   end if
   xt3d_EndMode3D
   put sFPS & " fps" into tText
   if sModel > 0 and sAnimFrames > 0 then put "   frame " & trunc(sAnimFrame) & " / " & sAnimFrames after tText
   if sModel = 0 then put "   no model loaded" after tText
   xt3d_DrawText tText, 10 * kSample, 10 * kSample, 20 * kSample, 255,255,255,255
   xt3d_EndTextureMode

   -- shrink into the view-sized target (negative source height keeps it upright)
   xt3d_BeginTextureMode sTarget
   xt3d_DrawTexturePro sBigTexture, 0,0,sViewW * kSample,-(sViewH * kSample), 0,0,sViewW,sViewH, 0,0, 0, 255,255,255,255
   xt3d_EndTextureMode
   set the imageData of image "view" to xt3d_RenderTextureImageData(sTarget)

   send "xbFrame" to me in kFrameMS milliseconds
   put the result into sFrameMsg
end xbFrame

-------------------------------------------------------------------- models

command xbLoadModel pPath
   local i, tBox, tSizeX, tSizeY, tSizeZ, tCX, tCY, tCZ, tBiggest, tAnims, tInfo
   if sRunning is not true then xbStartView
   xbUnloadModel
   xt3d_SetTraceLogLevel 3
   put xt3d_LoadModel(pPath) into sModel
   if sModel is not a number or sModel <= 0 then
      put 0 into sModel
      xt3d_SetTraceLogLevel 4
      put "Could not load:" & return & pPath & return & return & "See the raylib lines below the view." into field "info"
      xbShowLog
      return false
   end if
   put pPath into sModelPath

   -- bounding box: minX,minY,minZ,maxX,maxY,maxZ
   put xt3d_GetModelBoundingBox(sModel) into tBox
   put item 4 of tBox - item 1 of tBox into tSizeX
   put item 5 of tBox - item 2 of tBox into tSizeY
   put item 6 of tBox - item 3 of tBox into tSizeZ
   put (item 1 of tBox + item 4 of tBox) / 2 into tCX
   put (item 2 of tBox + item 5 of tBox) / 2 into tCY
   put (item 3 of tBox + item 6 of tBox) / 2 into tCZ
   put max(tSizeX, tSizeY, tSizeZ) into tBiggest
   if tBiggest <= 0 then put 1 into tBiggest
   put 2 / tBiggest into sFit
   put tSizeY * sFit / 2 into sLift
   -- move the model's middle to its origin, so it sits on the grid and spins about its middle
   xt3d_ModelSetTransform sModel, 1,0,0,0, 0,1,0,0, 0,0,1,0, -tCX,-tCY,-tCZ,1

   -- animations: "firstHandle,count"; handles are consecutive
   put xt3d_LoadModelAnimations(pPath) into tAnims
   put item 1 of tAnims into sAnimFirst
   put item 2 of tAnims into sAnimCount
   if sAnimCount is not a number then put 0 into sAnimCount
   xt3d_SetTraceLogLevel 4
   xbAnimMenu
   xbSelectAnim 0

   put "file: " & pPath & return into tInfo
   put "meshes,materials,bones: " & xt3d_ModelInfo(sModel) & return after tInfo
   put "bounding box: " & tBox & return after tInfo
   put "size: " & tSizeX & ", " & tSizeY & ", " & tSizeZ & return after tInfo
   put "animations: " & sAnimCount & return after tInfo
   repeat with i = 0 to sAnimCount - 1
      put "  " & i & ": " & xt3d_ModelAnimationInfo(sAnimFirst + i) & "  (name,bones,frames)" & return after tInfo
   end repeat
   put tInfo into field "info"
   xbShowLog
   return true
end xbLoadModel

command xbSelectAnim pIndex
   put 0 into sAnimFrame
   put 0 into sAnimFrames
   put 0 into sAnim
   if sAnimCount > 0 and pIndex >= 0 and pIndex < sAnimCount then
      put pIndex into sAnim
      put item -1 of xt3d_ModelAnimationInfo(sAnimFirst + sAnim) into sAnimFrames
   end if
   put true into sSettingSlider
   set the endValue of scrollbar "frameBar" to max(1, sAnimFrames - 1)
   set the thumbPosition of scrollbar "frameBar" to 0
   put false into sSettingSlider
end xbSelectAnim

command xbUnloadModel
   if sAnimCount > 0 then xt3d_UnloadModelAnimations sAnimFirst
   if sModel > 0 then xt3d_UnloadModel sModel
   put 0 into sModel
   put 0 into sAnimCount
   put 0 into sAnimFrames
   put 0 into sLift
   put 1 into sFit
   put empty into sModelPath
   if there is a button "animMenu" then xbAnimMenu
end xbUnloadModel

-- warnings, errors and load reports from raylib's log, newest last
command xbShowLog
   local tLog, tCount
   if there is not a file kRaylibLog then exit xbShowLog
   put URL ("file:" & kRaylibLog) into tLog
   filter tLog with regex pattern "(WARNING|ERROR|FATAL|MODEL:|ANIM)"
   put the number of lines of tLog into tCount
   if tCount > 40 then put line tCount - 39 to tCount of tLog into tLog
   put tLog into field "log"
   set the vScroll of field "log" to 100000
end xbShowLog

-------------------------------------------------------------------- checks

command xbStep pText
   open file kCheckLog for append
   write pText & return to file kCheckLog
   close file kCheckLog
end xbStep

command xbCheck pName, pGot, pExpected
   local tLine
   if pGot is pExpected then
      put "PASS  " & pName into tLine
   else
      put "FAIL  " & pName & "   got [" & pGot & "] expected [" & pExpected & "]" into tLine
   end if
   put tLine & return after sReport
   xbStep "   " & tLine
   put sReport into field "info"
end xbCheck

command xbNote pText
   put "      " & pText & return after sReport
   xbStep "   " & pText
   put sReport into field "info"
end xbNote

on xbRunChecks
   local tKeep, tFiles, tFile, tInfo, tExpect, tData
   put empty into sReport
   put empty into URL ("file:" & kCheckLog)
   put sModelPath into tKeep
   put "Running checks... (each step is logged to " & kCheckLog & ")" into field "info"

   -- 1. crash guards: with no window, these must do nothing instead of crashing
   xbStep "G0 close the view"
   xbStopView
   xbStep "G1 IsWindowReady with no window"
   xbCheck "no window is open", xt3d_IsWindowReady(), "false"
   xbStep "G2 DrawCube with no window"
   xt3d_DrawCube 0,0,0, 1,1,1, 255,0,0,255
   xbCheck "DrawCube with no window did not crash", "ok", "ok"
   xbStep "G3 LoadModel with no window"
   xbCheck "LoadModel with no window answers 0", xt3d_LoadModel(kTestModels & "/skinned_bend.glb"), 0
   xbStep "G4 GetMousePosition with no window"
   xbCheck "GetMousePosition with no window answers empty", xt3d_GetMousePosition(), empty
   xbStep "G5 CloseWindow with no window"
   xt3d_CloseWindow
   xbCheck "CloseWindow with no window did not crash", "ok", "ok"
   xbStep "G6 UnloadModel 7 with no window"
   xt3d_UnloadModel 7
   xbCheck "UnloadModel with no window did not crash", "ok", "ok"

   -- 2. work that needs no window
   xbStep "P1 ColorToInt"
   xbCheck "ColorToInt(1,2,3,4)", xt3d_ColorToInt(1,2,3,4), 16909060
   xbStep "P2 CheckCollisionSpheres"
   xbCheck "spheres 1.5 apart touch", xt3d_CheckCollisionSpheres(0,0,0,1, 1.5,0,0,1), "true"
   xbStep "P3 Version"
   xbCheck "Version starts with xt3d", (xt3d_Version() begins with "xt3d "), "true"

   -- 3. reopen and load every test model
   xbStep "W1 open the view again"
   xbStartView
   xbCheck "window open again", xt3d_IsWindowReady(), "true"
   put "skinned_bend.glb,3,1" & return & "body_block_baked.glb,65,1" into tExpect
   put the defaultFolder into tData
   set the defaultFolder to kTestModels
   put the files into tFiles
   set the defaultFolder to tData
   filter tFiles with regex pattern kModelTypes
   repeat for each line tFile in tFiles
      xbStep "M load " & tFile
      xbLoadModel kTestModels & "/" & tFile
      if the result is not "true" then
         xbCheck tFile & " loads", "failed", "loaded"
         next repeat
      end if
      put xt3d_ModelInfo(sModel) into tInfo
      repeat for each line tData in tExpect
         if item 1 of tData is tFile then
            xbCheck tFile & " bones", item 3 of tInfo, item 2 of tData
            xbCheck tFile & " animations", sAnimCount, item 3 of tData
            put empty into tFile
            exit repeat
         end if
      end repeat
      if tFile is not empty then xbNote tFile & ": meshes,materials,bones " & tInfo & ", animations " & sAnimCount
   end repeat
   xbUnloadModel

   -- 4. one frame copied into LiveCode
   xbStep "F1 frame copy"
   put xt3d_RenderTextureImageData(sTarget) into tData
   xbCheck "frame bytes", the number of bytes in tData, sViewW * sViewH * 4

   xbStep "done"
   put return & "Done. Log: " & kCheckLog after sReport
   if tKeep is not empty then
      xbLoadModel tKeep
      put sReport & return & return & field "info" into field "info"
   else
      put sReport into field "info"
   end if
end xbRunChecks
