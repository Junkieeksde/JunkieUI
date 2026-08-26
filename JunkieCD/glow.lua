--[[---------------------------------------------------------------------------
  JunkieCD - Glow effects

  Glows for aura icons. Cooldown icons use the client's own spell activation
  overlay engine instead (see bars.lua).

  Cost: animation driven through the widget animation system. Only the rotating
  style keeps a light OnUpdate, and only while that glow is actually shown.
-------------------------------------------------------------------------------]]
local C = JunkieCD

C.GLOW_TYPES = {
  { key = "none",  name = "No glow" },
  { key = "pixel", name = "Pulsing" },
  { key = "proc",  name = "Pixel glow" },
}

-- Glow art is deliberately warmer/yellower than the UI accent so it remains
-- readable over red, blue and green spell art.
local GLOW = { 1, 0.78, 0.16 }

-- 3.3.5: only frames have CreateAnimationGroup and Alpha animations use a
-- delta (SetChange), not a target value. Two ordered steps loop cleanly.
local function Pulse(frame, low, high, duration)
  frame:SetAlpha(high)
  local ok, ag = pcall(frame.CreateAnimationGroup, frame)
  if not ok or not ag then return nil end
  ag:SetLooping("REPEAT")
  local down = ag:CreateAnimation("Alpha")
  down:SetChange(low - high)
  down:SetDuration(duration)
  down:SetOrder(1)
  down:SetSmoothing("IN_OUT")
  local up = ag:CreateAnimation("Alpha")
  up:SetChange(high - low)
  up:SetDuration(duration)
  up:SetOrder(2)
  up:SetSmoothing("IN_OUT")
  return ag
end

local function BuildBase(frame, inset)
  local g = CreateFrame("Frame", nil, frame)
  g:SetPoint("TOPLEFT", -inset, inset)
  g:SetPoint("BOTTOMRIGHT", inset, -inset)
  g:SetFrameLevel(frame:GetFrameLevel() + 6)
  return g
end

-- Proc style: nine short accent lines that chase each other around the icon
-- edge. Hard-inset 2px lines so they scale with any icon size and cost
-- nothing but a light OnUpdate while it is visible.
local PROC_SEGMENTS = 9
local PROC_LOOP = 2.2          -- seconds for one lap around the icon

-- Match the pulse border exactly: a 2 frame-unit line, hard-inset by half its
-- thickness so nothing ever bleeds outside the icon.
local PROC_THICKNESS = 2

local PROC_INSET = PROC_THICKNESS * 0.5



local function PointOn(w, h, d, inset)
  inset = inset or 0
  local iw, ih = w - inset * 2, h - inset * 2
  if iw <= 0 or ih <= 0 then return 0, 0, "H" end
  local perim = 2 * (iw + ih)
  d = d % perim
  if d < iw then return d + inset, inset, "H" end
  d = d - iw
  if d < ih then return iw + inset, d + inset, "V" end
  d = d - ih
  if d < iw then return iw + inset - d, ih + inset, "H" end
  d = d - iw
  return inset, ih + inset - d, "V"
end

