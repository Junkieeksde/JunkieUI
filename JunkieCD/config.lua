-- /jcd settings panel. Same flat JunkieUI theme so it can be merged into the
-- /jui panel as an extra tab later on.
local C = JunkieCD

local panel
local BG, BOX, ACCENT, TXT, DIM = C.BG, C.BOX, C.ACCENT, C.TXT, C.DIM
local HL = { 0.18, 0.11, 0.06 }

-- Canvas palette. Kept as plain numbers so every mockup reads the exact same
-- colour: background #2E2B24, inactive fill #1F1F1F, active edge #171717.
-- Inactive frames and empty (+) slots rest on a deep orange (#532B12) and
-- light up to the bright orange (#BB6129) while the mouse is over them.
local CANVAS_BG  = { 0.0902, 0.0902, 0.0902 }
local MOCK_OFF   = { 0.0549, 0.0549, 0.0549 }
local EDGE_DARK  = { 0.0549, 0.0549, 0.0549 }
local EDGE_OFF   = { 0.3255, 0.1686, 0.0706 }
local EDGE_HOT   = { 0.7333, 0.3804, 0.1608 }
-- Frame colour used everywhere outside the canvas, so the canvas border can
-- match the rest of the settings window.
local EDGE_UI    = { 0.18, 0.17, 0.14 }


local refreshers = {}
local openList   -- only one expandable list may be open at a time

-- Which canvas the menu is editing: nil = the profile itself, a number = form.
C.editForm = nil
C.editPowerForm = nil

local function CloseLists(except)
  if openList and openList ~= except then openList:Hide() end
  openList = except
end

local function Label(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(C.font, size or 11)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetShadowOffset(0, 0)
  fs:SetTextColor(TXT[1], TXT[2], TXT[3])
  return fs
end

local function Flat(f, r, g, b, a)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(r, g, b, a or 1)
  f:SetBackdropBorderColor(0.18, 0.17, 0.14, 1)
  return f
end

local function Header(parent, text, y)
  local fs = Label(parent, 11, "LEFT")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
  fs:SetText(string.upper(text))
  fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetTexture("Interface\\Buttons\\WHITE8X8")
  line:SetVertexColor(0.35, 0.3, 0.15, 1)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
  line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
  return fs
end

local function Hint(parent, text, y)
  local fs = Label(parent, 10, "LEFT")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
  -- An explicit width is what actually turns wrapping on: two horizontal
  -- anchors alone leave the string on one line and it gets cut with "...".
  local w = (parent:GetWidth() or 632)
  if w < 100 then w = 632 end
  fs:SetWidth(w - 28)
  fs:SetJustifyV("TOP")
  fs:SetText(text)
  fs:SetTextColor(DIM[1], DIM[2], DIM[3])
  return fs
end


local function MakeButton(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 110, h or 22)
  Flat(b, BOX[1], BOX[2], BOX[3], 1)
  local fs = Label(b, 11, "CENTER")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  b.text = fs
  b.selected = false
  function b:Refresh()
    if self.selected then
      self:SetBackdropColor(HL[1], HL[2], HL[3], 1)
      self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
      self.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else
      self:SetBackdropColor(BOX[1], BOX[2], BOX[3], 1)
      self:SetBackdropBorderColor(0.18, 0.17, 0.14, 1)
      self.text:SetTextColor(TXT[1], TXT[2], TXT[3])
    end
  end
  b:SetScript("OnEnter", function(self) if not self.selected then self:SetBackdropColor(HL[1], HL[2], HL[3], 1) end end)
  b:SetScript("OnLeave", function(self) self:Refresh() end)
  if onClick then b:SetScript("OnClick", onClick) end
  b:Refresh()
  return b
end

-- Mouseover response for canvas elements: a flat white wash at 10% opacity on
-- top of the button. It reads as "10% brighter" on both the icon textures and
-- the flat bars, and it costs nothing - the client draws highlight textures
-- itself, so there is no OnEnter/OnLeave bookkeeping and no extra frames.
local function AddHover(b, inset)
  inset = inset or 1
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
  local t = b:GetHighlightTexture()
  if t then
    t:SetVertexColor(1, 1, 1, 0.10)
    t:SetBlendMode("ADD")
    t:SetPoint("TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", -inset, inset)
  end
  return b
end



local function MakeCheck(parent, label, y, get, onClick, x)
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(16, 16)
  c.px, c.py = x or 16, y
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", c.px, c.py)
  Flat(c, BG[1], BG[2], BG[3], 1)
  local fill = c:CreateTexture(nil, "ARTWORK")
  fill:SetTexture("Interface\\Buttons\\WHITE8X8")
  fill:SetPoint("TOPLEFT", 4, -4)
  fill:SetPoint("BOTTOMRIGHT", -4, 4)
  fill:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
  local t = Label(c, 11, "LEFT")
  t:SetPoint("LEFT", c, "RIGHT", 8, 0)
  -- Keep long labels inside the window: they wrap instead of running out.
  local pw = parent:GetWidth() or 632
  if pw < 100 then pw = 632 end
  t:SetWidth(math.max(80, pw - (x or 16) - 16 - 8 - 12))
  t:SetJustifyV("MIDDLE")
  t:SetText(label)


  c.label = t
  c.fill = fill

  local function refresh()
    if get() then fill:Show() else fill:Hide() end
  end
  c.Refresh = refresh
  refresh()
  table.insert(refreshers, refresh)
  c:SetScript("OnClick", function()
    onClick(not get())
    refresh()
    C:RefreshConfig()
  end)
  function c:SetShown(show)
    if show then self:Show() else self:Hide() end
  end
  function c:SetY(ny)
    self.py = ny
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", parent, "TOPLEFT", self.px, ny)
  end
  c.blockHeight = 30
  return c
end


local function MakeDropdown(parent, label, y, options, get, onSelect, width, x)
  local px = x or 16
  local title
  if label then
    title = Label(parent, 11, "LEFT")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", px, y)
    -- Long labels wrap inside the window instead of running past its edge.
    -- Wrapping needs a real width; two anchors alone cut the line with "...".
    local pw = parent:GetWidth() or 632
    if pw < 100 then pw = 632 end
    title:SetWidth(pw - px - 12)
    title:SetJustifyV("TOP")
    title:SetText(label)
    y = y - 18
  end

  local function LabelFor(key)
    for _, o in ipairs(type(options) == "function" and options() or options) do
      if o.key == key then return o.name end
    end
    return "-"
  end
  local btn = MakeButton(parent, LabelFor(get()), width or 200, 22, nil)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", px, y)
  btn.text:ClearAllPoints()
  btn.text:SetPoint("LEFT", btn, "LEFT", 8, 0)
  btn.text:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
  btn.text:SetJustifyH("LEFT")

  -- Flat + / - box on the right, the same marker JunkieUI uses.
  local mark = CreateFrame("Frame", nil, btn)
  mark:SetSize(14, 14)
  mark:SetPoint("RIGHT", btn, "RIGHT", -5, 0)
  Flat(mark, BG[1], BG[2], BG[3], 1)
  local markFS = Label(mark, 11, "CENTER")
  markFS:SetPoint("CENTER", mark, "CENTER", 0, 0)
  markFS:SetText("+")
  markFS:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

  -- Keep the expanded list outside the settings page hierarchy. A child frame
  -- cannot reliably draw above later-created sibling controls in the 3.3.5
  -- client, even when its nominal frame level is higher. UIParent makes the
  -- list a real overlay instead of another page child.
  local list = CreateFrame("Frame", nil, UIParent)
  list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
  list:SetSize(width or 200, 24)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetFrameLevel(500)
  list:EnableMouse(true)
  Flat(list, BOX[1], BOX[2], BOX[3], 1)
  list:Hide()
  list.items = {}
  -- UIParent does not inherit the settings panel's scale. Match the button's
  -- effective scale whenever the list opens so its anchors and pixels remain
  -- aligned at every configured UI scale.
  function list:Raise()
    local rootScale = UIParent:GetEffectiveScale() or 1
    local buttonScale = btn:GetEffectiveScale() or rootScale
    if rootScale > 0 then self:SetScale(buttonScale / rootScale) end
    self:SetFrameStrata("FULLSCREEN_DIALOG")
    self:SetFrameLevel(500)
    for _, it in ipairs(self.items) do
      it:SetFrameLevel(510)
    end
  end
  list:SetScript("OnHide", function(self)
    markFS:SetText("+")
    if openList == self then openList = nil end
  end)
  parent:HookScript("OnHide", function() list:Hide() end)


  local function Populate()
    local opts = type(options) == "function" and options() or options
    for _, it in ipairs(list.items) do it:Hide() end
    for i, o in ipairs(opts) do
      local item = list.items[i]
      if not item then
        item = MakeButton(list, "", (width or 200) - 8, 18)
        item:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -2 - (i - 1) * 20)
        list.items[i] = item
      end
      item.text:SetText(o.name)
      item:SetScript("OnClick", function()
        btn.text:SetText(o.name)
        list:Hide()
        CloseLists(nil)
        onSelect(o.key)
      end)
      item:Show()
    end
    list:SetHeight(math.max(1, #opts) * 20 + 4)
  end

  btn:SetScript("OnClick", function()
    if list:IsShown() then
      list:Hide()
      CloseLists(nil)
    else
      Populate()
      CloseLists(list)
      list:Show()
      list:Raise()
      markFS:SetText("-")

    end
  end)
  btn.titleFS = title
  btn.list = list
  function btn:SetShown(show)
    if show then self:Show() else self:Hide() end
    if self.titleFS then if show then self.titleFS:Show() else self.titleFS:Hide() end end
    if not show then self.list:Hide() end
  end
  function btn:SetY(ny)
    if self.titleFS then
      self.titleFS:ClearAllPoints()
      self.titleFS:SetPoint("TOPLEFT", parent, "TOPLEFT", px, ny)
      -- A wrapped label takes more than one line: push the button down for it.
      local h = math.max(18, math.ceil((self.titleFS:GetStringHeight() or 12) + 4))
      self.blockHeight = h + 28
      ny = ny - h
    end
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", parent, "TOPLEFT", px, ny)
  end
  -- Popups are reused between icons. Re-read the current icon every time the
  -- window opens instead of leaving the label from the previously viewed icon.
  function btn:Sync()
    self.text:SetText(LabelFor(get()))
    self.list:Hide()
  end
  btn.blockHeight = label and 46 or 28

  table.insert(refreshers, function() btn:Sync() end)

  return btn
end


-- Click anywhere on the track to jump the slider there.
local function ClickToSlide(s, minV, maxV)
  s:EnableMouse(true)
  s:SetScript("OnMouseDown", function(self)
    local scale = self:GetEffectiveScale()
    local cx = GetCursorPosition() / scale
    local left, w = self:GetLeft(), self:GetWidth()
    if not left or not w or w <= 0 then return end
    local frac = (cx - left) / w
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    self:SetValue(minV + frac * (maxV - minV))
  end)
end

-- Every slider in the window shares one inset and one track width so the
-- tracks and their value boxes line up from page to page.
local SLIDER_X, SLIDER_W = 16, 240

local function MakeSlider(parent, label, minV, maxV, y, get, onChange, x, w)
  x, w = SLIDER_X, SLIDER_W
  local title = Label(parent, 11, "LEFT")
  title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  title:SetText(label)

  local track = CreateFrame("Frame", nil, parent)
  track:SetSize(w, 10)
  track:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
  Flat(track, BG[1], BG[2], BG[3], 1)

  local s = CreateFrame("Slider", nil, parent)
  s:SetAllPoints(track)
  s:SetOrientation("HORIZONTAL")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(1)
  s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
  local thumb = s:GetThumbTexture()
  thumb:SetSize(8, 16)
  thumb:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
  ClickToSlide(s, minV, maxV)

  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(48, 20)
  box:SetPoint("LEFT", track, "RIGHT", 10, 0)
  Flat(box, BG[1], BG[2], BG[3], 1)
  local val = Label(box, 11, "CENTER")
  val:SetPoint("CENTER")

  s:SetValue(get())
  val:SetText(tostring(get()))
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    val:SetText(tostring(v))
  end)
  -- A full bar rebuild for every pixel crossed while dragging caused visible
  -- stutter. Keep the number live, but commit the setting once on release.
  s:SetScript("OnMouseUp", function(self)
    local v = math.floor((self:GetValue() or get()) + 0.5)
    val:SetText(tostring(v))
    onChange(v)
  end)
  table.insert(refreshers, function()
    s:SetValue(get())
    val:SetText(tostring(get()))
  end)
  s.titleFS = title
  s.track = track
  s.valueBox = box
  function s:SetShown(show)
    if show then self:Show(); track:Show(); box:Show(); title:Show()
    else self:Hide(); track:Hide(); box:Hide(); title:Hide() end
  end
  function s:SetY(ny)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, ny)
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, ny - 18)
  end
  s.blockHeight = 48
  return s
end


-- Numeric field with its own OK button. Nothing can be typed before the owning
-- option is switched on: the whole field is hidden until then.
local function MakeField(parent, title, y, x, width, get, set, maxLetters)
  local group = {}
  local head = Label(parent, 10, "LEFT")
  head:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y)
  -- Long descriptions wrap onto several lines instead of leaving the window.
  -- The width has to be explicit, otherwise the string is cut with "...".
  local pw = parent:GetWidth() or 632
  if pw < 100 then pw = 632 end
  head:SetWidth(pw - (x or 16) - 12)
  head:SetJustifyV("TOP")
  head:SetText(title)
  head:SetTextColor(DIM[1], DIM[2], DIM[3])



  local box = CreateFrame("Frame", nil, parent)
  box:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y - 17)
  box:SetSize(width or 120, 22)
  Flat(box, BOX[1], BOX[2], BOX[3], 1)

  local edit = CreateFrame("EditBox", nil, box)
  edit:SetPoint("TOPLEFT", 5, -1)
  edit:SetPoint("BOTTOMRIGHT", -5, 1)
  edit:SetFont(C.font, 11)
  edit:SetAutoFocus(false)
  edit:SetNumeric(true)
  edit:SetMaxLetters(maxLetters or 7)
  edit:SetTextColor(TXT[1], TXT[2], TXT[3])
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local function commit()
    set(tonumber(edit:GetText()))
    edit:ClearFocus()
    C:RefreshConfig()
    C:Rebuild()
  end
  edit:SetScript("OnEnterPressed", commit)

  local ok = MakeButton(parent, "OK", 34, 22, commit)
  ok:SetPoint("LEFT", box, "RIGHT", 6, 0)

  group.edit, group.box, group.ok, group.head = edit, box, ok, head
  function group:Sync() edit:SetText(tostring(get() or "")) end
  function group:SetShown(show)
    if show then head:Show(); box:Show(); ok:Show()
    else head:Hide(); box:Hide(); ok:Hide(); edit:ClearFocus() end
  end
  function group:SetY(ny)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, ny)
    local h = math.max(17, math.ceil((head:GetStringHeight() or 12) + 5))
    self.blockHeight = h + 29
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, ny - h)
  end

  group.blockHeight = 46

  table.insert(refreshers, function() group:Sync() end)
  return group
end

