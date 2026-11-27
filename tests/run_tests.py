"""Offline tests for EnchantPro: a fake WoW API (harness.lua) driven through Lua 5.1 by lupa.
python tests/run_tests.py [addon folder]"""
import sys, pathlib
import lupa.lua51 as LUPA

here = pathlib.Path(__file__).parent
addon = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent
harness = (here / "harness.lua").read_text(encoding="utf-8")

def toc_files():
    """The .lua files the game loads, in the .toc's order."""
    out = []
    for line in (addon / "EnchantPro.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and line.lower().endswith(".lua"):
            out.append(line.replace("\\", "/"))
    return out
FILES = toc_files()

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + (("  -- " + str(extra)) if extra and not ok else ""))
    if not ok: fails += 1

def runtime(pre=""):
    """A fresh game: the fake API, then every file of the .toc sharing one private table, as the game does."""
    lua = LUPA.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(pre + "\n" + harness)
    lua.execute("T.baseGlobals = {}; for k in pairs(_G) do T.baseGlobals[k] = true end")
    load =lua.eval("function(src, path, ns) local f, e = loadstring(src, path); if not f then error(e) end; f('EnchantPro', ns) end")
    ns = lua.table()
    for f in FILES:
        load((addon / f).read_text(encoding="utf-8"), f, ns)
    lua.globals().T.ns = ns      # the private table, for tests only (T is the harness's)
    return lua

on_disk = sorted(p.relative_to(addon).as_posix() for p in addon.rglob("*.lua")
                 if "tests" not in p.relative_to(addon).parts and not p.relative_to(addon).parts[0].startswith("."))
check("toc lists every .lua file", sorted(FILES) == on_disk and all((addon / f).exists() for f in FILES), (FILES, on_disk))

lua = runtime()
G = lua.globals()
T, EP = G.T, G.EnchantPro
fire = T.fire
def prints(): return list(T.prints.values())
def called(name): return [list(c.values()) for c in T.called(name).values()]
def advance(sec): T.time = T.time + sec
def slash(msg): G.SlashCmdList.ENCHANTPRO(msg)
def tbl(d):
    t = lua.table()
    for k, v in d.items(): t[k] = v
    return t
def set_trade(money=0, items=None, target=None):
    t = lua.table(); t.money = money
    it = lua.table()
    for slot, (iid, n) in (items or {}).items():
        it[slot] = lua.table(iid, n)
    t["items"] = it
    if target:
        t.target = tbl(target)
    T.trade = t
    G.TradeFrame.shown = True

T.equip = tbl({"item:bracer": "INVTYPE_WRIST", "item:sword": "INVTYPE_WEAPON", "item:boots": "INVTYPE_FEET", "item:staff": "INVTYPE_2HWEAPON"})
fire("ADDON_LOADED", "EnchantPro")
fire("PLAYER_LOGIN")
check("login on an enchanter starts", EP.started == True)
check("asks to open Enchanting once", any("Open your Enchanting window once" in p for p in prints()), prints())
check("cast button says open Enchanting", "Open your Enchanting" in (G.EnchantProCastButton.text or ""), G.EnchantProCastButton.text)
check("default fee: none, tips only", G.EnchantProDB.fee == 0, G.EnchantProDB.fee)
slash("fee 20s")   # the sales below charge a fee; tips only is tested further down

# --- the profession window teaches the enchants
fire("TRADE_SKILL_SHOW")
T.runTimers()
known = EP._test.knownList()
labels = [known[i].label for i in range(1, len(known) + 1)]
check("9 enchants learned (rod and unlearned skipped)", len(labels) == 9, labels)
for want in ["+7 Sta Bracer", "+3 Sta Bracer", "+1 Sta Bracer", "Crusader Weapon", "+1 Agi Cloak", "+5 Agi Boots",
             "Minor Speed Boots", "+4 Stats Chest", "+9 Impact 2H"]:
    check(f"label {want}", want in labels, labels)
check("best bracer first", [l for l in labels if l.endswith("Bracer")][0] == "+7 Sta Bracer", labels)
check("saved per character", G.EnchantProDB.chars["Mage"].recipes[13945].name == "Enchant Bracer - Greater Stamina")
check("mats read from the schematic", G.EnchantProDB.chars["Mage"].recipes[20034].reagents[1].q == 4)

# --- what chat lines mean
ci, wi, clean = EP._test.channelIntent, EP._test.whisperIntent, EP._test.clean
def chat(line):
    r = ci(clean(line))
    if not isinstance(r, tuple): return (r, None)
    return (r[0], r[1].label if r[0] and r[1] else None)
for line, want, label in [
    ("LF enchanter", True, None),
    ("WTB crusader", True, "Crusader Weapon"),
    ("LF enchanter for +7 stam bracer", True, "+7 Sta Bracer"),
    ("anyone can do +5 agi boots?", True, "+5 Agi Boots"),
    ("need minor speed on boots", True, "Minor Speed Boots"),
    ("LFW enchanter, your mats, tips", False, None),
    ("WTS crusader enchant, pst", False, None),
    ("Enchanter LF work: crusader, +7 stam, tips appreciated", False, None),
    ("LF enchanter to DE some greens", False, None),
    ("LF tank for SM", False, None),
    ("lf someone to enchant my 2h with impact", True, "+9 Impact 2H"),
    ("LF enchanter stamina bracer?", True, "+7 Sta Bracer"),
    ("LF enchanter +3 stam bracer", True, "+3 Sta Bracer"),
    ("lf ench chest stats", True, "+4 Stats Chest"),
    ("any enchanter around? need cloak agi", True, "+1 Agi Cloak"),
    ("LF enchanter for crusader on my 2 hander", True, "Crusader Weapon"),
    ("need fiery weapon enchant", True, None),
    ("ding! enchanting 225", False, None),
    ("+2 healing on gloves anyone", True, None),
]:
    ok, lab = chat(line)
    check(f"chat '{line}' -> {want}, {label}", bool(ok) == want and (not want or lab == label), (ok, lab))

def wh(line):
    r = wi(clean(line))
    if not isinstance(r, tuple): return (r, None)
    return (r[0], r[1].label if r[1] else None)
for line, want, label in [
    ("crusader?", True, "Crusader Weapon"),
    ("how much", "price", None),
    ("what mats for crusader", "mats", "Crusader Weapon"),
    ("hey", False, None),
    ("how much for crusader", True, "Crusader Weapon"),
    ("can you do stam bracer", True, "+7 Sta Bracer"),
]:
    got = wh(line)
    check(f"whisper '{line}' -> {want}, {label}", got[0] == want and got[1] == label, got)

# --- linked enchants (raw lines, as the game sends them)
def link(kind, data, text): return "|cffffd000|H" + kind + ":" + data + "|h[" + text + "]|h|r"
CRUS = link("enchant", "20034", "Enchant Weapon - Crusader")
STAM = link("enchant", "13945", "Enchant Bracer - Greater Stamina")
AGI = link("spell", "13935:0", "Enchanting: Enchant Boots - Agility")
STATS = link("enchant", "20025", "Enchant Chest - Greater Stats")
FIERY = link("enchant", "13898", "Enchant Weapon - Fiery Weapon")
PROF = link("trade", "Player-1:333:225:300", "Enchanting")
FORMULA = link("item", "16252", "Formula: Enchant Weapon - Crusader")
def chatL(line):
    raw = EP._test.dropRecipeItems(line)
    r = ci(clean(raw), EP._test.readLinks(raw))
    if not isinstance(r, tuple): return (r, None, None)
    if not r[0]: return (r[0], r[1], None)
    return (True, r[1].label if r[1] else None, r[3] if len(r) > 3 else None)
