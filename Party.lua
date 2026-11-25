-- EnchantPro - units and the group: finding buyers around you, inviting them (so you see where they are on the
-- map) and letting them go after the enchant.
local ADDON, ns = ...
local buyers = ns.buyers
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now
local shortName = ns.shortName

-- ---------------------------------------------------------------------------------------
-- units: buyers are found by target, mouseover, focus, nameplates and the group

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
-- the group

local KICK_AFTER = 15   -- seconds after the enchant: time for the thank-you, or a second item

-- the group unit (party1.. / raid1..) of a name; nil when they're not in your group
local function groupUnit(name)
  if not name then return nil end
  local lname = string.lower(name)
  local prefix, n = "party", 4
  if IsInRaid and IsInRaid() then prefix, n = "raid", 40 end
  for i = 1, n do
    local un = fullName(prefix .. i)
    if un and string.lower(un) == lname then return prefix .. i end
  end
  return nil
end

-- the zone a group member is in ("Durotar"), nil when the game can't say
local function zoneOf(unit)
  if not (unit and C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
  local id = safe(C_Map.GetBestMapForUnit, unit)
  local info = id and safe(C_Map.GetMapInfo, id)
  return type(info) == "table" and type(info.name) == "string" and info.name or nil
end

local function isLeader()
  if not (IsInGroup and IsInGroup()) then return true end
  return safe(UnitIsGroupLeader, "player") == true
end

-- spots left in a party, less the invites still out (a minute)
local function freeSlots()
  if IsInRaid and IsInRaid() then return 0 end
  local pending, t = 0, now()
  for _, b in pairs(buyers) do
    if b.invitedAt and not b.inGroup and t - b.invitedAt < 60 then pending = pending + 1 end
  end
  return 5 - math.max(1, safe(GetNumGroupMembers) or 0) - pending
end

-- invite b. false when it has to wait (not the leader, no spot): b.queued, and the tick tries again.
local function invite(b)
  if not isLeader() or freeSlots() <= 0 then
    if not b.queued then
      say(b.name .. (isLeader() and " waits for a free spot in the group." or " waits - you're not the group leader."))
    end
    b.queued = true
    return false
  end
  local f = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  pcall(f, b.name)
  b.queued, b.invitedAt, b.weInvited = nil, now(), true
  return true
end

-- does b get an invite for asking (src: whisper, chat, say)? Not twice in 30 s; after a "no", only for a whisper.
local function wantsInvite(b, src)
  if not ns.DB.invite or b.cant or b.inGroup or b.queued or groupUnit(b.name) then return false end
  local t = now()
  if b.invitedAt and t - b.invitedAt < 30 then return false end
  if b.refusedAt and t - b.refusedAt < 300 and src ~= "whisper" then return false end
  return true
end

-- out of the group now - only someone EnchantPro invited, never a friend who was there already
local function kick(b)
  b.kickAt = nil
  if ns.DB.autoKick and b.weInvited and groupUnit(b.name) then
    local f = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit
    pcall(f, b.name)
  end
  b.weInvited = nil
end

-- the enchant is done: out of the group in a moment (a new trade with them calls it off)
local function letGo(b)
  if b.weInvited then b.kickAt = now() + KICK_AFTER end
end

-- the tick: invite whoever waits for a spot, let go whoever is due
local function groupTick(t)
  if ns.DB.invite and isLeader() then
    for _, b in pairs(buyers) do
      if b.queued and freeSlots() > 0 then invite(b) end
    end
  end
  for _, b in pairs(buyers) do
    if b.kickAt and t >= b.kickAt then kick(b) end
    b.zone = b.inGroup and zoneOf(groupUnit(b.name)) or nil
  end
end

-- GROUP_ROSTER_UPDATE: who joined, who left
local function onRoster()
  local t = now()
  for _, b in pairs(buyers) do
    if groupUnit(b.name) then
      if not b.inGroup then b.inGroup, b.joinedAt, b.queued = true, t, nil end
    else
      b.inGroup = nil
    end
  end
  if ns.refresh then ns.refresh() end
end

local function toPattern(s)
  if type(s) ~= "string" then return nil end
  s = string.gsub(s, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  s = string.gsub(s, "%%s", "(.+)")
  s = string.gsub(s, "%%d", "%%d+")
  return "^" .. s .. "$"
end

-- CHAT_MSG_SYSTEM: "X declines your group invitation." / "X is already in a group."
local function onSystem(text)
  if isSecret(text) or type(text) ~= "string" then return end
  for _, s in ipairs({ ERR_DECLINE_GROUP_S, ERR_ALREADY_IN_GROUP_S }) do
    local p = toPattern(s)
    local name = p and string.match(text, p)
    if name then
      local b = buyers[string.lower(shortName(name) or "")]
      if b then b.refusedAt, b.invitedAt, b.weInvited = now(), nil, nil end
      if ns.refresh then ns.refresh() end
      return
    end
  end
end

ns.fullName = fullName
ns.unitFor = unitFor
ns.near = near
ns.groupUnit = groupUnit
ns.invite = invite
ns.wantsInvite = wantsInvite
ns.kick = kick
ns.letGo = letGo
ns.groupTick = groupTick
ns.onRoster = onRoster
ns.onSystem = onSystem