-- Reflows a list of widgets so hidden blocks collapse and shown blocks push the
-- rest down: the panel expands instead of leaving blank holes.
local function Reflow(startY, items)
  local y = startY
  for _, it in ipairs(items) do
    local widget, visible, height = it[1], it[2], it[3]
    if visible then
      if widget.SetY then widget:SetY(y) end
      if widget.SetShown then widget:SetShown(true) else widget:Show() end
      y = y - (height or widget.blockHeight or 30)
    else
      if widget.SetShown then widget:SetShown(false) else widget:Hide() end
    end
  end
  return y
end

-- Accent line that marks where an expanded block starts and ends.
local function MakeDivider(parent, inset)
  local d = { }
  local line = parent:CreateTexture(nil, "OVERLAY")
  line:SetTexture("Interface\\Buttons\\WHITE8X8")
  line:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
  line:SetHeight(1)
  function d:SetY(ny)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", inset or 12, ny)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset or 12), ny)
  end
  function d:SetShown(show) if show then line:Show() else line:Hide() end end
  d.blockHeight = 12
  line:Hide()
  return d
end



-- Icon grid ------------------------------------------------------------------
local GLOW_OPTIONS = C.GLOW_TYPES
local SOUND_OPTIONS = C.SOUNDS

local function EntryLabel(entry)
  if not entry or not entry.id then return nil end
  if entry.kind == "trinket" then
    local slot = tonumber(entry.id) or 13
    return "Trinket slot " .. (slot == 14 and 2 or 1),
      GetInventoryItemTexture("player", slot) or "Interface\\Icons\\INV_Misc_Pocketwatch_01"
  end
  if entry.kind == "item" then
    local name, _, _, _, _, _, _, _, _, tex = GetItemInfo(entry.id)
    return name or ("item " .. entry.id), tex
  end
  local name, _, tex = GetSpellInfo(entry.id)
  return name or ("spell " .. entry.id), tex
end

local UNIT_OPTIONS = {
  { key = "player", name = "Player", tag = "P" },
  { key = "target", name = "Target", tag = "T" },
  { key = "pet", name = "Pet", tag = "E" },
}

local MODE_OPTIONS = {
  { key = "found", name = "Show when found" },
  { key = "missing", name = "Show when missing" },
}

local MISSING_STYLE_OPTIONS = {
  { key = "colour", name = "Colour" },
  { key = "grayscale", name = "Grayscale" },
}

local FILTER_OPTIONS = {
  { key = "buff", name = "Buff", tag = "B" },
  { key = "debuff", name = "Debuff", tag = "D" },
}

-- Older profiles stored one combined key.
local function NormalizeAura(entry)
  if not entry then return end
  if entry.unit == "my" or entry.unit == nil then
    entry.unit = "player"
    entry.filter = entry.filter or "buff"
  elseif entry.unit == "target" then
    entry.filter = entry.filter or "debuff"
  elseif entry.unit == "pet" then
    entry.filter = entry.filter or "buff"
  end
  entry.glow = entry.glow or "none"
  -- One of the two states is always active: found is the default.
  entry.mode = (entry.mode == "missing") and "missing" or "found"
  entry.missingStyle = (entry.missingStyle == "grayscale") and "grayscale" or "colour"
  entry.glowStacks = tonumber(entry.glowStacks) or 1
  return entry
end

-- Reminder row: when an icon is allowed to nag.
local REMIND_OPTIONS = {
  { key = "always", name = "Always" },
  { key = "party",  name = "Only in a party or raid" },
  { key = "raid",   name = "Only in a raid" },
}

local function UnitInfo(key)
  if key == "my" then key = "player" end
  for _, o in ipairs(UNIT_OPTIONS) do if o.key == key then return o end end
  return UNIT_OPTIONS[1]
end

-- Per icon settings ------------------------------------------------------------
-- One popup for both cooldowns and auras, opened by clicking the icon itself.
-- It never writes to anything except the single icon it was opened from: the
-- icon is looked up again by its own uid on every read and every write, so two
-- slots can never end up sharing a value.
local iconPopup
local iconDetailHost

local function PopupEntry(f)
  local bag = f and f.bag
  if not bag or not f.uid then return nil end
  local arr = bag.list()
  for i = 1, bag.max do
    local e = arr[i]
    if e and e.uid == f.uid then return e end
  end
  return nil
end

local function BuildIconPopup()
  local parent = iconDetailHost or UIParent
  local f = CreateFrame("Frame", "JunkieCDIconPopup", parent)
  if iconDetailHost then
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    f:SetSize(parent:GetWidth(), parent:GetHeight())
  else
    f:SetSize(300, 300)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
  end
  Flat(f, BOX[1], BOX[2], BOX[3], 1)
  f:EnableMouse(true)
  f:Hide()
  if not iconDetailHost then C:RegisterSettingsWindow(f) end

  f.title = Label(f, 11, "LEFT")
  f.title:SetPoint("TOPLEFT", 12, -12)
  f.title:SetPoint("RIGHT", f, "RIGHT", -38, 0)
  f.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

  local function ReturnToModule()
    f:Hide()
    if f.bag and f.bag.detailPage and C.UpdateDetailPanel then
      C:UpdateDetailPanel(f.bag.detailPage)
    end
  end

  local close = MakeButton(f, "X", 20, 20, ReturnToModule)
  close:SetPoint("TOPRIGHT", -8, -8)

  local function get(key, fallback)
    local e = PopupEntry(f)
    local v = e and e[key]
    if v == nil then return fallback end
    return v
  end

  local function set(key, value)
    local e = PopupEntry(f)
    if not e then return end
    e[key] = value
    C:Rebuild()
    C:RefreshConfig()
    if f:IsShown() then f.sync() end
  end

  -- Aura blocks ---------------------------------------------------------------
  local glowDrop = MakeDropdown(f, "Glow style", -40, GLOW_OPTIONS,
    function() return get("glow", "none") end,
    function(key) set("glow", key) end, 250, 12)

  local unitDrop = MakeDropdown(f, "Which unit to watch", -40, UNIT_OPTIONS,
    function() return get("unit", "player") end,
    function(key) set("unit", key) end, 250, 12)

  local filterDrop = MakeDropdown(f, "Buff or debuff", -40, FILTER_OPTIONS,
    function() return get("filter", "buff") end,
    function(key) set("filter", key) end, 250, 12)

  local onlyMineCheck = MakeCheck(f, "Only my own (ignore auras from other players)", -40,
    function() return get("onlyMine", false) end,
    function(v) set("onlyMine", v) end, 12)

  local modeDrop = MakeDropdown(f, "Show this icon when the aura is", -40, MODE_OPTIONS,
    function() return get("mode", "found") end,
    function(key) set("mode", key) end, 250, 12)

  local remindDrop = MakeDropdown(f, "Remind me", -40, REMIND_OPTIONS,
    function() return get("remind", "always") end,
    function(key) set("remind", key) end, 250, 12)

  local missingDrop = MakeDropdown(f, "How the icon looks when the aura is missing", -40, MISSING_STYLE_OPTIONS,
    function() return get("missingStyle", "colour") end,
    function(key) set("missingStyle", key) end, 250, 12)

  local stackCheck = MakeCheck(f, "Glow at a number of stacks", -40,
    function() return get("glowStacksEnabled", false) end,
    function(v)
      local e = PopupEntry(f)
      if not e then return end
      if not v then e.glowStacks = 1 end
      set("glowStacksEnabled", v)
    end, 12)

  local stackField = MakeField(f, "Glow from this many stacks and up", -40, 12, 70,
    function() return get("glowStacks", 1) end,
    function(v) set("glowStacks", math.max(1, tonumber(v) or 1)) end, 2)

  -- One icon can watch several auras: any match lights it up (or, in missing
  -- mode, keeps it hidden).
  local extraFields = {}
  for i = 2, C.MAX_AURA_IDS do
    local key = "id" .. i
    extraFields[i] = MakeField(f, "Extra aura ID " .. i .. " (any of them counts)", -40, 12, 120,
      function() return get(key) end,
      function(v) set(key, (v and v > 0) and v or nil) end)
  end

  local soundDrop = MakeDropdown(f, "Sound when the aura appears", -40, SOUND_OPTIONS,
    function() return get("sound", "none") end,
    function(key)
      set("sound", key)
      C:PlayAlert(key)
    end, 250, 12)

  -- Cooldown blocks -----------------------------------------------------------
  local replaceCheck = MakeCheck(f, "Swap to another spell in some situations", -40,
    function() return get("replaceEnabled", false) end,
    function(v) set("replaceEnabled", v) end, 12)

  local triggerField = MakeField(f, "When you have this aura ID", -40, 12, 120,
    function() return get("replaceTriggerID") end,
    function(v) set("replaceTriggerID", (v and v > 0) and v or nil) end)

  local replaceField = MakeField(f, "...track this spell ID instead", -40, 12, 120,
    function() return get("replaceID") end,
    function(v) set("replaceID", (v and v > 0) and v or nil) end)

  local replaceGlowDrop = MakeDropdown(f, "Glow while the swapped spell is active", -40, GLOW_OPTIONS,
    function() return get("replaceGlow", "none") end,
    function(key) set("replaceGlow", key) end, 250, 12)

  -- Items only: a trinket in the bags stays hidden until it is worn.
  local equippedCheck = MakeCheck(f, "Only show if equipped", -40,
    function() return get("equippedOnly", false) end,
    function(v) set("equippedOnly", v) end, 12)

  local chargeCheck = MakeCheck(f, "Always show the charge number (also at 0 and 1)", -40,
    function() return get("chargeText", false) end,
    function(v) set("chargeText", v) end, 12)

  local glowCheck = MakeCheck(f, "Glow when an aura is on the unit", -40,
    function() return get("glowAuraEnabled", false) end,
    function(v)
      local e = PopupEntry(f)
      if e and v then
        e.glowAuraUnit = e.glowAuraUnit or "player"
        e.glowAuraFilter = e.glowAuraFilter or "buff"
        e.glowAuraType = e.glowAuraType or "pixel"
      end
      set("glowAuraEnabled", v)
    end, 12)

  local glowField = MakeField(f, "Glow when this aura ID is up", -40, 12, 120,
    function() return get("glowAuraID") end,
    function(v) set("glowAuraID", (v and v > 0) and v or nil) end)

  local glowStyleDrop = MakeDropdown(f, "Glow style", -40, GLOW_OPTIONS,
    function() return get("glowAuraType", "pixel") end,
    function(key) set("glowAuraType", key) end, 250, 12)

  local glowUnitDrop = MakeDropdown(f, "Which unit to watch", -40, UNIT_OPTIONS,
    function() return get("glowAuraUnit", "player") end,
    function(key) set("glowAuraUnit", key) end, 250, 12)

  local glowFilterDrop = MakeDropdown(f, "Buff or debuff", -40, FILTER_OPTIONS,
    function() return get("glowAuraFilter", "buff") end,
    function(key) set("glowAuraFilter", key) end, 250, 12)

  local glowStackCheck = MakeCheck(f, "Glow at a number of stacks", -40,
    function() return get("glowAuraStacksEnabled", false) end,
    function(v)
      local e = PopupEntry(f)
      if e and not v then e.glowAuraStacks = 1 end
      set("glowAuraStacksEnabled", v)
    end, 12)

  local glowStackField = MakeField(f, "Glow from this many stacks and up", -40, 12, 70,
    function() return get("glowAuraStacks", 1) end,
    function(v) set("glowAuraStacks", math.max(1, math.min(99, tonumber(v) or 1))) end, 2)

  -- The cooldown glow can watch several auras as well: any match lights it up.
  local glowExtraFields = {}
  for i = 2, C.MAX_AURA_IDS do
    local key = "glowAuraID" .. i
    glowExtraFields[i] = MakeField(f, "Extra glow aura ID " .. i .. " (any of them counts)", -40, 12, 120,
      function() return get(key) end,
      function(v) set(key, (v and v > 0) and v or nil) end)
  end

  local glowSoundDrop = MakeDropdown(f, "Sound when that aura appears", -40, SOUND_OPTIONS,
    function() return get("glowAuraSound", "none") end,
    function(key)
      set("glowAuraSound", key)
      C:PlayAlert(key)
    end, 250, 12)

  -- Reminder auras can start nagging before the buff actually falls off.
  local expireCheck = MakeCheck(f, "Warn me before the buff runs out", -40,
    function() return get("expireWarn", false) end,
    function(v) set("expireWarn", v) end, 12)

  local expireField = MakeField(f, "Seconds left when the warning starts (60 = 1 minute)", -40, 12, 70,
    function() return get("expireWarnAt", 60) end,
    function(v) set("expireWarnAt", math.max(1, math.min(600, tonumber(v) or 60))) end, 3)

  local div = MakeDivider(f, 12)


  -- Footer --------------------------------------------------------------------
  local change = MakeButton(f, "Change", 90, 22, function()
    local bag = f.bag
    local e = PopupEntry(f)
    if not (bag and e) then return end
    C:OpenPicker(f.mode, function(sel)
      local cur = PopupEntry(f)
      if not cur then return end
      cur.kind = sel.kind
      cur.id = sel.id
      C:Rebuild()
      C:RefreshConfig()
      if f:IsShown() then f.sync() end
    end, f.anchorIcon)
  end)
  change:SetPoint("BOTTOMLEFT", 12, 12)

  local remove = MakeButton(f, "Remove icon", 100, 22, function()
    if f.onRemove then f.onRemove() end
    ReturnToModule()
  end)
  remove.text:SetTextColor(0.85, 0.25, 0.22)
  remove:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)

  local okBtn = MakeButton(f, "OK", 80, 22, ReturnToModule)
  okBtn:SetPoint("BOTTOMRIGHT", -12, 12)

  function f.sync()
    local e = PopupEntry(f)
    if not e then f:Hide() return end
    -- The frame and all controls are shared, but their displayed values are
    -- not. Always hydrate every control from the newly selected uid first.
    glowDrop:Sync()
    unitDrop:Sync()
    filterDrop:Sync()
    modeDrop:Sync()
    missingDrop:Sync()
    remindDrop:Sync()
    replaceGlowDrop:Sync()
    glowStyleDrop:Sync()
    glowUnitDrop:Sync()
    glowFilterDrop:Sync()
    soundDrop:Sync()
    glowSoundDrop:Sync()
    local endY
    if f.mode == "aura" then
      NormalizeAura(e)
      local stacksOn = e.glowStacksEnabled and true or false
      local blocks = {
        { glowDrop, true },
        { unitDrop, true },
        { filterDrop, true },
        { onlyMineCheck, true },
        { modeDrop, not f.remindRow },
        { missingDrop, e.mode == "missing" and not f.remindRow },
        { remindDrop, f.remindRow and true or false },
        { div, true },
      }
      for i = 2, C.MAX_AURA_IDS do blocks[#blocks + 1] = { extraFields[i], true } end
      endY = Reflow(-40, blocks)
      local warnOn = e.expireWarn and true or false
      local tail = {
        { expireCheck, (f.remindRow or e.mode == "missing") and true or false },
        { expireField, warnOn and (f.remindRow or e.mode == "missing") and true or false },
        { soundDrop, true },
        { stackCheck, true },
        { stackField, stacksOn },
        -- cooldown-only blocks stay parked
        { equippedCheck, false },
        { replaceCheck, false }, { triggerField, false }, { replaceField, false },
        { replaceGlowDrop, false }, { chargeCheck, false },
        { glowCheck, false }, { glowField, false },
        { glowStyleDrop, false }, { glowUnitDrop, false }, { glowFilterDrop, false },
        { glowStackCheck, false }, { glowStackField, false },
        { glowSoundDrop, false },
      }
      for i = 2, C.MAX_AURA_IDS do tail[#tail + 1] = { glowExtraFields[i], false } end
      endY = Reflow(endY, tail)
      -- Per icon, never shared: rehydrate the tick from this uid's own value.
      onlyMineCheck:Refresh()
      expireCheck:Refresh()
      expireField:Sync()
      stackCheck:Refresh()
      stackField:Sync()
      for i = 2, C.MAX_AURA_IDS do extraFields[i]:Sync() end
    else
      local repOn = e.replaceEnabled and true or false
      local glowOn = e.glowAuraEnabled and true or false
      local parked = {
        { div, true },
        { equippedCheck, e.kind == "item" },
        { replaceCheck, true },
        { triggerField, repOn },
        { replaceField, repOn },
        { replaceGlowDrop, repOn },
        { chargeCheck, true },
        { glowCheck, true },
        { glowField, glowOn },
        { glowStyleDrop, glowOn },
        { glowUnitDrop, glowOn },
        { glowFilterDrop, glowOn },
        { glowStackCheck, glowOn },
        { glowStackField, glowOn and (e.glowAuraStacksEnabled and true or false) },
        { glowSoundDrop, glowOn },
        -- aura-only blocks stay parked
        { glowDrop, false }, { unitDrop, false }, { filterDrop, false },
        { onlyMineCheck, false },
        { modeDrop, false }, { missingDrop, false }, { remindDrop, false },
        { stackCheck, false }, { stackField, false }, { soundDrop, false },
        { expireCheck, false }, { expireField, false },
      }
      for i = 2, C.MAX_AURA_IDS do parked[#parked + 1] = { extraFields[i], false } end
      -- The extra glow IDs belong directly under the main one, so they are
      -- spliced in there instead of trailing the whole block.
      for i = C.MAX_AURA_IDS, 2, -1 do
        for n = 1, #parked do
          if parked[n][1] == glowField then
            table.insert(parked, n + 1, { glowExtraFields[i], glowOn })
            break
          end
        end
      end
      endY = Reflow(-40, parked)
      glowStackCheck:Refresh()
      glowStackField:Sync()
      for i = 2, C.MAX_AURA_IDS do glowExtraFields[i]:Sync() end
      equippedCheck:Refresh()
      replaceCheck:Refresh()
      chargeCheck:Refresh()
      glowCheck:Refresh()
      triggerField:Sync()
      replaceField:Sync()
      glowField:Sync()
    end

    f:SetHeight(math.max(190, -endY + 56))
  end

  iconPopup = f
  return f
end

-- Clicking an icon opens its own settings. bag + uid is the whole identity:
-- nothing here ever touches a neighbouring slot.
local function OpenIconSettings(anchor, bag, entry, mode, label, onRemove)
  if not (entry and entry.uid) then return end
  local f = iconPopup or BuildIconPopup()
  f.bag, f.uid, f.mode, f.onRemove = bag, entry.uid, mode, onRemove
  -- Remember which icon opened this panel so "Change" can drop the spell
  -- picker right next to that icon instead of somewhere else on screen.
  f.anchorIcon = anchor
  -- The reminder row has no found/missing choice: it is always "missing", and
  -- instead it picks when the icon is allowed to nag.
  f.remindRow = bag.remindRow and true or false
  f.title:SetText(label or (mode == "aura" and "Aura slot" or "Cooldown slot"))
  f.sync()
  if iconDetailHost then
    if C.UpdateDetailPanel then C:UpdateDetailPanel(10) end
    f:Show()
  else
    f:Show()
    C:PlaceSettingsWindow(f, _G["JunkieConfig"])
  end
end

local function CloseIconSettings()
  if iconPopup then iconPopup:Hide() end
end


-- Icon grids -------------------------------------------------------------------
-- A grid is driven by a "bag": the stored array plus how to write its count.
-- There are no sliders any more. The row always shows the filled icons plus one
-- empty "+" placeholder, and the stored count follows the filled icons, so a
-- removed icon makes the row collapse to the left both here and on screen.
local dragging   -- { bag = bag, index = n }

-- Smooth motion --------------------------------------------------------------
-- Slots only ever glide when the player actually changed the layout (dropped,
-- added or removed an icon). Every other refresh snaps them into place so the
-- grid never drifts around while other settings are being touched.
local animFrames = {}
local animDriver = CreateFrame("Frame")
animDriver:Hide()
animDriver:SetScript("OnUpdate", function(self, elapsed)
  local k = elapsed * 14
  if k > 1 then k = 1 end
  local any = false
  for f in pairs(animFrames) do
    local done = true
    local dx = f.animDX or 0
    if dx > 0.4 or dx < -0.4 then
      dx = dx * (1 - k)
      done = false
    else
      dx = 0
    end
    f.animDX = dx
    local ta = f.animAlpha or 1
    local a = f:GetAlpha()
    if a - ta > 0.02 or ta - a > 0.02 then
      a = a + (ta - a) * k
      done = false
    else
      a = ta
    end
    f:SetAlpha(a)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", f.animParent, "TOPLEFT", (f.baseX or 0) + dx, f.baseY or 0)
    if done then
      if ta <= 0.01 then f:Hide() end
      animFrames[f] = nil
    else
      any = true
    end
  end
  if not any then self:Hide() end
end)

local function Animate(f)
  animFrames[f] = true
  animDriver:Show()
end

local function Settle(f, alpha)
  animFrames[f] = nil
  f.animDX = 0
  f.animAlpha = alpha
  f:SetAlpha(alpha)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", f.animParent, "TOPLEFT", f.baseX or 0, f.baseY or 0)
  if alpha <= 0.01 then f:Hide() end
end

-- Raised for one refresh by an add, remove or drop.
local layoutChanged = false
local function LayoutChanged() layoutChanged = true end



-- The lifted icon that follows the cursor while dragging.
local ghost
local function GhostShow(tex, size)
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:EnableMouse(false)
    ghost:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2,
    })
    ghost:SetBackdropColor(BG[1], BG[2], BG[3], 0.9)
    ghost:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetPoint("TOPLEFT", 3, -3)
    ghost.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ghost:SetScript("OnUpdate", function(self, elapsed)
      -- ~100Hz is far past what the eye resolves on a dragged icon, and it
      -- keeps the anchor churn off the frame budget on slower machines.
      self.t = (self.t or 0) + (elapsed or 0)
      if self.t < 0.01 then return end
      self.t = 0
      local s = UIParent:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      if cx == self.cx and cy == self.cy then return end
      self.cx, self.cy = cx, cy
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s, cy / s)
    end)
  end
  ghost:SetSize(size, size)
  ghost.icon:SetTexture(tex)
  -- Force the throttled OnUpdate to reposition on its very first tick so the
  -- ghost never flashes at the spot where the previous drag ended.
  ghost.t, ghost.cx, ghost.cy = 1, nil, nil
  ghost:Show()
