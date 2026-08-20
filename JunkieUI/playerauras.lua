-- ---------------------------------------------------------------------------
-- JunkieUI - player buffs / debuffs
-- ---------------------------------------------------------------------------
-- Blizzard's aura frames are hidden and replaced with our own flat icon boxes
-- (same style as the target auras), placed to the left of the minimap.
-- Everything is event driven and flushed at 4 Hz by a single driver frame that
-- puts itself to sleep as soon as nothing is counting down.
--
-- Sections:
--   1. Upvalues and constants
--   2. Blizzard aura hider
--   3. Icon box factory
--   4. Group creation and layout
--   5. Aura data refresh
--   6. Timer text
--   7. Module: groups, driver, config hooks
-- ---------------------------------------------------------------------------

local J = JunkieUI

-- ---------------------------------------------------------------------------
-- 1. Upvalues and constants
-- ---------------------------------------------------------------------------
local CreateFrame          = CreateFrame
local UIParent             = UIParent
local GameTooltip          = GameTooltip
local UnitBuff             = UnitBuff
local UnitDebuff           = UnitDebuff
local GetTime              = GetTime
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemTexture = GetInventoryItemTexture
local InCombatLockdown     = InCombatLockdown
local CancelUnitBuff       = CancelUnitBuff
local CancelItemTempEnchantment = CancelItemTempEnchantment
local _G                   = _G
local pairs                = pairs
local format               = string.format
local floor, ceil, max     = math.floor, math.ceil, math.max

local MAX_BUFFS, MAX_DEBUFFS = 32, 16
local PER_ROW = 10
local GAP     = 4
local ROW_GAP = 14   -- extra room for the timer text under each row
local TICK    = 0.25

local BLIZZ_FRAMES = { "BuffFrame", "TemporaryEnchantFrame", "ConsolidatedBuffs" }

local PREVIEW_BACKDROP = {
  bgFile   = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  edgeSize = 1,
}

-- All module state lives here; nothing leaks into the global namespace.
local state = {
  hider    = nil,
  buffs    = nil,
  debuffs  = nil,
  groups   = nil,
  dirty    = true,
  preview  = false,
  previews = {},
}

-- ---------------------------------------------------------------------------
-- 2. Blizzard aura hider
-- ---------------------------------------------------------------------------
local function HideBlizzardAuras()
  local hider = state.hider
  if not hider then
    hider = CreateFrame("Frame", "JunkieAuraHider", UIParent)
    hider:Hide()
    state.hider = hider
  end
  for i = 1, #BLIZZ_FRAMES do
    local f = _G[BLIZZ_FRAMES[i]]
    if f and f:GetParent() ~= hider then
      f:UnregisterAllEvents()
      f:Hide()
      f:SetParent(hider)
    end
  end
end

-- ---------------------------------------------------------------------------
-- 3. Icon box factory
-- ---------------------------------------------------------------------------
local function AuraTooltip(self)
  if not self.JUI_auraIndex then return end
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
  if self.JUI_enchantSlot then
    GameTooltip:SetInventoryItem("player", self.JUI_enchantSlot)
  elseif self.JUI_auraFilter == "HELPFUL" then
    GameTooltip:SetUnitBuff("player", self.JUI_auraIndex)
  else
    GameTooltip:SetUnitDebuff("player", self.JUI_auraIndex)
  end
  GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

local function AuraClick(self)
  if InCombatLockdown and InCombatLockdown() then return end
  if self.JUI_enchantSlot then
    if CancelItemTempEnchantment then
      CancelItemTempEnchantment(self.JUI_enchantSlot == 16 and 1 or 2)
    end
  elseif self.JUI_auraFilter == "HELPFUL" and self.JUI_auraIndex and CancelUnitBuff then
    CancelUnitBuff("player", self.JUI_auraIndex)
  end
end

local function CreateAuraButton(parent, kind)
  local b = CreateFrame("Button", nil, parent)
  J:SkinUnit(b)

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon = icon

  if kind == "debuff" then
    b.jborder:SetBackdropBorderColor(0.7, 0.15, 0.15, 1)
  end

  b.count = J:Text(b, 11, "RIGHT")
  b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  b.time = J:Text(b, 11, "CENTER")
  b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)

  b:RegisterForClicks("RightButtonUp")
  b:SetScript("OnEnter", AuraTooltip)
  b:SetScript("OnLeave", HideTooltip)
  b:SetScript("OnClick", AuraClick)
  b:Hide()
  return b
end

-- ---------------------------------------------------------------------------
-- 4. Group creation and layout
-- ---------------------------------------------------------------------------
local function CreateGroup(name, count, kind)
  local holder = CreateFrame("Frame", name, UIParent)
  holder:SetSize(1, 1)
  local g = { holder = holder, buttons = {}, kind = kind, used = 0 }
  for i = 1, count do
    g.buttons[i] = CreateAuraButton(holder, kind)
  end
  return g
