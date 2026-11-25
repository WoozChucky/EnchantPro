-- EnchantPro - the trade: what the buyer handed over, what is owed, accepting, and the cast button.
local ADDON, ns = ...
local EP = ns.EP
local EQUIP = ns.EQUIP
local buyers = ns.buyers
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now
local shortName = ns.shortName
local money = ns.money
local spellName = ns.spellName
local bagCount = ns.bagCount
local itemName = ns.itemName
local itemIdOf = ns.itemIdOf
local equipLoc = ns.equipLoc
local matCost = ns.matCost
local feeFor = ns.feeFor
local fullFor = ns.fullFor
local canCast = ns.canCast
local toBox = ns.toBox
local whisper = ns.whisper
local thanksText = ns.thanksText
local fullName = ns.fullName
local ledgerAdd = ns.ledgerAdd
local buyerFor = ns.buyerFor

-- ---------------------------------------------------------------------------------------
-- trade


local function partnerName()
  local n = fullName("NPC")
  if n then return n end
  local fs = _G.TradeFrameRecipientNameText
  if fs and fs.GetText then
    n = safe(fs.GetText, fs)
    if type(n) == "string" then return n end
  end
  return nil
end

local function tradeBuyer()
  local t = EP.trade
  return t and t.name and buyers[string.lower(shortName(t.name) or "")] or nil
end

-- what is in the buyer's side of the trade: gold, mats (slots 1-6), the item to enchant (slot 7)
local function readTrade()
  local t = EP.trade
  if not t then return end
  t.money = safe(GetTargetTradeMoney) or 0
  t.items = {}
  for i = 1, 6 do
    local id = itemIdOf(safe(GetTradeTargetItemLink, i))
    if id then
      local ok, _, _, q = pcall(GetTradeTargetItemInfo, i)
      q = (ok and not isSecret(q) and type(q) == "number" and q > 0) and q or 1
      t.items[id] = (t.items[id] or 0) + q
    end
  end
  local link = safe(GetTradeTargetItemLink, 7)
  if type(link) == "string" then
    local ok, name, _, _, _, _, ench = pcall(GetTradeTargetItemInfo, 7)
    local loc = equipLoc(link)
    t.target = { link = link, name = (ok and not isSecret(name) and type(name) == "string") and name or nil, equip = loc,
      slots = loc and EQUIP[loc] or nil,
      ench = (ok and not isSecret(ench) and type(ench) == "string" and ench ~= "") and ench or nil }
  else
    t.target = nil
  end
  -- anyone who opens trade with an item to enchant, or hands gold or mats over, is a buyer
  if t.name and (t.target or t.money > 0 or next(t.items)) then
    local b = buyerFor(t.name)
    if b.new then b.new = nil; b.src, b.where = "trade", "trade" end
    if b.state ~= "done" then b.state = "trading" end
  end
end

local function fits(r, t)
  return not (t and t.target and t.target.slots) or t.target.slots[r.slot] == true
end

