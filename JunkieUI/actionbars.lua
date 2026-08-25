--[[---------------------------------------------------------------------------
  JunkieUI - Actionbars

  Blizzard owns the buttons. This module only repositions and reskins them.

  Layout (bottom, centered):
    left 6x2  = Bar4 (MultiBarRight)
    center    = bottom 12 = Bar1 (ActionButton), top 12 = Bar3 (MultiBarBottomRight)
    right 6x2 = Bar2 (MultiBarBottomLeft)
    right screen edge = 12 downwards = Bar5 (MultiBarLeft)

  TAINT POLICY (applies to this entire file, do not repeat it per function):
    * Never replace or wrap a method on a Blizzard frame (Show/Hide/SetPoint).
      A tainted closure running inside Blizzard's secure code spreads taint to
      the action bars and blocks dragging / placing / removing spells in combat.
      Hiding is done by reparenting to a permanently hidden frame instead.
    * Never call ActionButton_ShowGrid, MultiActionBar_Update,
      UIParent_ManageFramePositions or write ALWAYS_SHOW_MULTIBARS from here.
    * Only positions, sizes, strata and levels are written on secure buttons,
      and never while InCombatLockdown() is true.
    * Visibility of the normal Bar1 set is driven by ONE secure state driver.

  SECTIONS
    1  Upvalues and constants        7  Bar1 slot row and keybinds
    2  Module state                  8  Micro menu
    3  Shared helpers                9  Stance bar
    4  Cooldown text                10  Pet bar
    5  Macro text                   11  Layout engine
    6  Button skinning              12  Totem bar
                                    13  Init
-----------------------------------------------------------------------------]]

local J = JunkieUI

-- 1 -- Upvalues and constants -------------------------------------------------
-- Lua 5.1 resolves every global through a hash lookup. The skin path and the
-- cooldown driver run per button and per frame, so their API calls are cached.
local _G = _G
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring
local floor, max = math.floor, math.max
local format = string.format
local tsort = table.sort

local BASESIZE = 32          -- default button edge
local GAP = 2                -- space between buttons
local EDGE = 3               -- distance to the screen edge
local PAD = 2                -- background plate padding
local PETSIZE = 27
-- Horizontal spacing between the vertical right-edge columns. Set to 1 so the
-- right-edge columns have a 1 pixel gap. The background plates still
-- bleed their PAD outward and will overlap slightly, but they are the same
-- color so the overlap is invisible.
local COLGAP = 1
local PER_MICRO_ROW = 5
local MICRO_W, MICRO_H = 29, 36

local COLOR_PANEL = { 0.098, 0.098, 0.098 }   -- #191919 plates
local COLOR_SLOT = { 0.078, 0.078, 0.078 }    -- #141414 button background
local WHITE8 = "Interface\\Buttons\\WHITE8X8"

local BACKDROP = J:PixelBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })

-- Blizzard button prefixes that this module skins and places.
local BAR_PREFIXES = {
  "ActionButton", "MultiBarRightButton", "MultiBarLeftButton",
  "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "BonusActionButton",
}

-- Blizzard bar artwork that is removed once, at login.
local BLIZZARD_ART = {
  "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
  "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
  "MainMenuBarPageNumber",
  "ActionBarUpButton", "ActionBarDownButton",
  "MainMenuBarPerformanceBarFrame",
  "MainMenuBarMaxLevelBar",
  "MainMenuXPBarTexture0", "MainMenuXPBarTexture1", "MainMenuXPBarTexture2", "MainMenuXPBarTexture3",
  "MainMenuExpBar", "ReputationWatchBar",
  "SlidingActionBarTexture0", "SlidingActionBarTexture1",
  "MultiBarLeftTexture0", "MultiBarLeftTexture1", "MultiBarLeftTexture2", "MultiBarLeftTexture3",
  "MultiBarRightTexture0", "MultiBarRightTexture1", "MultiBarRightTexture2", "MultiBarRightTexture3",
  "BonusActionBarTexture0", "BonusActionBarTexture1",
  "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
}

-- The bag row is hidden entirely; the micro menu is parked off-screen instead.
-- Blizzard rebuilds this row from MainMenuBar_UpdateKeyRing and the bag update
-- path, which on a fresh character runs after our login pass, so the row has to
-- be re-hidden on demand instead of once.
local BLIZZARD_HIDDEN = {
  "KeyRingButton", "MainMenuBarBackpackButton", "CharacterBag0Slot",
  "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
  "MainMenuBarBackpackButtonCount", "CharacterBag0SlotCount",
  "CharacterBag1SlotCount", "CharacterBag2SlotCount", "CharacterBag3SlotCount",
  "MainMenuBarBackpackButtonNormalTexture", "CharacterBag0SlotNormalTexture",
  "CharacterBag1SlotNormalTexture", "CharacterBag2SlotNormalTexture",
  "CharacterBag3SlotNormalTexture", "KeyRingButtonNormalTexture",
}


