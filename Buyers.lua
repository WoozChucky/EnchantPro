-- EnchantPro - buyers: answering what they ask in chat (and inviting them, Party.lua).
local ADDON, ns = ...
local EP = ns.EP
local SLOT = ns.SLOT
local buyers = ns.buyers
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now
local shortName = ns.shortName
local money = ns.money
local playSound = ns.playSound
local feeFor = ns.feeFor
local fullFor = ns.fullFor
local matsText = ns.matsText
local clean = ns.clean
local firstSlot = ns.firstSlot
local readLinks = ns.readLinks
local dropRecipeItems = ns.dropRecipeItems
local channelIntent = ns.channelIntent
local whisperIntent = ns.whisperIntent
local whisper = ns.whisper
local replyText = ns.replyText
local askText = ns.askText
local groupUnit = ns.groupUnit
local invite = ns.invite
local wantsInvite = ns.wantsInvite

-- ---------------------------------------------------------------------------------------
-- buyers. state: asked (in chat) -> mats (handed mats / gold over) -> done; "trading" while a trade is open

local function buyerFor(sender)
  local name = shortName(sender)
  if not name or name == "" then return nil end
  local key = string.lower(name)
  local b = buyers[key]
  if not b then
    b = { key = key, name = name, full = sender, state = "asked", at = now() }
    buyers[key] = b
    b.new = true
  end
  return b
end

local function sayPrices(b)
  local list = {}
  for _, r in ipairs(ns.knownList) do
    if ns.DB.adList[r.id] and #list < 4 then
      local fee = feeFor(r)
      list[#list + 1] = r.label .. " " .. (fee > 0 and money(fee) or "free") .. (fullFor(r) and ("/" .. money(fullFor(r))) or "")
    end
  end
  whisper(b, "Your mats, " .. ns.feeTerms(ns.DB.fee) .. " for most enchants"
    .. (#list > 0 and (" (" .. table.concat(list, ", ") .. ")") or "") .. ". Which one do you need?")
end

-- someone asked for an enchant (src = "whisper", "chat" or "say")
-- guid: the chat event's sender GUID, for the class colour
local function request(sender, text, src, where, guid)
  if isSecret(sender) or isSecret(text) or type(sender) ~= "string" or type(text) ~= "string" then return end
  local name = shortName(sender)
  if not name or string.lower(name) == string.lower(ns.myName) then return end
  local key = string.lower(name)
  if ns.DB.blocked and ns.DB.blocked[key] then return end
  local typed = text   -- as they wrote it, for the row's tooltip
  if src ~= "whisper" and EP.sellers[key] and now() - EP.sellers[key] < 3600 then return end
  text = dropRecipeItems(text)
  local links = readLinks(text)
  local lower = clean(text)
  local intent, r, a, unknown
  if src == "whisper" then
    intent, r, a, unknown = whisperIntent(lower, links)
  else
    intent, r, a, unknown = channelIntent(lower, links)
  end
  if not intent then
    -- an enchanter advertising: not a buyer for the next hour, and off the list if a line of theirs got there
    if r == "seller" then
      EP.sellers[key] = now()
      local old = buyers[key]
      if old and old.src ~= "whisper" and old.state == "asked" then buyers[key] = nil; if ns.refresh then ns.refresh() end end
    end
    return
  end

  if intent == "price" then sayPrices(buyers[string.lower(name)] or { name = name, full = sender }); return end
  if intent == "mats" and r then
    whisper(buyers[string.lower(name)] or { name = name, full = sender }, r.label .. " takes " .. matsText(r) .. ".")
    if not buyers[string.lower(name)] then return end
  end

  local b = buyerFor(sender)
  local t = now()
  if b.state == "done" and t - (b.doneAt or 0) < 60 then return end
  if b.state == "done" then b.state, b.n, b.wants, b.rec = "asked", nil, nil, nil end   -- a new order, at the back
  local changed = false
  if r then
    b.cant = nil
    changed = ns.addWant(b, r)
  elseif (unknown or a.effect) and not b.rec then
    b.cant, b.want = true, unknown      -- asks for an enchant you don't have
  elseif a.anySlot then
    b.slot = firstSlot(a)
  end
  b.at, b.src, b.where = t, src, where
  -- what they typed and what it was read as, so a wrong match can be seen on hover: the last 5 lines
  ns.Kit.noteSaid(b, typed, where or src, r and r.label or nil,
    not r and type(unknown) == "string" and unknown ~= "" and unknown or nil)
  ns.enqueue(b)
  if not b.class and type(guid) == "string" and not isSecret(guid) and guid ~= "" then
    local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(cls) == "string" then b.class = cls end
  end
  b.inGroup = groupUnit(b.name) ~= nil or nil
  local invited = wantsInvite(b, src) and invite(b)
  local inv = invited and " Group invite sent." or ""
  -- the first answer tells them their place, when someone is ahead of them
  local p = not b.replied and not b.asked and ns.place(b)
  if p and p >= 2 then inv = inv .. " You're #" .. p .. " in the queue." end

  if b.new then
    b.new = nil
    playSound()
    if ns.onNewBuyer then ns.onNewBuyer(b) end
    say((b.cant and "|cff808080Buyer|r " or "|cff40ff40Buyer|r ") .. name .. " - "
      .. (r and r.label or b.want or b.slot and SLOT[b.slot].label or "an enchant") .. " (" .. (where or src) .. ")"
      .. (b.cant and " - |cff808080you don't have that enchant.|r" or "."))
  end

  if ns.DB.reply and intent ~= "mats" then
    if r and (changed or not b.replied) then
      if whisper(b, replyText(b, r) .. inv) then b.replied = true end
    elseif b.cant and src == "whisper" and not b.sorry then
      b.sorry = true
      whisper(b, "Sorry, I don't have that enchant.")
    elseif not r and not b.cant and not b.asked then
      b.asked = true
      whisper(b, askText(b) .. inv)
    end
  end
  if EP.updateCast then EP.updateCast() end
  if ns.refresh then ns.refresh() end
end

ns.buyerFor = buyerFor
ns.request = request

-- blocked characters: off the list now, never listed or answered again (shift-right-click, /ep block)
local function block(name)
  name = strtrim(name or "")
  if name == "" then return end
  local short = shortName(name) or name
  local key = string.lower(short)
  local b = buyers[key]
  ns.DB.blocked[key] = b and b.name or short
  if b then
    if b.inGroup and ns.kick then ns.kick(b) end
    buyers[key] = nil
  end
  say(ns.DB.blocked[key] .. " blocked - never listed again. /ep unblock " .. ns.DB.blocked[key] .. " to undo.")
  if ns.refresh then ns.refresh() end
end
local function unblock(name)
  local key = string.lower(shortName(strtrim(name or "")) or "")
  if not ns.DB.blocked[key] then say("Not blocked: " .. (name or "") .. ". /ep block lists who is."); return end
  say(ns.DB.blocked[key] .. " unblocked.")
  ns.DB.blocked[key] = nil
end
local function listBlocked()
  local names = {}
  for _, n in pairs(ns.DB.blocked) do names[#names + 1] = n end
  table.sort(names)
  say(#names == 0 and "Nobody blocked. Shift-right-click a buyer's line to block them."
    or ("Blocked: " .. table.concat(names, ", ") .. ". /ep unblock <name> to undo."))
end
ns.block, ns.unblock, ns.listBlocked = block, unblock, listBlocked