end

local function GhostHide()
  if ghost then ghost:Hide() end
end


local function BagCompact(bag)
  local arr = bag.list()
  local out = {}
  for i = 1, bag.max do
    if arr[i] and arr[i].id then out[#out + 1] = arr[i] end
  end
  for i = 1, bag.max do arr[i] = out[i] end
  local n = math.min(#out, bag.max)
  bag.setCount(n)
  return n
end

local function BagFilled(bag)
  local arr = bag.list()
  local n = 0
  for i = 1, bag.max do
    if arr[i] and arr[i].id then n = n + 1 else break end
  end
  return n
end

local function BagSet(bag, i, entry)
  bag.list()[i] = entry
  BagCompact(bag)
end

local function BagRemoveUID(bag, uid)
  if not uid then return false end
  local arr = bag.list()
  for i = 1, bag.max do
    local entry = arr[i]
    if entry and entry.uid == uid then
      arr[i] = nil
      BagCompact(bag)
      return true
    end
  end
  return false
end

-- Drag & drop: pull an icon out of one row and drop it anywhere in the same
-- family (cooldown rows together, aura rows together). The source row closes
-- its hole and the target row opens one at the drop position.
local function DropOn(target, index)
  if not dragging then return end
  local src, si = dragging.bag, dragging.index
  dragging = nil
  if not src or src.group ~= target.group then return end
  local entry = src.list()[si]
  if not entry then return end

  if src == target then
    local arr = src.list()
    table.remove(arr, si)
    table.insert(arr, math.min(index, #arr + 1), entry)
    BagCompact(src)
  else
    if BagFilled(target) >= target.max then return end
    src.list()[si] = nil
    BagCompact(src)
    local arr = target.list()
    table.insert(arr, math.min(index, BagFilled(target) + 1), entry)
    BagCompact(target)
  end
  LayoutChanged()
  C:RefreshConfig()
  C:Rebuild()
end

local function MakeGrid(parent, x, y, bag)
  local slots = {}
  local mode = bag.mode
  local max = bag.max
  local pixel = bag.pixelUnit
  local function GridSnap(v)
    if not pixel then return v end
    return math.floor(v / pixel + 0.5) * pixel
  end
  -- Cooldown rows use slightly larger icons than the aura rows; the size is
  -- handed in by the module so every other element can follow the same width.
  local slotSize = GridSnap(bag.slotSize or 34)
  local slotPitch = GridSnap(bag.slotPitch or 36)
  local iconInset = GridSnap(2)
  local function getEntry(i) return bag.list()[i] end
  -- Every icon owns its own table and its own uid. Nothing in the grid ever
  -- copies one icon's settings into another slot.
  local function setEntry(i, e)
    if e and not e.uid then e.uid = C:NextUID() end
    BagSet(bag, i, e)
  end




  for i = 1, max do
    -- Lua 5.1 reuses the numeric-for control variable. Every callback must
    -- capture its own immutable slot number or all icons can end up operating
    -- on the same slot after the loop has finished.
    local slotIndex = i
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(slotSize, slotSize)
    b.animParent, b.baseX, b.baseY = parent, GridSnap(x + (slotIndex - 1) * slotPitch), GridSnap(y)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", b.baseX, b.baseY)
    Flat(b, BG[1], BG[2], BG[3], 1)
    if pixel then
      b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = pixel })
      b:SetBackdropColor(BG[1], BG[2], BG[3], 1)
    end
    b:SetBackdropBorderColor(EDGE_OFF[1], EDGE_OFF[2], EDGE_OFF[3], 1)
    AddHover(b, pixel)

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.jcdBag, b.jcdIndex = bag, slotIndex


    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", iconInset, -iconInset)
    b.icon:SetPoint("BOTTOMRIGHT", -iconInset, iconInset)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.plus = Label(b, 16, "CENTER")
    b.plus:SetPoint("CENTER")
    b.plus:SetText("+")
    b.plus:SetTextColor(EDGE_OFF[1], EDGE_OFF[2], EDGE_OFF[3])


    b.tagR = Label(b, 9, "RIGHT")
    b.tagR:SetPoint("BOTTOMRIGHT", -2, 2)
    b.tagR:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])


    b.unitTag = Label(b, 9, "LEFT")
    b.unitTag:SetPoint("TOPLEFT", 2, -2)
    b.unitTag:SetTextColor(DIM[1], DIM[2], DIM[3])

    -- Plain left click and hold lifts the icon: it grows 15%, gets an orange
    -- frame and follows the cursor until it is dropped on another slot.
    b:SetScript("OnDragStart", function(self)
      local entry = getEntry(slotIndex)
      if not entry or not entry.id then return end
      dragging = { bag = bag, index = slotIndex }
      local _, tex = EntryLabel(entry)
      GhostShow(tex, math.floor(self:GetWidth() * 1.15 + 0.5))
      self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
      self.icon:SetAlpha(0.25)
      CloseIconSettings()
      GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
      GhostHide()
      self:SetBackdropBorderColor(EDGE_DARK[1], EDGE_DARK[2], EDGE_DARK[3], 1)
      self.icon:SetAlpha(1)
      if not dragging then return end
      local focus = GetMouseFocus()
      if focus and focus.jcdBag then
        DropOn(focus.jcdBag, focus.jcdIndex)
      else
        dragging = nil
      end
    end)


    b:SetScript("OnClick", function(self, button)
      if C.SelectCanvasElement and bag.moduleFrame then C:SelectCanvasElement(bag.moduleFrame) end
      if bag.detailPage and C.UpdateDetailPanel then C:UpdateDetailPanel(bag.detailPage) end
      if button == "RightButton" then
        setEntry(slotIndex, nil)
        CloseIconSettings()
        LayoutChanged()
        C:RefreshConfig()
        C:Rebuild()
        return
      end
      local entry = getEntry(slotIndex)
      if entry and entry.id then
        -- A filled slot opens its own settings; the picker only ever runs on
        -- an empty slot or from the Change button inside the popup.
        local label = (EntryLabel(entry) or (mode == "aura" and "Aura" or "Cooldown"))
          .. "  (ID " .. entry.id .. ")"
        local selectedUID = entry.uid
        OpenIconSettings(self, bag, entry, mode, label, function()
          if BagRemoveUID(bag, selectedUID) then
            LayoutChanged()
            C:RefreshConfig()
            C:Rebuild()
          end
        end)
        return
      end
      C:OpenPicker(mode, function(sel)
        setEntry(slotIndex, {
          kind = sel.kind,
          id = sel.id,
          glow = "none",
          unit = "player",
          filter = "buff",
        })
        LayoutChanged()
        C:RefreshConfig()
        C:Rebuild()
      end, self)
    end)

    b:SetScript("OnEnter", function(self)
      local entry = getEntry(slotIndex)
      -- Mouseover lights the resting deep orange frame up to the bright one.
      self.jcdHover = true
      self:SetBackdropBorderColor(EDGE_HOT[1], EDGE_HOT[2], EDGE_HOT[3], 1)
      if self.plus and self.plus:IsShown() then
        self.plus:SetTextColor(EDGE_HOT[1], EDGE_HOT[2], EDGE_HOT[3])
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

      if not entry or not entry.id then
        GameTooltip:AddLine("Empty slot", 1, 1, 1)
        GameTooltip:AddLine("Click to pick a " .. (mode == "aura" and "aura" or "spell or item")
          .. ". A new empty slot appears next to it.", DIM[1], DIM[2], DIM[3], true)
        GameTooltip:Show()
        return
      end
      local name = EntryLabel(entry)
      GameTooltip:AddLine(name or "?", 1, 1, 1)
      GameTooltip:AddLine("ID " .. entry.id, DIM[1], DIM[2], DIM[3])
      if self.jcdMissing then
        GameTooltip:AddLine("Not in your spellbook right now - hidden on the bar until you learn it again",
          0.85, 0.25, 0.22, true)
      end

      if mode == "aura" then
        GameTooltip:AddLine("Reads: " .. UnitInfo(entry.unit).name .. " " ..
          ((entry.filter == "debuff") and "debuff" or "buff"), DIM[1], DIM[2], DIM[3])
        GameTooltip:AddLine("Glow: " .. (entry.glow or "none"), DIM[1], DIM[2], DIM[3])
      end
      GameTooltip:AddLine("Drag to reorder or to move it to another row", DIM[1], DIM[2], DIM[3])
      GameTooltip:AddLine("Click it to open only this icon's settings", DIM[1], DIM[2], DIM[3])
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
      self.jcdHover = nil
      local e = self.jcdEdge or EDGE_OFF
      self:SetBackdropBorderColor(e[1], e[2], e[3], 1)
      if self.plus then self.plus:SetTextColor(EDGE_OFF[1], EDGE_OFF[2], EDGE_OFF[3]) end
      GameTooltip:Hide()
    end)

    slots[slotIndex] = b
  end

  -- Which slot each entry table sat in last refresh. Keyed by the entry table
  -- itself, so two icons that share the same spell ID never confuse each other.
  local prevIndex = {}

  -- The slot mirrors what the icon will look like in game: grayscale when the
  -- aura is tracked while missing, and the chosen glow running live.
  local function Preview(b, entry)
    local kind
    if mode == "aura" then
      kind = entry and entry.glow or "none"
      b.icon:SetDesaturated((entry and entry.mode == "missing"
        and entry.missingStyle == "grayscale") and true or false)
    else
      kind = (entry and entry.glowAuraEnabled) and (entry.glowAuraType or "pixel") or "none"
      b.icon:SetDesaturated(false)
    end
    local show = (entry and entry.id and kind and kind ~= "none") and true or false
    C:SetGlow(b, show and kind or nil, show)
  end

  local function refresh()
    local on = (not bag.enabled) or bag.enabled()
    local filled = BagCompact(bag)
    local shown = on and math.min(max, filled + 1) or 0
    local nextIndex = {}
    for i = 1, max do
      local b = slots[i]
      if i <= shown then
        local wasShown = b:IsShown()
        b:Show()
        -- A reversed row is laid out right to left: slot 1 sits on the right
        -- edge and the trailing empty (+) slot lands on the left.
        if bag.reverse then
          local nx = GridSnap((shown - i) * slotPitch)
          if b.baseX ~= nx then
            b.baseX = nx
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", parent, "TOPLEFT", nx, b.baseY)
          end
        end
        local entry = getEntry(i)

        local _, tex = EntryLabel(entry)
        if tex then
          b.icon:SetTexture(tex)
          b.icon:SetAlpha(1)
          b.plus:Hide()
        else
          b.icon:SetTexture(nil)
          b.plus:Show()
        end
        if mode == "aura" then
          NormalizeAura(entry)
          b.tagR:SetText("")
          b.unitTag:SetText(entry and entry.id
            and (UnitInfo(entry.unit).tag .. ((entry.filter == "debuff") and "d" or "b")) or "")
        else
          b.tagR:SetText("")
          b.unitTag:SetText(entry and entry.replaceEnabled and "R" or "")
        end
        Preview(b, entry)
        -- A cooldown the player does not own right now is kept in the list but
        -- marked with a red frame; it is hidden on the bar until it comes back.
        b.jcdMissing = (mode ~= "aura" and entry and entry.id and not C:EntryKnown(entry)) and true or false
        if b.jcdMissing then
          b.jcdEdge = { 0.85, 0.25, 0.22 }
        elseif entry and entry.id then
          b.jcdEdge = { EDGE_DARK[1], EDGE_DARK[2], EDGE_DARK[3] }
        else
          -- Empty slot: the deep orange (+) box; it brightens on mouseover.
          b.jcdEdge = { EDGE_OFF[1], EDGE_OFF[2], EDGE_OFF[3] }
        end
        if b.jcdHover then
          b:SetBackdropBorderColor(EDGE_HOT[1], EDGE_HOT[2], EDGE_HOT[3], 1)
        else
          b:SetBackdropBorderColor(b.jcdEdge[1], b.jcdEdge[2], b.jcdEdge[3], 1)
        end


        if not layoutChanged then
          Settle(b, 1)
        else
          -- Slide the icon in from the slot it left, and fade a new slot in.
          b.animAlpha = 1
          local from = entry and prevIndex[entry]
          if not wasShown then
            b:SetAlpha(0)
            b.animDX = 0
            Animate(b)
          elseif from and from ~= i then
            b.animDX = (from - i) * slotPitch
            Animate(b)
          end
        end
        if entry then nextIndex[entry] = i end
      else
        if b:IsShown() then
          if layoutChanged then
            b.animAlpha = 0
            Animate(b)
          else
            Settle(b, 0)
          end
        end
        C:SetGlow(b, nil, false)
      end

    end
    prevIndex = nextIndex
  end


  refresh()
  table.insert(refreshers, refresh)
  return slots, refresh
