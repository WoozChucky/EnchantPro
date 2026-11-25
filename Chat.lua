-- EnchantPro - reading chat: who is a buyer, which enchant they mean, who is an enchanter selling.
local ADDON, ns = ...
local SLOT_ORDER = ns.SLOT_ORDER
local SLOT_WORD = ns.SLOT_WORD
local PHRASES = ns.PHRASES
local EFFECT_WORDS = ns.EFFECT_WORDS
local DISTINCT = ns.DISTINCT
local canon = ns.canon
local parseRecipe = ns.parseRecipe

-- ---------------------------------------------------------------------------------------
-- reading chat

local function clean(text)
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|H.-|h(.-)|h", "%1")
  text = string.lower(text)
  text = string.gsub(text, "[%c]", " ")
  return text
end

local function wordPattern(w)
  return "%f[%w]" .. string.gsub(w, " ", "%%s*") .. "%f[%W]"
end
local function has(lower, w) return string.find(lower, wordPattern(w)) ~= nil end

-- a line as what it asks for: its effect words, numbers and slots
local function analyze(lower)
  local s = " " .. lower .. " "
  for _, p in ipairs(PHRASES) do s = string.gsub(s, p[1], " " .. p[2] .. " ") end
  local a = { set = {}, nums = {}, slots = {}, hasNum = false, anySlot = false, effect = false }
  for w in string.gmatch(s, "%a+") do
    local c = canon(w)
    a.set[c] = true
    if EFFECT_WORDS[c] then a.effect = true end
    local sw = SLOT_WORD[w]
    if sw then
      a.anySlot = true
      for k, v in pairs(sw) do if v > (a.slots[k] or 0) then a.slots[k] = v end end
    end
  end
  if a.set.damage then a.set.striking, a.set.impact = true, true end
  for n in string.gmatch(s, "%d+") do
    n = tonumber(n)
    if n and n >= 1 and n <= 40 then a.nums[n], a.hasNum = true, true end
  end
  return a
end

local function score(r, a)
  local hit = 0
  for _, k in ipairs(r.keys) do if a.set[k] then hit = hit + 1 end end
  if hit == 0 then return nil end
  local sc = hit * 4
  if a.anySlot then
    local s = a.slots[r.slot]
    if not s then return nil end
    sc = sc + s
  end
  if r.amount and a.hasNum then sc = sc + (a.nums[r.amount] and 3 or -1) end
  if r.tier and a.set[r.tier] then sc = sc + 2 end
  if ns.DB.adList[r.id] then sc = sc + 0.5 end
  return sc + r.rank * 0.05   -- unsure which: the better one
end

-- the enchant you know that fits the line best, or nil
local function findEnchant(a)
  local best, bestScore
  for _, r in ipairs(ns.knownList) do
    local sc = score(r, a)
    if sc and (not bestScore or sc > bestScore) then best, bestScore = r, sc end
  end
  return best
end

local function firstSlot(a)
  local best, bv
  for k, v in pairs(a.slots) do if not bv or v > bv or (v == bv and SLOT_ORDER[k] < SLOT_ORDER[best]) then best, bv = k, v end end
  return best
end

local SERVICE = { "enchant", "enchanter", "enchanters", "enchanting", "enchants", "ench", "enchants", "chanter", "enchantment" }
local BUY_CUES = { "wtb", "lf", "lfm", "need", "needed", "anyone", "any", "anybody", "someone", "looking", "buy", "buying",
  "pls", "plz", "please", "who", "can", "could" }
local SELL_CUES = { "wts", "selling", "sell", "lfw", "lf work", "your mats", "ur mats", "my mats",
  "whisper me", "w me", "/w", "pst", "msg me", "can do", "services", "service", "cheap", "free" }
-- only enchanters write these: they win over "lf" and "?" ("LF customers, can do [Crusader], your mats")
local SELLER_CUES = { "customer", "customers", "tips appreciated", "tip appreciated", "your mats", "ur mats",
  "my enchants", "all enchants", "for sale", "selling", "offering", "services", "lf work", "lfw", "wts" }