local MICRO_BUTTONS = {
  "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
  "AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
  "PVPMicroButton", "LFGMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

-- Blizzard containers that must never intercept clicks meant for the buttons.
local MOUSE_OFF_FRAMES = {
  "MainMenuBar", "MainMenuBarArtFrame", "BonusActionBarFrame",
  "MultiBarRight", "MultiBarLeft", "MultiBarBottomLeft", "MultiBarBottomRight",
}

-- 2 -- Module state -----------------------------------------------------------
-- Every mutable value of this module lives here, so nothing can be read before
-- it is assigned and no helper can shadow another helper's bookkeeping.
local state = {
  size = BASESIZE,          -- current bottom-stack button size
  layoutPending = false,    -- a layout pass was deferred by combat
  bar1Driven = false,       -- secure visibility driver installed
  cooldownHooked = false,   -- Cooldown.SetCooldown hook installed
  microList = nil,          -- cached micro button names
  microHooked = false,
  microScanned = false,
  stanceSig = nil,          -- last placement signature
  stanceParked = false,
  totemHooked = false,
  totemHider = nil,
  totemX = nil,            -- default totem anchor, relative to the bar holder
  totemY = nil,
  hider = nil,              -- permanently hidden reparent target
  slotPool = {},
  slotUsed = 0,
  cooldowns = {},           -- [cooldownFrame] = true, all registered
  activeCooldowns = {},     -- [cooldownFrame] = true, currently counting down
  macroTexts = {},          -- [fontString] = true
}

-- 3 -- Shared helpers ---------------------------------------------------------
local function Hider()
  if not state.hider then
    state.hider = CreateFrame("Frame", "JunkieHiddenParent", UIParent)
    state.hider:Hide()
  end
  return state.hider
end

local function HideFrame(frame)
  if not frame then return end
  -- Textures and font strings only need to go blank; reparenting a region is
  -- not supported on every object type in 3.3.5 and errors out.
  if frame.SetTexture and not frame.CreateTexture then frame:SetTexture(nil) end
  if frame.SetText and not frame.CreateTexture then frame:SetText("") end
  frame:Hide()
  if frame.SetAlpha then frame:SetAlpha(0) end
  if frame.CreateTexture then
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame:GetParent() ~= Hider() then frame:SetParent(Hider()) end
  end
end


-- One backdrop implementation for buttons, slots and panels.
local function ApplyBackdrop(frame, color)
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(color[1], color[2], color[3], 1)
  frame:SetBackdropBorderColor(0, 0, 0, 1)
  return frame
end

local function Buttons(prefix, n)
  local t = {}
  for i = 1, n do t[i] = _G[prefix .. i] end
  return t
end

-- Blizzard's bag row and key ring are unprotected item buttons, so an OnShow
-- guard is safe here (no secure code path calls Show on them). It is installed
-- once and keeps the row down no matter which update function brings it back.
local bagGuarded = {}
local bagGuardRunning = false
local function EnforceHidden(frame)
  if not frame or bagGuardRunning then return end
  bagGuardRunning = true
  HideFrame(frame)
  bagGuardRunning = false
end

local function GuardHidden(frame)
  if not frame or bagGuarded[frame] or not frame.HookScript then return end
  bagGuarded[frame] = true
  -- OnShow alone is insufficient on 3.3.5: several bag update paths can
  -- reparent an already-shown button without firing OnShow. OnEvent runs after
  -- the button's original event handler and restores every hidden property.
  frame:HookScript("OnShow", EnforceHidden)
  frame:HookScript("OnEvent", EnforceHidden)
end

local function StripBlizzardArt()
  for _, name in ipairs(BLIZZARD_ART) do
    local f = _G[name]
    if f then
      if f.SetTexture and not f.CreateTexture then f:SetTexture(nil) else HideFrame(f) end
    end
  end
  for _, name in ipairs(BLIZZARD_HIDDEN) do
    local f = _G[name]
    EnforceHidden(f)
    GuardHidden(f)
  end
end

-- These are the Blizzard 3.3.5 paths that can rebuild, reparent or repaint the
-- bag row after login. Hooking the update functions is deterministic and only
-- runs when Blizzard itself changes the row; no permanent polling is needed.
local BAG_UPDATE_FUNCTIONS = {
  "MainMenuBar_UpdateKeyRing",
  "MainMenuBar_UpdateCharacterBagButtons",
  "MainMenuBarBackpackButton_UpdateFreeSlots",
  "BagSlotButton_UpdateChecked",
}

local function HookBagUpdates()
  for _, name in ipairs(BAG_UPDATE_FUNCTIONS) do
    if type(_G[name]) == "function" then
      hooksecurefunc(name, StripBlizzardArt)
    end
  end
end


-- 4 -- Cooldown text ----------------------------------------------------------
local cdSecondText, cdMinuteText, cdHourText = {}, {}, {}
local function FormatCD(remaining)
  local value, cache, suffix
  if remaining >= 3600 then
    value, cache, suffix = floor(remaining / 3600 + 0.5), cdHourText, "h"
  elseif remaining > 60 then
    value, cache, suffix = floor(remaining / 60 + 0.5), cdMinuteText, "m"
  else
    value, cache, suffix = floor(remaining + 0.5), cdSecondText, ""
  end
  local text = cache[value]
  if not text then text = tostring(value) .. suffix; cache[value] = text end
  return text
end

local cdDriver = CreateFrame("Frame")
cdDriver.elapsed = 0
cdDriver:Hide()
cdDriver:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < 0.2 then return end
  self.elapsed = 0
  if not (J.db and J.db.cooldownText) then self:Hide(); return end

  local now = GetTime()
  local active = state.activeCooldowns
  local hasActive = false
  for cd in pairs(active) do
    local text = cd.JUI_text
    local start, duration = cd.JUI_start, cd.JUI_duration
    if text and start and duration and duration > 1.5 then
      local remaining = start + duration - now
      if remaining > 0 then
        hasActive = true
        if cd:IsShown() then
          -- Only touch the font string when the printed value changed: with a
          -- full bar set this loop visits every button five times a second and
          -- each SetText re-lays the string out.
          local str = FormatCD(remaining)
          if cd.JUI_shownCD ~= str then
            cd.JUI_shownCD = str
            text:SetText(str)
          end
          local low = remaining <= 5
          if cd.JUI_lowCD ~= low then
            cd.JUI_lowCD = low
            if low then
              text:SetTextColor(1, 0.25, 0.25)
            else
              text:SetTextColor(1, 0.85, 0.2)
            end
          end
          text:Show()
        end
      else
        if cd.JUI_shownCD ~= "" then
          cd.JUI_shownCD = ""
          text:SetText("")
        end
        cd.JUI_start, cd.JUI_duration = nil, nil
        active[cd] = nil
      end
    else
      active[cd] = nil
    end
  end
  if not hasActive then self:Hide() end
end)

-- Installed once from the init block, never lazily per button: a lazy install
-- retried the metatable lookup for every button when the first one failed.
local function HookCooldowns(sample)
  if state.cooldownHooked or not sample then return end
  local meta = getmetatable(sample)
  local proto = meta and meta.__index
  if not (proto and proto.SetCooldown) then return end
  state.cooldownHooked = true

  hooksecurefunc(proto, "SetCooldown", function(self, start, duration)
    if not state.cooldowns[self] then return end
    self.JUI_start, self.JUI_duration = start, duration
    if duration and duration > 1.5 and start + duration > GetTime() then
      state.activeCooldowns[self] = true
      if J.db and J.db.cooldownText then cdDriver:Show() end
    else
      state.activeCooldowns[self] = nil
    end
    if not (J.db and J.db.cooldownText) and self.JUI_text then
      self.JUI_shownCD, self.JUI_lowCD = "", nil
      self.JUI_text:SetText("")
    end
  end)
end

local function RegisterCooldown(cd)
  if not cd or cd.JUI_text then return end
  local text = cd:CreateFontString(nil, "OVERLAY")
  text:SetFont(J.font, 13, "OUTLINE")
  text:SetPoint("CENTER", cd, "CENTER", 0, 1)
  text:SetShadowOffset(0, 0)
  cd.JUI_text = text
  state.cooldowns[cd] = true
  HookCooldowns(cd)
end

-- Called by the options window when the toggle changes.
function J.ApplyCooldownText()
  local on = J.db and J.db.cooldownText
  local active = state.activeCooldowns
  local hasActive = false

  for cd in pairs(state.cooldowns) do
    local text = cd.JUI_text
    if text then
      if on then
        local start, duration = cd.JUI_start, cd.JUI_duration
        if start and duration and duration > 1.5 and (start + duration - GetTime()) > 0 then
          active[cd] = true
          hasActive = true
        end
      else
        -- Turning the option off must clear the pending set immediately,
        -- otherwise stale entries survive until the driver next runs.
        active[cd] = nil
        cd.JUI_shownCD, cd.JUI_lowCD = "", nil
        text:SetText("")
        text:Hide()
      end
    end
  end

  if on and hasActive then cdDriver:Show() else cdDriver:Hide() end
end

-- 5 -- Macro text -------------------------------------------------------------
function J.ApplyMacroText()
  local on = J.db and J.db.macroText
  for fs in pairs(state.macroTexts) do
    if on then fs:Show() else fs:Hide() end
  end
end

-- 6 -- Button skinning --------------------------------------------------------
-- Blizzard restores normal textures while actions and pages change. The art is
-- cleared from the regular update path instead of hooking each texture.
local function ClearButtonArt(tex)
  if not tex then return end
  -- A clean texture has neither a texture nor visibility, so the hot
  -- ActionButton_Update path returns after two reads and writes nothing.
  if not tex:GetTexture() and not tex:IsShown() then return end
  tex:SetTexture(nil)
  tex:SetAlpha(0)
  tex:Hide()
end