end



-- Serialization ----------------------------------------------------------------
local function Serialize(v, indent)
  local t = type(v)
  if t == "number" then return tostring(v) end
  if t == "boolean" then return v and "true" or "false" end
  if t == "string" then return string.format("%q", v) end
  if t ~= "table" then return "nil" end
  local parts = { "{" }
  for k, val in pairs(v) do
    local key
    if type(k) == "number" then key = "[" .. k .. "]" else key = "[" .. string.format("%q", k) .. "]" end
    table.insert(parts, key .. "=" .. Serialize(val) .. ",")
  end
  table.insert(parts, "}")
  return table.concat(parts)
end

function C:ExportProfile()
  local p = C:Profile()
  return "JCD1:" .. Serialize(p)
end

function C:ImportProfile(str)
  if type(str) ~= "string" then return false, "empty" end
  local body = str:match("^%s*JCD1:(.+)%s*$")
  if not body then return false, "not a JCD profile string" end
  local fn = loadstring("return " .. body)
  if not fn then return false, "corrupt string" end
  setfenv(fn, {})
  local ok, data = pcall(fn)
  if not ok or type(data) ~= "table" then return false, "corrupt data" end
  local base = C:NewProfile(data.name or "Imported")
  for k, v in pairs(data) do base[k] = v end
  local name = base.name or "Imported"
  while C.db.profiles[name] do name = name .. "*" end
  base.name = name
  C.db.profiles[name] = base
  C:UseProfile(name, true)
  return true, name
end

-- Canvas helpers ---------------------------------------------------------------
local function CanvasOptions()
  local out = { { key = -1, name = "Base canvas (no form)" } }
  for f = 0, C:StanceCount() do
    table.insert(out, { key = f, name = "Form: " .. C:StanceName(f) })
  end
  return out
end

local function CDSet()
  return C:EditSet(C.editForm) or C:Profile()
end

-- The three universal bar slots of the set that is being edited. Which one the
-- detail panel shows is remembered on the namespace, so both the canvas and the
-- settings page always talk about the very same slot.
C.editBarSlot = C.editBarSlot or 1

local function BarList()
  local set = C:EditSet(C.editPowerForm) or C:Profile()
  return C:MigrateBars(set, set.combo)
end

local function BarCfg(index)
  local list = BarList()
  return list[index or C.editBarSlot or 1] or list[1]
end

-- Session clipboard for moving a cooldown row between the base canvas and a
-- stance/shapeshift canvas. Entries are cloned so later edits never leak back
-- into the copied source row.
local canvasClipboard = {}