end

local function SetRows(g, used)
  local rows = max(1, ceil(max(used, 1) / PER_ROW))
  local claimed = rows
  if g.kind == "buff" then
    -- The buff block reserves three rows so the debuffs keep their normal
    -- starting height, and from three buff rows and up it always keeps one
    -- empty row as a separator between the two blocks.
    claimed = rows <= 2 and 3 or (rows + 1)
  end
  if g.rows == rows and g.claimed == claimed then return end
  g.rows, g.claimed = rows, claimed
  g.holder:SetHeight(claimed * (g.size + ROW_GAP))
end

local function LayoutGroup(g, size)
  local buttons = g.buttons
  for i = 1, #buttons do
    local b = buttons[i]
    local col = (i - 1) % PER_ROW
    local row = floor((i - 1) / PER_ROW)
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", g.holder, "TOPRIGHT",
      -col * (size + GAP), -row * (size + ROW_GAP))
  end
  g.size = size
  g.holder:SetWidth(PER_ROW * (size + GAP))
  g.rows, g.claimed = nil, nil
  SetRows(g, g.used or 0)
end

-- ---------------------------------------------------------------------------
-- 5. Aura data refresh
-- ---------------------------------------------------------------------------
local function Fill(b, icon, count, expires)
  if b.JUI_shownIcon ~= icon then
    b.icon:SetTexture(icon)
    b.JUI_shownIcon = icon
  end
  local c = (count and count > 1) and count or ""
  if b.JUI_shownCount ~= c then
    b.count:SetText(c)
    b.JUI_shownCount = c
  end
  b.JUI_expires = expires
  if not b:IsShown() then b:Show() end
end

local function ClearButton(b)
  b.JUI_auraIndex, b.JUI_enchantSlot = nil, nil
  b.JUI_expires = nil
  if b.JUI_shownTime ~= "" then
    b.time:SetText("")
    b.JUI_shownTime = ""
  end
  b:Hide()
end

-- Temporary weapon enchants occupy the first buff slots so they keep a stable
-- spot. Returns the number of slots consumed.
local function FillEnchants(g)
  if not GetWeaponEnchantInfo then return 0 end
  local has1, exp1, _, has2, exp2 = GetWeaponEnchantInfo()
  local shown = 0
  if has1 then
    shown = shown + 1
    local b = g.buttons[shown]
    if b then
      b.JUI_enchantSlot, b.JUI_auraIndex, b.JUI_auraFilter = 16, shown, "HELPFUL"
      Fill(b, GetInventoryItemTexture("player", 16), nil,
        exp1 and (GetTime() + exp1 / 1000) or nil)
    end
  end
  if has2 then
    shown = shown + 1
    local b = g.buttons[shown]
    if b then
      b.JUI_enchantSlot, b.JUI_auraIndex, b.JUI_auraFilter = 17, shown, "HELPFUL"
      Fill(b, GetInventoryItemTexture("player", 17), nil,
        exp2 and (GetTime() + exp2 / 1000) or nil)
    end
  end
  return shown
end

-- Shared refresh for both groups: query, pack into consecutive buttons and
-- hide the tail. `query` is UnitBuff or UnitDebuff (both are Blizzard's
-- C-filtered HELPFUL/HARMFUL lists), `filter` the tooltip hint. The list has
-- no gaps, so the scan stops at the first empty slot instead of probing all 40.
local function Refresh(g, query, filter, maxButtons, shown)
  for i = 1, 40 do
    if shown >= maxButtons then break end
    local name, _, icon, count, _, _, expires = query("player", i)
    if not name then break end
    local b = g.buttons[shown + 1]
    if not b then break end
    shown = shown + 1
    b.JUI_enchantSlot = nil
    b.JUI_auraIndex, b.JUI_auraFilter = i, filter
    Fill(b, icon, count, expires)
  end

  if shown > maxButtons then shown = maxButtons end

  for i = shown + 1, maxButtons do
    local b = g.buttons[i]
    if b and b:IsShown() then ClearButton(b) end
  end

  g.used = shown
  SetRows(g, shown)
  return shown
end

-- ---------------------------------------------------------------------------
-- 6. Timer text
-- ---------------------------------------------------------------------------
local auraSecondText, auraMinuteText = {}, {}
local function TimerText(b, now)
  if not b then return false end
  local expires = b.JUI_expires
  if expires and expires > 0 then
    local r = expires - now
    if r > 0 then
      local value = r > 60 and floor(r / 60) or floor(r)
      local cache = r > 60 and auraMinuteText or auraSecondText
      local txt = cache[value]
      if not txt then
        txt = tostring(value) .. (r > 60 and "m" or "")
        cache[value] = txt
      end
      if b.JUI_shownTime ~= txt then
        b.time:SetText(txt)
        b.JUI_shownTime = txt
      end
      return true
    end
  end
  if b.JUI_shownTime ~= "" then
    b.time:SetText("")
    b.JUI_shownTime = ""
  end
  return false
