-- EnchantPro - the ledger, messages and enchants windows.
local ADDON, ns = ...
local EP = ns.EP
local say = ns.say
local money = ns.money
local parseMoney = ns.parseMoney
local matsText = ns.matsText
local AD_DEFAULT = ns.AD_DEFAULT
local AD_TOKENS = ns.AD_TOKENS
local REPLY_DEFAULT = ns.REPLY_DEFAULT
local REPLY_TOKENS = ns.REPLY_TOKENS
local ASK_DEFAULT = ns.ASK_DEFAULT
local ASK_TOKENS = ns.ASK_TOKENS
local THANKS_DEFAULT = ns.THANKS_DEFAULT
local THANKS_TOKENS = ns.THANKS_TOKENS
local adText = ns.adText
local replyText = ns.replyText
local askText = ns.askText
local thanksText = ns.thanksText
local sampleRec = ns.sampleRec
local newTotals = ns.newTotals
local ledgerSum = ns.ledgerSum
local net = ns.net
local dayStart = ns.dayStart
local Kit = ns.Kit
local button = Kit.button
local tooltip = Kit.tooltip

-- where a window keeps its place and size: DB.frames[key]
local function frameSave(key)
  ns.DB.frames = ns.DB.frames or {}
  ns.DB.frames[key] = ns.DB.frames[key] or {}
  return ns.DB.frames[key]
end
ns.frameSave = frameSave

-- the ledger window ----------------------------------------------------------------------

local ledgerFrame
local LEDGER_MAX_ROWS = 50
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

local function signed(c) return (c < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(c)) .. "|r" end

local function tileSub(T)
  return T.sales .. " enchants - " .. money(T.tips) .. " tips"
    .. (T.matsCost > 0 and (" - my mats " .. money(T.matsCost)) or "")
end

local function iconForLabel(label)
  for _, r in ipairs(ns.knownList) do if r.label == label then return ns.spellIcon and ns.spellIcon(r.id) end end
end