local function CloneValue(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, child in pairs(value) do
    -- Imported canvas entries are new icons and must not inherit an identity
    -- from the source canvas.
    if key ~= "uid" then copy[CloneValue(key)] = CloneValue(child) end
  end
  return copy
end

local function CopyCanvasRow(kind)
  local set = CDSet()
  local list = kind == "main" and set.main or set.sub
  canvasClipboard[kind] = CloneValue(list or {})
  print("|cffde7230JunkieCD|r " .. (kind == "main" and "main" or "secondary") .. " canvas copied.")
end

local function ImportCanvasRow(kind)
  local copied = canvasClipboard[kind]
  if not copied then
    print("|cffde7230JunkieCD|r copy a " .. (kind == "main" and "main" or "secondary") .. " canvas first.")
    return
  end
  local set = CDSet()
  local list = CloneValue(copied)
  local count = 0
  for i = 1, C.MAX_ICONS do
    if list[i] and list[i].id then
      list[i].uid = C:NextUID()
      count = count + 1
    end
  end
  if kind == "main" then
    set.main = list
    set.mainEnabled = count > 0
    set.mainCount = count
  else
    set.sub = list
    set.subEnabled = count > 0
    set.subCount = count
  end
  LayoutChanged()
  C:RefreshConfig()
  C:Rebuild()
  print("|cffde7230JunkieCD|r " .. (kind == "main" and "main" or "secondary") .. " canvas imported.")
end

-- Panel ------------------------------------------------------------------------
-- The panel is hosted inside the JunkieUI settings window: JunkieUI hands us
-- a frame and we fill it. There is no standalone JunkieCD window.
local function HidePanel()
  if JunkieUI and JunkieUI.CloseConfig then JunkieUI:CloseConfig() end
end

local function BuildPanel(host)
  panel = host
  local width = host:GetWidth()
  if not width or width < 200 then width = 620 end
  local height = host:GetHeight()
  if not height or height < 200 then height = 640 end

  -- Shell: three top tabs (General / Canvas / Profiles). The old multi entry
  -- sidebar is gone; every page body below is untouched and only gets a new
  -- parent - General and Profiles fill the whole body, the remaining pages are
  -- the detail views of the canvas tab.
  local TAB_H, TAB_GAP, SPLIT_GAP = 24, 6, 6
  -- The canvas got 20% taller and then another 10%: it is the builder now, and
  -- it grows downwards into the settings area, which scrolls anyway.
  local PREVIEW_H = math.floor(height * 0.42 * 1.2 * 1.1)
  local bodyH = height - TAB_H - TAB_GAP
  local detailH = bodyH - PREVIEW_H - SPLIT_GAP


  local pages, detailPages = {}, {}

  -- Refreshers that only touch the canvas mockups. The live loop on the canvas
  -- tab runs these alone, never the whole settings window.
  local canvasRefreshers = {}
  local function AddCanvasRefresh(fn)
    table.insert(refreshers, fn)
    table.insert(canvasRefreshers, fn)
  end
  C.RefreshCanvas = function()
    for _, fn in ipairs(canvasRefreshers) do fn() end
  end

  local tabStrip = CreateFrame("Frame", nil, panel)
  tabStrip:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  tabStrip:SetSize(width, TAB_H)
  tabStrip:Show()

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -TAB_GAP)
  body:SetSize(width, bodyH)
  body:Show()

  local function Container()
    local f = CreateFrame("Frame", nil, body)
    f:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    f:SetSize(width, bodyH)
    return f
  end

  local generalTab, canvasTab, profilesTab = Container(), Container(), Container()

  -- Canvas tab split: preview on top, the reused settings pages below.
  local preview = CreateFrame("Frame", "JunkieCDCanvasPreview", canvasTab)
  preview:SetPoint("TOPLEFT", canvasTab, "TOPLEFT", 0, 0)
  preview:SetSize(width, PREVIEW_H)
  Flat(preview, CANVAS_BG[1], CANVAS_BG[2], CANVAS_BG[3], 1)
  preview:SetBackdropBorderColor(EDGE_UI[1], EDGE_UI[2], EDGE_UI[3], 1)

  -- Everything the canvas draws lives in one scaled container so the mockups
  -- read a little larger than the surrounding chrome.
  local CANVAS_SCALE = 0.75
  local content = CreateFrame("Frame", nil, preview)
  content:SetScale(CANVAS_SCALE)

  -- Pixel lock, take three. Snapping coordinates is not enough on its own:
  -- if the container's own scale is not a whole number of screen pixels per
  -- unit, every "snapped" edge still lands between pixels and thin borders
  -- drop out. So instead of rounding the coordinates we round the SCALE:
  -- the container is scaled so that one local unit is exactly N real screen
  -- pixels. After that every integer coordinate is automatically perfect and
  -- the pixel step is simply 1.
  local PX_STEP = 1
  local function PhysicalPixel()
    local _, resH = string.match(GetCVar("gxResolution") or "", "(%d+)x(%d+)")
    resH = tonumber(resH) or 768
    return 768 / resH
  end
  local function ApplyPixelLock()
    local perfect = PhysicalPixel()
    local parentScale = preview:GetEffectiveScale() or 1
    if parentScale <= 0 then parentScale = 1 end
    -- Desired effective scale, rounded to a whole number of real pixels.
    local units = math.floor((CANVAS_SCALE * parentScale) / perfect + 0.5)
    if units < 1 then units = 1 end
    local target = units * perfect
    content:SetScale(target / parentScale)
    -- The container itself must also start on a whole screen pixel, otherwise
    -- the whole grid inside it is offset by a fraction.
    local w = math.floor(width / (target / parentScale) + 0.5)
    local h = math.floor(PREVIEW_H / (target / parentScale) + 0.5)
    content:SetSize(w, h)
    local offX = math.floor((width - w * (target / parentScale)) / 2 + 0.5)
    local offY = math.floor(PREVIEW_H * 0.10 + 0.5) - 20
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", preview, "TOPLEFT", offX, -offY)
  end
  local function Snap(v)
    v = tonumber(v) or 0
    if v < 0 then return -math.floor(-v + 0.5) end
    return math.floor(v + 0.5)
  end
  local function SnapSize(v)
    local s = Snap(v)
    if s < 1 then s = 1 end
    return s
  end
  ApplyPixelLock()
  preview:HookScript("OnShow", ApplyPixelLock)



  -- Bottom half: a real scroll frame, so a long settings page can be reached
  -- even when the taller canvas eats the space.
  local detail = CreateFrame("Frame", "JunkieCDCanvasDetail", canvasTab)
  detail:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -SPLIT_GAP)
  detail:SetSize(width, detailH)
  Flat(detail, BOX[1], BOX[2], BOX[3], 1)

  local PAGE_H = math.max(detailH, 640)
  local PAGE_W = width - 24

  local scroll = CreateFrame("ScrollFrame", "JunkieCDDetailScroll", detail, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", detail, "TOPLEFT", 2, -2)
  scroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -22, 2)

  -- Any scrolling closes open dropdowns: an open list is anchored to a widget
  -- that just moved, so leaving it up would draw it detached from its button.
  scroll:HookScript("OnVerticalScroll", function() CloseLists(nil) end)
  scroll:HookScript("OnMouseWheel", function() CloseLists(nil) end)
  local detailBar = _G["JunkieCDDetailScrollScrollBar"]
  if detailBar then
    detailBar:HookScript("OnValueChanged", function() CloseLists(nil) end)
  end



  local scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(PAGE_W, PAGE_H)
  scroll:SetScrollChild(scrollChild)

  -- Page frames. Numbers stay exactly as they were so the page bodies further
  -- down do not have to be renumbered.
  local function NewPage(index, parent, isDetail, w, h)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    p:SetSize(w, h)
    Flat(p, BOX[1], BOX[2], BOX[3], 1)
    p:Hide()
    pages[index] = p
    if isDetail then detailPages[index] = true end
    return p
  end

  NewPage(1, generalTab, false, width, bodyH)
  NewPage(5, profilesTab, false, width, bodyH)
  for _, i in ipairs({ 9, 2, 6, 3, 7, 4, 8, 10, 11 }) do
    NewPage(i, scrollChild, true, PAGE_W, PAGE_H)
  end
  iconDetailHost = pages[10]


  -- Detail view swap: clicking a module in the preview loads the existing
  -- widgets for that element into the bottom half. Page 9 is the global canvas
  -- page shown when nothing in particular is selected.
  local DEFAULT_DETAIL = 9

  -- Scroll range follows the page: a short page must not scroll at all, a long
  -- one only as far as its last widget.
  local function PageExtent(p)
    local top = p:GetTop()
    if not top then return nil end
    local low = top
    local function Consider(region)
      if not region or region.skipExtent then return end
      if region.IsShown and not region:IsShown() then return end
      local b = region.GetBottom and region:GetBottom()
      if b and b < low then low = b end
    end
    for _, child in ipairs({ p:GetChildren() }) do Consider(child) end
    for _, region in ipairs({ p:GetRegions() }) do Consider(region) end
    return top - low
  end

  local function LockScroll(index)
    local p = pages[index]
    if not p then return end
    local visible = scroll:GetHeight() or detailH
    local needed = PageExtent(p)
    local h = math.max(visible, (needed or 0) + 24)
    p:SetHeight(h)
    scrollChild:SetHeight(h)
    scroll:UpdateScrollChildRect()
    local canScroll = h > visible + 1
    scroll:EnableMouseWheel(canScroll)
    local bar = _G["JunkieCDDetailScrollScrollBar"]
    if bar then if canScroll then bar:Show() else bar:Hide() end end
  end

  local function ShowDetail(index)
    if not detailPages[index] then index = DEFAULT_DETAIL end
    CloseLists(nil)
    for i in pairs(detailPages) do
      if i == index then pages[i]:Show() else pages[i]:Hide() end
    end
    detail.current = index
    -- A fresh detail view always starts at the top of the scroll area.
    scroll:SetVerticalScroll(0)
    LockScroll(index)
  end
  C.UpdateDetailPanel = function(_, index) ShowDetail(index) end

  -- Live canvas: while the Canvas tab is open the mockups follow every change
  -- immediately. The driver is created hidden and only runs on that tab, so it
  -- costs nothing anywhere else in the interface.
  local liveDriver = CreateFrame("Frame", nil, canvasTab)
  liveDriver:Hide()
  liveDriver:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    -- 10 Hz is sufficient for live settings feedback. RefreshCanvas rebuilds
    -- several mock grids, so 30 Hz caused avoidable frame-time spikes while
    -- the canvas editor was open.
    if self.t < 0.1 then return end
    self.t = 0
    -- Hard stop: the loop dies the moment the canvas tab, the settings body or
    -- the whole settings window is no longer on screen.
    if not (canvasTab:IsShown() and panel:IsShown() and panel:IsVisible()) then
      self:Hide()
      return
    end
    C:RefreshCanvas()
  end)

  local tabButtons = {}
  local function SelectTab(which)
    CloseLists(nil)
    for i, b in ipairs(tabButtons) do b.selected = (i == which); b:Refresh() end
    if which == 1 then generalTab:Show() else generalTab:Hide() end
    if which == 2 then canvasTab:Show() else canvasTab:Hide() end
    if which == 3 then profilesTab:Show() else profilesTab:Hide() end
    pages[1]:Hide(); pages[5]:Hide()
    if which == 1 then pages[1]:Show() end
    if which == 3 then pages[5]:Show() end
    if which == 2 then ShowDetail(detail.current or DEFAULT_DETAIL) end
    -- Only the canvas tab gets the live refresh loop.
    if which == 2 then liveDriver:Show() else liveDriver:Hide() end
  end
  canvasTab:SetScript("OnHide", function() liveDriver:Hide() end)
  panel:HookScript("OnHide", function() liveDriver:Hide() end)


  local TAB_NAMES = { "General", "Canvas", "Profiles" }
  for i, name in ipairs(TAB_NAMES) do
    local b = MakeButton(tabStrip, name, 120, TAB_H, function() SelectTab(i) end)
    b:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", (i - 1) * 126, 0)
    tabButtons[i] = b
  end

  -- Legacy entry point: old code (and the JunkieUI page) still asks for a page
  -- number, so map it onto the new three-tab shell.
  local function Select(index)
    if index == 1 then SelectTab(1)
    elseif index == 5 then SelectTab(3)
    else SelectTab(2); ShowDetail(index) end
  end
  C.OpenConfigPage = function(_, index) Select(index or 1) end

  -- Canvas builder ------------------------------------------------------------
  -- Original MakeGrid modules are created with their legacy page as parent and
  -- then physically moved into the top canvas. There is no second icon renderer.
  local canvasBG = CreateFrame("Button", nil, preview)
  canvasBG:SetAllPoints(preview)
  canvasBG:SetFrameLevel(preview:GetFrameLevel())
  -- Element focus: while one canvas element is being edited every other
  -- element is faded back so it is obvious what the settings below belong to.
  -- The stance switch, the canvas picker and the copy / import buttons are the
  -- canvas chrome and always stay at full strength.
  local canvasElements = {}
  local selectedElement

  -- Lightbox: one black overlay covering the whole canvas. It fades in when an
  -- element is being edited; the element itself is lifted above the overlay and
  -- every other element fades back to 50% so the focus is obvious.
  local dimmer = CreateFrame("Frame", nil, preview)
  dimmer:SetAllPoints(preview)
  dimmer:SetFrameStrata(preview:GetFrameStrata())
  dimmer:SetFrameLevel((preview:GetFrameLevel() or 1) + 40)
  dimmer:EnableMouse(false)
  local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
  dimTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
  dimTex:SetAllPoints(dimmer)
  dimTex:SetVertexColor(0, 0, 0, 0.5)
  dimmer:SetAlpha(0)
  dimmer:Hide()

  -- Shared fader: one OnUpdate walks the frames that are still moving, so a
  -- selection change never spawns a timer per element.
  local FADE_TIME = 0.18
  local fading, faderHost = {}, CreateFrame("Frame", nil, preview)
  faderHost:Hide()
  faderHost:SetScript("OnUpdate", function(_, elapsed)
    local active = false
    for f, target in pairs(fading) do
      local cur = f:GetAlpha() or 1
      local step = elapsed / FADE_TIME
      if math.abs(target - cur) <= step then
        f:SetAlpha(target)
        fading[f] = nil
        if target <= 0 and f == dimmer then f:Hide() end
      else
        f:SetAlpha(cur + (target > cur and step or -step))
        active = true
      end
    end
    if not active then faderHost:Hide() end
  end)

  local function FadeTo(f, target)
    if not f then return end
    if target > 0 and not f:IsShown() then
      f:SetAlpha(0)
      f:Show()
    end
    if (f:GetAlpha() or 1) == target then
      fading[f] = nil
      if target <= 0 and f == dimmer then f:Hide() end
      return
    end
    fading[f] = target
    faderHost:Show()
  end

  local function RegisterElement(frame)
    if frame then canvasElements[#canvasElements + 1] = frame end
    return frame
  end

  local function ClearElevation(f)
    if not f then return end
    if f.jcdBaseLevel then
      f:SetFrameLevel(f.jcdBaseLevel)
      f.jcdBaseLevel = nil
    end
    if f.jcdBaseStrata then
      f:SetFrameStrata(f.jcdBaseStrata)
      f.jcdBaseStrata = nil
    end
  end

  local function Elevate(f)
    if not f then return end
    f.jcdBaseLevel = f.jcdBaseLevel or f:GetFrameLevel()
    f.jcdBaseStrata = f.jcdBaseStrata or f:GetFrameStrata()
    f:SetFrameStrata(dimmer:GetFrameStrata())
    f:SetFrameLevel(dimmer:GetFrameLevel() + 10)
  end

  local function ApplyElementFocus()
    for _, f in ipairs(canvasElements) do
      if f ~= selectedElement then ClearElevation(f) end
      FadeTo(f, (selectedElement and f ~= selectedElement) and 0.5 or 1)
    end
    if selectedElement then
      Elevate(selectedElement)
      FadeTo(dimmer, 1)
    else
      FadeTo(dimmer, 0)
    end
  end
  local function SelectElement(frame)
    if selectedElement and selectedElement ~= frame then ClearElevation(selectedElement) end
    selectedElement = frame
    ApplyElementFocus()
  end

  C.SelectCanvasElement = function(_, frame) SelectElement(frame) end

  canvasBG:SetScript("OnClick", function() SelectElement(nil); ShowDetail(9) end)


  -- Canvas chrome is a single title now. The stance switch, the canvas picker
  -- and the copy / import buttons live in the settings panel below the canvas.
  local canvasTitle = Label(preview, 11, "LEFT")
  canvasTitle:SetPoint("TOPLEFT", preview, "TOPLEFT", 10, -10)
  canvasTitle:SetTextColor(1, 1, 1)
  canvasTitle:SetText("CANVAS")
  local function UpdateCanvasTitle()
    local form = C.editForm
    if C:Profile().stanceEnabled and form then
      canvasTitle:SetText("CANVAS: " .. string.upper(C:StanceName(form) or "FORM"))
    else
      canvasTitle:SetText("CANVAS")
    end
  end
  AddCanvasRefresh(UpdateCanvasTitle)
  table.insert(refreshers, UpdateCanvasTitle)





  local function GridModule(page, bag)
    local frame = CreateFrame("Button", nil, content)
    bag.pixelUnit = PX_STEP
    local slotPitch = Snap(bag.slotPitch or 36)
    frame.jcdSlotPitch = slotPitch
    frame.jcdSlotSize = Snap(bag.slotSize or 34)
    frame:SetSize(bag.max * slotPitch, slotPitch)
    frame:SetScript("OnClick", function() SelectElement(frame); ShowDetail(page) end)
    bag.detailPage = page
    bag.moduleFrame = frame
    RegisterElement(frame)

    -- MakeGrid creates the real picker/drag/drop slots once. They remain children
    -- of their functional module frame when that whole frame is placed in Canvas.
    frame.slots, frame.jcdRefresh = MakeGrid(frame, 0, 0, bag)
    -- The live canvas loop has to drive the real grids too, otherwise only the
    -- mockup bars followed the settings and the icon rows looked frozen.
    AddCanvasRefresh(frame.jcdRefresh)
    frame:ClearAllPoints()
    return frame
  end

  -- Icon rows anchored on TOP / BOTTOM are centred on the power bars. Their
  -- frame is as wide as all slots, so it is trimmed to the visible ones after
  -- every refresh, otherwise a half filled row looks shifted to the left.
  local centeredGrids = {}
  local function PlaceGrid(frame, point, relativeTo, relativePoint, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
    if point == "TOP" or point == "BOTTOM" then
      centeredGrids[#centeredGrids + 1] = frame
    end
  end
  local function SetEnabledFromCount(set, key, count)
    set[key .. "Enabled"] = count > 0
    set[key .. "Count"] = count
  end

  -- Layout follows the mockup: one central block in the middle of the canvas,
  -- the aura rows floating above it, the player frame on its left and the
  -- target frame on its right.
  -- Cooldown icons are one pixel larger than the aura icons; every bar under
  -- them is width synced to the main row, so the whole stack follows along.
  local CD_SLOT_SIZE, CD_SLOT_PITCH = 35, 37
  local GRID_W = C.MAX_ICONS * CD_SLOT_PITCH
  local BAR_H = 16   -- multiple of the pixel step, so no half pixel edges

  -- Central block, built bottom to top: secondary CDs, main CDs, power 2,
  -- power 1, combo points and - when it is switched on - the castbar.
  local function SelectBarSlot(index)
    C.editBarSlot = index
    ShowDetail(4)
    C:RefreshConfig()
  end

  -- A mockup bar keeps the colour it was given: the plain button refresh would
  -- paint it back to panel grey the moment the mouse leaves it.
  local function MockBar(w, h, onClick)
    local b
    b = MakeButton(content, "", w, h, function() SelectElement(b); if onClick then onClick() end end)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = PX_STEP })
    b.mock = { MOCK_OFF[1], MOCK_OFF[2], MOCK_OFF[3] }
    b.on = true
    -- An inactive bar carries the same subtle (+) as an empty icon slot instead
    -- of a name, so the canvas reads the same way everywhere. It sits one pixel
    -- above the centre: the glyph's own bearing makes a true centre look low.
    b.plus = Label(b, 14, "CENTER")
    b.plus:SetPoint("CENTER", b, "CENTER", 0, PX_STEP)
    b.plus:SetText("+")
    b.plus:SetTextColor(EDGE_OFF[1], EDGE_OFF[2], EDGE_OFF[3])
    b.plus:Hide()
    function b:Refresh()
      local c = self.mock
      if self.on then
        self:SetBackdropColor(c[1], c[2], c[3], 1)
        self:SetBackdropBorderColor(EDGE_DARK[1], EDGE_DARK[2], EDGE_DARK[3], 1)
        self.plus:Hide()
        self.text:SetText(self.pendingText or "")
      else
        -- Inactive bar: flat body inside a deep orange frame with the (+).
        self:SetBackdropColor(MOCK_OFF[1], MOCK_OFF[2], MOCK_OFF[3], 1)
        self:SetBackdropBorderColor(EDGE_OFF[1], EDGE_OFF[2], EDGE_OFF[3], 1)
        self.text:SetText("")
        self.plus:SetTextColor(EDGE_OFF[1], EDGE_OFF[2], EDGE_OFF[3])
        self.plus:Show()
      end
      self.text:SetTextColor(TXT[1], TXT[2], TXT[3])
    end
    -- Callers set the label through this so an inactive bar keeps its (+).
    function b:Label(s)
      self.pendingText = s
      self.text:SetText(self.on and s or "")
    end
    function b:Paint(r, g, bl, on)
      self.mock[1], self.mock[2], self.mock[3] = r, g, bl
      self.on = on and true or false
      self:Refresh()
    end
    -- Plain name plus one line of help, so the bars can stay wordless.
    function b:Tip(title, note)
      self.tipTitle, self.tipNote = title, note
    end
    b:SetScript("OnEnter", function(self)
      -- Active or not, the frame lights up in the bright orange on hover.
      self:SetBackdropBorderColor(EDGE_HOT[1], EDGE_HOT[2], EDGE_HOT[3], 1)
      self.plus:SetTextColor(EDGE_HOT[1], EDGE_HOT[2], EDGE_HOT[3])
      if self.tipTitle then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.tipTitle, TXT[1], TXT[2], TXT[3])
        if self.tipNote then GameTooltip:AddLine(self.tipNote, DIM[1], DIM[2], DIM[3], true) end
        GameTooltip:Show()
      end
    end)
    b:SetScript("OnLeave", function(self)
      self:Refresh()
      GameTooltip:Hide()
    end)
    AddHover(b, PX_STEP)
    b:Refresh()
    RegisterElement(b)
    return b

  end


  -- Three identical bar slots. What each one shows - a resource bar or a combo
  -- point bar - is picked in its own settings, so nothing here is hardcoded.
  -- Every gap is a multiple of the pixel step so the whole stack stays sharp.
  -- The whole central block sits 10% of the canvas height lower; the
  -- reminder row is the only element that keeps its place at the top.
  local STACK_DROP = Snap(-34 - (PREVIEW_H * 0.10) / CANVAS_SCALE)
  local slotMocks, slotSegs = {}, {}
  for i = 1, C.MAX_BARS do
    local mock = MockBar(GRID_W, BAR_H, function() SelectBarSlot(i) end)
    if i == 1 then
      mock:SetPoint("CENTER", content, "CENTER", 0, STACK_DROP)
    else
      mock:SetPoint("BOTTOM", slotMocks[i - 1], "TOP", 0, PX_STEP)
    end
    mock:Tip("Bar slot " .. i, "A resource bar or a combo point bar - you choose in its settings.")
    -- Combo plates are drawn as real segments so the picked colour is visible.
    local segs = {}
    for n = 1, 20 do
      local t = mock:CreateTexture(nil, "ARTWORK")
      t:SetTexture("Interface\\Buttons\\WHITE8X8")
      t:Hide()
      segs[n] = t
    end
    slotMocks[i], slotSegs[i] = mock, segs
  end
  local power1Select = slotMocks[1]
  local castbarMock = MockBar(GRID_W, 16, function() ShowDetail(11) end)
  castbarMock:SetPoint("BOTTOM", slotMocks[C.MAX_BARS], "TOP", 0, PX_STEP)
  castbarMock:Label("CASTBAR")
  castbarMock:Tip("Castbar", "Your cast bar docked on top of the power and combo bars.")


  local mainGrid = GridModule(2, {
    mode = "spell", group = "cd", max = C.MAX_ICONS,
    slotSize = CD_SLOT_SIZE, slotPitch = CD_SLOT_PITCH,
    list = function() local set = CDSet(); set.main = set.main or {}; return set.main end,
    setCount = function(n) SetEnabledFromCount(CDSet(), "main", n) end,
  })
  PlaceGrid(mainGrid, "TOP", power1Select, "BOTTOM", 0, -PX_STEP)
  local subGrid = GridModule(2, {
    mode = "spell", group = "cd", max = C.MAX_ICONS,
    slotSize = CD_SLOT_SIZE, slotPitch = CD_SLOT_PITCH,
    list = function() local set = CDSet(); set.sub = set.sub or {}; return set.sub end,
    setCount = function(n) SetEnabledFromCount(CDSet(), "sub", n) end,
  })
  -- Secondary row hangs centred straight under the main row.
  PlaceGrid(subGrid, "TOP", mainGrid, "BOTTOM", 0, -PX_STEP)

  -- Aura rows: three stacked rows centred above the power / combo block.
  -- Row 1 is the lowest row, row 3 the top one.
  local auraAnchor = castbarMock
  local auraGap = PX_STEP * 4

  for i = 1, 3 do
    local rowIndex = i
    local grid = GridModule(3, {
      mode = "aura", group = "aura", max = C.MAX_ROW_ICONS,
      list = function() local row = C:Profile().rows[rowIndex]; row.icons = row.icons or {}; return row.icons end,
      setCount = function(n) local row = C:Profile().rows[rowIndex]; row.enabled = n > 0; row.count = n end,
    })
    PlaceGrid(grid, "BOTTOM", auraAnchor, "TOP", 0, auraGap)
    auraAnchor = grid
    auraGap = PX_STEP
  end

  -- Reminder row sits centred at the very top of the canvas. It is anchored to
  -- the canvas frame itself, not to the scaled content block, so the 15% drop
  -- of everything else leaves it exactly where it is.
  local reminderGrid = GridModule(7, {
    mode = "aura", group = "aura", max = C.MAX_ROW_ICONS, remindRow = true,
    list = function() local row = C:Profile().rows[4]; row.icons = row.icons or {}; return row.icons end,
    setCount = function(n) local row = C:Profile().rows[4]; row.enabled = n > 0; row.count = n end,
  })
  PlaceGrid(reminderGrid, "TOP", preview, "TOP", 0, -65)

  -- A thin rule keeps the reminder row visually apart from the rest.
  local reminderDivider = content:CreateTexture(nil, "ARTWORK")
  reminderDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
  reminderDivider:SetVertexColor(0.35, 0.30, 0.15, 0.8)
  reminderDivider:SetHeight(PX_STEP)
  reminderDivider:SetPoint("TOPLEFT", reminderGrid, "BOTTOMLEFT", -40, -PX_STEP * 2)
  reminderDivider:SetPoint("TOPRIGHT", reminderGrid, "BOTTOMRIGHT", 40, -PX_STEP * 2)

  -- Names the row so it is clear what the top block of the canvas is for.
  local reminderTitle = Label(content, 10, "CENTER")
  reminderTitle:SetPoint("TOP", reminderDivider, "BOTTOM", 0, -PX_STEP * 2)
  reminderTitle:SetText("BUFF REMINDER")
  reminderTitle:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])



  -- Player and target frames sit on either side of the central block. They are
  -- pure reference mockups: nothing to click, no settings behind them.
  -- The mockups are exactly as tall as one main bar icon row, so they line up
  -- with the main cooldown bar instead of sticking out above and below it.
  -- Three physical pixels shorter than before, independent of UI scale.
  -- One more physical pixel is taken off the bottom edge: the height shrinks by
  -- a pixel and the anchor moves up by half of it, so the top edge stays put.
  local UF_W, UF_H = SnapSize(220), SnapSize(36 - PX_STEP) - PX_STEP
  local UF_Y = PX_STEP + PX_STEP * 0.5
  local playerFrame = MakeButton(content, "PLAYER", UF_W, UF_H, nil)
  playerFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = PX_STEP })
  playerFrame:SetBackdropColor(MOCK_OFF[1], MOCK_OFF[2], MOCK_OFF[3], 1)
  playerFrame:SetBackdropBorderColor(EDGE_DARK[1], EDGE_DARK[2], EDGE_DARK[3], 1)
  playerFrame.Refresh = function() end
  playerFrame:EnableMouse(false)
  playerFrame:SetScript("OnEnter", nil)
  playerFrame:SetScript("OnLeave", nil)
  -- Sits at the height of the main cooldown row, on its left. The main row and
  -- the power bars always share the same width, so anchoring here keeps the
  -- frame horizontally where it was and only drops it down to the bar line.
  playerFrame:SetPoint("RIGHT", mainGrid, "LEFT", -PX_STEP * 10, UF_Y)
  playerFrame.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
  local targetFrame = MakeButton(content, "TARGET", UF_W, UF_H, nil)
  targetFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = PX_STEP })
  targetFrame:SetBackdropColor(MOCK_OFF[1], MOCK_OFF[2], MOCK_OFF[3], 1)
  targetFrame:SetBackdropBorderColor(EDGE_DARK[1], EDGE_DARK[2], EDGE_DARK[3], 1)
  targetFrame.Refresh = function() end
  targetFrame:EnableMouse(false)
  targetFrame:SetScript("OnEnter", nil)
  targetFrame:SetScript("OnLeave", nil)
  -- The reference mockups are not clickable, but they fade with everything
  -- else while a single element is being edited.
  RegisterElement(playerFrame)
  RegisterElement(targetFrame)
  targetFrame:SetPoint("LEFT", mainGrid, "RIGHT", PX_STEP * 10, UF_Y)
  targetFrame.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

  -- The two extra cooldown bars are glued to the player frame corners.
  local upGrid = GridModule(6, {
    mode = "spell", group = "cd", max = C.MAX_ICONS,
    -- The row grows to the left, so its slots are laid out right to left and
    -- the empty (+) slot ends up on the left edge, in the growth direction.
    reverse = true,
    list = function() local set = CDSet(); set.up = set.up or {}; return set.up end,
    setCount = function(n) SetEnabledFromCount(CDSet(), "up", n) end,
  })

  -- Upper player bar hangs on the top right corner of the player mockup and
  -- grows to the left, exactly like the real bar in game. Both bars keep a
  -- single pixel of air to the mockup.
  PlaceGrid(upGrid, "BOTTOMRIGHT", playerFrame, "TOPRIGHT", 0, PX_STEP)
  -- Trimmed to the visible slots as well, otherwise the empty tail of the row
  -- would push the icons away from the player frame corner.
  centeredGrids[#centeredGrids + 1] = upGrid
  local downGrid = GridModule(6, {
    mode = "spell", group = "cd", max = C.MAX_ICONS,
    list = function() local set = CDSet(); set.down = set.down or {}; return set.down end,
    setCount = function(n) SetEnabledFromCount(CDSet(), "down", n) end,
  })
  PlaceGrid(downGrid, "TOPLEFT", playerFrame, "BOTTOMLEFT", 0, -PX_STEP)

  -- Trim every centred row to the slots it actually shows so it stays centred
  -- on the power bars. Runs last, after the grids have refreshed themselves.
  -- Every width goes through the pixel lock: a fractional width is what pushed
  -- a row half a pixel off centre and made thin elements drop out.
  -- Shared width of the whole central stack, in canvas units. The combo layout
  -- reads this instead of GetWidth() so both always agree on the same integer.
  local stackWidth = GRID_W
  AddCanvasRefresh(function()
    for _, frame in ipairs(centeredGrids) do
      local n = 0
      for _, slot in ipairs(frame.slots or {}) do
        if slot:IsShown() then n = n + 1 end
      end
      local pitch = frame.jcdSlotPitch or Snap(36)
      local size = frame.jcdSlotSize or Snap(34)
      frame:SetWidth(SnapSize(math.max(size, (math.max(1, n) - 1) * pitch + size)))
    end
    -- Power bars, combo points and the castbar are exactly as wide as the main
    -- cooldown row, down to the pixel.
    local w = SnapSize(mainGrid:GetWidth() or GRID_W)
    stackWidth = w
    for _, mock in ipairs(slotMocks) do mock:SetWidth(w) end
    castbarMock:SetWidth(w)

  end)

  -- The mockups mirror the real settings: resource colours and text, the combo
  -- plate colour and count, and the castbar switch.
  -- Height is deliberately NOT mirrored: every mockup bar keeps the fixed
  -- canvas height BAR_H. A height above the default would otherwise blow the
  -- bar up inside the canvas and push the rest of the layout out of the frame.
  AddCanvasRefresh(function()
    local prof = C:Profile()
    local bars = BarList()
    for i = 1, C.MAX_BARS do
      local cfg = bars[i]
      local mock, segs = slotMocks[i], slotSegs[i]
      local on = cfg.enabled and true or false
      mock:SetHeight(BAR_H)
      if cfg.kind == "combo" then
        local col = C:BarColor(cfg)
        mock:Paint(0.10, 0.10, 0.10, on)
        mock:Label("")
        local n = math.max(1, math.min(20, tonumber(cfg.count) or 5))
        -- The segments live INSIDE the bar's own 1 pixel border, so the usable
        -- room is the bar width minus both edges. Widths are whole pixel steps
        -- and the leftover steps are handed out one per segment from the left,
        -- so the row always ends exactly on the inner right edge: no drifting
        -- offset, no lost border and nothing that spills outside the bar.
        local border = PX_STEP
        local gap = PX_STEP
        local inner = math.max(PX_STEP, stackWidth - 2 * border)
        if inner - (n - 1) * gap < n * PX_STEP then gap = 0 end
        local drawn = math.min(n, math.floor((inner + gap) / (PX_STEP + gap)))
        if drawn < 1 then drawn = 1 end
        local avail = inner - (drawn - 1) * gap
        local steps = math.floor(avail / PX_STEP)
        local base, extra = math.floor(steps / drawn), steps % drawn
        if base < 1 then base, extra = 1, 0 end
        local segH = math.max(PX_STEP, BAR_H - 2 * border)
        local x = border
        for n2, t in ipairs(segs) do
          if on and n2 <= drawn then
            local segW = (base + (n2 <= extra and 1 or 0)) * PX_STEP
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", mock, "TOPLEFT", x, -border)
            t:SetWidth(segW)
            t:SetHeight(segH)
            x = x + segW + gap
            t:SetVertexColor(col[1], col[2], col[3], 1)
            t:Show()
          else
            t:Hide()
          end
        end
      else
        for _, t in ipairs(segs) do t:Hide() end
        if cfg.resource == "OTHER" then
          local col = C:BarColor(cfg)
          mock:Paint(col[1], col[2], col[3], on)
          mock:Label(on and "CUSTOM" or "")
        else
          local info = C:PowerInfo(cfg.resource)
          local col = info.color
          mock:Paint(col[1], col[2], col[3], on)
          if not on then
            mock:Label("")
          elseif info.key == "MANA" and cfg.showPercent then
            mock:Label("100%")
          else
            mock:Label(info.name)
          end
        end
      end
    end

    local castOn = prof.castbarTop and true or false
    castbarMock:SetHeight(BAR_H)
    castbarMock:Paint(0.35, 0.30, 0.15, castOn)
    castbarMock:Label("CASTBAR")

  end)




  -- Every page closes with its own OK button.
  local function PageOK(parent)
    local b = MakeButton(parent, "OK", 90, 24, function()
      CloseLists(nil)
      C:RefreshConfig()
      C:Rebuild()
      HidePanel()
    end)
    b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 12)
    -- The OK button follows the page bottom, so it must not count when the
    -- page is measured for the scroll range.
    b.skipExtent = true
    return b
  end

  -- Page 1: general -----------------------------------------------------------
  local ge = pages[1]
  local y = -14
  Hint(ge, "The everyday switches live here. Cooldown bars, aura rows, reminders, power bars and profiles are grouped in the sidebar.", y)
  y = y - 40

  Header(ge, "Module", y); y = y - 26
  Hint(ge, "Unload switches the whole cooldown manager off: its bars disappear and it stops loading at login. Load turns it back on. Both need a UI reload.", y)
  y = y - 34
  local unloadBtn = MakeButton(ge, "Unload cooldown manager", 200, 22, function()
    if not JunkieUI then return end
    JunkieUI.db.cdEnabled = false
    if JunkieUI.RefreshCDPage then JunkieUI.RefreshCDPage() end
    print("|cffde7230JunkieCD|r unloading - reloading the interface.")
    ReloadUI()
  end)
  unloadBtn:SetPoint("TOPLEFT", ge, "TOPLEFT", 16, y)
  local loadBtn = MakeButton(ge, "Load cooldown manager", 200, 22, function()
    if not JunkieUI then return end
    JunkieUI.db.cdEnabled = true
    if EnableAddOn then EnableAddOn("JunkieCD") end
    print("|cffde7230JunkieCD|r loading - reloading the interface.")
    ReloadUI()
  end)
  loadBtn:SetPoint("LEFT", unloadBtn, "RIGHT", 8, 0)
  table.insert(refreshers, function()
    local on = (JunkieUI and JunkieUI.db and JunkieUI.db.cdEnabled) and true or false
    if on then unloadBtn:Show(); loadBtn:Hide() else unloadBtn:Hide(); loadBtn:Show() end
  end)
  y = y - 40

  Header(ge, "Text", y); y = y - 30
  MakeCheck(ge, "Show the timer number on icons", y,
    function() return C.db.cooldownText end,
    function(v) C.db.cooldownText = v; C:Rebuild() end)
  y = y - 40

  -- The castbar switch lives on the castbar element in the canvas now.


  PageOK(ge)

  -- Page 9: global canvas settings ---------------------------------------------
  -- Shown whenever the empty canvas background is clicked. It carries the
  -- settings that belong to the whole canvas, never to a single element.
  local gl = pages[9]
  y = -14
  Header(gl, "GLOBAL CANVAS SETTINGS", y)
  y = y - 30

  Header(gl, "Stance / shapeshift canvases", y); y = y - 26
  MakeCheck(gl, "Use a different icon set per stance / form", y,
    function() return C:Profile().stanceEnabled end,
    function(v) C:Profile().stanceEnabled = v; C:Rebuild(); C:RefreshConfig() end)
  y = y - 30
  local cdCanvas = MakeDropdown(gl, "Icon set you are editing", y, CanvasOptions,
    function() return C.editForm or -1 end,
    function(key)
      C.editForm = (key >= 0) and key or nil
      C:RefreshConfig()
    end, 240)
  y = y - 46

  local copyBtn = MakeButton(gl, "Copy Canvas", 90, 22, function()
    C:CopySet(CDSet())
    print("|cffde7230JunkieCD|r: Canvas copied to clipboard.")
    C:RefreshConfig()
  end)
  copyBtn:SetPoint("TOPLEFT", cdCanvas, "TOPLEFT", 250, 0)

  local pasteBtn = MakeButton(gl, "Paste Canvas", 90, 22, function()
    if not C.clipboard then
      print("|cffde7230JunkieCD|r: Clipboard is empty.")
      return
    end
    C:PasteSet(CDSet())
    print("|cffde7230JunkieCD|r: Canvas pasted from clipboard.")
    C:RefreshConfig()
    C:Rebuild()
  end)
  pasteBtn:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)

  local importBaseBtn = MakeButton(gl, "Import from Base", 110, 22, function()
    local p = C:Profile()
    C:CopySet(p)
    C:PasteSet(CDSet())
    print("|cffde7230JunkieCD|r: Canvas imported from Base.")
    C:RefreshConfig()
    C:Rebuild()
  end)
  importBaseBtn:SetPoint("LEFT", pasteBtn, "RIGHT", 4, 0)

  table.insert(refreshers, function()
    local on = C:Profile().stanceEnabled and true or false
    copyBtn:SetShown(on)
    pasteBtn:SetShown(on and C.clipboard and true or false)
    importBaseBtn:SetShown(on and C.editForm and true or false)
  end)
  local cdCanvasHint = Hint(gl, "", y)
  table.insert(refreshers, function()
    local on = C:Profile().stanceEnabled and true or false
    cdCanvas:SetShown(on)
    if not on and C.editForm then C.editForm = nil end
    cdCanvasHint:SetText(on
      and "Each form owns a small canvas of its own: only these cooldown icons, nothing else from the profile."
      or "Turn the switch on to give every form its own cooldown canvas.")
  end)
  y = y - 30

  Header(gl, "Icon sizes", y); y = y - 26
  MakeSlider(gl, "Main and secondary bar size", 20, 60, y,
    function() return C:Profile().iconSize or 40 end,
    function(v) C:Profile().iconSize = v; C:Rebuild() end)
  y = y - 56
  MakeSlider(gl, "Aura size", 20, 60, y,
    function() return C:Profile().auraSize or 35 end,
    function(v) C:Profile().auraSize = v; C:Rebuild() end)
  y = y - 56
  MakeSlider(gl, "Unitframe bar size", 20, 60, y,
    function() return C:Profile().unitIconSize or 35 end,
    function(v) C:Profile().unitIconSize = v; C:Rebuild() end)
  y = y - 56
  MakeSlider(gl, "Reminder size", 20, 60, y,
    function() return C:Profile().remindSize or C:Profile().auraSize or 35 end,
    function(v) C:Profile().remindSize = v; C:Rebuild() end)
  y = y - 60

  Header(gl, "Frame distance", y); y = y - 26
  MakeSlider(gl, "Vertical offset", -400, 400, y, function() return C:Profile().y end,
    function(v) C:Profile().y = v; C:Rebuild() end)
  y = y - 56
  MakeSlider(gl, "Reminder row distance from the top", 0, 500, y,
    function() return C:Profile().missingY or 120 end,
    function(v) C:Profile().missingY = v; C:Rebuild() end)
  PageOK(gl)

  -- Page 11: the castbar element ----------------------------------------------
  -- Opened by clicking the castbar mockup in the canvas.
  local cb = pages[11]
  y = -14
  Hint(cb, "The player castbar can sit right on top of this package, at the same width as the main bar.", y)
  y = y - 44
  Header(cb, "Player castbar", y); y = y - 26
  MakeCheck(cb, "Use the player castbar on top", y,
    function() return C:Profile().castbarTop end,
    function(v) C:Profile().castbarTop = v; C:Rebuild(); C:RefreshConfig() end)
  y = y - 34
  -- The castbar height is fixed at 35 so it always matches the package.
  PageOK(cb)

  -- Page 2: cooldown bars ------------------------------------------------------
  -- Detail view only: the icons themselves are built in the canvas above.
  local cd = pages[2]
  y = -14
  Hint(cd, "The cooldown grids live in the canvas above. Adding the first icon activates a bar; removing its last icon puts it to sleep.", y)
  y = y - 56

  Header(cd, "Main bar", y)
  y = y - 26
  local copyMain = MakeButton(cd, "Copy canvas", 104, 22, function() CopyCanvasRow("main") end)
  copyMain:SetPoint("TOPLEFT", cd, "TOPLEFT", 16, y)
  local importMain = MakeButton(cd, "Import canvas", 104, 22, function() ImportCanvasRow("main") end)
  importMain:SetPoint("LEFT", copyMain, "RIGHT", 6, 0)
  y = y - 40

  Header(cd, "Secondary bar", y)
  y = y - 26
  local copySub = MakeButton(cd, "Copy canvas", 104, 22, function() CopyCanvasRow("sub") end)
  copySub:SetPoint("TOPLEFT", cd, "TOPLEFT", 16, y)
  local importSub = MakeButton(cd, "Import canvas", 104, 22, function() ImportCanvasRow("sub") end)
  importSub:SetPoint("LEFT", copySub, "RIGHT", 6, 0)
  y = y - 44

  MakeCheck(cd, "Show the global cooldown (1.5s) on the icons", y,
    function() return C:Profile().showGCD end,
    function(v) C:Profile().showGCD = v; C:UpdateCooldowns() end)
  PageOK(cd)

  -- Page 6: unitframe bars ------------------------------------------------------
  local uf = pages[6]
  y = -14
  Hint(uf, "Two extra cooldown bars glued to the JunkieUI player unit frame. The upper bar hangs on the top right corner and grows to the left, the lower bar hangs on the bottom left corner and grows to the right. Their icons are built in the canvas above.", y)
  y = y - 60

  PageOK(uf)

  -- Page 3: auras -------------------------------------------------------------
  local au = pages[3]
  y = -14
  Hint(au, "Every row reads exact aura IDs and only shows an icon while that aura is active. The icons are built in the canvas above: click an empty [+] slot to add one, or a filled icon to edit it.", y)
  PageOK(au)

  -- Page 7: reminders & alerts -------------------------------------------------
  local mb = pages[7]
  y = -14
  Hint(mb, "One row pinned to the top of the screen. Each icon only shows while its buff is missing, and its own settings say whether it may nag always, in a party or only in a raid. Its icons are built in the canvas above.", y)
  y = y - 60
  Header(mb, "Reminder row", y); y = y - 26
  y = y - 16

  MakeSlider(mb, "Distance from the top of the screen", 0, 500, y,
    function() return C:Profile().missingY or 120 end,
    function(v) C:Profile().missingY = v; C:Rebuild() end, 5, 220)
  PageOK(mb)

  -- Page 4: power -------------------------------------------------------------
  local po = pages[4]
  y = -14
  Header(po, "Stance / shapeshift power sets", y); y = y - 26
  MakeCheck(po, "Use different power bars per stance / form", y,
    function() return C:Profile().powerStanceEnabled end,
    function(v) C:Profile().powerStanceEnabled = v; C:Rebuild(); C:RefreshConfig() end)
  y = y - 30
  local powerCanvas = MakeDropdown(po, "Power bar set you are editing", y, CanvasOptions,
    function() return C.editPowerForm or -1 end,
    function(key)
      C.editPowerForm = (key >= 0) and key or nil
      C:RefreshConfig()
    end, 240)
  y = y - 48
  table.insert(refreshers, function()
    local on = C:Profile().powerStanceEnabled and true or false
    powerCanvas:SetShown(on)
    if not on and C.editPowerForm then C.editPowerForm = nil end
  end)

  -- Everything below reflows: a block only takes room once it is switched on.
  local powerTop = y

  local function MovableHeader(parent, text)
    local o = CreateFrame("Frame", nil, parent)
    o:SetSize(10, 16)
    local fs = Label(parent, 11, "LEFT")
    fs:SetText(string.upper(text))
    fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.35, 0.3, 0.15, 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    function o:SetY(ny)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, ny)
    end
    function o:SetShown(show)
      if show then fs:Show(); line:Show() else fs:Hide(); line:Hide() end
    end
    function o:SetText(value) fs:SetText(string.upper(value)) end
    o.blockHeight = 28
    return o
  end

  -- One settings page for all three bar slots. Which slot it edits is whatever
  -- was clicked in the canvas, so the page never duplicates itself per bar.
  local barHeader = MovableHeader(po, "Bar slot settings")

  local barEnable = MakeCheck(po, "Enable this bar", y,
    function() return BarCfg().enabled and true or false end,
    function(v) BarCfg().enabled = v and true or false; C:Rebuild(); C:RefreshConfig() end)

  local KIND_OPTIONS = {
    { key = "resource", name = "Resource bar" },
    { key = "combo",    name = "Combo point bar" },
  }
  local kindDrop = MakeDropdown(po, "Bar type", y, KIND_OPTIONS,
    function() return BarCfg().kind or "resource" end,
    function(key) BarCfg().kind = key; C:Rebuild(); C:RefreshConfig() end, 240)

  local heightSlider = MakeSlider(po, "Height", 15, 50, y,
    function() return C:BarHeight(BarCfg()) end,
    function(v) BarCfg().height = math.max(15, math.min(50, v)); C:Rebuild() end, 1, 240)

  -- Resource mode --------------------------------------------------------------
  local resourceOptions = {}
  for _, p in ipairs(C.POWER_TYPES) do table.insert(resourceOptions, { key = p.key, name = p.name }) end
  table.insert(resourceOptions, { key = "OTHER", name = "Other resources (aura stacks)" })
  local resourceDrop = MakeDropdown(po, "Resource", y, resourceOptions,
    function() return BarCfg().resource or "MANA" end,
    function(key) BarCfg().resource = key; C:Rebuild(); C:RefreshConfig() end, 240)

  local otherField = MakeField(po, "Aura ID to read stacks from", y, 16, 120,
    function() return BarCfg().auraID end,
    function(v) BarCfg().auraID = (v and v > 0) and v or nil; C:Rebuild() end)
  local otherTypeDrop = MakeDropdown(po, "Aura type", y,
    { { key = "HELPFUL", name = "Buff" }, { key = "HARMFUL", name = "Debuff" } },
    function() return BarCfg().auraType or "HELPFUL" end,
    function(key) BarCfg().auraType = key; C:Rebuild() end, 240)
  local otherMaxField = MakeField(po, "Stacks that read as a full bar", y, 16, 120,
    function() return BarCfg().maxStacks or 100 end,
    function(v) BarCfg().maxStacks = (v and v > 0) and v or 100; C:Rebuild() end)

  local manaPct = MakeCheck(po, "Show mana in percent instead of numbers", y,
    function() return BarCfg().showPercent end,
    function(v) BarCfg().showPercent = v; C:Rebuild() end)
  local smooth = MakeCheck(po, "Smooth bar movement (slightly heavier)", y,
    function() return BarCfg().smooth end,
    function(v) BarCfg().smooth = v; C:UpdatePower() end)
  local standalone = MakeCheck(po, "Free this bar from the icon row (own width)", y,
    function() return BarCfg().standalone end,
    function(v) BarCfg().standalone = v; C:Rebuild() end)
  local widthSlider = MakeSlider(po, "Bar width", 60, 600, y,
    function() return BarCfg().width or 250 end,
    function(v) BarCfg().width = v; C:Rebuild() end, 16, 240)

  -- Combo mode -----------------------------------------------------------------
  local comboSlider = MakeSlider(po, "Points", 1, 20, y,
    function() return BarCfg().count or 5 end,
    function(v) BarCfg().count = v; C:Rebuild() end, 1, 240)
  local comboIDCheck = MakeCheck(po, "Count stacks of an aura instead of combo points", y,
    function() return BarCfg().useAura end,
    function(v)
      local cp = BarCfg()
      cp.useAura = v
      if not v then cp.spellID = nil end
      C:Rebuild(); C:RefreshConfig()
    end)
  local comboField = MakeField(po, "Aura ID to count stacks from", y, 16, 120,
    function() return BarCfg().spellID end,
    function(v) BarCfg().spellID = (v and v > 0) and v or nil; C:Rebuild() end)
  local comboTargetCheck = MakeCheck(po, "Read the aura on the target instead of on you", y,
    function() return BarCfg().onTarget end,
    function(v) BarCfg().onTarget = v and true or false; C:Rebuild() end)
  local comboChargeCheck = MakeCheck(po, "Count charges of a spell instead of combo points", y,
    function() return BarCfg().useCharges end,
    function(v)
      local cp = BarCfg()
      cp.useCharges = v
      if not v then cp.chargeSpellID = nil end
      C:Rebuild(); C:RefreshConfig()
    end)
  local comboChargeField = MakeField(po, "Spell ID to count charges from", y, 16, 120,
    function() return BarCfg().chargeSpellID end,
    function(v) BarCfg().chargeSpellID = (v and v > 0) and v or nil; C:Rebuild() end)

  -- Either the class colour or a palette colour drives the bar.
  local classColorCheck = MakeCheck(po, "Class colour", y,
    function() return BarCfg().classColor end,
    function(v) BarCfg().classColor = v and true or false; C:Rebuild(); C:RefreshConfig() end)

  -- Filled colour: one swatch is shown, the rest unfold on click.
  local COLORS = {
    { 0.871, 0.447, 0.188 }, { 1.00, 0.82, 0.00 }, { 1.00, 0.96, 0.41 }, { 0.95, 0.85, 0.30 },
    { 1.00, 0.49, 0.04 }, { 1.00, 0.24, 0.17 }, { 0.78, 0.20, 0.20 }, { 0.64, 0.19, 0.79 },
    { 0.85, 0.44, 0.84 }, { 0.96, 0.55, 0.73 }, { 1.00, 0.71, 0.79 }, { 0.58, 0.51, 0.79 },
    { 0.41, 0.80, 0.94 }, { 0.35, 0.75, 0.90 }, { 0.20, 0.45, 0.95 }, { 0.13, 0.31, 0.75 },
    { 0.00, 0.68, 0.68 }, { 0.10, 0.80, 0.60 }, { 0.20, 0.86, 0.31 }, { 0.13, 0.62, 0.20 },
    { 0.67, 0.83, 0.45 }, { 0.79, 0.85, 0.55 }, { 0.78, 0.61, 0.43 }, { 0.60, 0.42, 0.24 },
    { 0.42, 0.26, 0.13 }, { 1.00, 1.00, 1.00 }, { 0.78, 0.78, 0.78 }, { 0.50, 0.50, 0.50 },
    { 0.28, 0.28, 0.28 }, { 0.08, 0.08, 0.08 },
  }

  local paletteOpen = false
  local colorBlock = CreateFrame("Frame", nil, po)
  colorBlock:SetSize((po:GetWidth() or 620) - 28, 30)
  colorBlock:SetPoint("TOPLEFT", po, "TOPLEFT", 16, -400)

  local swatchLabel = Label(colorBlock, 11, "LEFT")
  swatchLabel:SetPoint("TOPLEFT", colorBlock, "TOPLEFT", 0, 0)
  swatchLabel:SetText("Filled colour")

  local current = CreateFrame("Button", nil, colorBlock)
  current:SetSize(22, 22)
  current:SetPoint("TOPLEFT", colorBlock, "TOPLEFT", 100, 2)
  Flat(current, 1, 1, 1, 1)
  local currentHint = Label(colorBlock, 10, "LEFT")
  currentHint:SetPoint("LEFT", current, "RIGHT", 8, 0)
  currentHint:SetTextColor(DIM[1], DIM[2], DIM[3])

  local swatches = {}
  for i, col in ipairs(COLORS) do
    local sw = CreateFrame("Button", nil, colorBlock)
    sw:SetSize(18, 18)
    local cIdx = (i - 1) % 15
    local rIdx = math.floor((i - 1) / 15)
    sw:SetPoint("TOPLEFT", colorBlock, "TOPLEFT", cIdx * 21, -30 - rIdx * 21)
    Flat(sw, col[1], col[2], col[3], 1)
    sw:Hide()
    sw:SetScript("OnClick", function()
      local cfg = BarCfg()
      cfg.color = { col[1], col[2], col[3] }
      cfg.classColor = false
      paletteOpen = false
      C:Rebuild()
      C:RefreshConfig()
    end)
    swatches[i] = sw
  end

  current:SetScript("OnClick", function()
    paletteOpen = not paletteOpen
    C:RefreshConfig()
  end)

  function colorBlock:SetY(ny)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", po, "TOPLEFT", 16, ny)
  end

  -- Page 8 is no longer its own section: combo points are one of the two modes
  -- a bar slot can be set to.
  local cpPage = pages[8]
  Hint(cpPage, "Combo points now live in the bar slots. Click one of the three bars in the canvas and set it to \"Combo point bar\".", -14)

  table.insert(refreshers, function()
    local cfg = BarCfg()
    local on = cfg.enabled and true or false
    local isCombo = cfg.kind == "combo"
    local isResource = not isCombo
    local other = isResource and cfg.resource == "OTHER"
    colorBlock.blockHeight = paletteOpen and 110 or 34
    barHeader:SetText("Bar slot " .. (C.editBarSlot or 1) .. " settings")
    Reflow(powerTop, {
      { barHeader, true },
      { barEnable, true },
      { kindDrop, on },
      { heightSlider, on },
      { resourceDrop, on and isResource },
      { otherField, on and other },
      { otherTypeDrop, on and other },
      { otherMaxField, on and other },
      { manaPct, on and isResource and cfg.resource == "MANA" },
      { smooth, on and isResource },
      { standalone, on and isResource },
      { widthSlider, on and isResource and (cfg.standalone and true or false) },
      { comboSlider, on and isCombo },
      { comboIDCheck, on and isCombo },
      { comboField, on and isCombo and (cfg.useAura and true or false) },
      { comboTargetCheck, on and isCombo and (cfg.useAura and true or false) },
      { comboChargeCheck, on and isCombo },
      { comboChargeField, on and isCombo and (cfg.useCharges and true or false) },
      { classColorCheck, on and (isCombo or other) },
      { colorBlock, on and (isCombo or other) and not cfg.classColor },
    })

    local cur = C:BarColor(cfg) or ACCENT
    current:SetBackdropColor(cur[1], cur[2], cur[3], 1)
    currentHint:SetText(paletteOpen and "Pick a colour" or "Click the colour to pick another one")
    for i, sw in ipairs(swatches) do
      if paletteOpen and on and not cfg.classColor then sw:Show() else sw:Hide() end
      local col = COLORS[i]
      local sel = math.abs(col[1] - cur[1]) < 0.01 and math.abs(col[2] - cur[2]) < 0.01
        and math.abs(col[3] - cur[3]) < 0.01
      sw:SetBackdropBorderColor(sel and ACCENT[1] or 0.18, sel and ACCENT[2] or 0.17, sel and ACCENT[3] or 0.14, 1)
    end
  end)
  PageOK(po)
  PageOK(cpPage)


  -- Page 5: profiles & share --------------------------------------------------
  local pr = pages[5]
  y = -14
  Header(pr, "CD Manager profile", y); y = y - 28
  Hint(pr, "These profiles only cover the Junkie Cooldown Manager: its cooldown bars, aura rows, power bars and combo points. Nothing else in JunkieUI is profile based.", y)
  y = y - 42

  local function ProfileOptions()
    local out = {}
    for _, n in ipairs(C:ProfileNames()) do table.insert(out, { key = n, name = n }) end
    return out
  end

  MakeDropdown(pr, nil, y, ProfileOptions, function() return C.db.resolved end,
    function(key) C:UseProfile(key) end, 240)

  local nameBox = CreateFrame("Frame", nil, pr)
  nameBox:SetPoint("TOPLEFT", pr, "TOPLEFT", 272, y)
  nameBox:SetSize(180, 22)
  Flat(nameBox, BG[1], BG[2], BG[3], 1)
  local nameEdit = CreateFrame("EditBox", nil, nameBox)
  nameEdit:SetPoint("TOPLEFT", 5, -1)
  nameEdit:SetPoint("BOTTOMRIGHT", -5, 1)
  nameEdit:SetFont(C.font, 11)
  nameEdit:SetAutoFocus(false)
  nameEdit:SetMaxLetters(24)
  nameEdit:SetTextColor(TXT[1], TXT[2], TXT[3])
  nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local function CreateFromBox()
    if C:CreateProfile(nameEdit:GetText()) then
      nameEdit:SetText("")
      C:RefreshConfig()
      C:RequestReload("A profile was created")
    end
  end
  nameEdit:SetScript("OnEnterPressed", CreateFromBox)

  local newBtn = MakeButton(pr, "New", 70, 22, CreateFromBox)
  newBtn:SetPoint("TOPLEFT", pr, "TOPLEFT", 460, y)

  local delBtn = MakeButton(pr, "Delete", 70, 22, function()
    C:DeleteProfile(C.db.resolved)
    C:RefreshConfig()
    C:RequestReload("A profile was deleted")
  end)
  delBtn:SetPoint("TOPLEFT", pr, "TOPLEFT", 536, y)
  y = y - 40

  Header(pr, "Load if spell known", y); y = y - 26
  Hint(pr, "Bind this profile to a spell ID that only one build has. The profile loads automatically whenever that spell is known, so a character can swing freely between builds.", y)
  y = y - 40
  MakeCheck(pr, "Use this profile when you know a certain spell", y,
    function() local p = C:Profile(); return p.loadSpell and p.loadSpell.enabled end,
    function(v)
      local p = C:Profile()
      p.loadSpell = p.loadSpell or {}
      p.loadSpell.enabled = v
      if not v then p.loadSpell.id = nil end
      C.db.resolved = C:ResolveProfileName()
      C:Rebuild()
      C:RefreshConfig()
    end)
  y = y - 30

  local browseBtn = MakeButton(pr, "Browse spellbook", 130, 22, function()
    C:OpenPicker("spell", function(sel)
      if not sel or not sel.id then return end
      local p = C:Profile()
      p.loadSpell = p.loadSpell or {}
      p.loadSpell.id = sel.id
      C.db.resolved = C:ResolveProfileName()
      C:Rebuild()
      C:RefreshConfig()
    end)
  end)
  browseBtn:SetPoint("TOPLEFT", pr, "TOPLEFT", 190, y - 17)

  -- The picked spell is shown with its own icon, not just its name.
  local spellIcon = CreateFrame("Frame", nil, pr)
  spellIcon:SetSize(24, 24)
  spellIcon:SetPoint("TOPLEFT", browseBtn, "TOPRIGHT", 8, 1)
  C:Flat(spellIcon, 0, 0, 0, 1)
  spellIcon.tex = spellIcon:CreateTexture(nil, "ARTWORK")
  spellIcon.tex:SetPoint("TOPLEFT", 1, -1)
  spellIcon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  spellIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  spellIcon.label = Label(pr, 11, "LEFT")
  spellIcon.label:SetPoint("LEFT", spellIcon, "RIGHT", 6, 0)
  spellIcon:Hide()

  local spellHint = Label(pr, 10, "LEFT")
  spellHint:SetPoint("TOPLEFT", pr, "TOPLEFT", 16, y - 44)
  spellHint:SetWidth((pr:GetWidth() or 632) - 30)
  spellHint:SetJustifyV("TOP")
  spellHint:SetTextColor(DIM[1], DIM[2], DIM[3])
  spellHint:SetText("Enable \"SpellID and AuraID on tooltip\" and mouse over your buff or debuff to find its aura ID.")

  local spellField = MakeField(pr, "Spell ID you have to know", y, 16, 120,
    function() local p = C:Profile(); return p.loadSpell and p.loadSpell.id end,
    function(v)
      local p = C:Profile()
      p.loadSpell = p.loadSpell or {}
      p.loadSpell.id = (v and v > 0) and v or nil
      C.db.resolved = C:ResolveProfileName()
      C:Rebuild()
      C:RefreshConfig()
    end)
  y = y - 70
  local spellTag = Label(pr, 10, "LEFT")
  spellTag:SetPoint("TOPLEFT", pr, "TOPLEFT", 16, y)
  spellTag:SetWidth((pr:GetWidth() or 632) - 30)
  spellTag:SetJustifyV("TOP")
  spellTag:SetTextColor(DIM[1], DIM[2], DIM[3])

  -- Two profiles bound to the same spell can never both load: warn about it.
  local spellWarn = Label(pr, 10, "LEFT")
  spellWarn:SetPoint("TOPLEFT", pr, "TOPLEFT", 16, y - 16)
  spellWarn:SetWidth((pr:GetWidth() or 632) - 30)
  spellWarn:SetJustifyV("TOP")
  spellWarn:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
  table.insert(refreshers, function()
    local p = C:Profile()
    local ls = p.loadSpell or {}
    local on = ls.enabled and true or false
    spellField:SetShown(on)
    spellField:Sync()
    if on then browseBtn:Show(); spellHint:Show() else browseBtn:Hide(); spellHint:Hide() end
    local sName, _, sTex = nil, nil, nil
    if on and ls.id then sName, _, sTex = GetSpellInfo(ls.id) end
    if sTex then
      spellIcon.tex:SetTexture(sTex)
      spellIcon.label:SetText(sName or ("Spell " .. tostring(ls.id)))
      spellIcon:Show()
      spellIcon.label:Show()
    else
      spellIcon:Hide()
      spellIcon.label:Hide()
    end
    local bound = ""
    if on and ls.id then
      local name = GetSpellInfo(ls.id)
      bound = "  |  bound to " .. (name or ("spell " .. ls.id)) ..
        (C:SpellKnown(ls.id) and " (known)" or " (not known)")
    end
    local dupes = {}
    if on and ls.id then
      for _, other in ipairs(C:ProfileNames()) do
        local op = C.db.profiles[other]
        local ols = op and op.loadSpell
        if ols and ols.enabled and tonumber(ols.id) == tonumber(ls.id) then
          table.insert(dupes, other)
        end
      end
    end
    if #dupes > 1 then
      spellWarn:SetText("Warning: " .. table.concat(dupes, ", ") ..
        " all load from the same spell. Only the first one can ever load - give the others their own spell ID.")
      spellWarn:Show()
    else
      spellWarn:SetText("")
      spellWarn:Hide()
    end
    spellTag:SetText("Character: " .. C:CharacterName() .. "  |  uses " .. (C.db.resolved or "-") .. bound)
  end)
  y = y - 34


  Header(pr, "Export & import", y); y = y - 26
  Hint(pr, "Export copies the active profile into the box. Paste someone else's string and press Import.", y)
  y = y - 26

  local box = CreateFrame("Frame", nil, pr)
  box:SetPoint("TOPLEFT", pr, "TOPLEFT", 14, y)
  box:SetPoint("RIGHT", pr, "RIGHT", -14, 0)
  box:SetHeight(80)
  Flat(box, BG[1], BG[2], BG[3], 1)

  local scroll = CreateFrame("ScrollFrame", "JunkieCDShareScroll", box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -26, 6)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFont(C.font, 11)
  edit:SetWidth(560)
  edit:SetAutoFocus(false)
  edit:SetTextColor(TXT[1], TXT[2], TXT[3])
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)

  local exportBtn = MakeButton(pr, "Export", 110, 24, function()
    edit:SetText(C:ExportProfile())
    edit:HighlightText()
    edit:SetFocus()
  end)
  exportBtn:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)

  local importBtn = MakeButton(pr, "Import", 110, 24, function()
    local ok, res = C:ImportProfile(edit:GetText())
    if ok then
      print("|cffde7230JunkieCD|r imported profile: " .. res)
      C:RefreshConfig()
      C:RequestReload("A profile was imported")
    else
      print("|cffde7230JunkieCD|r import failed: " .. tostring(res))
    end
  end)
  importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
  PageOK(pr)

  Select(1)
  panel:HookScript("OnHide", function()
    CloseLists(nil)
    CloseIconSettings()
    C:SetPreview(false)
  end)
  panel:HookScript("OnShow", function()
    C:RefreshConfig()
    C:SetPreview(true)
  end)
  
end

function C:RefreshConfig()
  -- Event bursts can rebuild the display while settings are closed. Running
  -- every settings refresher off-screen is expensive and cannot change what
  -- the player sees, so defer hydration until the panel's next OnShow.
  if not panel or not panel:IsShown() then layoutChanged = false return end
  for _, fn in ipairs(refreshers) do pcall(fn) end
  layoutChanged = false
end


-- Everything routes through JunkieUI: it owns the window, we only fill a page.
function C:ToggleConfig()
  if JunkieUI and JunkieUI.OpenCooldownManager then
    JunkieUI:OpenCooldownManager()
    return
  end
  print("|cffde7230JunkieCD|r needs JunkieUI to show its settings.")
end

if JunkieUI and JunkieUI.RegisterCooldownManagerPanel then
  JunkieUI:RegisterCooldownManagerPanel(function(host) BuildPanel(host) end)
end
