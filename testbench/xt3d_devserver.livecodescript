script "xt3dDevServer"
-- xt3d dev server: lets Claude Code (or any local tool) drive the running LiveCode IDE.
-- A script-only library stack. The test bench starts it with its "Dev server" switch:
--    start using stack "<this file>"
--    DevServer.Start 8766, "xt3dTestBench"
-- It is a separate stack so it keeps running while the bench is closed and reopened.
-- Adapted from the LIB_DEVSERVER kit (vector engine project).
--
-- Plain HTTP. Only connections from 127.0.0.1 are answered, and every request must
-- carry the header  X-Token: <token>.  The token is new on every start and is written,
-- with the port, to C:/xt3d/.xt3d_devtoken (line 1 token, line 2 port).
-- tools/xt3d_dev.sh reads it from there.
--
-- ROUTES (bodies are UTF-8 text)
--   GET  /ping                   "OK" + LiveCode version + target stack + xt3d version
--   POST /run                    body = LiveCode statements. Runs inside the target stack's
--                                script (so bench handlers and locals are reachable), or
--                                here with ?in=server. Answers the message box text (anything
--                                "put" with no destination) and the result.
--   POST /eval                   body = one expression -> its value (?in=server as above)
--   POST /reload                 close the target stack and open it again from its file
--                                (?path=<file> opens that file instead)
--   GET  /snap                   save a PNG of the target stack's card (?file=, default
--                                C:/xt3d/snap.png), for Claude to look at
--
-- THIS RUNS ANY CODE IT IS SENT. Development only; never ship it in a standalone.

constant kTokenFile = "C:/xt3d/.xt3d_devtoken"
constant kSnapFile = "C:/xt3d/snap.png"

local sDev   -- ["port"], ["token"], ["target"], ["reload"], ["conn"][socket][...]

-------------------------------------------------------------------- start / stop

command DevServer.Start pPort, pTarget
   local tErr
   if pPort is empty then put 8766 into pPort
   if pTarget is empty then put "xt3dTestBench" into pTarget
   DevServer.Stop
   put pPort into sDev["port"]
   put pTarget into sDev["target"]
   put DevServer.NewToken() into sDev["token"]
   accept connections on port pPort with message "DevServer.OnConnect"
   put the result into tErr
   if tErr is not empty then
      put empty into sDev
      return "DevServer: could not listen on port" && pPort & ":" && tErr
   end if
   put sDev["token"] & return & sDev["port"] & return into URL ("file:" & kTokenFile)
   return "DevServer listening on 127.0.0.1:" & pPort
end DevServer.Start

command DevServer.Stop
   local tErr
   if sDev["port"] is not empty then
      try
         close socket sDev["port"]
      catch tErr
      end try
   end if
   put empty into sDev
   if there is a file kTokenFile then delete file kTokenFile
end DevServer.Stop

function DevServer.Running
   return sDev["port"] is not empty
end DevServer.Running

function DevServer.NewToken
   local tChars, tToken
   put "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" into tChars
   repeat 32 times
      put char random(62) of tChars after tToken
   end repeat
   return tToken
end DevServer.NewToken

-------------------------------------------------------------------- HTTP in

on DevServer.OnConnect pSocket
   set the itemDel to ":"
   if item 1 of pSocket is not "127.0.0.1" then
      close socket pSocket
      exit DevServer.OnConnect
   end if
   read from socket pSocket until crlf & crlf with message "DevServer.OnHeader"
end DevServer.OnConnect

on DevServer.OnHeader pSocket, pData
   local tC, tReq, tPath, tQ, tQuery, tPair, tEq, tToken, tLine, tColon, tKey, tVal
   replace crlf with return in pData
   put line 1 of pData into tReq
   put word 1 of tReq into tC["method"]
   put word 2 of tReq into tPath
   put offset("?", tPath) into tQ
   if tQ > 0 then
      put char 1 to tQ - 1 of tPath into tC["route"]
      put char tQ + 1 to -1 of tPath into tQuery
   else
      put tPath into tC["route"]
   end if
   set the itemDel to "&"
   repeat for each item tPair in tQuery
      put offset("=", tPair) into tEq
      if tEq = 0 then next repeat
      put urlDecode(char tEq + 1 to -1 of tPair) into tC["query"][char 1 to tEq - 1 of tPair]
   end repeat
   put 0 into tC["len"]
   repeat for each line tLine in line 2 to -1 of pData
      put offset(":", tLine) into tColon
      if tColon = 0 then next repeat
      put toLower(word 1 to -1 of char 1 to tColon - 1 of tLine) into tKey
      put word 1 to -1 of char tColon + 1 to -1 of tLine into tVal
      if tKey is "content-length" then put tVal into tC["len"]
      if tKey is "x-token" then put tVal into tToken
   end repeat
   if sDev["token"] is empty or tToken is not sDev["token"] then
      DevServer.Reply pSocket, 403, "bad or missing X-Token"
      exit DevServer.OnHeader
   end if
   put tC into sDev["conn"][pSocket]
   if tC["len"] > 0 then
      read from socket pSocket for tC["len"] with message "DevServer.OnBody"
   else
      DevServer.Handle pSocket, empty
   end if
