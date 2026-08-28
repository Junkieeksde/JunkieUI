-- ============================================================================
-- JunkieUI - Boss frames (boss1 .. boss5)
--
-- Target frame styling, stripped to the bare minimum:
--   * one health bar + health text, no power bar
--   * name on the left (10 characters max), health on the right
--   * raid target mark, nothing else - no buffs, debuffs or castbar
--
-- Cost profile
--   Frames are created once at login and never rebuilt. Visibility is handled
--   by RegisterUnitWatch (secure, C-side), so there is no OnUpdate and no
--   polling anywhere in this file. Outside an encounter the module is
--   completely silent: the boss units do not exist, so none of the registered
--   unit events carry a boss token and every handler returns on the first
--   table lookup.
--
-- Globals produced: JunkieBossFrame1 .. JunkieBossFrame5, JunkieBossMover
--
-- Sections
--   1. Upvalues and constants
--   2. Module state
--   3. Value updaters
--   4. Frame construction
--   5. Group placement + mover
--   6. Event wiring
-- ============================================================================

local J = JunkieUI

-- ---------------------------------------------------------------------------
-- 1. Upvalues and constants
-- ---------------------------------------------------------------------------

local CreateFrame        = CreateFrame
local UnitExists         = UnitExists
local UnitHealth         = UnitHealth
local UnitHealthMax      = UnitHealthMax
local UnitName           = UnitName
local UnitGUID           = UnitGUID
local UnitIsPlayer       = UnitIsPlayer
local UnitClass          = UnitClass
local UnitSelectionColor = UnitSelectionColor
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local RegisterUnitWatch  = RegisterUnitWatch
local InCombatLockdown   = InCombatLockdown
local floor              = math.floor
local strlen             = string.len
local strsub             = string.sub
local tonumber           = tonumber
local pairs              = pairs

local COUNT   = 5                 -- boss1 .. boss5
local W       = floor(250 * 0.7)  -- 30% narrower than the target frame: 175
local H       = 40
local GAP     = 5                 -- vertical spacing inside the group
local NAME_MAX = 10

local GROUP_H = COUNT * H + (COUNT - 1) * GAP

-- Unit events only matter when arg1 is one of these tokens.
local BOSS_UNIT = {}
for i = 1, COUNT do BOSS_UNIT["boss" .. i] = i end