local function SkinButton(b)
  if not b then return end
  local name = b:GetName()
  if not name then return end

  if b.JUI_skinned then
    -- Hot path. The normal slot texture is the only artwork Blizzard recreates
    -- from its regular action update, and a spell drag refreshes every button
    -- in a single frame on 3.3.5 - keep this branch as small as possible.
    ClearButtonArt(b.JUI_normalTex)
    local hotkey = b.JUI_hotkey
    if hotkey and not b.JUI_ownKeyLabel then
      J:ShortenHotkey(hotkey, b)
    end
    return
  end
  b.JUI_skinned = true

  -- Bar 1 (and its stance page) uses one persistent label from the slot row,
  -- so Blizzard's own two competing strings stay invisible there.
  b.JUI_ownKeyLabel = (name:match("^ActionButton%d+$") or name:match("^BonusActionButton%d+$")) and true or false

  local normalTex = _G[name .. "NormalTexture"] or (b.GetNormalTexture and b:GetNormalTexture())
  b.JUI_normalTex = normalTex

  -- One-time cleanup of every Blizzard art layer. Only NormalTexture needs the
  -- lightweight maintenance path above.
  ClearButtonArt(normalTex)
  ClearButtonArt(_G[name .. "NormalTexture2"])
  ClearButtonArt(_G[name .. "FloatingBG"])
  ClearButtonArt(_G[name .. "Border"])
  -- Active-state marker: Blizzard's checked texture is what flags a toggled
  -- ability (stance/aura/seal/tracking, auto-repeat shots, an active toy or
  -- item effect - anything IsCurrentAction reports as on). The default artwork
  -- does not fit the flat skin, so it is replaced with a tinted plate rather
  -- than stripped. Blizzard keeps driving it through ActionButton_UpdateState,
  -- so this costs nothing per frame.
  if b.SetCheckedTexture then
    b:SetCheckedTexture(WHITE8)
    local ck = b:GetCheckedTexture()
    if ck then
      ck:SetVertexColor(1, 0.82, 0, 0.35)
      ck:SetAllPoints(b)
      ck:SetDrawLayer("OVERLAY")
    end
  end

  local icon = _G[name .. "Icon"]
  if icon then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  end

  local flash = _G[name .. "Flash"]
  if flash then
    flash:SetTexture(WHITE8)
    flash:SetVertexColor(0.8, 0.1, 0.1, 0.35)
    flash:SetAllPoints(b)
  end

  if b.SetHighlightTexture then
    b:SetHighlightTexture(WHITE8)
    local hl = b:GetHighlightTexture()
    if hl then hl:SetVertexColor(1, 1, 1, 0.15); hl:SetAllPoints(b) end
  end
  if b.SetPushedTexture then
    b:SetPushedTexture(WHITE8)
    local pt = b:GetPushedTexture()
    if pt then pt:SetVertexColor(1, 1, 1, 0.25); pt:SetAllPoints(b) end
  end

  local cd = _G[name .. "Cooldown"]
  if cd then
    cd:ClearAllPoints()
    cd:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    cd:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    RegisterCooldown(cd)
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
  end

  local hotkey = _G[name .. "HotKey"]
  b.JUI_hotkey = hotkey
  if hotkey then
    hotkey:SetFont(J.font, 11, "OUTLINE")
    hotkey:SetShadowOffset(0, 0)
    hotkey:ClearAllPoints()
    hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
    hotkey:SetJustifyH("RIGHT")
    if b.JUI_ownKeyLabel then hotkey:SetAlpha(0) end
  end

  local count = _G[name .. "Count"]
  if count then
    count:SetFont(J.font, 12, "OUTLINE")
    count:SetShadowOffset(0, 0)
  end

  local macro = _G[name .. "Name"]
  if macro then
    state.macroTexts[macro] = true
    macro:SetFont(J.font, 10, "OUTLINE")
    macro:SetShadowOffset(0, 0)
    if J.db and J.db.macroText then macro:Show() else macro:Hide() end
  end

  if not b.JUI_backdrop then
    local bd = CreateFrame("Frame", nil, b)
    bd:SetAllPoints(b)
    bd:SetFrameLevel(max(b:GetFrameLevel() - 1, 0))
    ApplyBackdrop(bd, COLOR_SLOT)
    b.JUI_backdrop = bd
  end
end

local function SkinAll()
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do SkinButton(_G[prefix .. i]) end
  end
end


-- Key press down ---------------------------------------------------------------
-- "Cast on key down" is two separate switches on this client: the CVar drives
-- keybinds (Blizzard's ActionButton_Down path) and RegisterForClicks drives
-- actual mouse clicks. Both are set once, at login, and after the forced reload
-- the settings toggle triggers -- nothing here runs per frame.
-- RegisterForClicks is protected on action buttons, so the pass bails in
-- combat; a change can only reach it through a reload anyway.
local KEYDOWN_EXTRA_PREFIXES = { "ShapeshiftButton", "PetActionButton" }

local function ApplyKeyPressDown()
  if InCombatLockdown and InCombatLockdown() then return end
  local on = (J.db and J.db.keyPressDown) and true or false
  if type(SetCVar) == "function" then
    pcall(SetCVar, "ActionButtonUseKeyDown", on and "1" or "0")
  end
  local clicks = on and "AnyDown" or "AnyUp"
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do
      local b = _G[prefix .. i]
      if b and b.RegisterForClicks then b:RegisterForClicks(clicks) end
    end
  end
  for _, prefix in ipairs(KEYDOWN_EXTRA_PREFIXES) do
    for i = 1, 12 do
      local b = _G[prefix .. i]
      if b and b.RegisterForClicks then b:RegisterForClicks(clicks) end
    end
  end
end
J.ApplyKeyPressDown = ApplyKeyPressDown


-- Range check ----------------------------------------------------------------
-- Blizzard's own range timer does not drive every bar on this client (the main
-- bar in particular repaints only when an action happens), so the tint is owned
-- here instead: one 5Hz ticker, parked whenever there is no target, and the
-- icon is only touched when the range flag actually flips.
-- IsActionInRange returns 0 both when the target is too far away and when it
-- is inside a spell's minimum range (deadzone), which is exactly the two cases
-- the icon should read as red.
local RANGE_R, RANGE_G, RANGE_B = 1, 0.25, 0.25
local rangeButtons = nil

local function ButtonIcon(b)
  local icon = b.JUI_icon
  if not icon then
    local name = b:GetName()
    icon = name and _G[name .. "Icon"]
    b.JUI_icon = icon
  end
  return icon
end

local function RangeList()
  if rangeButtons then return rangeButtons end
  rangeButtons = {}
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do
      local b = _G[prefix .. i]
      if b then
        b.JUI_ranged = true          -- marks the buttons this module owns
        rangeButtons[#rangeButtons + 1] = b
      end
    end
  end
  return rangeButtons
end

local function ApplyRangeTint(b, oor)
  local icon = ButtonIcon(b)
  if not icon then return end
  if oor then
    icon:SetVertexColor(RANGE_R, RANGE_G, RANGE_B)
  elseif ActionButton_UpdateUsable then
    -- Hand the colour back to Blizzard so usable/unusable/mana stays correct.
    ActionButton_UpdateUsable(b)
  else
    icon:SetVertexColor(1, 1, 1)
  end
end

-- Blizzard repaints the icon on its own (usable, mana, action change) and would
-- wipe the red. This hook only re-applies the cached flag: no API call, and it
-- never touches buttons this module does not own.
local function UpdateRangeTint(self)
  if not self or not self.JUI_ranged or not self.JUI_oor then return end
  local icon = ButtonIcon(self)
  if icon then icon:SetVertexColor(RANGE_R, RANGE_G, RANGE_B) end
end

local function ClearRangeTints()
  local list = RangeList()
  for i = 1, #list do
    local b = list[i]
    if b.JUI_oor then
      b.JUI_oor = nil
      ApplyRangeTint(b, false)
    end
  end
end

local rangeTicker = CreateFrame("Frame")
rangeTicker:Hide()
rangeTicker.elapsed = 0
rangeTicker:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < 0.2 then return end
  self.elapsed = 0
  if not UnitExists("target") then
    ClearRangeTints()
    self:Hide()
    return
  end
  local list = RangeList()
  for i = 1, #list do
    local b = list[i]
    local action = b.action
    -- IsVisible() (not IsShown) skips every button on a bar that is hidden as
    -- a whole, and HasAction skips empty slots: both are cheap local checks
    -- that keep IsActionInRange off the buttons that could never tint anyway.
    if action and b:IsVisible() and HasAction(action) then
      local oor = (IsActionInRange(action) == 0) or false
      if oor ~= (b.JUI_oor or false) then
        b.JUI_oor = oor or nil
        ApplyRangeTint(b, oor)
      end
    elseif b.JUI_oor then
      -- Slot went empty or its bar was hidden while tinted: drop the flag so a
      -- later action in that slot starts from a clean colour.
      b.JUI_oor = nil
      ApplyRangeTint(b, false)
    end
  end
end)

