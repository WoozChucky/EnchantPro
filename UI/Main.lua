-- EnchantPro - the main window: Buyers / Enchants / Messages / Ledger tabs.
local ADDON, ns = ...
local EP = ns.EP
local SLOT = ns.SLOT
local PANEL_MAX_ROWS = ns.PANEL_MAX_ROWS
local buyers = ns.buyers
local rows = ns.rows
local toggles = ns.toggles
local safe = ns.safe
local say = ns.say
local now = ns.now
local money = ns.money
local restricted = ns.restricted
local whisper = ns.whisper
local replyText = ns.replyText
local askText = ns.askText
local adLeft = ns.adLeft
local ledgerSum = ns.ledgerSum
local net = ns.net
local dayStart = ns.dayStart
local tradeLine = ns.tradeLine
local openTrade = ns.openTrade
local cycle = ns.cycle
local Kit = ns.Kit
local button = Kit.button
local tooltip = Kit.tooltip

local ICON = "Interface\\Icons\\Trade_Engraving"
local TAB = { buyers = 1, enchants = 2, messages = 3, ledger = 4 }
local ROW_H, ROW_STEP, ROWS_TOP = 28, 30, 122

local STATE_TEXT = {
  asked = "|cffffd200asked|r", mats = "|cff7fd4ffmats in|r", trading = "|cffffffffin trade|r",
  done = "|cff808080done|r",
}
local STATE_ORDER = { trading = 1, mats = 2, asked = 3, done = 4 }

-- where a buyer is: in range, in your group, invited, waiting for a spot
local function groupText(b)
  if b.near then return " |cff40ff40in range|r" end
  if b.inGroup then return " |cff7fd4ffin group|r" end
  if b.queued then return " |cff808080waits for a spot|r" end
  if b.invitedAt and now() - b.invitedAt < 120 then return " |cff7fd4ffinvited|r" end
  return ""
end

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

