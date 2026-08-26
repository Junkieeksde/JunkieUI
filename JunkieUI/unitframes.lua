-- ============================================================================
-- JunkieUI - Unit frames (player / target / target-of-target / pet)
--
-- Layout: two flat 250x40 bars mirrored around screen center, ToT hanging
-- under the target frame and the pet bar under the player frame.
--
-- Everything in this file is local. The only globals produced are the frame
-- names other modules look up through _G:
--   JunkiePlayerFrame, JunkieTargetFrame, JunkieToTFrame, JunkiePetFrame,
--   JunkieUnitHider
--
-- Sections
--   1. Upvalues and constants
--   2. Module state
--   3. Shared event dispatcher
--   4. Shared 0.25s ticker
--   5. Value updaters (health / power / name / indicators)
--   6. Unit frame construction
--   7. Aura groups (target buffs and debuffs)
--   8. Timer text helpers
--   9. Module: player / target / ToT + auras
--  10. Module: pet
-- ============================================================================

local J = JunkieUI

-- ---------------------------------------------------------------------------
-- 1. Upvalues and constants
-- ---------------------------------------------------------------------------

local CreateFrame       = CreateFrame
local UnitExists        = UnitExists
local UnitHealth        = UnitHealth
local UnitHealthMax     = UnitHealthMax
local UnitPower         = UnitPower
local UnitPowerMax      = UnitPowerMax
local UnitPowerType     = UnitPowerType
local UnitClass         = UnitClass
local UnitIsPlayer      = UnitIsPlayer
local UnitName          = UnitName
local UnitBuff          = UnitBuff
local UnitAura          = UnitAura
local UnitClassification    = UnitClassification
local UnitSelectionColor    = UnitSelectionColor
local UnitIsPartyLeader     = UnitIsPartyLeader
local UnitAffectingCombat   = UnitAffectingCombat
local GetRaidTargetIndex    = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local RegisterUnitWatch     = RegisterUnitWatch
local InCombatLockdown  = InCombatLockdown
local GetTime           = GetTime
local floor             = math.floor
local ceil              = math.ceil
local strlen            = string.len
local strsub            = string.sub

local tonumber          = tonumber
local pairs             = pairs

local W, H = 250, 40

local TICK  = 0.25   -- shared driver interval
local NEXT_ROW = 8   -- default icons per wrapped aura row

-- Events that carry a unit token in arg1 and therefore only concern the frame
-- that owns that unit.
local UNIT_EVENT = {
  UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_MANA = true, UNIT_ENERGY = true,
  UNIT_RAGE = true, UNIT_RUNIC_POWER = true, UNIT_DISPLAYPOWER = true,
  UNIT_NAME_UPDATE = true, UNIT_TARGET = true, UNIT_CLASSIFICATION_CHANGED = true,
}
local POWER_EVENT = {
  UNIT_MANA = true, UNIT_ENERGY = true, UNIT_RAGE = true,
  UNIT_RUNIC_POWER = true, UNIT_DISPLAYPOWER = true,
}
local INDICATOR_EVENT = {
  RAID_TARGET_UPDATE = true, PARTY_LEADER_CHANGED = true,
  PARTY_MEMBERS_CHANGED = true, RAID_ROSTER_UPDATE = true,
}

-- Every event the unit frames need, registered exactly once on the dispatcher
-- below instead of once per frame.
local FRAME_EVENTS = {
  "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MANA", "UNIT_ENERGY", "UNIT_RAGE",
  "UNIT_RUNIC_POWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_TARGET",
  "UNIT_CLASSIFICATION_CHANGED", "RAID_TARGET_UPDATE", "PARTY_LEADER_CHANGED",
  "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
  "PLAYER_ENTERING_WORLD",
}

-- ---------------------------------------------------------------------------
-- 2. Module state
-- ---------------------------------------------------------------------------

local state = {
  frames    = {},   -- every unit frame we created, in creation order
  byUnit    = {},   -- unit token -> array of frames watching it
  hooks     = {},   -- event -> array of extra callbacks
  posPending = false,
  petPending = false,
  petRetries = 0,
}

-- ---------------------------------------------------------------------------
-- 3. Shared event dispatcher
-- ---------------------------------------------------------------------------

local dispatcher = CreateFrame("Frame")

local UpdateHealthBar, UpdatePower, UpdateName, UpdateIndicators

local function DispatchToFrame(f, event)
  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
    UpdateHealthBar(f)
  elseif POWER_EVENT[event] then
    UpdatePower(f)
  elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_CLASSIFICATION_CHANGED" then
    UpdateName(f)
  elseif INDICATOR_EVENT[event] then
    UpdateIndicators(f)
  else
    UpdateName(f)
    UpdateHealthBar(f)
    UpdatePower(f)
    UpdateIndicators(f)
  end
end

-- Only the events in FRAME_EVENTS drive the unit frames; everything else that
-- shares this dispatcher (aura flags, combat icon, pet driver) runs through
-- hooks only.
local FRAME_EVENT_SET = {}
for i = 1, #FRAME_EVENTS do FRAME_EVENT_SET[FRAME_EVENTS[i]] = true end

dispatcher:SetScript("OnEvent", function(_, event, arg1)
  if FRAME_EVENT_SET[event] then
    if UNIT_EVENT[event] then
      -- Unit events fire for every unit in the group; only the owning frames
      -- are touched instead of waking all four handlers on every health tick.
      local list = state.byUnit[arg1]
      if list then
        for i = 1, #list do DispatchToFrame(list[i], event) end
      end

      -- UNIT_TARGET identifies the unit whose target changed. The dependent
      -- target-of-target frame therefore has to be refreshed explicitly;
      -- routing only by arg1 updates the target frame itself and leaves ToT
      -- stale until PLAYER_TARGET_CHANGED.
      if event == "UNIT_TARGET" and arg1 == "target" then
        local dependents = state.byUnit.targettarget
        if dependents then
          for i = 1, #dependents do DispatchToFrame(dependents[i], event) end
        end
      end
    else
      local list = state.frames
      for i = 1, #list do DispatchToFrame(list[i], event) end
    end
  end

  local hooks = state.hooks[event]
  if hooks then
    for i = 1, #hooks do hooks[i](event, arg1) end
  end
end)