local function RefreshRangeAll()
  if UnitExists("target") then
    rangeTicker.elapsed = 1
    rangeTicker:Show()
  else
    ClearRangeTints()
    rangeTicker:Hide()
  end
end


-- Persistent slot art. Blizzard hides empty secure buttons in several states
-- (and their skin backdrop goes with them), so the visible frame/background of
-- a slot lives in its own mouse-transparent frame that this module owns.
local function NewSlotFrame(parent, strata, level)
  local s = CreateFrame("Frame", nil, parent)
  s:EnableMouse(false)
  s:SetFrameStrata(strata)
  s:SetFrameLevel(level)
  return ApplyBackdrop(s, COLOR_SLOT)
end

local function HideAllSlots()
  for _, s in ipairs(state.slotPool) do s:Hide() end
  state.slotUsed = 0
end

local function AcquireSlot(parent)
  state.slotUsed = state.slotUsed + 1
  local s = state.slotPool[state.slotUsed]
  if not s then
    s = NewSlotFrame(parent, "LOW", 1)
    state.slotPool[state.slotUsed] = s
  end
  s:SetParent(parent)
  s:ClearAllPoints()
  s:Show()
  return s
end

-- Background plate behind a block of buttons.
local function Panel(key, parent)
  J.barPanels = J.barPanels or {}
  local p = J.barPanels[key]
  if not p then
    p = CreateFrame("Frame", nil, parent)
    p:SetFrameStrata("BACKGROUND")
    ApplyBackdrop(p, COLOR_PANEL)
    J.barPanels[key] = p
  end
  p:SetParent(parent)
  p:ClearAllPoints()
  return p
end

local function HideUnusedPanels(used)
  if not J.barPanels then return end
  local on = not (J.db and J.db.barBackground == false)
  for key, p in pairs(J.barPanels) do
    p.JUI_used = used[key] and true or false
    if on and p.JUI_used then p:Show() else p:Hide() end
  end
end

-- Toggle the background plates without a full relayout.
function J:ApplyBarBackground()
  if not J.barPanels then return end
  local on = not (J.db and J.db.barBackground == false)
  for _, p in pairs(J.barPanels) do
    if on and p.JUI_used then p:Show() else p:Hide() end
  end
end

-- Buttons are only repositioned; their shown state belongs to Blizzard.
-- dir "right" fills rows left to right from BOTTOMLEFT, dir "down" fills a
-- single column downwards from TOPRIGHT.
local function PlaceGrid(buttons, anchor, relPoint, x, y, perRow, size, dir)
  local down = (dir == "down")
  local point = down and "TOPRIGHT" or "BOTTOMLEFT"
  for i, b in ipairs(buttons) do
    if b then
      local ox, oy
      if down then
        ox, oy = x, y - (i - 1) * (size + GAP)
      else
        local col = (i - 1) % perRow
        local row = floor((i - 1) / perRow)
        ox, oy = x + col * (size + GAP), y + row * (size + GAP)
      end
      b:ClearAllPoints()
      b:SetPoint(point, anchor, relPoint, ox, oy)
      b:SetSize(size, size)
      b:SetFrameStrata("MEDIUM")
      b:SetFrameLevel(5)
      local s = AcquireSlot(anchor)
      s:SetPoint(point, anchor, relPoint, ox, oy)
      s:SetSize(size, size)
    end
  end
end

-- 7 -- Bar1 slot row and keybinds ---------------------------------------------
-- Bar 1 is special in 3.3.5: Blizzard swaps the normal ActionButtons for
-- BonusActionButtons in stances/stealth and hides every empty secure button, so
-- a backdrop parented to either set disappears with it. This permanent,
-- mouse-transparent row supplies the background and the keybind label instead.
local function PlaceBar1Slots()
  local holder = J.barHolder
  if not holder then return end
  J.bar1Slots = J.bar1Slots or {}

  local size = state.size
  for i = 1, 12 do
    local slot = J.bar1Slots[i]
    if not slot then
      slot = NewSlotFrame(holder, "LOW", 1)

      local keyLayer = CreateFrame("Frame", nil, holder)
      keyLayer:EnableMouse(false)
      keyLayer:SetFrameStrata("HIGH")
      keyLayer:SetFrameLevel(20)

      local key = keyLayer:CreateFontString(nil, "OVERLAY")
      key:SetFont(J.font, 11, "OUTLINE")
      key:SetJustifyH("RIGHT")
      key:SetShadowOffset(0, 0)
      key:SetTextColor(0.6, 0.6, 0.6)
      key:SetPoint("TOPRIGHT", keyLayer, "TOPRIGHT", -2, -2)

      slot.key = key
      slot.keyLayer = keyLayer
      J.bar1Slots[i] = slot
    end

    slot:ClearAllPoints()
    slot:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT",
      (J.bar1X or 0) + (i - 1) * (size + GAP), J.bar1Y or 0)
    slot:SetSize(size, size)
    slot.keyLayer:ClearAllPoints()
    slot.keyLayer:SetAllPoints(slot)
    slot.keyLayer:Show()
    slot:Show()
  end

  J:RefreshBar1Keys()
end

function J:RefreshBar1Keys()
  local slots = J.bar1Slots
  if not slots then return end
  for i = 1, 12 do
    local slot = slots[i]
    if slot and slot.key then
      -- Read Blizzard's already formatted label so modifier names and
      -- server-specific abbreviations match every other bar.
      local native = _G["ActionButton" .. i .. "HotKey"]
      local text = native and native:GetText()
      if not text or text == "" then
        local binding = GetBindingKey("ACTIONBUTTON" .. i)
        text = binding and GetBindingText(binding, "KEY_", 1) or ""
      end
      -- Write the shortened form straight away; the raw label must never be
      -- rendered, not even for one frame.
      slot.key:SetText(J:AbbrevKey(text))
      J:ShortenHotkey(slot.key, slot)
    end
  end
end

-- Blizzard 3.3.5 can leave ActionButton1-12 shown underneath the separate
-- BonusActionButton set during a stance transition; both sets then share
-- coordinates and frame level, so icons bleed through and can take clicks.
-- ONE state driver handles all 12 buttons - twelve individual drivers made the
-- restricted environment re-evaluate the same conditional twelve times per
-- stealth/form/aura event, which is what caused the stutter.
local function SetupBar1Visibility()
  if state.bar1Driven or not RegisterStateDriver then return end

  local vis = CreateFrame("Frame", "JunkieBar1Visibility", UIParent, "SecureHandlerStateTemplate")
  for i = 1, 12 do
    local button = _G["ActionButton" .. i]
    if button then vis:SetFrameRef("b" .. i, button) end
  end
  vis:SetAttribute("_onstate-jbar1", [[
    local hide = newstate == "hide"
    for i = 1, 12 do
      local b = self:GetFrameRef("b" .. i)
      if b then
        if hide then b:Hide() else b:Show() end
      end
    end
  ]])
  RegisterStateDriver(vis, "jbar1",
    "[bonusbar:1][bonusbar:2][bonusbar:3][bonusbar:4][bonusbar:5][stealth][vehicleui] hide; show")

  J.bar1Visibility = vis
  state.bar1Driven = true
end

