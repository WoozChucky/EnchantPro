-- EnchantPro - sending: the chat box queue, whispers, the ad and the message templates.
local ADDON, ns = ...
local EP = ns.EP
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now
local money = ns.money
local fill = ns.fill
local zoneText = ns.zoneText
local feeFor = ns.feeFor
local fullFor = ns.fullFor
local matsText = ns.matsText

-- ---------------------------------------------------------------------------------------
-- sending chat

local function restricted()
  local f = C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
  return safe(f) == true
end

local function sendDirect(text, kind, target)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ok = pcall(send, text, kind, nil, target)
  return ok
end

-- Lines for the chat box wait here while you type something of your own; the tick opens the next one.
-- A line is a string ("/s hello") or { tell = name, text = ... } for a whisper.
EP.boxQueue = {}

local function activeBox()
  local box
  if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then box = safe(ChatFrameUtil.GetActiveWindow) end
  if type(box) ~= "table" then box = DEFAULT_CHAT_FRAME and rawget(DEFAULT_CHAT_FRAME, "editBox") end
  if type(box) ~= "table" then box = rawget(_G, "ChatFrame1EditBox") end
  return type(box) == "table" and box or nil
end

local function chatBusy()
  local box = activeBox()
  if not box or type(box.HasFocus) ~= "function" then return false end
  return safe(box.HasFocus, box) == true
end

local function openBox(line)
  EP.boxAt = now()
  if type(line) == "table" then
    -- a whisper: the game's own "tell" box (names with a surname have a space, so no "/w name text")
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if type(tell) == "function" then
      local item = line
      C_Timer.After(0, function()
        pcall(tell, item.tell, DEFAULT_CHAT_FRAME)
        local box = activeBox()
        if box and box.Insert then pcall(box.Insert, box, item.text) end
      end)
      return
    end
    line = "/w " .. line.tell .. " " .. line.text
  end
  local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
  if type(open) ~= "function" then say("Type this in chat: " .. line); return end
  C_Timer.After(0, function() pcall(open, line, DEFAULT_CHAT_FRAME) end)
end