for i = 1, #FRAME_EVENTS do dispatcher:RegisterEvent(FRAME_EVENTS[i]) end

-- Extra listeners (combat icon, regen flush, pet driver) share the same frame.
local function AddHook(event, fn)
  local hooks = state.hooks[event]
  if not hooks then
    hooks = {}
    state.hooks[event] = hooks
    dispatcher:RegisterEvent(event)
  end
  hooks[#hooks + 1] = fn
end

local function RegisterFrame(f)
  state.frames[#state.frames + 1] = f
  local list = state.byUnit[f.unit]
  if not list then
    list = {}
    state.byUnit[f.unit] = list
  end
  list[#list + 1] = f
end

-- ---------------------------------------------------------------------------
-- 4. Shared 0.25s ticker
-- ---------------------------------------------------------------------------
-- The only recurring loop in this module. It polls target-of-target while a
-- target exists and drives the short pet retry burst; everything else (unit
-- values, target changes, auras) is event driven. It hides itself the moment
-- neither of those two jobs has work left.

local ticker = CreateFrame("Frame")
ticker:Hide()

-- Waking an already running ticker must not reset its accumulator; frequent
-- aura events should not starve countdown text or the pet retry burst.
local function Wake()
  if not ticker:IsShown() then
    ticker.JUI_elapsed = TICK   -- run the body on the very next frame
    ticker:Show()
  end
end

-- ---------------------------------------------------------------------------
-- 5. Value updaters
-- ---------------------------------------------------------------------------

function UpdateHealthBar(f)
  local unit = f.unit
  if not UnitExists(unit) then return end
  local cur, max = UnitHealth(unit), UnitHealthMax(unit)
  if max == 0 then max = 1 end
  f.health:SetMinMaxValues(0, max)
  f.health:SetValue(cur)

  -- Colour and text are only pushed when they actually changed. UNIT_HEALTH
  -- can fire dozens of times per second on a target, and rebuilding the
  -- string every tick was pure garbage for the collector.
  -- The colour itself is also cached: UnitClass/UnitIsPlayer/UnitSelectionColor
  -- were run on every single health tick even though the answer only changes
  -- when the unit changes (or, rarely, when it is tapped/changes faction), so
  -- it is recomputed on a unit swap and at most twice a second otherwise.
  local now = GetTime()
  local guid = UnitGUID(unit)
  local r, g, b = f.JUI_hr, f.JUI_hg, f.JUI_hb
  if r == nil or guid ~= f.JUI_colorGUID or now - (f.JUI_colorAt or 0) >= 0.5 then
    local _, class = UnitClass(unit)
    -- The pet bar borrows the player's class colour so it reads as part of the
    -- player block instead of the usual green "friendly npc" bar.
    if f.JUI_style == "pet" then _, class = UnitClass("player") end
    local c = RAID_CLASS_COLORS[class]
    if (UnitIsPlayer(unit) or f.JUI_style == "pet") and c then
      r, g, b = c.r * 0.9, c.g * 0.9, c.b * 0.9
    else
      r, g, b = UnitSelectionColor(unit)
      r, g, b = r * 0.8, g * 0.8, b * 0.8
    end
    f.JUI_colorGUID, f.JUI_colorAt = guid, now
    if f.JUI_hr ~= r or f.JUI_hg ~= g or f.JUI_hb ~= b then
      f.JUI_hr, f.JUI_hg, f.JUI_hb = r, g, b
      f.health:SetStatusBarColor(r, g, b)
    end
  end


  local style = f.JUI_style
  if style == "player" or style == "target" or style == "focus" then
    local pct = floor(cur / max * 100 + 0.5)
    if f.JUI_shownHP ~= cur or f.JUI_shownPct ~= pct then
      f.JUI_shownHP, f.JUI_shownPct = cur, pct
      if style == "target" then
        f.left:SetText(pct .. "% - " .. J:Short(cur))
      else
        -- player and focus share the same layout: name left, health right.
        f.right:SetText(J:Short(cur) .. " - " .. pct .. "%")
      end
    end
  end

end

function UpdatePower(f)
  local bar = f.power
  if not bar then return end
  local unit = f.unit
  local cur, max = UnitPower(unit), UnitPowerMax(unit)
  if max == 0 then max = 1 end
  -- Energy/focus tick several times a second; skip the setters when nothing
  -- actually moved.
  if f.JUI_pmax ~= max then
    f.JUI_pmax = max
    bar:SetMinMaxValues(0, max)
  end
  if f.JUI_pcur ~= cur then
    f.JUI_pcur = cur
    bar:SetValue(cur)
  end
  local pt = UnitPowerType(unit)
  if f.JUI_ptype ~= pt then
    local col = PowerBarColor[pt]
    if col then
      f.JUI_ptype = pt
      bar:SetStatusBarColor(col.r, col.g, col.b)
    end
  end
end

-- Elite / rare marker appended to the target name: gold E, silver R
local function ClassificationTag(unit)
  local c = UnitClassification(unit)
  if c == "worldboss" then
    return " |cffffd100B|r"
  elseif c == "elite" then
    return " |cffffd100E|r"
  elseif c == "rare" or c == "rareelite" then
    return " |cffc0c0c0R|r"
  end
  return ""
end

function UpdateName(f)
  local unit = f.unit
  local style = f.JUI_style
  local name = UnitName(unit) or ""
  if (style == "target" or style == "focus") and strlen(name) > 15 then
    name = strsub(name, 1, 15)
  elseif (style == "tot" or style == "pet") and strlen(name) > 10 then
    name = strsub(name, 1, 10)
  end
  if style == "target" or style == "focus" then
    name = name .. ClassificationTag(unit)
  end
  -- Same caching rationale as the health text above.
  if f.JUI_shownName == name then return end
  f.JUI_shownName = name
  if style == "player" or style == "focus" then
    f.left:SetText(name)
  elseif style == "target" then
    f.right:SetText(name)
  else
    f.center:SetText(name)
  end
end


-- Raid mark (top center) + leader crown (top left)
-- Both states are change-cached: target-of-target polls this four times a
-- second, and re-issuing SetRaidTargetIconTexture/Show/Hide with the value the
-- texture already has is pure C churn for no visual difference.
function UpdateIndicators(f)
  local unit = f.unit
  local exists = UnitExists(unit)
  if f.mark then
    local index = (exists and GetRaidTargetIndex(unit)) or false
    if f.JUI_markIndex ~= index then
      f.JUI_markIndex = index
      if index then
        SetRaidTargetIconTexture(f.mark, index)
        f.mark:Show()
      else
        f.mark:Hide()
      end
    end
  end
  if f.leader then
    local isLeader = (exists and UnitIsPartyLeader(unit)) and true or false
    if f.JUI_leaderShown ~= isLeader then
      f.JUI_leaderShown = isLeader
      if isLeader then f.leader:Show() else f.leader:Hide() end
    end
  end
end

local function UpdateAll(f)
  UpdateName(f)
  UpdateHealthBar(f)
  UpdateIndicators(f)
end

-- ---------------------------------------------------------------------------
-- 6. Unit frame construction
-- ---------------------------------------------------------------------------

-- Toggle the power bar on/off for this frame (skipped in combat: protected).
-- Shared by every frame instead of one closure per frame.
local function SetPowerShown(self, show)
  if InCombatLockdown and InCombatLockdown() then
    self.JUI_powerPending = show
    return
  end
  self.JUI_powerPending = nil
  if show then
    self.power:Show()
    self.separator:Show()
    self.health:SetPoint("BOTTOMRIGHT", self, -1, 5)
  else
    self.power:Hide()
    self.separator:Hide()
    self.health:SetPoint("BOTTOMRIGHT", self, -1, 1)
  end
end

-- A dropdown opened by addon Lua becomes tainted before its protected
-- "Set Focus" entry runs on this 3.3.5 client. Forward right-click through
-- SecureActionButton's protected "click" action to Blizzard's own unit button
-- instead. Blizzard then opens and executes its menu without an addon callback
-- anywhere in the protected path.
local STOCK_UNIT_BUTTON = {
  player = "PlayerFrame",
  target = "TargetFrame",
  targettarget = "TargetFrameToT",
  focus = "FocusFrame",
  pet = "PetFrame",
}

-- Mouseover tooltip (target and focus frames only). Pure event scripts: they
-- run on enter/leave, never per frame, so they cost nothing while idle. The
-- anchor goes through GameTooltip_SetDefaultAnchor, which tooltip.lua already
-- hooks, so the tooltip lands wherever the user chose in the settings.
local function UnitTooltipEnter(self)
  local unit = self.unit
  if not unit or not UnitExists(unit) then return end
  GameTooltip:SetOwner(self, "ANCHOR_NONE")
  if GameTooltip_SetDefaultAnchor then
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
  else
    GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 4)
  end
  GameTooltip:SetUnit(unit)
  GameTooltip:Show()
end

local function UnitTooltipLeave() GameTooltip:Hide() end

local function CreateUnitFrame(name, unit, w, h, style)
  local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
  f:SetSize(w, h)
  f.unit = unit
  f.JUI_style = style
  J:SkinUnit(f)

  f:SetAttribute("unit", unit)
  f:SetAttribute("*type1", "target")
  local stockButton = _G[STOCK_UNIT_BUTTON[unit or ""]]
  if stockButton then
    f:SetAttribute("*type2", "click")
    -- Set both forms for compatibility with the client's modified-attribute
    -- resolver. They point to the same secure Blizzard button.
    f:SetAttribute("clickbutton2", stockButton)
    f:SetAttribute("*clickbutton2", stockButton)
  end
  f:RegisterForClicks("AnyUp")

  -- The protected click must finish before addon code touches the dropdown.
  -- Repositioning the already-built list in PostClick is purely cosmetic and
  -- does not enter or modify Blizzard's protected Set Focus execution path.
  f:HookScript("PostClick", function(self, button)
    if button ~= "RightButton" then return end
    local list = _G["DropDownList1"]
    if not list or not list:IsShown() then return end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, 0)
  end)
  RegisterUnitWatch(f)

  if style == "target" or style == "focus" then
    f:SetScript("OnEnter", UnitTooltipEnter)
    f:SetScript("OnLeave", UnitTooltipLeave)
  end



  local health = CreateFrame("StatusBar", nil, f)
  health:SetPoint("TOPLEFT", f, 1, -1)
  health:SetPoint("BOTTOMRIGHT", f, -1, 5)
  J:RegisterBar(health)
  f.health = health

  local power = CreateFrame("StatusBar", nil, f)
  power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -1)
  power:SetPoint("BOTTOMRIGHT", f, -1, 1)
  J:RegisterBar(power)
  f.power = power

  -- 1px divider between health and power
  local sep = f:CreateTexture(nil, "OVERLAY")
  sep:SetTexture("Interface\\Buttons\\WHITE8X8")
  sep:SetVertexColor(0, 0, 0, 1)
  sep:SetHeight(1)
  sep:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, -1)
  sep:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, -1)
  f.separator = sep

  f.SetPowerShown = SetPowerShown

  f.left = J:Text(health, 12, "LEFT")
  f.left:SetPoint("LEFT", health, "LEFT", 5, 0)

  f.right = J:Text(health, 12, "RIGHT")
  f.right:SetPoint("RIGHT", health, "RIGHT", -5, 0)

  f.center = J:Text(health, 12, "CENTER")
  f.center:SetPoint("CENTER", health, 0, 0)

  -- Raid target mark, centered on the frame (same spot as combat indicator)
  local markHolder = CreateFrame("Frame", nil, f)
  markHolder:SetAllPoints(f)
  markHolder:SetFrameStrata("HIGH")
  markHolder:SetFrameLevel(f:GetFrameLevel() + 10)
  local mark = markHolder:CreateTexture(nil, "OVERLAY")
  mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  mark:SetSize(20, 20)
  mark:SetPoint("CENTER", markHolder, "CENTER", 0, 0)
  mark:Hide()
  f.mark = mark

  -- Leader crown: player top left, target top right
  if style == "player" or style == "target" then
    local leader = markHolder:CreateTexture(nil, "OVERLAY")
    leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    leader:SetSize(12, 12)
    if style == "target" then
      leader:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 2, -2)
    else
      leader:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -2, -2)
    end
    leader:Hide()
    f.leader = leader
  end

  RegisterFrame(f)
  return f
