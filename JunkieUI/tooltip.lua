-- Tooltip: fixed anchor or mouse follow
local J = JunkieUI

local anchor
local lastCursorX, lastCursorY

local function Position()
  if not J.db then return end
  if J.db.tooltipMouse then return end
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
end

local function FollowMouse()
  local scale = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  x, y = x / scale, y / scale
  if x == lastCursorX and y == lastCursorY then return end
  lastCursorX, lastCursorY = x, y
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 18, y + 18)
end

local function DefaultAnchor(tooltip, parent)
  if not J.db then return end
  if J.db.tooltipMouse then
    tooltip:SetOwner(parent, "ANCHOR_NONE")
    tooltip.jFollow = true
    FollowMouse()
  else
    tooltip:SetOwner(parent, "ANCHOR_NONE")
    tooltip.jFollow = nil
    Position()
  end
end

local function CreateAnchor()
  anchor = CreateFrame("Frame", "JunkieTooltipAnchor", UIParent)
  anchor:SetSize(180, 28)
  anchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
    J.db.tooltipX or -220, J.db.tooltipY or 220)
  anchor:SetFrameStrata("HIGH")
  anchor:SetMovable(true)
  anchor:EnableMouse(true)
  anchor:SetClampedToScreen(true)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  anchor:SetBackdropColor(0.055, 0.055, 0.055, 0.9)
  anchor:SetBackdropBorderColor(0.871, 0.447, 0.188, 1)

  local fs = anchor:CreateFontString(nil, "OVERLAY")
  fs:SetFont(J.font, 11)
  fs:SetPoint("CENTER")
  fs:SetText("Tooltip anchor")
  fs:SetTextColor(0.871, 0.447, 0.188)

  anchor:SetScript("OnDragStart", anchor.StartMoving)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x = self:GetRight() - UIParent:GetRight()
    local y = self:GetBottom() - UIParent:GetBottom()
    J.db.tooltipX, J.db.tooltipY = x, y
    self:ClearAllPoints()
    self:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, y)
  end)
  anchor:Hide()
end

function J:SetTooltipAnchorUnlocked(v)
  J.db.tooltipUnlocked = v
  if not anchor then return end
  if v then anchor:Show() else anchor:Hide() end
end

-- Spell / aura IDs ---------------------------------------------------------
-- Cache the left-hand font strings per tooltip so the safety scan below does
-- not build a new global lookup string for every line on every mouseover.
local lineCache = {}
local function Lines(tip)
  local lines = lineCache[tip]
  if not lines then
    lines = {}
    lineCache[tip] = lines
  end
  return lines
end

-- Resolving an id through GetSpellLink allocates a link string and runs a
-- pattern match. Spell names repeat constantly while hovering a bar, so the
-- result is memoised (false = no id available).
local idByName = {}
local function IDFromName(name)
  if not name then return nil end
  local cached = idByName[name]
  if cached ~= nil then return cached or nil end
  local link = GetSpellLink(name)
  local id = link and string.match(link, "spell:(%d+)")
  id = id and tonumber(id) or false
  idByName[name] = id
  return id or nil
end

local function AddID(tip, label, id)
  if not id or not tip or not J.db or not J.db.tooltipIDs then return end
  if tip.jID == id then return end
  if not tip:IsShown() then return end
  -- Some servers ship their own tooltip mods that walk every line after the
  -- tooltip is built. Never leave a line with nil text behind.
  local name = tip:GetName()
  if name then
    local lines = Lines(tip)
    local n = tip:NumLines() or 0
    for i = 1, n do
      local l = lines[i]
      if not l then
        l = _G[name .. "TextLeft" .. i]
        lines[i] = l
      end
      if l and l:GetText() == nil then return end
    end
  end
  tip.jID = id
  tip:AddDoubleLine(label, tostring(id), 0.55, 0.53, 0.48, 0.871, 0.447, 0.188)
  tip:Show()
end


-- Best effort id for a spell tooltip (GetSpell exists in 3.3.5 but the
-- id return is not reliable on every client, so fall back to the link).
local function SpellID(tip)
  if tip.GetSpell then
    local name, _, id = tip:GetSpell()
    if type(id) == "number" then return id end
    if name then return IDFromName(name) end
  end
  local text = _G[tip:GetName() .. "TextLeft1"]
  return IDFromName(text and text:GetText())
end


local function HookTip(tip)
  if not tip then return end
  tip:HookScript("OnTooltipCleared", function(self) self.jID = nil end)
  tip:HookScript("OnHide", function(self) self.jID = nil end)

  if tip.SetUnitAura then
    hooksecurefunc(tip, "SetUnitAura", function(self, unit, index, filter)
      local _, _, _, _, _, _, _, _, _, _, id = UnitAura(unit, index, filter)
      AddID(self, "Aura ID", id)
    end)
  end
  if tip.SetUnitBuff then
    hooksecurefunc(tip, "SetUnitBuff", function(self, unit, index, filter)
      local _, _, _, _, _, _, _, _, _, _, id = UnitBuff(unit, index, filter)
      AddID(self, "Aura ID", id)
    end)
  end
  if tip.SetUnitDebuff then
    hooksecurefunc(tip, "SetUnitDebuff", function(self, unit, index, filter)
      local _, _, _, _, _, _, _, _, _, _, id = UnitDebuff(unit, index, filter)
      AddID(self, "Aura ID", id)
    end)
  end
  -- No SetAction hook: the client (and some server tooltip mods) walk the
  -- tooltip lines during SetAction, so the ID line is added afterwards in
  -- ActionButton_SetTooltip instead (see below).


  if tip.SetHyperlink then
    hooksecurefunc(tip, "SetHyperlink", function(self, link)
      local id = link and string.match(link, "spell:(%d+)")
      AddID(self, "Spell ID", tonumber(id))
    end)
  end
  if tip:HasScript("OnTooltipSetSpell") then
    tip:HookScript("OnTooltipSetSpell", function(self)
      AddID(self, "Spell ID", SpellID(self))
    end)
  end
end

J:AddModule(function()
  CreateAnchor()
  if J.db.tooltipUnlocked then anchor:Show() end
  HookTip(GameTooltip)
  HookTip(ItemRefTooltip)

  -- Action buttons: add the spell ID after the client has finished building
  -- (and other mods have scanned) the tooltip.
  if type(ActionButton_SetTooltip) == "function" then
    hooksecurefunc("ActionButton_SetTooltip", function(button)
      if not button or not button.action then return end
      local kind, id = GetActionInfo(button.action)
      if kind == "spell" and type(id) == "number" and id > 0 then
        AddID(GameTooltip, "Spell ID", id)
      elseif kind == "macro" then
        local spell = GetMacroSpell and GetMacroSpell(id)
        local sid = spell and IDFromName(spell)
        if sid then AddID(GameTooltip, "Spell ID", sid) end
      end
    end)
  end


  hooksecurefunc("GameTooltip_SetDefaultAnchor", DefaultAnchor)

  GameTooltip:HookScript("OnUpdate", function(self, elapsed)
    if not self.jFollow or not J.db.tooltipMouse then return end
    self.jFollowElapsed = (self.jFollowElapsed or 0) + (elapsed or 0)
    if self.jFollowElapsed < 0.025 then return end
    self.jFollowElapsed = 0
    FollowMouse()
  end)

  GameTooltip:HookScript("OnHide", function(self)
    self.jFollow = nil
    self.jFollowElapsed = nil
    lastCursorX, lastCursorY = nil, nil
  end)
end)
