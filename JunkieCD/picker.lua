-- Spell / item picker. Scans the spellbook on login and whenever the spellbook
-- changes (talent or spec swap), plus every on-use item in bags and equipped.
local C = JunkieCD

local cache, cacheDirty = {}, true
local picker

local function AddSpells(out)
  local best = {}
  local i = 1
  -- Hard cap: a corrupted spellbook can keep answering with a name, and an
  -- unbounded loop here would freeze the client.
  while i < 1024 do
    local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
    if not name then break end
    if not IsPassiveSpell(i, BOOKTYPE_SPELL) then
      local link = GetSpellLink(i, BOOKTYPE_SPELL)
      local id = link and tonumber(string.match(link, "spell:(%d+)"))
      if not id then
        local l2 = GetSpellLink(name)
        id = l2 and tonumber(string.match(l2, "spell:(%d+)"))
      end
      -- Some custom clients throw on hidden or pet-only book indices; a single
      -- bad texture must never abort the whole spellbook scan.
      local okTex, tex = pcall(GetSpellTexture, i, BOOKTYPE_SPELL)
      local entry = {
        kind = "spell",
        id = id,
        name = name,
        rank = rank,
        label = (rank and rank ~= "") and (name .. " (" .. rank .. ")") or name,
        icon = okTex and tex or nil,
      }
      table.insert(out, entry)
      -- Highest rank per name = the last one found in the book.
      best[name] = entry
    end
    i = i + 1
  end
  for _, e in ipairs(out) do
    if e.kind == "spell" then e.highest = (best[e.name] == e) end
  end
end

local function AddItem(out, link, seen, tex, force)
  if not link then return end
  local id = tonumber(string.match(link, "item:(%d+)"))
  if not id or seen[id] then return end
  local name, _, _, _, _, _, _, _, _, itex = GetItemInfo(link)
  -- Uncached items (very common for anything sitting on cooldown) still give a
  -- usable name from the link itself, so never drop them.
  name = name or string.match(link, "%[(.-)%]") or ("item " .. id)
  tex = itex or tex
  if not force and not GetItemSpell(link) then return end  -- on-use items only
  seen[id] = true
  table.insert(out, { kind = "item", id = id, name = name, label = name, icon = tex, highest = true })
end

local function AddItems(out)
  local seen = {}
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      local tex = GetContainerItemInfo(bag, slot)
      AddItem(out, GetContainerItemLink(bag, slot), seen, tex)
    end
  end
  for inv = 1, 19 do
    -- Trinkets are always listed, cooldown or not.
    AddItem(out, GetInventoryItemLink("player", inv), seen,
      GetInventoryItemTexture("player", inv), inv == 13 or inv == 14)
  end
end

-- Slot based picks: they follow whatever trinket is worn instead of a fixed
-- item id, and they only draw while that slot holds an on-use trinket.
local TRINKET_PICKS = {
  { kind = "trinket", id = 13, name = "Trinket slot 1", label = "Trinket slot 1", highest = true },
  { kind = "trinket", id = 14, name = "Trinket slot 2", label = "Trinket slot 2", highest = true },
}

function C:InvalidateSpellCache() cacheDirty = true end