-- 8 -- Micro menu -------------------------------------------------------------
-- Custom servers (Ascension and friends) add micro buttons that are not in
-- MICRO_BUTTONS. Any global button whose name ends in "MicroButton" is picked
-- up too. Scanning the whole global table is expensive, so it runs once per
-- session and when the menu is toggled - never on zone changes or OnUpdate.
local function ScanMicro()
  local found, list = {}, {}
  for _, n in ipairs(MICRO_BUTTONS) do
    if _G[n] then found[n] = true; list[#list + 1] = n end
  end

  local extra = {}
  for name, obj in pairs(_G) do
    if type(name) == "string" and not found[name] and name ~= "FriendsMicroButton"
      and name:sub(-11) == "MicroButton" and type(obj) == "table"
      and obj.GetObjectType and obj.SetParent then
      local ok, objType = pcall(obj.GetObjectType, obj)
      if ok and objType == "Button" then extra[#extra + 1] = name end
    end
  end
  tsort(extra)
  for _, n in ipairs(extra) do list[#list + 1] = n end

  state.microList = list
  state.microScanned = true
  return list
end

local function CollectMicro()
  return state.microList or ScanMicro()
end

-- Off = reparented to the permanently hidden frame, so Blizzard can call Show
-- as often as it likes and nothing appears. On = two rows under the clock bar.
local function ApplyMicroMenu()
  local holder = J.microHolder
  if not holder then return end
  local on = (J.db and J.db.microMenu) and true or false

  holder:ClearAllPoints()
  if on then
    local anchor = _G.JunkieClock or Minimap
    holder:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 1, -2)
    holder:SetSize(PER_MICRO_ROW * MICRO_W, MICRO_H * 2)
    holder:Show()
  else
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -5000, -5000)
    holder:Hide()
  end

  local parent = on and holder or Hider()
  for i, n in ipairs(CollectMicro()) do
    local b = _G[n]
    if b then
      if b:GetParent() ~= parent then b:SetParent(parent) end
      b:ClearAllPoints()
      local col = (i - 1) % PER_MICRO_ROW
      local row = floor((i - 1) / PER_MICRO_ROW)
      b:SetPoint("TOPLEFT", parent, "TOPLEFT",
        on and col * MICRO_W or 0, on and -row * MICRO_H or 0)
      b:SetAlpha(1)
    end
  end
end

function J:SetMicroMenu(on)
  if not J.db then return end
  J.db.microMenu = on and true or false
  ScanMicro()
  ApplyMicroMenu()
end

local function SetupMicroMenu()
  if not J.microHolder then
    local holder = CreateFrame("Frame", "JunkieMicroMenu", UIParent)
    holder:SetSize(PER_MICRO_ROW * MICRO_W, MICRO_H * 2)
    holder:SetFrameStrata("MEDIUM")
    J.microHolder = holder
  end
  ApplyMicroMenu()

  -- Blizzard only moves this group from a handful of update functions. Follow
  -- those directly instead of polling; custom buttons are included because
  -- ApplyMicroMenu uses the cached full list.
  if not state.microHooked and hooksecurefunc then
    state.microHooked = true
    for _, fn in ipairs({ "MoveMicroButtons", "UpdateMicroButtons" }) do
      if type(_G[fn]) == "function" then hooksecurefunc(fn, ApplyMicroMenu) end
    end
  end
end

-- 9 -- Stance bar -------------------------------------------------------------
-- Vertical column flush against the right side bars. Blizzard calls
-- ShapeshiftBar_Update very often (form, usable and cooldown updates), so the
-- placement work is skipped unless the mode or the number of forms changed.
-- Entering combat makes the client re-run its own stance bar layout, and on this
-- client that pass can leave a scale on ShapeshiftBarFrame. The buttons are its
-- children, so a stray scale is exactly what makes the whole column balloon.
-- Scale/alpha are not protected calls, so this stays safe inside lockdown.
local function NormalizeStanceFrame()
  local f = ShapeshiftBarFrame
  if not f then return end
  if f.GetScale and f:GetScale() ~= 1 then f:SetScale(1) end
  for i = 1, 10 do
    local b = _G["ShapeshiftButton" .. i]
    if b and b.GetScale and b:GetScale() ~= 1 then b:SetScale(1) end
  end
end

-- Cheap fingerprint of the anchor the bar currently carries. Blizzard's own
-- login pass (and UIParent_ManageFramePositions) can re-anchor or re-scale the
-- column after we placed it; a mode/form-count signature alone cannot see that,
-- which is why the bar stayed wrong until the options panel forced a pass.
-- GetPoint/GetScale return stored values (no layout resolution, no screen
-- coordinate rounding), so the fingerprint is deterministic: right after our
-- own placement it always matches, which rules out repeated relayouts.
local function StanceGeomSig()
  local b = _G["ShapeshiftButton1"]
  if not b or not b.GetPoint then return "-" end
  local p, rel, rp, x, y = b:GetPoint(1)
  local relName = (rel and rel.GetName and rel:GetName()) or "?"
  local s = (b.GetScale and b:GetScale()) or 1
  local fs = (ShapeshiftBarFrame and ShapeshiftBarFrame.GetScale
    and ShapeshiftBarFrame:GetScale()) or 1
  return tostring(p) .. ":" .. relName .. ":" .. tostring(rp) .. ":"
    .. tostring(x and floor(x + 0.5)) .. ":" .. tostring(y and floor(y + 0.5))
    .. ":" .. tostring(s) .. ":" .. tostring(fs)
end

local function PlaceStanceBar(used, force)
  if InCombatLockdown and InCombatLockdown() then
    -- Secure buttons cannot be re-anchored while locked down, so the geometry
    -- pass is deferred to PLAYER_REGEN_ENABLED. The scale fix above still runs,
    -- which is what keeps the bar from blowing up mid-fight.
    NormalizeStanceFrame()
    state.stancePending = true
    state.stanceSig = nil
    return false
  end
  NormalizeStanceFrame()


  local numForms = (GetNumShapeshiftForms and GetNumShapeshiftForms()) or 0
  local mode = J.db and J.db.barLayout
  local sig = tostring(mode) .. ":" .. numForms .. ":" .. StanceGeomSig()
  if not force and not used and sig == state.stanceSig then return false end
  state.stancePending = false


  -- Two side columns exist in the "one big stack" layouts, one otherwise.
  local cols = (mode == "triple" or mode == "tripleHigh" or mode == "sebby") and 2 or 1
  local sx = -EDGE - cols * (BASESIZE + COLGAP)
  -- Vertically centered on the side bars (their centre sits GAP/2 above RIGHT).
  local barH = max(numForms, 1) * BASESIZE + max(numForms - 1, 0) * GAP
  local topY = GAP / 2 + barH / 2

  if ShapeshiftBarFrame then
    if ShapeshiftBarFrame:GetParent() ~= UIParent then ShapeshiftBarFrame:SetParent(UIParent) end
    ShapeshiftBarFrame:ClearAllPoints()
    ShapeshiftBarFrame:SetPoint("TOPRIGHT", UIParent, "RIGHT", sx, topY)
    ShapeshiftBarFrame:SetSize(BASESIZE, barH)
    ShapeshiftBarFrame:SetAlpha(1)
    ShapeshiftBarFrame:EnableMouse(false)
  end

  for i = 1, 10 do
    local b = _G["ShapeshiftButton" .. i]
    if b then
      b:ClearAllPoints()
      b:SetPoint("TOPRIGHT", UIParent, "RIGHT", sx, topY - (i - 1) * (BASESIZE + GAP))
      b:SetSize(BASESIZE, BASESIZE)
      b:SetFrameStrata("MEDIUM")
      b:SetFrameLevel(5)
      b:SetAlpha(1)
      b:EnableMouse(true)
      SkinButton(b)
    end
  end

  local panel = J.barPanels and J.barPanels["stance"]
  if numForms > 0 then
    local ps = Panel("stance", UIParent)
    ps:SetPoint("TOPRIGHT", UIParent, "RIGHT", sx + PAD, topY + PAD)
    ps:SetSize(BASESIZE + PAD * 2, numForms * BASESIZE + (numForms - 1) * GAP + PAD * 2)
    ps:Show()
    if used then used["stance"] = true end
  else
    if panel then panel:Hide() end
    if used then used["stance"] = false end
  end
  -- Recorded after the placement so the fingerprint describes our own final
  -- geometry. Any later foreign move/scale changes it and unlocks one pass.
  state.stanceSig = tostring(mode) .. ":" .. numForms .. ":" .. StanceGeomSig()
  return true
end
J.PlaceStanceBar = PlaceStanceBar

-- Login settle pass. At login the client finishes its own stance/bonus-bar
-- layout after our modules have run, so a single placement at PLAYER_LOGIN can
-- be overwritten. This driver re-checks a handful of times over the first few
-- seconds and then hides itself for good: no OnUpdate remains during play, and
-- each check is a signature compare that only re-places when something drifted.
local STANCE_SETTLE = { 0.1, 0.4, 1.0, 2.0, 4.0 }
local stanceSettle
local function StartStanceSettle()
  if not (J.db and J.db.stanceBar) then return end
  if not stanceSettle then
    stanceSettle = CreateFrame("Frame")
    stanceSettle:Hide()
    stanceSettle:SetScript("OnUpdate", function(self, elapsed)
      self.t = (self.t or 0) + elapsed
      local step = STANCE_SETTLE[self.i or 1]
      if not step then self:Hide() return end
      if self.t < step then return end
      self.i = (self.i or 1) + 1
      if InCombatLockdown and InCombatLockdown() then
        -- Placement is unsafe in lockdown; PLAYER_REGEN_ENABLED redoes it.
        state.stancePending = true
        self:Hide()
        return
      end
      -- The toggle may have been switched off while the pass was running; the
      -- parked bar must never be dragged back onto the screen.
      if not (J.db and J.db.stanceBar) then self:Hide() return end
      PlaceStanceBar(nil, false)
      if not STANCE_SETTLE[self.i] then self:Hide() end
    end)
  end
  stanceSettle.t = 0
  stanceSettle.i = 1
  stanceSettle:Show()
end
J.StartStanceSettle = StartStanceSettle


-- 10 -- Pet bar ---------------------------------------------------------------
-- PetActionBarFrame is a sliding bar that re-points itself while it animates,
-- which pulled the row apart. The buttons keep their original parent (Blizzard
-- still owns their visibility) but anchor to our bar holder, which never moves.
local function PlacePetBar()
  if not PetActionBarFrame or not J.barHolder then return end
  if InCombatLockdown() then return end
  if not J.petBarX then return end

  PetActionBarFrame:SetScale(1)
  for i = 1, 10 do
    local b = _G["PetActionButton" .. i]
    if b then
      SkinButton(b)
      b:SetScale(1)
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT",
        J.petBarX + (i - 1) * (PETSIZE + GAP), J.petBarY)
      b:SetSize(PETSIZE, PETSIZE)
      b:SetFrameStrata("MEDIUM")
      b:SetFrameLevel(5)
    end
  end