end DevServer.OnHeader

on DevServer.OnBody pSocket, pData
   DevServer.Handle pSocket, textDecode(pData, "UTF-8")
end DevServer.OnBody

-------------------------------------------------------------------- routes

on DevServer.Handle pSocket, pBody
   local tC, tCode, tOut, tErr, tTarget, bInServer, tFile, tVersion
   put sDev["conn"][pSocket] into tC
   put 200 into tCode
   put sDev["target"] into tTarget
   -- run in the target stack when it is open, unless asked to run here
   put (tC["query"]["in"] is "server" or there is not a stack tTarget) into bInServer
   try
      switch tC["route"]
         case "/ping"
            try
               put xt3d_Version() into tVersion
            catch tErr
               put "xt3d extension not loaded" into tVersion
            end try
            put "OK LiveCode" && the version & " | target" && tTarget & \
                  (there is a stack tTarget) & " | " & tVersion into tOut
            break
         case "/run"
            put DevServer.Run(pBody, bInServer, tTarget) into tOut
            break
         case "/eval"
            if bInServer then
               put DevServer.Eval(pBody) into tOut
            else
               dispatch function "DevServer.Eval" to stack tTarget with pBody
               if it is "unhandled" then
                  put DevServer.Eval(pBody) into tOut
               else
                  put the result into tOut
               end if
            end if
            break
         case "/reload"
            if tC["query"]["path"] is not empty then
               put tC["query"]["path"] into sDev["reload"]
            else if there is a stack tTarget then
               put the effective filename of stack tTarget into sDev["reload"]
            else
               put "ERROR: the target stack is not open; give ?path=" into tOut
               break
            end if
            -- after the reply has gone: the target can't be closed while it is answering
            send "DevServer.DoReload" to me in 50 milliseconds
            put "OK reloading" && sDev["reload"] into tOut
            break
         case "/snap"
            put tC["query"]["file"] into tFile
            if tFile is empty then put kSnapFile into tFile
            put DevServer.Snap(tTarget, tFile) into tOut
            break
         default
            put 404 into tCode
            put "unknown route:" && tC["route"] into tOut
      end switch
   catch tErr
      put 500 into tCode
      put "ERROR:" && tErr into tOut
   end try
   if tOut begins with "ERROR:" and tCode is 200 then put 422 into tCode
   DevServer.Reply pSocket, tCode, tOut
end DevServer.Handle

-- Statements run through "do". Anything put into the message box comes back,
-- followed by the result if there is one.
function DevServer.Run pCode, pInServer, pTarget
   local tErr, tResult
   put empty into msg
   if pInServer then
      try
         do pCode
         put the result into tResult
      catch tErr
         return "ERROR:" && tErr
      end try
   else
      dispatch "DevServer.Exec" to stack pTarget with pCode
      if it is "unhandled" then return "ERROR: the target stack has no DevServer.Exec handler"
      put the result into tResult
      if tResult begins with "ERROR:" then return tResult
   end if
   if tResult is empty then return msg
   if msg is empty then return "result:" && tResult
   return msg & return & "result:" && tResult
end DevServer.Run

function DevServer.Eval pExpr
   local tErr
   try
      return value(pExpr)
   catch tErr
      return "ERROR:" && tErr
   end try
end DevServer.Eval

command DevServer.DoReload
   local tPath, tName
   put sDev["reload"] into tPath
   put sDev["target"] into tName
   if there is a stack tName then
      -- closeStack stops the bench's view; delete removes the old script from memory
      close stack tName
      if there is a stack tName then delete stack tName
   end if
   go stack tPath
end DevServer.DoReload

function DevServer.Snap pTarget, pFile
   local tErr
   if there is not a stack pTarget then return "ERROR: stack" && pTarget && "is not open"
   try
      export snapshot from this card of stack pTarget to file pFile as PNG
   catch tErr
      try
         export image "view" of stack pTarget to file pFile as PNG
      catch tErr
         return "ERROR: snapshot failed:" && tErr
      end try
   end try
   return "OK" && pFile
end DevServer.Snap

-------------------------------------------------------------------- HTTP out

on DevServer.Reply pSocket, pCode, pText
   local tStatus, tBytes, tHead
   switch pCode
      case 200
         put "OK" into tStatus
         break
      case 403
         put "Forbidden" into tStatus
         break
      case 404
         put "Not Found" into tStatus
         break
      case 422
         put "Unprocessable" into tStatus
         break
      default
         put "Error" into tStatus
   end switch
   put textEncode(pText, "UTF-8") into tBytes
   put "HTTP/1.1" && pCode && tStatus & crlf into tHead
   put "Content-Type: text/plain; charset=utf-8" & crlf after tHead
   put "Content-Length: " & the number of bytes of tBytes & crlf after tHead
   put "Connection: close" & crlf & crlf after tHead
   write textEncode(tHead, "UTF-8") & tBytes to socket pSocket
   close socket pSocket
   delete variable sDev["conn"][pSocket]
end DevServer.Reply
