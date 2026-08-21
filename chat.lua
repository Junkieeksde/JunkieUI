-- Simple chat box: #232323 backdrop, edit box directly above the chat
local J = JunkieUI

J:AddModule(function()
  local cf = ChatFrame1

  -- Backdrop box
  local box = CreateFrame("Frame", "JunkieChatBox", UIParent)
  box:SetPoint("TOPLEFT", cf, "TOPLEFT", -6, 3)
  box:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 6, -6)
  box:SetFrameStrata("BACKGROUND")
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  box:SetBackdropColor(0.086, 0.086, 0.086, 0.6)
  box:SetBackdropBorderColor(J.BORDER[1], J.BORDER[2], J.BORDER[3], 1)

  for i = 1, NUM_CHAT_WINDOWS do
    local f = _G["ChatFrame" .. i]
    f:SetFont(J.font, 13, "OUTLINE")
    f:SetShadowOffset(0, 0)

    local tab = _G["ChatFrame" .. i .. "Tab"]
    if tab then
      _G["ChatFrame" .. i .. "TabLeft"]:SetTexture(nil)
      _G["ChatFrame" .. i .. "TabMiddle"]:SetTexture(nil)
      _G["ChatFrame" .. i .. "TabRight"]:SetTexture(nil)
      tab:SetAlpha(1)
      _G["ChatFrame" .. i .. "TabText"]:SetFont(J.font, 12, "OUTLINE")
    end

    local eb = _G["ChatFrame" .. i .. "EditBox"]
    if eb then
      eb:SetFont(J.font, 13, "OUTLINE")
      eb:SetAltArrowKeyMode(false)
      -- Move edit box below the chat frame
      eb:ClearAllPoints()
      eb:SetPoint("TOPLEFT", _G["ChatFrame" .. i], "BOTTOMLEFT", -6, -8)
      eb:SetPoint("TOPRIGHT", _G["ChatFrame" .. i], "BOTTOMRIGHT", 6, -8)
      eb:SetHeight(22)
      for _, region in pairs({
        _G["ChatFrame" .. i .. "EditBoxLeft"],
        _G["ChatFrame" .. i .. "EditBoxMid"],
        _G["ChatFrame" .. i .. "EditBoxRight"],
      }) do
        if region then region:SetTexture(nil) end
      end
      local ebbg = CreateFrame("Frame", nil, eb)
      ebbg:SetAllPoints(eb)
      ebbg:SetFrameLevel(math.max(eb:GetFrameLevel() - 1, 0))
      ebbg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
      })
      ebbg:SetBackdropColor(0.086, 0.086, 0.086, 0.6)
      ebbg:SetBackdropBorderColor(J.BORDER[1], J.BORDER[2], J.BORDER[3], 1)
    end
  end

  -- Hide clutter (incl. hover menu to the left of the chat). Everything is
  -- reparented to a hidden frame; replacing Show on FriendsMicroButton (a
  -- Blizzard micro button) tainted the bar code that keeps calling it.
  local hider = CreateFrame("Frame", "JunkieChatHider", UIParent)
  hider:Hide()

  for _, f in ipairs({ ChatFrameMenuButton, FriendsMicroButton }) do
    if f then
      f:Hide()
      f:SetParent(hider)
    end
  end

  for i = 1, NUM_CHAT_WINDOWS do
    local bf = _G["ChatFrame" .. i .. "ButtonFrame"]
    if bf then
      bf:Hide()
      bf:SetParent(hider)
    end
    for _, suffix in pairs({ "UpButton", "DownButton", "BottomButton" }) do
      local b = _G["ChatFrame" .. i .. suffix]
      if b then
        b:Hide()
        b:SetParent(hider)
      end
    end
  end

end)