-- the enchants that fit the trade item (all you know without one), the buyer's ask and ad enchants first
local function candidates(t)
  local list = {}
  for _, r in ipairs(ns.knownList) do if fits(r, t) then list[#list + 1] = r end end
  return list
end

-- the enchant to cast now
function EP.plan()
  local t = EP.trade
  local manual = ns.DB.manual and ns.REC[ns.DB.manual]
  if manual and EP.manualAt and now() - EP.manualAt < 20 and fits(manual, t) then return manual end
  local b = t and tradeBuyer()
  if b and b.rec and ns.REC[b.rec] and fits(ns.REC[b.rec], t) then return ns.REC[b.rec] end
  if t and t.target and t.target.slots then
    local list = candidates(t)
    if b and b.slot then
      for _, r in ipairs(list) do if r.slot == b.slot and ns.DB.adList[r.id] then return r end end
    end
    if manual and fits(manual, t) then return manual end
    for _, r in ipairs(list) do if ns.DB.adList[r.id] then return r end end
    return list[1]
  end
  if manual then return manual end
  -- no trade: the newest buyer's enchant
  local newest
  for _, nb in pairs(buyers) do
    if nb.rec and ns.REC[nb.rec] and nb.state ~= "done" and (not newest or nb.at > newest.at) then newest = nb end
  end
  return newest and ns.REC[newest.rec] or nil
end

-- what the buyer owes for r: owed (nil: can't say), mode, the mats you put in (list), the mats you lack (list).
-- The mats count as theirs when they handed them over before (b.given) or put them in this trade.
local function quote(r, b, t)
  local given = {}
  for id, q in pairs(b and b.given or {}) do given[id] = (given[id] or 0) + q end
  for id, q in pairs(t and (t.final or t).items or {}) do given[id] = (given[id] or 0) + q end
  local missing, lack, gaveAny = {}, {}, false
  local value, known = 0, true
  for _, m in ipairs(r.reagents) do
    local g = given[m.id] or 0
    if g > 0 then gaveAny = true end
    if g < m.q then
      local q = m.q - g
      missing[#missing + 1] = { id = m.id, q = q }
      if bagCount(m.id) < m.q then lack[#lack + 1] = { id = m.id, q = m.q - bagCount(m.id) } end
      local c = matCost(m.id)
      if c then value = value + c * q else known = false end
    end
  end
  local fee, full = feeFor(r), fullFor(r)
  if #missing == 0 then return fee, "mats", missing, lack end
  if not gaveAny and full then return full, "full", missing, lack end
  if known then
    local owed = fee + value
    if full and owed > full then owed = full end
    return owed, "part", missing, lack
  end
  if full then return full, "full", missing, lack end
  return nil, "need", missing, lack
end

local function listText(list)
  local parts = {}
  for _, m in ipairs(list) do parts[#parts + 1] = m.q .. " " .. itemName(m.id) end
  return table.concat(parts, ", ")
end

local function itemsText(items)
  local parts = {}
  for id, q in pairs(items or {}) do parts[#parts + 1] = q .. " " .. itemName(id) end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

-- the trade window's line, and the panel's status (same words)
local function tradeLine()
  local t = EP.trade
  if not t then return nil end
  local b = tradeBuyer()
  local got = t.money or 0
  local who = t.name or "?"
  if not t.target then
    if got > 0 or next(t.items) then
      return who .. ": hands over " .. (next(t.items) and itemsText(t.items) or "") .. (got > 0 and ((next(t.items) and " + " or "") .. money(got)) or "")
    end
    return who .. ": no item in the bottom slot yet"
  end
  local r = EP.plan()
  if not r then return who .. ": |cffff4040no enchant of yours fits this item|r" end
  local owed, mode, _, lack = quote(r, b, t)
  local due = owed and math.max(0, owed - (b and b.paid or 0)) or nil
  local parts = { who .. ": |cffffffff" .. r.label .. "|r" }
  if mode == "mats" then parts[#parts + 1] = "their mats" .. CHECK
  elseif mode == "need" then parts[#parts + 1] = "|cffff4040mats missing - set a full price or /ep matcost|r"
  else parts[#parts + 1] = "your mats" end
  if #lack > 0 then parts[#parts + 1] = "|cffff4040you lack " .. listText(lack) .. "|r" end
  if due then
    if due <= 0 or got >= due then parts[#parts + 1] = CHECK .. " |cff40ff40" .. money(got) .. (due > 0 and " PAID" or "") .. "|r"
    else parts[#parts + 1] = CROSS .. " |cffff4040" .. money(got) .. " of " .. money(due) .. "|r" end
  end
  if t.castRec or (t.target and t.target.ench) then parts[#parts + 1] = "|cff40ff40enchanted|r" end
  return table.concat(parts, "  ")
end

-- where the sale stands, for the trade dock. nil without a trade.
-- flags: Asked (they asked in chat), Mats (all in your bags), Item (in the bottom slot, fits), Cast, Paid.
-- current: the first of Mats..Paid not done (Asked is only told, never waited for); done: how many are done.
function ns.dockState()
  local t = EP.trade
  if not t then return nil end
  local b = tradeBuyer()
  local r = EP.plan()
  local s = { buyer = b, rec = r, got = t.money or 0, mats = {}, flags = {} }
  s.flags[1] = b ~= nil and b.src ~= "trade"
  if r then
    for i, m in ipairs(r.reagents) do s.mats[i] = { id = m.id, have = bagCount(m.id), need = m.q } end
    s.flags[2] = canCast(r) and true or false
    local owed, mode = quote(r, b, t)
    s.mode = mode
    if owed then s.owed = math.max(0, owed - (b and b.paid or 0)) end
  else
    s.flags[2] = false
  end
  s.flags[3] = (r and t.target and t.target.slots and fits(r, t)) and true or false
  s.flags[4] = (t.castRec or (t.target and t.target.ench)) and true or false
  s.flags[5] = (s.owed and s.got >= s.owed) and true or false
  s.done = 0
  for i = 1, 5 do if s.flags[i] then s.done = s.done + 1 end end
  for i = 2, 5 do if not s.flags[i] then s.current = i; break end end
  return s
end

-- the trade dock shows the trade (UI/Dock.lua)
local function updateOverlay()
  if ns.updateDock then ns.updateDock() end
end

local function tradeDone()
  local t = EP.trade or EP.lastTrade
  if not t or t.counted then return end
  t.counted = true
  local snap = t.final or t
  local got = snap.money or 0
  local r = t.castRec and ns.REC[t.castRec]
  local b = t.name and buyers[string.lower(shortName(t.name) or "")]
  if not b and not r then return end
  if not b then b = buyerFor(t.name); b.new = nil end

  if r then
    local owed, mode, missing = quote(r, b, t)
    owed = owed or 0
    local pre = b.paid or 0
    local due = math.max(0, owed - pre)
    local tip = math.max(0, got - due)
    local mine = 0
    for _, m in ipairs(missing) do mine = mine + (matCost(m.id) or 0) * m.q end
    ledgerAdd({ k = "sale", n = b.name, en = r.label, mode = mode, p = owed, g = got, pre = pre, tip = tip, m = mine })
    -- what they handed over went into this enchant
    if b.given then
      for _, m in ipairs(r.reagents) do
        if b.given[m.id] then b.given[m.id] = math.max(0, b.given[m.id] - m.q); if b.given[m.id] == 0 then b.given[m.id] = nil end end
      end
    end
    b.paid, b.state, b.doneAt, b.rec = nil, "done", now(), nil
    if ns.letGo then ns.letGo(b) end
    if ns.DB.thanks then
      local line = thanksText(b, r.label, pre + got, tip, owed, owed)
      if ns.DB.thanksSay then toBox("/s " .. line) else whisper(b, line) end
    end
    say("|cff40ff40+" .. money(got) .. "|r from " .. b.name .. " for " .. r.label .. (tip > 0 and (" (" .. money(tip) .. " tip)") or "")
      .. (pre + got < owed and (" - |cffff4040" .. money(owed - pre - got) .. " short|r") or "") .. ".")
  else
    local items = snap.items or {}
    if got <= 0 and not next(items) then return end
    b.paid = (b.paid or 0) + got
    b.given = b.given or {}
    for id, q in pairs(items) do b.given[id] = (b.given[id] or 0) + q end
    ledgerAdd({ k = "pay", n = b.name, g = got, it = itemsText(items) })
    if b.state ~= "done" then b.state = "mats" end
    say(b.name .. " handed over " .. (next(items) and itemsText(items) or "") .. (got > 0 and ((next(items) and " and " or "") .. money(got)) or "")
      .. " - now the item.")
  end
  if EP.updateCast then EP.updateCast() end
  if ns.refresh then ns.refresh() end
end

function EP.accept()
  local tf = _G.TradeFrame
  if not (tf and tf:IsShown()) then return end
  local t = EP.trade
  local armed = EP.acceptArmed and now() - EP.acceptArmed < 3
  if t and not armed then
    local b = tradeBuyer()
    if t.target and not t.castRec and not t.target.ench then
      EP.acceptArmed = now()
      say("Not enchanted yet - press again to accept anyway.")
      return
    end
    local r = t.target and EP.plan()
    if r then
      local owed = quote(r, b, t)
      local due = owed and math.max(0, owed - (b and b.paid or 0)) or 0
      if due > 0 and (t.money or 0) < due then
        EP.acceptArmed = now()
        say("Only " .. money(t.money or 0) .. " of " .. money(due) .. " in the trade - press again to accept anyway.")
        return
      end
    end
  end
  EP.acceptArmed = nil
  pcall(AcceptTrade)
end

local function openTrade(b, unit)
  local ok = pcall(InitiateTrade, unit)
  b.tradeTry, b.tradeTries = now(), (b.tradeTries or 0) + 1
  return ok
end

-- ---------------------------------------------------------------------------------------
-- the cast button: always the enchant for the trade item, cast onto the trade's bottom slot

function EP.updateCast()
  if not ns.castBtn then return end
  if InCombatLockdown() then EP.castDirty = true; return end
  EP.castDirty = nil
  local r = EP.plan()
  EP.castRec = r
  if r then
    local name = spellName(r.id) or r.name
    local onTrade = EP.trade and EP.trade.target and rawget(_G, "TradeRecipientItem7ItemButton") ~= nil
    ns.castBtn:SetAttribute("type", "macro")
    ns.castBtn:SetAttribute("macrotext", "/cast " .. name .. (onTrade and "\n/click TradeRecipientItem7ItemButton" or ""))
    ns.castBtn:SetText(r.label .. (canCast(r) and "" or " |cffff4040(no mats)|r"))
    if ns.dockCast then
      ns.dockCast:SetAttribute("type", "macro")
      ns.dockCast:SetAttribute("macrotext", ns.castBtn:GetAttribute("macrotext"))
      ns.dockCast:SetText("Cast " .. r.label)
    end
  else
    ns.castBtn:SetAttribute("type", nil)
    ns.castBtn:SetAttribute("macrotext", nil)
    ns.castBtn:SetText(#ns.knownList == 0 and "Open your Enchanting window once" or "No enchant picked")
    if ns.dockCast then
      ns.dockCast:SetAttribute("type", nil)
      ns.dockCast:SetAttribute("macrotext", nil)
      ns.dockCast:SetText("No enchant picked")
    end
  end
end

local function cycle(step)
  local list = candidates(EP.trade)
  if #list == 0 then return end
  local idx = 0
  for i, r in ipairs(list) do if r == EP.castRec then idx = i end end
  idx = (idx - 1 + step) % #list + 1
  ns.DB.manual, EP.manualAt = list[idx].id, now()
  EP.updateCast()
  updateOverlay()
  if ns.refresh then ns.refresh() end
end

ns.partnerName = partnerName
ns.readTrade = readTrade
ns.quote = quote
ns.tradeLine = tradeLine
ns.updateOverlay = updateOverlay
ns.tradeDone = tradeDone
ns.openTrade = openTrade
ns.cycle = cycle