end

-- ---------------------------------------------------------------------------
-- 7. Target aura rows
-- ---------------------------------------------------------------------------
-- Target aura row builder. Each group uses its own holder whose left edge is
-- hard-anchored to the target frame, so aura data can never shift the grid.

local function AuraTooltip(self)
  if not self.JUI_auraIndex then return end
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
  GameTooltip:SetUnitAura(self.JUI_auraUnit or "target", self.JUI_auraIndex, self.JUI_auraFilter)
  GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

local function CreateAuraGroup(anchorFrame, count, size, gap, frameGap, dir, firstRow, perRow)
  local PER_ROW = perRow or NEXT_ROW
  local FIRST_ROW = firstRow or PER_ROW
  local rows = 1
  if count > FIRST_ROW then
    rows = 1 + ceil((count - FIRST_ROW) / PER_ROW)
  end
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:SetSize(W, rows * size + (rows - 1) * gap)
  holder:ClearAllPoints()
  if dir == "up" then
    holder:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, frameGap)
  else
    holder:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -frameGap)
  end

  local t = {
    buttons = {},
    holder = holder,
    size = size,
    gap = gap,
    frameGap = frameGap,
    firstRow = FIRST_ROW,
    nextRow = PER_ROW,
    used = 0,
  }
  for i = 1, count do
    local b = CreateFrame("Frame", nil, holder)
    b:SetSize(size, size)
    local col, row
    if i <= FIRST_ROW then
      col, row = i - 1, 0
    else
      col = (i - FIRST_ROW - 1) % PER_ROW
      row = floor((i - FIRST_ROW - 1) / PER_ROW) + 1
    end
    local x = col * (size + gap)
    local y = row * (size + gap)
    if dir == "up" then
      -- buffs: bottom row nearest the frame, additional rows stack upwards
      b:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", x, y)
    else
      -- debuffs: first row directly below, additional rows go further down
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
    end
    J:SkinUnit(b)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon

    -- Cooldown swipe on the icon
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", 1, -1)
    cd:SetPoint("BOTTOMRIGHT", -1, 1)
    cd:SetReverse(true)
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    b.cd = cd

    b.count = J:Text(b, 11, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)

    -- Mouseover tooltip for target buffs / debuffs
    b:EnableMouse(true)
    b:SetScript("OnEnter", AuraTooltip)
    b:SetScript("OnLeave", HideTooltip)
    b:Hide()

    t.buttons[i] = b
  end
  return t