-- Enchant links in a line as the game sends it: |Henchant:20034|h[Enchant Weapon - Crusader]|h, and spell links
-- ("[Enchanting: Enchant ...]") alike. A profession link ([Enchanting]) is how enchanters advertise.
local NO_LINKS = { n = 0, ids = {}, names = {}, trade = false }
local function readLinks(text)
  local L = { n = 0, ids = {}, names = {}, trade = false }
  if type(text) ~= "string" then return L end
  for kind, data, label in string.gmatch(text, "|H(%a+):(.-)|h(.-)|h") do
    label = string.lower((string.gsub(label, "^%[(.*)%]$", "%1")))
    if kind == "trade" then
      L.trade = true
    elseif kind == "enchant" or kind == "spell" then
      local name = string.match(label, "^enchant .+") or string.match(label, "^[^:]+:%s*(enchant .+)$")
      if name then
        L.n = L.n + 1
        L.ids[L.n] = tonumber(string.match(data, "^(%d+)"))
        L.names[L.n] = name
      end
    end
  end
  return L
end

-- the first linked enchant you know; else nil and the label of the first one you don't ("not yours")
local function linkedEnchant(L)
  local unknown
  for i = 1, L.n do
    local r = L.ids[i] and ns.REC[L.ids[i]]
    if not r then
      for _, k in ipairs(ns.knownList) do if string.lower(k.name) == L.names[i] then r = k end end
    end
    if r then return r end
    if not unknown then
      local p = parseRecipe(0, { name = "Enchant" .. string.sub(L.names[i], 8) })
      unknown = p and p.label or L.names[i]
    end
  end
  return nil, unknown
end

-- recipe items ([Formula: Enchant ...]) are bought and sold as items: they don't ask for an enchant
local function dropRecipeItems(text)
  return (string.gsub(text, "|Hitem:[^|]*|h%[[^%]]*:[^%]]*%]|h", ""))
end

local function service(lower)
  for _, w in ipairs(SERVICE) do if has(lower, w) then return true end end
  return false
end

-- A line in public chat: a buyer? Returns true, enchant (or nil), analysis, and the label of a linked enchant you
-- don't have. Not a buyer: false, and "seller" when the line advertises enchanting.
local function channelIntent(lower, links)
  links = links or NO_LINKS
  local a = analyze(lower)
  local lr, unknown = linkedEnchant(links)
  local r = lr or (not unknown and findEnchant(a)) or nil
  local svc = service(lower) or links.n > 0
  -- an enchant named by a word only enchants use ("crusader", "fiery") counts without "enchant" or a slot
  local distinct = false
  for _, k in ipairs(r and r.keys or {}) do if DISTINCT[k] then distinct = true end end
  if links.trade then return false, "seller" end                    -- [Enchanting]: an enchanter's own link
  if not svc and not distinct and not (a.effect and a.anySlot) then return false end
  if has(lower, "disenchant") or has(lower, "de") then return false end
  local wtb = has(lower, "wtb")
  if not wtb then
    for _, w in ipairs(SELLER_CUES) do
      if has(lower, w) then return false, "seller" end
    end
    if links.n >= 3 then return false, "seller" end                 -- a list of enchants is a price list
  end
  local buy = wtb or string.find(lower, "?", 1, true) ~= nil
  for _, w in ipairs(BUY_CUES) do if buy then break end; buy = has(lower, w) end
  if buy then return true, r, a, unknown end
  for _, w in ipairs(SELL_CUES) do
    if string.find(lower, w, 1, true) then return false, "seller" end
  end
  if links.n == 0 and svc and not a.effect and not a.anySlot then return false end   -- "enchanting 225 ding"
  return true, r, a, unknown   -- "[Enchant Weapon - Crusader]" with no cue at all: nobody sells like that
end

-- A whisper: true (a buyer), "price", "mats" or false; then the enchant and the analysis.
local function whisperIntent(lower, links)
  links = links or NO_LINKS
  local a = analyze(lower)
  local lr, unknown = linkedEnchant(links)
  local r = lr or (not unknown and findEnchant(a)) or nil
  if unknown and not r then return true, nil, a, unknown end
  local price = has(lower, "how much") or has(lower, "price") or has(lower, "prices") or has(lower, "cost") or has(lower, "costs")
  local mats = has(lower, "mats") or has(lower, "mat") or has(lower, "materials") or has(lower, "reagents")
  if r or a.effect or a.anySlot then
    if mats and not price and r then return "mats", r, a end
    return true, r, a
  end
  if price then return "price", nil, a end
  if mats then return "mats", nil, a end
  if service(lower) or has(lower, "wtb") then return true, nil, a end
  return false
end

ns.clean = clean
ns.analyze = analyze
ns.findEnchant = findEnchant
ns.firstSlot = firstSlot
ns.readLinks = readLinks
ns.dropRecipeItems = dropRecipeItems
ns.channelIntent = channelIntent
ns.whisperIntent = whisperIntent