end

-- 11 -- Layout engine ---------------------------------------------------------
local function CurrentMode()
  local m = J.db and J.db.barLayout
  if m == "three" or m == "triple" or m == "tripleHigh" or m == "sebby" then return m end
  return "one"
end

local function ApplyLayout()
  if InCombatLockdown and InCombatLockdown() then
    state.layoutPending = true
    return
  end
  state.layoutPending = false
  HideAllSlots()

  local mode = CurrentMode()
  local isTriple = (mode == "triple" or mode == "tripleHigh" or mode == "sebby")

  -- Sebby Layout runs the bottom stack 10% larger; the two vertical bars at the
  -- right screen edge always keep BASESIZE.
  local size = (mode == "sebby") and floor(BASESIZE * 1.1 + 0.5) or BASESIZE
  state.size = size

  local bottomY = (mode == "sebby") and 90 or ((mode == "tripleHigh") and 40 or EDGE)
  -- Sebby: the player castbar is docked on top of the stack, so the pet bar
  -- has to make room for it.
  local castReserve = (mode == "sebby") and 30 or 0

  local blockW = 6 * size + 5 * GAP            -- 6-column block
  local midW   = 12 * size + 11 * GAP          -- 12-column row
  local rowH   = size * 2 + GAP
  -- In split mode the plates keep 2px between them (PAD on each side).
  local blockGap = (mode == "three") and (GAP + PAD * 2) or GAP

  local bar4 = Buttons("MultiBarRightButton", 12)
  local bar1 = Buttons("ActionButton", 12)
  local bar3 = Buttons("MultiBarBottomRightButton", 12)
  local bar2 = Buttons("MultiBarBottomLeftButton", 12)
  local bar5 = Buttons("MultiBarLeftButton", 12)
  local bonus = Buttons("BonusActionButton", 12)

  local used = {}
  local totalW, holderH

  if isTriple then
    totalW, holderH = midW, size * 3 + GAP * 2
    J.bar1X, J.bar1Y = 0, 0
  else
    totalW, holderH = blockW + blockGap + midW + blockGap + blockW, rowH
    J.bar1X, J.bar1Y = blockW + blockGap, 0
  end

  J.barHolder:SetSize(totalW, holderH)
  J.barHolder:ClearAllPoints()
  J.barHolder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, bottomY)

  -- Buttons stay in their original secure parents; only the anchors move.
  PlaceGrid(bar1, J.barHolder, "BOTTOMLEFT", J.bar1X, 0, 12, size)
  PlaceGrid(bar3, J.barHolder, "BOTTOMLEFT", J.bar1X, size + GAP, 12, size)
  PlaceBar1Slots()

  if isTriple then
    -- Bar 4 becomes a third full 12-row on top of the stack.
    PlaceGrid(bar4, J.barHolder, "BOTTOMLEFT", 0, (size + GAP) * 2, 12, size)
    -- Bar 2 becomes a second vertical 12-column directly left of Bar 5.
    local topY = 6 * (BASESIZE + GAP)
    PlaceGrid(bar2, UIParent, "RIGHT", -EDGE - BASESIZE - COLGAP, topY, 1, BASESIZE, "down")

    local pmain = Panel("bottom", J.barHolder)
    pmain:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT", -PAD, -PAD)
    pmain:SetSize(totalW + PAD * 2, holderH + PAD * 2)
    used["bottom"] = true

    local p2 = Panel("bar2", UIParent)
    p2:SetPoint("TOPRIGHT", UIParent, "RIGHT", -EDGE - BASESIZE - COLGAP + PAD, topY + PAD)
    p2:SetSize(BASESIZE + PAD * 2, 12 * BASESIZE + 11 * GAP + PAD * 2)
    used["bar2"] = true
  else
    PlaceGrid(bar4, J.barHolder, "BOTTOMLEFT", 0, 0, 6, size)
    PlaceGrid(bar2, J.barHolder, "BOTTOMLEFT", blockW + blockGap + midW + blockGap, 0, 6, size)

    if mode == "three" then
      local pleft = Panel("left", J.barHolder)
      pleft:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT", -PAD, -PAD)
      pleft:SetSize(blockW + PAD * 2, rowH + PAD * 2)

      local pmid = Panel("bottom", J.barHolder)
      pmid:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT", blockW + blockGap - PAD, -PAD)
      pmid:SetSize(midW + PAD * 2, rowH + PAD * 2)

      local pright = Panel("right", J.barHolder)
      pright:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT",
        blockW + blockGap + midW + blockGap - PAD, -PAD)
      pright:SetSize(blockW + PAD * 2, rowH + PAD * 2)

      used["left"], used["bottom"], used["right"] = true, true, true
    else
      local pall = Panel("bottom", J.barHolder)
      pall:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT", -PAD, -PAD)
      pall:SetSize(totalW + PAD * 2, rowH + PAD * 2)
      used["bottom"] = true
    end
  end

  -- The stance/bonus bar sits exactly on Bar 1. Bonus buttons carry their own
  -- opaque backdrop from SkinButton; the permanent slot row supplies the
  -- background for empty buttons on every stance page.
  if BonusActionBarFrame then
    BonusActionBarFrame:ClearAllPoints()
    BonusActionBarFrame:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT", J.bar1X, 0)
    BonusActionBarFrame:SetSize(midW, size)
  end
  PlaceGrid(bonus, J.barHolder, "BOTTOMLEFT", J.bar1X, 0, 12, size)
  -- Never leave the active stance set tied with the normal set at level 5. The
  -- visibility driver prevents overlap; level 6 is a second safeguard during
  -- Blizzard's transition frame when entering or leaving a bonus page.
  for _, button in ipairs(bonus) do
    if button then button:SetFrameLevel(6) end
  end

  -- Bar 5: 12 buttons downwards at the right screen edge.
  PlaceGrid(bar5, UIParent, "RIGHT", -EDGE, 6 * (BASESIZE + GAP), 1, BASESIZE, "down")

  local p5 = Panel("bar5", UIParent)
  p5:SetPoint("TOPRIGHT", UIParent, "RIGHT", -EDGE + PAD, 6 * (BASESIZE + GAP) + PAD)
  p5:SetSize(BASESIZE + PAD * 2, 12 * BASESIZE + 11 * GAP + PAD * 2)
  used["bar5"] = true

  -- Pet bar: centered above the top row, no background plate.
  local petW = 10 * PETSIZE + 9 * GAP
  local petY = holderH + GAP + PAD * 2 + castReserve
  J.petBarX = floor((totalW - petW) / 2 + 0.5)
  J.petBarY = floor(petY + 0.5)
  PlacePetBar()

  -- Totem bar (shaman): hard locked 20px left of the pet bar position.
  -- File-local: nothing outside this module reads these.
  state.totemX = (totalW - petW) / 2 - 20
  state.totemY = petY

  -- Top of the pet bar row, relative to the holder bottom. The player castbar
  -- rides above this line, so a layout change lifts it as well.
  J.petTopY = petY + PETSIZE
  J.barBottomY = bottomY
  J.barTopW = totalW
  J.barLayoutMode = mode
  J.barHolderH = holderH

  J.LockTotemBar()
  if J.AnchorPlayerCastbar then J:AnchorPlayerCastbar() end
  if J.AnchorTargetCastbar then J:AnchorTargetCastbar() end

  -- Stance bar: optional. Parked off-screen when disabled.
  if J.db and J.db.stanceBar then
    if state.stanceParked then
      -- Coming back from parked: the cached signature is stale.
      state.stanceParked = false
      state.stanceSig = nil
    end
    PlaceStanceBar(used, true)
  else
    used["stance"] = false
    if not state.stanceParked then
      -- Hide the intact Blizzard frame. Never unregister its events: doing so
      -- permanently breaks forms when the option is enabled again.
      state.stanceParked = true
      state.stanceSig = nil
      if ShapeshiftBarFrame then ShapeshiftBarFrame:SetParent(Hider()) end
    end
  end

  HideUnusedPanels(used)
  SkinAll()
