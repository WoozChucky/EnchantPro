-- EnchantPro - sell enchants with as little clicking as the game allows.
--
-- How an enchant is sold: the buyer opens trade with the item in the bottom "Will not be traded" slot, you cast
-- the enchant on that slot and both accept. The mats must be in YOUR bags when you cast, so a "your mats" sale is
-- two trades: the buyer hands the mats over first (the addon remembers what they gave), then the item.
-- Every enchant has a fee (with the buyer's mats) and, if you set one, a full price (with your mats).
--
-- What the game lets an addon do, and so what this one does:
--   * read chat                                    -> finds buyers and the enchant they ask for
--   * read your Enchanting window                  -> knows your enchants and their mats (open it once)
--   * open trade with someone in range              -> opens trade with buyers who come to you
--   * read the trade window                         -> the item, its slot, the mats and the gold: PAID / missing
--   * cast a spell: only from a key press or click  -> one Cast button: the right enchant, onto the trade item
--   * accept a trade / post in public chat: only from a key press or click -> buttons / keys
-- WoW Forever's live realms refuse every chat line an addon sends: replies, the ad and the thank-you go into
-- your chat box and your Enter sends them.
-- WoW Forever only.

local ADDON = ...

local EP = {}
_G.EnchantPro = EP

local ENCHANTING = 333   -- the Enchanting skill line

-- Enchant slots. names: how the recipe names them ("Enchant Bracer - ..."); words: how players write them.
-- "twohand" / "onehand" are what PHRASES turn "2h", "two-handed", "1h" ... into.
local SLOTS = {
  { key = "boots",  label = "Boots",  names = { "boots" }, words = { "boots", "boot", "feet", "shoes" } },
  { key = "bracer", label = "Bracer", names = { "bracer", "bracers" }, words = { "bracer", "bracers", "brace", "wrist", "wrists", "bracelet" } },
  { key = "chest",  label = "Chest",  names = { "chest" }, words = { "chest", "chestpiece", "robe" } },
  { key = "cloak",  label = "Cloak",  names = { "cloak" }, words = { "cloak", "cape" } },
  { key = "gloves", label = "Gloves", names = { "gloves" }, words = { "gloves", "glove", "hands", "gauntlets" } },
  { key = "shield", label = "Shield", names = { "shield" }, words = { "shield" } },
  { key = "2h",     label = "2H",     names = { "2h weapon", "two-handed weapon", "2h" }, words = { "twohand", "staff" } },
  { key = "weapon", label = "Weapon", names = { "weapon" }, words = { "weapon", "weapons", "wep", "weap", "wpn", "onehand", "mh", "oh", "sword", "mace", "axe", "dagger" } },
}
local SLOT, SLOT_ORDER, SLOT_WORD = {}, {}, {}
for i, s in ipairs(SLOTS) do
  SLOT[s.key], SLOT_ORDER[s.key] = s, i
  for _, w in ipairs(s.words) do
    -- a weapon enchant fits a 2H weapon too, and the other way round second best
    if s.key == "2h" then SLOT_WORD[w] = { ["2h"] = 3, weapon = 2 }
    elseif s.key == "weapon" then SLOT_WORD[w] = { weapon = 3, ["2h"] = 1 }
    else SLOT_WORD[w] = { [s.key] = 3 } end
  end
end

-- the trade item's equip slot -> the enchant slots that fit it
local EQUIP = {
  INVTYPE_FEET = { boots = true }, INVTYPE_WRIST = { bracer = true }, INVTYPE_CHEST = { chest = true },
  INVTYPE_ROBE = { chest = true }, INVTYPE_CLOAK = { cloak = true }, INVTYPE_HAND = { gloves = true },
  INVTYPE_SHIELD = { shield = true }, INVTYPE_2HWEAPON = { ["2h"] = true, weapon = true },
  INVTYPE_WEAPON = { weapon = true }, INVTYPE_WEAPONMAINHAND = { weapon = true }, INVTYPE_WEAPONOFFHAND = { weapon = true },
}

local TIER_RANK = { minor = 1, lesser = 2, greater = 4, superior = 5, major = 6 }

-- multi-word ways of writing one thing, applied before the line is cut into words
local PHRASES = {
  { "%f[%w]two[%s%-]?hand[a-z]*%f[%W]", "twohand" },
  { "%f[%w]2[%s%-]?hand[a-z]*%f[%W]", "twohand" },
  { "%f[%w]2[%s%-]?h%f[%W]", "twohand" },
  { "%f[%w]2hd%f[%W]", "twohand" },
  { "%f[%w]one[%s%-]?hand[a-z]*%f[%W]", "onehand" },
  { "%f[%w]1[%s%-]?hand[a-z]*%f[%W]", "onehand" },
  { "%f[%w]1[%s%-]?h%f[%W]", "onehand" },
  { "%f[%w]all[%s%-]?stats?%f[%W]", "stats" },
  { "%f[%w]run[%s%-]?speed%f[%W]", "speed" },
  { "%f[%w]movement[%s%-]?speed%f[%W]", "speed" },
  { "%f[%w]spell[%s%-]?power%f[%W]", "spellpower" },
  { "%f[%w]healing[%s%-]?power%f[%W]", "healing" },
  { "%f[%w]icy[%s%-]?chill%f[%W]", "icy" },
  { "%f[%w]fiery[%s%-]?weapon%f[%W]", "fiery" },
  { "%f[%w]unholy[%s%-]?weapon%f[%W]", "unholy" },
  { "%f[%w]riding[%s%-]?skill%f[%W]", "riding" },
}

-- short ways of writing a stat -> the recipe's word
local SYN = {
  agi = "agility", agil = "agility", str = "strength", stre = "strength", strenght = "strength",
  stam = "stamina", sta = "stamina", stamm = "stamina", int = "intellect", intel = "intellect", intelect = "intellect",
  intelligence = "intellect", spi = "spirit", spr = "spirit", hp = "health", life = "health", mp = "mana",
  stat = "stats", def = "defense", defence = "defense", ms = "speed", crus = "crusader", crusa = "crusader",
  crussader = "crusader", lifesteal = "lifestealing", ls = "lifestealing", beast = "beastslayer",
  res = "resistance", resist = "resistance", resi = "resistance", resistances = "resistance",
  sp = "spellpower", heal = "healing", heals = "healing", dmg = "damage", armor = "protection", armour = "protection",
}

-- words that name an effect: a line with one of these asks for a particular enchant
local EFFECT_WORDS = {}
for _, w in ipairs({ "agility", "strength", "stamina", "intellect", "spirit", "health", "mana", "stats", "defense",
  "speed", "crusader", "fiery", "icy", "unholy", "lifestealing", "beastslayer", "demonslaying", "striking", "impact",
  "damage", "resistance", "spellpower", "healing", "riding", "protection", "absorption", "parry", "dodge", "haste",
  "mining", "herbalism", "skinning", "fishing", "threat", "deflection", "blocking" }) do
  EFFECT_WORDS[w] = true
end
local DISTINCT = { crusader = true, fiery = true, icy = true, unholy = true, lifestealing = true, beastslayer = true, demonslaying = true }
local STOP = { weapon = true, skill = true, of = true, the = true, ["and"] = true, enchant = true }

local STAT_SHORT = { agility = "Agi", strength = "Str", stamina = "Sta", intellect = "Int", spirit = "Spi",
  health = "HP", mana = "Mana", stats = "Stats", defense = "Def", spellpower = "Spell Power", healing = "Healing" }

local DEFAULTS = {
  fee = 2000,           -- copper: 20s with the buyer's mats
  fees = {},            -- [recipe id] = fee for that enchant
  fulls = {},           -- [recipe id] = full price with your mats (none: not offered)
  adList = {},          -- [recipe id] = true: named in the ad
  matCost = {},         -- [item id] = what a mat costs you (else Auctionator's price)
  itemNames = {},       -- [item id] = name, for mats the game has not loaded
  chars = {},           -- [character] = { recipes = { [id] = { name, amount, reagents } } }
  adCooldown = 60,
  listen = true,        -- look for buyers in public chat
  reply = true,         -- answer buyers (in the chat box where the realm refuses addon chat)
  autoTrade = true,     -- open trade with buyers in range
  thanks = true,        -- a thank-you after every enchant
  thanksSay = false,    -- in /say instead of a whisper
  whisper = true,
  sound = true,
  shown = true,
}

local DB
local PANEL_MAX_ROWS = 20
local buyers = {}       -- [lower-case name] = buyer
EP.sellers = {}         -- [lower-case name] = when they last advertised enchanting: their chat lines are skipped
local REC = {}          -- [recipe id] = this character's enchant: id, name, slot, eff, keys, tier, amount, reagents, label
local knownList = {}    -- REC sorted: slot, then best first
local myName = ""
local panel, castBtn, rows, toggles = nil, nil, {}, {}
local refresh            -- forward

-- ---------------------------------------------------------------------------------------
-- helpers

local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

local function safe(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if not ok or isSecret(v) then return nil end
  return v
end

local function say(msg) print("|cff7fd4ffEnchantPro|r: " .. msg) end
local function now() return GetTime() end

local function shortName(n)
  if type(n) ~= "string" then return nil end
  return string.match(n, "^([^%-]+)")
end

local function money(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if k > 0 or #out == 0 then out[#out + 1] = k .. "c" end
  return table.concat(out, " ")
end

local function fill(tpl, vals)
  return (string.gsub(tpl, "{(%a+)}", function(k) return vals[k] end))
end

local function parseMoney(s)
  s = string.gsub(string.lower(s or ""), "%s", "")
  if s == "" then return nil end
  if string.match(s, "^%d+%.?%d*$") then return math.floor(tonumber(s) * 10000 + 0.5) end
  local rest = string.gsub(s, "%d+%.?%d*[gsc]", "")
  if rest ~= "" then return nil end
  local total = 0
  for n, u in string.gmatch(s, "(%d+%.?%d*)([gsc])") do
    total = total + tonumber(n) * (u == "g" and 10000 or u == "s" and 100 or 1)
  end
  return math.floor(total + 0.5)
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local n = safe(C_Spell.GetSpellName, id)
    if type(n) == "string" then return n end
  end
  if GetSpellInfo then
    local n = safe(GetSpellInfo, id)
    if type(n) == "string" then return n end
  end
  return nil
end

local function bagCount(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return safe(f, id) or 0
end

local function itemName(id)
  local n = C_Item and C_Item.GetItemNameByID and safe(C_Item.GetItemNameByID, id)
  if type(n) ~= "string" and GetItemInfo then n = safe(GetItemInfo, id) end
  if type(n) == "string" and n ~= "" then
    DB.itemNames[id] = n
    return n
  end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return DB.itemNames[id] or ("item " .. id)
end

local function itemIdOf(link)
  return type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil
end

local function equipLoc(link)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if type(f) ~= "function" then return nil end
  local ok, _, _, _, loc = pcall(f, link)
  if not ok or isSecret(loc) or type(loc) ~= "string" then return nil end
  return loc
end

-- what one mat costs you: your own figure, else Auctionator's, else unknown (nil)
local function matCost(id)
  if DB.matCost[id] then return DB.matCost[id] end
  local api = rawget(_G, "Auctionator") and Auctionator.API and Auctionator.API.v1
  if api and api.GetAuctionPriceByItemID then
    local p = safe(api.GetAuctionPriceByItemID, "EnchantPro", id)
    if type(p) == "number" and p > 0 then return p end
  end
  return nil
end

local function playSound()
  if not DB.sound then return end
  local id = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
  pcall(PlaySound, id, "Master")
end

local function zoneText()
  local z = safe(GetMinimapZoneText)
  if type(z) ~= "string" or z == "" then z = safe(GetZoneText) end
  return (type(z) == "string" and z ~= "") and z or "town"
end

-- ---------------------------------------------------------------------------------------
-- enchants: what this character knows, read from the Enchanting window and kept per character

local function canon(w) return SYN[w] or w end

-- the words of an effect ("Lesser Stamina" -> tier "lesser", keys { "stamina" })
local function effectKeys(eff)
  local s = " " .. eff .. " "
  for _, p in ipairs(PHRASES) do s = string.gsub(s, p[1], p[2]) end
  local keys = {}
  for w in string.gmatch(s, "%a+") do
    w = canon(w)
    if not STOP[w] then keys[#keys + 1] = w end
  end
  return keys
end

local function labelFor(r)
  local stat = r.keys[1] and STAT_SHORT[r.keys[1]]
  local slot = SLOT[r.slot].label
  if r.amount and stat then return "+" .. r.amount .. " " .. stat .. " " .. slot end
  -- "Minor Speed Boots", "Crusader Weapon", "+2 Striking Weapon"
  local eff = string.gsub(r.effText, "(%a)(%w*)", function(a, b) return string.upper(a) .. b end)
  if r.amount and not r.tier then eff = "+" .. r.amount .. " " .. eff end
  if string.find(string.lower(eff), string.lower(slot), 1, true) then return eff end   -- "Fiery Weapon"
  return eff .. " " .. slot
end

-- "Enchant Bracer - Lesser Stamina" -> the enchant, or nil for anything else Enchanting makes (rods, oils, wands)
local function parseRecipe(id, saved)
  local slotText, effect = string.match(saved.name or "", "^Enchant (.-) %- (.+)$")
  if not slotText then return nil end
  local slot
  slotText = string.lower(slotText)
  for _, s in ipairs(SLOTS) do
    for _, n in ipairs(s.names) do if slotText == n then slot = s.key end end
  end
  if not slot then return nil end
  local eff = string.lower(effect)
  local tier
  local first, rest = string.match(eff, "^(%a+)%s+(.+)$")
  if first and TIER_RANK[first] then tier, eff = first, rest end
  local r = { id = id, name = saved.name, slot = slot, eff = eff, effText = effect, keys = effectKeys(eff), tier = tier,
    rank = tier and TIER_RANK[tier] or 3, amount = saved.amount, reagents = saved.reagents or {} }
  r.label = labelFor(r)
  return r
end

local function rebuildKnown()
  REC, knownList = {}, {}
  local saved = DB.chars[myName] and DB.chars[myName].recipes or {}
  for id, s in pairs(saved) do
    local r = parseRecipe(id, s)
    if r then REC[id] = r; knownList[#knownList + 1] = r end
  end
  table.sort(knownList, function(a, b)
    if a.slot ~= b.slot then return SLOT_ORDER[a.slot] < SLOT_ORDER[b.slot] end
    if a.rank ~= b.rank then return a.rank > b.rank end
    return a.name < b.name
  end)
end

local function recipeAmount(id)
  local d
  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeDescription then d = safe(C_TradeSkillUI.GetRecipeDescription, id, {}) end
  if type(d) ~= "string" and C_Spell and C_Spell.GetSpellDescription then d = safe(C_Spell.GetSpellDescription, id) end
  if type(d) ~= "string" then return nil end
  return tonumber(string.match(d, "%+%s*(%d+)"))
end

local function recipeReagents(id)
  local sc = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic and safe(C_TradeSkillUI.GetRecipeSchematic, id, false)
  local out = {}
  if type(sc) ~= "table" or type(sc.reagentSlotSchematics) ~= "table" then return out end
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  for _, slot in ipairs(sc.reagentSlotSchematics) do
    local first = slot.reagents and slot.reagents[1]
    if (basic == nil or slot.reagentType == basic) and first and first.itemID and (slot.quantityRequired or 0) > 0 then
      out[#out + 1] = { id = first.itemID, q = slot.quantityRequired }
    end
  end
  return out
end

-- the open profession window: if it is your own Enchanting, every learned enchant is kept
function EP.scanProfession()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
  if safe(T.IsTradeSkillLinked) or safe(T.IsTradeSkillGuild) then return end
  local base = T.GetBaseProfessionInfo and safe(T.GetBaseProfessionInfo)
  if type(base) ~= "table" or base.professionID ~= ENCHANTING then return end
  local ids = safe(T.GetAllRecipeIDs)
  if type(ids) ~= "table" then return end
  local mine = {}
  for _, id in ipairs(ids) do
    local info = safe(T.GetRecipeInfo, id)
    if type(info) == "table" and info.learned and type(info.name) == "string" and string.find(info.name, "^Enchant ") then
      mine[id] = { name = info.name, amount = recipeAmount(id), reagents = recipeReagents(id) }
      for _, r in ipairs(mine[id].reagents) do itemName(r.id) end
    end
  end
  local before = #knownList
  DB.chars[myName] = { recipes = mine }
  rebuildKnown()
  if #knownList ~= before then
    say("Knows " .. #knownList .. " enchants now.")
  end
  if EP.enchantsRefresh then EP.enchantsRefresh() end
  if EP.updateCast then EP.updateCast() end
  if refresh then refresh() end
end

local function feeFor(r) return (r and DB.fees[r.id]) or DB.fee end
local function fullFor(r) return r and DB.fulls[r.id] or nil end

local function matsText(r, withBags)
  local parts = {}
  for _, m in ipairs(r.reagents) do
    local txt = m.q .. " " .. itemName(m.id)
    if withBags then
      local have = bagCount(m.id)
      txt = txt .. (have >= m.q and (" |cff40ff40(" .. have .. ")|r") or (" |cffff4040(" .. have .. ")|r"))
    end
    parts[#parts + 1] = txt
  end
  return #parts > 0 and table.concat(parts, ", ") or "no mats"
end

local function canCast(r)
  for _, m in ipairs(r.reagents) do if bagCount(m.id) < m.q then return false end end
  return true
end

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
  if DB.adList[r.id] then sc = sc + 0.5 end
  return sc + r.rank * 0.05   -- unsure which: the better one
end

-- the enchant you know that fits the line best, or nil
local function findEnchant(a)
  local best, bestScore
  for _, r in ipairs(knownList) do
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
    local r = L.ids[i] and REC[L.ids[i]]
    if not r then
      for _, k in ipairs(knownList) do if string.lower(k.name) == L.names[i] then r = k end end
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
  if not DB.whisper then return false end
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

-- the message templates
local AD_DEFAULT = "WTS Enchants: {list}. Your mats + {fee} tip, or full price with my mats. Whisper me!"
local AD_TOKENS = "{list} +7 Sta Bracer / Crusader Weapon (the enchants ticked in the Enchants window)   {fee} 20s   {where} Orgrimmar"
local REPLY_DEFAULT = "{enchant}: {offer}. Open trade with the item in the bottom slot - I'm in {where}."
local REPLY_TOKENS = "{enchant} +7 Sta Bracer   {offer} 20s tip with your mats (1 Greater Eternal Essence - trade them first), or 1g with mine   {fee} 20s   {full} 1g   {mats} 1 Greater Eternal Essence   {where} Orgrimmar   {name} Bob"
local ASK_DEFAULT = "Hi! Enchanter here - which enchant do you need? Your mats + tip, or full price with my mats. I'm in {where}."
local ASK_TOKENS = "{where} Orgrimmar   {fee} 20s   {name} Bob"
local THANKS_DEFAULT = "Thank you {name}! {enchant} done - received {got}{tip}."
local THANKS_TOKENS = "{name} Bob   {enchant} +7 Sta Bracer   {got} 30s   {tip} (incl. 10s tip - much appreciated!)   {price} 20s"

local function tpl(key, default) return (DB[key] and DB[key] ~= "") and DB[key] or default end

local function adList()
  local names = {}
  for _, r in ipairs(knownList) do if DB.adList[r.id] then names[#names + 1] = r.label end end
  return names
end

local function adText(t)
  local names = adList()
  return fill(t or tpl("ad", AD_DEFAULT), {
    list = #names > 0 and table.concat(names, " / ") or "all my enchants",
    fee = money(DB.fee), where = zoneText(),
  })
end

local function offerText(r)
  local s = money(feeFor(r)) .. " tip with your mats (" .. matsText(r) .. " - trade them first)"
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
  return fill(t or tpl("askText", ASK_DEFAULT), { where = zoneText(), fee = money(DB.fee), name = b.name })
end

local function thanksText(b, label, got, tip, owed, price, t)
  if got < owed then
    return b.name .. ": received " .. money(got) .. " - still " .. money(owed - got) .. " short of the " .. money(price) .. " price."
  end
  return fill(t or tpl("thanksText", THANKS_DEFAULT), {
    name = b.name, enchant = label or "the enchant", got = money(got), price = money(price),
    tip = tip > 0 and (" (incl. " .. money(tip) .. " tip - much appreciated!)") or "",
  })
end

local function sampleRec()
  return knownList[1] or { id = 0, label = "+7 Sta Bracer", reagents = {} }
end

local function adLeft()
  return math.max(0, (DB.adAt or 0) + DB.adCooldown - time())
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
  DB.adAt = time()
  if refresh then refresh() end
end

-- ---------------------------------------------------------------------------------------
-- units: buyers are not in your group, so they are found by target, mouseover, focus and nameplates

local function surnameSeparator()
  local c = Constants and Constants.CharacterNameSeparatorConsts
  local sep = c and c.CHARACTERNAME_SURNAME_SEPARATOR
  if type(sep) == "string" and sep ~= "" then return sep end
  return " "
end

local function fullName(unit)
  local ok, first, surname = pcall(UnitName, unit)
  if not ok or isSecret(first) or type(first) ~= "string" or first == "" then return nil end
  if not isSecret(surname) and type(surname) == "string" and surname ~= ""
     and not string.find(first, surname, 1, true) then
    return first .. surnameSeparator() .. surname
  end
  return first
end

local UNITS = { "target", "mouseover", "focus" }
for i = 1, 40 do UNITS[#UNITS + 1] = "nameplate" .. i end
for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end

local function unitFor(name)
  if not name then return nil end
  local lname = string.lower(name)
  for _, unit in ipairs(UNITS) do
    if safe(UnitExists, unit) then
      local un = fullName(unit)
      if un and string.lower(un) == lname and safe(UnitIsPlayer, unit) ~= false then return unit end
    end
  end
  return nil
end

local function near(unit) return safe(CheckInteractDistance, unit, 2) == true end

-- ---------------------------------------------------------------------------------------
-- ledger. An entry: { t = time(), k = kind, n = name, en = enchant label, mode, p = price, g = gold, pre, tip, m, it }
--   k = "pay"  - gold and/or mats a buyer handed over before the enchant (g; it = the mats as text)
--   k = "sale" - an enchant: asked p, got g in this trade on top of pre paid before; tip above what was owed;
--                mode "mats" (theirs), "full" (yours) or "part"; m = what your own mats in it cost

local LEDGER_MAX = 2000

local function newTotals()
  return { income = 0, tips = 0, sales = 0, theirMats = 0, myMats = 0, matsCost = 0, short = 0, unpaid = 0 }
end

local function addTo(T, e)
  if e.k == "pay" then
    T.income = T.income + (e.g or 0)
  elseif e.k == "sale" then
    T.income, T.tips, T.sales = T.income + e.g, T.tips + (e.tip or 0), T.sales + 1
    if e.mode == "mats" then T.theirMats = T.theirMats + 1 else T.myMats = T.myMats + 1 end
    T.matsCost = T.matsCost + (e.m or 0)
    local paid = (e.pre or 0) + e.g
    if paid < e.p then
      T.short = T.short + (e.p - paid)
      if paid == 0 then T.unpaid = T.unpaid + 1 end
    end
  end
end

local function ledgerAdd(e)
  e.t = e.t or time()
  local L = DB.ledger
  L[#L + 1] = e
  while #L > LEDGER_MAX do table.remove(L, 1) end
  addTo(DB.totals, e)
  if EP.ledgerRefresh then EP.ledgerRefresh() end
end

local function ledgerSum(since)
  if not since then return DB.totals end
  local T = newTotals()
  for _, e in ipairs(DB.ledger) do if e.t >= since then addTo(T, e) end end
  return T
end

local function net(T) return T.income - T.matsCost end

local function dayStart()
  local d = date("*t")
  d.hour, d.min, d.sec = 0, 0, 0
  return time(d)
end

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
  for _, r in ipairs(knownList) do
    if DB.adList[r.id] and #list < 4 then
      list[#list + 1] = r.label .. " " .. money(feeFor(r)) .. (fullFor(r) and ("/" .. money(fullFor(r))) or "")
    end
  end
  whisper(b, "Your mats + " .. money(DB.fee) .. " tip for most enchants"
    .. (#list > 0 and (" (" .. table.concat(list, ", ") .. ")") or "") .. ". Which one do you need?")
end

-- someone asked for an enchant (src = "whisper", "chat" or "say")
local function request(sender, text, src, where)
  if isSecret(sender) or isSecret(text) or type(sender) ~= "string" or type(text) ~= "string" then return end
  local name = shortName(sender)
  if not name or string.lower(name) == string.lower(myName) then return end
  local key = string.lower(name)
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
      if old and old.src ~= "whisper" and old.state == "asked" then buyers[key] = nil; if refresh then refresh() end end
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
  if b.state == "done" then b.state = "asked" end
  local changed = false
  if r then
    changed = b.rec ~= r.id
    b.rec, b.cant, b.slot = r.id, nil, r.slot
  elseif unknown or a.effect then
    b.cant, b.want = true, unknown      -- asks for an enchant you don't have
  elseif a.anySlot then
    b.slot = firstSlot(a)
  end
  b.at, b.src, b.where = t, src, where

  if b.new then
    b.new = nil
    playSound()
    say((b.cant and "|cff808080Buyer|r " or "|cff40ff40Buyer|r ") .. name .. " - "
      .. (r and r.label or b.want or b.slot and SLOT[b.slot].label or "an enchant") .. " (" .. (where or src) .. ")"
      .. (b.cant and " - |cff808080you don't have that enchant.|r" or "."))
  end

  if DB.reply and intent ~= "mats" then
    if r and (changed or not b.replied) then
      if whisper(b, replyText(b, r)) then b.replied = true end
    elseif b.cant and src == "whisper" and not b.sorry then
      b.sorry = true
      whisper(b, "Sorry, I don't have that enchant.")
    elseif not r and not b.cant and not b.asked then
      b.asked = true
      whisper(b, askText(b))
    end
  end
  if EP.updateCast then EP.updateCast() end
  if refresh then refresh() end
end

-- ---------------------------------------------------------------------------------------
-- trade

local overlay

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
  for _, r in ipairs(knownList) do if fits(r, t) then list[#list + 1] = r end end
  return list
end

-- the enchant to cast now
function EP.plan()
  local t = EP.trade
  local manual = DB.manual and REC[DB.manual]
  if manual and EP.manualAt and now() - EP.manualAt < 20 and fits(manual, t) then return manual end
  local b = t and tradeBuyer()
  if b and b.rec and REC[b.rec] and fits(REC[b.rec], t) then return REC[b.rec] end
  if t and t.target and t.target.slots then
    local list = candidates(t)
    if b and b.slot then
      for _, r in ipairs(list) do if r.slot == b.slot and DB.adList[r.id] then return r end end
    end
    if manual and fits(manual, t) then return manual end
    for _, r in ipairs(list) do if DB.adList[r.id] then return r end end
    return list[1]
  end
  if manual then return manual end
  -- no trade: the newest buyer's enchant
  local newest
  for _, nb in pairs(buyers) do
    if nb.rec and REC[nb.rec] and nb.state ~= "done" and (not newest or nb.at > newest.at) then newest = nb end
  end
  return newest and REC[newest.rec] or nil
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

local function updateOverlay()
  if not overlay then
    local tf = _G.TradeFrame
    if not tf then return end
    overlay = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay:SetPoint("BOTTOM", tf, "TOP", 0, 22)   -- above PortalPro's line
  end
  local line = tradeLine()
  overlay:SetText(line and ("|cff7fd4ffEnchantPro|r  " .. line) or "")
end

local function tradeDone()
  local t = EP.trade or EP.lastTrade
  if not t or t.counted then return end
  t.counted = true
  local snap = t.final or t
  local got = snap.money or 0
  local r = t.castRec and REC[t.castRec]
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
    if DB.thanks then
      local line = thanksText(b, r.label, pre + got, tip, owed, owed)
      if DB.thanksSay then toBox("/s " .. line) else whisper(b, line) end
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
  if refresh then refresh() end
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
  if not castBtn then return end
  if InCombatLockdown() then EP.castDirty = true; return end
  EP.castDirty = nil
  local r = EP.plan()
  EP.castRec = r
  if r then
    local name = spellName(r.id) or r.name
    local onTrade = EP.trade and EP.trade.target and rawget(_G, "TradeRecipientItem7ItemButton") ~= nil
    castBtn:SetAttribute("type", "macro")
    castBtn:SetAttribute("macrotext", "/cast " .. name .. (onTrade and "\n/click TradeRecipientItem7ItemButton" or ""))
    castBtn:SetText(r.label .. (canCast(r) and "" or " |cffff4040(no mats)|r"))
  else
    castBtn:SetAttribute("type", nil)
    castBtn:SetAttribute("macrotext", nil)
    castBtn:SetText(#knownList == 0 and "Open your Enchanting window once" or "No enchant picked")
  end
end

local function cycle(step)
  local list = candidates(EP.trade)
  if #list == 0 then return end
  local idx = 0
  for i, r in ipairs(list) do if r == EP.castRec then idx = i end end
  idx = (idx - 1 + step) % #list + 1
  DB.manual, EP.manualAt = list[idx].id, now()
  EP.updateCast()
  updateOverlay()
  if refresh then refresh() end
end

-- ---------------------------------------------------------------------------------------
-- the half-second tick

local function tick()
  if not DB then return end
  local t = now()
  local tf = _G.TradeFrame
  local trading = EP.trade or (tf and tf:IsShown())

  -- buyers you can see: near or not, and trade with the first one in range
  for _, b in pairs(buyers) do
    b.unit = (b.state ~= "done" and not b.cant) and unitFor(b.name) or nil
    b.near = b.unit and near(b.unit) or false
  end
  if DB.autoTrade and not EP.tradeBlocked and not trading and not InCombatLockdown() then
    for _, b in pairs(buyers) do
      if b.near and (b.state == "asked" or b.state == "mats") and (b.tradeTries or 0) < 3 and t - (b.tradeTry or 0) > 8 then
        openTrade(b, b.unit)
        break
      end
    end
  end

  -- drop old lines: asked and never came (10 min), done (2 min)
  for key, b in pairs(buyers) do
    if (b.state == "done" and t - (b.doneAt or 0) > 120)
       or ((b.state == "asked") and t - b.at > 600 and not b.near) then
      buyers[key] = nil
    end
  end

  if #EP.boxQueue > 0 and t - (EP.boxAt or 0) > 1 and not chatBusy() then
    openBox(table.remove(EP.boxQueue, 1))
  end
  if EP.castDirty and not InCombatLockdown() then EP.updateCast() end
  if refresh then refresh() end
end

-- ---------------------------------------------------------------------------------------
-- windows

local STATE_TEXT = {
  asked = "|cffffd200asked|r", mats = "|cff7fd4ffmats in|r", trading = "|cffffffffin trade|r",
  done = "|cff808080done|r",
}
local STATE_ORDER = { trading = 1, mats = 2, asked = 3, done = 4 }

local function sortedBuyers()
  local list = {}
  for _, b in pairs(buyers) do list[#list + 1] = b end
  table.sort(list, function(a, b)
    local oa, ob = STATE_ORDER[a.state] or 9, STATE_ORDER[b.state] or 9
    if oa ~= ob then return oa < ob end
    if (a.near and 1 or 0) ~= (b.near and 1 or 0) then return a.near == true end
    return a.at > b.at
  end)
  return list
end

local function onOff(v) return v and "|cff40ff40ON|r" or "|cff808080OFF|r" end

local function button(parent, w, h, text, template)
  local b = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  return b
end

local function backdrop(f, alpha)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0, 0, 0, alpha)
  end
end

local function tooltip(widget, text)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(type(text) == "function" and text(self) or text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a window you resize by the grip in its bottom-right corner; size kept in DB.frames[key]
local function makeResizable(frame, key, minW, minH, maxW, maxH, onSize, secure)
  DB.frames = DB.frames or {}
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW, maxH)
  else
    if frame.SetMinResize then frame:SetMinResize(minW, minH) end
    if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
  end
  local saved = DB.frames[key]
  if saved and saved.w and saved.h then
    frame:SetSize(math.max(minW, math.min(maxW, saved.w)), math.max(minH, math.min(maxH, saved.h)))
  end
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, mouse)
    if mouse ~= "LeftButton" then return end
    if secure and InCombatLockdown() then say("The panel can't be resized in combat."); return end
    frame.sizing = true
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    if not frame.sizing then return end
    frame.sizing = nil
    frame:StopMovingOrSizing()
    local w, h = frame:GetSize()
    DB.frames[key] = DB.frames[key] or {}
    DB.frames[key].w, DB.frames[key].h = math.floor(w + 0.5), math.floor(h + 0.5)
  end)
  frame.grip = grip
  frame:SetScript("OnSizeChanged", function(_, w, h) onSize(w, h) end)
  onSize(frame:GetSize())
end

local function keepPlace(frame, key, default)
  DB.frames = DB.frames or {}
  local p = DB.frames[key] and DB.frames[key].point
  frame:ClearAllPoints()
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint(unpack(default)) end
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, rp, x, y = self:GetPoint()
    DB.frames[key] = DB.frames[key] or {}
    DB.frames[key].point = { a, rp, x, y }
  end)
end

-- a movable dialog window with a title and a close button; Escape closes it
local function dialog(name, title, w, h, key, default)
  local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(w, h)
  f:SetFrameStrata("DIALOG")
  backdrop(f, 0.92)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  keepPlace(f, key, default)
  f:Hide()
  tinsert(UISpecialFrames, name)
  local tt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  tt:SetPoint("TOPLEFT", 12, -10)
  tt:SetText("|cff7fd4ffEnchantPro|r " .. title)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetPoint("TOPRIGHT", 0, 0)
  return f
end

local function toggle(f) if f then if f:IsShown() then f:Hide() else f:Show() end end end

-- the ledger window ----------------------------------------------------------------------

local ledgerFrame
local LEDGER_MAX_ROWS = 50
local SUM_ROWS = {
  { "Income",            function(T) return money(T.income) end },
  { "  of it tips",      function(T) return "|cff40ff40" .. money(T.tips) .. "|r" end },
  { "Enchants",          function(T) return tostring(T.sales) end },
  { "  their / my mats", function(T) return T.theirMats .. " / " .. T.myMats end },
  { "My mats used",      function(T) return T.matsCost > 0 and ("|cffff8040-" .. money(T.matsCost) .. "|r") or "-" end },
  { "Net profit",        function(T) local n = net(T); return (n < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(n)) .. "|r" end },
  { "Short / unpaid",    function(T) return T.short > 0 and ("|cffff4040" .. money(T.short) .. "|r" .. (T.unpaid > 0 and (" (" .. T.unpaid .. ")") or "")) or "-" end },
  { "Net per enchant",   function(T) if T.sales == 0 then return "-" end; local n = math.floor(net(T) / T.sales); return (n < 0 and "-" or "") .. money(math.abs(n)) end },
}

local function entryText(e)
  local txt
  if e.k == "sale" then
    local paid = (e.pre or 0) + e.g
    txt = (e.n or "?") .. ": " .. (e.en or "?") .. "  |cffffffff" .. money(e.g) .. "|r"
      .. (e.mode == "mats" and " |cffa0a0a0(their mats)|r" or (" |cffa0a0a0(my mats" .. ((e.m or 0) > 0 and (" -" .. money(e.m)) or "") .. ")|r"))
      .. ((e.tip or 0) > 0 and (" |cff40ff40+" .. money(e.tip) .. " tip|r") or "")
      .. (paid < e.p and (" |cffff4040" .. (paid == 0 and "unpaid" or (money(e.p - paid) .. " short")) .. "|r") or "")
  elseif e.k == "pay" then
    txt = (e.n or "?") .. " handed over " .. ((e.it and e.it ~= "") and e.it or "")
      .. ((e.g or 0) > 0 and (((e.it and e.it ~= "") and " + " or "") .. "|cffffffff" .. money(e.g) .. "|r") or "")
  else
    txt = tostring(e.k)
  end
  return "|cffa0a0a0" .. date("%m-%d %H:%M", e.t) .. "|r  " .. txt
end

function EP.ledgerRefresh()
  local lf = ledgerFrame
  if not lf or not lf:IsShown() then return end
  local sums = { ledgerSum(dayStart()), ledgerSum(time() - 7 * 86400), ledgerSum(nil) }
  for r, def in ipairs(SUM_ROWS) do
    for c = 1, 3 do lf.cells[r][c]:SetText(def[2](sums[c])) end
  end
  local L = DB.ledger
  local shown = lf.visible or 12
  lf.offset = math.max(0, math.min(lf.offset or 0, #L - shown))
  for i = 1, LEDGER_MAX_ROWS do
    local e = i <= shown and L[#L - lf.offset - i + 1] or nil
    lf.rows[i]:SetText(e and entryText(e) or "")
  end
  lf.empty:SetText(#L == 0 and "Nothing yet - mats handed over and enchants sold land here." or "")
end

local function buildLedger()
  local lf = dialog("EnchantProLedger", "ledger", 460, 430, "ledger", { "CENTER" })
  ledgerFrame = lf
  local reset = button(lf, 60, 18, "Reset")
  reset:SetPoint("RIGHT", lf.close, "LEFT", -2, 0)
  reset:SetScript("OnClick", function() StaticPopup_Show("ENCHANTPRO_RESET_LEDGER") end)
  tooltip(reset, "Delete the whole ledger (asks first).")

  for c, name in ipairs({ "Today", "7 days", "All time" }) do
    local h = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPRIGHT", lf, "TOPRIGHT", -14 - (3 - c) * 80, -38)
    h:SetText(name)
  end
  lf.cells = {}
  for r, def in ipairs(SUM_ROWS) do
    local y = -54 - (r - 1) * 16
    local label = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 14, y)
    label:SetText(def[1])
    lf.cells[r] = {}
    for c = 1, 3 do
      local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPRIGHT", lf, "TOPRIGHT", -14 - (3 - c) * 80, y)
      fs:SetJustifyH("RIGHT")
      lf.cells[r][c] = fs
    end
  end
  local note = lf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", 14, -54 - #SUM_ROWS * 16 - 6)
  note:SetText("My mats are priced from /ep matcost, else Auctionator's scan.")

  local head = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 14, -54 - #SUM_ROWS * 16 - 28)
  head:SetText("HISTORY  |cff808080newest first - scroll for more|r")
  lf.rows = {}
  for i = 1, LEDGER_MAX_ROWS do
    local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 14, -54 - #SUM_ROWS * 16 - 44 - (i - 1) * 16)
    fs:SetPoint("RIGHT", -14, 0)
    fs:SetJustifyH("LEFT")
    lf.rows[i] = fs
  end
  lf.empty = lf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  lf.empty:SetPoint("TOPLEFT", lf.rows[1], "TOPLEFT")
  lf:EnableMouseWheel(true)
  lf:SetScript("OnMouseWheel", function(self, delta)
    self.offset = (self.offset or 0) - delta * 3
    EP.ledgerRefresh()
  end)
  lf:SetScript("OnShow", function(self) self.offset = 0; EP.ledgerRefresh() end)
  local top = 54 + #SUM_ROWS * 16 + 44
  makeResizable(lf, "ledger", 460, 330, 1000, 1000, function(_, h)
    lf.visible = math.max(1, math.min(LEDGER_MAX_ROWS, math.floor((h - top - 22) / 16)))
    EP.ledgerRefresh()
  end)
end

function EP.resetLedger()
  DB.ledger, DB.totals = {}, newTotals()
  say("Ledger cleared.")
  EP.ledgerRefresh()
  if refresh then refresh() end
end

StaticPopupDialogs.ENCHANTPRO_RESET_LEDGER = {
  text = "Delete the whole EnchantPro ledger?\nThis cannot be undone.",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function() EP.resetLedger() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

function EP.toggleLedger() toggle(ledgerFrame) end

-- the messages window ---------------------------------------------------------------------

local msgFrame

local function setChecked(cb, v) if cb.SetChecked then cb:SetChecked(v and true or false) end end

local function addEditor(parent, y, def)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 14, y)
  label:SetText(def.label)
  local reset = button(parent, 70, 20, "Default")
  reset:SetPoint("TOPRIGHT", -14, y + 3)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetHeight(20)
  eb:SetPoint("TOPLEFT", 22, y - 18)
  eb:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(255)
  local pv = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pv:SetPoint("TOPLEFT", 16, y - 42)
  pv:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  pv:SetJustifyH("LEFT")
  local tk = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tk:SetPoint("TOPLEFT", 16, y - 58)
  tk:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  tk:SetJustifyH("LEFT")
  tk:SetText(def.tokens)

  local ed = { eb = eb, pv = pv }
  function ed.update()
    local raw = eb:GetText()
    local text = def.preview(type(raw) == "string" and raw or "")
    local over = string.len(text) > 255
    pv:SetText("|cff808080Preview:|r " .. text
      .. (over and ("  |cffff4040too long for chat: " .. string.len(text) .. " / 255|r") or ""))
  end
  function ed.load()
    eb:SetText(def.get() or def.default)
    if eb.SetCursorPosition then eb:SetCursorPosition(0) end
    ed.update()
  end
  function ed.save()
    local t = strtrim(eb:GetText() or "")
    local new = t
    if t == "" or t == def.default then new = nil end
    if new ~= def.get() then
      def.set(new)
      say(def.label .. (new and " saved." or " back to the standard text."))
    end
    ed.load()
  end
  eb:SetScript("OnTextChanged", function() ed.update() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function() ed.save() end)
  eb:SetScript("OnEscapePressed", function(self) ed.load(); self:ClearFocus() end)
  reset:SetScript("OnClick", function() eb:SetText(def.default); ed.save() end)
  return ed
end

local function stored(key) return function() return (DB[key] and DB[key] ~= "") and DB[key] or nil end end
local function store(key) return function(v) DB[key] = v end end

local function buildMessages()
  local mf = dialog("EnchantProMessages", "messages", 520, 420, "messages", { "CENTER", UIParent, "CENTER", 0, 120 })
  msgFrame = mf
  local hint = mf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPRIGHT", -36, -16)
  hint:SetText("Enter saves - Escape undoes")
  local B = { name = "Bob", full = "Bob" }
  mf.eds = {
    addEditor(mf, -44, { label = "Trade ad", default = AD_DEFAULT, tokens = AD_TOKENS, get = stored("ad"), set = store("ad"),
      preview = function(t) return adText(t ~= "" and t or AD_DEFAULT) end }),
    addEditor(mf, -128, { label = "Reply (they named an enchant)", default = REPLY_DEFAULT, tokens = REPLY_TOKENS,
      get = stored("replyText"), set = store("replyText"),
      preview = function(t) return replyText(B, sampleRec(), t ~= "" and t or REPLY_DEFAULT) end }),
    addEditor(mf, -212, { label = "Reply (no enchant named yet)", default = ASK_DEFAULT, tokens = ASK_TOKENS,
      get = stored("askText"), set = store("askText"),
      preview = function(t) return askText(B, t ~= "" and t or ASK_DEFAULT) end }),
    addEditor(mf, -296, { label = "Thank-you", default = THANKS_DEFAULT,
      tokens = THANKS_TOKENS .. "\n|cff808080A trade that falls short always says how much is missing instead.|r",
      get = stored("thanksText"), set = store("thanksText"),
      preview = function(t) return thanksText(B, sampleRec().label, 3000, 1000, 2000, 2000, t ~= "" and t or THANKS_DEFAULT) end }),
  }
  local function check(x, y, text, key)
    local cb = CreateFrame("CheckButton", nil, mf, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = mf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self) DB[key] = self:GetChecked() and true or false end)
    cb.key = key
    return cb
  end
  mf.checks = { check(110, -292, "after every enchant", "thanks"), check(250, -292, "in /say, not a whisper", "thanksSay") }
  makeResizable(mf, "messages", 520, 420, 1100, 560, function()
    for _, ed in ipairs(mf.eds) do ed.update() end
  end)
  mf:SetScript("OnShow", function(self)
    for _, ed in ipairs(self.eds) do ed.load() end
    for _, cb in ipairs(self.checks) do setChecked(cb, DB[cb.key]) end
  end)
end

function EP.toggleMessages() toggle(msgFrame) end

-- the enchants window: what you know, and its fee, full price and ad tick ---------------------

local enchFrame
local ENCH_MAX_ROWS = 40

local function moneyBox(parent, w)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(w, 18)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(12)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return eb
end

function EP.enchantsRefresh()
  local ef = enchFrame
  if not ef or not ef:IsShown() then return end
  ef.fee:SetText(money(DB.fee))
  local shown = ef.visible or 10
  ef.offset = math.max(0, math.min(ef.offset or 0, #knownList - shown))
  for i = 1, ENCH_MAX_ROWS do
    local row = ef.rows[i]
    local r = i <= shown and knownList[ef.offset + i] or nil
    row.rec = r
    if r then
      setChecked(row.ad, DB.adList[r.id])
      row.label:SetText(r.label)
      row.fee:SetText(DB.fees[r.id] and money(DB.fees[r.id]) or "")
      row.full:SetText(DB.fulls[r.id] and money(DB.fulls[r.id]) or "")
      row.mats:SetText(matsText(r, true))
      row:Show()
    else
      row:Hide()
    end
  end
  ef.empty:SetText(#knownList == 0
    and "No enchants yet. Open your Enchanting window (the profession) once - EnchantPro reads your enchants from it." or "")
end

local function buildEnchants()
  local ef = dialog("EnchantProEnchants", "enchants", 560, 400, "enchants", { "CENTER", UIParent, "CENTER", -40, 40 })
  enchFrame = ef
  ef.offset = 0

  local feeLabel = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  feeLabel:SetPoint("TOPLEFT", 14, -40)
  feeLabel:SetText("Fee with their mats:")
  ef.fee = moneyBox(ef, 70)
  ef.fee:SetPoint("LEFT", feeLabel, "RIGHT", 10, 0)
  ef.fee:SetScript("OnEditFocusLost", function(self)
    local c = parseMoney(self:GetText())
    if c and c ~= DB.fee then DB.fee = c; say("Fee: " .. money(c) .. ".") end
    EP.enchantsRefresh()
    if refresh then refresh() end
  end)
  local feeHint = ef:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  feeHint:SetPoint("LEFT", ef.fee, "RIGHT", 10, 0)
  feeHint:SetText("for every enchant without its own fee. Blank full price: not offered.")

  local heads = { { "Ad", 16 }, { "Enchant", 42 }, { "Fee", 212 }, { "Full", 290 }, { "Mats (in your bags)", 366 } }
  for _, h in ipairs(heads) do
    local fs = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", h[2], -66)
    fs:SetText(h[1])
  end

  ef.rows = {}
  for i = 1, ENCH_MAX_ROWS do
    local row = CreateFrame("Frame", nil, ef)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 10, -80 - (i - 1) * 22)
    row:SetPoint("RIGHT", -14, 0)
    row.ad = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.ad:SetSize(20, 20)
    row.ad:SetPoint("LEFT", 2, 0)
    row.ad:SetScript("OnClick", function(self)
      local r = row.rec
      if r then DB.adList[r.id] = self:GetChecked() and true or nil end
    end)
    tooltip(row.ad, "Name this enchant in the ad.")
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 32, 0)
    row.label:SetWidth(166)
    row.label:SetJustifyH("LEFT")
    row.fee = moneyBox(row, 64)
    row.fee:SetPoint("LEFT", 206, 0)
    row.full = moneyBox(row, 64)
    row.full:SetPoint("LEFT", 284, 0)
    row.mats = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mats:SetPoint("LEFT", 356, 0)
    row.mats:SetPoint("RIGHT", 0, 0)
    row.mats:SetJustifyH("LEFT")
    -- the box keeps which enchant it was loaded for: a scroll while it has focus can't save to another
    local function onFocus(self) self.recId = row.rec and row.rec.id end
    row.fee:SetScript("OnEditFocusGained", onFocus)
    row.full:SetScript("OnEditFocusGained", onFocus)
    row.fee:SetScript("OnEditFocusLost", function(self)
      local id = self.recId
      if not id then return end
      local txt = strtrim(self:GetText() or "")
      local c = txt ~= "" and parseMoney(txt) or nil
      if txt ~= "" and not c then say("Write prices like 25s or 1g50s.")
      elseif c == DB.fee then DB.fees[id] = nil
      else DB.fees[id] = c end
      EP.enchantsRefresh()
    end)
    row.full:SetScript("OnEditFocusLost", function(self)
      local id = self.recId
      if not id then return end
      local txt = strtrim(self:GetText() or "")
      local c = txt ~= "" and parseMoney(txt) or nil
      if txt ~= "" and not c then say("Write prices like 25s or 1g50s.")
      elseif c and c > 0 then DB.fulls[id] = c
      else DB.fulls[id] = nil end
      EP.enchantsRefresh()
    end)
    row:EnableMouse(true)
    tooltip(row, function(self) return self.rec and (self.rec.name .. "\n" .. matsText(self.rec)) or "" end)
    ef.rows[i] = row
  end
  ef.empty = ef:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ef.empty:SetPoint("TOPLEFT", 14, -84)
  ef.empty:SetPoint("RIGHT", -14, 0)
  ef.empty:SetJustifyH("LEFT")

  ef:EnableMouseWheel(true)
  ef:SetScript("OnMouseWheel", function(self, delta)
    for _, row in ipairs(self.rows) do row.fee:ClearFocus(); row.full:ClearFocus() end
    self.offset = (self.offset or 0) - delta * 3
    EP.enchantsRefresh()
  end)
  ef:SetScript("OnShow", function() EP.enchantsRefresh() end)
  makeResizable(ef, "enchants", 560, 240, 1000, 1000, function(_, h)
    ef.visible = math.max(1, math.min(ENCH_MAX_ROWS, math.floor((h - 80 - 22) / 22)))
    EP.enchantsRefresh()
  end)
end

function EP.toggleEnchants() toggle(enchFrame) end

-- the panel ---------------------------------------------------------------------------------

local function savePoint()
  local p, _, rp, x, y = panel:GetPoint()
  DB.point = { p, rp, x, y }
end

local function buildPanel()
  panel = CreateFrame("Frame", "EnchantProPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetSize(320, 290)
  panel:SetFrameStrata("MEDIUM")
  backdrop(panel, 0.85)
  if DB.point then
    panel:SetPoint(DB.point[1], UIParent, DB.point[2], DB.point[3], DB.point[4])
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
  end
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("|cff7fd4ffEnchantPro|r")
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() EP.togglePanel(false) end)
  local ledgerB = button(panel, 54, 18, "Ledger")
  ledgerB:SetPoint("RIGHT", close, "LEFT", -2, 0)
  ledgerB:SetScript("OnClick", function() EP.toggleLedger() end)
  local msgB = button(panel, 68, 18, "Messages")
  msgB:SetPoint("RIGHT", ledgerB, "LEFT", -2, 0)
  msgB:SetScript("OnClick", function() EP.toggleMessages() end)
  local enchB = button(panel, 66, 18, "Enchants")
  enchB:SetPoint("RIGHT", msgB, "LEFT", -2, 0)
  enchB:SetScript("OnClick", function() EP.toggleEnchants() end)
  tooltip(enchB, "Your enchants: fee, full price, mats, and which ones the ad names.")

  panel.info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.info:SetPoint("TOPLEFT", 12, -32)
  panel.info:SetPoint("RIGHT", -12, 0)
  panel.info:SetJustifyH("LEFT")

  panel.ad = button(panel, 146, 22, "Post ad")
  panel.ad:SetPoint("TOPLEFT", 10, -50)
  panel.ad:SetScript("OnClick", function() EP.postAd() end)
  panel.accept = button(panel, 146, 22, "Accept trade")
  panel.accept:SetPoint("TOPRIGHT", -10, -50)
  panel.accept:SetScript("OnClick", function() EP.accept() end)

  local prev = button(panel, 24, 28, "<")
  prev:SetPoint("TOPLEFT", 10, -78)
  prev:SetScript("OnClick", function() cycle(-1) end)
  local nextB = button(panel, 24, 28, ">")
  nextB:SetPoint("TOPRIGHT", -10, -78)
  nextB:SetScript("OnClick", function() cycle(1) end)

  -- the one secure button: casting needs the player's own click or key
  castBtn = CreateFrame("Button", "EnchantProCastButton", panel, "UIPanelButtonTemplate,SecureActionButtonTemplate")
  castBtn:SetPoint("TOPLEFT", prev, "TOPRIGHT", 2, 0)
  castBtn:SetPoint("BOTTOMRIGHT", nextB, "BOTTOMLEFT", -2, 0)
  local down = safe(GetCVarBool, "ActionButtonUseKeyDown")
  castBtn:RegisterForClicks(down and "AnyDown" or "AnyUp")

  panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 12, -112)
  panel.status:SetPoint("RIGHT", -12, 0)
  panel.status:SetJustifyH("LEFT")

  local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 12, -130)
  head:SetText("BUYERS  |cff808080click: trade / reply - right-click: remove|r")

  for i = 1, PANEL_MAX_ROWS do
    local r = CreateFrame("Button", nil, panel)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 12, -146 - (i - 1) * 18)
    r:SetPoint("RIGHT", -12, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 2, 0)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -2, 0)
    r:SetScript("OnClick", function(self, mouse)
      local b = self.buyer
      if not b then return end
      if mouse == "RightButton" then
        buyers[b.key] = nil
      elseif b.unit and b.near then
        openTrade(b, b.unit)
      else
        local rec = b.rec and REC[b.rec]
        whisper(b, rec and replyText(b, rec) or askText(b))
        if not b.unit then say(b.name .. " isn't near - target them or wait until they come, then click again.") end
      end
      refresh()
    end)
    rows[i] = r
  end

  local defs = { { "listen", "Listen" }, { "reply", "Reply" }, { "autoTrade", "Trade" }, { "thanks", "Thanks" } }
  local tips = {
    listen = "Look for buyers in Trade, General, LFG, say and yell.",
    reply = "Answer buyers with the price and mats (in the chat box - your Enter sends it).",
    autoTrade = "Open trade with buyers who come in range.",
    thanks = "A thank-you after every enchant, saying what was paid.",
  }
  for i, d in ipairs(defs) do
    local t = button(panel, 68, 20, d[2])
    t:SetPoint("BOTTOMLEFT", 10 + (i - 1) * 70, 10)
    t.key, t.label = d[1], d[2]
    t:SetScript("OnClick", function(self)
      DB[self.key] = not DB[self.key]
      if self.key == "autoTrade" then EP.tradeBlocked = nil end
      refresh()
    end)
    tooltip(t, tips[d[1]])
    toggles[i] = t
  end

  makeResizable(panel, "panel", 320, 290, 700, 800, function(w, h)
    local half = math.floor((w - 24) / 2)
    panel.ad:SetWidth(half)
    panel.accept:SetWidth(half)
    local tw = math.floor((w - 20 - 20 - 3 * 2) / #toggles)
    for i, t in ipairs(toggles) do
      t:SetWidth(tw)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", 10 + (i - 1) * (tw + 2), 10)
    end
    panel.visibleRows = math.max(1, math.min(PANEL_MAX_ROWS, math.floor((h - 146 - 36) / 18)))
    if refresh then refresh() end
  end, true)

  if not DB.shown then panel:Hide() end
end

refresh = function()
  if not panel or not panel:IsShown() then return end
  local today = net(ledgerSum(dayStart()))
  panel.info:SetText(string.format("Enchants: %d   Today net: %s   Fee: %s", #knownList,
    (today < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(today)) .. "|r", money(DB.fee)))
  local left = adLeft()
  panel.ad:SetText(left > 0 and string.format("Post ad (%d:%02d)", math.floor(left / 60), left % 60) or "Post ad")
  local tf = _G.TradeFrame
  if tf and tf:IsShown() then panel.accept:Enable() else panel.accept:Disable() end

  local status = tradeLine()
  if not status then
    if #knownList == 0 then status = "|cffffd200Open your Enchanting window once so I learn your enchants.|r"
    elseif restricted() then status = "|cff808080This realm blocks addon chat: replies go into the chat box, Enter sends.|r"
    else status = "" end
  end
  panel.status:SetText(status)

  local list = sortedBuyers()
  for i, row in ipairs(rows) do
    local b = i <= (panel.visibleRows or 6) and list[i] or nil
    row.buyer = b
    if b then
      local what = b.rec and REC[b.rec] and REC[b.rec].label or b.want or (b.slot and (SLOT[b.slot].label .. "?")) or "?"
      row.left:SetText(b.name .. "  |cffa0a0a0" .. what .. "|r")
      row.right:SetText(b.cant and "|cff808080not yours|r"
        or ((STATE_TEXT[b.state] or b.state) .. (b.near and b.state ~= "done" and " |cff40ff40near|r" or "")))
      row:Show()
    else
      row:Hide()
    end
  end
  for _, t in ipairs(toggles) do t:SetText(t.label .. " " .. onOff(DB[t.key])) end
end

function EP.togglePanel(show)
  if not panel then return end
  if InCombatLockdown() then say("The panel can't be shown or hidden in combat."); return end
  if show == nil then show = not panel:IsShown() end
  if show then panel:Show() else panel:Hide() end
  DB.shown = show
  refresh()
end

-- ---------------------------------------------------------------------------------------
-- events

local function initDB()
  EnchantProDB = EnchantProDB or {}
  DB = EnchantProDB
  for k, v in pairs(DEFAULTS) do
    if DB[k] == nil then DB[k] = type(v) == "table" and {} or v end
  end
  DB.ledger = DB.ledger or {}
  DB.totals = DB.totals or newTotals()
  for k, v in pairs(newTotals()) do if DB.totals[k] == nil then DB.totals[k] = v end end
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
    "UI_INFO_MESSAGE", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED",
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
  buildLedger()
  buildMessages()
  buildEnchants()
  registerAll()
  EP.updateCast()
  C_Timer.NewTicker(0.5, tick)
  if #knownList == 0 then
    say("Open your Enchanting window once so I learn your enchants. /ep help")
  else
    say("Ready: " .. #knownList .. " enchants, fee " .. money(DB.fee) .. ". /ep help")
  end
end

local scanPending
local function scheduleScan()
  if scanPending then return end
  scanPending = true
  C_Timer.After(0.3, function() scanPending = nil; EP.scanProfession() end)
end

f:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
  if ev == "ADDON_LOADED" then
    if a1 == ADDON then initDB() end
  elseif ev == "PLAYER_LOGIN" then
    myName = fullName("player") or ""
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
    if DB.listen then
      local where = (not isSecret(a9) and type(a9) == "string" and a9) or (not isSecret(a4) and type(a4) == "string" and a4) or "chat"
      request(a2, a1, "chat", where)
    end
  elseif ev == "CHAT_MSG_SAY" or ev == "CHAT_MSG_YELL" then
    if DB.listen then request(a2, a1, "say", ev == "CHAT_MSG_SAY" and "say" or "yell") end
  elseif ev == "CHAT_MSG_WHISPER" then
    request(a2, a1, "whisper", "whisper")
  elseif ev == "TRADE_SHOW" then
    EP.trade = { name = partnerName(), money = 0, items = {} }
    readTrade(); EP.updateCast(); updateOverlay(); refresh()
  elseif ev == "TRADE_MONEY_CHANGED" or ev == "TRADE_TARGET_ITEM_CHANGED" or ev == "TRADE_UPDATE" then
    if EP.trade then readTrade() end
    EP.updateCast(); updateOverlay(); refresh()
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
    updateOverlay(); refresh()
  elseif ev == "TRADE_CLOSED" then
    if EP.trade then EP.lastTrade = EP.trade end
    EP.trade = nil
    for _, b in pairs(buyers) do if b.state == "trading" then b.state = b.given and "mats" or "asked" end end
    EP.updateCast(); updateOverlay(); refresh()
  elseif ev == "UI_INFO_MESSAGE" then
    if a1 == ERR_TRADE_COMPLETE or a2 == ERR_TRADE_COMPLETE then tradeDone() end
  elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 == "player" and not isSecret(a3) and type(a3) == "number" and REC[a3] and EP.trade then
      EP.trade.castRec = a3
      updateOverlay(); refresh()
    end
  elseif ev == "PLAYER_REGEN_ENABLED" then
    if EP.castDirty then EP.updateCast() end
  elseif ev == "BAG_UPDATE_DELAYED" then
    EP.updateCast(); EP.enchantsRefresh(); refresh()
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
  "/ep fee 25s - the fee with the buyer's mats, for every enchant without its own",
  "/ep price +7 sta bracer 30s 1g - one enchant's fee and full price (full: off to stop offering it)",
  "/ep matcost <item id or name> 5s - what a mat costs you (else Auctionator's price). off - forget it",
  "/ep messages - edit the ad, replies and thank-you (or the Messages button)",
  "/ep ad - show the ad.  /ep cd 90 - seconds between ads",
  "/ep listen | reply | trade | thanks | whisper | sound - turn one on / off",
  "/ep ledger - the ledger window.  /ep stats - today / 7 days / all time in chat.  /ep ledger reset",
  "/ep test <line> - would this chat line count as a buyer, and for which enchant?",
  "Keys: Game Menu > Key Bindings > EnchantPro (Post ad, Cast enchant, Accept trade).",
}

local SWITCHES = { listen = "listen", reply = "reply", trade = "autoTrade", thanks = "thanks", whisper = "whisper", sound = "sound" }

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
    if not c then say("Fee now " .. money(DB.fee) .. ". Write it like /ep fee 25s."); return end
    DB.fee = c
    say("Fee: " .. money(c) .. (c == 0 and " (tips)" or "") .. ".")
    EP.enchantsRefresh(); refresh()
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
    if fee then DB.fees[r.id] = (fee ~= DB.fee) and fee or nil end
    if prices[2] then
      local full = parseMoney(prices[2])
      DB.fulls[r.id] = (full and full > 0) and full or nil
    end
    say(r.label .. ": fee " .. money(feeFor(r)) .. ", full " .. (fullFor(r) and money(fullFor(r)) or "not offered") .. ".")
    EP.enchantsRefresh()
  elseif cmd == "matcost" then
    local what, val = string.match(rest, "^(.-)%s+(%S+)$")
    if not what then say("Write it like /ep matcost Strange Dust 5s."); return end
    local id = tonumber(what) or itemIdOf(what)
    if not id then
      local lw = string.lower(what)
      for iid, n in pairs(DB.itemNames) do if string.lower(n) == lw then id = iid end end
    end
    if not id then say("Unknown mat - use the item id, a link, or the name of a mat one of your enchants takes."); return end
    if string.lower(val) == "off" then DB.matCost[id] = nil; say(itemName(id) .. ": back to Auctionator's price."); return end
    local c = parseMoney(val)
    if not c then say("Write the cost like 5s."); return end
    DB.matCost[id] = c
    say(itemName(id) .. ": " .. money(c) .. " each.")
  elseif cmd == "messages" or cmd == "msg" then
    EP.toggleMessages()
  elseif cmd == "ad" then
    say("Ad: " .. adText())
  elseif cmd == "cd" then
    local n = tonumber(rest)
    if not n or n < 15 then say("Seconds between ads, 15 or more."); return end
    DB.adCooldown = math.floor(n)
    say("Ads every " .. DB.adCooldown .. " s at most.")
    refresh()
  elseif SWITCHES[cmd] then
    local k = SWITCHES[cmd]
    DB[k] = not DB[k]
    if k == "autoTrade" then EP.tradeBlocked = nil end
    say(cmd .. ": " .. onOff(DB[k]))
    refresh()
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
EP._test = { readLinks = readLinks, dropRecipeItems = dropRecipeItems, channelIntent = channelIntent, whisperIntent = whisperIntent, analyze = analyze, findEnchant = findEnchant,
  clean = clean, parseMoney = parseMoney, money = money, quote = quote, buyers = buyers, REC = function() return REC end,
  knownList = function() return knownList end, tradeLine = tradeLine, cycle = cycle }