function C:SpellList()
  if not cacheDirty then return cache end
  cache = {}
  AddSpells(cache)
  AddItems(cache)
  table.sort(cache, function(a, b)
    if a.kind ~= b.kind then return a.kind == "spell" end
    return (a.label or a.name) < (b.label or b.name)
  end)
  -- Always last in the list, whatever the search order was.
  for i = 1, #TRINKET_PICKS do
    local e = TRINKET_PICKS[i]
    e.icon = GetInventoryItemTexture("player", e.id) or "Interface\\Icons\\INV_Misc_Pocketwatch_01"
    cache[#cache + 1] = e
  end
  cacheDirty = false
  return cache
end

-- Picker UI -------------------------------------------------------------------
local ROWS = 14
local ROW_H = 22

local function Filtered(text, highestOnly)
  local list = C:SpellList()
  text = text and text:lower() or ""
  local out = {}
  for _, e in ipairs(list) do
    local label = e.label or e.name
    local ok = (text == "") or label:lower():find(text, 1, true)
      or (e.id and tostring(e.id):find(text, 1, true))
    if ok and (not highestOnly or e.highest) then
      table.insert(out, e)
    end
  end
  return out
end

local function BuildPicker()
  picker = CreateFrame("Frame", "JunkieCDPicker", UIParent)
  picker:SetSize(360, 420)
  picker:SetFrameStrata("FULLSCREEN_DIALOG")
  picker:SetMovable(true)
  picker:EnableMouse(true)
  picker:RegisterForDrag("LeftButton")
  picker:SetScript("OnDragStart", picker.StartMoving)
  picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
  C:Flat(picker, C.BOX[1], C.BOX[2], C.BOX[3], 1)
  C:RegisterSettingsWindow(picker)

  -- Click-outside-to-close: a full screen catcher sits one level below the
  -- popup while it is open, so any click that misses the popup closes it.
  local closer = CreateFrame("Button", nil, UIParent)
  closer:SetAllPoints(UIParent)
  closer:SetFrameStrata("FULLSCREEN_DIALOG")
  closer:SetFrameLevel(1)
  closer:RegisterForClicks("AnyUp")
  closer:SetScript("OnClick", function() picker:Hide() end)
  closer:Hide()
  picker:HookScript("OnShow", function(self)
    closer:Show()
    closer:SetFrameLevel(1)
    self:SetFrameLevel(closer:GetFrameLevel() + 10)
  end)
  picker:HookScript("OnHide", function() closer:Hide() end)


  local title = C:Text(picker, 12, "LEFT")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("PICK A SPELL OR ITEM")
  picker.title = title
  title:SetTextColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3])

  local close = CreateFrame("Button", nil, picker)
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", -8, -8)
  C:Flat(close, C.BG[1], C.BG[2], C.BG[3], 1)
  local ct = C:Text(close, 11, "CENTER")
  ct:SetPoint("CENTER")
  ct:SetText("X")
  close:SetScript("OnClick", function() picker:Hide() end)

  local searchBox = CreateFrame("Frame", nil, picker)
  searchBox:SetPoint("TOPLEFT", 12, -34)
  searchBox:SetSize(190, 22)
  C:Flat(searchBox, C.BG[1], C.BG[2], C.BG[3], 1)
  picker.searchBox = searchBox
  local search = CreateFrame("EditBox", nil, searchBox)
  search:SetPoint("TOPLEFT", 5, -1)
  search:SetPoint("BOTTOMRIGHT", -5, 1)
  search:SetFont(C.font, 11)
  search:SetAutoFocus(false)
  search:SetTextColor(C.TXT[1], C.TXT[2], C.TXT[3])
  search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  picker.search = search

  -- Manual ID entry
  local idBox = CreateFrame("Frame", nil, picker)
  idBox:SetPoint("TOPLEFT", searchBox, "TOPRIGHT", 6, 0)
  idBox:SetSize(66, 22)
  C:Flat(idBox, C.BG[1], C.BG[2], C.BG[3], 1)
  local idEdit = CreateFrame("EditBox", nil, idBox)
  idEdit:SetPoint("TOPLEFT", 4, -1)
  idEdit:SetPoint("BOTTOMRIGHT", -4, 1)
  idEdit:SetFont(C.font, 11)
  idEdit:SetAutoFocus(false)
  idEdit:SetNumeric(true)
  idEdit:SetMaxLetters(7)
  idEdit:SetTextColor(C.TXT[1], C.TXT[2], C.TXT[3])
  idEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  picker.idBox, picker.idEdit = idBox, idEdit

  local function SubmitID()
    local id = tonumber(idEdit:GetText())
    if id and id > 0 and picker.callback then
      picker.callback({ kind = picker.mode == "item" and "item" or "spell", id = id })
      picker:Hide()
    end
  end
  idEdit:SetScript("OnEnterPressed", SubmitID)

  local addID = CreateFrame("Button", nil, picker)
  addID:SetSize(38, 22)
  addID:SetPoint("TOPLEFT", idBox, "TOPRIGHT", 6, 0)
  C:Flat(addID, C.BG[1], C.BG[2], C.BG[3], 1)
  local at = C:Text(addID, 11, "CENTER")
  at:SetPoint("CENTER")
  at:SetText("ID")
  at:SetTextColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3])
  addID:SetScript("OnClick", SubmitID)
  picker.addID = addID

  local hint = C:Text(picker, 10, "LEFT")
  hint:SetPoint("TOPLEFT", 12, -60)
  hint:SetTextColor(C.DIM[1], C.DIM[2], C.DIM[3])
  hint:SetWidth(336)
  hint:SetJustifyV("TOP")
  picker.hint = hint

  -- The hint wraps onto a variable number of lines, so everything below it is
  -- re-anchored from its measured height instead of a fixed offset.
  function picker:LayoutBelowHint(topY, showRank)
    local h = math.ceil((self.hint:GetStringHeight() or 12) + 8)
    local y = topY - h
    if showRank then
      self.rank:ClearAllPoints()
      self.rank:SetPoint("TOPLEFT", 12, y)
      y = y - 22
    end
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 12, y)
    self.list:SetPoint("BOTTOMRIGHT", -12, 12)
    return y
  end

  -- Highest rank only ---------------------------------------------------------
  local rank = CreateFrame("Button", nil, picker)
  rank:SetSize(14, 14)
  rank:SetPoint("TOPLEFT", 12, -76)
  C:Flat(rank, C.BG[1], C.BG[2], C.BG[3], 1)
  local fill = rank:CreateTexture(nil, "ARTWORK")
  fill:SetTexture("Interface\\Buttons\\WHITE8X8")
  fill:SetPoint("TOPLEFT", 3, -3)
  fill:SetPoint("BOTTOMRIGHT", -3, 3)
  fill:SetVertexColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
  local rt = C:Text(rank, 10, "LEFT")
  rt:SetPoint("LEFT", rank, "RIGHT", 6, 0)
  rt:SetText("Highest rank only")
  rt:SetTextColor(C.DIM[1], C.DIM[2], C.DIM[3])
  rank.fill = fill
  picker.rank = rank

  local list = CreateFrame("Frame", nil, picker)
  list:SetPoint("TOPLEFT", 12, -96)
  list:SetPoint("BOTTOMRIGHT", -12, 12)
  C:Flat(list, C.BG[1], C.BG[2], C.BG[3], 1)
  picker.list = list

  local scroll = CreateFrame("ScrollFrame", "JunkieCDPickerScroll", list, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -26, 4)

  picker.rows = {}
  for i = 1, ROWS do
    local b = CreateFrame("Button", nil, list)
    b:SetSize(258, ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.text = C:Text(b, 11, "LEFT")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.text:SetTextColor(C.TXT[1], C.TXT[2], C.TXT[3])
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.hl:SetVertexColor(0.18, 0.11, 0.06, 1)
    b.hl:Hide()
    b:SetScript("OnEnter", function(self) self.hl:Show() end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    b:SetScript("OnClick", function(self)
      if self.entry and picker.callback then
        picker.callback({ kind = self.entry.kind, id = self.entry.id, name = self.entry.name })
        picker:Hide()
      end
    end)
    picker.rows[i] = b
  end

  local function Refresh()
    local data = Filtered(search:GetText(), C.db and C.db.highestRankOnly)
    FauxScrollFrame_Update(scroll, #data, ROWS, ROW_H)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, ROWS do
      local b = picker.rows[i]
      local e = data[i + offset]
      if e then
        b.entry = e
        b.icon:SetTexture(e.icon)
        -- A slot pick has no item id worth printing.
        local suffix = (e.kind ~= "trinket" and e.id) and ("  |cff8a8a8a" .. e.id .. "|r") or ""
        b.text:SetText((e.label or e.name) .. suffix)
        b:Show()
      else
        b.entry = nil
        b:Hide()
      end
    end
  end
  picker.Refresh = Refresh
  rank:SetScript("OnClick", function()
    C.db.highestRankOnly = not C.db.highestRankOnly
    if C.db.highestRankOnly then fill:Show() else fill:Hide() end
    Refresh()
  end)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Refresh)
  end)
  search:SetScript("OnTextChanged", Refresh)
  picker:Hide()
end

-- The picker opens next to the icon that was clicked instead of somewhere on
-- the far side of the screen. It is clamped so it never leaves the viewport.
local function PlaceAtAnchor(f, anchor)
  if not (anchor and anchor.GetCenter and anchor:IsVisible()) then return false end
  local ax, ay = anchor:GetCenter()
  if not ax then return false end
  local scale = f:GetEffectiveScale()
  local ascale = anchor:GetEffectiveScale()
  local w, h = f:GetWidth(), f:GetHeight()
  local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale() / scale
  local sh = UIParent:GetHeight() * UIParent:GetEffectiveScale() / scale
  local left = (anchor:GetRight() or ax) * ascale / scale + 8
  local top = (anchor:GetTop() or ay) * ascale / scale
  if left + w > sw then left = (anchor:GetLeft() or ax) * ascale / scale - 8 - w end
  if left < 0 then left = 0 end
  if top - h < 0 then top = h end
  if top > sh then top = sh end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  return true
end

-- mode: "spell" (cooldown slot) or "aura" (exact aura id)
-- anchor: the clicked icon, so the popup opens right next to it.
function C:OpenPicker(mode, callback, anchor)
  if not picker then BuildPicker() end
  picker.mode = mode
  picker.callback = callback
  picker.search:SetText("")
  picker.idEdit:SetText("")
  if mode == "aura" then
    -- Auras are tracked by exact aura id only, so no spellbook list here.
    picker:SetSize(360, 156)
    picker.title:SetText("EXACT AURA ID")
    picker.searchBox:Hide()
    picker.rank:Hide()
    picker.list:Hide()
    picker.idBox:ClearAllPoints()
    picker.idBox:SetPoint("TOPLEFT", 12, -44)
    picker.hint:ClearAllPoints()
    picker.hint:SetPoint("TOPLEFT", 12, -78)
    picker.hint:SetText("Type the exact aura spell ID and press ID or Enter.\nEnable \"SpellID and AuraID on tooltip\" and mouse over your buff or debuff to find its aura ID.")
    picker:SetHeight(90 + math.ceil((picker.hint:GetStringHeight() or 12) + 20))
    picker:Show()
    if not PlaceAtAnchor(picker, anchor) then
      C:PlaceSettingsWindow(picker, _G["JunkieCDIconPopup"])
    end
    picker.idEdit:SetFocus()

  else
    picker:SetSize(360, 440)
    picker.title:SetText("PICK A SPELL OR ITEM")
    picker.searchBox:Show()
    picker.rank:Show()
    picker.list:Show()
    picker.idBox:ClearAllPoints()
    picker.idBox:SetPoint("TOPLEFT", picker.searchBox, "TOPRIGHT", 6, 0)
    picker.hint:ClearAllPoints()
    picker.hint:SetPoint("TOPLEFT", 12, -60)
    picker.hint:SetText("Search by name or ID, or type an exact ID and press ID.\nEnable \"SpellID and AuraID on tooltip\" and mouse over your buff or debuff to find its aura ID.")
    picker:LayoutBelowHint(-60, true)

    if C.db.highestRankOnly then picker.rank.fill:Show() else picker.rank.fill:Hide() end
    picker:Show()
    if not PlaceAtAnchor(picker, anchor) then
      C:PlaceSettingsWindow(picker, _G["JunkieCDIconPopup"])
    end
    picker.Refresh()
    picker.search:SetFocus()
  end
end

C:AddModule(function()
  local f = CreateFrame("Frame")
  f:RegisterEvent("SPELLS_CHANGED")
  f:RegisterEvent("LEARNED_SPELL_IN_TAB")
  f:RegisterEvent("PLAYER_TALENT_UPDATE")
  f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  f:SetScript("OnEvent", function() C:InvalidateSpellCache() end)
end)
