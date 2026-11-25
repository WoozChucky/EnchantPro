-- EnchantPro - the minimap button, the compact bar and the new-buyer pop-up (widgets from UI/Kit.lua).
local ADDON, ns = ...
local EP = ns.EP
local buyers = ns.buyers
local say = ns.say
local Kit = ns.Kit

local ICON = "Interface\\Icons\\Trade_Engraving"
local mm, bar, toast

local function ui()
  ns.DB.ui = ns.DB.ui or {}
  return ns.DB.ui
end

-- buyers waiting: listed, not done, an enchant you have
local function waiting()
  local n, near = 0, 0
  for _, b in pairs(buyers) do
    if not b.cant and b.state ~= "done" then
      n = n + 1
      if b.near then near = near + 1 end
    end
  end
  return n, near
end
ns.waitingBuyers = waiting

function EP.toggleMinimap()
  local hidden = not ui().minimapHidden
  if mm then mm:SetHidden(hidden) else ui().minimapHidden = hidden end
  say("Minimap button " .. (hidden and "hidden - /ep minimap brings it back." or "shown."))
end

-- fold the window to the bar, or back. The window holds the Cast button, so this waits for combat to end.
function EP.setCompact(on)
  if InCombatLockdown() then
    say("The window " .. (on and "folds" or "opens") .. " when combat ends.")
    EP.pendingCompact = on
    return
  end
  ui().compact = on and true or false
  if on then
    if ns.panel then ns.panel:Hide() end
    bar:Show()
  else
    bar:Hide()
    if ns.panel then ns.panel:Show(); ns.DB.shown = true end
  end
  ns.refresh()
end

function EP.extrasAfterCombat()
  if EP.pendingCompact ~= nil then
    local on = EP.pendingCompact
    EP.pendingCompact = nil
    EP.setCompact(on)
  end
end

-- a buyer just showed up (Buyers.lua). Enchants you don't have don't pop up.
function ns.onNewBuyer(b)
  if not toast or b.cant then return end
  local rec = b.rec and ns.REC[b.rec]
  toast:Pop(b.key, rec and ns.spellIcon(rec.id) or ICON,
    "|cff" .. Kit.classHex(b.class) .. b.name .. "|r wants an enchant",
    (rec and rec.label or "an enchant") .. "  |cff808080" .. (b.where or b.src or "") .. "|r")
end

-- the badge and the bar's line, whether the window is open or not (ns.refresh calls this)
function ns.updateExtras()
  local n, near = waiting()
  if mm then mm:SetBadge(n) end
  if bar then bar.text:SetText(n .. " buyers · " .. near .. " in range") end
end

function ns.buildExtras()
  mm = Kit.minimapButton("EnchantProMinimapButton", ICON, ui(), function(mouse)
    if mouse == "RightButton" then EP.postAd() else EP.togglePanel() end
  end, function()
    local n, near = waiting()
    return "EnchantPro\n|cffffffff" .. n .. " buyers, " .. near .. " in range|r\n"
      .. "|cff808080Click: window - Right-click: post the ad - Drag: move|r"
  end)
  bar = Kit.compactBar("EnchantProCompact", ICON, ns.frameSave("compact"), "Post ad",
    function() EP.postAd() end, function() EP.setCompact(false) end)
  toast = Kit.toast("EnchantProToast", 6, function() EP.showTab("buyers") end)
  if ui().compact then
    if ns.panel then ns.panel:Hide() end
    bar:Show()
  end
  ns.updateExtras()
end
