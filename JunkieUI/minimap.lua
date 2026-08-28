--[[---------------------------------------------------------------------------
  JunkieUI - Minimap

  Square minimap with a 1px #000 border, a custom clock box docked underneath
  and a hard-locked quest tracker. No globals are created by this file other
  than the named frames the WoW API requires (Junkie* frame names).

  Size changes are broadcast so dependants (the button collector and the
  Blizzard buff chain) re-anchor themselves instead of polling.

  Cost: event driven only. No OnUpdate.

  Sections:
    1. Upvalues
    2. Helpers
    3. Module
-------------------------------------------------------------------------------]]

local J = JunkieUI

-- ---------------------------------------------------------------------------
-- 1. Upvalues
-- ---------------------------------------------------------------------------
local CreateFrame   = CreateFrame
local UIParent      = UIParent
local Minimap       = Minimap
local GetCVarBool   = GetCVarBool
local SetCVar       = SetCVar
local GetGameTime   = GetGameTime
local hooksecurefunc = hooksecurefunc
local date          = date
local tonumber      = tonumber
local pcall         = pcall
local format        = string.format
local floor         = math.floor
local abs           = math.abs

local BASE      = 165   -- minimap edge length at size step 1
local MIN_ZOOM  = 1     -- zoom-out is locked one step in
local MAX_ZOOM  = 5
local CLOCK_H   = 20
local TICK      = 5     -- clock refresh interval in seconds

-- Shared backdrop tables (reused; never mutated after creation)
local BD_EDGE = J:PixelBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
local BD_SOLID = J:PixelBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  edgeSize = 1,
})
local BD_BG = { bgFile = "Interface\\Buttons\\WHITE8X8" }

-- Module state
local state = {
  shownTime = nil,
  useLocal  = false,
  use24     = false,
  elapsed   = 0,
  clockKilled = false,
}

-- ---------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------

-- Size steps 1..5: step 1 is the original size, step 5 is 20% larger.
local function MapSize()
  local step = tonumber(J.db and J.db.mapSize) or 1
  if step < 1 then step = 1 elseif step > 5 then step = 5 end
  return floor(BASE * (1 + 0.05 * (step - 1)) + 0.5)
end

local function Skin(frame, backdrop, r, g, b, a)
  frame:SetBackdrop(backdrop)
  if r then frame:SetBackdropColor(r, g, b, a) end
  frame:SetBackdropBorderColor(0, 0, 0, 1)
end

