-- /jui settings panel (flat AtlasLoot-inspired theme)
local J = JunkieUI

local panel

local BG      = { 0.055, 0.055, 0.055 }  -- #0e0e0e panel base
local BOX     = { 0.09, 0.09, 0.09 }     -- #171717 inner panels
local HL      = { 0.18, 0.11, 0.06 }     -- warm orange hover
local ACCENT  = { 0.871, 0.447, 0.188 }   -- #de7230 feather orange
local TXT     = { 0.86, 0.84, 0.78 }
local DIM     = { 0.55, 0.53, 0.48 }


local SCALES = { small = 0.5333, medium = 0.6333, large = 0.7333 }
local function ScaleKey()
  local v = (J.db and J.db.uiScale) or 0.6333
  if v < 0.58 then return "small" end
  if v < 0.68 then return "medium" end
  return "large"
end

local function Flat(frame, r, g, b, a)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(r, g, b, a or 1)
  frame:SetBackdropBorderColor(0.18, 0.17, 0.14, 1)
  return frame
end

local function Label(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(J.font, size or 11)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetShadowOffset(0, 0)
  fs:SetTextColor(TXT[1], TXT[2], TXT[3])
  return fs
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
  fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y)
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
  b:SetScript("OnEnter", function(self)
    if not self.selected then self:SetBackdropColor(HL[1], HL[2], HL[3], 1) end
  end)
  b:SetScript("OnLeave", function(self) self:Refresh() end)
  if onClick then b:SetScript("OnClick", onClick) end
  b:Refresh()
  return b
end

local function MakeCheck(parent, label, y, checked, onClick, x)
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(16, 16)
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y)
  Flat(c, BG[1], BG[2], BG[3], 1)

  local fill = c:CreateTexture(nil, "ARTWORK")
  fill:SetTexture("Interface\\Buttons\\WHITE8X8")
  fill:SetPoint("TOPLEFT", 4, -4)
  fill:SetPoint("BOTTOMRIGHT", -4, 4)
  fill:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)

  local t = Label(c, 11, "LEFT")
  t:SetPoint("LEFT", c, "RIGHT", 8, 0)
  t:SetText(label)

  c.checked = checked and true or false
  c.fill = fill
  local function refresh()
    if c.checked then fill:Show() else fill:Hide() end
  end
  c.Refresh = refresh
  refresh()


  c:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) end)
  c:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
  c:SetScript("OnClick", function(self)
    self.checked = not self.checked
    refresh()
    onClick(self.checked)
  end)
  return c
end

local function MakeDropdown(parent, label, y, options, current, onSelect)
  local title = Label(parent, 11, "LEFT")
  title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
  title:SetText(label)

  local function LabelFor(key)
    for _, o in ipairs(options) do if o.key == key then return o.name end end
    return options[1] and options[1].name or ""
  end

  local btn = MakeButton(parent, LabelFor(current), 200, 22)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y - 18)
  btn.text:ClearAllPoints()
  btn.text:SetPoint("LEFT", btn, "LEFT", 8, 0)
  btn.text:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
  btn.text:SetJustifyH("LEFT")

  -- +/- indicator drawn as flat bars, matching the checkbox styling
  local ind = CreateFrame("Frame", nil, btn)
  ind:SetSize(14, 14)
  ind:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
  Flat(ind, BG[1], BG[2], BG[3], 1)

  local hbar = ind:CreateTexture(nil, "OVERLAY")
  hbar:SetTexture("Interface\\Buttons\\WHITE8X8")
  hbar:SetSize(8, 2)
  hbar:SetPoint("CENTER")
  hbar:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)

  local vbar = ind:CreateTexture(nil, "OVERLAY")
  vbar:SetTexture("Interface\\Buttons\\WHITE8X8")
  vbar:SetSize(2, 8)
  vbar:SetPoint("CENTER")
  vbar:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)

  local sign = {}
  function sign:SetText(v)
    if v == "-" then vbar:Hide() else vbar:Show() end
  end

  -- Long lists (the shared media textures) scroll with the mouse wheel instead
  -- of running off the bottom of the panel.
  local MAX_ROWS = 12
  local rows = math.min(#options, MAX_ROWS)

  local list = CreateFrame("Frame", nil, parent)
  list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
  list:SetSize(200, rows * 20 + 4)
  list:SetFrameLevel(btn:GetFrameLevel() + 10)
  Flat(list, BG[1], BG[2], BG[3], 1)
  list:Hide()

  local offset = 0
  local items = {}
  for i = 1, rows do
    local item = MakeButton(list, "", 192, 18, function()
      local o = options[i + offset]
      if not o then return end
      btn.text:SetText(o.name)
      list:Hide()
      sign:SetText("+")
      onSelect(o.key)
    end)
    item:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -2 - (i - 1) * 20)
    items[i] = item
  end

  local function Fill()
    for i = 1, rows do
      local o = options[i + offset]
      items[i].text:SetText(o and o.name or "")
    end
  end
  Fill()

  if #options > rows then
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
      offset = offset - delta
      if offset < 0 then offset = 0 end
      if offset > #options - rows then offset = #options - rows end
      Fill()
    end)
  end

  btn:SetScript("OnClick", function()
    if list:IsShown() then
      list:Hide()
      sign:SetText("+")
    else
      list:Show()
      sign:SetText("-")
    end
  end)
  return btn