for line, want, label, extra in [
    ("LF " + STAM, True, "+7 Sta Bracer", None),
    (CRUS + " anyone?", True, "Crusader Weapon", None),
    ("LF enchanter " + AGI, True, "+5 Agi Boots", None),
    ("LF " + CRUS + " and " + AGI, True, "Crusader Weapon", None),
    ("LF " + FIERY, True, None, "Fiery Weapon"),
    ("WTS " + CRUS + " " + STAM + " your mats", "seller", None, None),
    ("LF customers! " + CRUS + " " + AGI, "seller", None, None),
    (CRUS + " " + STAM + " " + STATS + " pst", "seller", None, None),
    ("LF " + CRUS + " " + STAM + " " + STATS, "seller", None, None),
    ("WTB " + CRUS + " " + STAM + " " + STATS, True, "Crusader Weapon", None),
    (PROF + " LF work, tips", "seller", None, None),
    ("anyone? " + PROF, "seller", None, None),
    ("WTB " + FORMULA, False, None, None),
    ("LF enchanter for " + CRUS + ", tips appreciated", "seller", None, None),
]:
    got = chatL(line)
    ok = (got[0] == want if want != "seller" else (got[0] is False and got[1] == "seller")) and \
         (want is not True or (got[1] == label and got[2] == extra))
    check(f"linked chat '{clean(line)}' -> {want}, {label or extra}", ok, got)

wl = wi(clean(AGI), EP._test.readLinks(AGI))
check("whisper with a link -> that enchant", wl[0] is True and wl[1].label == "+5 Agi Boots", wl)
wl = wi(clean(FIERY), EP._test.readLinks(FIERY))
check("whisper with an unknown link -> not yours", wl[0] is True and wl[1] is None and wl[3] == "Fiery Weapon", wl)

# a seller's line puts them on the seller list: their later "LF" lines are skipped for an hour
fire("CHAT_MSG_CHANNEL", "WTS " + CRUS + " " + STAM + " your mats", "Ench Guy", "", "2. Trade", "", "", 2, 2, "Trade")
check("seller not listed", EP._test.buyers["ench guy"] is None)
fire("CHAT_MSG_CHANNEL", "LF enchanter for crusader", "Ench Guy", "", "2. Trade", "", "", 2, 2, "Trade")
check("seller's later LF line skipped", EP._test.buyers["ench guy"] is None)
fire("CHAT_MSG_WHISPER", "crusader?", "Ench Guy")
check("seller's whisper still counts", EP._test.buyers["ench guy"] is not None)
EP._test.buyers["ench guy"] = None
fire("CHAT_MSG_CHANNEL", "LF " + FIERY + " pls", "Al Fire", "", "2. Trade", "", "", 2, 2, "Trade")
af = EP._test.buyers["al fire"]
check("unknown linked enchant: listed as not yours", af is not None and af.cant and af.want == "Fiery Weapon", af and (af.cant, af.want))
EP._test.buyers["al fire"] = None
T.runTimers()
T.tells = lua.table()

# --- a whisper gets a reply in the whisper box
fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Nx Thearabian")
T.runTimers()
b = EP._test.buyers["nx thearabian"]
check("buyer listed with the enchant", b is not None and b.rec == 13945, b and b.rec)
tells = list(T.tells.values())
check("reply goes to the tell box for the full name", len(tells) == 1 and tells[0].name == "Nx Thearabian", [dict(t) for t in tells])
check("reply names enchant, fee and mats", tells and "+7 Sta Bracer: 20s with your mats (5 Dream Dust - trade them first)" in (tells[0].text or ""), tells and tells[0].text)
check("cast button holds the buyer's enchant", G.EnchantProCastButton.attrs["macrotext"] == "/cast Enchant Bracer - Greater Stamina", G.EnchantProCastButton.attrs["macrotext"])
check("cast button flags missing mats", "(no mats)" in G.EnchantProCastButton.text, G.EnchantProCastButton.text)

# --- the buyer comes near: a click opens the trade (never by itself)
T.units["target"] = "Nx Thearabian"; T.near["target"] = True
T.tick()
check("no trade opens by itself", called("InitiateTrade") == [], called("InitiateTrade"))
rg = lua.eval("rawget")
def row_of(ns_, key, rawget_):
    for i in range(1, 21):
        r = ns_.rows[i]
        b = rawget_(r, "buyer")
        if b is not None and b.key == key: return r
    return None
T.ns.refresh()
nrow = row_of(T.ns, "nx thearabian", rg)
nrow.scripts.OnClick(nrow, "LeftButton")
check("trade opened with the buyer in range", called("InitiateTrade") == [["InitiateTrade", "target"]], called("InitiateTrade"))

# --- trade 1: the mats
T.npc = "Nx Thearabian"
set_trade(items={1: (11176, 5)})
fire("TRADE_SHOW")
check("trade line: hands over mats", "hands over 5 Dream Dust" in (EP._test.tradeLine() or ""), EP._test.tradeLine())
fire("TRADE_ACCEPT_UPDATE", 1, 1)
fire("UI_INFO_MESSAGE", 0, "Trade complete.")
fire("TRADE_CLOSED")
b = EP._test.buyers["nx thearabian"]
check("mats remembered on the buyer", b.given[11176] == 5 and b.state == "mats", (b.given and b.given[11176], b.state))
L = G.EnchantProDB.ledger
check("ledger: pay entry for mats", L[1].k == "pay" and L[1].it == "5 Dream Dust", L[1] and L[1].k)
T.bags[11176] = 5

# --- trade 2: the item, enchant, gold
set_trade(money=2000, target={"link": "item:bracer", "name": "Bracers"})
fire("TRADE_SHOW")
mt = G.EnchantProCastButton.attrs["macrotext"]
check("cast button casts onto the trade slot", mt == "/cast Enchant Bracer - Greater Stamina\n/click TradeRecipientItem7ItemButton", mt)
line = EP._test.tradeLine()
check("trade line: their mats, paid", "their mats" in line and "PAID" in line, line)
EP.accept()
check("accept before the enchant asks again", called("AcceptTrade") == [] and any("Not enchanted yet" in p for p in prints()))
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13945)
advance(5)
EP.accept()
check("accept after the enchant", len(called("AcceptTrade")) == 1)
fire("TRADE_ACCEPT_UPDATE", 1, 1)
fire("UI_INFO_MESSAGE", 0, "Trade complete.")
fire("TRADE_CLOSED")
T.runTimers()
e = L[2]
check("ledger: sale with their mats", e.k == "sale" and e.mode == "mats" and e.p == 2000 and e.g == 2000 and e.tip == 0, (e.k, e.mode, e.p, e.g, e.tip))
check("buyer done, mats used up", b.state == "done" and (b.given is None or b.given[11176] is None), b.state)
tells = list(T.tells.values())
check("thank-you whispered", tells[-1].text == "Thank you Nx Thearabian! +7 Sta Bracer done - received 20s.", tells[-1].text)
tot = G.EnchantProDB.totals
check("totals: 20s in, one enchant with their mats", tot.income == 2000 and tot.sales == 1 and tot.theirMats == 1, (tot.income, tot.sales))

# --- full price with my mats, tip and mats cost
slash("price crusader 20s 1g")
check("/ep price sets full price", G.EnchantProDB.fulls[20034] == 10000, G.EnchantProDB.fulls[20034])
slash("matcost Large Brilliant Shard 30s")
slash("matcost 12811 10s")
check("/ep matcost by name and id", G.EnchantProDB.matCost[14344] == 3000 and G.EnchantProDB.matCost[12811] == 1000)
T.bags[14344] = 4; T.bags[12811] = 2
T.units["target"] = None
fire("CHAT_MSG_WHISPER", "crusader?", "Bob")
T.runTimers()
tells = list(T.tells.values())
check("reply offers full price", "or 1g with mine" in tells[-1].text, tells[-1].text)
T.npc = "Bob"
set_trade(money=12000, target={"link": "item:sword", "name": "Sword"})
fire("TRADE_SHOW")
line = EP._test.tradeLine()
check("trade line: my mats, paid", "your mats" in line and "PAID" in line and "Crusader" in line, line)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20034)
fire("TRADE_ACCEPT_UPDATE", 1, 1)
fire("UI_INFO_MESSAGE", 0, "Trade complete.")
fire("TRADE_CLOSED")
e = L[3]
check("ledger: full sale - 1g price, 20s tip, 1g40s my mats", e.mode == "full" and e.p == 10000 and e.tip == 2000 and e.m == 14000, (e.mode, e.p, e.tip, e.m))
check("net counts my mats", G.EnchantProDB.totals.matsCost == 14000)

