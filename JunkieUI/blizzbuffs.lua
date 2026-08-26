--[[---------------------------------------------------------------------------
  JunkieUI - Blizzard aura reskin

  The player's buffs and debuffs are Blizzard's own C-driven frames. JunkieUI
  does not rebuild them in Lua; the stock frame is only re-dressed:
    * square icons (cropped edges, 1px dark border, flat backdrop)
    * JunkieUI font on the duration / stack text
    * the whole chain (ConsolidatedBuffs, BuffFrame, TemporaryEnchantFrame) is
      docked to the minimap, so it tracks minimap size and position changes
    * Blizzard's own per-button duration script and warning pulse are left
      completely untouched

  Cost: one UNIT_AURA event handler, no ticker and no hook on Blizzard's
  per-button aura path. The skin work for a button runs once and is then
  flagged; after that only a debuff colour pass runs, once per aura change.
-------------------------------------------------------------------------------]]

local J = JunkieUI

local _G            = _G
local CreateFrame   = CreateFrame
local hooksecurefunc = hooksecurefunc

local BORDER = J:PixelBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  edgeSize = 1,
})

local DEBUFF_COLORS = {
  Magic   = { 0.20, 0.55, 1.00 },
  Curse   = { 0.60, 0.25, 0.95 },
  Disease = { 0.60, 0.40, 0.20 },
  Poison  = { 0.20, 0.75, 0.25 },
}

local function SkinButton(b)
  if not b or b.JUI_skinned then return end
  b.JUI_skinned = true

  local name = b:GetName()
  local icon = _G[name .. "Icon"]
  local border = _G[name .. "Border"]
  local duration = _G[name .. "Duration"]
  local count = _G[name .. "Count"]

  if border then border:SetTexture(nil) end

  if icon then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  end

  local bg = CreateFrame("Frame", nil, b)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  bg:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
  bg:SetBackdrop(BORDER)
  bg:SetBackdropColor(0.086, 0.086, 0.086, 1)
  bg:SetBackdropBorderColor(0, 0, 0, 1)
  b.JUI_bg = bg

  if duration then
    duration:SetFont(J.font, 12, "OUTLINE")
    duration:SetShadowOffset(0, 0)
    duration:ClearAllPoints()
    duration:SetPoint("TOP", b, "BOTTOM", 0, -1)
  end
  if count then
    count:SetFont(J.font, 12, "OUTLINE")
    count:SetShadowOffset(0, 0)
    count:ClearAllPoints()
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  end

end

-- Debuff border colour: Blizzard paints its own texture, so the colour is put
-- on our backdrop edge instead. Only runs when Blizzard repaints the button.
local function ColorDebuff(b, dispelType)
  local bg = b and b.JUI_bg
  if not bg then return end
  -- Only write when the type actually changed: Blizzard repaints a button on
  -- every aura update, and a redundant backdrop write is what turns the stock
  -- (very short) icon swap into a visible flicker.
  if b.JUI_dtype == (dispelType or false) then return end
  b.JUI_dtype = dispelType or false
  local c = dispelType and DEBUFF_COLORS[dispelType]
  if c then
    bg:SetBackdropBorderColor(c[1], c[2], c[3], 1)
  else
    bg:SetBackdropBorderColor(0.70, 0.15, 0.15, 1)
  end
end

function J:SkinBlizzardAuras()
  if self.blizzAurasSkinned then return end
  self.blizzAurasSkinned = true

  -- Buffs / debuffs: driven by UNIT_AURA instead of a hook on
  -- AuraButton_Update. A hooksecurefunc wrapper would sit in front of every
  -- single button repaint (and Blizzard's own work inside it is then billed
  -- to JunkieUI). One event pass over the visible buttons does the exact same
  -- job with one call per aura change instead of one call per button.
  local auraEvents = CreateFrame("Frame")
  auraEvents:RegisterEvent("UNIT_AURA")
  auraEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  auraEvents:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end

    for i = 1, BUFF_MAX_DISPLAY or 32 do
      local b = _G["BuffButton" .. i]
      if not b or not b:IsShown() then break end
      if not b.JUI_skinned then SkinButton(b) end
      if b.JUI_bg and b.JUI_dtype ~= false then
        b.JUI_dtype = false
        b.JUI_bg:SetBackdropBorderColor(0, 0, 0, 1)
      end
    end

    for i = 1, DEBUFF_MAX_DISPLAY or 16 do
      local b = _G["DebuffButton" .. i]
      if not b or not b:IsShown() then break end
      if not b.JUI_skinned then SkinButton(b) end
      local _, _, _, _, dispelType = UnitDebuff("player", i)
      ColorDebuff(b, dispelType)
    end
  end)


  -- Temporary weapon enchants live outside AuraButton_Update.
  for i = 1, 3 do
    local b = _G["TempEnchant" .. i]
    if b then
      SkinButton(b)
      b:HookScript("OnShow", SkinButton)
    end
  end

  -- Blizzard does not use BuffFrame as the only root. ConsolidatedBuffs is the
  -- real reference point for debuffs, temporary enchants and several buff-row
  -- paths. Moving BuffFrame alone therefore leaves most visible icons at the
  -- stock UIParent position. Dock the complete stock anchor chain instead.
  -- Once ConsolidatedBuffs is attached to Minimap's TOPLEFT, normal frame
  -- anchoring follows every map size/position change without polling.
  local function Anchor()
    local f = _G["BuffFrame"]
    local consolidated = _G["ConsolidatedBuffs"]
    if not f or not consolidated then return end

    local scale = consolidated:GetScale()
    if not scale or scale <= 0 then scale = 1 end
    local gap = 6 / scale

    consolidated:ClearAllPoints()
    consolidated:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -gap, 0)

    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", consolidated, "TOPRIGHT", 0, 0)

    -- Preserve Blizzard's own chain. Its update code may re-apply this exact
    -- relationship when enchants or consolidated buffs appear/disappear.
    local te = _G["TemporaryEnchantFrame"]
    if te then
      te:ClearAllPoints()
      te:SetPoint("TOPRIGHT", consolidated, "TOPLEFT", -6, 0)
    end
  end
  J.AnchorBlizzardAuras = Anchor
  Anchor()
  if UIParent_ManageFramePositions then
    hooksecurefunc("UIParent_ManageFramePositions", Anchor)
  end
  if BuffFrame_UpdateAllBuffAnchors then
    hooksecurefunc("BuffFrame_UpdateAllBuffAnchors", Anchor)
  end

  -- These hooks only restore the chain if another addon or Blizzard's layout
  -- code has replaced it. Relative anchors already follow map resizing/moving.
  hooksecurefunc(Minimap, "SetSize", Anchor)
  hooksecurefunc(Minimap, "SetWidth", Anchor)
  hooksecurefunc(Minimap, "SetHeight", Anchor)
  hooksecurefunc(Minimap, "SetPoint", Anchor)
end

-- Size: Blizzard's icons are a fixed 30px, so the slider scales the frame.
-- One SetScale call, never per frame.
function J:ApplyBuffScale()
  local f = _G["BuffFrame"]
  if not f then return end
  local pct = tonumber(self.db and self.db.buffScale) or 100
  if pct < 70 then pct = 70 elseif pct > 150 then pct = 150 end
  f:SetScale(pct / 100)
  local te = _G["TemporaryEnchantFrame"]
  if te then te:SetScale(pct / 100) end
  if self.AnchorBlizzardAuras then self.AnchorBlizzardAuras() end
end

J:AddModule(function()
  J:SkinBlizzardAuras()
  J:ApplyBuffScale()
end)
