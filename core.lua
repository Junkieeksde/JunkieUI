-- Junkie CD - cooldown manager
-- Core: namespace, profiles, shared helpers.
-- Designed to be folded into JunkieUI later: everything lives on the JunkieCD
-- table and never touches JunkieUI's own saved variables.

local ADDON = ...

JunkieCD = CreateFrame("Frame", "JunkieCDFrame", UIParent)
local C = JunkieCD

C.version = "2.5.1"
C.modules = {}

-- Shared JunkieUI palette ---------------------------------------------------
C.ACCENT = { 0.871, 0.447, 0.188 }
C.BG     = { 0.055, 0.055, 0.055 }
C.BOX    = { 0.09, 0.09, 0.09 }
C.TXT    = { 0.86, 0.84, 0.78 }
C.DIM    = { 0.55, 0.53, 0.48 }
C.BACKDROP = { 0.102, 0.102, 0.102 }

C.MAX_ICONS = 10
C.MAX_ROW_ICONS = 12
C.MAX_AURA_IDS = 9          -- one icon can watch up to nine aura IDs

-- Alert sounds shipped with the addon --------------------------------------
local SOUND_PATH = "Interface\\AddOns\\JunkieCD\\media\\"
C.SOUNDS = {
  { key = "none",     name = "No sound" },
  { key = "pling1",   name = "Pling 1 (bright)" },
  { key = "pling2",   name = "Pling 2 (double)" },
  { key = "pling3",   name = "Pling 3 (chime)" },
  { key = "swoosh1",  name = "Swoosh (short)" },
  { key = "swoosh2",  name = "Swoosh (long)" },
  { key = "gong",     name = "Gong" },
  { key = "gonggong", name = "Gong gong" },
}

function C:PlayAlert(key)
  if not key or key == "none" then return end
  local file = SOUND_PATH .. key .. ".wav"
  if type(PlaySoundFile) ~= "function" then return end
  -- Later 3.3.5 clients accept the channel argument; older custom clients only
  -- accept the original one-argument form. Prefer Master, then fall back.
  local ok = pcall(PlaySoundFile, file, "Master")
  if not ok then pcall(PlaySoundFile, file) end
end