# --- part mats: price = fee + the mats I add, capped at full
fire("CHAT_MSG_WHISPER", "crusader pls", "Kim")
T.npc = "Kim"
set_trade(money=0, items={1: (14344, 2)}, target={"link": "item:sword", "name": "Sword"})
fire("TRADE_SHOW")
owed = EP._test.quote(EP._test.REC()[20034], EP._test.buyers["kim"], EP.trade)
check("part mats: 20s + 2x30s + 2x10s = 1g", owed[0] == 10000 and owed[1] == "part", owed[:2])
EP.accept()
check("underpaid accept asks again", any("Not enchanted yet" in p for p in prints()))
fire("TRADE_CLOSED")

# --- no full price, no mat costs: says so
fire("CHAT_MSG_WHISPER", "minor speed boots", "Lee")
T.npc = "Lee"
set_trade(money=500, target={"link": "item:boots", "name": "Boots"})
fire("TRADE_SHOW")
check("no price for my mats: says so", "mats missing" in EP._test.tradeLine(), EP._test.tradeLine())
fire("TRADE_CLOSED")

# --- the item picks the enchant; < > cycles within its slot
fire("CHAT_MSG_WHISPER", "LF enchanter", "Max")
T.npc = "Max"
set_trade(money=0, target={"link": "item:bracer", "name": "Bracers"})
fire("TRADE_SHOW")
check("bracer in trade -> a bracer enchant", EP.castRec.slot == "bracer", EP.castRec.label)
first = EP.castRec.label
EP._test.cycle(1)
check("> cycles to another bracer enchant", EP.castRec.slot == "bracer" and EP.castRec.label != first, EP.castRec.label)
fire("TRADE_CLOSED")
set_trade(money=0, target={"link": "item:staff", "name": "Staff"})
fire("TRADE_SHOW")
slots = set()
for _ in range(4):
    EP._test.cycle(1); slots.add(EP.castRec.slot)
check("2H item: weapon and 2H enchants", slots == {"weapon", "2h"}, slots)
fire("TRADE_CLOSED")

# --- the trade dock: steps, mats, payment, its own Cast button
NS = T.ns
fire("CHAT_MSG_WHISPER", "crusader please", "Dee Dock")
T.runTimers()
T.npc = "Dee Dock"
bags = T.bags
T.bags = tbl({})
set_trade(money=0)
fire("TRADE_SHOW")
st = NS.dockState()
dock = G.EnchantProDock
check("dock: empty trade", st.done == 1 and st.current == 2 and st.flags[1] and not st.flags[2], (st.done, st.current))
check("dock shows with the trade", dock is not None and dock.shown)
check("dock lists the mats", st.mats[1].need == 4 and st.mats[1].have == 0, st.mats[1] and (st.mats[1].have, st.mats[1].need))
T.bags = bags
mid = T.ns.dockState().mats[1].id
T.bags[mid] = 7
fire("BAG_UPDATE_DELAYED")
check("dock mats follow the bags", "7/" in (dock.mats[1].count.text or ""), dock.mats[1].count.text)
T.bags[mid] = None
set_trade(money=0, target={"link": "item:sword", "name": "Sword"})
fire("TRADE_TARGET_ITEM_CHANGED")
st = NS.dockState()
check("dock: mats in bags + item fits -> current Cast", st.current == 4 and st.flags[2] and st.flags[3], (st.done, st.current))
check("dock cast pulses when it's time to cast", G.EnchantProDockCast.pulsing == True)
check("dock cast matches panel cast", G.EnchantProDockCast.attrs["macrotext"] is not None
      and G.EnchantProDockCast.attrs["macrotext"] == G.EnchantProCastButton.attrs["macrotext"], G.EnchantProDockCast.attrs["macrotext"])
set_trade(money=100000, target={"link": "item:sword", "name": "Sword", "ench": "Crusader"})
fire("TRADE_MONEY_CHANGED")
st = NS.dockState()
check("dock: enchanted and paid -> done 5", st.done == 5 and st.current is None, (st.done, st.current))
fire("TRADE_CLOSED")
check("dock hides when the trade closes", not dock.shown)
T.npc = "Some Stranger"
set_trade(money=0, target={"link": "item:bracer", "name": "Bracers"})
fire("TRADE_SHOW")
st = NS.dockState()
check("dock: stranger", st.buyer is not None and not st.flags[1] and dock.shown, st.flags[1])
T.combat = True
before = G.EnchantProDockCast.attrs["macrotext"]
fire("TRADE_CLOSED")
check("dock in combat waits", dock.shown and G.EnchantProDockCast.attrs["macrotext"] == before)
T.combat = False
fire("PLAYER_REGEN_ENABLED")
check("dock hides after combat", not dock.shown)
EP._test.buyers["dee dock"] = None; EP._test.buyers["some stranger"] = None
T.runTimers(); T.tells = lua.table()

# --- the ad
G.EnchantProDB.adList[13945] = True; G.EnchantProDB.adList[20034] = True
advance(100)
EP.postAd()
T.runTimers()
oc = called("OpenChat")
check("ad in the chat box", oc and oc[-1][1] == "/2 WTS Enchants: +7 Sta Bracer / Crusader Weapon. Your mats, 20s fee - or full price with my mats. Whisper me!", oc and oc[-1])

# --- one window with tabs: Buyers / Enchants / Messages / Ledger
panel = G.EnchantProPanel
pages = {"buyers": G.EnchantProBuyers, "enchants": G.EnchantProEnchants, "messages": G.EnchantProMessages, "ledger": G.EnchantProLedger}
def shown_pages(): return sorted(k for k, f in pages.items() if f is not None and f.shown)
slash("ledger")
check("/ep ledger shows ledger tab", panel.shown and panel.tabs.current == 4 and shown_pages() == ["ledger"], (panel.shown, shown_pages()))
slash("enchants")
check("tabs: one page at a time", shown_pages() == ["enchants"], shown_pages())

ef = G.EnchantProEnchants
check("enchants tab lists all 9 in order", [ef.rows[i].rec.label for i in range(1, 10)] == labels, [ef.rows[i].rec.label for i in range(1, 10)])
def rows_shown(f): return sum(1 for i in range(1, 41) if f.rows[i].shown)
panel.SetSize(panel, 600, 300); small = rows_shown(ef)
panel.SetSize(panel, 600, 640); big = rows_shown(ef)
check("enchants rows follow the window height", small < 9 and big == 9, (small, big))
row = ef.rows[2]
row.fee.scripts.OnEditFocusGained(row.fee)
row.fee.SetText(row.fee, "35s")
row.fee.scripts.OnEditFocusLost(row.fee)
check("fee edit saves for that enchant", G.EnchantProDB.fees[row.rec.id] == 3500, G.EnchantProDB.fees[row.rec.id])
slash("messages")
mf = G.EnchantProMessages
check("messages tab: 4 editors", shown_pages() == ["messages"] and len(list(mf.eds.values())) == 4)

_anch = lua.eval("function(o, r) local ps = o and rawget(o, 'points') or {} for _, p in ipairs(ps) do if rawequal(p[2], r) then return true end end return false end")
def anchored_to(obj, rel): return bool(_anch(obj, rel))
check("messages tab: each tokens line sits under its preview, so a wrapped preview pushes it down",
      all(anchored_to(mf.eds[i].tk, mf.eds[i].pv) for i in range(1, 5)))
check("messages tab: each editor starts under the one before",
      all(anchored_to(mf.eds[i].label, mf.eds[i - 1].tk) for i in range(2, 5)))
