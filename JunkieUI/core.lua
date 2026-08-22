-- Junkie UI - Featherlight
-- Core: namespace, defaults, helpers

local ADDON = ...
JunkieUI = CreateFrame("Frame", "JunkieUIFrame", UIParent)
local J = JunkieUI

J.version = "2.5.1"
J.modules = {}

-- Colors -------------------------------------------------------------------
J.BORDER = { 0.137, 0.137, 0.137 }
J.BACKDROP = { 0.102, 0.102, 0.102 }

J.defaults = {
  uiScale = 0.6333,       -- Small 0.5333 | Medium 0.6333 | Large 0.7333
  mapSize = 1,            -- minimap size step 1..5 (5 = 20% larger)
  fontChoice = "expressway", -- media.lua font key
  barTexture = "Flat",    -- statusbar texture name (media.lua / LibSharedMedia)
  cooldownText = true,
  macroText = false,      -- show macro names on action buttons
  barLayout = "one",      -- one | three | triple | tripleHigh | sebby
  barBackground = true,   -- background plates behind the action bars
  stanceBar = false,      -- show the stance / shapeshift bar (top left)
  microMenu = false,      -- show Blizzard's micro menu under the clock bar



  unitGap = 250,          -- pixels between player and target frame (1..500)
  unitY = -180,           -- shared Y offset from center
  hideCoAResource = false, -- hide Ascension's own resource bars / orb
  coaWasHidden = false,   -- bookkeeping: the option hid them at least once
  coaHiddenFrames = {},   -- exact Ascension widgets hidden by this option

  playerPower = true,     -- show player power bar
  targetPower = true,     -- show target power bar
  targetAuraText = true,  -- cooldown text on target buffs/debuffs
  -- castbars
  playerCastbar = true,   -- JunkieUI player castbar
  targetCastbar = true,   -- JunkieUI target castbar
  blizzardCastbars = false, -- keep Blizzard's own castbars visible
  -- player auras (own boxes under the minimap)
  buffSize = 30,          -- player buff icon size
  playerDebuffSize = 34,  -- player debuff icon size (under the minimap)
  debuffsOnFrame = false, -- dock the debuff block above the player unit frame
  debuffBlacklist = {},   -- [spellID] = true, hidden player debuffs (O(1) lookup)
  -- totem bar (shaman)
  totemBar = true,        -- show the totem / multicast bar
  totemUnlocked = false,  -- allow dragging it
  totemMoved = false,     -- use the custom position below
  totemX = 0,
  totemY = 0,

  -- objective / quest tracker
  watchUnlocked = false,  -- allow dragging the quest tracker
  watchX = 10,            -- offset from UIParent TOPLEFT
  watchY = -40,
  -- group loot roll block
  lootUnlocked = false,
  lootX = 0,
  lootY = 180,
  -- tooltip
  tooltipMouse = false,    -- tooltip follows the mouse (top right, 8px)
  tooltipUnlocked = false, -- show/move the anchor
  tooltipX = -220,
  tooltipY = 220,
  tooltipIDs = true,       -- show spell / aura IDs on the tooltip
  -- quality of life
  autoRepair = true,      -- repair all on merchant open
  -- Junkie Cooldown Manager (separate LoadOnDemand module)
  cdEnabled = false,      -- load JunkieCD on login
  cdGap = 1,              -- px between the manager and each unit frame
}


-- Helpers ------------------------------------------------------------------
function J:SkinUnit(frame)
  if frame.jbg then return frame end
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(frame)
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(J.BACKDROP[1], J.BACKDROP[2], J.BACKDROP[3], 1)
  frame.jbg = bg

  local b = CreateFrame("Frame", nil, frame)
  b:SetAllPoints(frame)
  b:SetFrameLevel(frame:GetFrameLevel() + 3)
  b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  b:SetBackdropBorderColor(0, 0, 0, 1)
  frame.jborder = b
  return frame
end

