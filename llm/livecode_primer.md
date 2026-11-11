# LiveCode Script (xTalk) primer for a model that does not know it

LiveCode Script reads like English. It is NOT JavaScript or Python: no dots for methods,
no parentheses around statements, no braces, no semicolons, no "=" assignment.

## Handlers
on myCommand pParam1, pParam2        -- a command handler; called as:  myCommand 1, 2
   ...
end myCommand
function myFunction pX               -- a function; called as:  put myFunction(5) into tY
   return pX * 2
end myFunction
on mouseUp                           -- event handlers: mouseUp, openStack, openCard, keyDown pKey
   ...
end mouseUp

## Variables and assignment
put 5 into tCount                    -- assignment is  put <value> into <container>
put "Hello" && "World" into tText    -- && joins with a space, & joins without
put tText after tLog                 -- after / before append and prepend
add 1 to tCount                      -- also: subtract 2 from tCount, multiply tX by 3, divide tX by 2
local tA, tB                         -- declare locals (optional);  global gScore  for globals
Naming habit: t = local, p = parameter, s = script local, g = global.

## Everything is text; chunk expressions
put word 3 of line 2 of tText into tW          -- char, word, item, line chunks; counted from 1
put item 2 of "a,b,c" into tB                  -- items are comma-separated (set the itemDel to "/" to change)
put the number of lines of tText into tN       -- also: the number of words/items/chars of ...
put "X" into char 1 of tText                   -- chunks can be targets too
delete line 3 of tText
if tText contains "cat" then ...   |   if tName begins with "xt" then ...   |   if tN is among the items of tList

## Message box
put tW                              -- put with no "into" shows the value in the message box

## Control flow
if tCount > 3 then
   put "big"
else
   put "small"
end if
repeat with i = 1 to 10             -- also: repeat for each line tLine in tText  /  repeat while x < 5  /  repeat 3 times
   ...
end repeat
switch tKind
   case "a"
      ...
      break
   default
      ...
end switch

## Objects and properties
set the text of field "Name" to "Bill"       -- set the <property> of <object> to <value>
put the width of button "OK" into tW
put the loc of image "view" into tLoc        -- loc = "x,y"; rect = "left,top,right,bottom"
answer "Done!"                               -- a dialog;  ask "Your name?"  then the answer is in it

## Arrays
put 10 into tScores["bill"]
repeat for each key tKey in tScores
   put tKey && tScores[tKey]
end repeat

## Calling other code
send "update" to me in 50 milliseconds       -- run a handler later (game loops use this)
dispatch "doThing" to card 2 with tArg

## Common mistakes to avoid
- WRONG: tText.split("\n")      RIGHT: line 2 of tText
- WRONG: x = 5                  RIGHT: put 5 into x
- WRONG: messageBox(x)          RIGHT: put x
- WRONG: print(x)               RIGHT: put x
- Variable names must not spell keywords: not tExt (= text), not tHere (= there).
- Chunks nest from small inside big: char 3 of word 2 of line 1 is fine, but taking a
  bigger chunk out of a smaller one is "bad chunk order": WRONG word 1 of char 1 to 5 of tX.
  Put the smaller chunk into a variable first, then take words from that.
- Items, words and lines are already numbers when they look like numbers: add tItem to tTotal
  (WRONG: the number of tItem; "the number of" only counts chunks: the number of items of tList).
- A handler that uses a global must declare it first:  global gScore  (at the top of the
  handler or the script), or it gets an empty local instead.
- To show something in a field: put tValue into field "Score"  (or set the text of field "Score" to tValue).

## xt3d (raylib for LiveCode)
Handlers are raylib's names with xt3d_ in front: xt3d_DrawCube, xt3d_LoadModel.
Commands: xt3d_DrawCube 0,0.5,0, 1,1,1, 255,0,0,255   (position, size, colour r,g,b,a)
Functions: put xt3d_LoadModel("C:/xt3d/test_models/skinned_bend.glb") into tModel
Vectors are separate numbers, colours are four numbers 0-255, and models, textures and
cameras are handle numbers (0 means it failed). Nothing draws or loads before a window exists.

One frame drawn into a render texture (every raylib call gets the xt3d_ prefix,
including Begin/End, and 3D mode takes the camera handle):
   xt3d_BeginTextureMode sTarget
   xt3d_ClearBackground 30,30,40,255
   xt3d_BeginMode3D sCamera
   xt3d_DrawGrid 10, 1
   xt3d_DrawSphere 0,1,0, 0.5, 255,0,0,255
   xt3d_EndMode3D
   xt3d_EndTextureMode
In the test bench these run inside handler xbFrame; to try one-off drawing there,
change the bench script rather than drawing from outside the frame loop.