end

local function SetAuraButton(b, icon, count, duration, expires)
  if b.JUI_shownIcon ~= icon then
    b.icon:SetTexture(icon)
    b.JUI_shownIcon = icon
  end
  local c = (count and count > 1) and count or ""
  if b.JUI_shownCount ~= c then
    b.count:SetText(c)
    b.JUI_shownCount = c
  end
  b.JUI_cleared = nil
  -- SetCooldown restarts the swipe animation on every call, and the aura block
  -- is repainted on every UNIT_AURA. The same pair is therefore written once.
  if duration and duration > 0 and expires and expires > 0 then
    local start = expires - duration
    if b.JUI_cdStart ~= start or b.JUI_cdDur ~= duration then
      b.JUI_cdStart, b.JUI_cdDur = start, duration
      b.cd:SetCooldown(start, duration)
    end
    if not b.cd:IsShown() then b.cd:Show() end
  else
    b.JUI_cdStart, b.JUI_cdDur = nil, nil
    if b.cd:IsShown() then b.cd:Hide() end
  end

  if not b.JUI_visible then
    b.JUI_visible = true
    b:Show()
  end
end

local function ClearAuraButton(b)
  -- Already empty: nothing on screen changes, so skip the whole write set.
  if b.JUI_cleared then return end
  b.JUI_cleared = true
  b.JUI_auraIndex = nil
  b.JUI_cdStart, b.JUI_cdDur = nil, nil
  b.JUI_visible = nil
  b:Hide()
end

-- Buff rows for the target. Stops at the first empty index instead of probing
-- all 27 slots, then hides the tail in one sweep.
local function UpdateAuraGroup(group, unit, filter)
  local buttons = group.buttons
  local total = #buttons
  local shown = 0
  if UnitExists(unit) then
    for i = 1, total do
      local name, _, icon, cnt, _, duration, expires = UnitBuff(unit, i)
      if not name then break end
      shown = shown + 1
      local b = buttons[shown]
      b.JUI_auraUnit, b.JUI_auraIndex, b.JUI_auraFilter = unit, i, filter
      SetAuraButton(b, icon, cnt, duration, expires)
    end
  end
  -- Only the buttons that were in use last pass can still be showing an icon;
  -- everything above that is already hidden, so the sweep stops there.
  for i = shown + 1, (group.used or total) do
    ClearAuraButton(buttons[i])
  end
  group.used = shown
  return shown
end

-- Debuff rows. The default filter is the player's own debuffs only:
-- Blizzard's C-side "PLAYER" filter does the ownership test inside the client,
-- so we ask for the already filtered, gap-free list instead of walking all 40
-- slots and comparing the caster in Lua. Indices returned here are indices
-- *into that filtered list*, so the tooltip must use SetUnitAura with the same
-- filter string. Callers may pass plain "HARMFUL" to show every debuff.
local TARGET_DEBUFF_FILTER = "HARMFUL|PLAYER"
local ALL_DEBUFF_FILTER    = "HARMFUL"

