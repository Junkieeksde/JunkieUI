--[[---------------------------------------------------------------------------
  JunkieUI - Minimap button collector

  Collects addon minimap buttons into a single box locked to the minimap's
  clock bar. Click the box to fold the buttons out.

  Cost: the discovery sweep runs only during the first minute after login, to
  catch late-loading addons, and then removes its own OnUpdate for good.

  Sections:
    1. Upvalues
    2. Constants
    3. Module state (all file-local)
    4. Filters
    5. Layout
    6. Collection
    7. Module
-------------------------------------------------------------------------------]]

local J = JunkieUI

-- ---------------------------------------------------------------------------
-- 1. Upvalues
-- ---------------------------------------------------------------------------
local CreateFrame = CreateFrame
local Minimap     = Minimap
local LibStub     = LibStub
local ipairs, pairs, select, type = ipairs, pairs, select, type
local tinsert = table.insert
local tsort   = table.sort
local sfind   = string.find
local ceil    = math.ceil
local floor   = math.floor
local min     = math.min
local max     = math.max

-- ---------------------------------------------------------------------------
-- 2. Constants
-- ---------------------------------------------------------------------------
local BOX     = 18   -- size of the toggle box (sits inside the clock box)
local ICON    = 32   -- grid cell size for each collected button
local GAP     = 3
local PER_ROW = 6

local SCAN_INTERVAL = 5   -- seconds between catch-up scans
local SCAN_WINDOW   = 60  -- stop scanning entirely after this many seconds

local BD_SOLID = J:PixelBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  edgeSize = 1,
})

local function Skin(frame)
  frame:SetBackdrop(BD_SOLID)
  frame:SetBackdropColor(0.086, 0.086, 0.086, 1)
  frame:SetBackdropBorderColor(0, 0, 0, 1)
end

-- ---------------------------------------------------------------------------
-- 3. Module state (all file-local)
-- ---------------------------------------------------------------------------
local collected = {}
local orig      = setmetatable({}, { __mode = "k" })
-- Frames we have already judged. GatherMate / HandyNotes can park hundreds of
-- pins on the minimap; without these caches every scan would re-run a dozen
-- string.find calls per pin. Weak keys so removed frames can be collected.
local seen      = setmetatable({}, { __mode = "k" })
local rejected  = setmetatable({}, { __mode = "k" })

local box, bar, label

-- ---------------------------------------------------------------------------
-- 4. Filters
-- ---------------------------------------------------------------------------
local blacklist = {
  MiniMapTrackingFrame      = true,
  MiniMapMailFrame          = true,
  MiniMapBattlefieldFrame   = true,
  MinimapZoomIn             = true,
  MinimapZoomOut            = true,
  MinimapBackdrop           = true,
  MiniMapWorldMapButton     = true,
  MinimapZoneTextButton     = true,
  GameTimeFrame             = true,
  MiniMapVoiceChatFrame     = true,
  MiniMapInstanceDifficulty = true,
  MinimapNorthTag           = true,
  -- JunkieUI's own frames must never be collected
  JunkieClock               = true,
  JunkieMinimapBorder       = true,
  JunkieMinimapBG           = true,
  JunkieMinimapButtonBox    = true,
  JunkieMinimapButtonBar    = true,
  JunkieConfigButton        = true,
  JunkieMicroToggle         = true,
}

local patterns = {
  "^LibDBIcon10_",
  "MinimapButton",
  "MinimapFrame",
  "MinimapIcon",
  "[%-_]Minimap[%-_]",
  "Minimap$",
}

-- Map overlays (GatherMate nodes, HandyNotes pins, arrows, blobs) are also
-- buttons parented to the minimap, so anything that looks like a world pin is
-- rejected outright and stays on the map where it belongs.
local rejectPatterns = {
  "[Pp]in",
  "[Nn]ode",
  "[Bb]lob",
  "[Aa]rrow",
  "[Ww]aypoint",
  "GatherMate",
  "HandyNotes",
  "Routes",
  "Cartographer",
  "[Tt]racker",
  "[Oo]verlay",
}

-- Returns: isButton, permanentlyRejected
local function LooksLikeButton(frame, name)
  -- Cheapest test first: real addon buttons are icon sized, pins are not.
  local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
  if w < 15 or w > 40 or h < 15 or h > 40 then return false end

  for i = 1, #rejectPatterns do
    -- Map pins never turn into addon buttons: reject them for good.
    if sfind(name, rejectPatterns[i]) then return false, true end
  end

  for i = 1, #patterns do
    if sfind(name, patterns[i]) then return true end
  end

  -- Fallback: a clickable, non-Blizzard button parented to the minimap.
  if frame:IsObjectType("Button") and not sfind(name, "^Mini[Mm]ap") then
    if frame:GetScript("OnClick") or frame:GetScript("OnMouseDown") then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- 5. Layout
-- ---------------------------------------------------------------------------
local function Layout()
  local shown = 0
  for _, b in ipairs(collected) do
    local o = orig[b]
    if o then
      local col = shown % PER_ROW
      local row = floor(shown / PER_ROW)
      o.ClearAllPoints(b)
      -- Center each button inside its fixed grid cell; keep its native size.
      local cx = GAP + col * (ICON + GAP) + ICON / 2
      local cy = GAP + row * (ICON + GAP) + ICON / 2
      o.SetPoint(b, "CENTER", bar, "TOPRIGHT", -cx, -cy)
      b:Show()
      shown = shown + 1
    end
  end

  -- Grow the backdrop with the number of collected buttons.
  local cols = min(shown, PER_ROW)
  local rows = ceil(shown / PER_ROW)
  bar:SetWidth(max(1, cols * (ICON + GAP) + GAP))
  bar:SetHeight(max(1, rows * (ICON + GAP) + GAP))
  return shown
