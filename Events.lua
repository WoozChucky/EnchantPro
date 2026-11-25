-- EnchantPro - start-up, events, the tick, key bindings and slash commands.
local ADDON, ns = ...
local EP = ns.EP
local ENCHANTING = ns.ENCHANTING
local DEFAULTS = ns.DEFAULTS
local buyers = ns.buyers
local isSecret = ns.isSecret
local say = ns.say
local now = ns.now
local money = ns.money
local parseMoney = ns.parseMoney
local itemName = ns.itemName
local itemIdOf = ns.itemIdOf
local rebuildKnown = ns.rebuildKnown
local feeFor = ns.feeFor
local fullFor = ns.fullFor
local clean = ns.clean
local analyze = ns.analyze
local findEnchant = ns.findEnchant
local readLinks = ns.readLinks
local dropRecipeItems = ns.dropRecipeItems
local channelIntent = ns.channelIntent
local whisperIntent = ns.whisperIntent
local chatBusy = ns.chatBusy
local openBox = ns.openBox
local adText = ns.adText
local fullName = ns.fullName
local unitFor = ns.unitFor
local near = ns.near
local newTotals = ns.newTotals
local ledgerSum = ns.ledgerSum
local net = ns.net
local dayStart = ns.dayStart
local request = ns.request
local partnerName = ns.partnerName
local readTrade = ns.readTrade
local quote = ns.quote
local tradeLine = ns.tradeLine
local updateOverlay = ns.updateOverlay
local tradeDone = ns.tradeDone
local openTrade = ns.openTrade
local cycle = ns.cycle
local onOff = ns.onOff
local buildPanel = ns.buildPanel

-- ---------------------------------------------------------------------------------------
-- the half-second tick