local function UpdateDebuffGroup(group, unit, filter)
  filter = filter or TARGET_DEBUFF_FILTER
  local buttons = group.buttons
  local total = #buttons
  local shown = 0
  if UnitExists(unit) then
    for i = 1, total do
      local name, _, icon, count, _, duration, expires =
        UnitAura(unit, i, filter)
      if not name then break end
      shown = i
      local b = buttons[i]
      b.JUI_auraUnit, b.JUI_auraIndex, b.JUI_auraFilter = unit, i, filter
      SetAuraButton(b, icon, count, duration, expires)
    end
  end
  for i = shown + 1, (group.used or total) do
    ClearAuraButton(buttons[i])
  end
  group.used = shown
  return shown
end


-- Number of icon rows a group needs for the given icon count.
local function AuraRows(group, count)
  if count <= 0 then return 0 end
  local rows = 1
  if count > group.firstRow then
    rows = rows + ceil((count - group.firstRow) / group.nextRow)
  end
  return rows
end




-- ---------------------------------------------------------------------------
-- 8. Module: player / target / target-of-target
-- ---------------------------------------------------------------------------

J:AddModule(function()
  -- Hide Blizzard player/target frames (party & raid keep Blizzard default)
  -- Blizzard's frames are parked on a hidden parent instead of having their
  -- Show method replaced: overwriting a method on a protected frame taints it.
  local park = CreateFrame("Frame", "JunkieUnitHider", UIParent)
  park:Hide()
  -- Leave FocusFrame entirely untouched. On several 3.3.5 clients it is tied
  -- to the protected focus-target path; even parking it can block /focus.
  -- Boss frames are not part of JunkieUI. Park Blizzard's originals alongside
  -- the player/target frames so deleting the old custom boss module cannot
  -- make the stock frames reappear.
  for _, f in pairs({
    PlayerFrame, TargetFrame, TargetFrameToT, ComboFrame,
    Boss1TargetFrame, Boss2TargetFrame, Boss3TargetFrame, Boss4TargetFrame,
  }) do
    if f then
      f:UnregisterAllEvents()
      f:Hide()
      if not InCombatLockdown() then f:SetParent(park) end
    end
  end

  local player = CreateUnitFrame("JunkiePlayerFrame", "player", W, H, "player")
  local target = CreateUnitFrame("JunkieTargetFrame", "target", W, H, "target")
  local tot    = CreateUnitFrame("JunkieToTFrame", "targettarget", 120, 22, "tot")

  -- ToT has no power bar
  tot:SetPowerShown(false)

  -- UNIT_TARGET for "target" is routed to this dependent frame by the shared
  -- dispatcher. Health/name events carrying "targettarget" reach it normally.
  function J:UpdatePlayerPower()
    player:SetPowerShown(J.db.playerPower)
  end
  J:UpdatePlayerPower()

  function J:UpdateTargetPower()
    target:SetPowerShown(J.db.targetPower)
  end
  J:UpdateTargetPower()

  -- Combat indicator on player
  local combat = player.health:CreateTexture(nil, "OVERLAY")
  combat:SetSize(20, 20)
  combat:SetPoint("CENTER", player.health, "CENTER", 0, 0)
  combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
  combat:SetTexCoord(0.5, 1.0, 0.0, 0.49)
  combat:Hide()
  player.combat = combat

  local function UpdateCombatIcon()
    if UnitAffectingCombat("player") then combat:Show() else combat:Hide() end
  end
  AddHook("PLAYER_REGEN_DISABLED", UpdateCombatIcon)
  AddHook("PLAYER_REGEN_ENABLED", UpdateCombatIcon)
  AddHook("PLAYER_ENTERING_WORLD", UpdateCombatIcon)

  -- Target of target: right edge lined up with the target frame's right edge
  tot:ClearAllPoints()
  tot:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, -1)

  -- Positioning: locked in Y, gap adjustable in X.
  -- Secure unit buttons cannot be moved while in combat, so defer to regen.
  AddHook("PLAYER_REGEN_ENABLED", function()
    if state.posPending then
      state.posPending = false
      J:UpdateUnitPositions()
    end
    -- Flush any power toggle that was requested while protected.
    local frames = state.frames
    for i = 1, #frames do
      local f = frames[i]
      if f.JUI_powerPending ~= nil then f:SetPowerShown(f.JUI_powerPending) end
    end
  end)

  function J:UpdateUnitPositions()
    if InCombatLockdown and InCombatLockdown() then
      state.posPending = true
      return
    end
    local gap = J.db.unitGap
    -- Locked mode: the cooldown manager sits between the frames and owns the
    -- gap, so the frames hug its main bar by J.db.cdGap pixels on each side.
    if J.CDLocked and J:CDLocked() and (J.cdWidth or 0) > 0 then
      gap = J.cdWidth + 2 * math.max(1, J.db.cdGap or 1)
    end
    -- Whole UI coordinates avoid half-pixel anchors when a dynamic JCD width is
    -- odd. Both sides remain symmetric and their 1px borders stay equally thick.
    local halfGap = floor(gap / 2 + 0.5)
    local y = floor((J.db.unitY or 0) + 0.5)
    player:ClearAllPoints()
    target:ClearAllPoints()
    player:SetPoint("RIGHT", UIParent, "CENTER", -halfGap, y)
    target:SetPoint("LEFT", UIParent, "CENTER", halfGap, y)
  end
  J:UpdateUnitPositions()

  -- The cooldown manager reports its main bar width from its own rebuild.
  function J:NotifyCDWidth(w)
    J.cdWidth = tonumber(w) or 0
    J:UpdateUnitPositions()
    if J.SyncGapState then J.SyncGapState() end
  end

  -- Target castbar lives in castbars.lua; only its drop distance is fed from
  -- the target debuff layout below.
  --
  -- The player's own debuffs are owned entirely by Blizzard's buff frame (see blizzbuffs.lua).
  -- can anchor its debuff block either under the minimap or above the player
  -- frame, so this file no longer keeps a second, duplicate debuff row.


  -- ===== Target auras: buffs above, debuffs below, wrapping at frame width =====
  -- 9 buffs per row, sized so a full row spans exactly the target frame width
  local BUFF_GAP = 1
  local BUFF_SIZE = (W - 8 * BUFF_GAP) / 9
  local targetBuffs   = CreateAuraGroup(target, 27, BUFF_SIZE, BUFF_GAP, 1, "up", 9, 9)
  local targetDebuffs = CreateAuraGroup(target, 20, 28, 1, 1, "down", 4)

  -- Keep the castbar just under the lowest visible debuff row
  local function UpdateCastbarAnchor(debuffCount)
    local rows = AuraRows(targetDebuffs, debuffCount)
    -- Default position assumes two debuff rows; more rows push the bar down.
    if rows < 2 then rows = 2 end
    local drop = targetDebuffs.frameGap
      + rows * targetDebuffs.size
      + (rows - 1) * targetDebuffs.gap
      + 6
    if J.AnchorTargetCastbar then J:AnchorTargetCastbar(drop) end
  end

  local function UpdateTargetAuras()
    UpdateAuraGroup(targetBuffs, "target", "HELPFUL")
    local debuffCount = UpdateDebuffGroup(targetDebuffs, "target")
    UpdateCastbarAnchor(debuffCount)
  end


  -- Aura events often arrive several times in one render frame. Collapse the
  -- burst into one scan/layout pass on the next frame instead of rebuilding
  -- both target aura groups synchronously for every event.
  local targetAuraQueue = CreateFrame("Frame")
  targetAuraQueue:Hide()
  targetAuraQueue:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateTargetAuras()
    Wake()
  end)

  -- Target aura visuals are refreshed directly from UNIT_AURA: stack changes
  -- and duration refreshes can keep the same slot count and must not depend on
  -- a polling loop. The player's own auras belong to Blizzard's frame.
  AddHook("UNIT_AURA", function(_, unit)
    -- UNIT_AURA fires for every raid member; ignore all unrelated units.
    if unit ~= "target" then return end
    targetAuraQueue:Show()
  end)

  -- Target-of-target refresh.
  --
  -- Root cause of the stale ToT: the 3.3.5 client never sends UNIT_HEALTH,
  -- UNIT_NAME_UPDATE or UNIT_AURA with arg1 == "targettarget", and UNIT_TARGET
  -- is only broadcast for units the client actively watches (party/raid
  -- members) - never for arbitrary NPC targets. That is why the frame only
  -- refreshed on PLAYER_TARGET_CHANGED. Blizzard's own ToT frame solves this
  -- the same way: it polls. So ToT is polled from the shared 0.25s ticker,
  -- which is kept awake for exactly as long as a target exists.
  local function UpdateToT()
    UpdateAll(tot)
  end

  local function MarkAllDirty()
    UpdateAll(target)
    UpdateToT()
    UpdateTargetAuras()
    Wake()
  end
  AddHook("PLAYER_TARGET_CHANGED", MarkAllDirty)
  AddHook("PLAYER_ENTERING_WORLD", MarkAllDirty)
  MarkAllDirty()

  -- The single OnUpdate for the whole module.
  ticker:SetScript("OnUpdate", function(self, e)
    self.JUI_elapsed = (self.JUI_elapsed or 0) + e
    if self.JUI_elapsed < TICK then return end
    self.JUI_elapsed = 0

    local hasTarget = UnitExists("target")

    -- --- pet retry burst --------------------------------------------------
    if state.petRetries > 0 then
      state.petRetries = state.petRetries - 1
      if state.petUpdate then state.petUpdate() end
    end

    -- --- target of target -------------------------------------------------
    -- Value setters are all change-cached, so a poll with nothing new costs
    -- only the unit queries. Aura countdown numbers are left to OmniCC, which
    -- draws them on the native cooldown swipe at no Lua cost, so this loop has
    -- nothing else to count down.
    if hasTarget then UpdateToT() end

    -- Nothing left to poll: stop the loop entirely. Events wake it back up
    -- through Wake().
    if not hasTarget and state.petRetries <= 0 then
      self:Hide()
    end
  end)
  Wake()

