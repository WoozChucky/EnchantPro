-- EnchantPro - sell enchants with as little clicking as the game allows.
--
-- How an enchant is sold: the buyer opens trade with the item in the bottom "Will not be traded" slot, you cast
-- the enchant on that slot and both accept. The mats must be in YOUR bags when you cast, so a "your mats" sale is
-- two trades: the buyer hands the mats over first (the addon remembers what they gave), then the item.
-- With the buyer's mats an enchant is free (tips welcome) unless you set a fee: one for all, or one per enchant.
-- With your mats it has a full price, if you set one.
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

local ADDON, ns = ...

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

local TIER_RANK = { inferior = 0, minor = 1, lesser = 2, greater = 4, superior = 5, major = 6 }

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
  fee = 0,              -- copper, with the buyer's mats: 0 = no fee, tips only
  fees = {},            -- [recipe id] = fee for that enchant
  fulls = {},           -- [recipe id] = full price with your mats (none: not offered)
  adList = {},          -- [recipe id] = true: named in the ad
  matCost = {},         -- [item id] = what a mat costs you (else Auctionator's price)
  itemNames = {},       -- [item id] = name, for mats the game has not loaded
  chars = {},           -- [character] = { recipes = { [id] = { name, amount, reagents } } }
  adCooldown = 60,
  listen = true,        -- look for buyers in public chat
  reply = true,         -- answer buyers (in the chat box where the realm refuses addon chat)
  invite = true,        -- invite buyers to the group, so you see where they are
  autoKick = true,      -- out of the group again after the enchant (only buyers EnchantPro invited)
  thanks = true,        -- a thank-you after every enchant
  thanksSay = false,    -- in /say instead of a whisper
  whisper = true,
  sound = true,
  shown = true,
  queues = {},          -- [character] = the waiting orders, saved at logout / reload
  blocked = {},         -- [lower name] = name: never listed, never answered
  nextOrder = 1,        -- the next queue number
}


local PANEL_MAX_ROWS = 20
local buyers = {}       -- [lower-case name] = buyer
EP.sellers = {}         -- [lower-case name] = when they last advertised enchanting: their chat lines are skipped
ns.REC = {}          -- [recipe id] = this character's enchant: id, name, slot, eff, keys, tier, amount, reagents, label
ns.knownList = {}    -- REC sorted: slot, then best first
ns.myName = ""
ns.panel = nil
ns.castBtn = nil
local rows = {}
local toggles = {}


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
    ns.DB.itemNames[id] = n
    return n
  end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return ns.DB.itemNames[id] or ("item " .. id)
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
  if ns.DB.matCost[id] then return ns.DB.matCost[id] end
  local api = rawget(_G, "Auctionator") and Auctionator.API and Auctionator.API.v1
  if api and api.GetAuctionPriceByItemID then
    local p = safe(api.GetAuctionPriceByItemID, "EnchantPro", id)
    if type(p) == "number" and p > 0 then return p end
  end
  return nil
end

local function playSound()
  if not ns.DB.sound then return end
  local id = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
  pcall(PlaySound, id, "Master")
end

local function zoneText()
  local z = safe(GetMinimapZoneText)
  if type(z) ~= "string" or z == "" then z = safe(GetZoneText) end
  return (type(z) == "string" and z ~= "") and z or "town"
end

ns.EP = EP
ns.ENCHANTING = ENCHANTING
ns.SLOTS = SLOTS
ns.SLOT = SLOT
ns.SLOT_ORDER = SLOT_ORDER
ns.SLOT_WORD = SLOT_WORD
ns.EQUIP = EQUIP
ns.TIER_RANK = TIER_RANK
ns.PHRASES = PHRASES
ns.SYN = SYN
ns.EFFECT_WORDS = EFFECT_WORDS
ns.DISTINCT = DISTINCT
ns.STOP = STOP
ns.STAT_SHORT = STAT_SHORT
ns.DEFAULTS = DEFAULTS
ns.PANEL_MAX_ROWS = PANEL_MAX_ROWS
ns.buyers = buyers
ns.rows = rows
ns.toggles = toggles
ns.isSecret = isSecret
ns.safe = safe
ns.say = say
ns.now = now
ns.shortName = shortName
ns.money = money
ns.fill = fill
ns.parseMoney = parseMoney
ns.spellName = spellName
ns.bagCount = bagCount
ns.itemName = itemName
ns.itemIdOf = itemIdOf
ns.equipLoc = equipLoc
ns.matCost = matCost
ns.playSound = playSound
ns.zoneText = zoneText