function EP.ledgerRefresh()
  local lf = ledgerFrame
  if not lf or not lf:IsShown() then return end
  local sums = { ledgerSum(dayStart()), ledgerSum(time() - 7 * 86400), ledgerSum(nil) }
  for i, T in ipairs(sums) do lf.tiles[i]:Set(signed(net(T)), tileSub(T)) end

  local days = ns.ledgerDays(7)
  local bars = {}
  for i, d in ipairs(days) do
    bars[i] = { d.income - d.tips, d.tips, i == #days and "Today" or date("%a", d.day) }
  end
  lf.bars:Set(bars)

  local best = ns.bestSellers(3)
  for i = 1, 3 do
    local s = best[i]
    lf.best[i]:SetText(s and (s.label .. "  |cffa0a0a0" .. s.count .. "x|r  |cffffffff" .. money(s.income) .. "|r") or "")
    lf.bestIcons[i]:SetIcon(s and iconForLabel(s.label) or nil)
    if s then lf.bestIcons[i]:Show() else lf.bestIcons[i]:Hide() end
  end
  local n, c = ns.owing()
  lf.owing:SetText(n > 0 and ("|cffff4040" .. n .. " owe you " .. money(c) .. "|r") or "|cff808080Nobody owes you.|r")

  local L = ns.DB.ledger
  local shown = lf.visible or 12
  lf.offset = math.max(0, math.min(lf.offset or 0, #L - shown))
  for i = 1, LEDGER_MAX_ROWS do
    local e = i <= shown and L[#L - lf.offset - i + 1] or nil
    lf.rows[i]:SetText(e and entryText(e) or "")
  end
  lf.empty:SetText(#L == 0 and "Nothing yet - mats handed over and enchants sold land here." or "")
end

local HISTORY_TOP = 236

local function buildLedger(lf)
  ledgerFrame = lf
  lf.tiles = {}
  for i, name in ipairs({ "Today", "7 days", "All time" }) do
    local t = Kit.tile(lf, name)
    lf.tiles[i] = t
  end
  lf.bars = Kit.bars(lf, 7)
  lf.bars:SetPoint("TOPLEFT", 4, -60)
  lf.bars:SetPoint("RIGHT", -4, 0)
  lf.bars:SetHeight(82)

  local bestHead = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bestHead:SetPoint("TOPLEFT", 4, -150)
  bestHead:SetText("BEST SELLERS")
  lf.owing = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lf.owing:SetPoint("TOPRIGHT", -4, -150)
  lf.best, lf.bestIcons = {}, {}
  for i = 1, 3 do
    local ic = Kit.icon(lf, 16)
    ic:SetPoint("TOPLEFT", 4, -166 - (i - 1) * 18)
    local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    fs:SetJustifyH("LEFT")
    lf.bestIcons[i], lf.best[i] = ic, fs
  end

  local head = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 4, -HISTORY_TOP + 16)
  head:SetText("HISTORY  |cff808080newest first - scroll for more|r")
  local reset = button(lf, 60, 18, "Reset")
  reset:SetPoint("TOPRIGHT", -4, -HISTORY_TOP + 19)
  reset:SetScript("OnClick", function() StaticPopup_Show("ENCHANTPRO_RESET_LEDGER") end)
  tooltip(reset, "Delete the whole ledger (asks first).")
  lf.rows = {}
  for i = 1, LEDGER_MAX_ROWS do
    local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, -HISTORY_TOP - (i - 1) * 16)
    fs:SetPoint("RIGHT", -4, 0)
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
  function lf.onLayout(w, h)
    local tw = math.floor((w - 8 - 2 * 6) / 3)
    for i, t in ipairs(lf.tiles) do
      t:SetWidth(tw)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", 4 + (i - 1) * (tw + 6), 0)
    end
    lf.visible = math.max(1, math.min(LEDGER_MAX_ROWS, math.floor((h - HISTORY_TOP) / 16)))
    EP.ledgerRefresh()
  end
end

function EP.resetLedger()
  ns.DB.ledger, ns.DB.totals = {}, newTotals()
  say("Ledger cleared.")
  EP.ledgerRefresh()
  if ns.refresh then ns.refresh() end
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


-- the messages window ---------------------------------------------------------------------

local msgFrame

local function setChecked(cb, v) if cb.SetChecked then cb:SetChecked(v and true or false) end end

-- each part hangs from the one above, so a preview or tokens line that wraps pushes the rest down.
-- above: the editor before this one (nil for the first)
local function addEditor(parent, above, def)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if above then label:SetPoint("TOPLEFT", above.tk, "BOTTOMLEFT", -2, -12)
  else label:SetPoint("TOPLEFT", 4, -4) end
  label:SetText(def.label)
  local reset = button(parent, 70, 20, "Default")
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetHeight(20)
  eb:SetPoint("TOPLEFT", label, "TOPLEFT", 8, -18)
  reset:SetPoint("BOTTOMRIGHT", eb, "TOPRIGHT", 4, 1)
  eb:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(255)
  local pv = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pv:SetPoint("TOPLEFT", label, "TOPLEFT", 2, -42)
  pv:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
  pv:SetJustifyH("LEFT")
  local tk = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tk:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 0, -3)
  tk:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
  tk:SetJustifyH("LEFT")
  tk:SetText(def.tokens)

  local ed = { eb = eb, pv = pv, tk = tk, label = label }
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

local function stored(key) return function() return (ns.DB[key] and ns.DB[key] ~= "") and ns.DB[key] or nil end end
local function store(key) return function(v) ns.DB[key] = v end end

local function buildMessages(mf)
  msgFrame = mf
  local hint = mf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -4, 0)
  hint:SetText("Enter saves - Escape undoes")
  local B = { name = "Bob", full = "Bob" }
  local eds = {}
  mf.eds = eds
  eds[1] = addEditor(mf, nil, { label = "Trade ad", default = AD_DEFAULT, tokens = AD_TOKENS, get = stored("ad"), set = store("ad"),
      preview = function(t) return adText(t ~= "" and t or AD_DEFAULT) end })
  eds[2] = addEditor(mf, eds[1], { label = "Reply (they named an enchant)", default = REPLY_DEFAULT, tokens = REPLY_TOKENS,
      get = stored("replyText"), set = store("replyText"),
      preview = function(t) return replyText(B, sampleRec(), t ~= "" and t or REPLY_DEFAULT) end })
  eds[3] = addEditor(mf, eds[2], { label = "Reply (no enchant named yet)", default = ASK_DEFAULT, tokens = ASK_TOKENS,
      get = stored("askText"), set = store("askText"),
      preview = function(t) return askText(B, t ~= "" and t or ASK_DEFAULT) end })
  eds[4] = addEditor(mf, eds[3], { label = "Thank-you", default = THANKS_DEFAULT,
      tokens = THANKS_TOKENS .. "\n|cff808080A trade that falls short always says how much is missing instead.|r",
      get = stored("thanksText"), set = store("thanksText"),
      preview = function(t) return thanksText(B, sampleRec().label, 3000, 1000, 2000, 2000, t ~= "" and t or THANKS_DEFAULT) end })
  local function check(x, text, key)   -- on the thank-you label's line
    local cb = CreateFrame("CheckButton", nil, mf, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", eds[4].label, "TOPLEFT", x, 4)
    local fs = mf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self) ns.DB[key] = self:GetChecked() and true or false end)
    cb.key = key
    return cb
  end
  mf.checks = { check(96, "after every enchant", "thanks"), check(236, "in /say, not a whisper", "thanksSay") }
  function mf.onLayout() for _, ed in ipairs(mf.eds) do ed.update() end end
  mf:SetScript("OnShow", function(self)
    for _, ed in ipairs(self.eds) do ed.load() end
    for _, cb in ipairs(self.checks) do setChecked(cb, ns.DB[cb.key]) end
  end)