end

local function MakeSlider(parent, name, label, minV, maxV, value, y, onChange)
  local title = Label(parent, 11, "LEFT")
  title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
  title:SetText(label)

  local track = CreateFrame("Frame", nil, parent)
  track:SetSize(300, 10)
  track:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y - 18)
  Flat(track, BG[1], BG[2], BG[3], 1)

  local s = CreateFrame("Slider", name, parent)
  s:SetAllPoints(track)
  s:SetOrientation("HORIZONTAL")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(1)
  s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
  local thumb = s:GetThumbTexture()
  thumb:SetSize(8, 16)
  thumb:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)

  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(58, 20)
  box:SetPoint("LEFT", track, "RIGHT", 12, 0)
  Flat(box, BG[1], BG[2], BG[3], 1)

  local edit = CreateFrame("EditBox", nil, box)
  edit:SetPoint("TOPLEFT", box, 4, -1)
  edit:SetPoint("BOTTOMRIGHT", box, -4, 1)
  edit:SetFont(J.font, 11)
  edit:SetJustifyH("CENTER")
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(5)
  edit:SetTextInsets(0, 0, 0, 0)
  edit:SetTextColor(TXT[1], TXT[2], TXT[3])
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  s:SetValue(value)
  edit:SetText(tostring(value))

  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v + 0.5)
    if not edit:HasFocus() then edit:SetText(tostring(v)) end
    onChange(v)
  end)
  edit:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v then
      v = math.max(minV, math.min(maxV, math.floor(v)))
      s:SetValue(v)
      self:SetText(tostring(v))
    end
    self:ClearFocus()
  end)
  return s, edit
end

-- Panel geometry: matches the Junkie Cooldown Manager window.
local PANEL_W, PANEL_H = 1020, 740
local SIDE_W = 150
local PAGE_X = 14 + SIDE_W + 8
local PAGE_W = PANEL_W - PAGE_X - 14
local PAGE_H = PANEL_H - 48 - 46

-- Greying out: a locked slider stays readable but takes no input.
local function SetSliderEnabled(slider, edit, on)
  if not slider then return end
  slider:EnableMouse(on and true or false)
  slider:SetAlpha(on and 1 or 0.35)
  if edit then
    edit:EnableMouse(on and true or false)
    edit:SetAlpha(on and 1 or 0.35)
    if not on then edit:ClearFocus() end
  end
end