local function tick()
  if not ns.DB then return end
  local t = now()
  local tf = _G.TradeFrame
  local trading = EP.trade or (tf and tf:IsShown())

  -- buyers you can see: near or not, and trade with the first one in range
  for _, b in pairs(buyers) do
    b.unit = (b.state ~= "done" and not b.cant) and unitFor(b.name) or nil
    b.near = b.unit and near(b.unit) or false
  end
  if ns.DB.autoTrade and not EP.tradeBlocked and not trading and not InCombatLockdown() then
    for _, b in pairs(buyers) do
      if b.near and (b.state == "asked" or b.state == "mats") and (b.tradeTries or 0) < 3 and t - (b.tradeTry or 0) > 8 then
        openTrade(b, b.unit)
        break
      end
    end
  end

  ns.groupTick(t)

  -- drop old lines: asked and never came (10 min, unless they're in your group), done (2 min)
  for key, b in pairs(buyers) do
    if (b.state == "done" and t - (b.doneAt or 0) > 120 and not b.kickAt)
       or ((b.state == "asked") and t - b.at > 600 and not b.near and not b.inGroup) then
      buyers[key] = nil
    end
  end

  if #EP.boxQueue > 0 and t - (EP.boxAt or 0) > 1 and not chatBusy() then
    openBox(table.remove(EP.boxQueue, 1))
  end
  if EP.castDirty and not InCombatLockdown() then EP.updateCast() end
  if ns.refresh then ns.refresh() end
end

-- ---------------------------------------------------------------------------------------
-- events

local function initDB()
  EnchantProDB = EnchantProDB or {}
  ns.DB = EnchantProDB
  for k, v in pairs(DEFAULTS) do
    if ns.DB[k] == nil then ns.DB[k] = type(v) == "table" and {} or v end
  end
  ns.DB.ledger = ns.DB.ledger or {}
  ns.DB.totals = ns.DB.totals or newTotals()
  for k, v in pairs(newTotals()) do if ns.DB.totals[k] == nil then ns.DB.totals[k] = v end end
  -- up to 0.3.0 the fee started at 20s; now it starts at tips only. A fee you set yourself stays.
  if not ns.DB.tipsDefault then
    ns.DB.tipsDefault = true
    if ns.DB.fee == 2000 then
      ns.DB.fee = 0
      say("No fee by default now: tips only. /ep fee 20s brings the fee back; an enchant's own fee still counts.")
    end
  end
end

-- is this character an enchanter? true, false, or nil when the game can't say yet
local function isEnchanter()
  if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
    local ok, p1, p2 = pcall(GetProfessions)
    if not ok then return nil end
    for _, i in ipairs({ p1 or false, p2 or false }) do
      if i and not isSecret(i) then
        local ok2, _, _, _, _, _, _, line = pcall(GetProfessionInfo, i)
        if ok2 and line == ENCHANTING then return true end
      end
    end
    return false
  end
  return nil
end

local f = CreateFrame("Frame")
local function listen(ev) pcall(f.RegisterEvent, f, ev) end
listen("ADDON_LOADED")
listen("PLAYER_LOGIN")

local function registerAll()
  for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER",
    "TRADE_SHOW", "TRADE_CLOSED", "TRADE_MONEY_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_UPDATE",
    "UI_INFO_MESSAGE", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "GROUP_ROSTER_UPDATE", "CHAT_MSG_SYSTEM",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    listen(ev)
  end
  if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player") else listen("UNIT_SPELLCAST_SUCCEEDED") end
end

-- everything starts once the character is known to be an enchanter
function EP.start()
  if EP.started then return end
  EP.started, EP.off = true, nil
  rebuildKnown()
  buildPanel()
  ns.buildDock()
  ns.buildExtras()
  registerAll()
  EP.updateCast()
  C_Timer.NewTicker(0.5, tick)
  if #ns.knownList == 0 then
    say("Open your Enchanting window once so I learn your enchants. /ep help")
  else
    say("Ready: " .. #ns.knownList .. " enchants, " .. ns.feeTerms(ns.DB.fee) .. ". /ep help")
  end
end

local scanPending
local function scheduleScan()
  if scanPending then return end
  scanPending = true
  C_Timer.After(0.3, function() scanPending = nil; EP.scanProfession() end)
end

f:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
  if ev == "ADDON_LOADED" then
    if a1 == ADDON then initDB() end
  elseif ev == "PLAYER_LOGIN" then
    ns.myName = fullName("player") or ""
    local e = isEnchanter()
    if e then EP.start(); return end
    -- not (yet) an enchanter: off, but a profession learned or loaded later still starts it
    EP.off = true
    listen("SKILL_LINES_CHANGED")
    C_Timer.After(5, function() if not EP.started and isEnchanter() then EP.start() end end)
  elseif ev == "SKILL_LINES_CHANGED" then
    if not EP.started and isEnchanter() then EP.start() end
  elseif not EP.started then
    return
  elseif ev == "CHAT_MSG_CHANNEL" then
    if ns.DB.listen then
      local where = (not isSecret(a9) and type(a9) == "string" and a9) or (not isSecret(a4) and type(a4) == "string" and a4) or "chat"
      request(a2, a1, "chat", where, a12)
    end
  elseif ev == "CHAT_MSG_SAY" or ev == "CHAT_MSG_YELL" then
    if ns.DB.listen then request(a2, a1, "say", ev == "CHAT_MSG_SAY" and "say" or "yell", a12) end
  elseif ev == "CHAT_MSG_WHISPER" then
    request(a2, a1, "whisper", "whisper", a12)
  elseif ev == "TRADE_SHOW" then
    EP.trade = { name = partnerName(), money = 0, items = {} }
    -- trading with someone due to leave the group: they want more, they stay
    local pn = EP.trade.name and ns.shortName(EP.trade.name)
    local pb = pn and buyers[string.lower(pn)]
    if pb then pb.kickAt = nil end
    readTrade(); EP.updateCast(); updateOverlay(); ns.refresh()
  elseif ev == "TRADE_MONEY_CHANGED" or ev == "TRADE_TARGET_ITEM_CHANGED" or ev == "TRADE_UPDATE" then
    if EP.trade then readTrade() end
    EP.updateCast(); updateOverlay(); ns.refresh()
  elseif ev == "TRADE_ACCEPT_UPDATE" then
    local t = EP.trade
    if t then
      readTrade()
      -- both sides accepted: what is in the trade now is what changes hands
      if a1 == 1 and a2 == 1 then
        local items = {}
        for id, q in pairs(t.items) do items[id] = q end
        t.final = { money = t.money, items = items }
      end
    end
    updateOverlay(); ns.refresh()
  elseif ev == "TRADE_CLOSED" then
    if EP.trade then EP.lastTrade = EP.trade end
    EP.trade = nil
    for _, b in pairs(buyers) do if b.state == "trading" then b.state = b.given and "mats" or "asked" end end
    EP.updateCast(); updateOverlay(); ns.refresh()
  elseif ev == "GROUP_ROSTER_UPDATE" then
    ns.onRoster()
  elseif ev == "CHAT_MSG_SYSTEM" then
    ns.onSystem(a1)
  elseif ev == "UI_INFO_MESSAGE" then
    if a1 == ERR_TRADE_COMPLETE or a2 == ERR_TRADE_COMPLETE then tradeDone() end
  elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 == "player" and not isSecret(a3) and type(a3) == "number" and ns.REC[a3] and EP.trade then
      EP.trade.castRec = a3
      updateOverlay(); ns.refresh()
    end
  elseif ev == "PLAYER_REGEN_ENABLED" then
    if EP.castDirty then EP.updateCast() end
    EP.afterCombat()
    EP.dockAfterCombat()
    EP.extrasAfterCombat()
  elseif ev == "BAG_UPDATE_DELAYED" then
    EP.updateCast(); EP.enchantsRefresh(); updateOverlay(); ns.refresh()
  elseif ev == "TRADE_SKILL_SHOW" or ev == "TRADE_SKILL_LIST_UPDATE" or ev == "NEW_RECIPE_LEARNED" then
    scheduleScan()
  elseif ev == "ADDON_ACTION_BLOCKED" or ev == "ADDON_ACTION_FORBIDDEN" then
    if a1 == ADDON then
      local fn = tostring(a2)
      if string.find(fn, "InitiateTrade", 1, true) or string.find(fn, "UNKNOWN", 1, true) then
        EP.tradeBlocked = true
        say("The game does not let addons open trade by themselves here - click the buyer's line when they are near.")
      else
        say("The game blocked " .. fn .. ". Tell the author.")
      end
    end
  end
end)

-- ---------------------------------------------------------------------------------------
-- keys and slash commands

BINDING_HEADER_ENCHANTPRO = "EnchantPro"
BINDING_NAME_ENCHANTPRO_AD = "Post ad"
_G["BINDING_NAME_CLICK EnchantProCastButton:LeftButton"] = "Cast enchant"
BINDING_NAME_ENCHANTPRO_ACCEPT = "Accept trade"
BINDING_NAME_ENCHANTPRO_PANEL = "Show / hide panel"

function EnchantPro_PostAd() if EP.started then EP.postAd() end end
function EnchantPro_AcceptTrade() if EP.started then EP.accept() end end
function EnchantPro_TogglePanel() if EP.started then EP.togglePanel() end end

local HELP = {
  "/ep - show / hide the panel",
  "/ep enchants - your enchants: fee, full price, mats, ad ticks (or the Enchants button)",
  "/ep fee 25s - a fee with the buyer's mats, for every enchant without its own (0: no fee, tips only - the default)",
  "/ep price +7 sta bracer 30s 1g - one enchant's fee and full price (full: off to stop offering it)",
  "/ep matcost <item id or name> 5s - what a mat costs you (else Auctionator's price). off - forget it",
  "/ep messages - edit the ad, replies and thank-you (or the Messages button)",
  "/ep ad - show the ad.  /ep cd 90 - seconds between ads",
  "/ep listen | reply | invite | trade | kick | thanks | whisper | sound - turn one on / off",
  "/ep ledger - the ledger window.  /ep stats - today / 7 days / all time in chat.  /ep ledger reset",
  "/ep test <line> - would this chat line count as a buyer, and for which enchant?",
  "/ep compact - fold the window to one line (again: back) - /ep minimap - hide or show the minimap button",
  "Keys: Game Menu > Key Bindings > EnchantPro (Post ad, Cast enchant, Accept trade).",
}

local SWITCHES = { listen = "listen", reply = "reply", invite = "invite", trade = "autoTrade", kick = "autoKick",
  thanks = "thanks", whisper = "whisper", sound = "sound" }

SLASH_ENCHANTPRO1 = "/ep"
SLASH_ENCHANTPRO2 = "/enchantpro"
SlashCmdList.ENCHANTPRO = function(msg)
  if not EP.started then say("EnchantPro only works on an enchanter."); return end
  msg = strtrim(msg or "")
  local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  if cmd == "" then
    EP.togglePanel()
  elseif cmd == "help" then
    for _, l in ipairs(HELP) do say(l) end
  elseif cmd == "enchants" or cmd == "list" then
    EP.toggleEnchants()
  elseif cmd == "fee" then
    local c = parseMoney(rest)
    if not c then say("Fee now " .. money(ns.DB.fee) .. ". Write it like /ep fee 25s."); return end
    ns.DB.fee = c
    say("Fee: " .. (c == 0 and "none, tips only" or money(c)) .. ".")
    EP.enchantsRefresh(); ns.refresh()
  elseif cmd == "price" then
    -- the last one or two words are money (or "off"), the rest names the enchant
    local words = {}
    for w in string.gmatch(rest, "%S+") do words[#words + 1] = w end
    local prices = {}
    while #words > 0 and #prices < 2 and (parseMoney(words[#words]) or string.lower(words[#words]) == "off") do
      table.insert(prices, 1, table.remove(words))
    end
    local r = #words > 0 and findEnchant(analyze(clean(table.concat(words, " "))))
    if not r or #prices == 0 then say("Write it like /ep price +7 sta bracer 30s 1g."); return end
    local fee = parseMoney(prices[1])
    if fee then ns.DB.fees[r.id] = (fee ~= ns.DB.fee) and fee or nil end
    if prices[2] then
      local full = parseMoney(prices[2])
      ns.DB.fulls[r.id] = (full and full > 0) and full or nil
    end
    say(r.label .. ": fee " .. money(feeFor(r)) .. ", full " .. (fullFor(r) and money(fullFor(r)) or "not offered") .. ".")
    EP.enchantsRefresh()
  elseif cmd == "matcost" then
    local what, val = string.match(rest, "^(.-)%s+(%S+)$")
    if not what then say("Write it like /ep matcost Strange Dust 5s."); return end
    local id = tonumber(what) or itemIdOf(what)
    if not id then
      local lw = string.lower(what)
      for iid, n in pairs(ns.DB.itemNames) do if string.lower(n) == lw then id = iid end end
    end
    if not id then say("Unknown mat - use the item id, a link, or the name of a mat one of your enchants takes."); return end
    if string.lower(val) == "off" then ns.DB.matCost[id] = nil; say(itemName(id) .. ": back to Auctionator's price."); return end
    local c = parseMoney(val)
    if not c then say("Write the cost like 5s."); return end
    ns.DB.matCost[id] = c
    say(itemName(id) .. ": " .. money(c) .. " each.")
  elseif cmd == "compact" then
    EP.setCompact(not (ns.DB.ui and ns.DB.ui.compact))
  elseif cmd == "minimap" then
    EP.toggleMinimap()
  elseif cmd == "messages" or cmd == "msg" then
    EP.toggleMessages()
  elseif cmd == "ad" then
    say("Ad: " .. adText())
  elseif cmd == "cd" then
    local n = tonumber(rest)
    if not n or n < 15 then say("Seconds between ads, 15 or more."); return end
    ns.DB.adCooldown = math.floor(n)
    say("Ads every " .. ns.DB.adCooldown .. " s at most.")
    ns.refresh()
  elseif SWITCHES[cmd] then
    local k = SWITCHES[cmd]
    ns.DB[k] = not ns.DB[k]
    if k == "autoTrade" then EP.tradeBlocked = nil end
    say(cmd .. ": " .. onOff(ns.DB[k]))
    ns.refresh()
  elseif cmd == "ledger" or cmd == "stats" then
    if string.lower(rest) == "reset" then
      if not (EP.resetArmed and now() - EP.resetArmed < 10) then
        EP.resetArmed = now()
        say("|cffff4040This deletes the whole ledger.|r Type /ep ledger reset again within 10 s to do it.")
        return
      end
      EP.resetArmed = nil
      EP.resetLedger()
      return
    end
    if cmd == "ledger" then EP.toggleLedger(); return end
    for _, p in ipairs({ { "Today", ledgerSum(dayStart()) }, { "7 days", ledgerSum(time() - 7 * 86400) }, { "All time", ledgerSum(nil) } }) do
      local T = p[2]
      say(string.format("%s: net %s%s = %s in (%s tips) - %s my mats. %d enchants (%d their mats), %s short.",
        p[1], net(T) < 0 and "-" or "", money(math.abs(net(T))), money(T.income), money(T.tips),
        money(T.matsCost), T.sales, T.theirMats, money(T.short)))
    end
  elseif cmd == "test" then
    local raw = dropRecipeItems(rest)
    local links = readLinks(raw)
    local lower = clean(raw)
    local ok, r, _, cu = channelIntent(lower, links)
    local wok, wr, _, wu = whisperIntent(lower, links)
    local function what(x, u)
      return type(x) == "table" and x.label or (u and (u .. " - not yours")) or "no enchant of yours"
    end
    say("In chat: " .. (ok and ("|cff40ff40buyer|r, " .. what(r, cu))
      or (r == "seller" and "|cffff8040an enchanter selling|r" or "|cff808080not a buyer|r"))
      .. ".  As a whisper: " .. (wok == "price" and "price question" or wok == "mats" and ("mats question, " .. what(wr))
        or wok and ("|cff40ff40buyer|r, " .. what(wr, wu)) or "|cff808080ignored|r") .. ".")
  else
    say("Unknown command. /ep help")
  end
end

-- for the offline tests
EP._test = { letGo = ns.letGo, readLinks = readLinks, dropRecipeItems = dropRecipeItems, channelIntent = channelIntent, whisperIntent = whisperIntent, analyze = analyze, findEnchant = findEnchant,
  clean = clean, parseMoney = parseMoney, money = money, quote = quote, buyers = buyers, REC = function() return ns.REC end,
  knownList = function() return ns.knownList end, tradeLine = tradeLine, cycle = cycle }
