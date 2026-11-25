-- EnchantPro - the queue: every buyer you can serve gets a number when first listed, and keeps it. Waiting
-- orders stay until they're done, removed, or quiet for 2 hours, and they're saved through a reload or restart.
local ADDON, ns = ...
local buyers = ns.buyers
local now = ns.now

local QUIET = 7200   -- a waiting order with no word from the buyer for this long is dropped

-- live fields: worked out again after a load, never saved
local LIVE = { unit = true, near = true, inGroup = true, zone = true, queued = true, kickAt = true, new = true,
  joinedAt = true, tradeTry = true, tradeTries = true, doneAt = true }
-- times kept as GetTime(): saved as wall-clock, since GetTime() starts over with the client
local TIMES = { at = true, since = true, invitedAt = true, refusedAt = true }

local function enqueue(b)
  if not b or b.n or b.cant then return end
  b.n = ns.DB.nextOrder or 1
  ns.DB.nextOrder = b.n + 1
  b.since = now()
end

local function isWaiting(b)
  return b.n ~= nil and b.state ~= "done" and not b.cant
end

local function waitingList()
  local list = {}
  for _, b in pairs(buyers) do if isWaiting(b) then list[#list + 1] = b end end
  table.sort(list, function(a, b) return a.n < b.n end)
  return list
end

-- 1 for the next in line
local function place(b)
  if not isWaiting(b) then return nil end
  local p = 1
  for _, o in pairs(buyers) do if o ~= b and isWaiting(o) and o.n < b.n then p = p + 1 end end
  return p
end

-- waiting by number, then just finished (newest first), then those you can't serve (newest first)
local function queueList()
  local list = waitingList()
  local done, rest = {}, {}
  for _, b in pairs(buyers) do
    if not isWaiting(b) then
      if b.state == "done" then done[#done + 1] = b else rest[#rest + 1] = b end
    end
  end
  table.sort(done, function(a, b) return (a.doneAt or 0) > (b.doneAt or 0) end)
  table.sort(rest, function(a, b) return (a.at or 0) > (b.at or 0) end)
  for _, b in ipairs(done) do list[#list + 1] = b end
  for _, b in ipairs(rest) do list[#list + 1] = b end
  return list
end

-- ---------------------------------------------------------------------------------------
-- an order's enchants: b.wants = { { id = recipe id, done = true|nil }, ... } in the order asked.
-- b.rec is the first open one (what most of the addon reads), b.slot its slot.

local function syncRec(b)
  b.rec = nil
  for _, w in ipairs(b.wants or {}) do
    if not w.done then b.rec = w.id; break end
  end
  local r = b.rec and ns.REC[b.rec]
  if r then b.slot = r.slot end
end

local function openWants(b)
  local list = {}
  for _, w in ipairs(b and b.wants or {}) do if not w.done then list[#list + 1] = w.id end end
  return list
end

-- r named in chat: a new enchant joins the order; one for a slot already wanted replaces it (a correction).
-- true when the order changed.
local function addWant(b, r)
  b.wants = b.wants or {}
  for _, w in ipairs(b.wants) do
    if w.id == r.id then
      local reopened = w.done
      w.done = nil
      syncRec(b)
      return reopened and true or false
    end
  end
  for _, w in ipairs(b.wants) do
    local wr = ns.REC[w.id]
    if not w.done and wr and wr.slot == r.slot then
      w.id = r.id
      syncRec(b)
      return true
    end
  end
  b.wants[#b.wants + 1] = { id = r.id }
  syncRec(b)
  return true
end

-- the enchant id was cast for b: that want (or the open one for its slot) is done. true while any is still open.
local function tickWant(b, id)
  local r = ns.REC[id]
  local hit
  for _, w in ipairs(b.wants or {}) do
    if not w.done and w.id == id then hit = w; break end
  end
  if not hit and r then
    for _, w in ipairs(b.wants or {}) do
      local wr = ns.REC[w.id]
      if not w.done and wr and wr.slot == r.slot then hit = w; break end
    end
  end
  if hit then hit.done = true end
  syncRec(b)
  return b.rec ~= nil
end

-- quiet for 2 hours - never while trading, or while you hold their mats or gold
local function quiet(b, t)
  if not isWaiting(b) or b.state == "trading" then return false end
  if (b.given and next(b.given)) or (b.paid or 0) > 0 then return false end
  return t - (b.at or t) > QUIET
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = copy(x) end
  return c
end

-- PLAYER_LOGOUT (a reload too): the waiting orders, per character
local function saveQueue()
  if not ns.DB or not ns.myName or ns.myName == "" then return end
  local t, wall = now(), time()
  local list = {}
  for _, b in ipairs(waitingList()) do
    local c = {}
    for k, v in pairs(b) do
      if not LIVE[k] then
        if TIMES[k] and type(v) == "number" then c[k] = wall - (t - v) else c[k] = copy(v) end
      end
    end
    if c.state == "trading" then c.state = c.given and "mats" or "asked" end
    list[#list + 1] = c
  end
  ns.DB.queues = ns.DB.queues or {}
  ns.DB.queues[ns.myName] = { saved = wall, list = list }
end

-- at start-up: the saved orders back into the list (once; the save is cleared)
local function loadQueue()
  local all = ns.DB and ns.DB.queues
  local q = all and ns.myName and all[ns.myName]
  if not q then return end
  all[ns.myName] = nil
  local t, wall = now(), time()
  for _, c in ipairs(q.list or {}) do
    if type(c) == "table" and c.key and c.n and not buyers[c.key] then
      for k in pairs(TIMES) do
        if type(c[k]) == "number" then c[k] = t - (wall - c[k]) end
      end
      if not c.wants and c.rec then c.wants = { { id = c.rec } } end
      if t - (c.at or t) <= QUIET then buyers[c.key] = c end
    end
  end
  if ns.onRoster then ns.onRoster() end
end

ns.enqueue = enqueue
ns.isWaiting = isWaiting
ns.place = place
ns.queueList = queueList
ns.quiet = quiet
ns.syncRec = syncRec
ns.openWants = openWants
ns.addWant = addWant
ns.tickWant = tickWant
ns.saveQueue = saveQueue
ns.loadQueue = loadQueue
