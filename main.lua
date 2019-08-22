require "lovedebug"

dofile "Z80.lua"

local zoom = 2
local width = 4+1 + 16*2 + 15 + 2 + 16
local height = 1 + 16 + 2 + 10
local keys = {}
local cmdline = ""
local valid_keys = "abcdefghijklmnopqrstuvwxyz1234567890()[],.-+<>=_'"
local shifted_keys = {
   [","] = "<",
   ["."] = ">",
   ["("] = "[",
   [")"] = "]",
   ["="] = "+",
   ["-"] = "_"
}

-- can't really run even as fast as a Z80? this hits some sweet spot...
frames = 10000

local ram_offset = 0
local console_text = {}

mem = Memory()
z80 = Z80(mem)
asm = require "assembler"
state = "repl"

-- CUT HERE LATER --
function parse_args(str)
   -- no args
   op = string.match(str, "^(%a+)$")
   if op then return "none" end

   -- register arg
   op, arg1 = string.match(str, "^(%a+) +(%a+)$")
   if op and arg then return "register" end

   op, arg1 = string.match(str, "^(%a+) +(%(%a+%))$")
   if op and arg then return "iregister" end

   op, arg1, off = string.match(str, "^(%a+) +%((%a+) *%+ *(%d+h?)%)$")
   if op and arg1 and off then return "ioffregister" end

   -- literal arg (no "one indirect literal arg")
   op, arg1 = string.match(str, "^(%a+) +(%d+)$")
   if op and arg then return "literal" end
   op, arg1 = string.match(str, "^(%a+) +(%x+h)$")
   if op and arg then return "literal" end


   -- register/*
   op, arg1, arg2 = string.match(str, "^(%a+) +(%a+), *(%a+)$")
   if op and arg1 and arg2 then return "register/register" end

   op, arg1, arg2 = string.match(str, "^(%a+) +(%a+), *(%(%a+%))$")
   if op and arg1 and arg2 then return "register/iregister" end

   op, arg1, arg2, off = string.match(str, "^(%a+) +(%a+), *%((%a+) *%+ *(%d+h?)%)$")
   if op and arg1 and arg2 then return "register/ioffregister" end

   op, arg1, arg2 = string.match(str, "^(%a+) +(%a+), *(%d+)$")
   if op and arg1 and arg2 then return "register/literal" end
   op, arg1, arg2 = string.match(str, "^(%a+) +(%a+), *(%x+h)$")
   if op and arg1 and arg2 then return "register/literal" end

   op, arg1, arg2 = string.match(str, "^(%a+) +(%a+), *(%(%d+%))$")
   if op and arg1 and arg2 then return "register/iliteral" end
   op, arg1, arg2 = string.match(str, "^(%a+) +(%a+), *(%(%x+h%))$")
   if op and arg1 and arg2 then return "register/iliteral" end


   -- iregister/*
   op, arg1, arg2 = string.match(str, "^(%a+) +(%(%a+%)), *(%a+)$")
   if op and arg1 and arg2 then return "iregister/register" end

   op, arg1, arg2 = string.match(str, "^(%a+) +(%(%a+%)), *(%d+)$")
   if op and arg1 and arg2 then return "iregister/literal" end
   op, arg1, arg2 = string.match(str, "^(%a+) +(%(%a+%)), *(%x+h)$")
   if op and arg1 and arg2 then return "iregister/literal" end


   -- ioffregister/*
   op, arg1, off, arg2 = string.match(str, "^(%a+) +%((%a+) *%+ *(%d+h?)%), *(%d+h?)$")
   if op and arg1 and off and arg2 then return "ioffregister/literal" end

   op, arg1, off, arg2 = string.match(str, "^(%a+) +%((%a+) *%+ *(%d+h?)%), *(%a+)$")
   if op and arg1 and off and arg2 then return "ioffregister/register" end


   -- literal/*
   op, arg1, arg2 = string.match(str, "^(%a+) +(%d+), *(%a+)$")
   if op and arg1 and arg2 then return "literal/register" end
   op, arg1, arg2 = string.match(str, "^(%a+) +(%x+h), *(%a+)$")
   if op and arg1 and arg2 then return "literal/register" end

   op, arg1, arg2 = string.match(str, "^(%a+) +(%d+), *(%(%a+%))$")
   if op and arg1 and arg2 then return "literal/iregister" end
   op, arg1, arg2 = string.match(str, "^(%a+) +(%x+h), *(%(%a+%))$")
   if op and arg1 and arg2 then return "literal/iregister" end

   op, arg1, arg2, off = string.match(str, "^(%a+) +(%d+h?), *%((%a+) *%+ *(%d+h?)%)$")
   if op and arg1 and arg2 and off then return "literal/ioffregister" end


   -- iliteral/*
   op, arg1, arg2 = string.match(str, "^(%a+) +(%(%d+%)), *(%a+)$")
   if op and arg1 and arg2 then return "iliteral/register" end
   op, arg1, arg2 = string.match(str, "^(%a+) +(%(%x+h%)), *(%a+)$")
   if op and arg1 and arg2 then return "iliteral/register" end

   return "can't decode argument types!"
end
-- CUT HERE LATER --



function split(s, delimiter)
   result = {};
   for match in (s..delimiter):gmatch("(.-)"..delimiter) do
      table.insert(result, match);
   end
   return result;
end

local function printxy(text, x, y, c)
   local c = c or {1,1,1}

   love.graphics.setColor(c)
   love.graphics.print(text, x*8, y*8)
end

function process_key(k)
   local pressed = love.keyboard.isDown(k)
   if pressed and not keys[k] then
      keys[k] = 60
      return true
   elseif pressed then
      keys[k] = keys[k] - 1
      if keys[k] == 0 then
         keys[k] = 60
         return true
      end
   else
      keys[k] = nil
   end
end

local commands = {
   [">"] = function(address)
      local addr = read_as_number(address)
      if addr then
         z80.pc = addr
         cmdline = ""
      end
   end,

   run = function ()
      state = "run"
   end,

   frames = function(n)
      local n = read_as_number(n)
      if n then frames = n end
   end
}

function do_command()
   local parts = split(cmdline, " ")
   local mnemonic = parts[1]
   local operands = split(parts[#parts], ",")
   local bytes = nil

   if mnemonic then
      local cmd = commands[mnemonic]

      if cmd then
         cmd(operands[1], operands[2])
         return true
      end
   end

   return false
end

function get_spec()
   local parts = split(cmdline, " ")
   local mnemonic = parts[1]
   local operands = split(parts[#parts], ",")

   local t1,t2 = argtype(operands[1]),argtype(operands[2])
   -- print(t1,t2)

   -- no arguments
   if t1 == "none" then return nil end

   -- one or two arguments (incomplete, needs ioffregs)
   if t1 == "register" or t1 == "iregister" then
      if t2 == "none" then
         return operands[1]
      elseif t2 == "register" or t2 == "iregister" then
         return operands[1] .. "," .. operands[2]
      elseif t2 == "literal" then
         return operands[1] .. ",*"
      elseif t2 == "iliteral" then
         return operands[1] .. ",(*)"
      elseif t2 == "ioffregister" then
         return operands[1] .. ",(+*)"
      end
   elseif t1 == "literal" then
      if t2 == "none" then
         return "*"
      elseif t2 == "register" or t2 == "iregister" then
         return "*," .. operands[2]
      end
   elseif t1 == "iliteral" then
      if t2 == "none" then
         return "(*)"
      elseif t2 == "register" or t2 == "iregister" then
         return "(*)," .. operands[2]
      end
   elseif t1 == "ioffregister" then
      if t2 == "none" then
         local reg,off = read_register_and_offset(operands[1])
         return "(" .. reg .. "+*)"
      elseif t2 == "register" or t2 == "iregister" then
         return "(+*)," .. operands[2]
      elseif t2 == "literal" then
         return "(+*),*"
      end
   end

   return nil
end

function assemble()
   local parts = split(cmdline, " ")
   local mnemonic = parts[1]
   local operands = split(parts[#parts], ",")
   local bytes = nil

   local spec = get_spec()

   -- print(parse_args(cmdline))
   -- print(mnemonic, spec, operands[1], operands[2])

   bytes = ass(mnemonic, spec, operands[1], operands[2])

   return bytes
end

function run_z80()
   -- a little hack to intercept HALT and go back to the REPL
   if mem:mem_read(z80.pc) == 0x76 then
      state = "repl"
   else
      z80:run_instruction()
   end
end






function love.load()
   z80:reset()
   love.window.setMode(width*8*zoom, height*8*zoom)
   love.graphics.setDefaultFilter("nearest", "nearest", 1)
   love.graphics.setNewFont("PressStart2P.ttf", 8)
end

function love.update(dt)
   if love.keyboard.isDown("escape") then love.event.quit() end

   if love.keyboard.isDown("f1") then state = "repl" end
   if love.keyboard.isDown("f5") then state = "run" end

   if state == "run" then
      for i=1,frames do
         run_z80()
      end
   elseif state == "repl" then
      local movepc = {
         left = -1,
         right = 1,
         up = -16,
         down = 16
      }

      for k,v in pairs(movepc) do
         if process_key(k) then
            z80.pc = (z80.pc+v) % 65536
         end
      end

      if process_key("backspace") then
         cmdline = string.sub(cmdline,1,#cmdline-1)
      end

      if process_key("space") then cmdline = cmdline .. " " end

      if process_key("return") then
         if do_command() then return end

         local bytes = assemble()

         if bytes then
            for i,b in ipairs(bytes) do
               mem:mem_write(z80.pc+i-1, b)
            end

            z80.pc = z80.pc + #bytes
         else
            print("Can't assemble '" .. cmdline .. "'")
         end

         if #console_text > 6 then
            table.remove(console_text,#console_text)
         end
         table.insert(console_text,1,cmdline)
         cmdline = ""
      end

      for i=1,#valid_keys do
         local k = string.sub(valid_keys,i,i)

         local shifted = love.keyboard.isDown("lshift")
            or love.keyboard.isDown("rshift")

         if process_key(k) then
            if shifted and shifted_keys[k] then
               k = shifted_keys[k]
            end
            cmdline = cmdline .. k
         end
      end

      if process_key("pageup") then
         ram_offset = (ram_offset - 256) % 65536
      end

      if process_key("pagedown") then
         ram_offset = (ram_offset + 256) % 65536
      end

      if process_key("f9") then
         z80.pc = 0
      end

      if process_key("f10") then
         run_z80()
      end
   end

end

function love.draw()
   love.graphics.scale(zoom)

   local format = string.format
   for i=0,15 do
      printxy(format("%2.2x", i), 5+i*3, 0, {0.1, 0.1, 1})
   end

   for i=0,15 do
      printxy(format("%4.4x", ram_offset + i*16), 0, i+1, {0.1, 0.1, 1})
   end

   for i=0,15 do
      for j=0,15 do
         if z80.pc == ram_offset + i*16+j then
            printxy(format("%2.2x", mem:mem_read(ram_offset + i*16+j)), 5+j*3, i+1, {1,0,1})
         else
            printxy(format("%2.2x", mem:mem_read(ram_offset + i*16+j)), 5+j*3, i+1)
         end
      end
   end

   printxy("A   B  C   D  E   H  L   IX   IY   PC   SP   SZYHXPNC  I   R", 0, 17, {0.2, 0.8, 0.2})

   printxy(format("%2.2x", z80.a), 0, 18)

   printxy(format("%2.2x", z80.b), 4, 18)
   printxy(format("%2.2x", z80.c), 7, 18)

   printxy(format("%2.2x", z80.d), 11, 18)
   printxy(format("%2.2x", z80.e), 14, 18)

   printxy(format("%2.2x", z80.h), 18, 18)
   printxy(format("%2.2x", z80.l), 21, 18)

   printxy(format("%4.4x", z80.ix), 25, 18)
   printxy(format("%4.4x", z80.iy), 30, 18)

   printxy(format("%4.4x", z80.pc), 35, 18)
   printxy(format("%4.4x", z80.sp), 40, 18)

   for i,name in ipairs({"S", "Z", "Y", "H", "X", "P", "N", "C"}) do
      printxy(format(z80.flags[name] and 1 or 0), 44+i, 18)
   end

   printxy(format("%2.2x", z80.i), 55, 18)
   printxy(format("%2.2x", z80.r), 59, 18)

   for i=#console_text,1,-1 do
      printxy(console_text[i], 0, 27-i)
   end
   printxy(cmdline, 0, 27)
end

-- function love.quit()  end
-- function love.threaderror(thread, errorstr) print("Thread error!\n" .. errorstr) end

-- game.controls = {
--    left =  function() player:move(-1, 0) end,
--    right = function() player:move( 1, 0) end,
--    up =    function() player:move( 0,-1) end,
--    down =  function() player:move( 0, 1) end
-- }