end

-- ---------------------------------------------------------------------------
-- 7. Module
-- ---------------------------------------------------------------------------
local function BuffSize()   return J.db.buffSize or 30 end
local function DebuffSize() return J.db.playerDebuffSize or 34 end

local function MakePreview(parent, n, size, kind)
  local list = state.previews[kind]
  if not list then
    list = {}
    state.previews[kind] = list
  end
  for i = 1, n do
    local p = list[i]
    if not p then
      p = CreateFrame("Frame", nil, UIParent)
      p:SetFrameStrata("DIALOG")
      p:SetBackdrop(PREVIEW_BACKDROP)
      p:SetBackdropColor(0.09, 0.09, 0.09, 0.8)
      p:SetBackdropBorderColor(0.871, 0.447, 0.188, 1)
      list[i] = p
    end
    p:SetSize(size, size)
    p:ClearAllPoints()
    p:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(i - 1) * (size + GAP), 0)
    p:Show()
  end
  for i = n + 1, #list do list[i]:Hide() end
end

J:AddModule(function()
  HideBlizzardAuras()

  local buffs   = CreateGroup("JunkieBuffs", MAX_BUFFS, "buff")
  local debuffs = CreateGroup("JunkieDebuffs", MAX_DEBUFFS, "debuff")
  state.buffs, state.debuffs = buffs, debuffs
  state.groups = { buffs, debuffs }

  -- Anchored to the minimap's top left corner: the block follows the map when
  -- it is resized and slides down together with it when the XP bar is up.
  -- The debuff block can instead be docked above the player unit frame; it
  -- keeps the exact same layout and simply grows upwards from there.
  local function PlaceDebuffs()
    local holder = debuffs.holder
    holder:ClearAllPoints()
    local anchor = _G["JunkiePlayerFrame"]
    if J.db.debuffsOnFrame and anchor then
      -- Docked above the player frame; raised 190 px above the default gap.
      holder:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 196)
    else
      holder:SetPoint("TOPRIGHT", buffs.holder, "BOTTOMRIGHT", 0, -6)
    end
  end

  buffs.holder:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -6, 0)
  PlaceDebuffs()

  LayoutGroup(buffs, BuffSize())
  LayoutGroup(debuffs, DebuffSize())


  -- Driver: aura events only raise a flag, the work happens 4x/sec and the
  -- frame stops updating completely as soon as nothing has a timer left.
  local driver = CreateFrame("Frame")
  driver:RegisterEvent("UNIT_AURA")
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_AURA" then
      if unit ~= "player" then return end
    else
      HideBlizzardAuras()
    end
    state.dirty = true
    if not self:IsShown() then self:Show() end
  end)

  driver:SetScript("OnUpdate", function(self, e)
    local t = (self.JUI_elapsed or 0) + e
    if t < TICK then
      self.JUI_elapsed = t
      return
    end
    self.JUI_elapsed = 0

    if state.dirty then
      state.dirty = false
      Refresh(buffs, UnitBuff, "HELPFUL", MAX_BUFFS, FillEnchants(buffs))
      Refresh(debuffs, UnitDebuff, "HARMFUL", MAX_DEBUFFS, 0)
    end

    local now = GetTime()
    local ticking = false
    local groups = state.groups
    for gi = 1, 2 do
      local g = groups[gi]
      local buttons = g.buttons
      for i = 1, (g.used or 0) do
        if TimerText(buttons[i], now) then ticking = true end
      end
    end

    -- Nothing left to count down: sleep until the next aura event.
    if not ticking and not state.dirty then self:Hide() end
  end)

  -- Config hooks -------------------------------------------------------------
  function J:UpdatePlayerAuraSizes()
    LayoutGroup(buffs, BuffSize())
    LayoutGroup(debuffs, DebuffSize())
    if state.preview then J:SetPlayerAuraPreview(true) end
  end

  -- Toggle: minimap column vs. docked above the player unit frame.
  function J:UpdateDebuffPlacement()
    PlaceDebuffs()
  end


  function J:SetPlayerAuraPreview(on)
    state.preview = on and true or false
    J.auraPreviewOn = state.preview
    if state.preview then
      MakePreview(buffs.holder, 6, BuffSize(), "buff")
      MakePreview(debuffs.holder, 4, DebuffSize(), "debuff")
    else
      for _, list in pairs(state.previews) do
        for i = 1, #list do list[i]:Hide() end
      end
    end
  end
end)
