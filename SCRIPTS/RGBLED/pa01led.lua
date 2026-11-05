-- FlySky PA01 专属灯光控制引擎 (后台 RGBLED 脚本)
-- 配合 /SCRIPTS/TOOLS/pa01led.lua 可视化调色盘工具使用

local CFG_FILE = "/SCRIPTS/RGBLED/pa01led.cfg"

-- 25 色色盘预置表（序号 1..24 为 360° RGB 色环每 15° 一格，序号 25 为纯白）
local PALETTE = {
  { 255,   0,   0 }, -- 1: 红 0°
  { 255,  64,   0 }, -- 2: 橙红 15°
  { 255, 128,   0 }, -- 3: 橙 30°
  { 255, 191,   0 }, -- 4: 金黄 45°
  { 255, 255,   0 }, -- 5: 黄 60°
  { 191, 255,   0 }, -- 6: 黄绿 75°
  { 128, 255,   0 }, -- 7: 翠绿 90°
  {   0, 255,   0 }, -- 8: 纯绿 120°
  {   0, 255,  85 }, -- 9: 春绿 140°
  {   0, 255, 170 }, -- 10: 青绿 160°
  {   0, 255, 255 }, -- 11: 青 180°
  {   0, 191, 255 }, -- 12: 天蓝 195°
  {   0, 128, 255 }, -- 13: 蔚蓝 210°
  {   0,  64, 255 }, -- 14: 海蓝 225°
  {   0,   0, 255 }, -- 15: 纯蓝 240°
  {  64,   0, 255 }, -- 16: 靛蓝 255°
  { 128,   0, 255 }, -- 17: 紫罗兰 270°
  { 191,   0, 255 }, -- 18: 亮紫 285°
  { 255,   0, 255 }, -- 19: 品红 300°
  { 255,   0, 191 }, -- 20: 洋红 315°
  { 255,   0, 128 }, -- 21: 玫红 330°
  { 255,   0,  64 }, -- 22: 猩红 345°
  { 255, 110, 180 }, -- 23: 樱花粉
  { 120, 220, 255 }, -- 24: 冰晶蓝
  { 255, 255, 255 }, -- 25: 纯白
}

local function defaultCfg()
  return {
    pwrColor  = 11,  -- 开机键颜色序号 (默认 11: 青色)
    pwrBrt    = 80,  -- 开机键强度 5..100 (%)
    pwrMode   = 1,   -- 开机键模式: 1=固定, 2=渐变, 3=状态, 4=默认
    lockColor = 13,  -- 锁定灯条颜色序号 (默认 13: 蔚蓝)
    lockBrt   = 60,  -- 锁定灯条强度 5..100 (%)
    armLeft   = 1,   -- 解锁左灯条颜色序号 (默认 1: 红)
    armRight  = 11,  -- 解锁右灯条颜色序号 (默认 11: 青)
    armBrt    = 90,  -- 解锁灯条强度 5..100 (%)
    armMode   = 3,   -- 解锁灯效: 1=固定双色, 2=同步渐变, 3=反向渐变, 4=双色循环, 5=全色循环
    armSpd    = 5,   -- 解锁速度 1..10
    swapLR    = 0,   -- 左右灯条对调: 0=正常(0,1左/2,3右), 1=对调
  }
end