end


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
  ef.fee:SetText(money(ns.DB.fee))
  local shown = ef.visible or 10
  ef.offset = math.max(0, math.min(ef.offset or 0, #ns.knownList - shown))
  for i = 1, ENCH_MAX_ROWS do
    local row = ef.rows[i]
    local r = i <= shown and ns.knownList[ef.offset + i] or nil
    row.rec = r
    if r then
      setChecked(row.ad, ns.DB.adList[r.id])
      row.label:SetText(r.label)
      row.fee:SetText(ns.DB.fees[r.id] and money(ns.DB.fees[r.id]) or "")
      row.full:SetText(ns.DB.fulls[r.id] and money(ns.DB.fulls[r.id]) or "")
      row.mats:SetText(matsText(r, true))
      row:Show()
    else
      row:Hide()
    end
  end
  ef.empty:SetText(#ns.knownList == 0
    and "No enchants yet. Open your Enchanting window (the profession) once - EnchantPro reads your enchants from it." or "")
end

local function buildEnchants(ef)
  enchFrame = ef
  ef.offset = 0

  local feeLabel = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  feeLabel:SetPoint("TOPLEFT", 4, -6)
  feeLabel:SetText("Fee with their mats:")
  ef.fee = moneyBox(ef, 70)
  ef.fee:SetPoint("LEFT", feeLabel, "RIGHT", 10, 0)
  ef.fee:SetScript("OnEditFocusLost", function(self)
    local c = parseMoney(self:GetText())
    if c and c ~= ns.DB.fee then ns.DB.fee = c; say("Fee: " .. money(c) .. ".") end
    EP.enchantsRefresh()
    if ns.refresh then ns.refresh() end
  end)
  local feeHint = ef:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  feeHint:SetPoint("LEFT", ef.fee, "RIGHT", 10, 0)
  feeHint:SetPoint("RIGHT", ef, "RIGHT", -4, 0)   -- wraps inside the window
  feeHint:SetJustifyH("LEFT")
  ef.feeHint = feeHint
  feeHint:SetText("0: no fee, tips only. Counts for every enchant without its own fee. Blank full price: not offered.")

  local heads = { { "Ad", 16 }, { "Enchant", 42 }, { "Fee", 212 }, { "Full", 290 }, { "Mats (in your bags)", 366 } }
  for _, h in ipairs(heads) do
    local fs = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", h[2] - 10, -32)
    fs:SetText(h[1])
  end

  ef.rows = {}
  for i = 1, ENCH_MAX_ROWS do
    local row = CreateFrame("Frame", nil, ef)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 0, -46 - (i - 1) * 22)
    row:SetPoint("RIGHT", -4, 0)
    row.ad = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.ad:SetSize(20, 20)
    row.ad:SetPoint("LEFT", 2, 0)
    row.ad:SetScript("OnClick", function(self)
      local r = row.rec
      if r then ns.DB.adList[r.id] = self:GetChecked() and true or nil end
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
    row.mats:SetWordWrap(false)   -- one line, cut short; the row's tooltip has the whole list
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
      elseif c == ns.DB.fee then ns.DB.fees[id] = nil
      else ns.DB.fees[id] = c end
      EP.enchantsRefresh()
    end)
    row.full:SetScript("OnEditFocusLost", function(self)
      local id = self.recId
      if not id then return end
      local txt = strtrim(self:GetText() or "")
      local c = txt ~= "" and parseMoney(txt) or nil
      if txt ~= "" and not c then say("Write prices like 25s or 1g50s.")
      elseif c and c > 0 then ns.DB.fulls[id] = c
      else ns.DB.fulls[id] = nil end
      EP.enchantsRefresh()
    end)
    row:EnableMouse(true)
    tooltip(row, function(self) return self.rec and (self.rec.name .. "\n" .. matsText(self.rec)) or "" end)
    ef.rows[i] = row
  end
  ef.empty = ef:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ef.empty:SetPoint("TOPLEFT", 4, -50)
  ef.empty:SetPoint("RIGHT", -4, 0)
  ef.empty:SetJustifyH("LEFT")

  ef:EnableMouseWheel(true)
  ef:SetScript("OnMouseWheel", function(self, delta)
    for _, row in ipairs(self.rows) do row.fee:ClearFocus(); row.full:ClearFocus() end
    self.offset = (self.offset or 0) - delta * 3
    EP.enchantsRefresh()
  end)
  ef:SetScript("OnShow", function() EP.enchantsRefresh() end)
  function ef.onLayout(_, h)
    ef.visible = math.max(1, math.min(ENCH_MAX_ROWS, math.floor((h - 46 - 4) / 22)))
    EP.enchantsRefresh()
  end
end


ns.buildLedger = buildLedger
ns.buildMessages = buildMessages
ns.buildEnchants = buildEnchants
