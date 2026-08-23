-- Junkie CD - display layer
-- Layout (top to bottom):
--   aura row 3 / 2 / 1        (dynamic, centred, only active auras)
--   60px gap
--   combo point bar           (15px, docked on top of the power bars)
--   power bar 2 / power bar 1 (15px each, 1px gap)
--   1px gap
--   main cooldown bar         (40px icons, 1px gaps)
--   secondary cooldown bar
-- Only the power bars use an OnUpdate (capped at 100 fps); everything else is
-- event driven and uses the client's own Cooldown widget for swipes.
local C = JunkieCD

-- Upvalues. Everything below runs per icon, per tick, so the globals are
-- resolved once at load instead of on every single call.
local GetTime, GetSpellInfo, GetSpellCooldown = GetTime, GetSpellInfo, GetSpellCooldown
local GetItemInfo, GetItemCooldown, GetItemCount = GetItemInfo, GetItemCooldown, GetItemCount
local GetActionInfo, GetActionCooldown, GetActionCount = GetActionInfo, GetActionCooldown, GetActionCount
local IsUsableSpell, IsSpellInRange, UnitAura = IsUsableSpell, IsSpellInRange, UnitAura
local UnitExists, UnitPower, UnitPowerMax = UnitExists, UnitPower, UnitPowerMax
local CreateFrame, pairs, ipairs, pcall, type, tonumber = CreateFrame, pairs, ipairs, pcall, type, tonumber

local GAP = 1
local ROW_GAP = 45
-- The four cooldown canvases, in the order they are drawn.
local SET_KEYS = { "main", "sub", "up", "down" }
local AURA_UNITS = { "player", "target", "pet" }

local anchor, main, sub, slots, rows
local upBar, downBar
local driver
-- Weak keys: an icon frame that is thrown away must never be kept alive by the
-- timer list.
local timedIcons = setmetatable({}, { __mode = "k" })
-- Filled in once the frames exist: { main.icons, sub.icons, upBar.icons, downBar.icons }.
local iconLists = {}
local FindAura
-- Forward declarations: the rebuild pass above uses these before the file
-- defines them further down.
local GlowAuraActive, FindGlowAura
local UpdateRangeTicker
local actionSlotsByID, actionSlotsByName = {}, {}
local auraCache = { player = {}, target = {}, pet = {} }
local auraNameCache = { player = {}, target = {}, pet = {} }
local auraRecords = { player = {}, target = {}, pet = {} }
-- Same lookup maps, but only filled with auras cast by the player. They are
-- built in the very same scan loop, so "only own" costs no extra API calls.
local auraMineCache = { player = {}, target = {}, pet = {} }
local auraMineNameCache = { player = {}, target = {}, pet = {} }
-- True as soon as the client reports a spellID for any aura: exact lookups can
-- then trust the ID map and skip the name fallback entirely.
local auraIDsAvailable = false


-- Custom 3.3.5 clients commonly backport charges through the action API while
-- GetSpellCooldown still reports the spell as ready. Mirror the action button:
-- build this lookup only when the action layout changes, never per icon tick.
-- What each slot currently holds, so a single changed slot can be re-read
-- without walking the whole action bar again.
local actionSlotEntry = {}

local function ForgetActionSlot(slot)
  local prev = actionSlotEntry[slot]
  if not prev then return end
  if prev.id and actionSlotsByID[prev.id] == slot then actionSlotsByID[prev.id] = nil end
  if prev.name and actionSlotsByName[prev.name] == slot then actionSlotsByName[prev.name] = nil end
  prev.id, prev.name = nil, nil
end

local function ReadActionSlot(slot)
  ForgetActionSlot(slot)
  local kind, id = GetActionInfo(slot)
  if kind ~= "spell" or not id then return end
  id = tonumber(id) or id
  local name = GetSpellInfo(id)
  actionSlotsByID[id] = slot
  if name then actionSlotsByName[name] = slot end
  local rec = actionSlotEntry[slot]
  if not rec then rec = {}; actionSlotEntry[slot] = rec end
  rec.id, rec.name = id, name
end

local function RefreshActionSlots()
  for k in pairs(actionSlotsByID) do actionSlotsByID[k] = nil end
  for k in pairs(actionSlotsByName) do actionSlotsByName[k] = nil end
  for slot = 1, 120 do
    local rec = actionSlotEntry[slot]
    if rec then rec.id, rec.name = nil, nil end
    ReadActionSlot(slot)
  end
end

-- ACTIONBAR_SLOT_CHANGED arrives in bursts (dragging a spell, a page flip, a
-- stance swap fires one event per slot). The event names the slot that moved,
-- so only that one is re-read; a page change still asks for the full pass.
-- Either way the work is collapsed into a single pass on the next frame.
local dirtySlots = {}
local fullSlotScan = false
local slotScan = CreateFrame("Frame")
slotScan:Hide()
slotScan:SetScript("OnUpdate", function(self)
  self:Hide()
  if fullSlotScan then
    RefreshActionSlots()
  else
    for slot in pairs(dirtySlots) do ReadActionSlot(slot) end
  end
  fullSlotScan = false
  for slot in pairs(dirtySlots) do dirtySlots[slot] = nil end
  C:UpdateCooldowns()
end)
local function QueueActionSlotScan(slot)
  slot = tonumber(slot)
  if slot and slot >= 1 and slot <= 120 then
    dirtySlots[slot] = true
  else
    fullSlotScan = true
  end
  slotScan:Show()
end


-- SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_USABLE / ACTIONBAR_UPDATE_COOLDOWN fire
-- several times per cast in combat. Repainting every icon on each one is the
-- single most expensive thing this addon can do, so the repaints are collapsed
-- into one pass on the next frame.
local cdQueue = CreateFrame("Frame")
cdQueue:Hide()
cdQueue:SetScript("OnUpdate", function(self)
  self:Hide()
  C:UpdateCooldowns()
end)
local function QueueCooldownUpdate() cdQueue:Show() end
C.QueueCooldownUpdate = QueueCooldownUpdate

-- Timer strings are shared by every icon. Cache each displayed value once so
-- simultaneous cooldowns do not manufacture identical short-lived strings on
-- every 0.2 second pass (a common source of GC spikes on Lua 5.1).
local secondText, minuteText, hourText = {}, {}, {}
local function FormatTime(r)
  local value, cache, suffix
  if r >= 3600 then
    value, cache, suffix = math.floor(r / 3600 + 0.5), hourText, "h"
  elseif r > 60 then
    value, cache, suffix = math.floor(r / 60 + 0.5), minuteText, "m"
  else
    value, cache, suffix = math.floor(r + 0.5), secondText, ""
  end
  local text = cache[value]
  if not text then text = tostring(value) .. suffix; cache[value] = text end
  return text
end

local timerDriver = CreateFrame("Frame")
timerDriver:Hide()
timerDriver.elapsed = 0
timerDriver:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < 0.2 then return end
  self.elapsed = 0
  if not C.db or not C.db.cooldownText then self:Hide(); return end
  local now, active = GetTime(), false
  for f in pairs(timedIcons) do
    local remaining = f.timerStart and f.timerDuration and (f.timerStart + f.timerDuration - now) or 0
    if remaining > 0 and f:IsShown() then
      active = true
      -- Only touch the font string when the printed value actually changed:
      -- SetText re-lays the string out on every call, five times a second.
      local text = FormatTime(remaining)
      if f.jcdTimerText ~= text then
        f.jcdTimerText = text
        f.timerText:SetText(text)
      end
      local low = remaining <= 5
      if f.jcdTimerLow ~= low then
        f.jcdTimerLow = low
        if low then
          f.timerText:SetTextColor(1, 0.25, 0.25)
        else
          f.timerText:SetTextColor(1, 0.85, 0.2)
        end
      end
      f.timerText:Show()
    else
      if f.jcdTimerText ~= "" then
        f.jcdTimerText = ""
        f.timerText:SetText("")
      end
      timedIcons[f] = nil
    end
  end
  if not active then self:Hide() end
end)

local function SetTimer(f, start, duration)
  f.timerStart, f.timerDuration = start, duration
  if C.db and C.db.cooldownText and start and duration and duration > 1.5 and start + duration > GetTime() then
    timedIcons[f] = true
    timerDriver:Show()
  else
    timedIcons[f] = nil
    if f.jcdTimerText ~= "" then
      f.jcdTimerText = ""
      f.timerText:SetText("")
    end
    f.timerText:Hide()
  end
end

local auraScratch = { {}, {}, {}, {} }