end)

-- ---------------------------------------------------------------------------
-- 9. Module: focus
-- ---------------------------------------------------------------------------
-- Same size and text layout as the player frame: name on the left, health on
-- the right, raid target mark in the middle. Buffs above and own debuffs
-- below, built with exactly the same aura machinery as the target frame; the
-- focus frame has no target-of-target, so the debuff rows use the full frame
-- width and the focus castbar rides underneath the lowest debuff row.
--
-- The custom frame has an event-driven mover. Blizzard's visual focus frames
-- are hidden once at login; there is no polling, OnUpdate or recurring hook.


J:AddModule(function()
  local player = _G["JunkiePlayerFrame"]
  local focus = CreateUnitFrame("JunkieFocusFrame", "focus", W, H, "focus")
  focus:SetPowerShown(false)

  -- Blizzard-safe visual suppression through its secure visibility driver.
  -- No events, scripts, methods or alpha values on the protected focus path
  -- are modified by addon code.
  for _, stock in pairs({ FocusFrame, FocusFrameToT, FocusFrameSpellBar }) do
    if stock then RegisterStateDriver(stock, "visibility", "hide") end
  end

  local mover = J:CreateMover("JunkieFocusMover", W, H,
    "|cffde7230Drag: Focus frame|r")

  local function PlaceFocus()
    if InCombatLockdown and InCombatLockdown() then
      state.focusPending = true
      return
    end
    state.focusPending = false
    focus:ClearAllPoints()
    if J.db.focusMoved then
      focus:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
        tonumber(J.db.focusX) or 0, tonumber(J.db.focusY) or 0)
    else
      focus:SetPoint("BOTTOMLEFT", player, "TOPLEFT", 0, 60)
    end
  end

  local function SyncFocusMover()
    mover:ClearAllPoints()
    mover:SetPoint("BOTTOMLEFT", focus, "BOTTOMLEFT", 0, 0)
  end

  mover:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left, bottom = J:MoverPos(self)
    J.db.focusX = floor(left + 0.5)
    J.db.focusY = floor(bottom + 0.5)
    J.db.focusMoved = true
    PlaceFocus()
    SyncFocusMover()
  end)

  function J:SetFocusUnlocked(on)
    J.db.focusUnlocked = on and true or false
    if J.db.focusUnlocked and not (InCombatLockdown and InCombatLockdown()) then
      SyncFocusMover()
      mover:Show()
    else
      mover:Hide()
    end
  end

  PlaceFocus()
  J:SetFocusUnlocked(J.db.focusUnlocked)
  AddHook("PLAYER_REGEN_ENABLED", function()
    if state.focusPending then PlaceFocus() end
    if J.db.focusUnlocked then SyncFocusMover(); mover:Show() end
  end)

  -- ===== Focus auras: buffs above, own debuffs below =====
  -- Same builders, same button pool logic and the same change-cached writers
  -- as the target frame, so an idle focus costs nothing at all: the groups are
  -- only touched from PLAYER_FOCUS_CHANGED and from UNIT_AURA with
  -- arg1 == "focus". No ticker and no OnUpdate is involved.
  -- 11 buffs and 10 debuffs per row, both sized so the row spans exactly the
  -- 250px focus frame: size = (W - gaps) / icons per row.
  local FBUFF_GAP   = 1
  local FBUFF_PER   = 11
  local FBUFF_SIZE  = (W - (FBUFF_PER - 1) * FBUFF_GAP) / FBUFF_PER
  local FDEBUFF_GAP = 1
  local FDEBUFF_PER = 10
  local FDEBUFF_SIZE = (W - (FDEBUFF_PER - 1) * FDEBUFF_GAP) / FDEBUFF_PER
  local focusBuffs = CreateAuraGroup(focus, FBUFF_PER * 3, FBUFF_SIZE,
    FBUFF_GAP, 1, "up", FBUFF_PER, FBUFF_PER)
  -- No target-of-target under the focus frame, so the debuff rows use the
  -- whole frame width.
  local focusDebuffs = CreateAuraGroup(focus, FDEBUFF_PER * 3, FDEBUFF_SIZE,
    FDEBUFF_GAP, 1, "down", FDEBUFF_PER, FDEBUFF_PER)


  -- The focus castbar sits 1px under the lowest visible debuff row and drops
  -- further down as soon as the debuffs wrap onto a second row.
  local function UpdateFocusCastbarAnchor(debuffCount)
    local rows = AuraRows(focusDebuffs, debuffCount)
    local drop = 1
    if rows > 0 then
      drop = focusDebuffs.frameGap
        + rows * focusDebuffs.size
        + (rows - 1) * focusDebuffs.gap
        + 1
    end
    if J.AnchorFocusCastbar then J:AnchorFocusCastbar(drop) end
  end

  -- A friendly player as focus (main tank) shows every debuff on them, since
  -- that is the point of watching them. A boss or other NPC shows only our own
  -- debuffs, exactly like the target frame. UnitIsPlayer is a cheap C call and
  -- only runs once per aura pass.
  local function UpdateFocusAuras()
    UpdateAuraGroup(focusBuffs, "focus", "HELPFUL")
    local filter = UnitIsPlayer("focus") and ALL_DEBUFF_FILTER
      or TARGET_DEBUFF_FILTER
    UpdateFocusCastbarAnchor(UpdateDebuffGroup(focusDebuffs, "focus", filter))
  end


  -- Aura events arrive in bursts; collapse them into one pass on the next
  -- frame, exactly like the target aura queue does.
  local focusAuraQueue = CreateFrame("Frame")
  focusAuraQueue:Hide()
  focusAuraQueue:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateFocusAuras()
  end)

  AddHook("UNIT_AURA", function(_, unit)
    if unit ~= "focus" then return end
    focusAuraQueue:Show()
  end)

  local function RefreshFocus()
    UpdateAll(focus)
    UpdatePower(focus)
    UpdateFocusAuras()
  end
  AddHook("PLAYER_FOCUS_CHANGED", function()
    RefreshFocus()
    if J.UpdateFocusCastbar then J:UpdateFocusCastbar() end
  end)
  AddHook("PLAYER_ENTERING_WORLD", RefreshFocus)
  RefreshFocus()
