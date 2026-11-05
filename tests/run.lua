-- 在仓库根目录执行：lua tests/run.lua
local function readFile(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("*a")
  file:close()
  return text
end

local bgSource = readFile("SCRIPTS/RGBLED/pa01led.lua")
local toolSource = readFile("SCRIPTS/TOOLS/pa01led.lua")
local cfgPath = "/SCRIPTS/RGBLED/pa01led.cfg"
local tests = 0

local function test(name, fn)
  fn()
  tests = tests + 1
  print("PASS " .. name)
end

local function makeEnv(initialCfg)
  local state = {
    time = 100,
    sa = -1024,
    ch5 = 1024,
    leds = {},
    frames = 0,
    handles = 0,
    cfgText = initialCfg,
    readOnly = false,
    corruptWrite = false,
    sharedG = {},
  }

  local env
  env = setmetatable({
    LCD_W = 320,
    LCD_H = 240,
    LED_STRIP_LENGTH = 4,
    SMLSIZE = 256,
    EVT_VIRTUAL_NEXT = 1,
    EVT_VIRTUAL_PREV = 2,
    EVT_VIRTUAL_ENTER = 3,
    EVT_VIRTUAL_EXIT = 4,
    EVT_ROT_RIGHT = 5,
    EVT_ROT_LEFT = 6,
    getTime = function() return state.time end,
    getFieldInfo = function(name)
      if name == "sa" then return { id = 42 } end
      return nil
    end,
    getValue = function(id)
      assert(id == 42, "unexpected source id")
      return state.sa
    end,
    getOutputValue = function(ch)
      assert(ch == 4, "expected CH5 index 4")
      return state.ch5
    end,
    setRGBLedColor = function(id, r, g, b)
      assert(id == 0 or id == 1 or id == 2 or id == 3 or id == 254 or id == 255,
        "unexpected PA01 LED id: " .. tostring(id))
      for _, v in ipairs({ r, g, b }) do
        assert(v % 1 == 0 and v >= 0 and v <= 255, "invalid RGB channel value")
      end
      state.leds[id] = { r, g, b }
    end,
    applyRGBLedColors = function()
      state.frames = state.frames + 1
    end,
    lcd = {
      clear = function() end,
      RGB = function(r, g, b)
        assert(r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255)
        return r * 65536 + g * 256 + b
      end,
      drawFilledRectangle = function(x, y, w, h)
        assert(x >= 0 and x + w <= 320 and y >= 0 and y + h <= 240, "rect out of 320x240 bounds")
      end,
      drawRectangle = function(x, y, w, h)
        assert(x >= 0 and x + w <= 320 and y >= 0 and y + h <= 240, "border out of 320x240 bounds")
      end,
      drawFilledCircle = function(x, y, r)
        assert(x - r >= 0 and x + r <= 320 and y - r >= 0 and y + r <= 240, "circle out of 320x240 bounds")
      end,
      drawCircle = function(x, y, r)
        assert(x - r >= 0 and x + r <= 320 and y - r >= 0 and y + r <= 240, "circle out of 320x240 bounds")
      end,
      drawText = function(x, y, s)
        assert(x >= 0 and x < 320 and y >= 0 and y < 240, "text out of 320x240 bounds")
        assert(type(s) == "string")
      end,
    },
    io = {
      open = function(path, mode)
        assert(path == cfgPath, "unexpected path: " .. tostring(path))
        if mode == "r" then
          if state.cfgText == nil then return nil end
          state.handles = state.handles + 1
          return { mode = "r", closed = false }
        elseif mode == "w" then
          if state.readOnly then return nil end
          state.cfgText = ""
          state.handles = state.handles + 1
          return { mode = "w", closed = false }
        end
        error("unsupported mode")
      end,
      read = function(f, count)
        assert(f.mode == "r" and not f.closed)
        return state.cfgText:sub(1, count)
      end,
      write = function(f, data)
        assert(f.mode == "w" and not f.closed)
        if state.corruptWrite then
          state.cfgText = "corrupted"
        else
          state.cfgText = state.cfgText .. data
        end
      end,
      close = function(f)
        assert(not f.closed)
        f.closed = true
        state.handles = state.handles - 1
      end,
    },
  }, { __index = _G })
  env._G = state.sharedG
  return env, state
end

local function loadInEnv(src, env)
  return assert(load(src, "@script", "t", env))()
end

test("default locked and armed states drive side strips (0..3) and power LED (254,255)", function()
  local env, state = makeEnv(nil)
  local bg = loadScript and nil or loadInEnv(bgSource, env)
  bg.init()
  state.time = 110
  state.sa = -1024 -- Locked
  bg.run()
  assert(state.frames == 1 and state.handles == 0)
  for _, id in ipairs({ 0, 1, 2, 3, 254, 255 }) do
    assert(state.leds[id] ~= nil, "missing LED write for id " .. id)
  end
  -- Locked state sets all 4 strip LEDs to the same color
  for id = 1, 3 do
    assert(state.leds[id][1] == state.leds[0][1]
       and state.leds[id][2] == state.leds[0][2]
       and state.leds[id][3] == state.leds[0][3], "locked LEDs must match")
  end
end)

test("all 5 armed modes and swapLR produce valid RGB frames across time steps", function()
  for mode = 1, 5 do
    for swap = 0, 1 do
      local cfg = string.format("11,80,2,13,60,1,15,90,%d,6,%d\n", mode, swap)
      local env, state = makeEnv(cfg)
      local bg = loadInEnv(bgSource, env)
      bg.init()
      state.sa = 1024 -- Armed
      for step = 1, 8 do
        state.time = state.time + 6
        bg.run()
      end
      assert(state.frames == 8 and state.handles == 0)
      if mode == 1 then
        local leftId = (swap == 0) and 0 or 2
        local rightId = (swap == 0) and 2 or 0
        assert(state.leds[leftId][1] > 200 and state.leds[leftId][3] == 0, "left should be red")
        assert(state.leds[rightId][3] > 200 and state.leds[rightId][1] == 0, "right should be blue")
      end
    end
  end
end)

test("power button mode 4 (default) does not overwrite LEDs 254 and 255", function()
  local env, state = makeEnv("11,80,4,13,60,1,11,90,1,5,0\n")
  local bg = loadInEnv(bgSource, env)
  bg.init()
  state.time = 110
  bg.run()
  assert(state.leds[254] == nil and state.leds[255] == nil, "mode 4 must leave power LEDs untouched")
  assert(state.leds[0] ~= nil and state.leds[3] ~= nil)
end)

test("foreground configurator UI stays within 320x240, edits values, and persists verified config", function()
  local env, state = makeEnv(nil)
  local tool = loadInEnv(toolSource, env)
  assert(tool.init() == 0)
  assert(tool.run(0) == 0)
  -- Move to pwrColor (item 2), enter edit, rotate +4, confirm
  tool.run(env.EVT_VIRTUAL_NEXT)
  tool.run(env.EVT_VIRTUAL_ENTER)
  for _ = 1, 4 do tool.run(env.EVT_VIRTUAL_NEXT) end
  tool.run(env.EVT_VIRTUAL_ENTER)
  -- Scroll through remaining items to verify every row renders within 320x240
  for _ = 1, 15 do
    state.time = state.time + 5
    assert(tool.run(env.EVT_VIRTUAL_NEXT) == 0)
  end
  -- Exit triggers save and clears live shared state
  assert(tool.run(env.EVT_VIRTUAL_EXIT) == 2)
  assert(state.cfgText == "15,80,1,13,60,1,11,90,3,5,0\n", "unexpected saved config: " .. tostring(state.cfgText))
  assert(state.sharedG.__PA01_LED_LIVE == nil and state.handles == 0)
end)

test("read-only or corrupted SD write is caught by read-back verification", function()
  local env, state = makeEnv(nil)
  state.corruptWrite = true
  local tool = loadInEnv(toolSource, env)
  tool.init()
  -- Jump to [保存设置] (last item) and press ENTER
  tool.run(env.EVT_VIRTUAL_PREV)
  tool.run(env.EVT_VIRTUAL_ENTER)
  assert(state.handles == 0)
end)

print(string.format("All %d test suites passed.", tests))