-- "Warn before it runs out" is the only time-based aura rule we have. The
-- ticker is only shown while at least one icon actually uses it, so the idle
-- cost is zero for everyone else.
-- The watchers: icon -> warn threshold, filled by UpdateAuras. The 4Hz tick
-- only has to answer "did one of them cross its threshold since last time",
-- which is a handful of number compares instead of a full row redraw.
local expiryWatchers = {}
local expiryDriver = CreateFrame("Frame")
expiryDriver:Hide()
expiryDriver.elapsed = 0
expiryDriver:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < 0.25 then return end
  self.elapsed = 0
  local now, flipped = GetTime(), false
  for f, warnAt in pairs(expiryWatchers) do
    local expires = f.jcdAuraExpires
    local warned = (expires and expires > 0 and (expires - now) <= warnAt) and true or false
    if warned ~= f.jcdWarned then flipped = true; break end
  end
  if not flipped then return end
  -- Redraw only: the aura data itself is already kept current by UNIT_AURA,
  -- so this pass must never rescan all three units four times a second.
  C:UpdateAuras(nil, true)
end)

-- Helpers -------------------------------------------------------------------
-- Name and texture never change for a given id, so a complete answer is kept.
-- EntryInfo is called for every icon on every cooldown repaint.
local spellInfoName, spellInfoTex = {}, {}
local itemInfoName, itemInfoTex = {}, {}
local trinketInfo = {}
local function EntryInfo(entry)
  if not entry or not entry.id then return nil end
  -- A trinket slot follows whatever is worn, so the answer is cached against
  -- the equipment epoch instead of an id: two API calls per swap rather than
  -- two per icon per cooldown repaint.
  if entry.kind == "trinket" then
    local slot = tonumber(entry.id) or 13
    local epoch = C.equipEpoch or 0
    local rec = trinketInfo[slot]
    if rec and rec.epoch == epoch then return rec.name, rec.tex end
    local link = GetInventoryItemLink("player", slot)
    local nm
    if link then nm = GetItemInfo(link) or string.match(link, "%[(.-)%]") end
    nm = nm or ("Trinket slot " .. (slot == 14 and 2 or 1))
    local tex = GetInventoryItemTexture("player", slot)
    rec = rec or {}
    rec.epoch, rec.name, rec.tex = epoch, nm, tex
    trinketInfo[slot] = rec
    return nm, tex
  end

  local key = tonumber(entry.id) or entry.id
  local names = entry.kind == "item" and itemInfoName or spellInfoName
  local textures = entry.kind == "item" and itemInfoTex or spellInfoTex
  local cachedTex = textures[key]
  if cachedTex then return names[key], cachedTex end

  local name, tex
  if entry.kind == "item" then
    local iname, _, _, _, _, _, _, _, _, itex = GetItemInfo(entry.id)
    name, tex = iname, itex
  else
    local sname, _, stex = GetSpellInfo(entry.id)
    name, tex = sname, stex
    -- Some ids (racials and a few ranked spells) answer with a name but without
    -- a texture: the spellbook still has one under that name.
    if name and not tex then
      local ok, btex = pcall(GetSpellTexture, name)
      if ok then tex = btex end
    end
  end
  -- An item that is not in the client cache yet answers with nothing; only a
  -- complete answer is worth keeping.
  if name and tex then names[key], textures[key] = name, tex end
  return name, tex
end

-- Only icons the player actually owns are drawn: the bar packs itself so it
-- always looks complete while a talent swap has taken a spell away.
-- One reusable list per canvas, so a rebuild allocates no tables at all.
local knownScratch = { {}, {}, {}, {} }
local function KnownList(slot, entries, count)
  local out = knownScratch[slot]
  for i = #out, 1, -1 do out[i] = nil end
  for i = 1, (count or 0) do
    local e = entries and entries[i]
    if e and e.id and C:EntryKnown(e) then out[#out + 1] = e end
  end
  return out, #out
end


-- Persistent icons per holder: never pooled, so a rebuild can never produce
-- duplicated or orphaned icons.
local function EnsureIcons(holder, count, size)
  holder.icons = holder.icons or {}
  for i = 1, count do
    local f = holder.icons[i]
    if not f then
      f = CreateFrame("Frame", nil, holder)
      C:Flat(f, C.BACKDROP[1], C.BACKDROP[2], C.BACKDROP[3], 1)

      f.icon = f:CreateTexture(nil, "ARTWORK")
      f.icon:SetPoint("TOPLEFT", 1, -1)
      f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

      f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
      f.cd:SetPoint("TOPLEFT", 1, -1)
      f.cd:SetPoint("BOTTOMRIGHT", -1, 1)

      -- Text lives in its own frame above the cooldown widget, otherwise the
      -- swipe texture paints over the timer.
      f.textLayer = CreateFrame("Frame", nil, f)
      f.textLayer:SetAllPoints(f)
      f.textLayer:SetFrameLevel(f.cd:GetFrameLevel() + 5)

      f.count = C:Text(f.textLayer, 12, "RIGHT")
      f.count:SetPoint("BOTTOMRIGHT", -2, 2)
      f.timerText = C:Text(f.textLayer, 13, "CENTER")
      f.timerText:SetPoint("CENTER", f, "CENTER", 0, 1)
      f.timerText:SetDrawLayer("OVERLAY", 7)
      f:SetScript("OnEnter", function(self)
        local e = self.entry
        if not (e and e.id) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if e.kind == "trinket" then
          GameTooltip:SetInventoryItem("player", tonumber(e.id) or 13)
        elseif e.kind == "item" then
          GameTooltip:SetHyperlink("item:" .. e.id)
        else
          GameTooltip:SetHyperlink("spell:" .. e.id)
        end
        GameTooltip:Show()
      end)
      f:SetScript("OnLeave", function() GameTooltip:Hide() end)
      holder.icons[i] = f
    end
    f:SetSize(size, size)
    f:EnableMouse(holder.tooltips and true or false)
    f:ClearAllPoints()
    f:Show()
  end
  for i = count + 1, #holder.icons do
    local f = holder.icons[i]
    C:SetGlow(f, nil, false)
    SetTimer(f, nil, nil)
    f.entry = nil
    f:Hide()
    f:ClearAllPoints()
  end
end

-- Anchor --------------------------------------------------------------------
local function BuildAnchor()
  anchor = CreateFrame("Frame", "JunkieCDAnchor", UIParent)
  anchor:SetSize(200, 40)

  anchor.mover = CreateFrame("Frame", nil, anchor)
  anchor.mover:SetAllPoints(anchor)
  anchor.mover:SetFrameStrata("HIGH")
  C:Flat(anchor.mover, 0.055, 0.055, 0.055, 0.9)
  anchor.mover:SetBackdropBorderColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3], 1)
  local fs = C:Text(anchor.mover, 11, "CENTER")
  fs:SetPoint("CENTER")
  fs:SetText("JunkieCD")
  fs:SetTextColor(C.ACCENT[1], C.ACCENT[2], C.ACCENT[3])
  anchor.mover:Hide()
end

function C:AnchorPosition()
  local p = C:Profile()
  anchor:ClearAllPoints()
  anchor:SetSize(250, 40)
  if C.db.locked and JunkieUI and JunkieUI.db then
    -- Locked: the manager owns the middle and the unit frames move out of the
    -- way, so it stays centered on the same line as the frames.
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, (JunkieUI.db.unitY or -180) + p.y)
  else
    -- Locked but JunkieUI has not loaded its saved variables yet: this is the
    -- fallback offset, so the login settle pass must place the anchor again.
    if C.db.locked then C.anchorPending = true end
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, p.y - 180)
  end
end


-- Cooldown bars --------------------------------------------------------------
-- Base width used while a bar has no icons at all: the power bars and the
-- combo bar hang off this row, so it must still report a sane width or they
-- would collapse and look invisible.
local BASE_WIDTH = 200
local function BuildCDBar(holder, entries, count, size)
  EnsureIcons(holder, count, size)
  if count <= 0 then
    holder:SetSize(BASE_WIDTH, size)
    holder:Hide()
    return 0
  end
  local width = count * size + (count - 1) * GAP
  holder:SetSize(width, size)
  holder:Show()

  for i = 1, count do
    local f = holder.icons[i]
    if i == 1 then
      f:SetPoint("LEFT", holder, "LEFT", 0, 0)
    else
      f:SetPoint("LEFT", holder.icons[i - 1], "RIGHT", GAP, 0)
    end
    f.entry = entries[i]
  end
  return width
end

-- Bars visually docked to the JunkieUI player frame. They must never use the
-- secure unit button as a relative anchor: on 3.3.5 that protection propagates
-- to the holder and blocks SetSize in combat. Copy the player's screen
-- coordinates into UIParent space instead, leaving these holders unprotected.
local function DockUnitBar(holder, player, grow)
  local left, right = player:GetLeft(), player:GetRight()
  local top, bottom = player:GetTop(), player:GetBottom()
  -- Right after login the unit frame can exist without having been laid out
  -- yet: it answers with nothing, the row would stay hidden until the next
  -- rebuild. Flag it so the login settle pass docks it as soon as it can.
  if not (left and right and top and bottom) then
    C.dockPending = true
    return false
  end
  C.dockLeft, C.dockTop, C.dockBottom = left, top, bottom

  holder:ClearAllPoints()
  if grow == "left" then
    holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", math.floor(right + 0.5), math.floor(top + GAP + 0.5))
  else
    holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.floor(left + 0.5), math.floor(bottom - GAP + 0.5))
  end
  return true