fh = G.rawget(ef, "feeHint")
check("enchants tab: the fee hint ends inside the window", fh is not None and anchored_to(fh, ef) and fh.point[1] == "RIGHT", fh and fh.point)
check("enchants tab: a long mats list stays on its own row (one line)", all(ef.rows[i].mats.wordWrap is False for i in range(1, 41)))
slash("ledger")
lf = G.EnchantProLedger
check("ledger shows entries", any("Nx Thearabian" in (lf.rows[i].text or "") for i in (1, 2, 3, 4)), [lf.rows[i].text for i in (1, 2, 3)])
slash("ledger")
check("/ep ledger again hides the window", not panel.shown)
slash("")
check("/ep shows it again on the Buyers tab", panel.shown and shown_pages() == ["buyers"], shown_pages())
panel.SetSize(panel, 600, 400); low = panel.visibleRows
panel.SetSize(panel, 600, 640); high = panel.visibleRows
check("buyer rows follow the height", 1 <= low < high, (low, high))

# --- buyer rows: class colour, icon, in-range dot
def row_for(key):
    for i in range(1, 21):
        r = T.ns.rows[i]
        if r and r.shown and r.buyer and r.buyer.key == key: return r
T.guids["Player-1-0AB"] = "MAGE"
fire("CHAT_MSG_WHISPER", "need crusader pls", "Holy Bread", "", "", "", "", 0, 0, "", 0, 7, "Player-1-0AB")
hb = row_for("holy bread")
check("buyer row class colour", hb is not None and "3fc7eb" in (hb.name.text or ""), hb and hb.name.text)
check("buyer row icon from recipe", hb is not None and hb.icon.icon == "tex:20034", hb and hb.icon.icon)
check("buyer row says what and where", hb is not None and "Crusader Weapon" in (hb.sub.text or "") and "whisper" in (hb.sub.text or ""), hb and hb.sub.text)
fire("CHAT_MSG_WHISPER", "crusader?", "Plain Jane")
pj = row_for("plain jane")
check("buyer row without GUID is white", pj is not None and "|cffffffff" in (pj.name.text or ""), pj and pj.name.text)
EP._test.buyers["holy bread"] = None; EP._test.buyers["plain jane"] = None
T.runTimers(); T.tells = lua.table()

# --- the window waits for combat to end
T.combat = True
slash("")
check("toggle in combat waits", panel.shown, panel.shown)
T.combat = False
fire("PLAYER_REGEN_ENABLED")
check("hidden after combat", not panel.shown)
slash("")
T.combat = True
tb4 = panel.tabs.buttons[4]
tb4.scripts.OnClick(tb4)
check("tab click in combat waits", shown_pages() == ["buyers"], shown_pages())
T.combat = False
fire("PLAYER_REGEN_ENABLED")
check("tab switches after combat", panel.shown and shown_pages() == ["ledger"], (panel.shown, shown_pages()))
EP.showTab("buyers")

# --- the ledger dashboard: days, best sellers, who owes
NS = T.ns
real_ledger = G.EnchantProDB.ledger
day0 = NS.dayStart()
def sale(t, en, p, g, pre=0, tip=0, mode="mats"):
    return tbl({"t": t, "k": "sale", "n": "X", "en": en, "p": p, "g": g, "pre": pre, "tip": tip, "mode": mode})
G.EnchantProDB.ledger = lua.table(
    sale(day0 + 3600, "+7 Sta Bracer", 2000, 5000, tip=1000),
    tbl({"t": day0 + 7200, "k": "pay", "n": "Y", "g": 200}),
    sale(day0 - 2 * 86400 + 3600, "Crusader Weapon", 1000, 1000),
    sale(day0 - 2 * 86400 + 7200, "Crusader Weapon", 2000, 2000),
    sale(day0 - 8 * 86400 + 3600, "Crusader Weapon", 9999, 9999),
    sale(day0 - 3600, "+5 Agi Boots", 2000, 0),
    sale(day0 - 1800, "+5 Agi Boots", 3000, 1000),
)
days = NS.ledgerDays(7)
got = [(days[i].income, days[i].tips) for i in range(1, 8)]
check("ledgerDays groups by day", got[6] == (5200, 1000) and got[4] == (3000, 0) and got[5] == (1000, 0)
      and sum(x[0] for x in got) == 9200 and days[7].day == day0, got)
best = NS.bestSellers(3)
names = [(best[i].label, best[i].count, best[i].income) for i in range(1, len(best) + 1)]
check("bestSellers order", names[:2] == [("Crusader Weapon", 3, 12999), ("+7 Sta Bracer", 1, 5000)], names)
n, c = NS.owing()
check("owing counts short and unpaid", (n, c) == (2, 4000), (n, c))
G.EnchantProDB.shown = True
slash("ledger")
lf = G.EnchantProLedger
want = NS.money(NS.net(NS.ledgerSum(day0)))
check("ledger tab tiles", lf.tiles[1].value.text is not None and want in lf.tiles[1].value.text, (lf.tiles[1].value.text, want))
check("ledger tab best sellers", "Crusader Weapon" in (lf.best[1].text or ""), lf.best[1].text)
check("ledger tab owing line", "2" in (lf.owing.text or "") and NS.money(4000) in (lf.owing.text or ""), lf.owing.text)
G.EnchantProDB.ledger = real_ledger
slash("")

# --- minimap button, compact bar, new-buyer pop-up
def clear_buyers():
    for k in list(EP._test.buyers.keys()): EP._test.buyers[k] = None
    T.ns.refresh()
clear_buyers()
mm = G.EnchantProMinimapButton
toast = G.EnchantProToast
check("badge hidden at 0", mm is not None and not mm.badge.shown)
fire("CHAT_MSG_WHISPER", "crusader please", "Ann Toast")
check("toast on new buyer", toast is not None and toast.shown and "Crusader Weapon" in (toast.what.text or "") and "Ann Toast" in (toast.who.text or ""),
      toast and (toast.shown, toast.what.text))
fire("CHAT_MSG_WHISPER", "agi boots?", "Ben Badge")
fire("CHAT_MSG_WHISPER", "+2 healing on gloves pls", "Cy Cant")
check("badge counts buyers", mm.badge.shown and mm.badge.text.text == "2", (EP._test.buyers["cy cant"] and EP._test.buyers["cy cant"].cant, mm.badge.text.text))
check("no toast for an enchant you don't have", toast.key == "ben badge", toast.key)
fire("CHAT_MSG_WHISPER", "still need crusader", "Ann Toast")
check("toast once per buyer", toast.key == "ben badge", toast.key)
advance(7); T.runTimers()
check("toast hides after 6 s", not toast.shown)
slash("compact")
bar = G.EnchantProCompact
check("compact folds", bar is not None and bar.shown and not panel.shown and "2 in queue · 0 in range" in (bar.text.text or ""),
      bar and (bar.shown, panel.shown, bar.text.text))
slash("compact")
check("compact unfolds", not bar.shown and panel.shown)
slash("minimap")
check("/ep minimap hides the button", not mm.shown)
slash("minimap")
check("/ep minimap shows it again", mm.shown)
clear_buyers(); T.runTimers(); T.tells = lua.table()

# --- the code stays in small files and adds no globals beyond its own names
import re
new_globals = [k for k in lua.eval("function() local t = {} for k in pairs(_G) do if not T.baseGlobals[k] then t[#t + 1] = tostring(k) end end return t end")().values()
               if not re.match(r"^(EnchantPro|SLASH_|BINDING_)", k)]
check("no stray globals", not new_globals, new_globals)
sizes = {f: len((addon / f).read_text(encoding="utf-8").splitlines()) for f in FILES}
check("files stay small", all(n < 700 for n in sizes.values()), sizes)
bad_art = [f for f in FILES if re.search(r'Interface\\(?!\\)', (addon / f).read_text(encoding="utf-8"))]
check("art paths keep their backslashes", not bad_art, bad_art)
check("minimap button default angle", G.EnchantProDB.ui.minimapAngle == 200, G.EnchantProDB.ui.minimapAngle)
check("compact bar default place", G.EnchantProCompact.point is not None and G.EnchantProCompact.point[5] == -80, G.EnchantProCompact.point and G.EnchantProCompact.point[5])
sibling = addon.parent / "PortalPro" / "UI" / "Kit.lua"
if sibling.exists():
    check("kit copies identical", (addon / "UI" / "Kit.lua").read_bytes() == sibling.read_bytes())
else:
    print("SKIP kit copies identical (no PortalPro next to this addon)")

