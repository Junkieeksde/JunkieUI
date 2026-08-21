-- Player / target castbars
-- Custom bars replacing Blizzard's. The OnUpdate script is only attached while
-- a cast is actually running, so there is no idle loop.
local J = JunkieUI

-- Upvalues: the OnUpdate below runs every frame while a cast is up, so the
-- globals it touches are resolved once at load instead of per frame.
local CreateFrame     = CreateFrame
local UIParent        = UIParent
local GetTime         = GetTime
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local format          = string.format

local PLAYER_W, PLAYER_H = 325, 33   -- total width, icon included (10% larger)
local SEBBY_PLAYER_H = 30            -- docked bar keeps the original height
local TARGET_W, TARGET_H = 250, 30   -- matches the target unit frame width
local SEBBY_TARGET_W, SEBBY_TARGET_H = 380, 43

local SEBBY_TARGET_TOP = 300         -- distance from the top of the screen

local castTimeText = {}
local function FormatTime(v)
  if v < 0 then v = 0 end
  local tenth = math.floor(v * 10 + 0.5)
  local text = castTimeText[tenth]
  if not text then
    text = math.floor(tenth / 10) .. "." .. (tenth % 10)
    castTimeText[tenth] = text
  end
  return text
end

-- Build ---------------------------------------------------------------------
local function CreateCastbar(name, unit, width, height)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(width, height)
  f:SetFrameStrata("MEDIUM")
  f.unit = unit
  f:Hide()

  -- Icon sits flush on the left, inside the total width.
  local iconHolder = CreateFrame("Frame", nil, f)
  iconHolder:SetSize(height, height)
  iconHolder:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  J:SkinUnit(iconHolder)
  local icon = iconHolder:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.icon = icon

  local holder = CreateFrame("Frame", nil, f)
  holder:SetPoint("TOPLEFT", iconHolder, "TOPRIGHT", 0, 0)
  holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  J:SkinUnit(holder)

  local bar = CreateFrame("StatusBar", nil, holder)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("BOTTOMRIGHT", -1, 1)
  J:RegisterBar(bar)
  bar:SetStatusBarColor(0.871, 0.447, 0.188)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  f.bar = bar

  local text = J:Text(bar, height >= 26 and 12 or 10, "LEFT")
  text:SetPoint("LEFT", bar, "LEFT", 4, 0)
  text:SetPoint("RIGHT", bar, "RIGHT", -38, 0)
  f.text = text

  local timer = J:Text(bar, height >= 26 and 12 or 10, "RIGHT")
  timer:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  f.timer = timer

  f.iconHolder = iconHolder
  function f:SetBarSize(w, h)
    self:SetSize(w, h)
    self.iconHolder:SetSize(h, h)
  end

  return f
end

-- Driver --------------------------------------------------------------------
local function OnUpdate(self, elapsed)
  local now = GetTime()
  local value
  if self.channeling then
    value = self.endTime - now
    if value <= 0 then return self:StopCast() end
  else
    value = now - self.startTime
    if value >= self.duration then
      self.bar:SetValue(self.duration)
      return self:StopCast()
    end
  end
  self.bar:SetValue(value)

  -- Only the text is throttled; the bar itself runs at full framerate.
  self.tt = (self.tt or 0) + elapsed
  if self.tt >= 0.1 then
    self.tt = 0
    local remaining = self.channeling and value or (self.duration - value)
    -- Only push the string when the printed tenth actually changed.
    local txt = FormatTime(remaining)
    if self.JUI_shownTimer ~= txt then
      self.JUI_shownTimer = txt
      self.timer:SetText(txt)
    end
  end
end

local function StopCast(self)
  self:SetScript("OnUpdate", nil)
  self:Hide()
  self.casting, self.channeling = false, false
  self.activeCastID = nil
end

