-- EnchantPro - the trade dock: a panel beside the trade window with the sale's steps, the mats, the payment
-- and a Cast button of its own.
local ADDON, ns = ...
local EP = ns.EP
local say = ns.say
local safe = ns.safe
local money = ns.money
local itemName = ns.itemName
local Kit = ns.Kit

local STEPS = { "Asked", "Mats", "Item", "Cast", "Paid" }
local MAX_MATS = 4
local dock

local function itemIcon(id)
  if C_Item and C_Item.GetItemIconByID then return safe(C_Item.GetItemIconByID, id) end
  return safe(GetItemIcon, id)
end

local function build()
  local tf = _G.TradeFrame
  if dock or not tf then return end
  dock = CreateFrame("Frame", "EnchantProDock", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  dock:SetSize(250, 290)
  dock:SetPoint("TOPLEFT", tf, "TOPRIGHT", 2, 0)
  dock:SetFrameStrata("HIGH")
  Kit.backdrop(dock, 0.95, true)

  dock.title = dock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dock.title:SetPoint("TOPLEFT", 16, -16)
  dock.title:SetPoint("RIGHT", -16, 0)
  dock.title:SetJustifyH("LEFT")
  dock.sub = dock:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  dock.sub:SetPoint("TOPLEFT", dock.title, "BOTTOMLEFT", 0, -2)
  dock.sub:SetPoint("RIGHT", -16, 0)
  dock.sub:SetJustifyH("LEFT")

  dock.steps = Kit.steps(dock, STEPS)
  dock.steps:SetPoint("TOPLEFT", 16, -52)
  dock.steps:SetPoint("RIGHT", -16, 0)
  dock.steps:SetWidth(218)

  local matsHead = dock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  matsHead:SetPoint("TOPLEFT", 16, -94)
  matsHead:SetText("MATS IN YOUR BAGS")
  dock.mats = {}
  for i = 1, MAX_MATS do
    local ic = Kit.icon(dock, 16)
    ic:SetPoint("TOPLEFT", 16, -110 - (i - 1) * 18)
    local name = dock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    name:SetJustifyH("LEFT")
    local count = dock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("RIGHT", dock, "RIGHT", -16, 0)
    count:SetPoint("TOP", ic, "TOP", 0, -2)
    dock.mats[i] = { icon = ic, name = name, count = count }
  end

  local payHead = dock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  payHead:SetPoint("TOPLEFT", 16, -186)
  payHead:SetText("PAYMENT")
  dock.pay = Kit.progress(dock)
  dock.pay:SetPoint("TOPLEFT", 16, -200)
  dock.pay:SetPoint("RIGHT", -16, 0)
  dock.pay:SetWidth(218)
  dock.payText = dock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dock.payText:SetPoint("TOPLEFT", 16, -214)
  dock.payText:SetPoint("RIGHT", -16, 0)
  dock.payText:SetJustifyH("LEFT")

  -- its own secure Cast button: the same macro as the panel's (EP.updateCast sets both)
  dock.icon = Kit.icon(dock, 40)
  dock.icon:SetPoint("BOTTOMLEFT", 16, 16)
  ns.dockCast = CreateFrame("Button", "EnchantProDockCast", dock, "UIPanelButtonTemplate,SecureActionButtonTemplate")
  ns.dockCast:SetPoint("TOPLEFT", dock.icon, "TOPRIGHT", 6, 0)
  ns.dockCast:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -16, 16)
  local down = safe(GetCVarBool, "ActionButtonUseKeyDown")
  ns.dockCast:RegisterForClicks(down and "AnyDown" or "AnyUp")
  ns.dockCast:SetText("Cast")
  dock:Hide()
end

local function setShown(show)
  if not dock then return end
  if dock:IsShown() == show then return end
  if InCombatLockdown() then EP.dockDirty = true; return end   -- it holds a secure button
  if show then dock:Show() else dock:Hide() end
end

-- fill the dock from the trade; shown while a trade is open
local function updateDock()
  build()
  if not dock then return end
  local s = ns.dockState()
  if not s then setShown(false); return end
  local r = s.rec
  dock.title:SetText(r and r.label or "|cffff4040No enchant of yours fits|r")
  local who = s.buyer and s.buyer.name or "?"
  local modeText = s.mode == "mats" and "their mats" or s.mode == "full" and "your mats"
    or s.mode == "part" and "part their mats" or s.mode == "need" and "|cffff4040no price for your mats|r" or ""
  dock.sub:SetText(who .. (modeText ~= "" and (" - " .. modeText) or ""))
  dock.steps:Set(s.flags, s.current)

  for i, row in ipairs(dock.mats) do
    local m = s.mats[i]
    if m then
      row.icon:SetIcon(itemIcon(m.id)); row.icon:Show()
      row.name:SetText(itemName(m.id))
      row.count:SetText((m.have >= m.need and "|cff40ff40" or "|cffff4040") .. m.have .. "/" .. m.need .. "|r")
    else
      row.icon:Hide(); row.name:SetText(""); row.count:SetText("")
    end
  end

  if s.owed == 0 then
    -- no fee: whatever they give is a tip
    dock.pay:Set(1)
    dock.payText:SetText(s.got > 0 and ("|cff40ff40Tip: " .. money(s.got) .. "|r") or "No fee - |cff40ff40tips welcome|r")
  elseif s.owed then
    local frac = s.owed > 0 and s.got / s.owed or 1
    if s.got >= s.owed then dock.pay:Set(1) else dock.pay:Set(frac, 0.9, 0.25, 0.25) end
    dock.payText:SetText(money(s.got) .. " of " .. money(s.owed)
      .. (s.got >= s.owed and ("  |cff40ff40PAID|r" .. (s.got > s.owed and (" +" .. money(s.got - s.owed) .. " tip") or "")) or ""))
  else
    dock.pay:Set(0)
    dock.payText:SetText(money(s.got) .. " in trade - |cff808080price unknown|r")
  end

  dock.icon:SetIcon(r and ns.spellIcon(r.id) or nil)
  if ns.dockCast then Kit.pulse(ns.dockCast, s.current == 4) end
  setShown(true)
end

function EP.dockAfterCombat()
  if EP.dockDirty then EP.dockDirty = nil; updateDock() end
end

ns.buildDock = build
ns.updateDock = updateDock