end
J.ApplyBarLayout = ApplyLayout

-- 12 -- Totem bar -------------------------------------------------------------
-- Pinned through its own state events. No SetPoint hooks: competing anchor
-- hooks can form an expensive loop. Placement is fully free; the only rule is
-- that the bar stays on screen.
local function ClampTotem()
  if not (J.db and J.db.totemMoved) then return end

  local bar = MultiCastActionBarFrame
  local w = (bar and bar:GetWidth()) or 240
  local h = (bar and bar:GetHeight()) or 40
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local x = tonumber(J.db.totemX) or 0
  local y = tonumber(J.db.totemY) or 0

  if x < 0 then x = 0 elseif x + w > sw then x = sw - w end
  if y < 0 then y = 0 elseif y + h > sh then y = sh - h end

  J.db.totemX, J.db.totemY = floor(x + 0.5), floor(y + 0.5)
end

local function LockTotemBar()
  local bar = MultiCastActionBarFrame
  if not bar or bar.JUI_locking then return end
  if InCombatLockdown and InCombatLockdown() then return end

  bar.JUI_locking = true
  if J.db and J.db.totemBar == false then
    if not state.totemHider then
      state.totemHider = CreateFrame("Frame", "JunkieTotemHider", UIParent)
      state.totemHider:Hide()
    end
    bar:SetParent(state.totemHider)
  else
    if bar:GetParent() ~= UIParent then bar:SetParent(UIParent) end
    if J.db and J.db.totemMoved then
      ClampTotem()
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", J.db.totemX or 0, J.db.totemY or 0)
    elseif J.barHolder and state.totemX then
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", J.barHolder, "BOTTOMLEFT", state.totemX, state.totemY)
    end
  end
  bar.JUI_locking = false

  if not state.totemHooked then
    state.totemHooked = true
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("UPDATE_MULTI_CAST_ACTIONBAR")
    watcher:SetScript("OnEvent", LockTotemBar)
  end
end
J.LockTotemBar = LockTotemBar