local cfg = defaultCfg()
local saSourceId = nil
local lastTick = 0
local lastCfgReload = 0
local phase = 0.0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function parseCfg(text)
  if type(text) ~= "string" or #text == 0 then return nil end
  local nums = {}
  for token in string.gmatch(text, "(-?%d+)") do
    nums[#nums + 1] = tonumber(token)
  end
  if #nums < 11 then return nil end
  return {
    pwrColor  = clamp(nums[1],  1, #PALETTE),
    pwrBrt    = clamp(nums[2],  0, 100),
    pwrMode   = clamp(nums[3],  1, 4),
    lockColor = clamp(nums[4],  1, #PALETTE),
    lockBrt   = clamp(nums[5],  0, 100),
    armLeft   = clamp(nums[6],  1, #PALETTE),
    armRight  = clamp(nums[7],  1, #PALETTE),
    armBrt    = clamp(nums[8],  0, 100),
    armMode   = clamp(nums[9],  1, 5),
    armSpd    = clamp(nums[10], 1, 10),
    swapLR    = clamp(nums[11], 0, 1),
  }
end

local function loadCfgFromDisk()
  if type(io) ~= "table" or type(io.open) ~= "function" then return end
  local f = io.open(CFG_FILE, "r")
  if not f then return end
  local content = io.read(f, 128)
  io.close(f)
  local parsed = parseCfg(content)
  if parsed then
    cfg = parsed
  end
end

local function hsvToRgb(h, s, v)
  h = h % 360
  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c
  local r, g, b
  if h < 60 then r, g, b = c, x, 0
  elseif h < 120 then r, g, b = x, c, 0
  elseif h < 180 then r, g, b = 0, c, x
  elseif h < 240 then r, g, b = 0, x, c
  elseif h < 300 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  return math.floor((r + m) * 255 + 0.5),
         math.floor((g + m) * 255 + 0.5),
         math.floor((b + m) * 255 + 0.5)
end

local function scaleColor(c, brtPct, wave)
  local factor = (brtPct / 100.0) * (wave or 1.0)
  return math.floor(c[1] * factor + 0.5),
         math.floor(c[2] * factor + 0.5),
         math.floor(c[3] * factor + 0.5)
end

local function lerpColor(c1, c2, t, brtPct)
  local factor = brtPct / 100.0
  local r = (c1[1] * (1 - t) + c2[1] * t) * factor
  local g = (c1[2] * (1 - t) + c2[2] * t) * factor
  local b = (c1[3] * (1 - t) + c2[3] * t) * factor
  return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

local function isArmed(activeCfg)
  if activeCfg.previewMode == 1 then return false end
  if activeCfg.previewMode == 2 then return true end
  if saSourceId then
    local v = getValue(saSourceId)
    if type(v) == "number" then
      return v > 0
    end
  end
  if type(getOutputValue) == "function" then
    local ch5 = getOutputValue(4)
    if type(ch5) == "number" then
      return ch5 < -500
    end
  end
  return false
end

local function init()
  if type(getFieldInfo) == "function" then
    local info = getFieldInfo("sa")
    if info and info.id then
      saSourceId = info.id
    end
  end
  loadCfgFromDisk()
  lastTick = type(getTime) == "function" and getTime() or 0
  lastCfgReload = lastTick
  phase = 0.0
end

local function run()
  if type(setRGBLedColor) ~= "function" or type(applyRGBLedColors) ~= "function" then
    return
  end

  local now = type(getTime) == "function" and getTime() or (lastTick + 5)
  local dt = now - lastTick
  if dt < 0 then dt = 0 end
  if dt < 3 then return end -- 约 33fps 刷新率
  lastTick = now

  -- 若前台调色工具正在运行，优先使用内存实时预览配置；否则每 2 秒检查一次配置文件更新
  local activeCfg = (_G and _G.__PA01_LED_LIVE) or cfg
  if not (_G and _G.__PA01_LED_LIVE) and (now - lastCfgReload >= 200) then
    lastCfgReload = now
    loadCfgFromDisk()
    activeCfg = cfg
  end

  -- 推进相位：速度 1..10 映射到角速度
  local step = (0.03 + activeCfg.armSpd * 0.018) * (dt / 4.0)
  phase = (phase + step) % (2 * math.pi * 60)

  local armed = isArmed(activeCfg)

  -- 1. 控制开机键 RGB 灯珠
  if activeCfg.pwrMode ~= 4 then
    local pCol = PALETTE[activeCfg.pwrColor] or PALETTE[11]
    if activeCfg.pwrMode == 3 then
      pCol = armed and (PALETTE[activeCfg.armLeft] or PALETTE[1])
                    or (PALETTE[activeCfg.lockColor] or PALETTE[13])
    end
    local pWave = 1.0
    if activeCfg.pwrMode == 2 then
      local s = math.sin(phase * 0.7) * 0.5 + 0.5
      pWave = 0.10 + 0.90 * (s * s)
    end
    local pr, pg, pb = scaleColor(pCol, activeCfg.pwrBrt, pWave)
    setRGBLedColor(254, pr, pg, pb)
    setRGBLedColor(255, pr, pg, pb)
  end

  -- 2. 控制机身左右两侧灯条 (Lua 0,1 与 2,3)
  local leftIdx0, leftIdx1 = 0, 1
  local rightIdx0, rightIdx1 = 2, 3
  if activeCfg.swapLR == 1 then
    leftIdx0, leftIdx1 = 2, 3
    rightIdx0, rightIdx1 = 0, 1
  end

  if not armed then
    -- 锁定状态：固定常亮 + 选定颜色 + 选定亮度
    local lCol = PALETTE[activeCfg.lockColor] or PALETTE[13]
    local lr, lg, lb = scaleColor(lCol, activeCfg.lockBrt, 1.0)
    setRGBLedColor(0, lr, lg, lb)
    setRGBLedColor(1, lr, lg, lb)
    setRGBLedColor(2, lr, lg, lb)
    setRGBLedColor(3, lr, lg, lb)
  else
    -- 解锁状态：5 种组合灯效
    local cL = PALETTE[activeCfg.armLeft] or PALETTE[1]
    local cR = PALETTE[activeCfg.armRight] or PALETTE[11]
    local mode = activeCfg.armMode
    local brt = activeCfg.armBrt

    if mode == 1 then
      -- ① 固定双色：左固定 cL，右固定 cR
      local r1, g1, b1 = scaleColor(cL, brt, 1.0)
      local r2, g2, b2 = scaleColor(cR, brt, 1.0)
      setRGBLedColor(leftIdx0,  r1, g1, b1)
      setRGBLedColor(leftIdx1,  r1, g1, b1)
      setRGBLedColor(rightIdx0, r2, g2, b2)
      setRGBLedColor(rightIdx1, r2, g2, b2)
    elseif mode == 2 then
      -- ② 同步渐变（同步呼吸）
      local s = math.sin(phase) * 0.5 + 0.5
      local w = 0.06 + 0.94 * (s * s)
      local r1, g1, b1 = scaleColor(cL, brt, w)
      local r2, g2, b2 = scaleColor(cR, brt, w)
      setRGBLedColor(leftIdx0,  r1, g1, b1)
      setRGBLedColor(leftIdx1,  r1, g1, b1)
      setRGBLedColor(rightIdx0, r2, g2, b2)
      setRGBLedColor(rightIdx1, r2, g2, b2)
    elseif mode == 3 then
      -- ③ 反向渐变（左右交替呼吸）
      local sL = math.sin(phase) * 0.5 + 0.5
      local sR = math.sin(phase + math.pi) * 0.5 + 0.5
      local wL = 0.06 + 0.94 * (sL * sL)
      local wR = 0.06 + 0.94 * (sR * sR)
      local r1, g1, b1 = scaleColor(cL, brt, wL)
      local r2, g2, b2 = scaleColor(cR, brt, wR)
      setRGBLedColor(leftIdx0,  r1, g1, b1)
      setRGBLedColor(leftIdx1,  r1, g1, b1)
      setRGBLedColor(rightIdx0, r2, g2, b2)
      setRGBLedColor(rightIdx1, r2, g2, b2)
    elseif mode == 4 then
      -- ④ 双色循环：左右灯珠在 cL ⇄ cR 之间带相位差流动循环
      local order = { leftIdx0, leftIdx1, rightIdx0, rightIdx1 }
      for k = 1, 4 do
        local t = math.sin(phase - (k - 1) * 0.75) * 0.5 + 0.5
        local r, g, b = lerpColor(cL, cR, t, brt)
        setRGBLedColor(order[k], r, g, b)
      end
    else
      -- ⑤ 全色循环：沿 360° RGB 色盘流光循环
      local baseHue = (phase * 45) % 360
      local order = { leftIdx0, leftIdx1, rightIdx0, rightIdx1 }
      for k = 1, 4 do
        local h = (baseHue + (k - 1) * 55) % 360
        local r, g, b = hsvToRgb(h, 1.0, brt / 100.0)
        setRGBLedColor(order[k], r, g, b)
      end
    end
  end

  applyRGBLedColors()
end

local function background()
end

return { init = init, run = run, background = background }
