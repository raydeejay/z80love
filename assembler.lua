local assembler = {}

function read_as_number(str)
   if not str then return nil end

   local num = tonumber(str)
   local base = string.lower(string.sub(str,#str,#str))

   if not num then
      if base == "h" then
         num = tonumber(string.sub(str,1,#str-1), 16)
      elseif base == "b" then
         num = tonumber(string.sub(str,1,#str-1), 2)
      elseif base == "o" then
         num = tonumber(string.sub(str,1,#str-1), 8)
      end
   end

   return num
end

function argtype(str)
   if not str or str == "" then return "none" end

   if string.match(str, "^%d+$") then return "literal" end
   if string.match(str, "^%x+h$") then return "literal" end
   if string.match(str, "^%(%d+h?%)$") then return "iliteral" end

   if string.match(str, "^%a+$") then return "register" end
   if string.match(str, "^%(%a+%)$") then return "iregister" end
   if string.match(str, "^%(%a+%+%d+h?%)$") then return "ioffregister" end

   return "error"
end

function read_register_and_offset(str)
   return string.match(str, "^%((%a+)%+(%d+h?)%)$")
end

function read_iliteral(str)
   return string.match(str, "^%((%dh?)%)$")
end

local function add_encoding(t, registers, base, offset, prefix)
   for i,reg in ipairs(registers) do
      if prefix then
         t[reg] = {prefix, base + offset*(i-1)}
      else
         t[reg] = {base + offset*(i-1)}
      end
   end
end


local function ld_reg_offreg(arg1, arg2)
   local value = read_register_and_offset(arg2)
   if not value then return nil end

   local lo = bit.band(value, 0xFF)
   local hi = bit.rshift(value, 8)

   local off = 0
   for i,_a_ in ipairs {"b", "c", "d", "e", "h", "l"} do
         encoded[_a_ .. ",ix"] = {0xDD, 0x46 + off, lo, hi}
         encoded[_a_ .. ",iy"] = {0xFD, 0x46 + off, lo, hi}
         off = off + 8
   end
   encoded["a,ix"] = {0xDD, 0x7E, lo, hi}
   encoded["a,iy"] = {0xFD, 0x7E, lo, hi}

   return encoded[arg1]
end

local function ld_offreg_reg(arg1, arg2)
   local value = read_register_and_offset(arg1)
   if not value then return nil end

   local lo = bit.band(value, 0xFF)
   local hi = bit.rshift(value, 8)

   local off = 0
   for i,_a_ in ipairs {"b", "c", "d", "e", "h", "l"} do
         encoded["ix," .. _a_] = {0xDD, 0x70 + off, lo, hi}
         encoded["iy," .. _a_] = {0xFD, 0x70 + off, lo, hi}
         off = off + 1
   end
   encoded["ix,a"] = {0xDD, 0x77, lo, hi}
   encoded["iy,a"] = {0xFD, 0x77, lo, hi}

   return encoded[arg2]
end


-- value encoding
----------------------------------------
local function byte1(arg1, arg2)
   return read_as_number(arg1)
end

local function byte2(arg1, arg2)
   return read_as_number(arg2)
end
----------------------------------------
local function word1hi(arg1, arg2)
   return bit.rshift(read_as_number(arg1), 8)
end

local function word1lo(arg1, arg2)
   return bit.band(read_as_number(arg1), 0xFF)
end

local function word2hi(arg1, arg2)
   return bit.rshift(read_as_number(arg2), 8)
end

local function word2lo(arg1, arg2)
   return bit.band(read_as_number(arg2), 0xFF)
end
----------------------------------------
local function i_word1hi(arg1, arg2)
   return bit.rshift(read_iliteral(arg1), 8)
end

local function i_word1lo(arg1, arg2)
   return bit.band(read_iliteral(arg1), 0xFF)
end

local function i_word2hi(arg1, arg2)
   return bit.rshift(read_iliteral(arg2), 8)
end

local function i_word2lo(arg1, arg2)
   return bit.band(read_iliteral(arg2), 0xFF)
end
----------------------------------------



instructions = {
   nop = {0},
   halt = {0x76},
   rlca = {0x07},
   rrca = {0x0F},
   rla = {0x17},
   rra = {0x1F},
   daa = {0x27},
   cpl = {0x2F},
   scf = {0x37},
   ccf = {0x3F},
   exx = {0xD9},
   di = {0xF3},
   ei = {0xFB}
}

-- EX
instructions.ex = {
   ["af,af'"] = {0x08},
   ["(sp),hl"] = {0xE3},
   ["de,hl"] = {0xEB},
   ["(sp),ix"] = {0xDD,0xE3},
   ["(sp),iy"] = {0xFD,0xE3}
}

-- DJNZ
instructions.djnz = {
   ["*"] = {0x10, byte1}
}

-- JR
instructions.jr = {
   ["*"] = {0x18, byte1},
   ["nz,*"] = {0x20, byte2},
   ["z,*"] = {0x28, byte2},
   ["nc,*"] = {0x30, byte2},
   ["c,*"] = {0x38, byte2}
}

-- RST
local function encode_rst(arg1,arg2)
   local value = read_as_number(arg1)
   local bytes = {
      [0x00] = 0xC7,
      [0x08] = 0xCF,
      [0x10] = 0xD7,
      [0x18] = 0xDF,
      [0x20] = 0xE7,
      [0x28] = 0xEF,
      [0x30] = 0xF7,
      [0x38] = 0xFF
   }

   return bytes[value]
end

instructions.rst = {
   ["*"] = {encode_rst}
}

-- XOR
instructions.xor = {
   ["*"] = {0xEE, byte1}
}

add_encoding(instructions.xor, {"b","c","d","e","h","l","(hl)","a"}, 0xA8, 1)
add_encoding(instructions.xor, {"ixh", "ixl"}, 0xAC, 1, 0xDD)
add_encoding(instructions.xor, {"iyh", "iyl"}, 0xAC, 1, 0xFD)

-- OR
instructions["or"] = {
   ["*"] = {0xF6, byte1}
}

add_encoding(instructions["or"], {"b","c","d","e","h","l","(hl)","a"}, 0xB0, 1)
add_encoding(instructions["or"], {"ixh", "ixl"}, 0xB4, 1, 0xDD)
add_encoding(instructions["or"], {"iyh", "iyl"}, 0xB4, 1, 0xFD)

-- SBC
instructions.sbc = {
   ["*"] = {0xDE, byte1}
}

add_encoding(instructions.sbc, {"b","c","d","e","h","l","(hl)","a"}, 0x98, 1)
add_encoding(instructions.sbc, {"ixh", "ixl"}, 0x9C, 1, 0xDD)
add_encoding(instructions.sbc, {"iyh", "iyl"}, 0x9C, 1, 0xFD)

-- SUB
instructions.sub = {
   ["*"] = {0xD6, byte1}
}

add_encoding(instructions.sub, {"b","c","d","e","h","l","(hl)","a"}, 0x90, 1)
add_encoding(instructions.sub, {"ixh", "ixl"}, 0x94, 1, 0xDD)
add_encoding(instructions.sub, {"iyh", "iyl"}, 0x94, 1, 0xFD)

-- AND
instructions["and"] = {
   ["*"] = {0xE6, byte1}
}

add_encoding(instructions["and"], {"b","c","d","e","h","l","(hl)","a"}, 0xA0, 1)
add_encoding(instructions["and"], {"ixh", "ixl"}, 0xA4, 1, 0xDD)
add_encoding(instructions["and"], {"iyh", "iyl"}, 0xA4, 1, 0xFD)

-- POP
instructions.pop = {
   ix = {0xDD, 0xE1},
   iy = {0xFD, 0xE1}
}

add_encoding(instructions.pop, {"bc", "de", "hl", "af"}, 0xC1, 16)

-- PUSH
instructions.push = {
   ix = {0xDD, 0xE5},
   iy = {0xFD, 0xE5}
}

add_encoding(instructions.push, {"bc", "de", "hl", "af"}, 0xC5, 16)

-- RET
instructions.ret = {
   none = {0xC9}
}
add_encoding(instructions.ret, {"nz", "z", "nc", "c", "po", "pe", "p", "m"}, 0xC0, 8)


-- LD
-- literal to register/iregister
instructions.ld = {
   ["bc,*"] = {0x01, word2lo, word2hi},
   ["de,*"] = {0x11, word2lo, word2hi},
   ["hl,*"] = {0x21, word2lo, word2hi},
   ["sp,*"] = {0x31, word2lo, word2hi},
   ["b,*"] = {0x06, byte2},
   ["c,*"] = {0x0E, byte2},
   ["d,*"] = {0x16, byte2},
   ["e,*"] = {0x1E, byte2},
   ["h,*"] = {0x26, byte2},
   ["l,*"] = {0x2E, byte2},
   ["(hl),*"] = {0x36, byte2},
   ["a,*"] = {0x3E, byte2},
   ["ix,*"] = {0xDD, 0x21, word2lo, word2hi},
   ["ixh,*"] = {0xDD, 0x26, byte2},
   ["ixl,*"] = {0xDD, 0x2E, byte2},
   ["iy,*"] = {0xFD, 0x21, word2lo, word2hi},
   ["iyh,*"] = {0xFD, 0x26, byte2},
   ["iyl,*"] = {0xFD, 0x2E, byte2}
}

-- register to register
add_encoding(instructions.ld, {"(bc),a", "a,(bc)", "(de),a", "a,(de)"}, 0x02, 8)
add_encoding(instructions.ld, {"i,a", "r,a", "a,i", "a,r"}, 0x47, 8, 0xED)
add_encoding(instructions.ld, {"b,ixh", "c,ixh", "d,ixh", "e,ixh", "ixh,ixh", "ixl,ixh"}, 0x44, 8, 0xDD)
add_encoding(instructions.ld, {"b,ixl", "c,ixl", "d,ixl", "e,ixl", "ixh,ixl", "ixl,ixl"}, 0x45, 8, 0xDD)
instructions.ld["a,ixh"] = {0xDD, 0x7C}
instructions.ld["a,ixl"] = {0xDD, 0x7D}

add_encoding(instructions.ld, {"b,iyh", "c,iyh", "d,iyh", "e,iyh", "ixh,iyh", "ixl,iyh"}, 0x44, 8, 0xFD)
add_encoding(instructions.ld, {"b,iyl", "c,iyl", "d,iyl", "e,iyl", "ixh,iyl", "ixl,iyl"}, 0x45, 8, 0xFD)
instructions.ld["a,iyh"] = {0xFD, 0x7C}
instructions.ld["a,iyl"] = {0xFD, 0x7D}

instructions.ld["sp,ix"] = {0xDD, 0xF9}
instructions.ld["sp,iy"] = {0xFD, 0xF9}

for i,_a_ in ipairs {"b", "c", "d", "e", "h", "l", "(hl)", "a"} do
   for j,_b_ in ipairs {"b", "c", "d", "e", "h", "l", "(hl)", "a"} do
      instructions.ld[_a_ .. "," .. _b_] = {0x40 + (i-1)*8+(j-1)}
   end
end

instructions.ld["(hl),(hl)"] = nil -- does not exist
instructions.ld["sp,hl"] = {0xF9}

-- register to iliteral
instructions.ld["(*),hl"] = {0x22, i_word1lo, i_word1hi}
instructions.ld["(*),a"] = {0x32, i_word1lo, i_word1hi}
instructions.ld["(*),bc"] = {0xED, 0x43, i_word1lo, i_word1hi}
instructions.ld["(*),de"] = {0xED, 0x53, i_word1lo, i_word1hi}
instructions.ld["(*),sp"] = {0xED, 0x73, i_word1lo, i_word1hi}
instructions.ld["(*),ix"] = {0xDD, 0x22, i_word1lo, i_word1hi}
instructions.ld["(*),iy"] = {0xFD, 0x22, i_word1lo, i_word1hi}

-- iliteral to register
instructions.ld["a,(*)"]  = {0x3A, i_word1lo, i_word1hi}
instructions.ld["bc,(*)"] = {0xED, 0x4B, i_word1lo, i_word1hi}
instructions.ld["de,(*)"] = {0xED, 0x5B, i_word1lo, i_word1hi}
instructions.ld["hl,(*)"] = {0xED, 0x6B, i_word1lo, i_word1hi}
instructions.ld["sp,(*)"] = {0xED, 0x7B, i_word1lo, i_word1hi}
instructions.ld["ix,(*)"] = {0xDD, 0x2A, i_word1lo, i_word1hi}
instructions.ld["iy,(*)"] = {0xFD, 0x2A, i_word1lo, i_word1hi}
-- unfinished

-- CP
instructions.cp = {
   ["*"] = {0xFE, byte1}
}

add_encoding(instructions.cp, {"b","c","d","e","h","l","(hl)","a"}, 0xB8, 1)
add_encoding(instructions.cp, {"ixh", "ixl"}, 0xBC, 1, 0xDD)
add_encoding(instructions.cp, {"iyh", "iyl"}, 0xBC, 1, 0xFD)

-- JP
instructions.jp = {
   ["*"] = {0xC3, word1lo, word1hi},
   ["(hl)"] = {0xE9},
   ["(ix)"] = {0xDD, 0xE9},
   ["(iy)"] = {0xFD, 0xE9},
   ["nz,*"] = {0xC2, word2lo, word2hi},
   ["z,*"] =  {0xCA, word2lo, word2hi},
   ["nc,*"] = {0xD2, word2lo, word2hi},
   ["c,*"] =  {0xDA, word2lo, word2hi},
   ["po,*"] = {0xE2, word2lo, word2hi},
   ["pe,*"] = {0xEA, word2lo, word2hi},
   ["p,*"] =  {0xF2, word2lo, word2hi},
   ["m,*"] =  {0xFA, word2lo, word2hi}
}

-- CALL
instructions.call = {
   ["*"] = {0xCD, word1lo, word1hi},
   ["nz,*"] = {0xC4, word2lo, word2hi},
   ["z,*"] =  {0xCC, word2lo, word2hi},
   ["nc,*"] = {0xD4, word2lo, word2hi},
   ["c,*"] =  {0xDC, word2lo, word2hi},
   ["po,*"] = {0xE4, word2lo, word2hi},
   ["pe,*"] = {0xEC, word2lo, word2hi},
   ["p,*"] =  {0xF4, word2lo, word2hi},
   ["m,*"] =  {0xFC, word2lo, word2hi}
}

-- DEC
instructions.dec = {
   ix = {0xDD, 0x2B},
   ixh = {0xDD, 0x25},
   ixl = {0xDD, 0x2D},
   iy = {0xFD, 0x2B},
   iyh = {0xFD, 0x25},
   iyl = {0xFD, 0x2D}
}

add_encoding(instructions.dec, {"bc", "de", "hl", "sp"}, 0x0B, 16)
add_encoding(instructions.dec, {"b", "c", "d", "e", "h", "l", "(hl)", "a"}, 0x05, 8)

-- INC
instructions.inc = {
   ix = {0xDD, 0x23},
   ixh = {0xDD, 0x24},
   ixl = {0xDD, 0x2C},
   iy = {0xFD, 0x23},
   iyh = {0xFD, 0x24},
   iyl = {0xFD, 0x2C}
}

add_encoding(instructions.inc, {"bc", "de", "hl", "sp"}, 0x03, 16)
add_encoding(instructions.inc, {"b", "c", "d", "e", "h", "l", "(hl)", "a"}, 0x04, 8)

-- ADD
instructions.add = {
   ["*"] = {0xC6, byte1},
   ixh = {0xDD, 0x84},
   ixl = {0xDD, 0x85},
   iyh = {0xFD, 0x84},
   iyl = {0xFD, 0x85}
}

add_encoding(instructions.add, {"hl,bc", "hl,de", "hl,hl", "hl,sp"}, 0x09, 16)
add_encoding(instructions.add, {"b", "c", "d", "e", "h", "l", "(hl)", "a"}, 0x80, 1)
add_encoding(instructions.add, {"ix,bc", "ix,de", "ix,ix", "ix,sp"}, 0x09, 16, 0xDD)
add_encoding(instructions.add, {"iy,bc", "iy,de", "iy,iy", "iy,sp"}, 0x09, 16, 0xFD)


-- ADC
instructions.adc = {
   ["*"] = {0xCE, byte1},
   ixh = {0xDD, 0x8C},
   ixl = {0xDD, 0x8D},
   iyh = {0xFD, 0x8C},
   iyl = {0xFD, 0x8D}
}

add_encoding(instructions.adc, {"a,b","a,c","a,d","a,e","a,h","a,l","a,(hl)","a,a"}, 0x88, 1)
add_encoding(instructions.adc, {"hl,bc", "hl,de", "hl,hl", "hl,sp"}, 0x4A, 16, 0xED)



-- assembling code
function encode(spec, arg1, arg2)
   local result = {}

   -- will have to decode (ix+4) values in some way at some point

   for i,b in ipairs(spec) do
      local value = b
      if type(b) == "function" then
         value = b(arg1, arg2)
         if not value then return "error" end
      end
      result[i] = value
   end

   return result
end

function ass(mnem, spec, arg1, arg2)
   local i = instructions[mnem]
   if not i then return nil end

   -- instructions (potentially) without arguments
   if type(i[1]) == "number" then return i end
   if not spec or spec == mnem then return i["none"] end

   -- print(spec,arg1,arg2)

   -- use the spec to extract the arguments
   -- local a1,a2,a3 = extract_arguments(spec, arg1, arg2)

   return encode(i[spec], arg1, arg2)
end




assembler.instructions = {
   ld = function (arg1, arg2)
      local t1,t2 = argtype(arg1), argtype(arg2)

      if (t1 == "register" or t1 == "iregister") then
         if t2 == "ioffregister" then
            return ld_reg_offreg(arg1, arg2)
         end
      elseif t1 == "ioffregister" and t2 == "register" then
         return ld_offreg_reg(arg1, arg2)
      end

      return nil
   end,

   dec = function (reg)
      local encoded = {}
      local t1 = argtype(reg)

      if t1 == "ioffregister" then
         local reg,value = read_register_and_offset(reg)

         encoded["ix"] = {0xDD, 0x35, value}
         encoded["iy"] = {0xFD, 0x35, value}
         return encoded[reg]
      else
         return "Error encoding!"
      end
   end,

   inc = function (reg)
      local encoded = {}
      local t1 = argtype(reg)

      if t1 == "ioffregister" then
         local reg,value = read_register_and_offset(reg)

         encoded["ix"] = {0xDD, 0x34, value}
         encoded["iy"] = {0xFD, 0x34, value}
         return encoded[reg]
      else
         return "Error encoding!"
      end
   end
}






return assembler