end

local function BuildUnitBar(holder, entries, count, size, grow)
  EnsureIcons(holder, count, size)
  if count <= 0 then
    holder:Hide()
    if grow ~= "left" and JunkieUI and JunkieUI.SetPetDock then JunkieUI:SetPetDock(0) end
    return 0
  end
  local width = count * size + (count - 1) * GAP
  holder:SetSize(width, size)
  for i = 1, count do
    local f = holder.icons[i]
    if grow == "left" then
      if i == 1 then
        f:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
      else
        f:SetPoint("RIGHT", holder.icons[i - 1], "LEFT", -GAP, 0)
      end
    else
      if i == 1 then
        f:SetPoint("LEFT", holder, "LEFT", 0, 0)
      else
        f:SetPoint("LEFT", holder.icons[i - 1], "RIGHT", GAP, 0)
      end
    end
    f.entry = entries[i]
  end

  local pf = _G["JunkiePlayerFrame"]
  if not pf then
    -- JunkieUI has not built its unit frames yet: try again from the settle pass.
    C.dockPending = true
    holder:ClearAllPoints()

    holder:Hide()
    if grow ~= "left" and JunkieUI and JunkieUI.SetPetDock then JunkieUI:SetPetDock(0) end
    return width
  end
  if not DockUnitBar(holder, pf, grow) then
    holder:Hide()
    return width
  end
  if grow ~= "left" then
    -- The lower row sits where the pet health bar normally lives, so JunkieUI
    -- is told to push the pet bar underneath it.
    if JunkieUI and JunkieUI.SetPetDock then JunkieUI:SetPetDock(size) end
  end
  holder:Show()
  return width
end

-- Bars -----------------------------------------------------------------------
-- Power bars and combo plates follow the bar texture chosen in JunkieUI.
C.statusbars, C.comboFills = {}, {}

function C:BarTexture()
  return (JunkieUI and JunkieUI.statusbar) or "Interface\\Buttons\\WHITE8X8"
end

function C:ApplyBarTexture(path)
  path = path or C:BarTexture()
  for i = #C.statusbars, 1, -1 do
    local bar = C.statusbars[i]
    if bar and bar.SetStatusBarTexture then
      local r, g, b, a = bar:GetStatusBarColor()
      bar:SetStatusBarTexture(path)
      if r then bar:SetStatusBarColor(r, g, b, a) end
    else
      table.remove(C.statusbars, i)
    end
  end
  for i = #C.comboFills, 1, -1 do
    local tex = C.comboFills[i]
    if tex and tex.SetTexture then
      local r, g, b, a = tex:GetVertexColor()
      tex:SetTexture(path)
      if r then tex:SetVertexColor(r, g, b, a) end
    else
      table.remove(C.comboFills, i)
    end
  end
end

