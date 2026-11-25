"""Offline tests for EnchantPro: a fake WoW API (harness.lua) driven through Lua 5.1 by lupa.
python tests/run_tests.py [addon folder]"""
import sys, pathlib
import lupa.lua51 as LUPA

here = pathlib.Path(__file__).parent
addon = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent
harness = (here / "harness.lua").read_text(encoding="utf-8")
src = (addon / "EnchantPro.lua").read_text(encoding="utf-8")

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + (("  -- " + str(extra)) if extra and not ok else ""))
    if not ok: fails += 1

def runtime(pre=""):
    lua = LUPA.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(pre + "\n" + harness)
    lua.eval("function(src) local f, e = loadstring(src, 'EnchantPro.lua'); if not f then error(e) end; return f end")(src)("EnchantPro")
    return lua

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
check("reply names enchant, fee and mats", tells and "+7 Sta Bracer: 20s tip with your mats (5 Dream Dust - trade them first)" in (tells[0].text or ""), tells and tells[0].text)
check("cast button holds the buyer's enchant", G.EnchantProCastButton.attrs["macrotext"] == "/cast Enchant Bracer - Greater Stamina", G.EnchantProCastButton.attrs["macrotext"])
check("cast button flags missing mats", "(no mats)" in G.EnchantProCastButton.text, G.EnchantProCastButton.text)

# --- the buyer comes near: trade opens
T.units["target"] = "Nx Thearabian"; T.near["target"] = True
T.tick()
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

# --- the ad
G.EnchantProDB.adList[13945] = True; G.EnchantProDB.adList[20034] = True
advance(100)
EP.postAd()
T.runTimers()
oc = called("OpenChat")
check("ad in the chat box", oc and oc[-1][1] == "/2 WTS Enchants: +7 Sta Bracer / Crusader Weapon. Your mats + 20s tip, or full price with my mats. Whisper me!", oc and oc[-1])

# --- windows
ef = G.EnchantProEnchants
ef.Show(ef)
check("enchants window lists all 9 in order", [ef.rows[i].rec.label for i in range(1, 10)] == labels, [ef.rows[i].rec.label for i in range(1, 10)])
ef.SetSize(ef, 600, 300)
check("enchants window rows follow the height", ef.visible == 9, ef.visible)
row = ef.rows[2]
row.fee.scripts.OnEditFocusGained(row.fee)
row.fee.SetText(row.fee, "35s")
row.fee.scripts.OnEditFocusLost(row.fee)
check("fee edit saves for that enchant", G.EnchantProDB.fees[row.rec.id] == 3500, G.EnchantProDB.fees[row.rec.id])
mf = G.EnchantProMessages
mf.Show(mf)
check("messages window: 4 editors", len(list(mf.eds.values())) == 4)
lf = G.EnchantProLedger
lf.Show(lf)
check("ledger shows entries", "Nx Thearabian" in (lf.rows[3].text or "") or "Nx Thearabian" in (lf.rows[2].text or ""), [lf.rows[i].text for i in (1, 2, 3)])
panel = G.EnchantProPanel
panel.SetSize(panel, 400, 500)
check("panel rows follow the height", panel.visibleRows == 17, panel.visibleRows)

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
