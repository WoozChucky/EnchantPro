-- EnchantPro - the ledger: what was sold and paid, and the totals.
local ADDON, ns = ...
local EP = ns.EP

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
  local L = ns.DB.ledger
  L[#L + 1] = e
  while #L > LEDGER_MAX do table.remove(L, 1) end
  addTo(ns.DB.totals, e)
  if EP.ledgerRefresh then EP.ledgerRefresh() end
end

-- Once: until 0.5.3 both addons logged some trades. A gold-only "pay" here that PortalPro logged as a trade
-- (same name, within 15 s) was a portal payment: taken out, and out of the totals.
-- an enchant sale to n in the 30 minutes from t: gold handed over at t was paying for it
local function saleAfter(L, n, t)
  for _, o in ipairs(L) do
    if o.k == "sale" and o.n == n and (o.t or 0) >= (t or 0) and (o.t or 0) - (t or 0) <= 1800 then return true end
  end
  return false
end

local function splitLedger()
  if ns.DB.ledgerSplit then return end
  ns.DB.ledgerSplit = true
  local other = type(PortalProDB) == "table" and type(PortalProDB.ledger) == "table" and PortalProDB.ledger
  if not other then return end
  local L, keep, gone = ns.DB.ledger, {}, 0
  for _, e in ipairs(L) do
    local drop = false
    if e.k == "pay" and (e.g or 0) > 0 and (e.it == nil or e.it == "") and not saleAfter(L, e.n, e.t) then
      for _, o in ipairs(other) do
        if o.k == "trade" and o.n == e.n and math.abs((o.t or 0) - (e.t or 0)) <= 15 then drop = true; break end
      end
    end
    if drop then
      ns.DB.totals.income = ns.DB.totals.income - (e.g or 0)
      gone = gone + 1
    else
      keep[#keep + 1] = e
    end
  end
  if gone > 0 then
    for i = #L, 1, -1 do L[i] = nil end
    for i, e in ipairs(keep) do L[i] = e end
    ns.say(gone .. " portal payment(s) PortalPro had logged too were taken out of this ledger.")
  end
end

local function ledgerSum(since)
  if not since then return ns.DB.totals end
  local T = newTotals()
  for _, e in ipairs(ns.DB.ledger) do if e.t >= since then addTo(T, e) end end
  return T
end

local function net(T) return T.income - T.matsCost end

local function dayStart()
  local d = date("*t")
  d.hour, d.min, d.sec = 0, 0, 0
  return time(d)
end

-- the last n days, oldest first: { day = start of that day, income, tips }
local function ledgerDays(n)
  local today = dayStart()
  local out = {}
  for i = 1, n do out[i] = { day = today - (n - i) * 86400, income = 0, tips = 0 } end
  local first = out[1].day
  for _, e in ipairs(ns.DB.ledger) do
    if e.t and e.t >= first then
      local i = math.min(n, math.floor((e.t - first) / 86400) + 1)
      local d = out[i]
      if e.k == "pay" then
        d.income = d.income + (e.g or 0)
      elseif e.k == "sale" then
        d.income = d.income + (e.g or 0)
        d.tips = d.tips + (e.tip or 0)
      end
    end
  end
  return out
end

-- the enchants that brought in most (everything paid for them, before and in the trade), up to k
local function bestSellers(k)
  local by, list = {}, {}
  for _, e in ipairs(ns.DB.ledger) do
    if e.k == "sale" and e.en then
      local s = by[e.en]
      if not s then s = { label = e.en, count = 0, income = 0 }; by[e.en] = s; list[#list + 1] = s end
      s.count = s.count + 1
      s.income = s.income + (e.g or 0) + (e.pre or 0)
    end
  end
  table.sort(list, function(a, b) if a.income ~= b.income then return a.income > b.income end return a.count > b.count end)
  while #list > k do table.remove(list) end
  return list
end

-- enchants paid short or not at all: how many, and how much is missing
local function owing()
  local n, c = 0, 0
  for _, e in ipairs(ns.DB.ledger) do
    if e.k == "sale" and e.p then
      local paid = (e.pre or 0) + (e.g or 0)
      if paid < e.p then n, c = n + 1, c + (e.p - paid) end
    end
  end
  return n, c
end

ns.ledgerDays = ledgerDays
ns.bestSellers = bestSellers
ns.owing = owing
ns.newTotals = newTotals
ns.ledgerAdd = ledgerAdd
ns.splitLedger = splitLedger
ns.ledgerSum = ledgerSum
ns.net = net
ns.dayStart = dayStart