-- ---------------------------------------------------------------------------
-- 3. Module
-- ---------------------------------------------------------------------------
J:AddModule(function()
  -- -- Blizzard chrome ------------------------------------------------------
  Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")

  MinimapBorder:Hide()
  MinimapBorderTop:Hide()
  MinimapZoomIn:Hide()
  MinimapZoomOut:Hide()
  MiniMapVoiceChatFrame:Hide()
  MiniMapWorldMapButton:Hide()
  MinimapZoneTextButton:Hide()
  -- Tracking button: Blizzard's own frame, kept clickable in the top left
  -- corner. Only the round border art is dropped so it matches the flat map;
  -- the button, its icon and its dropdown are untouched.
  if MiniMapTracking then
    MiniMapTracking:Show()
    MiniMapTracking:SetScale(0.9)
    for _, art in ipairs({ "MiniMapTrackingBorder", "MiniMapTrackingButtonBorder",
                           "MiniMapTrackingBackground", "MiniMapTrackingShine" }) do
      local t = _G[art]
      if t then if t.SetTexture then t:SetTexture(nil) end t:Hide() end
    end
    if MiniMapTrackingButton then MiniMapTrackingButton:Show() end
    if MiniMapTrackingIcon then
      MiniMapTrackingIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
  end
  MiniMapMailBorder:Hide()
  if MiniMapMailFrame then
    MiniMapMailFrame:ClearAllPoints()
    MiniMapMailFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 2, -2)
  end
  GameTimeFrame:Hide()

  -- -- Satellite anchoring --------------------------------------------------
  -- North tag top-center, dungeon difficulty top-left, dungeon finder/eye
  -- bottom-left (5px in, 26px up so it clears the clock bar). All are
  -- re-anchored on zone/instance changes because Blizzard resets them.
  local CORNERS = {
    { "MinimapNorthTag",          "TOP",        "TOP",        0, -2, nil, "OVERLAY" },
    { "MiniMapInstanceDifficulty", "TOPLEFT",   "TOPLEFT",   -6,  6, 0.8 },
    { "MiniMapLFGFrame",          "BOTTOMLEFT", "BOTTOMLEFT", 5, 26, 0.9 },
    -- Tracking sits inside the top left corner, mirroring the mail icon.
    { "MiniMapTracking",          "TOPLEFT",    "TOPLEFT",    2, -2, 0.9 },
  }

  local function PinCorners()
    for i = 1, #CORNERS do
      local c = CORNERS[i]
      local f = _G[c[1]]
      if f then
        f:ClearAllPoints()
        f:SetPoint(c[2], Minimap, c[3], c[4], c[5])
        if c[6] then f:SetScale(c[6]) end
        if c[7] then f:SetDrawLayer(c[7]) end
      end
    end
  end
  PinCorners()

  -- -- Cluster / size -------------------------------------------------------
  MinimapCluster:ClearAllPoints()
  -- NOTE: xp.lua owns the vertical offset of MinimapCluster (it shifts the
  -- cluster down when the XP bar is shown). Only the initial anchor lives here.
  MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -3, -3)

  Minimap:ClearAllPoints()
  Minimap:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", 0, 0)

  -- Resizing only touches the map itself; the clock, border, backdrop and the
  -- button box are all anchored to Minimap, so they follow along.
  function J:ApplyMinimapSize()
    local s = MapSize()
    Minimap:SetSize(s, s)
    MinimapCluster:SetSize(s, s)
    -- Blizzard's buff frame is docked to the minimap; re-apply the anchor so it
    -- tracks the new width instead of staying where the old map edge was.
    if J.AnchorBlizzardAuras then J.AnchorBlizzardAuras() end
  end
  J:ApplyMinimapSize()

  -- -- Border + backdrop plate ----------------------------------------------
  local border = CreateFrame("Frame", "JunkieMinimapBorder", Minimap)
  border:SetPoint("TOPLEFT", Minimap, -1, 1)
  border:SetPoint("BOTTOMRIGHT", Minimap, 1, -1)
  border:SetFrameLevel(Minimap:GetFrameLevel() + 2)
  Skin(border, BD_EDGE)

  -- Dark plate behind the minimap (visible if the map glitches)
  local mbg = CreateFrame("Frame", "JunkieMinimapBG", Minimap)
  mbg:SetPoint("TOPLEFT", Minimap, 0, 0)
  mbg:SetPoint("BOTTOMRIGHT", Minimap, 0, 0)
  mbg:SetFrameStrata("BACKGROUND")
  mbg:SetFrameLevel(0)
  mbg:SetBackdrop(BD_BG)
  mbg:SetBackdropColor(0, 0, 0, 1)

  -- -- Blizzard clock hider --------------------------------------------------
  local hider = CreateFrame("Frame", "JunkieHider", UIParent)
  hider:Hide()

  local function KillBlizzClock()
    local c = TimeManagerClockButton
    if c then
      c:UnregisterAllEvents()
      c:Hide()
      c:SetParent(hider)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
      c:SetAlpha(0)
      c:EnableMouse(false)
      c:SetScale(0.001)
      state.clockKilled = true
    end
    if TimeManagerClockTicker then TimeManagerClockTicker:SetText("") end
    if TimeManagerAlarmFiredTexture then TimeManagerAlarmFiredTexture:Hide() end
  end
  KillBlizzClock()

  -- -- Custom clock box -----------------------------------------------------
  local clock = CreateFrame("Button", "JunkieClock", Minimap)
  clock:SetHeight(CLOCK_H)
  -- Docked underneath the minimap, shifted 2px up into the map and widened
  -- 1px on each side so it always covers the minimap edge cleanly.
  clock:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -1, 1)
  clock:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 1, 1)
  clock:SetFrameStrata("MEDIUM")
  Skin(clock, BD_SOLID, 0.086, 0.086, 0.086, 1)
  clock:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local text = clock:CreateFontString(nil, "OVERLAY")
  text:SetFont(J.font, 12, "OUTLINE")
  text:SetPoint("CENTER", clock, "CENTER", 0, 0)
  text:SetTextColor(1, 1, 1)

  -- CVars are only read on login and when they actually change, so the tick
  -- itself does no API polling beyond the time lookup.
  local function RefreshCVars()
    state.useLocal = GetCVarBool and GetCVarBool("timeMgrUseLocalTime") or false
    state.use24    = GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime") or false
  end
  RefreshCVars()

  local function UpdateClock()
    local h, m
    if state.useLocal then
      h, m = tonumber(date("%H")), tonumber(date("%M"))
    elseif GetGameTime then
      h, m = GetGameTime()
    end
    if not h then return end
    local str
    if state.use24 then
      str = format("%02d:%02d", h, m)
    else
      local suffix = h >= 12 and "PM" or "AM"
      local hh = h % 12
      if hh == 0 then hh = 12 end
      str = format("%d:%02d %s", hh, m, suffix)
    end
    if state.shownTime ~= str then
      text:SetText(str)
      state.shownTime = str
    end
  end
  UpdateClock()

  -- Plain throttled OnUpdate on a dedicated ticker: one float add per frame,
  -- one time lookup every five seconds. Animation-group tickers that restart
  -- themselves from inside OnFinished are unsafe on 3.3.5.
  local ticker = CreateFrame("Frame", nil, clock)
  ticker:SetScript("OnUpdate", function(_, e)
    state.elapsed = state.elapsed + (e or 0)
    if state.elapsed < TICK then return end
    state.elapsed = 0
    UpdateClock()
  end)

  -- -- Clock context menu ---------------------------------------------------
  -- Same behaviour as Blizzard's clock: left-click = Time Manager,
  -- right-click = menu with stopwatch/settings.
  local menu = CreateFrame("Frame", "JunkieClockMenu", UIParent, "UIDropDownMenuTemplate")

  local function ToggleCVar(cvar)
    SetCVar(cvar, (GetCVarBool(cvar) and "0" or "1"))
    RefreshCVars()
    UpdateClock()
  end

  local function InitMenu()
    local info = UIDropDownMenu_CreateInfo()
    info.text = TIMEMANAGER_TITLE or "Time Manager"
    info.notCheckable = 1
    info.func = function() if ToggleTimeManager then ToggleTimeManager() end end
    UIDropDownMenu_AddButton(info)

    info = UIDropDownMenu_CreateInfo()
    info.text = TIMEMANAGER_STOPWATCH_TITLE or "Stopwatch"
    info.notCheckable = 1
    info.func = function() if Stopwatch_Toggle then Stopwatch_Toggle() end end
    UIDropDownMenu_AddButton(info)

    info = UIDropDownMenu_CreateInfo()
    info.text = TIMEMANAGER_SHOW24HRCLOCK or "24-hour clock"
    info.checked = GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime")
    info.func = function() ToggleCVar("timeMgrUseMilitaryTime") end
    UIDropDownMenu_AddButton(info)

    info = UIDropDownMenu_CreateInfo()
    info.text = TIMEMANAGER_LOCALTIME or "Local time"
    info.checked = GetCVarBool and GetCVarBool("timeMgrUseLocalTime")
    info.func = function() ToggleCVar("timeMgrUseLocalTime") end
    UIDropDownMenu_AddButton(info)
  end
  UIDropDownMenu_Initialize(menu, InitMenu, "MENU")

  clock:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
    elseif ToggleTimeManager then
      ToggleTimeManager()
    end
  end)

  -- -- Quest tracker: locked position, movable via /jui -----------------------
  local watch = WatchFrame or QuestWatchFrame

  local function WatchX() return tonumber(J.db and J.db.watchX) or 10 end
  local function WatchY() return tonumber(J.db and J.db.watchY) or -40 end

  local function MoveWatch()
    local f = watch
    if not f or f.JUI_moving then return end
    -- The tracker is an ordinary (unprotected) frame in 3.3.5, so it is safe to
    -- re-anchor while in combat. Bailing out on InCombatLockdown was what let
    -- Blizzard's own combat-time WatchFrame_Update drag it out of position.
    local h = UIParent:GetHeight() * 0.55
    local x, y = WatchX(), WatchY()
    local p, rel, relP, px, py = f:GetPoint(1)
    if p == "TOPLEFT" and rel == UIParent and relP == "TOPLEFT"
      and px == x and py == y
      and abs((f:GetHeight() or 0) - h) < 0.5 then
      return
    end
    f.JUI_moving = true
    pcall(function()
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
      f:SetHeight(h)
    end)
    f.JUI_moving = false
  end
  MoveWatch()

  -- Drag handle shown when unlocked
  local drag = J:CreateMover("JunkieWatchMover", 180, 26,
    "|cffde7230Drag: Quest tracker|r", J.MOVER_BORDER_ALT)

  local function SyncDrag()
    drag:ClearAllPoints()
    drag:SetPoint("TOPLEFT", UIParent, "TOPLEFT", WatchX(), WatchY())
  end
  SyncDrag()

  drag:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left, _, top = J:MoverPos(self)
    J.db.watchX = floor(left + 0.5)
    J.db.watchY = floor(top - UIParent:GetHeight() + 0.5)
    SyncDrag()
    MoveWatch()
  end)

  function J:SetWatchUnlocked(on)
    J.db.watchUnlocked = on and true or false
    if J.db.watchUnlocked then SyncDrag(); drag:Show() else drag:Hide() end
  end
  J:SetWatchUnlocked(J.db.watchUnlocked)

  if watch then
    -- Hard lock: pull the frame back if anything else moves it
    hooksecurefunc(watch, "SetPoint", function(self)
      if self.JUI_moving then return end
      MoveWatch()
    end)
    hooksecurefunc(watch, "SetHeight", function(self)
      if self.JUI_moving then return end
      MoveWatch()
    end)
    -- Blizzard collapses and re-lays out the tracker when combat starts and
    -- ends; re-assert our anchor right after each of those passes.
    if WatchFrame_Update then hooksecurefunc("WatchFrame_Update", MoveWatch) end
    if WatchFrame_Collapse then hooksecurefunc("WatchFrame_Collapse", MoveWatch) end
    if WatchFrame_Expand then hooksecurefunc("WatchFrame_Expand", MoveWatch) end
  end

  -- -- Single event driver ---------------------------------------------------
  -- Replaces the five separate event frames this file used to create.
  local handlers = {
    PLAYER_ENTERING_WORLD = function()
      PinCorners()
      KillBlizzClock()
      MoveWatch()
    end,
    UPDATE_INSTANCE_INFO   = PinCorners,
    LFG_UPDATE             = PinCorners,
    QUEST_LOG_UPDATE       = MoveWatch,
    ZONE_CHANGED           = MoveWatch,
    ZONE_CHANGED_NEW_AREA  = MoveWatch,
    UNIT_QUEST_LOG_CHANGED = MoveWatch,
    PLAYER_REGEN_ENABLED   = MoveWatch,
    PLAYER_REGEN_DISABLED  = MoveWatch,
    CVAR_UPDATE            = function()
      RefreshCVars()
      UpdateClock()
    end,
  }

  local driver = CreateFrame("Frame")
  for event in pairs(handlers) do driver:RegisterEvent(event) end
  -- The Blizzard clock is created once by Blizzard_TimeManager; keep listening
  -- until it exists, then drop the event instead of firing on every addon load.
  driver:RegisterEvent("ADDON_LOADED")
  driver:SetScript("OnEvent", function(self, event)
    if event == "ADDON_LOADED" then
      -- Already dealt with: drop the event before doing any more work. During
      -- login this handler would otherwise re-run for every addon that loads.
      if state.clockKilled then self:UnregisterEvent("ADDON_LOADED") return end
      KillBlizzClock()
      if state.clockKilled then self:UnregisterEvent("ADDON_LOADED") end
      return
    end
    local fn = handlers[event]
    if fn then fn() end
  end)

  -- -- Mousewheel zoom (buttons are hidden), min zoom locked one step in ------
  if Minimap:GetZoom() < MIN_ZOOM then Minimap:SetZoom(MIN_ZOOM) end
  Minimap:EnableMouseWheel(true)
  Minimap:SetScript("OnMouseWheel", function(self, delta)
    local z = self:GetZoom()
    if delta > 0 then
      if z < MAX_ZOOM then self:SetZoom(z + 1) end
    else
      if z > MIN_ZOOM then self:SetZoom(z - 1) end
    end
  end)
end)
