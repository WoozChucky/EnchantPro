-- EnchantPro - your enchants: read from the Enchanting window, kept per character, priced.
local ADDON, ns = ...
local EP = ns.EP
local ENCHANTING = ns.ENCHANTING
local SLOTS = ns.SLOTS
local SLOT = ns.SLOT
local SLOT_ORDER = ns.SLOT_ORDER
local TIER_RANK = ns.TIER_RANK
local PHRASES = ns.PHRASES
local SYN = ns.SYN
local STOP = ns.STOP
local STAT_SHORT = ns.STAT_SHORT
local safe = ns.safe
local say = ns.say
local bagCount = ns.bagCount
local itemName = ns.itemName

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
  ns.REC, ns.knownList = {}, {}
  local saved = ns.DB.chars[ns.myName] and ns.DB.chars[ns.myName].recipes or {}
  for id, s in pairs(saved) do
    local r = parseRecipe(id, s)
    if r then ns.REC[id] = r; ns.knownList[#ns.knownList + 1] = r end
  end
  table.sort(ns.knownList, function(a, b)
    if a.slot ~= b.slot then return SLOT_ORDER[a.slot] < SLOT_ORDER[b.slot] end
    if a.rank ~= b.rank then return a.rank > b.rank end
    if (a.amount or 0) ~= (b.amount or 0) then return (a.amount or 0) > (b.amount or 0) end
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
  local before = #ns.knownList
  ns.DB.chars[ns.myName] = { recipes = mine }
  rebuildKnown()
  if #ns.knownList ~= before then
    say("Knows " .. #ns.knownList .. " enchants now.")
  end
  if EP.enchantsRefresh then EP.enchantsRefresh() end
  if EP.updateCast then EP.updateCast() end
  if ns.refresh then ns.refresh() end
end

local function feeFor(r) return (r and ns.DB.fees[r.id]) or ns.DB.fee end
local function fullFor(r) return r and ns.DB.fulls[r.id] or nil end

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

ns.canon = canon
ns.parseRecipe = parseRecipe
ns.rebuildKnown = rebuildKnown
ns.feeFor = feeFor
ns.fullFor = fullFor
ns.matsText = matsText
ns.canCast = canCast