end)


-- ---------------------------------------------------------------------------
-- 10. Module: pet
-- ---------------------------------------------------------------------------


J:AddModule(function()
  local player = _G["JunkiePlayerFrame"]
  local pet = CreateUnitFrame("JunkiePetFrame", "pet", 120, 22, "pet")
  pet:SetPowerShown(false)

  -- The cooldown manager can own the strip right under the player frame with
  -- its lower unitframe bar. When it does, the pet bar moves below that row.
  -- The pet frame is a secure unit frame, so it is never anchored directly to
  -- the cooldown manager's rows: doing that would make those rows protected and
  -- block their resize in combat. Instead we anchor to our own player frame and
  -- offset by the dock's height.
  local function PlacePet()
    if InCombatLockdown and InCombatLockdown() then
      state.petPending = true
      return
    end
    state.petPending = false
    pet:ClearAllPoints()
    local dockHeight = tonumber(J.petDockHeight) or 0
    local offset = -1 - dockHeight - (dockHeight > 0 and 1 or 0)
    pet:SetPoint("TOPLEFT", player, "BOTTOMLEFT", 0, offset)
  end
  PlacePet()

  function J:SetPetDock(height)
    J.petDockHeight = tonumber(height) or 0
    PlacePet()
  end

  -- The pet health bar is always on; the unit watch (installed once in
  -- CreateUnitFrame) hides it whenever there is no pet.
  local function RefreshPet()
    UpdateAll(pet)
  end
  state.petUpdate = RefreshPet

  -- Pet summon/dismiss events are inconsistent between 3.3.5 cores. Listen to
  -- every relevant event and refresh all visible values; a short retry catches
  -- cores that create the pet unit one frame after UNIT_PET. UNIT_HEALTH /
  -- UNIT_MAXHEALTH / UNIT_NAME_UPDATE are not listed here: the pet frame is
  -- already routed those by the shared dispatcher.
  local function PetEvent(event, unit)
    if unit and unit ~= "player" and unit ~= "pet" then return end
    if event == "PLAYER_REGEN_ENABLED" and state.petPending then
      PlacePet()
    end
    RefreshPet()
    state.petRetries = 4
    Wake()
  end

  AddHook("UNIT_PET", PetEvent)
  AddHook("PET_UI_UPDATE", PetEvent)
  AddHook("PET_BAR_UPDATE", PetEvent)
  AddHook("PLAYER_ENTERING_WORLD", PetEvent)
  AddHook("PLAYER_REGEN_ENABLED", PetEvent)
end)