local function ProcUpdate(self, elapsed)
  self.elapsed = (self.elapsed or 0) + elapsed
  -- 10 Hz: the movement is interpolated against the accumulated elapsed time,
  -- so the loop takes exactly as long as before, at half the layout work
  -- (9 SetPoint + SetSize checks per tick and per active glow).
  if self.elapsed < 0.1 then return end
  elapsed = self.elapsed
  self.elapsed = 0

  local w, h = self:GetWidth() or 0, self:GetHeight() or 0
  local thickness, inset = PROC_THICKNESS, PROC_INSET
  if w <= thickness * 2 or h <= thickness * 2 then return end
  local iw, ih = w - inset * 2, h - inset * 2
  local perim = 2 * (iw + ih)
  self.offset = ((self.offset or 0) + elapsed * perim / PROC_LOOP) % perim
  local len = math.max(thickness * 2, perim / PROC_SEGMENTS * 0.5)
  for i = 1, PROC_SEGMENTS do
    local t = self.lines[i]
    local d = self.offset + (i - 1) * perim / PROC_SEGMENTS
    local x, y, axis = PointOn(w, h, d, inset)
    local sw, sh
    if axis == "H" then
      local lineLength = math.min(len, iw)
      x = math.max(inset + lineLength * 0.5, math.min(x, w - inset - lineLength * 0.5))
      sw, sh = lineLength, thickness
    else
      local lineLength = math.min(len, ih)
      y = math.max(inset + lineLength * 0.5, math.min(y, h - inset - lineLength * 0.5))
      sw, sh = thickness, lineLength
    end
    -- Size only changes when the icon is resized or the segment turns a
    -- corner; skipping the identical SetSize avoids a needless relayout.
    if t.jcdW ~= sw or t.jcdH ~= sh then
      t.jcdW, t.jcdH = sw, sh
      t:SetSize(sw, sh)
    end
    -- The anchor never changes, only its offset: SetPoint alone replaces the
    -- ClearAllPoints + SetPoint pair.
    t:SetPoint("CENTER", self, "TOPLEFT", x, -y)
  end
end

local function BuildProc(frame)
  local g = BuildBase(frame, 0)
  g:SetFrameLevel(frame:GetFrameLevel() + 10)
  g.lines = {}
  for i = 1, PROC_SEGMENTS do
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(GLOW[1], GLOW[2], GLOW[3], 1)
    t:SetBlendMode("ADD")
    t:SetSize(4, 1)
    g.lines[i] = t
  end
  g.offset = 0
  g.elapsed = 0
  g.Resize = function(self)
    self.elapsed = 0.1
    ProcUpdate(self, 0)
  end
  g:SetScript("OnUpdate", ProcUpdate)
  g:Hide()
  return g
end


-- Pulsing glow: one breathing border painted on the icon's own black border
-- and 1px inward, never outside the icon, and above it so the frame turns yellow.
local function BuildPixel(frame)
  local g = BuildBase(frame, 0)
  g:SetFrameLevel(frame:GetFrameLevel() + 10)
  g:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = C:Pixel(2) })
  g:SetBackdropBorderColor(GLOW[1], GLOW[2], GLOW[3], 1)
  g.anim = Pulse(g, 0.35, 1, 0.45)
  g:Hide()
  return g
end


local builders = { pixel = BuildPixel, proc = BuildProc }

function C:SetGlow(frame, kind, show)
  if not frame then return end
  if not show or not kind or kind == "none" then kind = nil end
  -- "glow" was removed; anything still stored in a profile falls back to pixel.
  if kind == "glow" then kind = "pixel" end

  if frame.jcdGlows then
    for k, g in pairs(frame.jcdGlows) do
      if k ~= kind then
        if g.anim then g.anim:Stop() end
        g:SetAlpha(1)
        g:Hide()
      end
    end
  end
  if not kind then return end

  frame.jcdGlows = frame.jcdGlows or {}
  local g = frame.jcdGlows[kind]
  if not g then
    local build = builders[kind]
    if not build then return end
    g = build(frame)
    frame.jcdGlows[kind] = g
  end
  if g.Resize then g:Resize() end
  if g:IsShown() then return end
  g:Show()
  if g.anim then g.anim:Play() end

end

-- Prewarm: build a glow's frames/textures ahead of time without showing them.
-- The very first proc in a fight would otherwise create nine textures and an
-- animation group mid-combat, which is exactly when a hitch is most visible.
function C:PrewarmGlow(frame, kind)
  if not frame or not kind or kind == "none" then return end
  if kind == "glow" then kind = "pixel" end
  local build = builders[kind]
  if not build then return end
  frame.jcdGlows = frame.jcdGlows or {}
  if frame.jcdGlows[kind] then return end
  local g = build(frame)
  if g.anim then g.anim:Stop() end
  g:Hide()
  frame.jcdGlows[kind] = g
end
