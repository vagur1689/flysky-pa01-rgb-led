-- FlySky PA01 可视化 RGB 色盘与灯效设置工具 (前台 TOOLS 脚本)
-- 适配 PA01 320x240 彩屏 + 滚轮交互，支持实时硬件灯光预览与配置保存

local CFG_FILE = "/SCRIPTS/RGBLED/pa01led.cfg"

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

local PWR_MODES = { "固定", "渐变", "状态", "默认" }
local ARM_MODES = { "固定双色", "同步渐变", "反向渐变", "双色循环", "全色循环" }
local PREVIEW_MODES = { "自动SA", "锁定预览", "解锁预览" }
local SWAP_MODES = { "正常", "反向" }

-- 预计算色盘 25 个点的屏幕坐标 (中心 cx=254, cy=92)
local WHEEL_CX = 254
local WHEEL_CY = 92
local WHEEL_R  = 46
local wheelPts = {}
for i = 1, 24 do
  local ang = (i - 1) * (2 * math.pi / 24) - (math.pi / 2)
  wheelPts[i] = {
    x = math.floor(WHEEL_CX + WHEEL_R * math.cos(ang) + 0.5),
    y = math.floor(WHEEL_CY + WHEEL_R * math.sin(ang) + 0.5),
  }
end
wheelPts[25] = { x = WHEEL_CX, y = WHEEL_CY }

local cfg = {
  pwrColor  = 11,
  pwrBrt    = 80,
  pwrMode   = 1,
  lockColor = 13,
  lockBrt   = 60,
  armLeft   = 1,
  armRight  = 11,
  armBrt    = 90,
  armMode   = 3,
  armSpd    = 5,
  swapLR    = 0,
  previewMode = 0, -- 0=跟随SA, 1=强制锁定, 2=强制解锁
}

local focusIdx = 1
local editing = false
local statusMsg = "滚轮选择 回车调节"
local statusTick = 0
local phase = 0.0
local lastTick = 0
local saSourceId = nil