# --- the widget kit (UI/Kit.lua)
Kit = T.ns.Kit
ltype = G.type
def ltab(*xs): return lua.table(*xs)
w = Kit.window("KitTestWin", "Test", r"Interface\Icons\Trade_Engraving", 300, 200, lua.table())
check("kit window builds", all(ltype(x) == "table" for x in (w.portrait, w.close, w.content, w.titleText)) if w else False)
T.badTemplates = tbl({"ButtonFrameTemplate": True, "PortraitFrameTemplate": True})
w2 = Kit.window("KitTestWin2", "Test", r"Interface\Icons\Trade_Engraving", 300, 200, lua.table())
T.badTemplates = None
check("kit window falls back", w2 is not None and w2.template == "BackdropTemplate"
      and all(ltype(x) == "table" for x in (w2.portrait, w2.close, w2.content, w2.titleText)), w2 and w2.template)
tabs = Kit.tabs(w, ltab("A", "B", "C"), None)
tabs.Select(tabs, 2)
check("kit tabs select", tabs.current == 2 and not tabs.pages[1].shown and tabs.pages[2].shown and not tabs.pages[3].shown)
bars = Kit.bars(w, 3)
bars.Set(bars, ltab(ltab(10, 0), ltab(5, 5), ltab(0, 0)))
check("kit bars proportional", [bars["items"][i].frac for i in (1, 2, 3)] == [1, 1, 0], [bars["items"][i].frac for i in (1, 2, 3)])
pb = Kit.progress(w)
pb.Set(pb, 1.5); hi = pb.frac
pb.Set(pb, -1); lo = pb.frac
check("kit progress clamps", hi == 1 and lo == 0, (hi, lo))
check("kit classHex", Kit.classHex("MAGE") == "3fc7eb" and Kit.classHex("ROGUE") == "fff569"
      and Kit.classHex(None) == "ffffff" and Kit.classHex("NOPE") == "ffffff", Kit.classHex("ROGUE"))
st = Kit.steps(w, ltab("Asked", "Mats", "Item"))
st.Set(st, 1, 2)
check("kit steps", st.done == 1 and st.current == 2)
scrolled = []
sp = Kit.row(w, 20)   # any frame will do as the scroll area
sc = Kit.scroller(sp, lambda *a: scrolled.append(1))
sc.Set(sc, 25, 6)
for _ in range(3): sp.scripts.OnMouseWheel(sp, -1)
check("kit scroller: wheel down moves the rows", sc.offset == 3 and len(scrolled) == 3, (sc.offset, len(scrolled)))
sc.Set(sc, 25, 6)
check("kit scroller: says what's above and below", "3 more" in (sc.text.text or "") and "16 more" in (sc.text.text or ""), sc.text.text)
sp.scripts.OnMouseWheel(sp, 1)
check("kit scroller: wheel up", sc.offset == 2, sc.offset)
sc.Set(sc, 5, 6)
check("kit scroller: clamps when the list shrinks", sc.offset == 0 and (sc.text.text or "") == "", (sc.offset, sc.text.text))
for _ in range(2): sp.scripts.OnMouseWheel(sp, -1)
check("kit scroller: no scrolling past the end", sc.offset == 0, sc.offset)
mk = Kit.row(w, 20)
mk.SetMark(mk, True)
on = mk.marked
mk.SetMark(mk, False)
check("kit row mark", on == True and mk.marked == False, (on, mk.marked))
T.noCloseButton = True
w3 = Kit.window("KitTestWin3", "Test", r"Interface\Icons\Trade_Engraving", 300, 200, lua.table())
T.noCloseButton = None
check("kit window without a close button gets one", ltype(w3.close) == "table", ltype(w3.close))

# --- tips only: no fee unless an enchant has its own
slash("fee 0")
nsx = T.ns
R = EP._test.REC()
bracer, crus = R[13945], R[20034]
G.EnchantProDB.fees[20034] = 5000
bob = tbl({"name": "Bob"})
rep1 = nsx.replyText(bob, bracer)
check("tips: reply says free, tips welcome", "+7 Sta Bracer: free with your mats (5 Dream Dust - trade them first), tips welcome" in rep1, rep1)
rep2 = nsx.replyText(bob, crus)
check("tips: an enchant's own fee is asked for", rep2.startswith("Crusader Weapon: 50s with your mats"), rep2)
ad = nsx.adText()
check("tips: ad", ad == "WTS Enchants: +7 Sta Bracer / Crusader Weapon. Your mats, tips welcome - or full price with my mats. Whisper me!", ad)
ask = nsx.askText(bob)
check("tips: ask", "Your mats, tips welcome - or full price with mine." in ask, ask)
check("tips: thanks without gold", nsx.thanksText(bob, "+7 Sta Bracer", 0, 0, 0, 0) == "Thank you Bob! +7 Sta Bracer done - enjoy!", nsx.thanksText(bob, "+7 Sta Bracer", 0, 0, 0, 0))
th = nsx.thanksText(bob, "+7 Sta Bracer", 1000, 1000, 0, 0)
check("tips: thanks for a tip", th == "Thank you Bob! +7 Sta Bracer done - received 10s, much appreciated.", th)
nsx.refresh()
check("tips: info line", "Fee: tips only" in (panel.info.text or ""), panel.info.text)
fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Tia")
T.npc = "Tia"
set_trade(money=0, items={1: (11176, 5)}, target={"link": "item:bracer", "name": "Bracers"})
fire("TRADE_SHOW")
st = nsx.dockState()
check("tips: nothing owed with their mats", st.owed == 0 and st.flags[5], st.owed)
check("tips: dock says tips welcome", "tips welcome" in (G.EnchantProDock.payText.text or ""), G.EnchantProDock.payText.text)
T.trade.money = 1000
fire("TRADE_MONEY_CHANGED")
check("tips: dock shows the tip", "Tip: 10s" in (G.EnchantProDock.payText.text or ""), G.EnchantProDock.payText.text)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13945)
advance(5)
n_acc = len(called("AcceptTrade"))
EP.accept()
check("tips: accept without asking for gold", len(called("AcceptTrade")) == n_acc + 1, prints()[-1])
fire("TRADE_ACCEPT_UPDATE", 1, 1)
fire("UI_INFO_MESSAGE", 0, "Trade complete.")
fire("TRADE_CLOSED")
T.runTimers()
e = G.EnchantProDB.ledger[len(G.EnchantProDB.ledger)]
check("tips: ledger counts it all as tip", e.k == "sale" and e.p == 0 and e.g == 1000 and e.tip == 1000, (e.k, e.p, e.g, e.tip))

# --- 0.2.0's 20s default turns into tips only, once; a fee you chose stays
lua4 = runtime("EnchantProDB = { fee = 2000, fees = { [20034] = 5000 } }")
G4 = lua4.globals()
G4.T.fire("ADDON_LOADED", "EnchantPro"); G4.T.fire("PLAYER_LOGIN")
check("old 20s default -> tips only, own fees kept", G4.EnchantProDB.fee == 0 and G4.EnchantProDB.fees[20034] == 5000, G4.EnchantProDB.fee)
check("old default: says so", any("tips only" in p for p in G4.T.prints.values()))
lua5 = runtime("EnchantProDB = { fee = 3000 }")
G5 = lua5.globals()
G5.T.fire("ADDON_LOADED", "EnchantPro")
check("a fee you chose stays", G5.EnchantProDB.fee == 3000, G5.EnchantProDB.fee)
lua6 = runtime("EnchantProDB = { fee = 2000, tipsDefault = true }")
G6 = lua6.globals()
G6.T.fire("ADDON_LOADED", "EnchantPro")
check("20s set again after the change stays", G6.EnchantProDB.fee == 2000, G6.EnchantProDB.fee)