local function BuildPanel()
  panel = CreateFrame("Frame", "JunkieConfig", UIParent)
  panel:SetSize(PANEL_W, PANEL_H)
  -- The small interface scale shrinks everything: give the settings window
  -- 20% back so its text and widgets stay readable, plus one extra pixel on
  -- every side so nothing sits flush against the border.
  if ScaleKey() == "small" then
    panel:SetScale(1.2)
    panel:SetSize(PANEL_W + 2, PANEL_H + 2)
  end
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  Flat(panel, BG[1], BG[2], BG[3], 1)

  -- Title bar --------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, panel)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(38)
  bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  bar:SetBackdropColor(BOX[1], BOX[2], BOX[3], 1)

  local title = Label(bar, 14, "CENTER")
  title:SetPoint("CENTER", bar, "CENTER", 0, 1)
  title:SetText("JUNKIEUI")
  title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

  local sub = Label(bar, 10, "LEFT")
  sub:SetPoint("LEFT", bar, "LEFT", 12, 0)
  local verNum = (GetAddOnMetadata and GetAddOnMetadata("JunkieUI", "Version")) or J.version or ""
  sub:SetText("Featherlight  v" .. verNum)
  sub:SetTextColor(DIM[1], DIM[2], DIM[3])

  local close = MakeButton(bar, "X", 22, 22, function() panel:Hide() end)
  close:SetPoint("RIGHT", bar, "RIGHT", -8, 0)

  -- Sidebar ----------------------------------------------------------------
  local tabs, pages = {}, {}

  local side = CreateFrame("Frame", nil, panel)
  side:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -48)
  side:SetSize(SIDE_W, PAGE_H)
  Flat(side, BOX[1], BOX[2], BOX[3], 1)

  local function Select(index)
    for i, t in ipairs(tabs) do t.selected = (i == index); t:Refresh() end
    for i, p in ipairs(pages) do if i == index then p:Show() else p:Hide() end end
    -- Size placeholders are only shown while the aura page is open.
    local on = (index == 4)
    if J.SetPlayerAuraPreview then J:SetPlayerAuraPreview(on) end
    if index == 10 and J.RefreshCDPage then J.RefreshCDPage() end
  end
  panel.SelectPage = Select

  local sy = -10
  local function SideLabel(text)
    local fs = Label(side, 10, "LEFT")
    fs:SetPoint("TOPLEFT", side, "TOPLEFT", 8, sy)
    fs:SetText(string.upper(text))
    fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    sy = sy - 18
  end

  local function NewPage(i)
    local p = CreateFrame("Frame", nil, panel)
    p:SetPoint("TOPLEFT", panel, "TOPLEFT", PAGE_X, -48)
    p:SetSize(PAGE_W, PAGE_H)
    Flat(p, BOX[1], BOX[2], BOX[3], 1)
    pages[i] = p
    return p
  end

  local function SideEntry(i, name)
    local t = MakeButton(side, name, SIDE_W - 16, 22, function() Select(i) end)
    t:SetPoint("TOPLEFT", side, "TOPLEFT", 8, sy)
    t.text:ClearAllPoints()
    t.text:SetPoint("LEFT", t, "LEFT", 8, 0)
    t.text:SetJustifyH("LEFT")
    sy = sy - 24
    tabs[i] = t
    NewPage(i)
  end

  local names = {
    "General", "Unitframes", "Actionbars", "Buffs & debuffs",
    "Minimap", "Movers", "Tooltip", "QoL", "About",
  }
  SideLabel("General")
  for i, n in ipairs(names) do SideEntry(i, n) end
  sy = sy - 12
  SideLabel("Modules")
  SideEntry(10, "Cooldown manager")

  -- Page 1: General ---------------------------------------------------------
  local gen = pages[1]
  local y = -14
  Header(gen, "UI scaling", y); y = y - 22
  Hint(gen, "Pick the scale that matches your resolution. Changing it reloads the interface.", y)
  y = y - 26
  MakeDropdown(gen, "Interface scale", y, {
    { key = "small",  name = "Small (0.5333)" },
    { key = "medium", name = "Medium (0.6333)" },
    { key = "large",  name = "Large (0.7333)" },
  }, ScaleKey(), function(key)
    J.db.uiScale = SCALES[key] or 0.6333
    if J.ApplyScale then J:ApplyScale() end
    if J.RequireReload then J:RequireReload() end
    print("|cff4fc3f7JunkieUI:|r interface scale changed - reloading the interface.")
    ReloadUI()
  end)
  y = y - 64

  Header(gen, "Bar texture", y); y = y - 22
  Hint(gen, "Every Junkie bar - health, power, castbars and the cooldown manager - uses this texture.", y)
  y = y - 26

  if J.BuildTextureList then J:BuildTextureList() end
  local texOptions = {}
  for _, t in ipairs(J.textures or {}) do
    texOptions[#texOptions + 1] = { key = t.key, name = t.name }
  end
  if #texOptions == 0 then texOptions[1] = { key = "Flat", name = "Flat" } end

  local previewHolder = CreateFrame("Frame", nil, gen)
  previewHolder:SetSize(300, 18)
  previewHolder:SetPoint("TOPLEFT", gen, "TOPLEFT", 16, y - 48)
  Flat(previewHolder, BG[1], BG[2], BG[3], 1)

  local previewBar = CreateFrame("StatusBar", nil, previewHolder)
  previewBar:SetPoint("TOPLEFT", 1, -1)
  previewBar:SetPoint("BOTTOMRIGHT", -1, 1)
  previewBar:SetMinMaxValues(0, 1)
  previewBar:SetValue(1)
  previewBar:SetStatusBarTexture(J.statusbar)
  previewBar:SetStatusBarColor(ACCENT[1], ACCENT[2], ACCENT[3])

  MakeDropdown(gen, "Statusbar texture", y, texOptions, J.db.barTexture or "Flat", function(key)
    J.db.barTexture = key
    local path = J.ApplyBarTexture and J:ApplyBarTexture() or J.statusbar
    previewBar:SetStatusBarTexture(path)
    previewBar:SetStatusBarColor(ACCENT[1], ACCENT[2], ACCENT[3])
  end)
  y = y - 100

  Header(gen, "Font", y); y = y - 26
  MakeDropdown(gen, "Interface font", y, J.fonts, J.db.fontChoice or "expressway", function(key)
    J.db.fontChoice = key
    if J.ApplyFont then J:ApplyFont() end
    if J.RequireReload then J:RequireReload() end
  end)

  -- Page 2: Unitframes -----------------------------------------------------
  local u = pages[2]
  y = -14
  Header(u, "Player & target", y); y = y - 24

  local gapSlider, gapEdit = MakeSlider(u, "JunkieGapSlider", "Space between player and target frame", 1, 500, J.db.unitGap, y, function(v)
    J.db.unitGap = v
    J:UpdateUnitPositions()
  end)
  y = y - 44

  local cdGapSlider, cdGapEdit = MakeSlider(u, "JunkieCDGapSlider",
    "Gap between Junkie Cooldown manager and unitframes", 1, 200, J.db.cdGap or 1, y, function(v)
      J.db.cdGap = v
      J:UpdateUnitPositions()
    end)
  y = y - 44

  -- While the cooldown manager is locked between the frames it owns the gap.
  local function SyncGapState()
    local locked = J.CDLocked and J:CDLocked()
    SetSliderEnabled(gapSlider, gapEdit, not locked)
    SetSliderEnabled(cdGapSlider, cdGapEdit, locked)
  end
  J.SyncGapState = SyncGapState
  SyncGapState()

  MakeSlider(u, "JunkieYSlider", "Vertical offset", -500, 500, J.db.unitY, y, function(v)
    J.db.unitY = v
    J:UpdateUnitPositions()
    if JunkieCD and JunkieCD.Rebuild then JunkieCD:Rebuild() end
  end)
  y = y - 48


  MakeCheck(u, "Power bar on the player frame", y, J.db.playerPower, function(v)
    J.db.playerPower = v
    if J.UpdatePlayerPower then J:UpdatePlayerPower() end
  end)
  y = y - 24

  MakeCheck(u, "Power bar on the target frame", y, J.db.targetPower, function(v)
    J.db.targetPower = v
    if J.UpdateTargetPower then J:UpdateTargetPower() end
  end)
  y = y - 24

  MakeCheck(u, "Show timers on target buffs and debuffs", y, J.db.targetAuraText, function(v)
    J.db.targetAuraText = v
  end)
  y = y - 24

  MakeCheck(u, "Disable Ascension Resource bars", y, J.db.hideCoAResource, function(v)
    local old = J.db.hideCoAResource
    J.db.hideCoAResource = v
    if old ~= v then
      ReloadUI()
    end
  end)
  y = y - 40


  Header(u, "Castbars", y); y = y - 26
  -- Both castbars belong to the same element, so they share one row.
  MakeCheck(u, "Player castbar", y, J.db.playerCastbar ~= false, function(v)
    J.db.playerCastbar = v
    if J.UpdateCastbars then J:UpdateCastbars() end
  end)
  MakeCheck(u, "Target castbar", y, J.db.targetCastbar ~= false, function(v)
    J.db.targetCastbar = v
    if J.UpdateCastbars then J:UpdateCastbars() end
  end, 200)
  y = y - 24
  MakeCheck(u, "Also keep Blizzard's castbars", y, J.db.blizzardCastbars, function(v)
    J.db.blizzardCastbars = v
    if J.UpdateCastbars then J:UpdateCastbars() end
    if J.RequireReload then J:RequireReload() end
  end)
  y = y - 22
  Hint(u, "Turn all three off to free the castbars for another addon.", y)



  -- Page 3: Actionbars -----------------------------------------------------
  local a = pages[3]
  y = -14
  Header(a, "Actionbars", y); y = y - 26
  MakeCheck(a, "Show cooldown timers on action buttons", y, J.db.cooldownText, function(v)
    J.db.cooldownText = v
    J:ApplyCooldownText()
    if J.RequireReload then J:RequireReload() end
  end)
  y = y - 24
  MakeCheck(a, "Show macro names on action buttons", y, J.db.macroText, function(v)
    J.db.macroText = v
    if J.ApplyMacroText then J:ApplyMacroText() end
  end)
  y = y - 24
  MakeCheck(a, "Dark background behind the action bars", y, J.db.barBackground ~= false, function(v)
    J.db.barBackground = v
    if J.ApplyBarBackground then J:ApplyBarBackground() end
    -- The docked castbar hugs the background plate, so it needs a re-anchor.
    if J.AnchorPlayerCastbar then J:AnchorPlayerCastbar() end
  end)

  y = y - 24
  MakeCheck(a, "Trigger actions on key press (down) instead of release", y, J.db.keyPressDown, function(v)
    local old = J.db.keyPressDown
    J.db.keyPressDown = v
    -- Click registration is protected, so the switch is applied through a
    -- clean reload instead of poking secure buttons mid-session.
    if old ~= v then ReloadUI() end
  end)

  y = y - 24
  MakeCheck(a, "Show the stance / form bar", y, J.db.stanceBar, function(v)
    J.db.stanceBar = v
    if J.ApplyBarLayout then J.ApplyBarLayout() end
    if J.RequireReload then J:RequireReload() end
  end)
  y = y - 40


  Header(a, "Layout", y); y = y - 26
  MakeDropdown(a, "Bar arrangement", y, {
    { key = "one",    name = "One block" },
    { key = "three",  name = "Triple block" },
    { key = "triple", name = "One big stack" },
    { key = "tripleHigh", name = "One big stack (Floating)" },
    { key = "sebby", name = "Sebby Layout" },
  }, J.db.barLayout or "one", function(key)
    J.db.barLayout = key
    if J.ApplyBarLayout then J.ApplyBarLayout() end
  end)

  -- Page 4: Buffs & debuffs ------------------------------------------------
  local bd = pages[4]
  y = -14
  Header(bd, "Player auras (under the minimap)", y); y = y - 22
  Hint(bd, "Placeholders show the size while this page is open.", y); y = y - 22

  MakeSlider(bd, "JunkieBuffSizeSlider", "Buff icon size", 16, 60, J.db.buffSize or 30, y, function(v)
    J.db.buffSize = v
    if J.UpdatePlayerAuraSizes then J:UpdatePlayerAuraSizes() end
  end)
  y = y - 44

  MakeSlider(bd, "JunkieDebuffSizeSlider", "Debuff icon size", 16, 60, J.db.playerDebuffSize or 34, y, function(v)
    J.db.playerDebuffSize = v
    if J.UpdatePlayerAuraSizes then J:UpdatePlayerAuraSizes() end
  end)
  y = y - 50

  Header(bd, "Debuff placement", y); y = y - 26
  MakeCheck(bd, "Move your debuffs above the player frame", y, J.db.debuffsOnFrame, function(v)
    J.db.debuffsOnFrame = v
    if J.UpdateDebuffPlacement then J:UpdateDebuffPlacement() end
  end)
  y = y - 40

  -- Blacklist ----------------------------------------------------------------
  -- Stored as a hash map (JunkieUIDB.debuffBlacklist[spellID] = true) so the
  -- aura refresh can test membership in O(1). This panel only ever touches the
  -- table on a click / Enter press; nothing here runs per frame.
  Header(bd, "Blacklist debuffs", y); y = y - 24
  Hint(bd, "Type an aura ID and press Enter to hide that debuff.", y); y = y - 22

  local blBox = CreateFrame("Frame", nil, bd)
  blBox:SetSize(120, 22)
  blBox:SetPoint("TOPLEFT", bd, "TOPLEFT", 16, y)
  Flat(blBox, BG[1], BG[2], BG[3], 1)

  local blEdit = CreateFrame("EditBox", nil, blBox)
  blEdit:SetPoint("TOPLEFT", blBox, 5, -1)
  blEdit:SetPoint("BOTTOMRIGHT", blBox, -5, 1)
  blEdit:SetFont(J.font, 11)
  blEdit:SetJustifyH("LEFT")
  blEdit:SetAutoFocus(false)
  blEdit:SetNumeric(true)          -- digits only: no bad input can reach the db
  blEdit:SetMaxLetters(9)
  blEdit:SetTextInsets(0, 0, 0, 0)
  blEdit:SetTextColor(TXT[1], TXT[2], TXT[3])
  blEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local BL_ROWS, BL_ROW_H = 12, 18
  local blList = CreateFrame("Frame", nil, bd)
  blList:SetPoint("TOPLEFT", bd, "TOPLEFT", 16, y - 30)
  blList:SetSize(220, BL_ROWS * BL_ROW_H)

  local blEmpty = Label(blList, 11, "LEFT")
  blEmpty:SetPoint("TOPLEFT", blList, "TOPLEFT", 0, -2)
  blEmpty:SetText("No debuffs blacklisted.")
  blEmpty:SetTextColor(DIM[1], DIM[2], DIM[3])

  local blRows, blIDs, blOffset = {}, {}, 0
  local RefreshBlacklist

  local function BlacklistRow(i)
    local row = blRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, blList)
    row:SetSize(220, BL_ROW_H - 2)
    row:SetPoint("TOPLEFT", blList, "TOPLEFT", 0, -(i - 1) * BL_ROW_H)

    row.text = Label(row, 11, "LEFT")
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.del = MakeButton(row, "x", 16, 16, function(self)
      local id = self:GetParent().auraID
      if id and J.db.debuffBlacklist then
        J.db.debuffBlacklist[id] = nil
        if J.UpdateDebuffBlacklist then J:UpdateDebuffBlacklist() end
        RefreshBlacklist()
      end
    end)
    row.del:SetPoint("LEFT", row, "LEFT", 92, 0)

    blRows[i] = row
    return row
  end

  -- Rebuilds the visible rows from the hash map. Called only on add/remove and
  -- when the panel is first built.
  function RefreshBlacklist()
    for i = #blIDs, 1, -1 do blIDs[i] = nil end
    local t = J.db.debuffBlacklist
    if type(t) == "table" then
      for id in pairs(t) do
        if type(id) == "number" then blIDs[#blIDs + 1] = id end
      end
      table.sort(blIDs)
    end

    local total = #blIDs
    local maxOffset = total - BL_ROWS
    if maxOffset < 0 then maxOffset = 0 end
    if blOffset > maxOffset then blOffset = maxOffset end

    for i = 1, BL_ROWS do
      local id = blIDs[i + blOffset]
      if id then
        local row = BlacklistRow(i)
        row.auraID = id
        row.text:SetText("Aura " .. id)
        row:Show()
      elseif blRows[i] then
        blRows[i].auraID = nil
        blRows[i]:Hide()
      end
    end

    if total > 0 then blEmpty:Hide() else blEmpty:Show() end
  end

  blList:EnableMouseWheel(true)
  blList:SetScript("OnMouseWheel", function(self, delta)
    local maxOffset = #blIDs - BL_ROWS
    if maxOffset < 1 then return end
    blOffset = blOffset - delta
    if blOffset < 0 then blOffset = 0 end
    if blOffset > maxOffset then blOffset = maxOffset end
    RefreshBlacklist()
  end)

  local function AddBlacklistID()
    local id = tonumber(blEdit:GetText())
    blEdit:SetText("")
    blEdit:ClearFocus()
    if not id or id <= 0 then return end
    id = math.floor(id)
    if type(J.db.debuffBlacklist) ~= "table" then J.db.debuffBlacklist = {} end
    J.db.debuffBlacklist[id] = true
    if J.UpdateDebuffBlacklist then J:UpdateDebuffBlacklist() end
    RefreshBlacklist()
  end

  blEdit:SetScript("OnEnterPressed", AddBlacklistID)

  local blAdd = MakeButton(bd, "Add", 60, 22, AddBlacklistID)
  blAdd:SetPoint("LEFT", blBox, "RIGHT", 8, 0)

  RefreshBlacklist()

  -- Page 5: Minimap ---------------------------------------------------------
  local mm = pages[5]
  y = -14
  Header(mm, "Minimap", y); y = y - 22
  Hint(mm, "Step 1 is the default size, step 5 is 20% larger.", y); y = y - 24
  MakeSlider(mm, "JunkieMapSizeSlider", "Minimap size", 1, 5, J.db.mapSize or 1, y, function(v)
    J.db.mapSize = v
    if J.ApplyMinimapSize then J:ApplyMinimapSize() end
  end)
  y = y - 50
  Hint(mm, "Clock, button box and player auras follow the map size.", y)

  -- Page 6: Movers ----------------------------------------------------------
  local m = pages[6]
  y = -14
  Header(m, "Movable frames", y); y = y - 26
  MakeCheck(m, "Unlock the quest tracker so you can drag it", y, J.db.watchUnlocked, function(v)
    if J.SetWatchUnlocked then J:SetWatchUnlocked(v) else J.db.watchUnlocked = v end
  end)
  y = y - 24
  MakeCheck(m, "Unlock the loot roll window so you can drag it", y, J.db.lootUnlocked, function(v)
    if J.SetLootUnlocked then J:SetLootUnlocked(v) else J.db.lootUnlocked = v end
  end)
  y = y - 24
  -- Totem bar: both options belong to the same element, so they share a row.
  MakeCheck(m, "Unlock the totem bar so you can drag it", y, J.db.totemUnlocked, function(v)
    if J.SetTotemUnlocked then J:SetTotemUnlocked(v) else J.db.totemUnlocked = v end
  end)
  MakeCheck(m, "Show totem bar", y, J.db.totemBar ~= false, function(v)
    J.db.totemBar = v
    if J.UpdateTotemBar then J:UpdateTotemBar() end
  end, 330)



  -- Page 7: Tooltip ---------------------------------------------------------
  local tt = pages[7]
  y = -14
  Header(tt, "Tooltip", y); y = y - 26
  MakeCheck(tt, "Unlock the tooltip so you can drag it", y, J.db.tooltipUnlocked, function(v)
    if J.SetTooltipAnchorUnlocked then J:SetTooltipAnchorUnlocked(v) else J.db.tooltipUnlocked = v end
  end)
  y = y - 24
  MakeCheck(tt, "Tooltip follows the mouse", y, J.db.tooltipMouse, function(v)
    J.db.tooltipMouse = v
    if J.RequireReload then J:RequireReload() end
  end)
  y = y - 24
  MakeCheck(tt, "Show spell and aura IDs in tooltips", y, J.db.tooltipIDs, function(v)
    J.db.tooltipIDs = v
  end)

  -- Page 8: Quality of life -------------------------------------------------
  local q = pages[8]
  y = -14
  Header(q, "Auto repair", y); y = y - 24
  Hint(q, "Repairs all gear when you open a repair merchant.", y); y = y - 22
  MakeCheck(q, "Repair automatically at a vendor", y, J.db.autoRepair, function(v)
    J.db.autoRepair = v
  end)

  -- Page 9: About -----------------------------------------------------------
  local o = pages[9]
  y = -14
  Header(o, "About", y); y = y - 24
  Hint(o, "Plug and play. No profiles, no fuss.", y); y = y - 16
  Hint(o, "Slash command: /jui", y); y = y - 30
  Header(o, "Compatibility", y); y = y - 24
  Hint(o, "For the best experience, avoid other addons that", y); y = y - 14
  Hint(o, "reposition or reskin UI elements while using Junkie UI.", y)

  -- Page 10: Cooldown manager (JunkieCD plugs in here) ------------------------
  local cdp = pages[10]

  local host = CreateFrame("Frame", "JunkieCDHost", cdp)
  host:SetPoint("TOPLEFT", cdp, "TOPLEFT", 6, -6)
  host:SetSize(PAGE_W - 12, PAGE_H - 12)
  host:Hide()
  J.cdHost = host

  local intro = CreateFrame("Frame", nil, cdp)
  intro:SetAllPoints(cdp)

  y = -14
  Header(intro, "Junkie Cooldown Manager", y); y = y - 24
  Hint(intro, "A separate module that plugs its settings into this window.", y); y = y - 16
  Hint(intro, "It only runs while Junkie UI is loaded.", y); y = y - 30

  -- If the module ever fails to build its page we say so on the page itself:
  -- a blank tab tells the player nothing, and chat output is easy to miss.
  local cdError = Hint(intro, "", -110)
  cdError:SetTextColor(0.9, 0.35, 0.35)
  cdError:Hide()

  local activate
  local function RefreshCDPage()
    local active = J:CooldownManagerActive()
    if active and J.cdBuilder and not J.cdBuilt then
      J.cdBuilt = true
      local ok, err = pcall(J.cdBuilder, host)
      if not ok then
        J.cdBuilt = false
        cdError:SetText("The cooldown manager settings failed to load:\n" .. tostring(err))
        cdError:Show()
        print("|cff4fc3f7JunkieUI:|r cooldown manager settings failed to build: " .. tostring(err))
      else
        cdError:Hide()
      end
    end

    if active and J.cdBuilt then
      intro:Hide()
      host:Show()
    else
      host:Hide()
      intro:Show()
    end
    if activate then activate.checked = (J.db.cdEnabled and true or false); activate:Refresh() end
    if J.SyncGapState then J.SyncGapState() end
  end
  J.RefreshCDPage = RefreshCDPage

  activate = MakeCheck(intro, "Activate Junkie Cooldown Manager", y, J.db.cdEnabled, function(v)
    if v and not GetAddOnInfo("JunkieCD") then
      J.db.cdEnabled = false
      print("|cff4fc3f7JunkieUI:|r Junkie Cooldown Manager is not installed.")
      RefreshCDPage()
      return
    end
    J.db.cdEnabled = v
    if v and EnableAddOn then EnableAddOn("JunkieCD") end
    RefreshCDPage()
    -- Turning the module on or off always reloads: that is the only way the
    -- addon list, its saved variables and our frames end up in the same state.
    print("|cff4fc3f7JunkieUI:|r " .. (v and "activating" or "deactivating")
      .. " the cooldown manager - reloading the interface.")
    ReloadUI()
  end)



  -- Footer -----------------------------------------------------------------
  local reload = MakeButton(panel, "Reload UI", 110, 22, function() ReloadUI() end)
  reload:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 14)

  local done = MakeButton(panel, "Close", 110, 22, function() panel:Hide() end)
  done:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 14)

  local note = Label(panel, 10, "CENTER")
  note:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)
  note:SetText("")

  panel.reloadBtn, panel.closeBtn, panel.reloadNote = reload, done, note

  function J:RequireReload()
    if not panel then return end
    panel.reloadBtn.text:SetText("Reload UI *")
    panel.reloadBtn.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    panel.reloadNote:SetText("Reload required to apply this change")
    panel.reloadNote:SetTextColor(0.9, 0.35, 0.35)
  end

  -- Idle fade + live refresh: the window (and any cooldown-manager popup that
  -- belongs to it) sits at 50% while the mouse is elsewhere and lights up on
  -- hover. The same watcher re-docks everything that normally only follows the
  -- unit frames on events, so sliders look live while settings are open. It is
  -- a child of the panel, so nothing ticks once the window is closed.
  local fade = CreateFrame("Frame", nil, panel)
  fade.elapsed = 0
  fade:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed < 0.1 then return end
    self.elapsed = 0
    local windows = (JunkieCD and JunkieCD.settingsWindows) or nil
    local over = MouseIsOver(panel) and true or false
    if not over and windows then
      for _, w in ipairs(windows) do
        if w:IsShown() and MouseIsOver(w) then over = true break end
      end
    end
    local want = over and 1 or 0.5
    if math.abs((panel:GetAlpha() or 1) - want) > 0.01 then panel:SetAlpha(want) end
    if windows then
      for _, w in ipairs(windows) do
        if w:IsShown() and math.abs((w:GetAlpha() or 1) - want) > 0.01 then w:SetAlpha(want) end
      end
    end

    -- Followers of the player frame (cooldown manager bars) are rebuilt only
    -- when the frame actually moved, so an open settings window costs one
    -- geometry read per tick and nothing else.
    local pf = _G["JunkiePlayerFrame"]
    if pf and JunkieCD and JunkieCD.Rebuild then
      local left, bottom = pf:GetLeft(), pf:GetBottom()
      if left and bottom then
        local sig = math.floor(left + 0.5) .. ":" .. math.floor(bottom + 0.5)
        if sig ~= self.unitSig then
          self.unitSig = sig
          JunkieCD:Rebuild()
        end
      end
    end
  end)


  Select(1)
  panel:HookScript("OnHide", function()
    if J.SetPlayerAuraPreview then J:SetPlayerAuraPreview(false) end
  end)
  panel:Hide()