local function toBox(line)
  if chatBusy() or #EP.boxQueue > 0 then
    EP.boxQueue[#EP.boxQueue + 1] = line
    return
  end
  openBox(line)
end

-- a whisper to a buyer: straight out where the realm allows it, else into the chat box
local function whisper(b, text)
  if not ns.DB.whisper then return false end
  if restricted() then
    toBox({ tell = b.full or b.name, text = text })
    return true
  end
  return sendDirect(text, "WHISPER", b.full or b.name)
end

local function adChannel()
  local info = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
  local general, trade
  for i = 1, 20 do
    local ok, id, name = pcall(GetChannelName, i)
    if ok and not isSecret(id) and type(id) == "number" and id > 0 and not isSecret(name) and type(name) == "string" then
      local c = type(info) == "function" and safe(info, name) or nil
      local z = type(c) == "table" and not isSecret(c.zoneChannelID) and c.zoneChannelID or nil
      local lname = string.lower(name)
      if z == 2 or (not z and string.find(lname, "^trade")) then trade = trade or { id, name } end
      if z == 1 or (not z and string.find(lname, "^general")) then general = general or { id, name } end
    end
  end
  local pick = trade or general
  if pick then return pick[1], pick[2] end
  return nil
end

-- the fee in words: "tips welcome" with none, else "20s fee"
local function feeTerms(c)
  if not c or c <= 0 then return "tips welcome" end
  return money(c) .. " fee"
end

-- the message templates
local AD_DEFAULT = "WTS Enchants: {list}. Your mats, {terms} - or full price with my mats. Whisper me!"
local AD_TOKENS = "{list} +7 Sta Bracer / Crusader Weapon (the enchants ticked in the Enchants window)   {terms} tips welcome / 20s fee   {fee} 20s   {where} Orgrimmar"
local REPLY_DEFAULT = "{enchant}: {offer}. Open trade with the item in the bottom slot - I'm in {where}."
local REPLY_TOKENS = "{enchant} +7 Sta Bracer   {offer} free with your mats (1 Greater Eternal Essence - trade them first), tips welcome, or 1g with mine   {fee} 20s   {full} 1g   {mats} 1 Greater Eternal Essence   {where} Orgrimmar   {name} Bob"
local ASK_DEFAULT = "Hi! Enchanter here - which enchant do you need? Your mats, {terms} - or full price with mine. I'm in {where}."
local ASK_TOKENS = "{where} Orgrimmar   {terms} tips welcome / 20s fee   {fee} 20s   {name} Bob"
local THANKS_DEFAULT = "Thank you {name}! {enchant} done - received {got}{tip}."
local THANKS_TOKENS = "{name} Bob   {enchant} +7 Sta Bracer   {got} 30s   {tip} (incl. 10s tip - much appreciated!) / , much appreciated   {price} 20s"

local function tpl(key, default) return (ns.DB[key] and ns.DB[key] ~= "") and ns.DB[key] or default end

local function adList()
  local names = {}
  for _, r in ipairs(ns.knownList) do if ns.DB.adList[r.id] then names[#names + 1] = r.label end end
  return names
end

local function adText(t)
  local names = adList()
  return fill(t or tpl("ad", AD_DEFAULT), {
    list = #names > 0 and table.concat(names, " / ") or "all my enchants",
    fee = money(ns.DB.fee), terms = feeTerms(ns.DB.fee), where = zoneText(),
  })
end

local function offerText(r)
  local fee = feeFor(r)
  local s = (fee > 0 and money(fee) or "free") .. " with your mats (" .. matsText(r) .. " - trade them first)"
  if fee <= 0 then s = s .. ", tips welcome" end
  local full = fullFor(r)
  if full then s = s .. ", or " .. money(full) .. " with mine" end
  return s
end

local function replyText(b, r, t)
  return fill(t or tpl("replyText", REPLY_DEFAULT), {
    enchant = r.label, offer = offerText(r), fee = money(feeFor(r)), full = fullFor(r) and money(fullFor(r)) or "-",
    mats = matsText(r), where = zoneText(), name = b.name,
  })
end

local function askText(b, t)
  return fill(t or tpl("askText", ASK_DEFAULT), { where = zoneText(), fee = money(ns.DB.fee), terms = feeTerms(ns.DB.fee), name = b.name })
end

local function thanksText(b, label, got, tip, owed, price, t)
  if got < owed then
    return b.name .. ": received " .. money(got) .. " - still " .. money(owed - got) .. " short of the " .. money(price) .. " price."
  end
  local own = t or (ns.DB.thanksText and ns.DB.thanksText ~= "")
  -- nothing asked and nothing given: no "received 0c" (your own text is used as written)
  if price <= 0 and got <= 0 and not own then
    return "Thank you " .. b.name .. "! " .. (label or "The enchant") .. " done - enjoy!"
  end
  local tipText = ""
  if tip > 0 then
    tipText = (price <= 0 and tip >= got) and ", much appreciated" or (" (incl. " .. money(tip) .. " tip - much appreciated!)")
  end
  return fill(t or tpl("thanksText", THANKS_DEFAULT), {
    name = b.name, enchant = label or "the enchant", got = money(got), price = money(price), tip = tipText,
  })
end

local function sampleRec()
  return ns.knownList[1] or { id = 0, label = "+7 Sta Bracer", reagents = {} }
end

local function adLeft()
  return math.max(0, (ns.DB.adAt or 0) + ns.DB.adCooldown - time())
end

function EP.postAd()
  local left = adLeft()
  if left > 0 then say("Next ad in " .. left .. " s."); return end
  local id, name = adChannel()
  if not id then say("You are not in Trade or General chat here."); return end
  local text = adText()
  if restricted() then
    toBox("/" .. id .. " " .. text)
    say("The ad is in the chat box (" .. name .. ") - press Enter to post it.")
  elseif not sendDirect(text, "CHANNEL", id) then
    say("The ad did not go out.")
    return
  end
  ns.DB.adAt = time()
  if ns.refresh then ns.refresh() end
end

ns.restricted = restricted
ns.chatBusy = chatBusy
ns.openBox = openBox
ns.toBox = toBox
ns.whisper = whisper
ns.AD_DEFAULT = AD_DEFAULT
ns.AD_TOKENS = AD_TOKENS
ns.REPLY_DEFAULT = REPLY_DEFAULT
ns.REPLY_TOKENS = REPLY_TOKENS
ns.ASK_DEFAULT = ASK_DEFAULT
ns.ASK_TOKENS = ASK_TOKENS
ns.THANKS_DEFAULT = THANKS_DEFAULT
ns.THANKS_TOKENS = THANKS_TOKENS
ns.feeTerms = feeTerms
ns.adText = adText
ns.replyText = replyText
ns.askText = askText
ns.thanksText = thanksText
ns.sampleRec = sampleRec
ns.adLeft = adLeft