local UNIT_EVENTS = {
  "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE",
}
local BROADCAST_EVENTS = {
  "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "RAID_TARGET_UPDATE",
  "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}

-- ---------------------------------------------------------------------------
-- 2. Module state
-- ---------------------------------------------------------------------------

local frames = {}
local container, mover
local placePending = false

-- ---------------------------------------------------------------------------
-- 3. Value updaters
-- ---------------------------------------------------------------------------
-- Every writer below is change-cached: boss health events fire continuously in
-- an encounter and re-issuing SetText / SetStatusBarColor with a value the
-- widget already holds is pure C churn.

local function UpdateHealth(f)
  local unit = f.unit
  if not UnitExists(unit) then return end
  local cur, max = UnitHealth(unit), UnitHealthMax(unit)
  if max == 0 then max = 1 end
  f.health:SetMinMaxValues(0, max)
  f.health:SetValue(cur)

  -- Colour depends on the unit, not on its health, so it is recomputed only
  -- when the GUID behind the token changes.
  local guid = UnitGUID(unit)
  if guid ~= f.JUI_colorGUID then
    f.JUI_colorGUID = guid
    local r, g, b
    local _, class = UnitClass(unit)
    local c = UnitIsPlayer(unit) and class and RAID_CLASS_COLORS[class]
    if c then
      r, g, b = c.r * 0.9, c.g * 0.9, c.b * 0.9
    else
      r, g, b = UnitSelectionColor(unit)
      r, g, b = r * 0.8, g * 0.8, b * 0.8
    end
    if f.JUI_hr ~= r or f.JUI_hg ~= g or f.JUI_hb ~= b then
      f.JUI_hr, f.JUI_hg, f.JUI_hb = r, g, b
      f.health:SetStatusBarColor(r, g, b)
    end
  end

  local pct = floor(cur / max * 100 + 0.5)
  if f.JUI_shownHP ~= cur or f.JUI_shownPct ~= pct then
    f.JUI_shownHP, f.JUI_shownPct = cur, pct
    f.right:SetText(J:Short(cur) .. " - " .. pct .. "%")
  end
end

local function UpdateName(f)
  local name = UnitName(f.unit) or ""
  if strlen(name) > NAME_MAX then name = strsub(name, 1, NAME_MAX) end
  if f.JUI_shownName == name then return end
  f.JUI_shownName = name
  f.left:SetText(name)
end

local function UpdateMark(f)
  local index = (UnitExists(f.unit) and GetRaidTargetIndex(f.unit)) or false
  if f.JUI_markIndex == index then return end
  f.JUI_markIndex = index
  if index then
    SetRaidTargetIconTexture(f.mark, index)
    f.mark:Show()
  else
    f.mark:Hide()
  end
end

local function UpdateAll(f)
  UpdateName(f)
  UpdateHealth(f)
  UpdateMark(f)
end

-- ---------------------------------------------------------------------------
-- 4. Frame construction
-- ---------------------------------------------------------------------------

local function BossTooltipEnter(self)
  if not UnitExists(self.unit) then return end
  GameTooltip:SetOwner(self, "ANCHOR_NONE")
  if GameTooltip_SetDefaultAnchor then
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
  else
    GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 4)
  end
  GameTooltip:SetUnit(self.unit)
  GameTooltip:Show()
end

local function BossTooltipLeave() GameTooltip:Hide() end

local function CreateBossFrame(index, parent)
  local unit = "boss" .. index
  local f = CreateFrame("Button", "JunkieBossFrame" .. index, parent,
    "SecureUnitButtonTemplate")
  f:SetSize(W, H)
  f.unit = unit
  J:SkinUnit(f)

  f:SetAttribute("unit", unit)
  f:SetAttribute("*type1", "target")
  f:RegisterForClicks("AnyUp")
  f:EnableMouse(true)
  f:SetScript("OnEnter", BossTooltipEnter)
  f:SetScript("OnLeave", BossTooltipLeave)

  -- Secure, C-side visibility: the frame exists only while its boss unit does.
  RegisterUnitWatch(f)

  -- Health bar: registered with the media module so it follows the same
  -- texture setting as every other bar in the UI.
  local health = CreateFrame("StatusBar", nil, f)
  health:SetPoint("TOPLEFT", f, 1, -1)
  health:SetPoint("BOTTOMRIGHT", f, -1, 1)
  health:SetMinMaxValues(0, 1)
  health:SetValue(1)
  J:RegisterBar(health)
  f.health = health

  f.left = J:Text(health, 11, "LEFT")
  f.left:SetPoint("LEFT", health, "LEFT", 4, 0)

  f.right = J:Text(health, 11, "RIGHT")
  f.right:SetPoint("RIGHT", health, "RIGHT", -4, 0)

  -- Raid target mark, centred exactly like the target frame's.
  local markHolder = CreateFrame("Frame", nil, f)
  markHolder:SetAllPoints(f)
  markHolder:SetFrameStrata("HIGH")
  markHolder:SetFrameLevel(f:GetFrameLevel() + 10)
  local mark = markHolder:CreateTexture(nil, "OVERLAY")
  mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  mark:SetSize(18, 18)
  mark:SetPoint("CENTER", markHolder, "CENTER", 0, 0)
  mark:Hide()
  f.mark = mark

  return f
end