-- 13 -- Init ------------------------------------------------------------------
-- The first stance change and the first spell drag of a session used to stall
-- the client: Blizzard creates the bonus page icons, the stance button art, the
-- empty-slot grid artwork and our backdrops in one single frame. All of it is
-- prepared once after login, a few jobs per frame, so login stays smooth.
-- Nothing here runs again during play.
local function PrewarmStancePages()
  if J.stanceWarmed then return end
  J.stanceWarmed = true

  local cache = CreateFrame("Frame", nil, UIParent)
  cache:Hide()
  local tex = cache:CreateTexture(nil, "BACKGROUND")

  local work = {}
  for i = 1, 12 do work[#work + 1] = { "skin", _G["BonusActionButton" .. i] } end
  for i = 1, 10 do work[#work + 1] = { "skin", _G["ShapeshiftButton" .. i] } end
  for i = 1, 10 do work[#work + 1] = { "skin", _G["PetActionButton" .. i] } end
  for _, p in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do work[#work + 1] = { "skin", _G[p .. i] } end
  end
  -- Drag and empty-slot artwork: Blizzard loads these the first time a spell
  -- leaves a slot, which is exactly the frame that hitched.
  for _, path in ipairs({
    "Interface\\Buttons\\UI-Quickslot",
    "Interface\\Buttons\\UI-Quickslot2",
    "Interface\\Buttons\\UI-Quickslot-Depress",
    "Interface\\Buttons\\ButtonHilight-Square",
    "Interface\\Buttons\\CheckButtonHilight",
    "Interface\\Buttons\\UI-QuickslotRed",
  }) do
    work[#work + 1] = { "tex", path }
  end
  -- All action slots: a drag refreshes every bar at once, so any icon missing
  -- from the texture cache costs a stall.
  for slot = 1, 120 do work[#work + 1] = { "action", slot } end
  for i = 1, 10 do work[#work + 1] = { "form", i } end

  local index = 1
  cache:SetScript("OnUpdate", function(self)
    local budget = 8
    while budget > 0 and index <= #work do
      local job = work[index]
      index = index + 1
      budget = budget - 1
      local kind = job[1]
      if kind == "skin" then
        if job[2] then SkinButton(job[2]) end
      elseif kind == "tex" then
        tex:SetTexture(job[2])
      elseif kind == "action" then
        local path = GetActionTexture and GetActionTexture(job[2])
        if path then tex:SetTexture(path) end
      else
        local path = GetShapeshiftFormInfo and GetShapeshiftFormInfo(job[2])
        if path then tex:SetTexture(path) end
      end
    end
    if index > #work then
      self:SetScript("OnUpdate", nil)
      self:Hide()
      -- Release the queue; nothing needs it after the warmup.
      work, tex = nil, nil
    end
  end)
  cache:Show()
end

-- "Always Show ActionBars": forced on and locked, so empty slots keep their
-- background and border instead of disappearing.
local function LockAlwaysShowOption()
  local cb = _G["InterfaceOptionsCombatPanelAlwaysShowActionBars"]
  if not cb then return end
  if cb.SetChecked then cb:SetChecked(true) end
  if cb.Disable then cb:Disable() end
  local label = _G["InterfaceOptionsCombatPanelAlwaysShowActionBarsText"]
  if label then label:SetTextColor(0.5, 0.5, 0.5) end
end

local function EnforceAlwaysShow()
  if InCombatLockdown() then return end
  if GetCVar("alwaysShowActionBars") ~= "1" then
    SetCVar("alwaysShowActionBars", "1")
  end
  LockAlwaysShowOption()
end

J:AddModule(function()
  -- Only touch the bar toggles if they are not already the way we need them;
  -- forcing them on every login taints Blizzard's bar visibility state.
  local b1, b2, b3, b4 = GetActionBarToggles()
  if not (b1 and b2 and b3 and b4) then
    SetActionBarToggles(1, 1, 1, 1, nil)
  end

  EnforceAlwaysShow()

  local cvars = CreateFrame("Frame")
  cvars:RegisterEvent("CVAR_UPDATE")
  cvars:RegisterEvent("PLAYER_ENTERING_WORLD")
  cvars:RegisterEvent("PLAYER_REGEN_ENABLED")
  cvars:SetScript("OnEvent", function(_, event, cvar)
    if event == "CVAR_UPDATE" and cvar and cvar ~= "ALWAYS_SHOW_MULTIBARS" then return end
    EnforceAlwaysShow()
  end)

  if InterfaceOptionsFrame then
    InterfaceOptionsFrame:HookScript("OnShow", LockAlwaysShowOption)
  end

  StripBlizzardArt()
  HookBagUpdates()

  -- Catch late frame creation by Blizzard/addons. The guarded frame hooks and
  -- Blizzard function hooks above handle all subsequent updates directly.
  local bagWatch = CreateFrame("Frame")
  bagWatch:RegisterEvent("PLAYER_LOGIN")
  bagWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
  bagWatch:RegisterEvent("BAG_UPDATE")
  bagWatch:RegisterEvent("KNOWN_CURRENCY_TYPES_UPDATE")
  bagWatch:RegisterEvent("ADDON_LOADED")
  bagWatch:RegisterEvent("UPDATE_INVENTORY_ALERTS")
  bagWatch:SetScript("OnEvent", StripBlizzardArt)


  SetupMicroMenu()

  J.barHolder = CreateFrame("Frame", "JunkieBarHolder", UIParent)
  SetupBar1Visibility()
  ApplyLayout()

  for _, n in ipairs(MOUSE_OFF_FRAMES) do
    local f = _G[n]
    if f and f.EnableMouse then f:EnableMouse(false) end
  end

  -- Binding and micro-menu maintenance is event driven. There is deliberately
  -- no actionbar watchdog and no global-table scan running during play.
  local bindings = CreateFrame("Frame")
  bindings:RegisterEvent("UPDATE_BINDINGS")
  bindings:RegisterEvent("PLAYER_ENTERING_WORLD")
  bindings:SetScript("OnEvent", function(_, event)
    J:RefreshBar1Keys()
    if event == "PLAYER_ENTERING_WORLD" then
      -- Scan the global table once per session, not on every zone load.
      if not state.microScanned then ScanMicro() end
      PrewarmStancePages()
    end
    ApplyMicroMenu()
  end)

  -- Blizzard may try to restore anchors. Only rebuild when a layout pass was
  -- actually deferred by combat; a full relayout after every fight caused a
  -- noticeable hitch when leaving combat.
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("UNIT_PET")
  events:RegisterEvent("PET_BAR_UPDATE")
  events:SetScript("OnEvent", function(_, event, unit)
    -- UNIT_PET fires for every raid member's pet. Only our own pet can move
    -- the pet bar, so everyone else's summons are dropped immediately.
    if event == "UNIT_PET" and unit ~= "player" and unit ~= "pet" then return end
    if state.layoutPending then ApplyLayout() end
    if event == "PLAYER_ENTERING_WORLD" then
      StripBlizzardArt()
      -- Short, self-terminating re-check so the stance column ends up correct
      -- straight after login instead of only after opening the options panel.
      StartStanceSettle()
    end
    -- A stance pass deferred by combat is redone here, forced, so the bar never
    -- stays in Blizzard's own (over-sized) placement after a fight.
    if state.stancePending and J.db and J.db.stanceBar then PlaceStanceBar(nil, true) end
    -- Blizzard re-anchors the pet buttons when a pet is summoned or the bar
    -- refreshes, so the row is re-placed on those events as well.
    PlacePetBar()
  end)


  if hooksecurefunc then
    -- ActionButton_ShowGrid/HideGrid both call ActionButton_Update themselves,
    -- so this single hook covers action, page and grid changes without
    -- skinning every button twice on the first drag of a session.
    hooksecurefunc("ActionButton_Update", SkinButton)
    -- Range tint: piggybacks on Blizzard's own usable refresh (see above).
    if ActionButton_UpdateUsable then
      hooksecurefunc("ActionButton_UpdateUsable", UpdateRangeTint)
      local rangeEvents = CreateFrame("Frame")
      rangeEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
      rangeEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
      rangeEvents:SetScript("OnEvent", RefreshRangeAll)
    end
    if ShapeshiftBar_Update then
      hooksecurefunc("ShapeshiftBar_Update", function()
        if J.db and J.db.stanceBar then PlaceStanceBar() end
      end)
    end
  end

  J.ApplyCooldownText()
  J.ApplyMacroText()
  ApplyKeyPressDown()
end)

-- Totem bar anchor: optional mover + show/hide toggle (mirrors the quest
-- tracker mover). Everything runs on demand: no OnUpdate and no extra hooks.
J:AddModule(function()
  local mover = J:CreateMover("JunkieTotemMover", 240, 26,
    "|cffde7230Drag: Totem bar|r")

  local function CurrentPos()
    local bar = MultiCastActionBarFrame
    if J.db.totemMoved or not bar then
      return tonumber(J.db.totemX) or 0, tonumber(J.db.totemY) or 0
    end
    local scale = UIParent:GetEffectiveScale()
    if not scale or scale == 0 then scale = 1 end
    local mul = bar:GetEffectiveScale() / scale
    return floor((bar:GetLeft() or 0) * mul + 0.5), floor((bar:GetBottom() or 0) * mul + 0.5)
  end

  local function SyncMover()
    local x, y = CurrentPos()
    mover:ClearAllPoints()
    mover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
  end

  mover:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left, bottom = J:MoverPos(self)
    J.db.totemX = floor(left + 0.5)
    J.db.totemY = floor(bottom + 0.5)
    J.db.totemMoved = true
    ClampTotem()
    SyncMover()
    LockTotemBar()
  end)

  function J:SetTotemUnlocked(on)
    J.db.totemUnlocked = on and true or false
    if J.db.totemUnlocked then
      SyncMover()
      mover:Show()
    else
      mover:Hide()
    end
  end

  function J:UpdateTotemBar()
    LockTotemBar()
    if J.db.totemUnlocked then SyncMover() end
  end

  J:SetTotemUnlocked(J.db.totemUnlocked)
  J:UpdateTotemBar()
end)