-- One universal bar slot. It owns both looks at once: a fluid status bar and a
-- row of combo plates. Only the one the slot is set to is ever shown, so a
-- slot can switch between the two modes without rebuilding any frame.
local function BuildSlot(parent)
  local f = CreateFrame("Frame", nil, parent)
  C:Flat(f, C.BACKDROP[1], C.BACKDROP[2], C.BACKDROP[3], 1)
  f.bar = CreateFrame("StatusBar", nil, f)
  f.bar:SetPoint("TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  f.bar:SetStatusBarTexture(C:BarTexture())
  C.statusbars[#C.statusbars + 1] = f.bar
  f.bar:SetMinMaxValues(0, 1)
  -- Text lives on its own frame above the fill so it stays readable on a full bar.
  f.textLayer = CreateFrame("Frame", nil, f)
  f.textLayer:SetAllPoints(f)
  f.textLayer:SetFrameLevel(f.bar:GetFrameLevel() + 5)
  f.text = C:Text(f.textLayer, 11, "CENTER")
  f.text:SetPoint("CENTER")
  f.text:SetDrawLayer("OVERLAY")
  f.points = {}
  f:Hide()
  return f
end

local COMBO_GAP = 0
-- Kept for older calls: the colour of the first combo slot.
function C:ComboColor()
  local bars = C:ActiveBars() or {}
  for i = 1, (C.MAX_BARS or 3) do
    local b = bars[i]
    if b and b.kind == "combo" then return C:BarColor(b) end
  end
  return C.ACCENT
end

local function LayoutCombo(holder, width, count, height, col)
  for _, p in ipairs(holder.points) do p:Hide() end
  if count <= 0 then return end
  -- Whole pixels only, otherwise a fractional rest shifts the plates. They sit
  -- edge to edge with the bar and with each other: no padding, no gap.
  local usable = width - (count - 1) * COMBO_GAP
  local each = math.max(2, math.floor(usable / count))
  local rest = usable - each * count
  for i = 1, count do
    local p = holder.points[i]
    if not p then
      p = CreateFrame("Frame", nil, holder)
      C:Flat(p, C.BACKDROP[1], C.BACKDROP[2], C.BACKDROP[3], 1)
      p.fill = p:CreateTexture(nil, "ARTWORK")
      p.fill:SetTexture(C:BarTexture())
      C.comboFills[#C.comboFills + 1] = p.fill
      p.fill:SetPoint("TOPLEFT", 1, -1)
      p.fill:SetPoint("BOTTOMRIGHT", -1, 1)
      holder.points[i] = p
    end
    p.litColor = col
    p.fill:SetVertexColor(col[1], col[2], col[3], 1)
    -- The plate was just repainted behind UpdateCombo's back: drop its cached
    -- state so the next update always re-colours it.
    p.jcdState = nil
    p:SetSize(each + (i == count and rest or 0), height or 15)
    p:ClearAllPoints()
    if i == 1 then
      p:SetPoint("LEFT", holder, "LEFT", 0, 0)
    else
      p:SetPoint("LEFT", holder.points[i - 1], "RIGHT", COMBO_GAP, 0)
    end
    p:Show()
  end
end



-- Rebuild --------------------------------------------------------------------
function C:Rebuild()
  if not anchor then return end
  -- Resizing or re-anchoring while the player is in combat can be blocked by
  -- the client, so the whole rebuild waits for the fight to end.
  if InCombatLockdown and InCombatLockdown() then
    C.rebuildAfterCombat = true
    return
  end
  local p = C:Profile()
  if not p then return end
  -- Cleared here and re-raised by AnchorPosition/DockUnitBar below if anything
  -- they need is still missing. Only the login settle pass reads them.
  C.anchorPending, C.dockPending = false, false

  -- The stored icon lists are the single source of truth: pack them and derive
  -- the counts on every rebuild so a deleted icon can never linger and a newly
  -- added one can never stay invisible because of a stale count.
  C:SyncSet(p)
  for i = 1, 4 do C:SyncRow(p.rows[i]) end
  for _, s in pairs(p.stances or {}) do C:SyncSet(s) end
  local set = C:ActiveSet() or p

  C:AnchorPosition()

  local size = p.iconSize or 40
  local mainList, mainN = KnownList(1, set.main, set.mainCount)
  local subList, subN = KnownList(2, set.sub, set.subCount)
  local mainW = BuildCDBar(main, mainList, mainN, size)
  BuildCDBar(sub, subList, subN, size)

  -- Does any cooldown icon react to auras? If not, UNIT_AURA can skip the
  -- cooldown repaint entirely.
  local auraDriven = false
  for k = 1, 4 do
    for _, e in ipairs(set[SET_KEYS[k]] or {}) do
      if (e.replaceEnabled and e.replaceTriggerID) or (e.glowAuraEnabled and GlowAuraActive(e)) or e.stacksEnabled then
        auraDriven = true
        break
      end
    end
    if auraDriven then break end
  end
  C.auraDrivenIcons = auraDriven

  local unitSize = p.unitIconSize or 35
  local upList, upN = KnownList(3, set.up, set.upCount)
  local downList, downN = KnownList(4, set.down, set.downCount)
  BuildUnitBar(upBar, upList, upN, unitSize, "left")
  BuildUnitBar(downBar, downList, downN, unitSize, "right")



  main:ClearAllPoints()
  main:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  sub:ClearAllPoints()
  sub:SetPoint("TOP", main, "BOTTOM", 0, -GAP)

  local barW = mainW
  if barW == 0 and subN > 0 then barW = subN * size + (subN - 1) * GAP end
  -- Nothing to hang off yet: fall back to the base width so the power bars,
  -- the combo bar and the castbar dock are visible the moment they are ticked.
  if barW == 0 then barW = BASE_WIDTH end


  -- Three universal slots, stacked bottom to top straight above the icon row.
  -- Every slot is either a fluid resource bar or a row of combo plates.
  local bars = C:ActiveBars() or {}
  local top = main
  for i = 1, C.MAX_BARS do
    local cfg = bars[i]
    local slot = slots[i]
    if cfg and cfg.enabled then
      local bh = C:BarHeight(cfg)
      -- Standalone resource bars keep their own width instead of matching the
      -- icon row; combo bars always follow the row.
      local w = barW
      if cfg.kind == "resource" and cfg.standalone then
        w = math.max(60, math.min(600, tonumber(cfg.width) or 250))
      end
      slot:SetSize(w, bh)
      slot:ClearAllPoints()
      slot:SetPoint("BOTTOM", top, "TOP", 0, GAP)
      slot.cfg = cfg
      slot.kind = cfg.kind
      if cfg.kind == "combo" then
        slot.bar:Hide()
        slot.text:SetText("")
        LayoutCombo(slot, w, math.max(1, math.min(20, tonumber(cfg.count) or 5)), bh, C:BarColor(cfg))
      else
        for _, plate in ipairs(slot.points) do plate:Hide() end
        slot.bar:Show()
        local info = C:PowerInfo(cfg.resource)
        if cfg.resource == "OTHER" then
          -- A custom resource keeps the profile colour so it can be told apart
          -- from the class resources.
          local col = C:BarColor(cfg)
          slot.bar:SetStatusBarColor(col[1], col[2], col[3])
          slot.powerKey = nil
        else
          slot.bar:SetStatusBarColor(info.color[1], info.color[2], info.color[3])
          slot.powerKey = info.key
        end
        -- The value always sits dead centre of the bar.
        local fontSize = math.max(7, math.min(13, bh - 4))
        slot.text:SetFont(C.font, fontSize, "OUTLINE")
        slot.text:ClearAllPoints()
        slot.text:SetPoint("CENTER", slot, "CENTER", 0, 0)
        slot.lastCur, slot.lastMax = nil, nil
      end
      slot:Show()
      top = slot
    else
      slot:Hide()
      slot.cfg = nil
      slot.powerKey = nil
    end
  end

  -- Aura rows anchor 60px above the top element, growing upwards. Their width
  -- is dynamic so layout happens in C:UpdateAuras().
  local asize = p.auraSize or 35
  -- The reminder row (4) carries its own size so it can read larger or smaller
  -- than the aura rows.
  local rsize = tonumber(p.remindSize) or asize
  for i = 1, 4 do
    local holder = rows[i]
    local isize = (i == 4) and rsize or asize
    EnsureIcons(holder, p.rows[i].count or 0, isize)
    -- A rebuild resizes the holder and its icons behind the layout cache's
    -- back, so the remembered row order is dropped here.
    holder.jcdLayoutSize = nil
    holder:ClearAllPoints()
    if i == 4 then
      -- Missing buff reminders live at the top of the screen, on their own.
      holder:SetPoint("TOP", UIParent, "TOP", 0, -(p.missingY or 120))
    elseif i == 1 then
      holder:SetPoint("BOTTOM", top, "TOP", 0, ROW_GAP)
    else
      holder:SetPoint("BOTTOM", rows[i - 1], "TOP", 0, GAP)
    end
    holder:SetSize(math.max(1, isize), isize)
    holder:Show()
  end

  if C.db.locked then anchor.mover:Hide() else anchor.mover:Show() end

  -- Talk back to JunkieUI: the unit frames hug this width while locked, and
  -- the player castbar can dock 1px above the topmost bar.
  if JunkieUI then
    -- Never let a host side error abort our own rebuild: the icons must always
    -- finish updating even if JunkieUI chokes on a docking call.
    if JunkieUI.NotifyCDWidth then pcall(JunkieUI.NotifyCDWidth, JunkieUI, barW) end
    if JunkieUI.DockPlayerCastbar then
      if p.castbarTop then
        -- Fixed height: the docked castbar is always 35px tall.
        pcall(JunkieUI.DockPlayerCastbar, JunkieUI, top, top:GetWidth(), 35)
      else
        pcall(JunkieUI.DockPlayerCastbar, JunkieUI, nil, 0)
      end
    end
  end


  C:UpdateCooldowns()
  C:UpdateAuras()
  C:UpdatePower()
  C:UpdateCombo()
  if UpdateRangeTicker then UpdateRangeTicker() end
end


-- Updates ---------------------------------------------------------------------
-- Spell alert (proc) state, mirroring what the action bars do. The client fires
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE with a spell id; IsSpellOverlayed is
-- used as a second source so a proc that started before login is caught too.
-- IsSpellOverlayed either exists and answers, or it does not: the pcall probe
-- is paid once for the session instead of twice per icon on every repaint.
local overlayAPI = nil   -- nil = untested, false = unusable, function = usable
local function IsAlerted(f, entry, name)
  if entry.kind == "item" or entry.kind == "trinket" then return false end
  if f.overlay then return true end
  if overlayAPI == nil then
    if type(IsSpellOverlayed) == "function" then
      local ok = pcall(IsSpellOverlayed, entry.id)
      overlayAPI = ok and IsSpellOverlayed or false
    else
      overlayAPI = false
    end
  end
  if overlayAPI then
    if overlayAPI(entry.id) then return true end
    if name and overlayAPI(name) then return true end
  end
  return false
end

-- Reused stand-in for a "replace this icon while an aura is up" swap: building
-- a fresh table here would allocate once per icon on every repaint.
local replaceScratch = { kind = "spell" }

-- Remembers which spell ids ever reported charges, so the pcall probe above
-- runs once per spell instead of once per repaint.
local chargeProbe = {}
local function ResetChargeProbe() for k in pairs(chargeProbe) do chargeProbe[k] = nil end end

-- Widget writes are expensive on 3.3.5 (each one dirties the frame and forces
-- a re-layout of the texture / font string). A repaint usually changes nothing
-- at all, so every frequent setter goes through these guards and only reaches
-- the client when the value actually moved.
local function SetIcon(f, tex)
  if f.jcdTex ~= tex then
    f.jcdTex = tex
    f.icon:SetTexture(tex)
  end
end

local function SetIconAlpha(f, a)
  if f.jcdAlpha ~= a then
    f.jcdAlpha = a
    f:SetAlpha(a)
  end
end

local function SetCountText(f, txt)
  if f.jcdCount ~= txt then
    f.jcdCount = txt
    f.count:SetText(txt)
  end
end

local function SetDesat(f, on)
  on = on and true or false
  if f.jcdDesat ~= on then
    f.jcdDesat = on
    f.icon:SetDesaturated(on)
  end
end

local function SetIconTint(f, r, g, b)
  if f.jcdTintR ~= r or f.jcdTintG ~= g or f.jcdTintB ~= b then
    f.jcdTintR, f.jcdTintG, f.jcdTintB = r, g, b
    f.icon:SetVertexColor(r, g, b)
  end
end

local function SetReverseSwipe(f, on)
  on = on and true or false
  if f.jcdReverse ~= on then
    f.jcdReverse = on
    f.cd:SetReverse(on)
  end
end

-- Cooldown swipes are the single most expensive thing on an icon: SetCooldown
-- restarts the animation and re-uploads the swipe every call. Repaints happen
-- several times per cast (and 4x/sec from the expiry ticker), so the same
-- start/duration pair is written once and skipped from then on.
local function SetCD(f, start, duration)
  if start and duration and duration > 0 then
    if f.jcdCDStart ~= start or f.jcdCDDur ~= duration then
      f.jcdCDStart, f.jcdCDDur = start, duration
      f.cd:SetCooldown(start, duration)
    end
    if not f.cd:IsShown() then f.cd:Show() end
  else
    f.jcdCDStart, f.jcdCDDur = nil, nil
    if f.cd:IsShown() then f.cd:Hide() end
  end
end




-- The cooldown glow can watch several aura IDs and, optionally, only fire once
-- one of them is stacked high enough. The first ID that satisfies the rule
-- wins, so the loop bails as early as possible.
local glowIDScratch = {}
GlowAuraActive = function(entry)
  if tonumber(entry.glowAuraID) then return true end
  for i = 2, C.MAX_AURA_IDS do
    if tonumber(entry[C.GLOW_AURA_ID_FIELDS[i]]) then return true end
  end
  return false
end

FindGlowAura = function(unit, filter, entry)
  if not FindAura then return false end
  local need = (entry.glowAuraStacksEnabled and math.max(1, tonumber(entry.glowAuraStacks) or 1)) or nil
  local ids = C:GlowAuraIDs(entry, glowIDScratch)
  for i = 1, #ids do
    local tex, count = FindAura(unit, filter, ids[i], true)
    if tex then
      if not need then return true end
      if (tonumber(count) or 0) >= need then return true end
    end
  end
  return false
end

local function UpdateCDIcon(f, profile)
  local entry = f.entry
  if not entry or not entry.id then
    SetIcon(f, nil)
    SetIconTint(f, 1, 1, 1)
    SetIconAlpha(f, 0.25)
    SetCD(f, nil, nil)
    SetTimer(f, nil, nil)
    SetCountText(f, "")
    f.jcdSpellName = nil
    C:SetGlow(f, nil, false)
    return
  end
  local shownEntry = entry
  if entry.replaceEnabled and entry.replaceID and entry.replaceTriggerID then
    local unit = entry.replaceUnit or "player"
    local filter = entry.replaceFilter == "debuff" and "HARMFUL" or "HELPFUL"
    if FindAura and FindAura(unit, filter, entry.replaceTriggerID, true) then
      replaceScratch.id = entry.replaceID
      shownEntry = replaceScratch
    end
  end
  local name, tex = EntryInfo(shownEntry)
  -- Cached for the range sweep, which would otherwise resolve the name again
  -- for every icon five times a second.
  f.jcdSpellName = (shownEntry.kind ~= "item" and shownEntry.kind ~= "trinket") and name or nil
  SetIcon(f, tex)
  SetIconAlpha(f, 1)
  SetReverseSwipe(f, false)

  local start, duration, enable
  local usable, nomana = true, false
  local inRange = true
  local stacks, charges, maxCharges, chargeStart, chargeDuration
  local chargeKey, hasCharges
  if shownEntry.kind == "trinket" then
    local slot = tonumber(shownEntry.id) or 13
    start, duration, enable = GetInventoryItemCooldown("player", slot)
    SetCountText(f, "")
  elseif shownEntry.kind == "item" then
    start, duration, enable = GetItemCooldown(shownEntry.id)
    local cnt = GetItemCount(shownEntry.id)
    SetCountText(f, (cnt and cnt > 1) and cnt or "")
  else
    if name then
      start, duration, enable = GetSpellCooldown(name)
      -- Spells that carry stacks or charges frequently report nothing under
      -- their name while the id still answers with the real recharge, so both
      -- sources are read and the longer cooldown wins.
      local s2, d2, e2 = GetSpellCooldown(shownEntry.id)
      if d2 and d2 > (duration or 0) then start, duration, enable = s2, d2, e2 end

      -- A spell either has charges or it never will: the pcall probe is only
      -- paid once per spell instead of on every repaint.
      chargeKey = tonumber(shownEntry.id) or shownEntry.id
      hasCharges = chargeProbe[chargeKey]

      -- Prefer a native/backported charge API when the client exposes one.
      -- It is pcall-guarded because stock 3.3.5a has no GetSpellCharges.
      if hasCharges ~= false and type(GetSpellCharges) == "function" then
        local ok, c, mc, cs, cd = pcall(GetSpellCharges, shownEntry.id)
        if (not ok or c == nil) and name then ok, c, mc, cs, cd = pcall(GetSpellCharges, name) end
        if ok and c ~= nil and mc and mc > 1 then
          charges, maxCharges = c, mc
          chargeStart, chargeDuration = cs, cd
          chargeProbe[chargeKey] = true
        else
          chargeProbe[chargeKey] = false
        end
      end

      -- Several Wrath custom clients expose recharge/count only through the
      -- action slot (the stock action button in the UI still knows the truth).
      local actionSlot = actionSlotsByID[tonumber(shownEntry.id) or shownEntry.id]
        or actionSlotsByName[name]
      if actionSlot then
        local aStart, aDuration, aEnable = GetActionCooldown(actionSlot)
        if aDuration and aDuration > (duration or 0) then
          start, duration, enable = aStart, aDuration, aEnable
        end
        -- Charges are read even without the per-icon stacks toggle so that a
        -- spell with several charges always shows its count.
        if charges == nil then
          local actionCount = GetActionCount(actionSlot)
          if actionCount and actionCount > 0 then charges = actionCount end
        end
      end
      usable, nomana = IsUsableSpell(name)
      -- Range is owned by the 5Hz sweep below. Re-querying it here would run
      -- IsSpellInRange once per icon on every repaint for no extra accuracy.
      if UnitExists("target") then
        if f.jcdInRange == false then inRange = false end
      end
    end
    -- Stacks / charges are read from an aura: the tracked spell itself by
    -- default, or a separate aura id when the charges live on another buff.
    if entry.stacksEnabled and FindAura then
      local sid = tonumber(entry.stackAuraID) or shownEntry.id
      local _, cnt = FindAura("player", "HELPFUL", sid)
      if not cnt then
        local _, cnt2 = FindAura("player", "HARMFUL", sid)
        cnt = cnt2
      end
      stacks = cnt or 0
    end
    -- With the per-icon charge toggle on, the number is always printed - even
    -- at 0 or 1 charge. Otherwise it only shows once there is more than one.
    local shownCount
    if entry.chargeText then
      shownCount = charges or (entry.stacksEnabled and stacks) or 0
    elseif charges ~= nil and charges > 1 then
      shownCount = charges
    elseif entry.stacksEnabled and stacks and stacks > 0 then
      shownCount = stacks
    end
    SetCountText(f, shownCount and tostring(shownCount) or "")
  end

  -- The global cooldown is hidden by default: without this every icon flashes
  -- a 1.5s swipe on every cast.
  local p = profile or C:Profile()
  local minDur = (p and p.showGCD) and 0 or 1.5
  -- Charge recharge has its own timer. Keep the swipe running while any charge
  -- is recharging, but only desaturate once no usable charge remains.
  local recharge = charges ~= nil and chargeStart and chargeDuration and chargeDuration > minDur
    and (not maxCharges or charges < maxCharges)
  if recharge then start, duration = chargeStart, chargeDuration end
  local onCD = (start and duration and duration > minDur and (enable == nil or enable == 1 or charges ~= nil)) and true or false
  if onCD then
    SetCD(f, start, duration)
    SetTimer(f, start, duration)
  else
    SetCD(f, nil, nil)
    SetTimer(f, nil, nil)
  end

  -- Out of power reads as unusable too: the icon greys out exactly like the
  -- action bars do when a spell cannot be paid for. With charges tracked the
  -- icon only greys out once the cooldown runs AND no charge is left.
  local available = (charges ~= nil and charges > 0) or (stacks and stacks > 0)
  local cdDim = onCD and not available
  local dim = cdDim or (not usable) or nomana
  SetDesat(f, dim)

  SetIconAlpha(f, 1)
  -- Out of range reads as red, exactly like the action bars do.
  f.jcdInRange = inRange
  if not inRange then
    SetIconTint(f, 1, 0.25, 0.25)
  else
    SetIconTint(f, 1, 1, 1)
  end

  -- Cooldown icons mirror the client's own spell alert engine, and can also
  -- glow while a chosen aura is up on the player, the target or the pet.
  local kind, glow = nil, false
  -- The replacement condition can carry its own glow.
  if shownEntry ~= entry and entry.replaceGlow and entry.replaceGlow ~= "none" then
    glow, kind = true, entry.replaceGlow
  end
  if entry.glowAuraEnabled and GlowAuraActive(entry) then
    local unit = entry.glowAuraUnit or "player"
    local filter = entry.glowAuraFilter == "debuff" and "HARMFUL" or "HELPFUL"
    local found = FindGlowAura(unit, filter, entry)
    -- The sound only fires on the edge: the moment the aura appears.
    if found and not f.auraSoundOn then C:PlayAlert(entry.glowAuraSound) end
    f.auraSoundOn = found
    if found and not glow then
      glow, kind = true, (entry.glowAuraType ~= "none" and entry.glowAuraType) or "pixel"
    end
  else
    f.auraSoundOn = nil
  end
  if not glow and IsAlerted(f, shownEntry, name) then
    local alertKind = entry.alertGlow or "proc"
    if alertKind ~= "none" then glow, kind = true, alertKind end
  end
  C:SetGlow(f, kind, glow)
end




-- The 5Hz poll only has to answer one question: did this icon move in or out
-- of range? Repainting the whole icon every tick is wasted work, so we compare
-- the range flag first and only rebuild when it flipped.
local function RangeSweep(list)
  for i = 1, #list do
    local f = list[i]
    local name = f.jcdSpellName
    if name and f:IsShown() then
      local inRange = IsSpellInRange(name, "target") ~= 0
      if inRange ~= f.jcdInRange then
        f.jcdInRange = inRange
        -- Range only ever drives the icon tint; rebuilding the whole icon here
        -- would re-query every cooldown API for nothing.
        if inRange then
          SetIconTint(f, 1, 1, 1)
        else
          SetIconTint(f, 1, 0.25, 0.25)
        end
      end
    end
  end
end

function C:UpdateCooldowns()
  local profile = C:Profile()
  for l = 1, #iconLists do
    local list = iconLists[l]
    for i = 1, #list do
      local f = list[i]
      if f:IsShown() then UpdateCDIcon(f, profile) end
    end
  end
end

-- The spell alert events and the client's own ActionButton overlay hooks all
-- ask the same question: which of our icons carry this spell?
local function ApplyOverlay(id, on)
  id = tonumber(id) or id
  if not id then return end
  local alertName = GetSpellInfo(id)
  local profile = C:Profile()
  for l = 1, #iconLists do
    local list = iconLists[l]
    for i = 1, #list do
      local f = list[i]
      local e = f.entry
      if e and e.kind ~= "item" and e.kind ~= "trinket" and e.id then
        -- Match on id, and on name too: a ranked spell carries a different id
        -- than the alert the client sends.
        local same = (tonumber(e.id) == tonumber(id)) or (alertName and GetSpellInfo(e.id) == alertName)
        if same then
          f.overlay = on or nil
          UpdateCDIcon(f, profile)
        end
      end
    end
  end
end

-- Range check: 5 times a second, and only while there is both a target and at
-- least one cooldown icon to colour. Parked the rest of the time, so an idle
-- session pays nothing at all for it.
local rangeTicker = CreateFrame("Frame")
rangeTicker:Hide()
rangeTicker.elapsed = 0
rangeTicker:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < 0.2 then return end
  self.elapsed = 0
  if not UnitExists("target") then self:Hide(); return end
  for l = 1, #iconLists do RangeSweep(iconLists[l]) end
end)

UpdateRangeTicker = function()
  local n = 0
  for l = 1, #iconLists do n = n + #iconLists[l] end
  if n > 0 and UnitExists("target") then rangeTicker:Show() else rangeTicker:Hide() end
end

-- Aura lookup by exact spell id.
local function ScanAuraFilter(unit, filter)
  local byID = auraCache[unit]
  local byName = auraNameCache[unit]
  local recordsByFilter = auraRecords[unit]
  local mineByID = auraMineCache[unit]
  local mineByName = auraMineNameCache[unit]
  if not byID or not byName or not recordsByFilter then return end
  local idMap = byID[filter]
  local nameMap = byName[filter]
  local records = recordsByFilter[filter]
  if not idMap then idMap = {}; byID[filter] = idMap end
  if not nameMap then nameMap = {}; byName[filter] = nameMap end
  if not records then records = {}; recordsByFilter[filter] = records end
  local mineIdMap = mineByID[filter]
  local mineNameMap = mineByName[filter]
  if not mineIdMap then mineIdMap = {}; mineByID[filter] = mineIdMap end
  if not mineNameMap then mineNameMap = {}; mineByName[filter] = mineNameMap end
  for key in pairs(idMap) do idMap[key] = nil end
  for key in pairs(nameMap) do nameMap[key] = nil end
  for key in pairs(mineIdMap) do mineIdMap[key] = nil end
  for key in pairs(mineNameMap) do mineNameMap[key] = nil end
  for i = 1, 40 do
    local name, _, tex, count, _, duration, expires, caster, _, _, spellID = UnitAura(unit, i, filter)
    if not name then break end
    local data = records[i]
    if not data then data = {}; records[i] = data end
    data[1], data[2], data[3], data[4] = tex, count, duration, expires
    if spellID then idMap[spellID] = data; auraIDsAvailable = true end
    nameMap[name] = data
    -- Mine-only maps: filled from the same pass, so the "only own" option adds
    -- no extra UnitAura calls at all.
    if caster == "player" or caster == "pet" or caster == "vehicle" then
      if spellID then mineIdMap[spellID] = data end
      mineNameMap[name] = data
    end
  end
end

local function RefreshAuraCache()
  for i = 1, #AURA_UNITS do
    local unit = AURA_UNITS[i]
    ScanAuraFilter(unit, "HELPFUL")
    ScanAuraFilter(unit, "HARMFUL")
  end
end

-- exact = match the aura ID only. Without it the lookup also accepts any aura
-- sharing the spell's name, which makes look-alike buffs (other ranks, other
-- players' versions) trigger the icon. The name fallback is only kept as a
-- last resort for clients that never report a spellID at all.
-- onlyMine = only auras the player applied are considered.
FindAura = function(unit, filter, id, exact, onlyMine)
  local byID = onlyMine and auraMineCache[unit] or auraCache[unit]
  local byName = onlyMine and auraMineNameCache[unit] or auraNameCache[unit]
  if not byID or not byName then return end
  local data = byID[filter] and byID[filter][tonumber(id) or id]
  if not data and not (exact and auraIDsAvailable) then
    local wanted = GetSpellInfo(id)
    data = wanted and byName[filter] and byName[filter][wanted]
  end
  if data then return data[1], data[2], data[3], data[4] end
end


-- One icon can watch several aura IDs: the first match wins.
local idScratch = {}
local function FindAnyAura(unit, filter, entry)
  local ids = C:AuraIDs(entry, idScratch)
  local onlyMine = entry and entry.onlyMine and true or false
  for i = 1, #ids do
    local tex, count, duration, expires = FindAura(unit, filter, ids[i], nil, onlyMine)
    if tex then return tex, count, duration, expires end
  end
end
C.FindAnyAura = function(_, unit, filter, entry) return FindAnyAura(unit, filter, entry) end


function C:SetPreview(on)
  C.preview = on and true or false
  C:UpdateAuras()
end

-- Source is stored per aura ("my" buffs by default), not per row.
local function AuraUnitFilter(entry)
  local key = entry and entry.unit or "my"
  -- Old profiles stored a combined key; new ones store unit + filter apart.
  if key == "my" then key = "player" end
  if key == "target" and not (entry and entry.filter) then return "target", "HARMFUL" end
  if key == "pet" and not (entry and entry.filter) then return "pet", "HELPFUL" end
  local unit = (key == "target" or key == "pet") and key or "player"
  local filter = (entry and entry.filter == "debuff") and "HARMFUL" or "HELPFUL"
  return unit, filter
end
C.AuraUnitFilter = function(_, entry) return AuraUnitFilter(entry) end

-- onlyUnit = only that unit's auras are rescanned, every other icon keeps the
-- value it already had. noScan = redraw from the cache without touching the
-- aura API at all (used by the expiry ticker).
function C:UpdateAuras(onlyUnit, noScan)
  if not noScan then
    if onlyUnit then
      ScanAuraFilter(onlyUnit, "HELPFUL")
      ScanAuraFilter(onlyUnit, "HARMFUL")
    else
      RefreshAuraCache()
    end
  end
  local p = C:Profile()
  local auraSize = p.auraSize or 35
  local remindSize = tonumber(p.remindSize) or auraSize
  local now = GetTime()
  local expiryWatch = false
  for f in pairs(expiryWatchers) do expiryWatchers[f] = nil end
  for r = 1, 4 do
    local size = (r == 4) and remindSize or auraSize
    local row = p.rows[r]
    local holder = rows[r]
    -- Reused scratch list: UNIT_AURA can fire several times a second, so this
    -- avoids a fresh table per row on every single aura tick.
    local shownList = auraScratch[r]
    for i = #shownList, 1, -1 do shownList[i] = nil end
    for i = 1, (row.count or 0) do
      local f = holder.icons[i]
      if f then
        local entry = row.icons[i]
        f.entry = entry
        local tex, count, duration, expires
        if entry and entry.id then
          local unit, filter = AuraUnitFilter(entry)
          if not onlyUnit or unit == onlyUnit then
            tex, count, duration, expires = FindAnyAura(unit, filter, entry)
          else
            tex, count, duration, expires = f.jcdAuraTex, f.jcdAuraCount,
              f.jcdAuraDuration, f.jcdAuraExpires
          end
        end
        f.jcdAuraTex, f.jcdAuraCount = tex, count
        f.jcdAuraDuration, f.jcdAuraExpires = duration, expires

        -- "Missing" slots invert the whole test: the icon is only drawn while
        -- the aura is absent, either in colour or desaturated. Row 4 is the
        -- dedicated reminder row, so every icon in it works that way.
        local missingMode = entry and (entry.mode == "missing" or r == 4)
        if r == 4 and entry and not C:RemindNow(entry) then
          tex = nil
          missingMode = false
        end
        if missingMode then
          local warnAt = (entry and entry.expireWarn) and (tonumber(entry.expireWarnAt) or 60) or nil
          local remaining = (expires and expires > 0) and (expires - now) or nil
          if tex and warnAt then
            expiryWatch = true
            expiryWatchers[f] = warnAt
            f.jcdWarned = (remaining and remaining <= warnAt) and true or false
            if remaining and remaining <= warnAt then
              -- Still up, but about to fall off: bring the icon back early and
              -- let its own swipe count the last seconds down.
              local _, itex = EntryInfo(entry)
              tex = itex or tex
              count = nil
            else
              tex = nil
            end
          elseif tex then
            tex = nil
          else
            local _, itex = EntryInfo(entry)
            tex = itex
            count, duration, expires = nil, nil, nil
          end
        end

        if tex then
          SetIcon(f, tex)
          SetDesat(f, missingMode and entry.missingStyle == "grayscale")
          SetIconAlpha(f, 1)
          SetCountText(f, (count and count > 1) and count or "")
          if duration and duration > 0 and expires then
            SetReverseSwipe(f, true)   -- uptime swipe runs inverted
            SetCD(f, expires - duration, duration)
            SetTimer(f, expires - duration, duration)
          else
            SetCD(f, nil, nil)
            SetTimer(f, nil, nil)
          end
          -- Without the stack switch the aura glows as soon as it is up: most
          -- auras report no stack count at all, so 0 has to pass here.
          local threshold = (entry.glowStacksEnabled and tonumber(entry.glowStacks)) or 0
          local glow = entry.glow and entry.glow ~= "none" and (count or 0) >= threshold
          C:SetGlow(f, entry.glow, glow)
          -- Sound on the rising edge only, never on every aura tick.
          if not f.soundOn then
            if not C.preview then C:PlayAlert(entry.sound) end
            f.soundOn = true
          end

          shownList[#shownList + 1] = f
        elseif C.preview then
          -- Menu preview: show the configured icon (or a + placeholder) dimmed.
          local _, ptex = EntryInfo(entry)
          SetIcon(f, ptex)
          SetDesat(f, true)
          SetIconAlpha(f, 0.45)
          SetCountText(f, "")
          SetCD(f, nil, nil)
          SetTimer(f, nil, nil)
          C:SetGlow(f, nil, false)
          shownList[#shownList + 1] = f
        else
          f:Hide()
          SetCD(f, nil, nil)
          SetTimer(f, nil, nil)
          SetCountText(f, "")
          C:SetGlow(f, nil, false)
          f.soundOn = nil
        end
      end
    end
    -- Dynamic layout: the row is only as wide as the visible icons and stays
    -- centred. Re-anchoring is the single most expensive thing in this pass
    -- (every SetPoint dirties the frame tree), and the visible set is unchanged
    -- on the vast majority of ticks, so the previous order is remembered and
    -- the anchors are only rewritten when it actually moved.
    local n = #shownList
    local last = holder.jcdLayout
    if not last then last = {}; holder.jcdLayout = last end
    local changed = (holder.jcdLayoutSize ~= size) or (#last ~= n)
    if not changed then
      for i = 1, n do
        if last[i] ~= shownList[i] then changed = true; break end
      end
    end
    if changed then
      holder.jcdLayoutSize = size
      for i = #last, 1, -1 do last[i] = nil end
      if n == 0 then
        holder:SetSize(1, size)
      else
        holder:SetSize(n * size + (n - 1) * GAP, size)
        for i = 1, n do
          local f = shownList[i]
          last[i] = f
          f:ClearAllPoints()
          if i == 1 then
            f:SetPoint("LEFT", holder, "LEFT", 0, 0)
          else
            f:SetPoint("LEFT", shownList[i - 1], "RIGHT", GAP, 0)
          end
        end
      end
    end
    for i = 1, n do
      local f = shownList[i]
      if not f:IsShown() then f:Show() end
    end
  end
  if expiryWatch then expiryDriver:Show() else expiryDriver:Hide() end
end

-- Power is fully event driven (UNIT_MANA / UNIT_RAGE / ... ), the same cheap
-- pattern the JunkieUI castbars use: no idle loop at all.


local function SmoothUpdate(self, elapsed)
  local cur = self.bar:GetValue() or 0
  local target = self.smoothTarget or cur
  local diff = target - cur
  if math.abs(diff) < 0.6 then
    self.bar:SetValue(target)
    self:SetScript("OnUpdate", nil)
    return
  end
  -- Frame rate independent glide, roughly 12x per second towards the value.
  self.bar:SetValue(cur + diff * math.min(elapsed * 12, 1))
end

local function SetPowerValue(bar, value, smooth)
  if smooth then
    bar.smoothTarget = value
    if not bar:GetScript("OnUpdate") then bar:SetScript("OnUpdate", SmoothUpdate) end
  else
    bar:SetScript("OnUpdate", nil)
    bar.bar:SetValue(value)
  end
end

-- Stacks of any aura, read for the "Other resources" mode.
local function AuraStacks(cfg)
  if not (FindAura and cfg and cfg.auraID) then return 0 end
  local unit = "player"
  local _, count = FindAura(unit, cfg.auraType == "HARMFUL" and "HARMFUL" or "HELPFUL", cfg.auraID, true)
  return count or 0
end

function C:UpdatePower()
  for i = 1, C.MAX_BARS do
    local slot = slots[i]
    local cfg = slot and slot.cfg
    if slot and slot:IsShown() and cfg and cfg.kind == "resource" then
      local cur, max, txt = 0, 0, ""
      if cfg.resource == "OTHER" then
        cur = AuraStacks(cfg)
        max = math.max(1, tonumber(cfg.maxStacks) or 100)
        if cur > max then cur = max end
        txt = tostring(cur)
      else
        local info = C:PowerInfo(slot.powerKey or cfg.resource)
        cur = UnitPower("player", info.index) or 0
        max = UnitPowerMax("player", info.index) or 0
        if max > 0 then
          if info.key == "MANA" and cfg.showPercent then
            txt = math.floor(cur / max * 100 + 0.5) .. "%"
          else
            txt = tostring(cur)
          end
        end
      end
      if slot.lastCur ~= cur or slot.lastMax ~= max then
        slot.lastCur, slot.lastMax = cur, max
        slot.bar:SetMinMaxValues(0, max > 0 and max or 1)
        SetPowerValue(slot, cur, cfg.smooth and true or false)
        slot.text:SetText(txt)
      end
    end
  end
end

-- Recharge sweep: only alive while a charge is actually filling up.
local chargeTicker = CreateFrame("Frame")
chargeTicker:Hide()
chargeTicker:SetScript("OnUpdate", function(self, e)
  self.t = (self.t or 0) + e
  if self.t < 0.1 then return end
  self.t = 0
  C:UpdateCombo()
end)

-- Charge mode: every point is one charge of a single spell, and the point
-- after the last full one fills up with the recharge of the next charge.
local function SpellCharges(id)
  if not id then return nil end
  local name = GetSpellInfo(id)
  local charges, maxCharges, start, duration
  if type(GetSpellCharges) == "function" then
    local ok, c, mc, cs, cd = pcall(GetSpellCharges, id)
    if (not ok or c == nil) and name then ok, c, mc, cs, cd = pcall(GetSpellCharges, name) end
    if ok and c ~= nil then charges, maxCharges, start, duration = c, mc, cs, cd end
  end
  if charges == nil then
    -- Custom 3.3.5 clients only answer through the action slot.
    local slot = actionSlotsByID[tonumber(id) or id] or (name and actionSlotsByName[name])
    if slot then
      charges = GetActionCount(slot)
      start, duration = GetActionCooldown(slot)
    end
  end
  if charges == nil and name then
    local cs, cd = GetSpellCooldown(name)
    charges = (cd or 0) > 1.5 and 0 or 1
    start, duration = cs, cd
  end
  return charges or 0, maxCharges, start, duration
end

local function UpdateComboSlot(slot)
  local cp = slot.cfg
  if not cp then return end
  local value, partial = 0, 0
  if cp.useCharges then
    local charges, _, start, duration = SpellCharges(cp.chargeSpellID)
    value = charges or 0
    if start and duration and duration > 1.5 and start + duration > GetTime() then
      partial = 1 - ((start + duration - GetTime()) / duration)
      if partial < 0 then partial = 0 elseif partial > 1 then partial = 1 end
      chargeTicker:Show()
    end
  elseif cp.spellID then
    -- "Read on target" moves the stack lookup to the current target.
    local unit = cp.onTarget and "target" or "player"
    local filter = cp.onTarget and "HARMFUL" or "HELPFUL"
    local _, count = FindAura(unit, filter, cp.spellID)
    if not count and cp.onTarget then
      local _, other = FindAura(unit, "HELPFUL", cp.spellID)
      count = other
    end
    value = count or 0
  else
    value = GetComboPoints("player", "target") or 0
  end
  local col = C:BarColor(cp)
  for i, box in ipairs(slot.points) do
    if box:IsShown() then
      -- Empty points read as the same dark plate the resource bars sit on.
      local plateCol = box.litColor or col
      local state
      if i <= value then
        state = "full"
      elseif cp.useCharges and i == value + 1 and partial > 0 then
        state = "grow"
      else
        state = "empty"
      end
      -- Re-anchoring the fill is the expensive part, so a plate only moves and
      -- re-colours when its state actually changed.
      if state == "grow" then
        -- The growing point: the plate fills from the left as it recharges.
        if box.jcdState ~= "grow" then
          box.fill:ClearAllPoints()
          box.fill:SetPoint("TOPLEFT", 1, -1)
          box.fill:SetPoint("BOTTOMLEFT", 1, 1)
          box.fill:SetVertexColor(plateCol[1] * 0.8, plateCol[2] * 0.8, plateCol[3] * 0.8, 1)
        end
        box.fill:SetWidth(math.max(1, (box:GetWidth() - 2) * partial))
      elseif box.jcdState ~= state then
        box.fill:ClearAllPoints()
        box.fill:SetPoint("TOPLEFT", 1, -1)
        box.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        if state == "full" then
          box.fill:SetVertexColor(plateCol[1], plateCol[2], plateCol[3], 1)
        else
          box.fill:SetVertexColor(C.BACKDROP[1], C.BACKDROP[2], C.BACKDROP[3], 1)
        end
      end
      box.jcdState = state
    end
  end
end

function C:UpdateCombo()
  local charging = false
  for i = 1, C.MAX_BARS do
    local slot = slots[i]
    if slot and slot:IsShown() and slot.cfg and slot.cfg.kind == "combo" then
      UpdateComboSlot(slot)
      if slot.cfg.useCharges then charging = true end
    end
  end
  -- The recharge sweep only runs while a charge bar is actually on screen.
  if not charging then chargeTicker:Hide() end
end


-- Reminder row: each icon says when it may nag (always, in a party, in a raid).
function C:RemindNow(entry)
  local when = entry and entry.remind or "always"
  if when == "party" then
    return (GetNumPartyMembers() or 0) > 0 or (GetNumRaidMembers() or 0) > 0
  elseif when == "raid" then
    return (GetNumRaidMembers() or 0) > 0
  end
  return true
end

-- Event driver -----------------------------------------------------------------
C:AddModule(function()
  BuildAnchor()

  main = CreateFrame("Frame", "JunkieCDMainBar", UIParent)
  main.icons = {}
  sub = CreateFrame("Frame", "JunkieCDSubBar", UIParent)
  sub.icons = {}
  upBar = CreateFrame("Frame", "JunkieCDPlayerUpperBar", UIParent)
  upBar.icons = {}
  downBar = CreateFrame("Frame", "JunkieCDPlayerLowerBar", UIParent)
  downBar.icons = {}
  -- One list of the four icon arrays, walked by every per-icon pass.
  iconLists[1], iconLists[2] = main.icons, sub.icons
  iconLists[3], iconLists[4] = upBar.icons, downBar.icons

  slots = {}
  for i = 1, C.MAX_BARS do slots[i] = BuildSlot(UIParent) end

  rows = {}
  for i = 1, 4 do
    local r = CreateFrame("Frame", "JunkieCDAuraRow" .. i, UIParent)
    r.icons = {}
    -- Only the reminder row answers the mouse, so nothing else can eat clicks.
    r.tooltips = (i == 4)
    rows[i] = r
  end
  anchor.mover:SetMovable(true)
  anchor.mover:EnableMouse(true)
  anchor.mover:RegisterForDrag("LeftButton")
  anchor.mover:SetScript("OnDragStart", function(self)
    self:SetMovable(true)
    self:StartMoving()
  end)
  anchor.mover:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p = C:Profile()
    local pf = _G["JunkiePlayerFrame"]
    if pf then
      p.y = self:GetTop() - pf:GetTop()
    else
      p.y = select(2, self:GetCenter()) - UIParent:GetHeight() / 2 + 180
    end
    self:ClearAllPoints()
    self:SetAllPoints(anchor)
    C:Rebuild()
  end)

  driver = CreateFrame("Frame")
  driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  driver:RegisterEvent("SPELL_UPDATE_USABLE")
  driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
  driver:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
  driver:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  driver:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
  driver:RegisterEvent("UNIT_AURA")
  driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  driver:RegisterEvent("UNIT_PET")
  driver:RegisterEvent("UNIT_COMBO_POINTS")
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  pcall(driver.RegisterEvent, driver, "PLAYER_TALENT_UPDATE")
  driver:RegisterEvent("CHARACTER_POINTS_CHANGED")
  driver:RegisterEvent("LEARNED_SPELL_IN_TAB")
  pcall(driver.RegisterEvent, driver, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  pcall(driver.RegisterEvent, driver, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  -- Power: event driven only.
  driver:RegisterEvent("UNIT_MANA")
  driver:RegisterEvent("UNIT_MAXMANA")
  driver:RegisterEvent("UNIT_RAGE")
  driver:RegisterEvent("UNIT_MAXRAGE")
  driver:RegisterEvent("UNIT_ENERGY")
  driver:RegisterEvent("UNIT_MAXENERGY")
  driver:RegisterEvent("UNIT_FOCUS")
  driver:RegisterEvent("UNIT_MAXFOCUS")
  driver:RegisterEvent("UNIT_RUNIC_POWER")
  driver:RegisterEvent("UNIT_MAXRUNIC_POWER")
  driver:RegisterEvent("UNIT_DISPLAYPOWER")

  local POWER_EVENTS = {
    UNIT_MANA = true, UNIT_MAXMANA = true, UNIT_RAGE = true, UNIT_MAXRAGE = true,
    UNIT_ENERGY = true, UNIT_MAXENERGY = true, UNIT_FOCUS = true, UNIT_MAXFOCUS = true,
    UNIT_RUNIC_POWER = true, UNIT_MAXRUNIC_POWER = true, UNIT_DISPLAYPOWER = true,
  }

  RefreshActionSlots()

  -- One repaint path for both aura ticks and target swaps.
  -- onlyUnit: only that unit's auras are rescanned, and the cooldown icons are
  -- only repainted when at least one of them actually watches an aura.
  -- nil: a full rescan and an immediate cooldown repaint (target/pet changed,
  -- so range, usability and aura swaps can all differ at once).
  local function Repaint(onlyUnit)
    C:UpdateAuras(onlyUnit)
    if onlyUnit then
      if C.auraDrivenIcons then QueueCooldownUpdate() end
    else
      C:UpdateCooldowns()
    end
    C:UpdateCombo()
    -- A custom resource bar can read aura stacks, so it follows too.
    C:UpdatePower()
  end

  -- UNIT_AURA arrives in bursts: every HoT tick, every stack change and every
  -- proc on player, target and pet fires one. Repainting synchronously means
  -- dozens of full passes inside a single frame in combat, so the units that
  -- went dirty are collected and drawn once on the next frame instead.
  local auraDirty = {}
  local auraQueue = CreateFrame("Frame")
  auraQueue:Hide()
  auraQueue:SetScript("OnUpdate", function(self)
    self:Hide()
    local units, n = nil, 0
    for unit in pairs(auraDirty) do
      auraDirty[unit] = nil
      n = n + 1
      units = unit
    end
    if n == 0 then return end
    -- One dirty unit keeps the cheap single-unit path; several at once are
    -- collapsed into the same full pass the target swap already uses.
    if n == 1 then Repaint(units) else Repaint(nil) end
  end)
  local function QueueAuraRepaint(unit)
    auraDirty[unit] = true
    auraQueue:Show()
  end



  driver:SetScript("OnEvent", function(_, event, unit)
    if POWER_EVENTS[event] then
      if unit == "player" then C:UpdatePower() end
      return
    end
    if event == "ACTIONBAR_SLOT_CHANGED" then
      -- arg1 is the slot that changed; only that one is re-read.
      QueueActionSlotScan(unit)
      return
    end
    if event == "ACTIONBAR_PAGE_CHANGED" then
      QueueActionSlotScan()
      return
    end
    if event == "UNIT_AURA" then
      if unit == "player" or unit == "target" or unit == "pet" then
        QueueAuraRepaint(unit)
      end
      return
    end
    -- UNIT_PET fires for every pet in the raid. Only our own pet may trigger
    -- a full aura + cooldown repaint; 24 other hunters/warlocks must not.
    if event == "UNIT_PET" and unit ~= "player" and unit ~= "pet" then return end
    if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_PET" then
      Repaint(nil)
      -- A target appearing or vanishing is what wakes or parks the range sweep.
      UpdateRangeTicker()
      return
    end
    if event == "UNIT_COMBO_POINTS" then
      C:UpdateCombo()
      return
    end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
      or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
      ApplyOverlay(unit, event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
      return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TALENT_UPDATE"
      or event == "CHARACTER_POINTS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
      -- Talents and new ranks can turn a chargeless spell into one with
      -- charges, so the memo is dropped whenever the spellbook changes.
      ResetChargeProbe()
      C:Rebuild()
      return
    end
    if unit and unit ~= "player" then return end
    QueueCooldownUpdate()
  end)

  -- Many 3.3.5 clients expose the action-button alert through these helpers
  -- without firing the later overlay events. Hook the exact client path too.
  local function HookOverlay(name, on)
    if type(_G[name]) ~= "function" then return end
    hooksecurefunc(name, function(button)
      local action = button and button.action
      local kind, id = action and GetActionInfo(action)
      if kind ~= "spell" or not id then return end
      ApplyOverlay(id, on)
    end)
  end
  HookOverlay("ActionButton_ShowOverlayGlow", true)
  HookOverlay("ActionButton_HideOverlayGlow", false)

  UpdateRangeTicker()

end)
