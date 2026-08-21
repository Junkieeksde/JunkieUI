-- Custom XP bar: 5px, full width, top of screen
local J = JunkieUI

local HEIGHT = 5

J:AddModule(function()
  -- Kill Blizzard XP / reputation bars. They are reparented to a hidden frame
  -- instead of having their Show method replaced: these frames belong to
  -- MainMenuBar, so a replaced method would run our code inside Blizzard's bar
  -- routines and taint the action bars.
  local hider = CreateFrame("Frame", "JunkieXPHider", UIParent)
  hider:Hide()
  for _, f in ipairs({ MainMenuExpBar, ReputationWatchBar, MainMenuBarMaxLevelBar, ExhaustionTick }) do
    if f then
      f:UnregisterAllEvents()
      f:Hide()
      f:SetParent(hider)
    end
  end


  local bar = CreateFrame("Frame", "JunkieXPBar", UIParent)
  bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
  bar:SetHeight(HEIGHT)
  bar:SetFrameStrata("MEDIUM")
  bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  bar:SetBackdropColor(0.086, 0.086, 0.086, 1)
  bar:EnableMouse(true)

  local edge = bar:CreateTexture(nil, "OVERLAY")
  edge:SetTexture("Interface\\Buttons\\WHITE8X8")
  edge:SetVertexColor(0, 0, 0, 1)
  edge:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  edge:SetHeight(1)

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetTexture("Interface\\Buttons\\WHITE8X8")
  fill:SetVertexColor(0.58, 0.32, 0.88, 1)
  fill:SetDrawLayer("ARTWORK", 1)
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 1)

  local rest = bar:CreateTexture(nil, "ARTWORK")
  rest:SetTexture("Interface\\Buttons\\WHITE8X8")
  rest:SetVertexColor(0.35, 0.72, 1, 0.9)
  rest:SetDrawLayer("ARTWORK", 0)
  rest:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
  rest:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)

  local fillEdge = bar:CreateTexture(nil, "OVERLAY")
  fillEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
  fillEdge:SetVertexColor(0, 0, 0, 1)
  fillEdge:SetWidth(1)
  fillEdge:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
  fillEdge:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)

  local text = J:Text(bar, 10, "CENTER")
  text:SetPoint("TOP", bar, "BOTTOM", 0, -1)
  text:Hide()

  local shown = nil
  local function ApplyOffset(on)
    if shown == on then return end
    shown = on
    local y = on and -(HEIGHT + 3) or -3
    MinimapCluster:ClearAllPoints()
    MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -3, y)
  end

  local function Update()
    local maxed = UnitLevel("player") >= (MAX_PLAYER_LEVEL or 80)
    if maxed then
      bar:Hide()
      ApplyOffset(false)
      return
    end
    bar:Show()
    ApplyOffset(true)

    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not max or max == 0 then return end
    local w = bar:GetWidth()
    local pct = cur / max
    fill:SetWidth(math.max(0.01, w * pct))

    local exh = GetXPExhaustion()
    if exh and exh > 0 then
      rest:Show()
      local visibleRest = math.min(exh, max - cur)
      rest:SetWidth(math.max(0.01, w * (visibleRest / max)))
      text:SetText(string.format("%.1f%% | Rested: %.0f%%", pct * 100, (exh / max) * 100))
    else
      rest:Hide()
      text:SetText(string.format("%.1f%%", pct * 100))
    end
  end

  bar:SetScript("OnShow", Update)
  bar:SetScript("OnEnter", function(self)
    text:Show()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(COMBAT_XP_GAIN or "Experience")
    local cur, max = UnitXP("player"), UnitXPMax("player")
    GameTooltip:AddLine(string.format("%d / %d (%.1f%%)", cur, max, max > 0 and cur / max * 100 or 0), 1, 1, 1)
    local exh = GetXPExhaustion()
    if exh and exh > 0 then
      GameTooltip:AddLine(string.format("%s: %d (%.0f%%)", TUTORIAL_TITLE26 or "Rested", exh, (exh / max) * 100), 0.35, 0.72, 1)
    end
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function()
    text:Hide()
    GameTooltip:Hide()
  end)

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:RegisterEvent("PLAYER_XP_UPDATE")
  ev:RegisterEvent("PLAYER_LEVEL_UP")
  ev:RegisterEvent("UPDATE_EXHAUSTION")
  ev:SetScript("OnEvent", Update)
  Update()
end)