end

-- Combat lockout ------------------------------------------------------------
local inCombat = false

local function IsInCombat()
  if inCombat then return true end
  if InCombatLockdown and InCombatLockdown() then return true end
  if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
  return false
end

local combatGuard = CreateFrame("Frame")
combatGuard:RegisterEvent("PLAYER_REGEN_DISABLED")
combatGuard:RegisterEvent("PLAYER_REGEN_ENABLED")
combatGuard:RegisterEvent("PLAYER_ENTERING_WORLD")
combatGuard:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
  else
    inCombat = true
  end
  if inCombat and panel and panel:IsShown() then
    panel:Hide()
    print("|cff4fc3f7JunkieUI:|r settings closed - entering combat.")
  end
end)

local function EnsurePanel()
  if not panel then
    BuildPanel()
    -- last line of defence: never allow the panel up while in combat
    panel:HookScript("OnShow", function(self)
      if IsInCombat() then self:Hide() end
    end)
  end
  return panel
end

function J:ToggleConfig()
  if IsInCombat() then
    print("|cff4fc3f7JunkieUI:|r settings are locked during combat.")
    return
  end
  EnsurePanel()
  if panel:IsShown() then panel:Hide() else panel:Show() end
end

function J:CloseConfig()
  if panel then panel:Hide() end
