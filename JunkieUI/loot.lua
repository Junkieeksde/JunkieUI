--[[---------------------------------------------------------------------------
  JunkieUI - Group loot rolls

  Blizzard's four GroupLootFrames are stacked into one movable block. The
  frames are unprotected, so they are anchored whenever they show, in combat
  included, and the anchor is locked against Blizzard's own re-layout passes.
-----------------------------------------------------------------------------]]

local J = JunkieUI

-- ---------------------------------------------------------------------------
-- 1. Upvalues and constants
-- ---------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local floor = math.floor

local ROLL_W, ROLL_H = 328, 79   -- one Blizzard GroupLootFrame
local ROLL_STEP = 81             -- vertical distance between two of them
local ROLL_COUNT = 4
local BLOCK_H = ROLL_STEP * ROLL_COUNT - 2   -- 322, the original block height
local MOVER_H = 26
local MOVER_GAP = 4

J:AddModule(function()
  local holder = CreateFrame("Frame", "JunkieLootRollHolder", UIParent)
  holder:SetSize(ROLL_W, BLOCK_H)
  holder:SetPoint("BOTTOM", UIParent, "BOTTOM", J.db.lootX, J.db.lootY)

  local mover = J:CreateMover("JunkieLootRollMover", ROLL_W, MOVER_H,
    "|cffde7230Drag: Loot rolls 1-4|r", J.MOVER_BORDER_ALT)

  -- Placeholder block so the position can be adjusted without live loot rolls.
  local placeholder = CreateFrame("Frame", "JunkieLootRollPlaceholder", holder)
  placeholder:SetAllPoints(holder)
  placeholder:SetFrameStrata("DIALOG")
  J:Plate(placeholder, 0.1, 0.1, 0.1, 0.55, J.MOVER_BORDER_ALT)
  placeholder:Hide()

  for i = 1, ROLL_COUNT do
    local slot = CreateFrame("Frame", nil, placeholder)
    slot:SetSize(ROLL_W, ROLL_H)
    slot:SetPoint("BOTTOM", placeholder, "BOTTOM", 0, (i - 1) * ROLL_STEP)
    J:Plate(slot, 0.09, 0.09, 0.09, 0.8, { 0, 0, 0 })
    local t = J:Text(slot, 11, "CENTER")
    t:SetPoint("CENTER")
    t:SetText("|cffde7230Loot roll " .. i .. "|r")
  end

  -- One placement pass for the holder, the mover and the four frames.
  --
  -- GroupLootFrames are plain (unprotected) frames, so they can be re-anchored
  -- in combat. Blizzard re-lays them out on its own (UIParent_ManageFramePositions
  -- runs when combat ends, when the tracker collapses, when an alert frame
  -- appears), which is exactly what made the block jump after the first fight.
  -- The anchor is therefore hard-locked per frame: any foreign SetPoint pulls
  -- it straight back, guarded by a flag so our own call cannot recurse.
  local lastX, lastY
  local function AnchorRoll(frame, i)
    if frame.JUI_moving then return end
    frame.JUI_moving = true
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", holder, "BOTTOM", 0, (i - 1) * ROLL_STEP)
    frame.JUI_moving = false
  end

  local function Reposition()
    local x, y = J.db.lootX, J.db.lootY
    if x ~= lastX or y ~= lastY then
      lastX, lastY = x, y
      holder:ClearAllPoints()
      holder:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
      mover:ClearAllPoints()
      mover:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y + BLOCK_H + MOVER_GAP)
    end
    for i = 1, ROLL_COUNT do
      local frame = _G["GroupLootFrame" .. i]
      if frame then AnchorRoll(frame, i) end
    end
  end

  for i = 1, ROLL_COUNT do
    local frame = _G["GroupLootFrame" .. i]
    if frame then
      if frame.HookScript then
        frame:HookScript("OnShow", function(self) AnchorRoll(self, i) end)
      end
      if hooksecurefunc then
        hooksecurefunc(frame, "SetPoint", function(self)
          if self.JUI_moving then return end
          AnchorRoll(self, i)
        end)
      end
    end
  end

  mover:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left, bottom = J:MoverPos(self)
    J.db.lootX = floor(left + self:GetWidth() * (self:GetEffectiveScale() / UIParent:GetEffectiveScale()) / 2 - UIParent:GetWidth() / 2 + 0.5)
    J.db.lootY = floor(bottom - BLOCK_H - MOVER_GAP + 0.5)
    Reposition()
  end)

  function J:SetLootUnlocked(on)
    J.db.lootUnlocked = on and true or false
    Reposition()
    if J.db.lootUnlocked then
      mover:Show()
      placeholder:Show()
    else
      mover:Hide()
      placeholder:Hide()
    end
  end

  J:SetLootUnlocked(J.db.lootUnlocked)

  local events = CreateFrame("Frame")
  events:RegisterEvent("START_LOOT_ROLL")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:SetScript("OnEvent", Reposition)

  if hooksecurefunc then
    if GroupLootFrame_OpenNewFrame then
      hooksecurefunc("GroupLootFrame_OpenNewFrame", Reposition)
    end
    -- Blizzard's global layout pass is the one that used to win the fight.
    if UIParent_ManageFramePositions then
      hooksecurefunc("UIParent_ManageFramePositions", Reposition)
    end
  end

end)

