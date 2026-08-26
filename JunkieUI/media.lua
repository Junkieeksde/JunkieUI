--[[---------------------------------------------------------------------------
  JunkieUI - Media

  Font and statusbar texture registry. Paths are validated once at load so a
  missing or corrupt file silently falls back instead of erroring later.

  Cost: one throwaway fontstring per candidate font at load, nothing after.

  Sections:
    1. Bar textures
    2. Registered bars
-------------------------------------------------------------------------------]]
local J = JunkieUI

J.FALLBACK_BAR = "Interface\\Buttons\\WHITE8X8"
J.statusbar = J.FALLBACK_BAR

J.fonts = {
  { key = "expressway", name = "Expressway", path = "Interface\\AddOns\\JunkieUI\\media\\Expressway.ttf" },
  { key = "avantgarde", name = "Avant Garde Bold", path = "Interface\\AddOns\\JunkieUI\\media\\AvantGardeLT-Bold.otf" },
}

local function Valid(path)
  local test = UIParent:CreateFontString(nil, "OVERLAY")
  local ok = test:SetFont(path, 12)
  test:Hide()
  return ok and true or false
end

function J:ApplyFont()
  local choice = (J.db and J.db.fontChoice) or "expressway"
  local path
  for _, f in ipairs(J.fonts) do
    if f.key == choice then path = f.path end
  end
  path = path or J.fonts[1].path
  if not Valid(path) then
    path = Valid(J.fonts[1].path) and J.fonts[1].path or STANDARD_TEXT_FONT
  end
  J.font = path
  return J.font
end

-- Safe default before saved variables load.
J.font = Valid(J.fonts[1].path) and J.fonts[1].path or STANDARD_TEXT_FONT

-- ---------------------------------------------------------------------------
-- 1. Bar textures
-- ---------------------------------------------------------------------------
-- Everything LibSharedMedia knows about, plus the textures Ascension ships
-- inside its own interface files (they are not always registered with LSM).
local BUILTIN = {
  { name = "Flat",      path = "Interface\\Buttons\\WHITE8X8" },
  { name = "Smooth v2", path = "Interface\\SharedMedia\\statusbar\\Smoothv2" },
  { name = "Smooth",    path = "Interface\\SharedMedia\\statusbar\\Smooth" },
  { name = "Minimalist", path = "Interface\\SharedMedia\\statusbar\\Minimalist" },
  { name = "Blizzard",  path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { name = "Blizzard Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { name = "Otravi",    path = "Interface\\SharedMedia\\statusbar\\Otravi" },
  { name = "Glaze",     path = "Interface\\SharedMedia\\statusbar\\Glaze" },
  { name = "Charcoal",  path = "Interface\\SharedMedia\\statusbar\\Charcoal" },
}

-- Textures are file paths; a missing file simply draws nothing, so each
-- candidate is probed once on a throwaway texture before it is offered.
local probe
local function TextureExists(path)
  if not path or path == "" then return false end
  probe = probe or UIParent:CreateTexture(nil, "BACKGROUND")
  probe:SetTexture(nil)
  probe:SetTexture(path)
  local got = probe:GetTexture()
  probe:SetTexture(nil)
  return got and true or false
end

function J:BuildTextureList()
  local list, seen = {}, {}
  local function Add(name, path)
    if not name or not path or seen[string.lower(name)] then return end
    if not TextureExists(path) then return end
    seen[string.lower(name)] = true
    list[#list + 1] = { key = name, name = name, path = path }
  end

  for _, t in ipairs(BUILTIN) do Add(t.name, t.path) end

  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then
    local hash = LSM:HashTable("statusbar")
    if hash then
      for name, path in pairs(hash) do Add(name, path) end
    end
  end

  table.sort(list, function(a, b) return a.name < b.name end)
  J.textures = list
  return list
end

function J:TexturePath(key)
  for _, t in ipairs(J.textures or {}) do
    if t.key == key then return t.path end
  end
  return J.FALLBACK_BAR
end

-- ---------------------------------------------------------------------------
-- 2. Registered bars
-- ---------------------------------------------------------------------------
J.bars = {}

local function Paint(bar)
  if not bar or not bar.SetStatusBarTexture then return end
  local r, g, b, a = bar:GetStatusBarColor()
  bar:SetStatusBarTexture(J.statusbar)
  if r then bar:SetStatusBarColor(r, g, b, a) end
end

function J:RegisterBar(bar)
  if not bar then return bar end
  J.bars[#J.bars + 1] = bar
  Paint(bar)
  return bar
end

function J:ApplyBarTexture()
  if not J.textures then J:BuildTextureList() end
  local key = J.db and J.db.barTexture
  local path = key and J:TexturePath(key) or J.FALLBACK_BAR
  if not TextureExists(path) then path = J.FALLBACK_BAR end
  J.statusbar = path

  for i = #J.bars, 1, -1 do
    local bar = J.bars[i]
    if bar and bar.SetStatusBarTexture then Paint(bar) else table.remove(J.bars, i) end
  end
  -- The cooldown manager paints its own power bars and combo points.
  if JunkieCD and JunkieCD.ApplyBarTexture then JunkieCD:ApplyBarTexture(path) end
  return path
end
