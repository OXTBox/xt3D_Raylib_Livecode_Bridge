script "xt3dDemo"
-- xt3d demo: a spinning cube rendered by raylib into an ordinary LiveCode image,
-- with LiveCode controls free to sit on top of it.
--
-- 1. Build the xt3d library (see README.md) and load the xt3d extension.
-- 2. Put this script on a card (or "start using" it) and send "xt3dStart".
-- 3. Send "xt3dStop" before closing the stack.

constant kWidth = 640
constant kHeight = 480

local sTarget, sCamera, sModel, sRunning, sAngle, sLastTick

on xt3dStart
   if sRunning is true then exit xt3dStart
   xt3d_InitHidden kWidth, kHeight, "xt3d"
   put xt3d_LoadRenderTexture(kWidth, kHeight) into sTarget
   -- eye 6,5,6  looking at 0,0.5,0  up 0,1,0  fov 45  perspective (0)
   put xt3d_CameraCreate(6,5,6, 0,0.5,0, 0,1,0, 45, 0) into sCamera
   put xt3d_LoadModelFromMesh(xt3d_GenMeshCube(1, 1, 1)) into sModel
   
   if there is no image "xt3dView" then create image "xt3dView"
   set the lockLoc of image "xt3dView" to true
   set the width of image "xt3dView" to kWidth
   set the height of image "xt3dView" to kHeight
   
   put 0 into sAngle
   put the milliseconds into sLastTick
   put true into sRunning
   xt3dFrame
end xt3dStart

on xt3dStop
   put false into sRunning
   xt3d_UnloadModel sModel
   xt3d_UnloadRenderTexture sTarget
   xt3d_CameraFree sCamera
   xt3d_CloseWindow
end xt3dStop

on xt3dFrame
   if sRunning is not true then exit xt3dFrame
   local tNow, tSeconds
   put the milliseconds into tNow
   put (tNow - sLastTick) / 1000 into tSeconds
   put tNow into sLastTick
   add 60 * tSeconds to sAngle
   
   -- game logic goes here, in LiveCode Script
   
   xt3d_BeginTextureMode sTarget
   xt3d_ClearBackground 30, 30, 40, 255
   xt3d_BeginMode3D sCamera
   xt3d_DrawGrid 10, 1
   -- model, position xyz, rotation axis xyz, angle, scale xyz, tint rgba
   xt3d_DrawModelEx sModel, 0,0.5,0, 0,1,0, sAngle, 1,1,1, 255,160,0,255
   xt3d_DrawModelWiresEx sModel, 0,0.5,0, 0,1,0, sAngle, 1,1,1, 0,0,0,255
   xt3d_EndMode3D
   xt3d_DrawText "xt3d " & xt3d_Version(), 10, 10, 20, 255,255,255,255
   xt3d_EndTextureMode
   
   set the imageData of image "xt3dView" to xt3d_RenderTextureImageData(sTarget)
   send "xt3dFrame" to me in 16 milliseconds
end xt3dFrame

-- Picking: which point of the cube is under the mouse?
-- Returns hit,distance,px,py,pz,nx,ny,nz  (hit is 1 or 0)
function xt3dPickAt pX, pY
   local tRay
   -- pX,pY are relative to the top-left of the image
   put xt3d_GetScreenToWorldRayEx(pX, pY, sCamera, kWidth, kHeight) into tRay
   return xt3d_GetRayCollisionModel(item 1 of tRay, item 2 of tRay, item 3 of tRay, \
         item 4 of tRay, item 5 of tRay, item 6 of tRay, sModel)
end xt3dPickAt

on mouseDown
   if the short name of the target is not "xt3dView" then pass mouseDown
   local tX, tY
   put the mouseH - the left of image "xt3dView" into tX
   put the mouseV - the top of image "xt3dView" into tY
   put xt3dPickAt(tX, tY)
end mouseDown