end

-- Module API (closed): the cooldown manager is the only consumer -------------
-- JunkieCD hands us a builder; we call it the first time its page is opened.
function J:RegisterCooldownManagerPanel(builder)
  J.cdBuilder = builder
  if J.RefreshCDPage then J.RefreshCDPage() end
end

function J:CooldownManagerActive()
  if not (J.db and J.db.cdEnabled) then return false end
  return IsAddOnLoaded("JunkieCD") and true or false
end

-- True while the manager is loaded and locked between the unit frames.
function J:CDLocked()
  if not J:CooldownManagerActive() then return false end
  return (JunkieCD and JunkieCD.db and JunkieCD.db.locked) and true or false
end

function J:OpenCooldownManager()
  if not J:CooldownManagerActive() then
    print("|cff4fc3f7JunkieUI:|r the cooldown manager is not active. Open /jui and tick it on.")
    return false
  end
  if IsInCombat() then
    print("|cff4fc3f7JunkieUI:|r settings are locked during combat.")
    return false
  end
  EnsurePanel()
  panel:Show()
  panel.SelectPage(10)
  return true
end

SLASH_JUNKIEUI1 = "/jui"
SlashCmdList["JUNKIEUI"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  -- "/jui coa" is a read-only report: which Ascension resource widgets exist,
  -- whether they are shown, and who their parent is. Nothing is changed.
  if msg == "coa" then
    if J.ReportCoAResourceBars then J:ReportCoAResourceBars() end
    return
  end
  J:ToggleConfig()
end





-- Minimap shortcut button (mirror of the minimap button collector) -----------
J:AddModule(function()
  local b = CreateFrame("Button", "JunkieConfigButton", JunkieClock or Minimap)
  b:SetSize(18, 18)
  if JunkieClock then
    b:SetPoint("LEFT", JunkieClock, "LEFT", 2, 0)
  else
    b:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 1)
  end
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  Flat(b, 0.086, 0.086, 0.086, 1)
  b:SetBackdropBorderColor(0, 0, 0, 1)

  local fs = b:CreateFontString(nil, "OVERLAY")
  fs:SetFont(J.font, 13, "OUTLINE")
  fs:SetPoint("CENTER")
  fs:SetText("J")
  fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

  b:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("JunkieUI", ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddLine("Click to open settings (/jui)", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0, 0, 0, 1)
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function() J:ToggleConfig() end)

  -- Micro menu toggle, right next to the "J" button.
  local mb = CreateFrame("Button", "JunkieMicroToggle", JunkieClock or Minimap)
  mb:SetSize(18, 18)
  mb:SetPoint("LEFT", b, "RIGHT", 2, 0)
  mb:SetFrameStrata("MEDIUM")
  mb:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  Flat(mb, 0.086, 0.086, 0.086, 1)
  mb:SetBackdropBorderColor(0, 0, 0, 1)

  local mfs = mb:CreateFontString(nil, "OVERLAY")
  mfs:SetFont(J.font, 13, "OUTLINE")
  mfs:SetPoint("CENTER")
  mfs:SetText("M")

  local function RefreshMicro()
    local on = J.db and J.db.microMenu
    if on then
      mfs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else
      mfs:SetTextColor(0.45, 0.45, 0.45)
    end
  end
  RefreshMicro()

  mb:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Micro menu", ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddLine("Click to show or hide the micro menu", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  mb:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0, 0, 0, 1)
    GameTooltip:Hide()
  end)
  mb:SetScript("OnClick", function()
    if J.SetMicroMenu then J:SetMicroMenu(not (J.db and J.db.microMenu)) end
    RefreshMicro()
  end)
end)