local function spellIcon(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then return safe(C_Spell.GetSpellTexture, id) end
  return safe(GetSpellTexture, id)
end
ns.spellIcon = spellIcon

local function age(t)
  local s = math.max(0, now() - (t or now()))
  if s < 60 then return "now" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end

-- "Trade - City" -> "Trade"
local function sourceText(b)
  local w = b.where or b.src or ""
  return (string.match(w, "^(.-)%s+%-%s+") or w)
end

-- the Buyers tab -----------------------------------------------------------------------------

local function buildBuyers(page)
  local panel = ns.panel
  panel.info = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.info:SetPoint("TOPLEFT", 2, 0)
  panel.info:SetPoint("RIGHT", -2, 0)
  panel.info:SetJustifyH("LEFT")

  panel.ad = button(page, 146, 22, "Post ad")
  panel.ad:SetPoint("TOPLEFT", 0, -16)
  panel.ad:SetScript("OnClick", function() EP.postAd() end)
  panel.accept = button(page, 146, 22, "Accept trade")
  panel.accept:SetPoint("TOPRIGHT", 0, -16)
  panel.accept:SetScript("OnClick", function() EP.accept() end)

  local prev = button(page, 24, 36, "<")
  prev:SetPoint("TOPLEFT", 0, -44)
  prev:SetScript("OnClick", function() cycle(-1) end)
  local nextB = button(page, 24, 36, ">")
  nextB:SetPoint("TOPRIGHT", 0, -44)
  nextB:SetScript("OnClick", function() cycle(1) end)
  panel.castIcon = Kit.icon(page, 36)
  panel.castIcon:SetPoint("LEFT", prev, "RIGHT", 4, 0)

  -- the one secure button: casting needs the player's own click or key
  ns.castBtn = CreateFrame("Button", "EnchantProCastButton", page, "UIPanelButtonTemplate,SecureActionButtonTemplate")
  ns.castBtn:SetPoint("TOPLEFT", panel.castIcon, "TOPRIGHT", 4, 0)
  ns.castBtn:SetPoint("BOTTOMRIGHT", nextB, "BOTTOMLEFT", -4, 0)
  local down = safe(GetCVarBool, "ActionButtonUseKeyDown")
  ns.castBtn:RegisterForClicks(down and "AnyDown" or "AnyUp")

  panel.status = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 2, -86)
  panel.status:SetPoint("RIGHT", -2, 0)
  panel.status:SetJustifyH("LEFT")

  local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 2, -106)
  head:SetText("BUYERS  |cff808080click: trade / invite + reply - right-click: remove|r")

  for i = 1, PANEL_MAX_ROWS do
    local r = Kit.row(page, ROW_H)
    r:SetPoint("TOPLEFT", 0, -ROWS_TOP - (i - 1) * ROW_STEP)
    r:SetPoint("RIGHT", 0, 0)
    r:SetScript("OnClick", function(self, mouse)
      local b = self.buyer
      if not b then return end
      if mouse == "RightButton" then
        if b.inGroup then ns.kick(b) end   -- someone you invited leaves the group too (with Kick on)
        buyers[b.key] = nil
      elseif b.unit and b.near then
        openTrade(b, b.unit)
      else
        local invited = not b.inGroup and not ns.groupUnit(b.name) and not b.cant and ns.invite(b)
        local rec = b.rec and ns.REC[b.rec]
        whisper(b, (rec and replyText(b, rec) or askText(b)) .. (invited and " Group invite sent." or ""))
        if not b.unit and not invited and not b.inGroup then
          say(b.name .. " isn't near - target them or wait until they come, then click again.")
        end
      end
      ns.refresh()
    end)
    rows[i] = r
  end

  local defs = { { "listen", "Listen" }, { "reply", "Reply" }, { "invite", "Invite" }, { "autoTrade", "Trade" },
    { "autoKick", "Kick" }, { "thanks", "Thanks" } }
  local tips = {
    listen = "Look for buyers in Trade, General, LFG, say and yell.",
    reply = "Answer buyers with the price and mats (in the chat box - your Enter sends it).",
    invite = "Invite buyers to your group, so you see on the map where they are.",
    autoTrade = "Open trade with buyers who come in range.",
    autoKick = "Take buyers out of the group 15 s after their enchant (only those EnchantPro invited).",
    thanks = "A thank-you after every enchant, saying what was paid.",
  }
  for i, d in ipairs(defs) do
    local key = d[1]
    local t = Kit.toggle(page, 68, 22, d[2], function() return ns.DB[key] end, function(v)
      ns.DB[key] = v
      if key == "autoTrade" then EP.tradeBlocked = nil end
      ns.refresh()
    end)
    t.key = key
    tooltip(t, tips[key])
    toggles[i] = t
  end

  function page.onLayout(w, h)
    local half = math.floor((w - 4) / 2)
    panel.ad:SetWidth(half)
    panel.accept:SetWidth(half)
    local tw = math.floor((w - (#toggles - 1) * 4) / #toggles)
    for i, t in ipairs(toggles) do
      t:SetWidth(tw)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", (i - 1) * (tw + 4), 0)
    end
    panel.visibleRows = math.max(1, math.min(PANEL_MAX_ROWS, math.floor((h - ROWS_TOP - 26) / ROW_STEP)))
  end
end

-- the window ---------------------------------------------------------------------------------

local function buildPanel()
  local panel = Kit.window("EnchantProPanel", "EnchantPro", ICON, 600, 480, ns.frameSave("main"))
  ns.panel = panel
  panel.visibleRows = 6
  panel.close:SetScript("OnClick", function() EP.togglePanel(false) end)
  panel.tabs = Kit.tabs(panel, { "Buyers", "Enchants", "Messages", "Ledger" }, function() ns.refresh() end,
    { "EnchantProBuyers", "EnchantProEnchants", "EnchantProMessages", "EnchantProLedger" },
    function(i)
      EP.pending = { show = true, tab = i }
      say("The tab switches when combat ends.")
    end)
  local pages = panel.tabs.pages
  buildBuyers(pages[1])
  ns.buildEnchants(pages[2])
  ns.buildMessages(pages[3])
  ns.buildLedger(pages[4])
  panel.tabs:Select(1)

  Kit.makeResizable(panel, ns.frameSave("main"), 560, 420, 1000, 900, function(w, h)
    -- the content area: the window less its frame, title bar and edges
    local cw, ch = w - 28, h - 76
    for _, page in ipairs(pages) do if page.onLayout then page.onLayout(cw, ch) end end
    if ns.refresh then ns.refresh() end
  end, true)

  if not ns.DB.shown then panel:Hide() end
end

ns.refresh = function()
  if ns.updateExtras then ns.updateExtras() end
  local panel = ns.panel
  if not panel or not panel:IsShown() then return end
  local today = net(ledgerSum(dayStart()))
  panel.info:SetText(string.format("Enchants: %d   Today net: %s   Fee: %s", #ns.knownList,
    (today < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(today)) .. "|r", ns.DB.fee > 0 and money(ns.DB.fee) or "tips only"))
  local left = adLeft()
  panel.ad:SetText(left > 0 and string.format("Post ad (%d:%02d)", math.floor(left / 60), left % 60) or "Post ad")
  local tf = _G.TradeFrame
  if tf and tf:IsShown() then panel.accept:Enable() else panel.accept:Disable() end
  panel.castIcon:SetIcon(EP.castRec and spellIcon(EP.castRec.id) or ICON)

  local status = tradeLine()
  if not status then
    if #ns.knownList == 0 then status = "|cffffd200Open your Enchanting window once so I learn your enchants.|r"
    elseif restricted() then status = "|cff808080This realm blocks addon chat: replies go into the chat box, Enter sends.|r"
    else status = "" end
  end
  panel.status:SetText(status)

  local list = sortedBuyers()
  for i, row in ipairs(rows) do
    local b = i <= (panel.visibleRows or 6) and list[i] or nil
    row.buyer = b
    if b then
      local rec = b.rec and ns.REC[b.rec]
      local what = rec and rec.label or b.want or (b.slot and (SLOT[b.slot].label .. "?")) or "?"
      row.name:SetText("|cff" .. Kit.classHex(b.class) .. b.name .. "|r")
      row.sub:SetText(what .. "  |cff808080" .. sourceText(b) .. " - " .. age(b.at) .. "|r"
        .. (b.zone and ("  |cff7fd4ff" .. b.zone .. "|r") or ""))
      row.icon:SetIcon(rec and spellIcon(rec.id) or nil)
      row:SetNear(b.near and b.state ~= "done")
      row.right:SetText(b.cant and "|cff808080not yours|r"
        or ((STATE_TEXT[b.state] or b.state) .. (b.state == "done" and "" or groupText(b))))
      row:SetAlpha(b.cant and 0.6 or 1)
      row:Show()
    else
      row:Hide()
    end
  end
  for _, t in ipairs(toggles) do t:Refresh() end
end

-- showing and hiding: the window holds the secure Cast button, so it can't change in combat;
-- what was asked then happens when combat ends
function EP.togglePanel(show)
  local panel = ns.panel
  if not panel then return end
  local opening = show == nil and not panel:IsShown()
  if show == nil then show = not panel:IsShown() end
  if InCombatLockdown() then
    EP.pending = { show = show, tab = opening and 1 or nil }
    say("The window " .. (show and "opens" or "closes") .. " when combat ends.")
    return
  end
  if show and ns.DB.ui and ns.DB.ui.compact then EP.setCompact(false); return end   -- unfold the bar
  if opening then panel.tabs:Select(1) end
  if show then panel:Show() else panel:Hide() end
  ns.DB.shown = show
  ns.refresh()
end

-- the window on one tab; toggle = a second ask for the tab already showing closes the window
function EP.showTab(key, toggle)
  local panel = ns.panel
  local i = TAB[key]
  if not panel or not i then return end
  if InCombatLockdown() then
    EP.pending = { show = true, tab = i }
    say("The window opens when combat ends.")
    return
  end
  if toggle and panel:IsShown() and panel.tabs.current == i then EP.togglePanel(false); return end
  panel.tabs:Select(i)
  if not panel:IsShown() then EP.togglePanel(true) end
end

function EP.afterCombat()
  local p = EP.pending
  if not p then return end
  EP.pending = nil
  if p.tab then ns.panel.tabs:Select(p.tab) end
  EP.togglePanel(p.show)
end

function EP.toggleLedger() EP.showTab("ledger", true) end
function EP.toggleMessages() EP.showTab("messages", true) end
function EP.toggleEnchants() EP.showTab("enchants", true) end

ns.onOff = onOff
ns.buildPanel = buildPanel