local function StartCast(self, channel)
  local unit = self.unit
  local name, _, text, texture, startTime, endTime, _, _, notInterruptible
  if channel then
    name, _, text, texture, startTime, endTime, _, notInterruptible = UnitChannelInfo(unit)
  else
    name, _, text, texture, startTime, endTime, _, _, notInterruptible = UnitCastingInfo(unit)
  end
  if not name then return StopCast(self) end

  self.startTime = startTime / 1000
  self.endTime = endTime / 1000
  self.duration = self.endTime - self.startTime
  if self.duration <= 0 then self.duration = 0.001 end
  self.channeling = channel and true or false
  self.casting = not self.channeling

  if self.JUI_shownIcon ~= texture then
    self.JUI_shownIcon = texture
    self.icon:SetTexture(texture)
  end
  local label = text or name
  if self.JUI_shownText ~= label then
    self.JUI_shownText = label
    self.text:SetText(label)
  end
  if channel then
    self.bar:SetMinMaxValues(0, self.duration)
    self.bar:SetValue(self.endTime - GetTime())
  else
    self.bar:SetMinMaxValues(0, self.duration)
    self.bar:SetValue(GetTime() - self.startTime)
  end
  if notInterruptible then
    self.bar:SetStatusBarColor(0.55, 0.55, 0.55)
  else
    self.bar:SetStatusBarColor(0.871, 0.447, 0.188)
  end
  self.tt = 0.1
  self:Show()
  self:SetScript("OnUpdate", OnUpdate)
end

local function Refresh(self)
  if not self.enabled or not UnitExists(self.unit) then return StopCast(self) end
  if UnitCastingInfo(self.unit) then
    StartCast(self, false)
  elseif UnitChannelInfo(self.unit) then
    StartCast(self, true)
  else
    StopCast(self)
  end
end

-- Spam protection: every cast attempt carries a unique lineID (4th argument on
-- the spellcast events). Extra key presses while a cast is running fire
-- UNIT_SPELLCAST_FAILED for a *different* lineID, which used to wipe the bar.
-- Only events carrying the lineID of the running cast may stop it.
local function OnEvent(self, event, unit, spellName, spellRank, lineID)
  if not self.enabled then return StopCast(self) end
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    return Refresh(self)

  end
  if unit ~= self.unit then return end

  if event == "UNIT_SPELLCAST_START" then
    self.activeCastID = lineID
    StartCast(self, false)
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    self.activeCastID = nil          -- channels do not carry a cast lineID
    StartCast(self, true)
  elseif event == "UNIT_SPELLCAST_DELAYED" then
    if self.casting then StartCast(self, false) end
  elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
    if self.channeling then StartCast(self, true) end
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if self.channeling then StopCast(self) end
  elseif event == "UNIT_SPELLCAST_FAILED"
      or event == "UNIT_SPELLCAST_INTERRUPTED"
      or event == "UNIT_SPELLCAST_STOP"
      or event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- Ignore anything belonging to another cast attempt (key spam).
    if lineID and self.activeCastID and lineID ~= self.activeCastID then return end
    -- No tracked cast (target bar, channel, or a bar restored by Refresh):
    -- ask the API what is actually running instead of blindly hiding.
    if not self.activeCastID then return Refresh(self) end
    StopCast(self)
  else
    StopCast(self)
  end
end

local function Register(f)
  f.StopCast = StopCast
  f.Refresh = Refresh
  f:RegisterEvent("UNIT_SPELLCAST_START")
  f:RegisterEvent("UNIT_SPELLCAST_STOP")
  f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  f:RegisterEvent("UNIT_SPELLCAST_FAILED")
  f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
  f:RegisterEvent("UNIT_SPELLCAST_DELAYED")
  f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
  f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
  f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  if f.unit == "target" then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
  f:SetScript("OnEvent", OnEvent)
end

-- Blizzard bars --------------------------------------------------------------
local blizzHooked = false
local function ApplyBlizzard()
  local show = J.db.blizzardCastbars and true or false
  local pb = _G["CastingBarFrame"]
  local tb = _G["TargetFrameSpellBar"]

  if pb then
    if show then
      pb:SetAlpha(1)
      CastingBarFrame_OnLoad(pb, "player", true, false)
    else
      pb:UnregisterAllEvents()
      pb:Hide()
      pb:SetAlpha(0)
    end
  end
  if tb then
    if show then
      tb:SetAlpha(1)
      CastingBarFrame_OnLoad(tb, "target", false, true)
    else
      tb:UnregisterAllEvents()
      tb:Hide()
      tb:SetAlpha(0)
    end
  end

  if not blizzHooked then
    blizzHooked = true
    local function Guard(frame)
      if not J.db.blizzardCastbars and frame:IsShown() then frame:Hide() end
    end
    if pb then pb:HookScript("OnShow", Guard) end
    if tb then tb:HookScript("OnShow", Guard) end
  end