# --- the group: buyers are invited (you see where they are), and let go after the enchant
lua7 = runtime()
G7 = lua7.globals()
T7, EP7 = G7.T, G7.EnchantPro
def called7(name): return [list(c.values()) for c in T7.called(name).values()]
def fire7(*a): T7.fire(*a)
def party7(*names): T7.party = lua7.table(*names); fire7("GROUP_ROSTER_UPDATE")
rg7 = lua7.eval("rawget")
def tells7(): return [t.text for t in T7.tells.values()]
eq7 = lua7.table(); eq7["item:bracer"] = "INVTYPE_WRIST"; T7.equip = eq7
fire7("ADDON_LOADED", "EnchantPro"); fire7("PLAYER_LOGIN"); fire7("TRADE_SKILL_SHOW"); T7.runTimers()
fire7("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Gia Rook")
T7.runTimers()
check("invite: a buyer who whispers is invited", called7("InviteUnit") == [["InviteUnit", "Gia Rook"]], called7("InviteUnit"))
check("invite: the reply says so", any("Group invite sent" in (t or "") for t in tells7()), tells7())
fire7("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Gia Rook")
check("invite: not twice in a row", len(called7("InviteUnit")) == 1, called7("InviteUnit"))
fire7("CHAT_MSG_CHANNEL", "LF " + FIERY + " pls", "Al Fire", "", "2. Trade", "", "", 2, 2, "Trade")
check("invite: not for an enchant you don't have", len(called7("InviteUnit")) == 1, called7("InviteUnit"))

# declines: a public ask in the next 5 minutes isn't invited again, a whisper is
fire7("CHAT_MSG_CHANNEL", "LF enchanter crusader", "Bo Nay", "", "2. Trade", "", "", 2, 2, "Trade")
check("invite: someone asking in public chat", called7("InviteUnit")[-1] == ["InviteUnit", "Bo Nay"], called7("InviteUnit"))
fire7("CHAT_MSG_SYSTEM", "Bo Nay declines your group invitation.")
T7.time = T7.time + 60
n = len(called7("InviteUnit"))
fire7("CHAT_MSG_CHANNEL", "LF enchanter crusader", "Bo Nay", "", "2. Trade", "", "", 2, 2, "Trade")
check("invite: declined, not again from public chat", len(called7("InviteUnit")) == n, called7("InviteUnit"))
fire7("CHAT_MSG_WHISPER", "crusader pls", "Bo Nay")
check("invite: declined, but a whisper asks again", len(called7("InviteUnit")) == n + 1, called7("InviteUnit"))

# joined: in the group, where they are, trade from the group unit
party7("Gia Rook")
gia = EP7._test.buyers["gia rook"]
check("invite: joined", gia.inGroup == True, gia.inGroup)
mp = lua7.table(); mp["party1"] = 1411; T7.maps = mp
T7.tick()
G7.EnchantProDB.shown = True
G7.EnchantPro.togglePanel(True)
T7.ns.refresh()
pnl7 = G7.EnchantProPanel
gia_row = [T7.ns.rows[i] for i in range(1, 7) if rg7(T7.ns.rows[i], "buyer") is not None and rg7(T7.ns.rows[i], "buyer").key == "gia rook"]
check("invite: row says in group, and where", gia_row and "in group" in (gia_row[0].right.text or "") and "Durotar" in (gia_row[0].sub.text or ""),
      gia_row and (gia_row[0].right.text, gia_row[0].sub.text))
T7.near["party1"] = True
T7.tick()
T7.ns.refresh()
grow = row_of(T7.ns, "gia rook", rg7)
grow.scripts.OnClick(grow, "LeftButton")
check("invite: a click trades with the group member in range", called7("InitiateTrade") == [["InitiateTrade", "party1"]], called7("InitiateTrade"))