-- Every aura ID an icon watches: the main ID plus up to four extras. The icon
-- reacts as soon as one of them matches.
local AURA_ID_FIELDS = {}
for i = 2, C.MAX_AURA_IDS do AURA_ID_FIELDS[i] = "id" .. i end
function C:AuraIDs(entry, out)
  out = out or {}
  for i = #out, 1, -1 do out[i] = nil end
  if not entry then return out end
  if tonumber(entry.id) then out[#out + 1] = tonumber(entry.id) end
  for i = 2, C.MAX_AURA_IDS do
    local extra = tonumber(entry[AURA_ID_FIELDS[i]])
    if extra then out[#out + 1] = extra end
  end
  return out
end

C.POWER_TYPES = {
  -- Darker takes on the classic power colours: same hue, ~65% brightness so
  -- the bars sit calmly against the dark UI instead of glowing.
  { key = "MANA",        name = "Mana",        index = 0, color = { 0.13, 0.29, 0.62 } },
  { key = "RAGE",        name = "Rage",        index = 1, color = { 0.50, 0.13, 0.13 } },
  { key = "FOCUS",       name = "Focus",       index = 2, color = { 0.55, 0.35, 0.16 } },
  { key = "ENERGY",      name = "Energy",      index = 3, color = { 0.62, 0.55, 0.19 } },
  { key = "RUNIC_POWER", name = "Runic power", index = 6, color = { 0.22, 0.48, 0.58 } },
}

-- Built once: PowerInfo is called on every power tick, so a linear walk over
-- the list is wasted work.
local POWER_BY_KEY = {}
for _, p in ipairs(C.POWER_TYPES) do POWER_BY_KEY[p.key] = p end

function C:PowerInfo(key)
  return POWER_BY_KEY[key] or C.POWER_TYPES[1]
end

-- Font ----------------------------------------------------------------------
local function PickFont()
  local test = UIParent:CreateFontString(nil, "OVERLAY")
  -- Built with tinsert on purpose: a nil first entry would make ipairs stop on
  -- the very first slot and silently skip every fallback below it.
  local candidates = {}
  if JunkieUI and JunkieUI.font then candidates[#candidates + 1] = JunkieUI.font end
  candidates[#candidates + 1] = "Interface\\AddOns\\JunkieUI\\media\\Expressway.ttf"
  for i = 1, #candidates do
    local path = candidates[i]
    if test:SetFont(path, 12) then
      test:Hide()
      return path
    end
  end
  test:Hide()
  return STANDARD_TEXT_FONT
end

C.font = PickFont()

function C:Text(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(C.font, size or 11, "OUTLINE")
  fs:SetJustifyH(justify or "CENTER")
  fs:SetShadowOffset(0, 0)
  return fs
end

function C:Flat(frame, r, g, b, a)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(r or C.BOX[1], g or C.BOX[2], b or C.BOX[3], a or 1)
  frame:SetBackdropBorderColor(0, 0, 0, 1)
  return frame
end

-- Profiles ------------------------------------------------------------------
function C:NewPower()
  return {
    enabled = false,
    count = 1,                       -- 1 or 2 stacked bars
    types = { "MANA", "ENERGY" },
    showPercent = false,             -- mana only: show the percentage instead
    smooth = false,                  -- glide to the new value instead of snapping
    height = 15,                     -- bar 1 height, 15..50 px
    height2 = 15,                    -- bar 2 height, 15..50 px
    standalone = false,              -- free width instead of following the icons
    width = 250,                     -- 60..600 px when standalone
  }
end

-- Universal bar slots ---------------------------------------------------------
-- The three bars above the cooldown row are identical slots. Each one is either
-- a resource bar (a fluid bar: a power type, or the stacks of any aura) or a
-- combo point bar (segmented plates: combo points, aura stacks or charges).
C.MAX_BARS = 3

function C:NewBar(kind)
  return {
    enabled = false,
    kind = kind or "resource",       -- "resource" | "combo"
    height = 15,                     -- 15..50 px, both modes
    -- Resource mode ---------------------------------------------------------
    resource = "MANA",               -- a power key, or "OTHER" for an aura
    showPercent = false,             -- mana only: percentage instead of numbers
    smooth = false,                  -- glide instead of snapping
    standalone = false,              -- free width instead of following the icons
    width = 250,                     -- 60..600 px while standalone
    auraID = nil,                    -- "Other resources": the aura it reads
    auraType = "HELPFUL",            -- HELPFUL = buff, HARMFUL = debuff
    maxStacks = 100,                 -- stack count that reads as a full bar
    -- Combo mode ------------------------------------------------------------
    count = 5,                       -- 1..20 segments
    useAura = false,                 -- count aura stacks instead of points
    spellID = nil,
    useCharges = false,              -- count charges of a spell instead
    chargeSpellID = nil,
    onTarget = false,                -- read the aura on the target, not the player
    classColor = false,
    color = { C.ACCENT[1], C.ACCENT[2], C.ACCENT[3] },
  }
end

function C:NewBars()
  return { C:NewBar("resource"), C:NewBar("resource"), C:NewBar("combo") }
end

function C:BarHeight(bar)
  return math.max(15, math.min(50, tonumber(bar and bar.height) or 15))
end

-- Colour of the lit segments of one combo bar.
function C:BarColor(bar)
  bar = bar or {}
  if bar.classColor then
    local _, class = UnitClass("player")
    local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if col then return { col.r, col.g, col.b } end
  end
  return bar.color or C.ACCENT
end

local VALID_KIND = { resource = true, combo = true }

-- Older profiles carried two hardcoded power bars plus one combo bar. They are
-- folded into the three universal slots exactly once, so nothing is lost.
function C:MigrateBars(set, combo)
  if type(set) ~= "table" then return end
  if type(set.bars) ~= "table" then
    local bars = C:NewBars()
    local pw = type(set.power) == "table" and set.power or nil
    if pw then
      for i = 1, 2 do
        local b = bars[i]
        b.kind = "resource"
        b.enabled = (pw.enabled and (i == 1 or (tonumber(pw.count) or 1) >= 2)) and true or false
        b.resource = (type(pw.types) == "table" and pw.types[i]) or (i == 1 and "MANA" or "ENERGY")
        b.height = tonumber(i == 2 and (pw.height2 or pw.height) or pw.height) or 15
        b.showPercent = pw.showPercent and true or false
        b.smooth = pw.smooth and true or false
        b.standalone = pw.standalone and true or false
        b.width = tonumber(pw.width) or 250
      end
    end
    if type(combo) == "table" then
      local b = bars[3]
      b.kind = "combo"
      b.enabled = combo.enabled and true or false
      b.count = tonumber(combo.count) or 5
      b.height = tonumber(combo.height) or 15
      b.useAura = combo.useAura and true or false
      b.spellID = tonumber(combo.spellID)
      b.useCharges = combo.useCharges and true or false
      b.chargeSpellID = tonumber(combo.chargeSpellID)
      b.classColor = combo.classColor and true or false
      if type(combo.color) == "table" then b.color = { combo.color[1], combo.color[2], combo.color[3] } end
    end
    set.bars = bars
  end
  for i = 1, C.MAX_BARS do
    local b = type(set.bars[i]) == "table" and set.bars[i] or C:NewBar(i == 3 and "combo" or "resource")
    set.bars[i] = b
    if not VALID_KIND[b.kind] then b.kind = "resource" end
    b.enabled = b.enabled and true or false
    b.height = C:BarHeight(b)
    b.width = math.max(60, math.min(600, tonumber(b.width) or 250))
    b.resource = type(b.resource) == "string" and b.resource or "MANA"
    b.auraID = tonumber(b.auraID)
    b.auraType = (b.auraType == "HARMFUL") and "HARMFUL" or "HELPFUL"
    b.maxStacks = math.max(1, math.min(1000, tonumber(b.maxStacks) or 100))
    b.count = math.max(1, math.min(20, tonumber(b.count) or 5))
    b.spellID = tonumber(b.spellID)
    b.chargeSpellID = tonumber(b.chargeSpellID)
    if type(b.color) ~= "table" then b.color = { C.ACCENT[1], C.ACCENT[2], C.ACCENT[3] } end
  end
  for i = C.MAX_BARS + 1, #set.bars do set.bars[i] = nil end
  return set.bars
end


function C:NewProfile(name)
  return {
    name = name or "Default",
    y = 0,
    iconSize = 40,
    auraSize = 35,
    remindSize = 35,     -- reminder row icons, independent of the aura rows
    unitIconSize = 35,   -- the two bars glued to the player unit frame
    castbarTop = false,  -- dock the JunkieUI player castbar on top (per profile)
    castbarHeight = 20,  -- height of the docked player castbar (15-50)
    showGCD = false,     -- draw the global cooldown swipe on both CD bars
    mainEnabled = false,
    subEnabled = false,
    upEnabled = false,
    downEnabled = false,
    mainCount = 0,
    subCount = 0,
    upCount = 0,
    downCount = 0,
    main = {},          -- [i] = { kind = "spell"|"item", id = n, glow = "none" }
    sub = {},
    up = {},            -- player unitframe upper bar (grows left)
    down = {},          -- player unitframe lower bar (grows right)
    rows = {
      { enabled = false, count = 0, unit = "my", icons = {} },   -- [i] = { id = n, glow = "none" }
      { enabled = false, count = 0, unit = "my", icons = {} },
      { enabled = false, count = 0, unit = "target", icons = {} },
      -- Row 4 is the "missing buffs" reminder row at the top of the screen.
      { enabled = false, count = 0, unit = "my", icons = {} },
    },
    missingY = 120,     -- reminder row distance from the top of the screen

    power = C:NewPower(),
    bars = C:NewBars(),
    combo = {
      enabled = false,
      count = 5,                       -- 1..20
      height = 15,                     -- bar height in px (15..50)
      spellID = nil,                   -- aura that carries the point stacks
      useCharges = false,              -- read charges of a spell instead
      chargeSpellID = nil,             -- that spell
      classColor = false,              -- use the class colour instead of the palette
      color = { C.ACCENT[1], C.ACCENT[2], C.ACCENT[3] },
    },
    -- Stance / shapeshift mini sets. These are NOT full profiles: they only
    -- carry their own cooldown canvas and their own power bars.
    stanceEnabled = false,
    powerStanceEnabled = false,
    stances = {},                      -- [form 0..n] = mini set
    loadSpell = { enabled = false, id = nil },
  }
end

-- Mini sets -------------------------------------------------------------------
function C:NewStanceSet()
  return {
    mainEnabled = false,
    subEnabled = false,
    upEnabled = false,
    downEnabled = false,
    mainCount = 0,
    subCount = 0,
    upCount = 0,
    downCount = 0,
    main = {},
    sub = {},
    up = {},
    down = {},
    power = C:NewPower(),
    bars = C:NewBars(),
  }
end

-- Counts are derived, never typed in: an icon list is packed to the left and
-- the count is however many icons carry an ID, or zero while the bar is off.
-- Two slots must never share the same entry table: an older build could copy
-- one table into several slots, which made every per-icon setting in the row
-- look linked. Any duplicate found here is split into its own copy.
-- Every icon also carries a uid so the settings popup can write back to the
-- exact icon it was opened from, whatever happens to the slot order.
local nextUID = 0
function C:NextUID()
  nextUID = nextUID + 1
  return string.format("%d-%d", math.floor(GetTime() * 100) % 1000000, nextUID)
end

local function Pack(list, max)
  local out, seen, uids = {}, {}, {}
  for i = 1, max do
    local e = list[i]
    if e and e.id then
      if seen[e] then e = C:Clone(e); e.uid = nil end
      seen[e] = true
      if not e.uid or uids[e.uid] then e.uid = C:NextUID() end
      uids[e.uid] = true
      out[#out + 1] = e
    end
  end
  for i = 1, max do list[i] = out[i] end
  return #out
end



function C:SyncSet(set)
  if not set then return end
  set.main = set.main or {}
  set.sub = set.sub or {}
  set.up = set.up or {}
  set.down = set.down or {}
  if set.mainEnabled == nil then set.mainEnabled = (set.mainCount or 0) > 0 end
  if set.subEnabled == nil then set.subEnabled = (set.subCount or 0) > 0 end
  if set.upEnabled == nil then set.upEnabled = (set.upCount or 0) > 0 end
  if set.downEnabled == nil then set.downEnabled = (set.downCount or 0) > 0 end
  local m = Pack(set.main, C.MAX_ICONS)
  local s = Pack(set.sub, C.MAX_ICONS)
  local u = Pack(set.up, C.MAX_ICONS)
  local d = Pack(set.down, C.MAX_ICONS)
  set.mainCount = set.mainEnabled and m or 0
  set.subCount = set.subEnabled and s or 0
  set.upCount = set.upEnabled and u or 0
  set.downCount = set.downEnabled and d or 0
end

function C:SyncRow(row)
  if not row then return end
  row.icons = row.icons or {}
  if row.enabled == nil then row.enabled = (row.count or 0) > 0 end
  local n = Pack(row.icons, C.MAX_ROW_ICONS)
  row.count = row.enabled and n or 0
end


-- form nil / -1 = the profile itself (base canvas).
function C:EditSet(form)
  local p = C:Profile()
  if not p then return nil end
  if not form or form < 0 then return p end
  p.stances = p.stances or {}
  p.stances[form] = p.stances[form] or C:NewStanceSet()
  p.stances[form].power = p.stances[form].power or C:NewPower()
  return p.stances[form]
end

-- Deep copy used by the canvas clipboard so a pasted canvas never shares
-- tables with the canvas it was copied from.
local function Clone(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do
    -- A copied icon is a new icon. Never copy its identity into another canvas;
    -- SyncSet/SyncRow assigns a fresh uid before it can be edited.
    if k ~= "uid" then out[k] = Clone(v) end
  end
  return out
end
C.Clone = function(_, v) return Clone(v) end

-- Floating settings windows share one collision-aware placement path. The
-- picker and per-icon editor are kept outside the main settings frame so they
-- never cover it or each other; if the preferred side is full they move to the
-- opposite side automatically.
C.settingsWindows = {}

function C:RegisterSettingsWindow(frame)
  if not frame then return end
  for _, other in ipairs(C.settingsWindows) do
    if other == frame then return end
  end
  table.insert(C.settingsWindows, frame)
end

local function FramesOverlap(a, b, gap)
  if not (a and b and a.GetLeft and b.GetLeft) then return false end
  local al, ar, at, ab = a:GetLeft(), a:GetRight(), a:GetTop(), a:GetBottom()
  local bl, br, bt, bb = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
  if not (al and ar and at and ab and bl and br and bt and bb) then return false end
  gap = gap or 0
  return al < br + gap and ar > bl - gap and ab < bt + gap and at > bb - gap
end

function C:PlaceSettingsWindow(frame, preferred)
  if not frame then return end
  C:RegisterSettingsWindow(frame)
  local host = _G["JunkieConfig"]
  local refs = {}
  if preferred and preferred:IsShown() then refs[#refs + 1] = preferred end
  if host and host:IsShown() and host ~= preferred then refs[#refs + 1] = host end
  for _, other in ipairs(C.settingsWindows) do
    if other ~= frame and other ~= preferred and other:IsShown() then refs[#refs + 1] = other end
  end
  local ref = refs[1] or host or UIParent
  local candidates = {
    { "TOPLEFT", ref, "TOPRIGHT", 8, 0 },
    { "TOPRIGHT", ref, "TOPLEFT", -8, 0 },
    { "BOTTOMLEFT", ref, "TOPLEFT", 0, 8 },
    { "TOPLEFT", ref, "BOTTOMLEFT", 0, -8 },
  }
  for _, point in ipairs(candidates) do
    frame:ClearAllPoints()
    frame:SetPoint(unpack(point))
    local bad = false
    local left, right = frame:GetLeft(), frame:GetRight()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    local ul, ur = UIParent:GetLeft() or 0, UIParent:GetRight() or UIParent:GetWidth()
    local ut, ub = UIParent:GetTop() or UIParent:GetHeight(), UIParent:GetBottom() or 0
    if not left or left < ul or right > ur or bottom < ub or top > ut then bad = true end
    if not bad then
      for _, other in ipairs(refs) do
        if other ~= frame and FramesOverlap(frame, other, 4) then bad = true break end
      end
    end
    if not bad then return end
  end
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

function C:CopySet(set)
  if not set then return end
  C.clipboard = {
    main = Clone(set.main or {}),
    sub = Clone(set.sub or {}),
    up = Clone(set.up or {}),
    down = Clone(set.down or {}),
    power = Clone(set.power or {}),
    bars = Clone(set.bars or {}),
    mainEnabled = set.mainEnabled,
    subEnabled = set.subEnabled,
    upEnabled = set.upEnabled,
    downEnabled = set.downEnabled,
  }
end

function C:PasteSet(set)
  if not C.clipboard or not set then return end
  set.main = Clone(C.clipboard.main or {})
  set.sub = Clone(C.clipboard.sub or {})
  set.up = Clone(C.clipboard.up or {})
  set.down = Clone(C.clipboard.down or {})
  if C.clipboard.mainEnabled ~= nil then set.mainEnabled = C.clipboard.mainEnabled end
  if C.clipboard.subEnabled ~= nil then set.subEnabled = C.clipboard.subEnabled end
  if C.clipboard.upEnabled ~= nil then set.upEnabled = C.clipboard.upEnabled end
  if C.clipboard.downEnabled ~= nil then set.downEnabled = C.clipboard.downEnabled end
  if C.clipboard.power then set.power = Clone(C.clipboard.power) end
  if C.clipboard.bars then set.bars = Clone(C.clipboard.bars); C:MigrateBars(set, nil) end
  C:SyncSet(set)
end


-- The cooldown canvas that is actually drawn right now.
function C:ActiveSet()
  local p = C:Profile()
  if p and p.stanceEnabled then
    local s = p.stances and p.stances[C:ActiveStance()]
    if s then return s end
  end
  return p
end

-- The three universal bar slots that are actually drawn right now. They follow
-- the same per stance switch the old power bars used.
function C:ActiveBars()
  local p = C:Profile()
  if not p then return nil end
  if p.powerStanceEnabled then
    local s = p.stances and p.stances[C:ActiveStance()]
    if s then return C:MigrateBars(s, nil) end
  end
  return C:MigrateBars(p, p.combo)
end

-- Stances / shapeshifts -------------------------------------------------------
function C:StanceCount()
  local ok, n = pcall(GetNumShapeshiftForms)
  return (ok and n) or 0
end

function C:ActiveStance()
  local ok, form = pcall(GetShapeshiftForm)
  if not ok or not form then return 0 end
  return form
end

function C:StanceName(i)
  if i == 0 then return "No form / caster" end
  local ok, _, name = pcall(GetShapeshiftFormInfo, i)
  if ok and name and name ~= "" then return name end
  return "Form " .. i
end

-- Characters ------------------------------------------------------------------
function C:CharacterName()
  return UnitName("player") or "?"
end

function C:CharKey()
  local name = C:CharacterName()
  local realm = GetRealmName() or ""
  return name .. " - " .. realm
end

-- Spell knowledge -------------------------------------------------------------
-- The spellbook is the only reliable source in 3.3.5: IsSpellKnown answers
-- false for a lot of things the player really owns (racials, profession and
-- pet book entries), which is why the book is scanned by name and cached.
local bookNames

-- The book is scanned tab by tab. A flat 1..n walk stops at the first empty
-- slot, and the general tab (racials such as Berserking) sits behind such a
-- gap on a lot of characters, which is why those never showed up on the bar.
local function ScanBook()
  bookNames = {}
  local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
  local scanned = false
  for t = 1, tabs do
    local _, _, offset, numSpells = GetSpellTabInfo(t)
    if offset and numSpells then
      scanned = true
      for i = offset + 1, offset + numSpells do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if name then bookNames[name] = true end
      end
    end
  end
  if not scanned then
    local i = 1
    while i < 1024 do
      local name = GetSpellName(i, BOOKTYPE_SPELL)
      if not name then break end
      bookNames[name] = true
      i = i + 1
    end
  end
end

-- Answered once per spell id and kept until the spellbook changes: EntryKnown
-- runs for every icon on every rebuild, and one raw lookup costs three API
-- calls plus two pcalls.
local knownCache = {}

function C:InvalidateBook()
  bookNames = nil
  for k in pairs(knownCache) do knownCache[k] = nil end
  if C.InvalidateSpellCache then C:InvalidateSpellCache() end
end

function C:SpellKnown(id)
  id = tonumber(id)
  if not id then return false end
  local cached = knownCache[id]
  if cached ~= nil then return cached end

  local known = false
  local name = GetSpellInfo(id)
  if name then
    if not bookNames then ScanBook() end
    if bookNames[name] then
      known = true
    else
      -- GetSpellInfo(name) only answers for spells that sit in the spellbook.
      local ok2, bookName = pcall(GetSpellInfo, name)
      if ok2 and bookName then known = true end
    end
  end
  if not known then
    local ok, isKnown = pcall(IsSpellKnown, id)
    if ok and isKnown then known = true end
  end
  knownCache[id] = known
  return known
end

-- Worn equipment, answered from one snapshot instead of 19 slot reads per
-- icon. The snapshot is only rebuilt after an equipment event, so a rebuild
-- with ten item icons costs the same as a rebuild with one.
local equipIDs, equipDirty = {}, true
local trinketUse = {}

C.equipEpoch = 0
function C:InvalidateEquip()
  equipDirty = true
  C.equipEpoch = (C.equipEpoch or 0) + 1
  trinketUse[13], trinketUse[14] = nil, nil
end

local function EquipMap()
  if equipDirty then
    for k in pairs(equipIDs) do equipIDs[k] = nil end
    for slot = 1, 19 do
      local ok, worn = pcall(GetInventoryItemID, "player", slot)
      if ok and worn then equipIDs[worn] = true end
    end
    equipDirty = false
  end
  return equipIDs
end

-- True while the id sits in one of the worn equipment slots.
function C:ItemEquipped(id)
  id = tonumber(id)
  if not id then return false end
  return EquipMap()[id] and true or false
end

-- The client can hand out an item link before its tooltip data has arrived,
-- and GetItemSpell then answers nil for a trinket that really does have a use
-- effect. One single delayed re-check covers that window; the frame hides
-- itself again immediately, so there is no running OnUpdate.
local retry = CreateFrame("Frame")
retry:Hide()
retry.elapsed = 0
retry:SetScript("OnUpdate", function(self, e)
  self.elapsed = self.elapsed + (e or 0)
  if self.elapsed < 0.5 then return end
  self:Hide()
  C:InvalidateEquip()
  if C.db then C:QueueRebuild() end
end)
local function QueueItemRetry()
  if retry:IsShown() then return end
  retry.elapsed = 0
  retry:Show()
end

-- On-use answer per trinket slot, kept until the slot changes.
local function TrinketUsable(slot)
  local cached = trinketUse[slot]
  if cached ~= nil then return cached end
  local link = GetInventoryItemLink("player", slot)
  if not link then trinketUse[slot] = false return false end
  local ok, spell = pcall(GetItemSpell, link)
  local usable = (ok and spell) and true or false
  if not usable and not ok then
    -- Data was not ready: do not cache a wrong answer, ask again shortly.
    QueueItemRetry()
    return false
  end
  if not usable and not GetItemInfo(link) then
    QueueItemRetry()
    return false
  end
  trinketUse[slot] = usable
  return usable
end

-- An icon is only drawn while the player actually owns it: a spell has to sit
-- in the spellbook and an item has to sit in the bags. Anything else keeps its
-- slot in the settings, marked red, and comes back on its own.
function C:EntryKnown(entry)
  if not entry or not entry.id then return false end
  if entry.kind == "trinket" then
    -- Follows the worn trinket: only an equipped on-use trinket is drawn.
    C.equipWatch = true
    return TrinketUsable(tonumber(entry.id) or 13)
  end
  if entry.kind == "item" then
    -- 3.3.5 has no "equipped" flag on GetItemCount, so the worn slots are read
    -- from the cached snapshot above.
    local equipped = C:ItemEquipped(entry.id)
    if entry.equippedOnly then
      -- Once a single icon asks for it, equipment swaps have to redraw.
      C.equipWatch = true
      return equipped
    end
    if equipped then return true end
    local ok, count = pcall(GetItemCount, entry.id)
    if not ok then return true end
    return (count or 0) > 0
  end
  return C:SpellKnown(entry.id) and true or false
end


-- Every character starts on its own blank profile and keeps whatever it picks.
function C:EnsureCharProfile()
  C.db.charProfile = C.db.charProfile or {}
  local key = C:CharKey()
  local bound = C.db.charProfile[key]
  if bound and C.db.profiles[bound] then return bound end

  -- Named after the character alone; the realm is only appended when another
  -- realm already owns that name.
  local name = C:CharacterName()
  if C.db.profiles[name] then
    local owner
    for k, v in pairs(C.db.charProfile) do
      if v == name then owner = k end
    end
    if owner and owner ~= key then name = key end
  end
  if not C.db.profiles[name] then
    C.db.profiles[name] = C:NewProfile(name)
  end
  C.db.charProfile[key] = name
  C.db.active = name
  C.db.resolved = name
  return name
end

function C:ProfileNames()
  local out = {}
  for name in pairs(C.db.profiles) do table.insert(out, name) end
  table.sort(out)
  return out
end

-- A profile bound to a spell may only load while that spell is known.
local function SpellBlocked(p)
  local ls = p and p.loadSpell
  if not (ls and ls.enabled) then return false end
  return not (ls.id and C:SpellKnown(ls.id))
end

local function SpellLoaded(p)
  local ls = p and p.loadSpell
  return (ls and ls.enabled and ls.id and C:SpellKnown(ls.id)) and true or false
end

function C:ResolveProfileName()
  -- The profile this character last picked always wins, so nothing a player
  -- sets up can be swapped out from under them on the next login.
  local bound = C.db.charProfile and C.db.charProfile[C:CharKey()]
  if bound and C.db.profiles[bound] and not SpellBlocked(C.db.profiles[bound]) then return bound end

  -- Otherwise spell driven loading takes over: one character, several builds.
  for _, name in ipairs(C:ProfileNames()) do
    if SpellLoaded(C.db.profiles[name]) then return name end
  end
  if C.db.active and C.db.profiles[C.db.active] and not SpellBlocked(C.db.profiles[C.db.active]) then
    return C.db.active
  end
  local names = C:ProfileNames()
  for _, name in ipairs(names) do
    if not SpellBlocked(C.db.profiles[name]) then return name end
  end
  return names[1]
end

-- Reload prompt ---------------------------------------------------------------
StaticPopupDialogs["JUNKIECD_RELOAD"] = {
  text = "JunkieCD: %s\nA UI reload is needed for stable performance.",
  button1 = "Reload now",
  button2 = "Later",
  OnAccept = function() ReloadUI() end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
}

function C:RequestReload(reason)
  if InCombatLockdown() then
    C.pendingReload = reason or "Settings changed"
    return
  end
  StaticPopup_Show("JUNKIECD_RELOAD", reason or "Settings changed")
end


function C:Profile()
  local p = C.db.profiles[C.db.resolved or ""]
  if p then return p end
  -- Never hand back nil: a missing profile would make every setter error out.
  local name = C:ResolveProfileName()
  if not name then
    name = "Default"
    C.db.profiles[name] = C.db.profiles[name] or C:NewProfile(name)
  end
  C.db.resolved = name
  return C.db.profiles[name]
end


function C:UseProfile(name, silent)
  if not C.db.profiles[name] then return end
  C.db.active = name
  C.db.resolved = name
  C.db.charProfile[C:CharKey()] = name
  if C.Rebuild then C:Rebuild() end
  if C.RefreshConfig then C:RefreshConfig() end
  if not silent then
    print("|cffde7230JunkieCD|r profile: " .. name)
  end
end

function C:CreateProfile(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or C.db.profiles[name] then return false end
  C.db.profiles[name] = C:NewProfile(name)
  C:UseProfile(name, true)
  return true
end

function C:DeleteProfile(name)
  if not C.db.profiles[name] then return end
  if #C:ProfileNames() <= 1 then return end
  C.db.profiles[name] = nil
  C.db.resolved = C:ResolveProfileName()
  C:UseProfile(C.db.resolved, true)
end

-- Init ----------------------------------------------------------------------
local function Defaults()
  return {
    profiles = {},
    charProfile = {},        -- ["Name - Realm"] = profile name
    active = "Default",
    locked = true,
    cooldownText = true,     -- one global timer-text switch for CDs and auras
    castbarTop = false,      -- dock the JunkieUI player castbar on top
    castbarHeight = 20,      -- height of the docked player castbar (15-50)
  }
end

-- Repair a saved profile in place. Missing tables are filled in and stray
-- values are coerced, so an old or half written profile can never make a
-- setter error out later (a Lua error mid-save is what wipes settings).
local function RepairIcons(list, max, seenTables, seenUIDs)
  if type(list) ~= "table" then return {} end
  for i = 1, max do
    local e = list[i]
    if type(e) ~= "table" or not tonumber(e.id) then
      list[i] = nil
    else
      -- Old profiles could hold the same Lua table in several slots. Detach it
      -- before any setting is read, and make identity unique across every row,
      -- canvas and stance—not merely inside the current row. Identical spell or
      -- aura IDs remain fully independent instances.
      if seenTables[e] then
        e = Clone(e)
        e.uid = nil
        list[i] = e
      end
      seenTables[e] = true
      e.id = tonumber(e.id)
      -- Extra aura IDs (an icon can watch up to five).
      for n = 2, C.MAX_AURA_IDS do
        local key = "id" .. n
        if e[key] ~= nil then e[key] = tonumber(e[key]) end
      end
      if e.expireWarnAt ~= nil then e.expireWarnAt = math.max(1, math.min(600, tonumber(e.expireWarnAt) or 60)) end
      if type(e.sound) ~= "string" then e.sound = e.sound and tostring(e.sound) or nil end
      if type(e.glow) ~= "string" then e.glow = "none" end
      if not e.uid or seenUIDs[e.uid] then e.uid = C:NextUID() end
      seenUIDs[e.uid] = true
    end
  end
  return list
end

local function RepairSet(set, seenTables, seenUIDs)
  if type(set) ~= "table" then return end
  set.main = RepairIcons(set.main or {}, C.MAX_ICONS, seenTables, seenUIDs)
  set.sub = RepairIcons(set.sub or {}, C.MAX_ICONS, seenTables, seenUIDs)
  set.up = RepairIcons(set.up or {}, C.MAX_ICONS, seenTables, seenUIDs)
  set.down = RepairIcons(set.down or {}, C.MAX_ICONS, seenTables, seenUIDs)
  C:MigrateBars(set, set.combo)
  set.power = type(set.power) == "table" and set.power or C:NewPower()
  set.power.height = tonumber(set.power.height) or 15
  set.power.width = tonumber(set.power.width) or 250
  set.power.count = tonumber(set.power.count) or 1
  set.power.types = type(set.power.types) == "table" and set.power.types or { "MANA", "ENERGY" }
  C:SyncSet(set)
end

local function Cleanup(db)
  -- Keys from removed features (specialization bookkeeping).
  db.specProfile, db.specNames, db.specOverride = nil, nil, nil
  db.chatSpec, db.stanceProfile, db.stanceEnabled, db.talentProfile = nil, nil, nil, nil

  local seenTables, seenUIDs = {}, {}
  for name, p in pairs(db.profiles or {}) do
    if type(p) ~= "table" then
      db.profiles[name] = C:NewProfile(name)
      p = db.profiles[name]
    end
    p.name = name
    p.specName, p.loadTalent, p.x = nil, nil, nil
    p.iconSize = tonumber(p.iconSize) or 40
    p.auraSize = tonumber(p.auraSize) or 35
    p.remindSize = tonumber(p.remindSize) or p.auraSize
    p.y = tonumber(p.y) or 0

    RepairSet(p, seenTables, seenUIDs)

    if type(p.rows) ~= "table" then p.rows = {} end
    local defaults = C:NewProfile(name).rows
    for i = 1, 4 do
      local row = type(p.rows[i]) == "table" and p.rows[i] or defaults[i]
      p.rows[i] = row
      row.unit = row.unit or defaults[i].unit
      row.icons = RepairIcons(row.icons or {}, C.MAX_ROW_ICONS, seenTables, seenUIDs)
      if row.enabled == nil then row.enabled = (row.count or 0) > 0 end
      C:SyncRow(row)
    end

    if type(p.stances) ~= "table" then p.stances = {} end
    for _, s in pairs(p.stances) do RepairSet(s, seenTables, seenUIDs) end

    if type(p.loadSpell) ~= "table" then p.loadSpell = { enabled = false, id = nil } end
    p.loadSpell.id = tonumber(p.loadSpell.id)
    if type(p.combo) ~= "table" then p.combo = C:NewProfile(name).combo end
    p.combo.count = math.max(1, math.min(20, tonumber(p.combo.count) or 5))
    p.combo.height = math.max(15, math.min(50, tonumber(p.combo.height) or 15))
    p.combo.spellID = tonumber(p.combo.spellID)
    if type(p.combo.color) ~= "table" then p.combo.color = { C.ACCENT[1], C.ACCENT[2], C.ACCENT[3] } end
    if p.combo.classColor == nil then p.combo.classColor = false end
  end
end

-- Spell and shapeshift events fire in bursts. Only touch the frames when the
-- resolved profile or the active form actually changed.
local lastForm
local function Reresolve()
  local name = C:ResolveProfileName()
  local form = C:ActiveStance()
  if name and name ~= C.db.resolved then
    C.db.resolved = name
    lastForm = form
    C:Rebuild()
    if C.RefreshConfig then C:RefreshConfig() end
  elseif form ~= lastForm then
    lastForm = form
    C:Rebuild()
  end
end
C.Reresolve = function() Reresolve() end

-- Spell events arrive in bursts, so the rebuild they ask for is collapsed into
-- one pass on the next frame instead of running once per event.
local pending = CreateFrame("Frame")
pending:Hide()
pending:SetScript("OnUpdate", function(self)
  self:Hide()
  if not C.db then return end
  C:Rebuild()
  if C.RefreshConfig then C:RefreshConfig() end
end)
function C:QueueRebuild() pending:Show() end

-- Login settle pass ----------------------------------------------------------
-- The first rebuild after login happens before JunkieUI has placed its unit
-- frames and before the client has finished handing out the spellbook and the
-- item cache, so docked rows and the anchor can land on fallback positions.
-- Instead of paying for that on every frame forever, the layout is sampled a
-- handful of times during the first seconds and rebuilt only when something it
-- depends on actually changed. Two clean samples in a row (or the last step)
-- hide the frame for the rest of the session: no cost afterwards.
local SETTLE_STEPS = { 0.5, 1.5, 3, 6 }
local SETTLE_KEYS = { "main", "sub", "up", "down" }
local settle = CreateFrame("Frame")
settle:Hide()
local settleStep, settleTime, settleSig, settleStable = 1, 0, nil, 0

local function LayoutSignature()
  local pf = _G["JunkiePlayerFrame"]
  local left = (pf and pf:GetLeft()) or 0
  local top = (pf and pf:GetTop()) or 0
  local uy = (JunkieUI and JunkieUI.db and JunkieUI.db.unitY) or 0
  local known = 0
  local set = (C.ActiveSet and C:ActiveSet()) or C:Profile()
  if type(set) == "table" then
    for k = 1, #SETTLE_KEYS do
      local list = set[SETTLE_KEYS[k]]
      if type(list) == "table" then
        for i = 1, #list do
          if C:EntryKnown(list[i]) then known = known + 1 end
        end
      end
    end
  end
  return string.format("%d:%d:%d:%d:%s",
    math.floor(left + 0.5), math.floor(top + 0.5), math.floor(uy + 0.5),
    known, tostring(C.db and C.db.resolved))
end

settle:SetScript("OnUpdate", function(self, elapsed)
  settleTime = settleTime + (elapsed or 0)
  local step = SETTLE_STEPS[settleStep]
  if not step then self:Hide() return end
  if settleTime < step then return end
  settleStep = settleStep + 1
  if not C.db then
    if not SETTLE_STEPS[settleStep] then self:Hide() end
    return
  end
  local sig = LayoutSignature()
  if sig ~= settleSig or C.dockPending or C.anchorPending then
    settleSig = sig
    settleStable = 0
    -- The spellbook may only just have filled in, so the known cache is
    -- dropped once per changed sample and the profile is resolved again.
    C:InvalidateBook()
    Reresolve()
    C:QueueRebuild()
  else
    settleStable = settleStable + 1
    if settleStable >= 2 then self:Hide() return end
  end
  if not SETTLE_STEPS[settleStep] then self:Hide() end
end)

-- Restarted on every world entry (login, reload, zoning) because JunkieUI
-- rebuilds its frames there too.
function C:StartSettle()
  settleStep, settleTime, settleSig, settleStable = 1, 0, nil, 0
  settle:Show()
end

C:RegisterEvent("ADDON_LOADED")
C:RegisterEvent("PLAYER_LOGIN")
C:RegisterEvent("PLAYER_ENTERING_WORLD")

C:RegisterEvent("PLAYER_TALENT_UPDATE")
C:RegisterEvent("CHARACTER_POINTS_CHANGED")
C:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
C:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
C:RegisterEvent("PLAYER_REGEN_ENABLED")
C:RegisterEvent("SPELLS_CHANGED")
C:RegisterEvent("LEARNED_SPELL_IN_TAB")
C:RegisterEvent("BAG_UPDATE")
-- Only acted on when an icon is set to "only show if equipped".
C:RegisterEvent("UNIT_INVENTORY_CHANGED")
pcall(C.RegisterEvent, C, "PLAYER_EQUIPMENT_CHANGED")

-- Loaded on demand by JunkieUI, so the start up path must also work when the
-- player is already logged in.
local started = false
local function Startup()
  if started then return end
  started = true
  C:EnsureCharProfile()
  C.db.resolved = C:ResolveProfileName()
  for _, fn in ipairs(C.modules) do fn() end
  C:Rebuild()
  print("|cffde7230JunkieCD|r v" .. C.version .. " loaded. |cffffffff/jcd|r for settings.")
end


C:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then

    JunkieCDDB = JunkieCDDB or {}
    for k, v in pairs(Defaults()) do
      if JunkieCDDB[k] == nil then JunkieCDDB[k] = v end
    end
    C.db = JunkieCDDB
    if not next(C.db.profiles) then
      C.db.profiles["Default"] = C:NewProfile("Default")
    end
    Cleanup(C.db)
    C.db.resolved = C:ResolveProfileName()
    if IsLoggedIn and IsLoggedIn() then Startup() C:StartSettle() end
  elseif event == "PLAYER_LOGIN" then
    Startup()
    C:StartSettle()

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- JunkieUI re-places its frames here as well, so the settle pass runs
    -- again on reloads and zoning. It costs four samples and then stops.
    C:InvalidateEquip()
    if C.db then C:StartSettle() end



  elseif event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
    -- A trinket moved in or out of a slot. Nothing to do unless some icon is
    -- actually gated on being equipped.
    if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
    C:InvalidateEquip()
    if C.equipWatch and C.db then C:QueueRebuild() end


  elseif event == "BAG_UPDATE" then
    -- An item that left the bags stops being drawn, and comes back on its own.
    -- One listener for both jobs: the picker cache and the bars.
    if C.InvalidateSpellCache then C:InvalidateSpellCache() end
    if C.db then C:QueueRebuild() end

  elseif event == "PLAYER_REGEN_ENABLED" then
    if C.rebuildAfterCombat then
      C.rebuildAfterCombat = nil
      C:QueueRebuild()
    end
    if C.pendingReload then
      local reason = C.pendingReload
      C.pendingReload = nil
      C:RequestReload(reason)
    end
  else
    if C.db then
      -- The spellbook just changed: drop the cache so unlearned icons vanish
      -- and relearned ones come back on their own.
      C:InvalidateBook()
      Reresolve()
      C:QueueRebuild()

    end
  end

end)

function C:AddModule(fn) table.insert(C.modules, fn) end

SLASH_JUNKIECD1 = "/jcd"
SlashCmdList["JUNKIECD"] = function(msg)
  msg = (msg or ""):lower()
  if msg == "lock" then
    C.db.locked = true
    C:Rebuild()
  elseif msg == "unlock" then
    C.db.locked = false
    C:Rebuild()
  elseif msg == "debug" then
    local p = C:Profile()
    local set = C:ActiveSet() or p
    print("|cffde7230JunkieCD|r profile: " .. tostring(p and p.name)
      .. " main " .. tostring(set.mainCount) .. "/" .. tostring(set.mainEnabled)
      .. " sub " .. tostring(set.subCount) .. "/" .. tostring(set.subEnabled))
    C:Rebuild()
  elseif C.ToggleConfig then
    C:ToggleConfig()
  end

end