end

J:AddModule(function()
  -- Blizzard's target spellbar reposition routine errors once the frame has
  -- been touched, so it is neutralised regardless of the toggles.
  if Target_Spellbar_AdjustPosition then
    Target_Spellbar_AdjustPosition = function() end
  end

  local playerBar = CreateCastbar("JunkiePlayerCastbar", "player", PLAYER_W, PLAYER_H)
  local targetBar = CreateCastbar("JunkieTargetCastbar", "target", TARGET_W, TARGET_H)
  J.playerCastbar, J.targetCastbar = playerBar, targetBar

  -- Centered, 30px above the pet bar row. Re-run on every bar layout change.
  -- In the "Sebby Layout" the bar instead docks flush on top of the stack and
  -- matches the outer width of the bar block (background plate included, so it
  -- lines up pixel perfect with what is actually drawn on screen).
  -- The cooldown manager can claim the player castbar: it then sits 1px above
  -- the manager's topmost bar and copies its width.
  function J:DockPlayerCastbar(anchorFrame, width, height)
    J.cdCastbarAnchor = anchorFrame
    J.cdCastbarWidth = tonumber(width) or 0
    J.cdCastbarHeight = tonumber(height) or nil
    J:AnchorPlayerCastbar()
  end

  function J:AnchorPlayerCastbar()
    playerBar:ClearAllPoints()
    if J.cdCastbarAnchor and (J.cdCastbarWidth or 0) > 0 then
      playerBar:SetBarSize(J.cdCastbarWidth, J.cdCastbarHeight or PLAYER_H)
      playerBar:SetPoint("BOTTOM", J.cdCastbarAnchor, "TOP", 0, 1)
      return
    end
    if J.barLayoutMode == "sebby" and J.barHolder then
      local pad = (J.db and J.db.barBackground == false) and 0 or 2
      playerBar:SetBarSize((J.barTopW or PLAYER_W) + pad * 2, SEBBY_PLAYER_H)
      playerBar:SetPoint("BOTTOMLEFT", J.barHolder, "TOPLEFT", -pad, pad)
    elseif J.barHolder and J.petTopY then
      playerBar:SetBarSize(PLAYER_W, PLAYER_H)
      playerBar:SetPoint("BOTTOM", J.barHolder, "BOTTOM", 0, J.petTopY + 80)
    else
      playerBar:SetBarSize(PLAYER_W, PLAYER_H)
      playerBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    end

  end

  J:AnchorPlayerCastbar()
  Register(playerBar)
  Register(targetBar)

  -- Target bar follows the debuff rows, same anchor logic Blizzard's bar used.
  function J:AnchorTargetCastbar(drop)
    if drop then targetBar.jdrop = drop end
    targetBar:ClearAllPoints()
    if J.barLayoutMode == "sebby" then
      -- Big centered enemy castbar, independent of the target frame.
      targetBar:SetBarSize(SEBBY_TARGET_W, SEBBY_TARGET_H)
      targetBar:SetPoint("TOP", UIParent, "TOP", 0, -SEBBY_TARGET_TOP)
      return
    end
    targetBar:SetBarSize(TARGET_W, TARGET_H)
    local anchor = _G["JunkieTargetFrame"]
    if not anchor then return end
    targetBar:SetPoint("TOP", anchor, "BOTTOM", 0, -(targetBar.jdrop or 6))
  end
  J:AnchorTargetCastbar(6)

  function J:UpdateCastbars()
    playerBar.enabled = J.db.playerCastbar ~= false
    targetBar.enabled = J.db.targetCastbar ~= false
    Refresh(playerBar)
    Refresh(targetBar)
    ApplyBlizzard()
  end
  J:UpdateCastbars()
end)