local ITEMS = {
  { key = "previewMode", label = "预览状态", kind = "enum",   min = 0, max = 2,  names = PREVIEW_MODES, zeroBased = true },
  { key = "pwrColor",    label = "开机键色", kind = "color",  min = 1, max = 25, previewState = 0 },
  { key = "pwrBrt",      label = "开机强度", kind = "slider", min = 0, max = 100, step = 5, previewState = 0 },
  { key = "pwrMode",     label = "开机模式", kind = "enum",   min = 1, max = 4,  names = PWR_MODES, previewState = 0 },
  { key = "lockColor",   label = "锁定颜色", kind = "color",  min = 1, max = 25, previewState = 1 },
  { key = "lockBrt",     label = "锁定强度", kind = "slider", min = 0, max = 100, step = 5, previewState = 1 },
  { key = "armLeft",     label = "解锁左色", kind = "color",  min = 1, max = 25, previewState = 2 },
  { key = "armRight",    label = "解锁右色", kind = "color",  min = 1, max = 25, previewState = 2 },
  { key = "armMode",     label = "解锁模式", kind = "enum",   min = 1, max = 5,  names = ARM_MODES, previewState = 2 },
  { key = "armBrt",      label = "解锁强度", kind = "slider", min = 0, max = 100, step = 5, previewState = 2 },
  { key = "armSpd",      label = "解锁速度", kind = "slider", min = 1, max = 10,  step = 1, previewState = 2 },
  { key = "swapLR",      label = "左右方向", kind = "enum",   min = 0, max = 1,  names = SWAP_MODES, zeroBased = true },
  { key = "save",        label = "[保存设置]", kind = "action" },
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function serializeCfg()
  return string.format(
    "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
    cfg.pwrColor, cfg.pwrBrt, cfg.pwrMode,
    cfg.lockColor, cfg.lockBrt,
    cfg.armLeft, cfg.armRight, cfg.armBrt,
    cfg.armMode, cfg.armSpd, cfg.swapLR
  )
end

local function loadCfg()
  if type(io) ~= "table" or type(io.open) ~= "function" then return end
  local f = io.open(CFG_FILE, "r")
  if not f then return end
  local text = io.read(f, 128)
  io.close(f)
  if type(text) ~= "string" then return end
  local nums = {}
  for token in string.gmatch(text, "(-?%d+)") do
    nums[#nums + 1] = tonumber(token)
  end
  if #nums >= 11 then
    cfg.pwrColor  = clamp(nums[1],  1, #PALETTE)
    cfg.pwrBrt    = clamp(nums[2],  0, 100)
    cfg.pwrMode   = clamp(nums[3],  1, 4)
    cfg.lockColor = clamp(nums[4],  1, #PALETTE)
    cfg.lockBrt   = clamp(nums[5],  0, 100)
    cfg.armLeft   = clamp(nums[6],  1, #PALETTE)
    cfg.armRight  = clamp(nums[7],  1, #PALETTE)
    cfg.armBrt    = clamp(nums[8],  0, 100)
    cfg.armMode   = clamp(nums[9],  1, 5)
    cfg.armSpd    = clamp(nums[10], 1, 10)
    cfg.swapLR    = clamp(nums[11], 0, 1)
  end
end

local function saveCfg()
  if type(io) ~= "table" or type(io.open) ~= "function" then
    statusMsg = "无SD卡"
    return false
  end
  local payload = serializeCfg()
  local f = io.open(CFG_FILE, "w")
  if not f then
    statusMsg = "保存失败: 只读"
    return false
  end
  io.write(f, payload)
  io.close(f)

  local rf = io.open(CFG_FILE, "r")
  if not rf then
    statusMsg = "读取失败"
    return false
  end
  local check = io.read(rf, 128)
  io.close(rf)
  if check == payload then
    statusMsg = "已保存到SD卡!"
    statusTick = type(getTime) == "function" and getTime() or 0
    return true
  end
  statusMsg = "写入失败"
  return false
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

local function isArmedNow()
  -- 编辑锁定/解锁参数时自动联动预览对应状态
  local item = ITEMS[focusIdx]
  if editing and item and item.previewState == 1 then return false end
  if editing and item and item.previewState == 2 then return true end
  if cfg.previewMode == 1 then return false end
  if cfg.previewMode == 2 then return true end
  if saSourceId and type(getValue) == "function" then
    local v = getValue(saSourceId)
    if type(v) == "number" then return v > 0 end
  end
  if type(getOutputValue) == "function" then
    local ch5 = getOutputValue(4)
    if type(ch5) == "number" then return ch5 < -500 end
  end
  return false
end

-- 计算并同步输出真机灯光，同时返回当前左/中(电源)/右 RGB 供屏幕模拟器显示
local function updateLiveLeds()
  local now = type(getTime) == "function" and getTime() or (lastTick + 4)
  local dt = now - lastTick
  if dt < 0 then dt = 0 end
  if dt > 0 then
    lastTick = now
    local step = (0.03 + cfg.armSpd * 0.018) * (dt / 4.0)
    phase = (phase + step) % (2 * math.pi * 60)
  end

  local armed = isArmedNow()
  local pCol = PALETTE[cfg.pwrColor] or PALETTE[11]
  if cfg.pwrMode == 3 then
    pCol = armed and (PALETTE[cfg.armLeft] or PALETTE[1])
                  or (PALETTE[cfg.lockColor] or PALETTE[13])
  end
  local pWave = 1.0
  if cfg.pwrMode == 2 then
    local s = math.sin(phase * 0.7) * 0.5 + 0.5
    pWave = 0.10 + 0.90 * (s * s)
  end
  local pr, pg, pb = scaleColor(pCol, cfg.pwrBrt, pWave)

  local l0r, l0g, l0b, r0r, r0g, r0b
  local leftIdx0, leftIdx1 = 0, 1
  local rightIdx0, rightIdx1 = 2, 3
  if cfg.swapLR == 1 then
    leftIdx0, leftIdx1 = 2, 3
    rightIdx0, rightIdx1 = 0, 1
  end

  if not armed then
    local lCol = PALETTE[cfg.lockColor] or PALETTE[13]
    l0r, l0g, l0b = scaleColor(lCol, cfg.lockBrt, 1.0)
    r0r, r0g, r0b = l0r, l0g, l0b
    if type(setRGBLedColor) == "function" then
      for i = 0, 3 do setRGBLedColor(i, l0r, l0g, l0b) end
    end
  else
    local cL = PALETTE[cfg.armLeft] or PALETTE[1]
    local cR = PALETTE[cfg.armRight] or PALETTE[11]
    local brt = cfg.armBrt
    if cfg.armMode == 1 then
      l0r, l0g, l0b = scaleColor(cL, brt, 1.0)
      r0r, r0g, r0b = scaleColor(cR, brt, 1.0)
      if type(setRGBLedColor) == "function" then
        setRGBLedColor(leftIdx0,  l0r, l0g, l0b)
        setRGBLedColor(leftIdx1,  l0r, l0g, l0b)
        setRGBLedColor(rightIdx0, r0r, r0g, r0b)
        setRGBLedColor(rightIdx1, r0r, r0g, r0b)
      end
    elseif cfg.armMode == 2 then
      local s = math.sin(phase) * 0.5 + 0.5
      local w = 0.06 + 0.94 * (s * s)
      l0r, l0g, l0b = scaleColor(cL, brt, w)
      r0r, r0g, r0b = scaleColor(cR, brt, w)
      if type(setRGBLedColor) == "function" then
        setRGBLedColor(leftIdx0,  l0r, l0g, l0b)
        setRGBLedColor(leftIdx1,  l0r, l0g, l0b)
        setRGBLedColor(rightIdx0, r0r, r0g, r0b)
        setRGBLedColor(rightIdx1, r0r, r0g, r0b)
      end
    elseif cfg.armMode == 3 then
      local sL = math.sin(phase) * 0.5 + 0.5
      local sR = math.sin(phase + math.pi) * 0.5 + 0.5
      l0r, l0g, l0b = scaleColor(cL, brt, 0.06 + 0.94 * sL * sL)
      r0r, r0g, r0b = scaleColor(cR, brt, 0.06 + 0.94 * sR * sR)
      if type(setRGBLedColor) == "function" then
        setRGBLedColor(leftIdx0,  l0r, l0g, l0b)
        setRGBLedColor(leftIdx1,  l0r, l0g, l0b)
        setRGBLedColor(rightIdx0, r0r, r0g, r0b)
        setRGBLedColor(rightIdx1, r0r, r0g, r0b)
      end
    elseif cfg.armMode == 4 then
      local order = { leftIdx0, leftIdx1, rightIdx0, rightIdx1 }
      for k = 1, 4 do
        local t = math.sin(phase - (k - 1) * 0.75) * 0.5 + 0.5
        local cr, cg, cb = lerpColor(cL, cR, t, brt)
        if k == 1 then l0r, l0g, l0b = cr, cg, cb end
        if k == 3 then r0r, r0g, r0b = cr, cg, cb end
        if type(setRGBLedColor) == "function" then
          setRGBLedColor(order[k], cr, cg, cb)
        end
      end
    else
      local baseHue = (phase * 45) % 360
      local order = { leftIdx0, leftIdx1, rightIdx0, rightIdx1 }
      for k = 1, 4 do
        local h = (baseHue + (k - 1) * 55) % 360
        local cr, cg, cb = hsvToRgb(h, 1.0, brt / 100.0)
        if k == 1 then l0r, l0g, l0b = cr, cg, cb end
        if k == 3 then r0r, r0g, r0b = cr, cg, cb end
        if type(setRGBLedColor) == "function" then
          setRGBLedColor(order[k], cr, cg, cb)
        end
      end
    end
  end

  if type(setRGBLedColor) == "function" and type(applyRGBLedColors) == "function" then
    if cfg.pwrMode ~= 4 then
      setRGBLedColor(254, pr, pg, pb)
      setRGBLedColor(255, pr, pg, pb)
    end
    applyRGBLedColors()
  end

  return armed, l0r, l0g, l0b, pr, pg, pb, r0r, r0g, r0b
end

local function rgbFlag(r, g, b)
  if type(lcd) == "table" and type(lcd.RGB) == "function" then
    return lcd.RGB(r, g, b)
  end
  return 0
end

local function activeColorIndex()
  local item = ITEMS[focusIdx]
  if item and item.kind == "color" then
    return cfg[item.key]
  elseif focusIdx <= 4 then
    return cfg.pwrColor
  elseif focusIdx <= 6 then
    return cfg.lockColor
  elseif focusIdx == 8 then
    return cfg.armRight
  else
    return cfg.armLeft
  end
end

local function drawWheel(selectedColorIdx, isEditingColor)
  -- 绘制色盘背景卡片
  lcd.drawFilledRectangle(192, 26, 124, 132, rgbFlag(22, 26, 34))
  lcd.drawRectangle(192, 26, 124, 132, isEditingColor and rgbFlag(255, 210, 0) or rgbFlag(70, 80, 95), 1)

  -- 绘制 24 颗环状色点 + 中心白点
  for i = 1, #PALETTE do
    local pt = wheelPts[i]
    local c = PALETTE[i]
    local r = (i == 25) and 6 or 5
    lcd.drawFilledCircle(pt.x, pt.y, r, rgbFlag(c[1], c[2], c[3]))
  end

  -- 中心大预览环 (避开正中白点，用粗外环展示当前选中色)
  local sel = PALETTE[selectedColorIdx] or PALETTE[1]
  lcd.drawCircle(WHEEL_CX, WHEEL_CY, 18, rgbFlag(sel[1], sel[2], sel[3]))
  lcd.drawCircle(WHEEL_CX, WHEEL_CY, 19, rgbFlag(sel[1], sel[2], sel[3]))

  -- 高亮选中色盘节点的光标外圈
  local spt = wheelPts[selectedColorIdx] or wheelPts[1]
  lcd.drawCircle(spt.x, spt.y, 8, rgbFlag(255, 255, 255))
  lcd.drawCircle(spt.x, spt.y, 9, rgbFlag(0, 0, 0))
end

local function drawRadioPreview(armed, lr, lg, lb, pr, pg, pb, rr, rg, rb)
  lcd.drawFilledRectangle(192, 162, 124, 52, rgbFlag(22, 26, 34))
  lcd.drawRectangle(192, 162, 124, 52, rgbFlag(70, 80, 95), 1)

  lcd.drawText(200, 165, armed and "当前: 解锁" or "当前: 锁定", SMLSIZE + rgbFlag(210, 220, 230))

  -- 左灯条预览
  lcd.drawFilledRectangle(202, 186, 18, 20, rgbFlag(lr, lg, lb))
  lcd.drawRectangle(202, 186, 18, 20, rgbFlag(200, 200, 200), 1)
  lcd.drawText(207, 188, "左", SMLSIZE + rgbFlag(0, 0, 0))

  -- 中央开机键预览
  lcd.drawFilledCircle(254, 196, 10, rgbFlag(pr, pg, pb))
  lcd.drawCircle(254, 196, 11, rgbFlag(220, 220, 220))

  -- 右灯条预览
  lcd.drawFilledRectangle(288, 186, 18, 20, rgbFlag(rr, rg, rb))
  lcd.drawRectangle(288, 186, 18, 20, rgbFlag(200, 200, 200), 1)
  lcd.drawText(293, 188, "右", SMLSIZE + rgbFlag(0, 0, 0))
end

local function drawItemRow(rowY, item, isFocused, isEditing)
  local bgCol = isFocused and (isEditing and rgbFlag(70, 55, 15) or rgbFlag(38, 52, 74)) or rgbFlag(22, 26, 34)
  lcd.drawFilledRectangle(4, rowY, 184, 24, bgCol)
  if isFocused then
    lcd.drawRectangle(4, rowY, 184, 24, isEditing and rgbFlag(255, 210, 0) or rgbFlag(100, 180, 255), 1)
  end

  local txtCol = rgbFlag(235, 240, 245)
  lcd.drawText(8, rowY + 3, item.label, SMLSIZE + txtCol)

  if item.kind == "color" then
    local cIdx = cfg[item.key]
    local c = PALETTE[cIdx] or PALETTE[1]
    lcd.drawFilledRectangle(102, rowY + 4, 48, 16, rgbFlag(c[1], c[2], c[3]))
    lcd.drawRectangle(102, rowY + 4, 48, 16, rgbFlag(230, 230, 230), 1)
    lcd.drawText(156, rowY + 3, "#" .. tostring(cIdx), SMLSIZE + txtCol)
  elseif item.kind == "slider" then
    local val = cfg[item.key]
    local ratio = (val - item.min) / (item.max - item.min)
    local barX, barY, barW, barH = 88, rowY + 8, 58, 8
    lcd.drawFilledRectangle(barX, barY, barW, barH, rgbFlag(55, 62, 72))
    local fillW = math.floor(barW * ratio + 0.5)
    if fillW > 0 then
      lcd.drawFilledRectangle(barX, barY, fillW, barH, rgbFlag(0, 200, 255))
    end
    local knobX = barX + fillW
    lcd.drawFilledCircle(knobX, barY + 4, 5, isEditing and rgbFlag(255, 220, 0) or rgbFlag(255, 255, 255))
    local suffix = (item.max == 100) and "%" or ""
    lcd.drawText(152, rowY + 3, tostring(val) .. suffix, SMLSIZE + txtCol)
  elseif item.kind == "enum" then
    local v = cfg[item.key]
    local nameIdx = item.zeroBased and (v + 1) or v
    local label = item.names[nameIdx] or tostring(v)
    lcd.drawText(100, rowY + 3, label, SMLSIZE + (isEditing and rgbFlag(255, 220, 0) or rgbFlag(120, 220, 255)))
  elseif item.kind == "action" then
    lcd.drawText(108, rowY + 3, "回车保存", SMLSIZE + rgbFlag(100, 255, 140))
  end
end

local function handleEvent(event)
  if event == 0 or event == nil then return 0 end

  if event == EVT_VIRTUAL_EXIT then
    if editing then
      editing = false
      statusMsg = "滚轮选择 回车调节"
      return 0
    else
      saveCfg()
      return 2
    end
  end

  local item = ITEMS[focusIdx]
  if event == EVT_VIRTUAL_ENTER then
    if item.kind == "action" then
      saveCfg()
    else
      editing = not editing
      statusMsg = editing and "滚轮调节 回车完成" or "滚轮选择 回车调节"
    end
    return 0
  end

  local delta = 0
  if event == EVT_VIRTUAL_NEXT or event == EVT_ROT_RIGHT then
    delta = 1
  elseif event == EVT_VIRTUAL_PREV or event == EVT_ROT_LEFT then
    delta = -1
  end

  if delta ~= 0 then
    if not editing then
      focusIdx = focusIdx + delta
      if focusIdx > #ITEMS then focusIdx = 1 end
      if focusIdx < 1 then focusIdx = #ITEMS end
    else
      local step = item.step or 1
      local nextVal = cfg[item.key] + delta * step
      if item.kind == "color" or item.kind == "enum" then
        if nextVal > item.max then nextVal = item.min end
        if nextVal < item.min then nextVal = item.max end
      else
        nextVal = clamp(nextVal, item.min, item.max)
      end
      cfg[item.key] = nextVal
    end
  end

  return 0
end

local function init()
  if type(getFieldInfo) == "function" then
    local info = getFieldInfo("sa")
    if info and info.id then saSourceId = info.id end
  end
  loadCfg()
  if _G then _G.__PA01_LED_LIVE = cfg end
  focusIdx = 1
  editing = false
  lastTick = type(getTime) == "function" and getTime() or 0
  return 0
end

local function run(event)
  if _G then _G.__PA01_LED_LIVE = cfg end
  local res = handleEvent(event)
  if res ~= 0 then
    if _G then _G.__PA01_LED_LIVE = nil end
    return res
  end

  local armed, lr, lg, lb, pr, pg, pb, rr, rg, rb = updateLiveLeds()

  lcd.clear(rgbFlag(14, 17, 23))

  -- 顶部标题栏 (320x22)
  lcd.drawFilledRectangle(0, 0, 320, 22, rgbFlag(28, 38, 54))
  lcd.drawText(8, 2, "PA01 RGB 调色与灯效设置", SMLSIZE + rgbFlag(255, 255, 255))

  -- 左侧 7 行滚动视窗 (y = 26..214)
  local visibleRows = 7
  local firstRow = clamp(focusIdx - 3, 1, #ITEMS - visibleRows + 1)
  for r = 0, visibleRows - 1 do
    local idx = firstRow + r
    local item = ITEMS[idx]
    if item then
      drawItemRow(26 + r * 27, item, idx == focusIdx, idx == focusIdx and editing)
    end
  end

  -- 右侧 RGB 色盘 + 机身实时模拟器
  local curItem = ITEMS[focusIdx]
  drawWheel(activeColorIndex(), editing and curItem and curItem.kind == "color")
  drawRadioPreview(armed, lr, lg, lb, pr, pg, pb, rr, rg, rb)

  -- 底部状态提示栏 (y = 218..240)
  lcd.drawFilledRectangle(0, 218, 320, 22, rgbFlag(24, 30, 40))
  lcd.drawText(8, 221, statusMsg, SMLSIZE + rgbFlag(180, 220, 255))
  lcd.drawText(206, 221, string.format("项 %d/%d", focusIdx, #ITEMS), SMLSIZE + rgbFlag(160, 170, 185))

  return 0
end

return { init = init, run = run }