# the enchant done: let go 15 s later, not before
T7.npc = "Gia Rook"
tr = lua7.table(); tr.money = 0
items = lua7.table(); items[1] = lua7.table(11176, 5); tr["items"] = items
tg = lua7.table(); tg.link = "item:bracer"; tg.name = "Bracers"; tr.target = tg
T7.trade = tr; G7.TradeFrame.shown = True
fire7("TRADE_SHOW")
fire7("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13945)
T7.time = T7.time + 5
EP7.accept()
fire7("TRADE_ACCEPT_UPDATE", 1, 1)
fire7("UI_INFO_MESSAGE", 0, "Trade complete.")
fire7("TRADE_CLOSED")
G7.TradeFrame.shown = False
T7.runTimers()
T7.tick()
check("kick: not straight after the enchant", called7("UninviteUnit") == [], called7("UninviteUnit"))
T7.time = T7.time + 16
T7.tick()
check("kick: 15 s after the enchant", called7("UninviteUnit") == [["UninviteUnit", "Gia Rook"]], called7("UninviteUnit"))

# a friend already in your group buys an enchant: no invite, never kicked
party7("Pal Friend")
n = len(called7("InviteUnit"))
fire7("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Pal Friend")
check("friend in the group: not invited", len(called7("InviteUnit")) == n, called7("InviteUnit"))
pal = EP7._test.buyers["pal friend"]
pal.state, pal.doneAt = "done", T7.time
EP7._test.letGo(pal)
T7.time = T7.time + 20
T7.tick()
check("friend in the group: never kicked", called7("UninviteUnit") == [["UninviteUnit", "Gia Rook"]], called7("UninviteUnit"))

# a full group: the buyer waits, and is invited once a spot frees
party7("A One", "B Two", "C Three", "D Four")
n = len(called7("InviteUnit"))
fire7("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Wai Ting")
check("full group: waits", len(called7("InviteUnit")) == n and EP7._test.buyers["wai ting"].queued == True)
party7("A One")
T7.tick()
check("full group: invited when a spot frees", called7("InviteUnit")[-1] == ["InviteUnit", "Wai Ting"], called7("InviteUnit")[-1:])

# right-click removes a buyer you invited, and lets them go
party7("A One", "Wai Ting")
T7.ns.refresh()
wrow = [T7.ns.rows[i] for i in range(1, 7) if rg7(T7.ns.rows[i], "buyer") is not None and rg7(T7.ns.rows[i], "buyer").key == "wai ting"]
wrow[0].scripts.OnClick(wrow[0], "RightButton")
check("right-click: removed and let go", EP7._test.buyers["wai ting"] is None and called7("UninviteUnit")[-1] == ["UninviteUnit", "Wai Ting"], called7("UninviteUnit")[-1:])

# the switches
party7()
G7.SlashCmdList.ENCHANTPRO("invite")
check("/ep invite turns inviting off", G7.EnchantProDB.invite == False)
n = len(called7("InviteUnit"))
fire7("CHAT_MSG_WHISPER", "+7 stam bracer pls", "No Inv")
check("invite off: nobody invited", len(called7("InviteUnit")) == n)
T7.ns.refresh()
nrow = [T7.ns.rows[i] for i in range(1, 7) if rg7(T7.ns.rows[i], "buyer") is not None and rg7(T7.ns.rows[i], "buyer").key == "no inv"]
nrow[0].scripts.OnClick(nrow[0], "LeftButton")
check("click on a buyer far away invites them", called7("InviteUnit")[-1] == ["InviteUnit", "No Inv"], called7("InviteUnit")[-1:])
G7.SlashCmdList.ENCHANTPRO("kick")
check("/ep kick turns letting go off", G7.EnchantProDB.autoKick == False)
tg_keys = [T7.ns.toggles[i].key for i in range(1, len(T7.ns.toggles) + 1)]
check("invite and kick toggles on the Buyers tab", "invite" in tg_keys and "autoKick" in tg_keys, tg_keys)

# --- the queue: numbers, order, lifetime, saved through a reload or a restart
lua_type = LUPA.lua_type
def lua_src(v):
    """A saved Lua value written back as Lua source, for a fresh runtime."""
    t = lua_type(v)
    if t == "table":
        parts = []
        for k, x in v.items():
            key = ("[%d]" % k) if isinstance(k, int) else ("[%r]" % k).replace("'", '"')
            parts.append(key + " = " + lua_src(x))
        return "{ " + ", ".join(parts) + " }"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    return "nil"
def fresh(pre=""):
    l = runtime(pre)
    g = l.globals()
    eq = l.table(); eq["item:bracer"] = "INVTYPE_WRIST"; eq["item:boots"] = "INVTYPE_FEET"; eq["item:sword"] = "INVTYPE_WEAPON"
    g.T.equip = eq
    return l, g, g.T
lua8, G8, T8 = fresh()
T8.fire("ADDON_LOADED", "EnchantPro"); T8.fire("PLAYER_LOGIN"); T8.fire("TRADE_SKILL_SHOW"); T8.runTimers()
Q = T8.ns
qb = Q.buyers
T8.fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Ann A")
T8.time = T8.time + 5
T8.fire("CHAT_MSG_WHISPER", "crusader pls", "Ben B")
T8.time = T8.time + 5
T8.fire("CHAT_MSG_WHISPER", "+5 agi boots pls", "Cy C")
check("queue: numbered in the order they asked", (qb["ann a"].n, qb["ben b"].n, qb["cy c"].n) == (1, 2, 3), (qb["ann a"].n, qb["ben b"].n, qb["cy c"].n))
T8.time = T8.time + 30
T8.fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Ann A")
check("queue: asking again keeps the number", qb["ann a"].n == 1 and Q.place(qb["ann a"]) == 1, qb["ann a"].n)
check("queue: place", Q.place(qb["cy c"]) == 3, Q.place(qb["cy c"]))
T8.fire("CHAT_MSG_CHANNEL", "LF " + FIERY + " pls", "Al Fire", "", "2. Trade", "", "", 2, 2, "Trade")
ql = Q.queueList()
check("queue: someone you can't serve gets no number, listed last", qb["al fire"].n is None and [ql[i].key for i in range(1, 5)] == ["ann a", "ben b", "cy c", "al fire"],
      [ql[i].key for i in range(1, len(ql) + 1)])
T8.time = T8.time + 11 * 60
T8.tick()
check("queue: still there after 11 minutes", qb["ann a"] is not None and qb["cy c"] is not None)
wait_before = T8.time - qb["ann a"].since
# hover a row: what they typed, and what the addon made of it
G8.EnchantPro.togglePanel(True); T8.ns.refresh()
ra = row_of(T8.ns, "ann a", G8.rawget)
G8.GameTooltip.text = None
if ra is not None and ra.scripts.OnEnter: ra.scripts.OnEnter(ra)
tip8 = G8.rawget(G8.GameTooltip, "text") or ""
lab8 = T8.ns.REC[qb["ann a"].rec].label
check("hover: the row's tooltip shows what they typed", "+7 stam bracer pls" in tip8, tip8)
check("hover: ... and the enchant it was read as", lab8 in tip8 and "whisper" in tip8, tip8)
T8.fire("CHAT_MSG_CHANNEL", "LF " + FIERY + " pls", "Al Fire", "", "2. Trade", "", "", 2, 2, "Trade")   # gone after 11 min; asks again
T8.ns.refresh()
rf = row_of(T8.ns, "al fire", G8.rawget)
G8.GameTooltip.text = None
if rf is not None and rf.scripts.OnEnter: rf.scripts.OnEnter(rf)
tipf = G8.rawget(G8.GameTooltip, "text") or ""
check("hover: a line you can't serve shows too, with where it was said", "pls" in tipf and "Trade" in tipf, tipf)
for i in range(1, 8):
    T8.fire("CHAT_MSG_WHISPER", "LF " + FIERY + " pls " + str(i), "Al Fire")
sd = G8.rawget(qb["al fire"], "said") or []
check("hover: keeps the last 5 lines", len(sd) == 5 and sd[1].text.endswith("pls 3") and sd[5].text.endswith("pls 7"),
      [sd[i].text for i in range(1, len(sd) + 1)] if len(sd) else sd)
check("hover: lines don't give a number", qb["al fire"].n is None)

# a client restart: GetTime starts over, the wall clock moved on 60 s
T8.fire("PLAYER_LOGOUT")
saved_wall = G8.time()
src = "EnchantProDB = " + lua_src(G8.EnchantProDB)
lua9, G9, T9 = fresh(src)
T9.time = 100
T9.wallOffset = saved_wall + 60 - 100
T9.fire("ADDON_LOADED", "EnchantPro"); T9.fire("PLAYER_LOGIN")
qb9 = T9.ns.buyers
ok = qb9["ann a"] is not None and qb9["ben b"] is not None and qb9["cy c"] is not None
check("restore: the queue is back after a restart", ok and (qb9["ann a"].n, qb9["ben b"].n, qb9["cy c"].n) == (1, 2, 3),
      ok and (qb9["ann a"].n, qb9["ben b"].n, qb9["cy c"].n))
check("restore: waiting time carries on", ok and abs((T9.time - qb9["ann a"].since) - (wait_before + 60)) <= 1,
      ok and (T9.time - qb9["ann a"].since, wait_before + 60))
check("restore: the save is cleared once loaded", G9.EnchantProDB.queues["Mage"] is None)
said9 = qb9["ann a"] and G9.rawget(qb9["ann a"], "said")
check("restore: what they typed is kept too", said9 is not None and any(said9[i].text == "+7 stam bracer pls" for i in range(1, len(said9) + 1)))
T9.fire("CHAT_MSG_WHISPER", "crusader pls", "Dee D")
check("restore: numbers carry on", qb9["dee d"].n == 4, qb9["dee d"].n)
T9.npc = "Tra Der"
tr = lua9.table(); tr.money = 0; tr["items"] = lua9.table()
tg = lua9.table(); tg.link = "item:sword"; tg.name = "Sword"; tr.target = tg
T9.trade = tr; G9.TradeFrame.shown = True
T9.fire("TRADE_SHOW")
check("queue: someone who opens trade without asking gets a number", qb9["tra der"] is not None and qb9["tra der"].n == 5,
      qb9["tra der"] and qb9["tra der"].n)
T9.fire("TRADE_CLOSED"); G9.TradeFrame.shown = False
T9.time = T9.time + 7201
T9.tick()
check("queue: dropped after 2 hours without a word", qb9["ann a"] is None and qb9["dee d"] is None)

# --- one order, several enchants
lua10, G10, T10 = fresh()
T10.fire("ADDON_LOADED", "EnchantPro"); T10.fire("PLAYER_LOGIN"); T10.fire("TRADE_SKILL_SHOW"); T10.runTimers()
N10, EP10 = T10.ns, G10.EnchantPro
qb10 = N10.buyers
def wants10(key):
    w = qb10[key].wants
    return [(w[i].id, bool(w[i].done)) for i in range(1, len(w) + 1)] if w else []
def trade10(name, item, mats, money=0):
    T10.npc = name
    tr = lua10.table(); tr.money = money
    it = lua10.table()
    for slot, (iid, q) in mats.items(): it[slot] = lua10.table(iid, q)
    tr["items"] = it
    tg = lua10.table(); tg.link = item; tg.name = item; tr.target = tg
    T10.trade = tr; G10.TradeFrame.shown = True
    T10.fire("TRADE_SHOW")
def finish10(spell):
    T10.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", spell)
    T10.time = T10.time + 5
    EP10.accept()
    T10.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    T10.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
    T10.fire("TRADE_CLOSED"); G10.TradeFrame.shown = False
    T10.runTimers()
T10.fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Ann Zed")
T10.fire("CHAT_MSG_WHISPER", "and +5 agi boots", "Ann Zed")
check("order: a second enchant is added", wants10("ann zed") == [(13945, False), (13935, False)] and qb10["ann zed"].rec == 13945, wants10("ann zed"))
T10.fire("CHAT_MSG_WHISPER", "+3 stam bracer actually", "Ann Zed")
check("order: an enchant for the same slot replaces the first", wants10("ann zed") == [(13648, False), (13935, False)], wants10("ann zed"))
T10.fire("CHAT_MSG_WHISPER", "crusader pls", "Ben B")
EP10.updateCast()
mt = G10.EnchantProCastButton.attrs["macrotext"] or ""
check("no trade: Cast holds the first open enchant of the first order", "Enchant Bracer - Stamina" in mt, mt)
trade10("Ann Zed", "item:boots", {1: (11174, 2)})
check("order: the item picks the enchant from the order", EP10.plan() is not None and EP10.plan().id == 13935, EP10.plan() and EP10.plan().id)
finish10(13935)
check("order: one enchant done, the order waits for the next", wants10("ann zed") == [(13648, False), (13935, True)] and qb10["ann zed"].state == "asked" and qb10["ann zed"].kickAt is None,
      (wants10("ann zed"), qb10["ann zed"].state))
trade10("Ann Zed", "item:bracer", {1: (10940, 6)})
finish10(13648)
check("order: done when every enchant is", qb10["ann zed"].state == "done", qb10["ann zed"].state)
T10.time = T10.time + 61
T10.fire("CHAT_MSG_WHISPER", "+5 agi boots pls", "Ann Zed")
check("order: asking after done is a new order at the back", qb10["ann zed"].n == 3 and wants10("ann zed") == [(13935, False)],
      (qb10["ann zed"].n, wants10("ann zed")))
# a saved order from before wants, and an enchant this character doesn't know
G10.EnchantProDB.queues["Mage"] = lua10.eval("function(t) return { saved = t, list = { { key = 'old o', name = 'Old O', n = 50, state = 'asked', at = t, rec = 13945 }, { key = 'odd o', name = 'Odd O', n = 51, state = 'asked', at = t, wants = { { id = 99999 } } } } } end")(G10.time())
N10.loadQueue()
check("restore: an old order's enchant becomes its list", wants10("old o") == [(13945, False)], wants10("old o"))
trade10("Odd O", "item:sword", {})
ok, err = lua10.eval("function() return pcall(EnchantPro.plan) end")()
check("an enchant you don't know in an order: no error", ok, err)
T10.fire("TRADE_CLOSED"); G10.TradeFrame.shown = False

# --- the queue on screen
lua11, G11, T11 = fresh()
T11.fire("ADDON_LOADED", "EnchantPro"); T11.fire("PLAYER_LOGIN"); T11.fire("TRADE_SKILL_SHOW"); T11.runTimers()
N11 = T11.ns
rg11 = lua11.eval("rawget")
T11.tells = lua11.table()
T11.fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Ann Zed"); T11.runTimers()
T11.fire("CHAT_MSG_WHISPER", "crusader pls", "Ben Yo"); T11.runTimers()
tl = [t.text or "" for t in T11.tells.values()]
check("reply: the first in line isn't told a place", tl and "in the queue" not in tl[0], tl)
check("reply: the second hears their place", len(tl) >= 2 and "You're #2 in the queue." in tl[-1], tl)
for i in range(1, 26):
    T11.fire("CHAT_MSG_WHISPER", "crusader pls", "B%02d Qx" % i)
T11.runTimers()
G11.EnchantPro.togglePanel(True)
N11.refresh()
def row_name(i): return re.sub(r"\|c[0-9a-f]{8}|\|r", "", N11.rows[i].name.text or "")
check("rows: numbered", "#1 " in row_name(1) and "Ann Zed" in row_name(1) and "#2 " in row_name(2), (row_name(1), row_name(2)))
page11 = G11.EnchantProBuyers
for _ in range(3): page11.scripts.OnMouseWheel(page11, -1)
check("rows: the wheel scrolls the queue", "#4 " in row_name(1), row_name(1))
more = N11.scroll.text.text or ""
check("rows: says how many more", "3 more" in more and "more" in more, more)
for _ in range(3): page11.scripts.OnMouseWheel(page11, 1)
ann = N11.buyers["ann zed"]
N11.addWant(ann, N11.REC[13935]); N11.tickWant(ann, 13945)
T11.units["target"] = "Ben Yo"; T11.near["target"] = True
T11.tick()
N11.refresh()
ar, br = row_of(N11, "ann zed", rg11), row_of(N11, "ben yo", rg11)
sub = ar.sub.text or ""
check("rows: every enchant of the order, done ones ticked", "+7 Sta Bracer" in sub and "+5 Agi Boots" in sub and "ReadyCheck-Ready" in sub, sub)
check("rows: the first in range is marked", br.marked == True and ar.marked == False, (br.marked, ar.marked))
check("bar: counts the queue", (G11.EnchantProCompact.text.text or "").startswith("27 in queue · 1 in range"), G11.EnchantProCompact.text.text)
keys11 = [N11.toggles[i].key for i in range(1, len(N11.toggles) + 1)]
check("no Trade switch any more", "autoTrade" not in keys11, keys11)

# --- review fixes: trades count as word, prepayment carries, a buyer you can't serve leaves
lua12, G12, T12 = fresh()
T12.fire("ADDON_LOADED", "EnchantPro"); T12.fire("PLAYER_LOGIN"); T12.fire("TRADE_SKILL_SHOW"); T12.runTimers()
N12, EP12, qb12 = T12.ns, G12.EnchantPro, T12.ns.buyers
def trade12(name, item=None, mats=None, money=0, spell=None):
    T12.npc = name
    tr = lua12.table(); tr.money = money
    it = lua12.table()
    for slot, (iid, q) in (mats or {}).items(): it[slot] = lua12.table(iid, q)
    tr["items"] = it
    if item:
        tg = lua12.table(); tg.link = item; tg.name = item; tr.target = tg
    T12.trade = tr; G12.TradeFrame.shown = True
    T12.fire("TRADE_SHOW")
    if spell: T12.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", spell)
    T12.time = T12.time + 5
    T12.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    T12.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
    T12.fire("TRADE_CLOSED"); G12.TradeFrame.shown = False
    T12.runTimers()
T12.fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Mat Giver")
T12.time = T12.time + 110 * 60
trade12("Mat Giver", mats={1: (11176, 5)})
T12.time = T12.time + 11 * 60
T12.tick()
check("a buyer who handed over mats isn't dropped as quiet", qb12["mat giver"] is not None and qb12["mat giver"].given[11176] == 5)
G12.EnchantProDB.fulls[13945] = 10000; G12.EnchantProDB.fulls[13935] = 10000
T12.fire("CHAT_MSG_WHISPER", "+7 stam bracer pls", "Pre Payer")
T12.fire("CHAT_MSG_WHISPER", "+5 agi boots too", "Pre Payer")
trade12("Pre Payer", money=20000)
trade12("Pre Payer", item="item:bracer", spell=13945)
pp12 = qb12["pre payer"]
check("prepayment: what's left carries to the next enchant", pp12.state != "done" and pp12.paid == 10000, (pp12.state, pp12.paid))
T12.fire("CHAT_MSG_WHISPER", "need an enchanter pls", "Can Not")
T12.fire("CHAT_MSG_WHISPER", "LF " + FIERY, "Can Not")
T12.time = T12.time + 11 * 60
T12.tick()
check("a numbered buyer you then can't serve leaves after 10 minutes", qb12["can not"] is None, qb12["can not"] and (qb12["can not"].cant, qb12["can not"].n))

# --- saved settings from 0.2.0 (separate windows) load cleanly
lua3 = runtime("EnchantProDB = { point = { 'CENTER', 'CENTER', -300, 0 }, shown = true, frames = { ledger = { point = { 'CENTER', 'CENTER', 10, 10 }, w = 460, h = 430 }, messages = { w = 520, h = 420 }, enchants = { w = 560, h = 400 }, panel = { w = 320, h = 290 } } }")
G3 = lua3.globals()
G3.T.fire("ADDON_LOADED", "EnchantPro"); G3.T.fire("PLAYER_LOGIN")
check("old window saves load", G3.EnchantPro.started == True and G3.EnchantProPanel is not None and G3.EnchantProPanel.tabs is not None)

# --- not an enchanter: off, until the profession shows up
lua2 = runtime()
G2 = lua2.globals()
G2.T.enchanter = False
G2.T.fire("ADDON_LOADED", "EnchantPro")
G2.T.fire("PLAYER_LOGIN")
check("not an enchanter: off", G2.EnchantPro.started is None and G2.EnchantProPanel is None)
G2.SlashCmdList.ENCHANTPRO("")
check("slash says enchanters only", any("only works on an enchanter" in p for p in G2.T.prints.values()))
G2.T.enchanter = True
G2.T.fire("SKILL_LINES_CHANGED")
check("starts once the profession shows up", G2.EnchantPro.started == True and G2.EnchantProPanel is not None)

print()
print(f"{fails} failure(s)")
sys.exit(1 if fails else 0)