-- ---------------------------------------------------------------------------
-- 5. Group placement + mover
-- ---------------------------------------------------------------------------
-- The five frames hang off one invisible container so they always keep their
-- exact spacing and alignment. Only the container ever moves, which is also
-- why the drag handle is a single group-sized plate: there is no way to knock
-- one boss frame out of line.

local function PlaceGroup()
  if InCombatLockdown and InCombatLockdown() then
    placePending = true
    return
  end
  placePending = false
  container:ClearAllPoints()
  if J.db.bossMoved then
    container:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
      tonumber(J.db.bossX) or 0, tonumber(J.db.bossY) or 0)
  else
    -- Default: right hand side of the screen, vertically centred.
    container:SetPoint("RIGHT", UIParent, "RIGHT", -40, 80)
  end
end

local function SyncMover()
  mover:ClearAllPoints()
  mover:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
end

-- ---------------------------------------------------------------------------
-- 6. Module
-- ---------------------------------------------------------------------------

J:AddModule(function()
  container = CreateFrame("Frame", "JunkieBossFrames", UIParent)
  container:SetSize(W, GROUP_H)

  for i = 1, COUNT do
    local f = CreateBossFrame(i, container)
    f:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (H + GAP))
    frames[i] = f
  end

  -- Drag handle: exact copies of the real frames, same size, same spacing,
  -- same position. Dragging any part of it moves the whole group.
  mover = J:CreateMover("JunkieBossMover", W, GROUP_H, "")
  for i = 1, COUNT do
    local ghost = CreateFrame("Frame", nil, mover)
    ghost:SetSize(W, H)
    ghost:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, -(i - 1) * (H + GAP))
    J:Plate(ghost, 0.09, 0.09, 0.09, 0.95)
    local fs = J:Text(ghost, 11, "CENTER")
    fs:SetPoint("CENTER")
    fs:SetText("|cffde7230Boss " .. i .. "|r")
  end
  if mover.label then mover.label:SetText("") end

  mover:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left, bottom = J:MoverPos(self)
    J.db.bossX = floor(left + 0.5)
    J.db.bossY = floor(bottom + 0.5)
    J.db.bossMoved = true
    PlaceGroup()
    SyncMover()
  end)

  function J:SetBossUnlocked(on)
    J.db.bossUnlocked = on and true or false
    if J.db.bossUnlocked then
      SyncMover()
      mover:Show()
    else
      mover:Hide()
    end
  end

  function J:ResetBossFrames()
    J.db.bossMoved = false
    PlaceGroup()
    SyncMover()
  end

  PlaceGroup()
  J:SetBossUnlocked(J.db.bossUnlocked)

  -- Event wiring -----------------------------------------------------------
  -- One frame, one handler. Unit events are filtered on arg1 before anything
  -- else happens, so raid-wide health traffic costs a single table lookup.
  local dispatcher = CreateFrame("Frame")
  dispatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
      local i = BOSS_UNIT[arg1]
      if i then UpdateHealth(frames[i]) end
    elseif event == "UNIT_NAME_UPDATE" then
      local i = BOSS_UNIT[arg1]
      if i then UpdateName(frames[i]) end
    elseif event == "RAID_TARGET_UPDATE" then
      for i = 1, COUNT do UpdateMark(frames[i]) end
    elseif event == "PLAYER_REGEN_ENABLED" then
      if placePending then PlaceGroup() end
      if J.db.bossUnlocked then SyncMover(); mover:Show() end
    else
      -- Encounter start / stop and zoning: refresh everything once.
      for i = 1, COUNT do UpdateAll(frames[i]) end
    end
  end)
  for _, e in pairs(UNIT_EVENTS) do dispatcher:RegisterEvent(e) end
  for _, e in pairs(BROADCAST_EVENTS) do dispatcher:RegisterEvent(e) end
  -- Not present on every 3.3.5 core.
  pcall(dispatcher.RegisterEvent, dispatcher, "UNIT_TARGETABLE_CHANGED")

  for i = 1, COUNT do UpdateAll(frames[i]) end
end)