end

-- ---------------------------------------------------------------------------
-- 6. Collection
-- ---------------------------------------------------------------------------
local noop = function() end

local function Collect(frame)
  if not frame or seen[frame] then return false end
  if type(frame.IsObjectType) ~= "function" then return false end
  if not frame:IsObjectType("Frame") then return false end

  seen[frame] = true
  -- Keep the original methods so we can still position the button ourselves
  -- after the public ones are neutered below.
  orig[frame] = {
    ClearAllPoints = frame.ClearAllPoints,
    SetPoint       = frame.SetPoint,
    SetParent      = frame.SetParent,
  }
  frame:SetParent(bar)
  frame:SetFrameStrata("MEDIUM")
  frame:SetFrameLevel(bar:GetFrameLevel() + 2)
  frame:SetScript("OnDragStart", nil)
  frame:SetScript("OnDragStop", nil)
  frame:ClearAllPoints()
  -- Many addons reposition their button every frame; block that.
  frame.ClearAllPoints = noop
  frame.SetPoint       = noop
  frame.SetParent      = noop
  frame.SetScale       = noop
  tinsert(collected, frame)
  return true
end

-- Walks the vararg child list directly: no table allocation per scan
-- (GatherMate alone can park hundreds of pins on the minimap).
local function ScanChildren(...)
  local added = false
  for i = 1, select("#", ...) do
    local child = select(i, ...)
    if child and not rejected[child] and not seen[child] then
      local name = child.GetName and child:GetName()
      if not name or blacklist[name] then
        rejected[child] = true
      else
        local ok, permanent = LooksLikeButton(child, name)
        if ok then
          if Collect(child) then added = true end
        elseif permanent then
          rejected[child] = true
        end
      end
    end
  end
  return added
end

local function SortByName(a, b)
  return ((a.GetName and a:GetName()) or "") < ((b.GetName and b:GetName()) or "")
end

local function Scan()
  local added = ScanChildren(Minimap:GetChildren())

  -- LibDBIcon buttons that were parented elsewhere
  if LibStub then
    local lib = LibStub:GetLibrary("LibDBIcon-1.0", true)
    if lib and lib.objects then
      for name, b in pairs(lib.objects) do
        if not blacklist[name] and Collect(b) then added = true end
      end
    end
  end

  if added then
    tsort(collected, SortByName)
    Layout()
  end
end

-- ---------------------------------------------------------------------------
-- 7. Module
-- ---------------------------------------------------------------------------
J:AddModule(function()
  box = CreateFrame("Button", "JunkieMinimapButtonBox", JunkieClock or Minimap)
  box:SetSize(BOX, BOX)
  -- Locked inside the clock box, right edge, so it doesn't cover the minimap.
  if JunkieClock then
    box:SetPoint("RIGHT", JunkieClock, "RIGHT", -2, 0)
  else
    box:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -2, 1)
  end
  box:SetFrameStrata("MEDIUM")
  box:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  Skin(box)

  label = box:CreateFontString(nil, "OVERLAY")
  label:SetFont(J.font, 13, "OUTLINE")
  label:SetPoint("CENTER", box, "CENTER", 0, 0)
  label:SetText("+")
  label:SetTextColor(0.871, 0.447, 0.188)

  bar = CreateFrame("Frame", "JunkieMinimapButtonBar", box)
  bar:SetHeight(ICON + GAP * 2)
  bar:SetWidth(1)
  bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMLEFT", -2, 0)
  bar:SetFrameStrata("MEDIUM")
  bar:SetFrameLevel(box:GetFrameLevel() + 1)
  Skin(bar)
  bar:Hide()

  box:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(0.871, 0.447, 0.188, 1)
  end)
  box:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0, 0, 0, 1)
  end)
  box:SetScript("OnClick", function()
    if bar:IsShown() then
      bar:Hide()
      label:SetText("+")
    else
      Scan()
      if Layout() > 0 then
        bar:Show()
        label:SetText("-")
      end
    end
  end)

  -- -- Single scan driver ----------------------------------------------------
  -- Late-loading addons keep adding buttons for a while after login, and
  -- ADDON_LOADED can fire in bursts. One throttled ticker serves both: events
  -- request a scan on the next frame, and a catch-up scan runs every 5s for
  -- the first minute. After that the OnUpdate is removed entirely.
  local queued, sinceScan, total = false, 0, 0

  local driver = CreateFrame("Frame")
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("ADDON_LOADED")
  driver:SetScript("OnEvent", function(self)
    if self:GetScript("OnUpdate") then
      queued = true          -- coalesce bursts into one scan next frame
    else
      Scan()                 -- window closed: scan directly, no idle ticker
    end
  end)
  driver:SetScript("OnUpdate", function(self, e)
    e = e or 0
    sinceScan, total = sinceScan + e, total + e
    if queued or sinceScan > SCAN_INTERVAL then
      queued = false
      sinceScan = 0
      Scan()
    end
    -- Late-loading addons stop adding buttons after a while; drop the ticker
    -- entirely so there is zero idle cost during play.
    if total > SCAN_WINDOW then self:SetScript("OnUpdate", nil) end
  end)

  Scan()
end)
