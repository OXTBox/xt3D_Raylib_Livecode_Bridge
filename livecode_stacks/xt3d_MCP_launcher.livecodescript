-- Stack script for xt3d_MCP.livecode (the standalone dev server).
-- It loads the dev server from its file each time it starts, so changes to
-- C:/xt3d/testbench/xt3d_devserver.livecodescript need no standalone rebuild.
-- Port 8767, so it can run beside the IDE's dev server (8766). Claude starts it as needed.

constant kServer = "C:/xt3d/testbench/xt3d_devserver.livecodescript"

on openStack
   local tResult
   -- the dev server library also sees openStack; only act for this stack
   if the short name of the owner of the target is not the short name of me then pass openStack
   -- in the IDE the test bench runs the dev server (port 8766); this stack only serves
   -- as the standalone, so do nothing here when opened in the IDE
   if the environment is "development" then exit openStack
   if there is not a file kServer then
      answer "Dev server file not found:" && kServer
      exit openStack
   end if
   start using stack kServer
   DevServer.Start 8767, "xt3dTestBench"   -- 8767: the IDE keeps 8766
   put the result into tResult
   set the title of me to "xt3d dev server"
   if there is not a field "status" then create field "status"
   set the rect of field "status" to 0, 0, the width of me, the height of me
   put tResult & return & "Errors: C:/xt3d/livecode_errors.txt" & return & \
         "Close this window to stop the server." into field "status"
end openStack