function J:Text(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(J.font, size or 12, "OUTLINE")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetShadowOffset(0, 0)
  return fs
end

-- Movable elements ----------------------------------------------------------
-- Loot rolls, the totem bar and the quest tracker all used to
-- hand-roll the same drag handle: identical backdrop table, identical colors,
-- identical StartMoving/StopMovingOrSizing pair. One implementation now, so a
-- fix or a color change lands everywhere at once.
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
J.MOVER_BACKDROP = { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 }
J.MOVER_BORDER = { 0.871, 0.447, 0.188 }   -- ember (frames, totem bar)
J.MOVER_BORDER_ALT = { 0.78, 0.64, 0.36 }  -- gold (loot rolls, quest tracker)

-- Solid plate with a 1px border. Used by movers and their placeholders.
function J:Plate(frame, r, g, b, a, border, ba)
  frame:SetBackdrop(J.MOVER_BACKDROP)
  frame:SetBackdropColor(r, g, b, a)
  border = border or J.MOVER_BORDER
  frame:SetBackdropBorderColor(border[1], border[2], border[3], ba or 1)
  return frame
end

-- Drag handle. Starts hidden; the caller wires OnDragStop and decides where
-- the resulting position is stored.
function J:CreateMover(name, w, h, text, border, alpha, fontSize)
  local m = CreateFrame("Frame", name, UIParent)
  if w and h then m:SetSize(w, h) end
  m:SetFrameStrata("DIALOG")
  m:EnableMouse(true)
  m:SetMovable(true)
  m:RegisterForDrag("LeftButton")
  J:Plate(m, 0.09, 0.09, 0.09, alpha or 0.9, border)
  m:SetScript("OnDragStart", function(self) self:StartMoving() end)

  local fs = J:Text(m, fontSize or 11, "CENTER")
  fs:SetPoint("CENTER")
  fs:SetText(text or "")
  m.label = fs
  m:Hide()
  return m
end

-- UIParent-relative position of a frame, in UIParent coordinates. Every drag
-- stop in this addon needs the same scale correction.
function J:MoverPos(frame)
  local scale = UIParent:GetEffectiveScale()
  if not scale or scale == 0 then scale = 1 end
  local mul = frame:GetEffectiveScale() / scale
  return (frame:GetLeft() or 0) * mul, (frame:GetBottom() or 0) * mul,
    (frame:GetTop() or 0) * mul
end


-- Keybind labels ------------------------------------------------------------
-- Blizzard's binding text ("Mouse Button 4", "Shift-Num Pad 1") is far too long
-- for a 30px button, so every bar renders the same shortened form.
-- Order matters: the longest names must be replaced before their substrings.
local KEY_SHORT = {
  { "MOUSE WHEEL UP", "MU" }, { "MOUSEWHEELUP", "MU" },
  { "MOUSE WHEEL DOWN", "MD" }, { "MOUSEWHEELDOWN", "MD" },
  { "MIDDLE MOUSE", "M3" }, { "MIDDLEMOUSE", "M3" },
  { "MOUSE BUTTON", "M" }, { "MOUSEBUTTON", "M" }, { "BUTTON", "M" },
  { "NUM PAD", "N" }, { "NUMPAD", "N" },
  { "PAGE UP", "PU" }, { "PAGEUP", "PU" },
  { "PAGE DOWN", "PD" }, { "PAGEDOWN", "PD" },
  { "SPACEBAR", "Sp" }, { "SPACE", "Sp" },
  { "BACKSPACE", "BS" }, { "CAPSLOCK", "Cp" }, { "ESCAPE", "Esc" },
  { "INSERT", "Ins" }, { "DELETE", "Del" }, { "HOME", "Hm" }, { "END", "En" },
  { "DIVIDE", "/" }, { "MULTIPLY", "*" }, { "MINUS", "-" }, { "PLUS", "+" },
}

function J:AbbrevKey(text)
  if not text or text == "" then return text end
  local out = text:upper()
  -- Modifiers first: Blizzard separates them with "-".
  out = out:gsub("ALT%-", "a"):gsub("CTRL%-", "c"):gsub("SHIFT%-", "s")
  for _, pair in ipairs(KEY_SHORT) do
    out = out:gsub(pair[1], pair[2])
  end
  out = out:gsub("%s+", "")
  return out
end

-- Writes the shortened label and shrinks the font until it fits the button.
-- Dragging a spell makes Blizzard refresh every button at once, so the result
-- is cached per font string: repeated skins on unchanged text cost nothing.
function J:ShortenHotkey(fs, button, maxSize)
  if not fs then return end
  local raw = fs:GetText()
  if not raw or raw == "" or raw == RANGE_INDICATOR then return end
  if raw == fs.jkeyOut then return end
  if raw == fs.jkeyRaw and fs.jkeyOut then
    -- Same binding, but something re-wrote the long form: restore the short
    -- label and keep the measured font size.
    fs:SetText(fs.jkeyOut)
    if fs.jkeySize then fs:SetFont(J.font, fs.jkeySize, "OUTLINE") end
    return
  end
  local short = J:AbbrevKey(raw)
  fs.jkeyRaw = raw
  fs.jkeyOut = short
  if short ~= raw then fs:SetText(short) end
  local width = (button and button:GetWidth() or 30) - 4
  local size = maxSize or 11
  fs:SetFont(J.font, size, "OUTLINE")
  while size > 7 and fs:GetStringWidth() > width do
    size = size - 1
    fs:SetFont(J.font, size, "OUTLINE")
  end
  fs.jkeySize = size
end



function J:Short(v)
  if not v then return "" end
  if v >= 1e6 then return string.format("%.1fm", v / 1e6) end
  if v >= 1e3 then return string.format("%.1fk", v / 1e3) end
  return tostring(v)
end

-- Init ---------------------------------------------------------------------
J:RegisterEvent("ADDON_LOADED")
J:RegisterEvent("PLAYER_LOGIN")
function J:ApplyScale()
  SetCVar("useUiScale", 1)
  SetCVar("uiScale", J.db.uiScale)
  UIParent:SetScale(J.db.uiScale)
end

function J:AddModule(fn) table.insert(J.modules, fn) end

-- The cooldown manager reports only the lower row height. Passing its frame to
-- the secure pet unit button would make that frame protected on older clients.
function J:SetPetDock(height) J.petDockHeight = tonumber(height) or 0 end

J:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    JunkieUIDB = JunkieUIDB or {}
    for k, v in pairs(J.defaults) do
      if type(v) == "table" then
        -- Table defaults must never be shared with the defaults table itself,
        -- otherwise a saved edit would write straight into J.defaults.
        if type(JunkieUIDB[k]) ~= "table" then
          local copy = {}
          for dk, dv in pairs(v) do copy[dk] = dv end
          JunkieUIDB[k] = copy
        end
      elseif JunkieUIDB[k] == nil then
        JunkieUIDB[k] = v
      end
    end
    -- Drop keys from removed features so old saved variables stay clean.
    for k in pairs(JunkieUIDB) do
      if J.defaults[k] == nil then JunkieUIDB[k] = nil end
    end
    J.db = JunkieUIDB
    if J.ApplyFont then J:ApplyFont() end
    -- Bar textures are resolved before any module builds its bars, so every
    -- statusbar is created with the chosen texture already in place.
    if J.BuildTextureList then
      J:BuildTextureList()
      J:ApplyBarTexture()
    end

  elseif event == "PLAYER_LOGIN" then
    J:ApplyScale()
    -- The cooldown manager is a module of this addon: we load it, it never
    -- loads itself. Doing it on the login path keeps older 3.3.5 clients happy.
    if J.db.cdEnabled and not IsAddOnLoaded("JunkieCD") then
      if EnableAddOn then EnableAddOn("JunkieCD") end
      LoadAddOn("JunkieCD")
    end
    for _, fn in ipairs(J.modules) do fn() end
    -- Media addons register their textures during load, so the list is rebuilt
    -- once everything is up and the chosen texture is pushed to every bar.
    if J.BuildTextureList then
      J:BuildTextureList()
      J:ApplyBarTexture()
    end

    print("|cff4fc3f7Welcome to JunkieUI v" .. J.version .. ".|r |cffffffff/JUI|r for settings.")
  end
end)

