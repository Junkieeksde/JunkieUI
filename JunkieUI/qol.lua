-- Quality of life: auto repair
local J = JunkieUI

local f = CreateFrame("Frame")

local function Money(copper)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out = ""
  if g > 0 then out = out .. g .. "|cffffd700g|r " end
  if g > 0 or s > 0 then out = out .. s .. "|cffc7c7cfs|r " end
  return out .. c .. "|cffeda55fc|r"
end

local function AutoRepair()
  if not J.db or not J.db.autoRepair then return end
  if not CanMerchantRepair or not CanMerchantRepair() then return end

  local cost, canRepair = GetRepairAllCost()
  if not canRepair or not cost or cost <= 0 then return end

  if GetMoney() >= cost then
    RepairAllItems()
    print("|cff4fc3f7JunkieUI:|r repaired for " .. Money(cost))
  else
    print("|cff4fc3f7JunkieUI:|r not enough money to repair (" .. Money(cost) .. ")")
  end
end

J:AddModule(function()
  f:RegisterEvent("MERCHANT_SHOW")
  f:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then AutoRepair() end
  end)
end)

-- Blizzard bug guard: StaticPopup_OnUpdate re-formats the popup text every
-- frame with text_arg1/text_arg2. If the value is nil (e.g. a resurrect offer
-- whose caster name is not available yet) SetFormattedText errors on repeat.
-- Backfill missing arguments so the popup shows instead of spamming errors.
local function FixPopupArgs(dialog)
  if not dialog or not dialog.which then return end
  local info = StaticPopupDialogs[dialog.which]
  if not info then return end
  local body = info.text
  if type(body) ~= "string" then return end
  local _, count = string.gsub(body, "%%s", "")
  if count < 1 then return end
  local t = dialog.text or _G[dialog:GetName() .. "Text"]
  if not t then return end
  if t.text_arg1 == nil then t.text_arg1 = UNKNOWN or "Unknown" end
  if count > 1 and t.text_arg2 == nil then t.text_arg2 = UNKNOWN or "Unknown" end
end

J:AddModule(function()
  if type(StaticPopup_Show) == "function" then
    hooksecurefunc("StaticPopup_Show", function(which)
      for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local d = _G["StaticPopup" .. i]
        if d and d:IsShown() and d.which == which then FixPopupArgs(d) end
      end
    end)
  end
  local g = CreateFrame("Frame")
  g:RegisterEvent("RESURRECT_REQUEST")
  g:SetScript("OnEvent", function()
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
      local d = _G["StaticPopup" .. i]
      if d and d:IsShown() then FixPopupArgs(d) end
    end
  end)
end)