-- ---------------------------------------------------------------------------
-- 10. Ascension resource bars
-- ---------------------------------------------------------------------------
-- The custom client draws its own resource widgets (segment bar, resource bar,
-- multicast bar and the orb). They are Blizzard-side frames we do not own, so
-- they are never destroyed or permanently neutered: a single OnShow hook per
-- frame hides them again while the option is on, and turning the option off
-- simply shows whatever was visible before. No OnUpdate, no polling.
local COA_FRAMES = {
  "CoAResourceSegmentBar",
  "CoAResourceBar",
  "CoAMultiCastActionBarFrame",
  "CoAResourceOrb",
}

local coaHooked = {}   -- [frameName] = true, OnShow hook installed once
local coaHidden = {}   -- [frameName] = true, hidden by us (so we only restore those)
local coaRestore = {}  -- short, self-terminating restore queue
local coaRestoreDriver = CreateFrame("Frame")
local COA_RESTORE_WAITS = { 0, 0.20, 0.60 }
coaRestoreDriver:Hide()

local function RememberCoAHidden(name)
  if not name then return end
  coaHidden[name] = true
  if J.db and J.db.coaHiddenFrames then J.db.coaHiddenFrames[name] = true end
end

local function QueueCoARestore(name)
  if name then coaRestore[name] = true end
  coaRestoreDriver.JUI_elapsed = 0
  coaRestoreDriver.JUI_step = 0
  coaRestoreDriver:Show()
end

-- Ascension can run its own visibility pass immediately after a settings click
-- or PLAYER_ENTERING_WORLD.  Three sparse retries let that pass finish first.
-- The driver exists only while restoring and then parks completely.
coaRestoreDriver:SetScript("OnUpdate", function(self, elapsed)
  if J.db and J.db.hideCoAResource then self:Hide(); return end
  self.JUI_elapsed = (self.JUI_elapsed or 0) + elapsed
  local step = (self.JUI_step or 0) + 1
  if self.JUI_elapsed < COA_RESTORE_WAITS[step] then return end
  self.JUI_step = step
  self.JUI_elapsed = 0
  for name in pairs(coaRestore) do
    local f = _G[name]
    if f and not f:IsShown() then f:Show() end
  end
  if step >= #COA_RESTORE_WAITS then
    self:Hide()
    for name in pairs(coaRestore) do
      coaRestore[name] = nil
      coaHidden[name] = nil
      if J.db and J.db.coaHiddenFrames then J.db.coaHiddenFrames[name] = nil end
    end
    if J.db then J.db.coaWasHidden = nil end
  end
end)

local function CoAHide(self)
  -- Guard: the hook stays installed for the session, so it must be a no-op
  -- while the option is off.
  if J.db and J.db.hideCoAResource and self:IsShown() then
    local name = self:GetName()
    RememberCoAHidden(name)
    self:Hide()
  end
end

function J:UpdateCoAResourceBars()
  local hide = J.db and J.db.hideCoAResource
  -- A one-shot restore: if any earlier pass (or an earlier session) hid these
  -- widgets, turning the option off shows all of them back, not just the ones
  -- this session happened to hide itself.
  local restoreAll = (not hide) and J.db and J.db.coaWasHidden
  local saved = J.db and J.db.coaHiddenFrames
  for i = 1, #COA_FRAMES do
    local name = COA_FRAMES[i]
    local f = _G[name]
    if f then
      if hide then
        -- The hook is only ever installed once the option is actually turned
        -- on, so with the option off this module never touches these frames.
        if not coaHooked[name] and f.HookScript then
          coaHooked[name] = true
          f:HookScript("OnShow", CoAHide)
        end
        if f:IsShown() then
          RememberCoAHidden(name)
          f:Hide()
        end
      elseif coaHidden[name] or (saved and saved[name]) or restoreAll then
        QueueCoARestore(name)
        if not f:IsShown() then f:Show() end
      end
    end
  end
  if J.db then
    if hide then J.db.coaWasHidden = true end
  end
end

-- Read-only diagnostic for "/jui coa".
function J:ReportCoAResourceBars()
  print("|cff4fc3f7JunkieUI|r CoA resource widgets (option "
    .. ((J.db and J.db.hideCoAResource) and "ON" or "OFF") .. "):")
  for i = 1, #COA_FRAMES do
    local name = COA_FRAMES[i]
    local f = _G[name]
    if not f then
      print("  " .. name .. ": |cff888888does not exist|r")
    else
      local p = f.GetParent and f:GetParent()
      local pname = (p and p.GetName and p:GetName()) or "?"
      print(string.format("  %s: shown=%s visible=%s alpha=%.2f parent=%s hookedByUs=%s restorePending=%s",
        name, tostring(f:IsShown()), tostring(f:IsVisible()),
        (f.GetAlpha and f:GetAlpha()) or 1, pname, tostring(coaHooked[name] or false),
        tostring(coaRestore[name] or false)))
    end
  end
end



J:AddModule(function()
  J:UpdateCoAResourceBars()
  -- Some of these widgets are created (or re-shown) after login and on every
  -- world load, so the state is re-applied on those events only.
  local coa = CreateFrame("Frame")
  coa:RegisterEvent("PLAYER_ENTERING_WORLD")
  coa:SetScript("OnEvent", function() J:UpdateCoAResourceBars() end)
end)
