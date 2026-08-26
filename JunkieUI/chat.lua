--[[---------------------------------------------------------------------------
  JunkieUI - Chat

  Nothing but the dark backdrop behind ChatFrame1. Fonts, tabs, edit box,
  scroll buttons and the chat menu button are left exactly as Blizzard ships
  them.

  Cost: one frame created at load, zero hooks, zero loops.
-------------------------------------------------------------------------------]]
local J = JunkieUI

J:AddModule(function()
  local cf = ChatFrame1
  if not cf then return end

  local box = CreateFrame("Frame", "JunkieChatBox", UIParent)
  box:SetPoint("TOPLEFT", cf, "TOPLEFT", -6, 3)
  box:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 6, -6)
  box:SetFrameStrata("BACKGROUND")
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = J.PIXEL,
  })
  box:SetBackdropColor(0.086, 0.086, 0.086, 0.6)
  box:SetBackdropBorderColor(J.BORDER[1], J.BORDER[2], J.BORDER[3], 1)
end)
