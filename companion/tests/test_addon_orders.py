"""Craft orders in the addon (Orders.lua), run with lupa (Lua 5.1 like the game) on stubbed WoW APIs:
orders from the companion's file, filtering per character / account, answered orders hidden and
pruned, the 2|O|... payload, orderIdentity, grouping and pagination, and a smoke run of the window."""

import os
import random
import unittest

import lupa.lua51 as lua51

ADDON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "WallOfShameForever")
FILES = ["Locales.lua", "DeathStrip.lua", "WallOfShameForever.lua", "Orders.lua"]
ME = "Chamy Chan-CAMWOWEU5Realm2PvP"

STUBS = r"""
STATE = { chat = {}, timers = {}, frames = {}, strips = {}, requested = {}, sounds = 0, itemData = {},
          now = 1763030000, battletag = "Alen#1234", guild = "Bagarre", name = "Chamy", second = "Chan",
          realm = "CAMWOWEU5Realm2PvP", level = 21, class = "SHAMAN" }

local methods = {}
local Stub
function methods.SetScript(self, name, fn) self._scripts[name] = fn end
function methods.GetScript(self, name) return self._scripts[name] end
function methods.RegisterEvent(self, event) self._events[event] = true end
function methods.Show(self)
    local was = self._shown
    self._shown = true
    if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function methods.Hide(self)
    local was = self._shown
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function methods.IsShown(self) return self._shown end
function methods.Enable(self) self._enabled = true end
function methods.Disable(self) self._enabled = false end
function methods.IsEnabled(self) return self._enabled ~= false end
function methods.SetFont() return true end
function methods.CreateTexture(self) return Stub(self) end
function methods.CreateFontString(self) return Stub(self) end
function methods.GetParent(self) return self._parent end
function methods.SetText(self, text) self._text = text end
function methods.GetText(self) return self._text end
Stub = function(parent)
    local o = { _scripts = {}, _events = {}, _shown = true, _parent = parent }
    return setmetatable(o, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if type(key) == "string" and (key:match("^Is") or key:match("^Has")) then
            return function() return false end
        end
        if type(key) == "string" and key:match("^Get") then return function() return 0 end end
        return function() end
    end })
end

function CreateFrame(kind, name, parent)
    local f = Stub(parent)
    table.insert(STATE.frames, f)
    if name then _G[name] = f end
    return f
end
function Fire(event, ...)
    for _, f in ipairs(STATE.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end
function RunTimers()
    local timers = STATE.timers
    STATE.timers = {}
    for _, fn in ipairs(timers) do fn() end
end

UIParent, WorldFrame, Minimap, GameTooltip = Stub(), Stub(), Stub(), Stub()
UISpecialFrames, SlashCmdList = {}, {}
tinsert = table.insert
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(STATE.chat, msg) end }
C_Timer = { After = function(_, fn) table.insert(STATE.timers, fn) end }
C_Item = { RequestLoadItemDataByID = function(id) STATE.requested[id] = true end }
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 } }
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 } }
function time() return STATE.now end
function date(...) return os.date(...) end
function GetTime() return STATE.now end
function GetLocale() return "frFR" end
function UnitFullName() return STATE.name, STATE.second end
function GetNormalizedRealmName() return STATE.realm end
function UnitGUID() return "Player-1-0001" end
function UnitClass() return "Chaman", STATE.class end
function UnitLevel() return STATE.level end
function GetRealZoneText() return "Elwynn" end
function GetGuildInfo() return STATE.guild end
function IsInGuild() return STATE.guild ~= nil end
function BNGetInfo() return 1, STATE.battletag end
function PlaySound() STATE.sounds = STATE.sounds + 1 end
function GetItemInfo(id)
    local item = STATE.itemData[id]
    if item then return item.name, nil, item.quality, nil, nil, nil, nil, nil, nil, item.icon end
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, text)
    local out, start = {}, 1
    while true do
        local i = string.find(text, sep, start, true)
        if not i then table.insert(out, text:sub(start)) break end
        table.insert(out, text:sub(start, i - 1))
        start = i + 1
    end
    return unpack(out)
end
"""


def order(oid, artisan=ME, buyer="Grumbar", realm="CAMWOWEU5Realm2PvP", item=2152, created=1763020000, **kw):
    o = {"id": oid, "artisan": artisan, "buyer": {"name": buyer, "realm": realm, "class": "HUNTER", "level": 30},
         "itemId": item, "itemName": "Light Armor Kit", "qty": 2, "note": "pour demain", "createdAt": created}
    o.update(kw)
    return o


class Addon:
    """The addon loaded in a fresh Lua state; login() fires ADDON_LOADED and PLAYER_LOGIN."""

    def __init__(self, orders=None, db=None, raw_orders=None):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUBS)
        self.g = self.lua.globals()
        self.ns = self.lua.table()
        load = self.lua.eval("function(src, name, ns) assert(loadstring(src, name))('WallOfShameForever', ns) end")
        for name in FILES:
            with open(os.path.join(ADDON, name), encoding="utf-8") as f:
                load(f.read(), name, self.ns)
        if db is not None:
            self.g.WallOfShameForeverDB = self.to_lua(db)
        if raw_orders is not None:
            self.g.WallOfShameForever_Orders = self.to_lua(raw_orders)
        elif orders is not None:
            self.g.WallOfShameForever_Orders = self.to_lua({"updated": 1763030000, "orders": orders})
        self.strips = []
        self.ns.ShowStrip = lambda payload: self.strips.append(payload)

    def to_lua(self, value):
        if isinstance(value, dict):
            t = self.lua.table()
            for k, v in value.items():
                t[k] = self.to_lua(v)
            return t
        if isinstance(value, list):
            return self.lua.table(*[self.to_lua(v) for v in value])
        return value

    def login(self):
        fire = self.g.Fire
        fire("ADDON_LOADED", "WallOfShameForever")
        fire("PLAYER_LOGIN")
        return self

    @property
    def db(self):
        return self.g.WallOfShameForeverDB

    @property
    def orders(self):
        return self.ns.Orders

    def pending(self, scope):
        return [o.id for o in self.orders.List(scope).values()]

    def lua_list(self, t):
        return list(t.values()) if t else []


class IdentityTest(unittest.TestCase):
    def test_written_at_login(self):
        a = Addon().login()
        identity = a.db.orderIdentity
        self.assertEqual(identity.battletag, "Alen#1234")
        self.assertEqual(a.lua_list(identity.characters), [ME])

    def test_accumulates_dedupes_and_keeps_battletag(self):
        db = {"orderIdentity": {"battletag": "Old#1", "characters": ["Alt-CAMWOWEU5Realm2PvP",
                                                                     ME.lower(), 5, "", "Alt-CAMWOWEU5Realm2PvP"]}}
        a = Addon(db=db)
        a.g.STATE.battletag = None  # BNGetInfo without battletag: the known one stays
        a.login()
        identity = a.db.orderIdentity
        self.assertEqual(identity.battletag, "Old#1")
        self.assertEqual(a.lua_list(identity.characters), [ME, "Alt-CAMWOWEU5Realm2PvP"])

    def test_capped(self):
        db = {"orderIdentity": {"characters": ["C%d-R" % i for i in range(80)]}}
        a = Addon(db=db).login()
        characters = a.lua_list(a.db.orderIdentity.characters)
        self.assertEqual(len(characters), 50)
        self.assertEqual(characters[:2], [ME, "C0-R"])
        self.assertEqual(a.db.orderIdentity.battletag, "Alen#1234")


class FilterTest(unittest.TestCase):
    ORDERS = [order("a1"), order("a2", artisan="Alt-CAMWOWEU5Realm2PvP"), order("a3", artisan="Stranger-Other"),
              order("a4", artisan=ME.upper())]

    def addon(self, **kw):
        db = {"orderIdentity": {"characters": ["Alt-CAMWOWEU5Realm2PvP"]}}
        db.update(kw)
        return Addon(orders=self.ORDERS, db=db).login()

    def test_character_and_account(self):
        a = self.addon()
        self.assertEqual(sorted(a.pending("char")), ["a1", "a4"])
        self.assertEqual(sorted(a.pending("account")), ["a1", "a2", "a4"])  # never another account's

    def test_handled_hidden_and_pruned(self):
        a = self.addon(ordersHandled={"a1": "done", "gone": "refused"})
        self.assertEqual(sorted(a.pending("account")), ["a2", "a4"])
        self.assertEqual(dict(a.db.ordersHandled), {"a1": "done"})  # no longer in the file: forgotten

    def test_missing_file_keeps_handled(self):
        a = Addon(db={"ordersHandled": {"a1": "done"}}).login()
        self.assertEqual(a.pending("account"), [])
        self.assertEqual(dict(a.db.ordersHandled), {"a1": "done"})
        self.assertEqual(a.orders.Notify(), 0)
        self.assertEqual(a.g.STATE.sounds, 0)
        a.g.SlashCmdList.WALLOFSHAMEFOREVER("commandes")  # empty window, no error
        win = a.g.WallOfShameForeverOrders
        self.assertTrue(win.IsShown(win))
        self.assertTrue(win.empty.IsShown(win.empty))
        self.assertIn("Pas encore", win.empty.hint._text)

    def test_bad_entries_skipped(self):
        raw = {"orders": [5, {"id": None, "artisan": ME}, {"id": 7, "artisan": ME}, {"id": "x"},
                          {"id": "b", "artisan": ME, "buyer": "nope", "qty": -3, "itemId": "abc"}]}
        a = Addon(raw_orders=raw).login()
        self.assertEqual(sorted(a.pending("char")), ["7", "b"])
        b = [o for o in a.orders.List("char").values() if o.id == "b"][0]
        self.assertEqual((b.qty, b.itemId, b.buyer.name, b.note), (1, None, "?", ""))

    def test_not_a_table(self):
        for raw in ("oops", {"orders": "oops"}, {}):
            a = Addon(raw_orders=raw).login()
            self.assertEqual(a.pending("account"), [])


class PayloadTest(unittest.TestCase):
    def addon(self):
        return Addon(orders=[order("ord-1"), order("ord-2")]).login()

    def test_done(self):
        a = self.addon()
        o = a.orders.List("char")[1]
        payload = a.orders.Mark(o, "done", "")
        self.assertEqual(payload, "2|O|%s:O:ord-1:done|Chamy Chan|CAMWOWEU5Realm2PvP|Bagarre|21|SHAMAN|1763030000"
                                  "|Alen#1234|ord-1|done|" % ME)
        self.assertIn(payload, a.lua_list(a.db.outbox))
        self.assertEqual(a.strips, [payload])
        self.assertEqual(dict(a.db.ordersHandled), {"ord-1": "done"})
        self.assertEqual(a.pending("char"), ["ord-2"])
        self.assertIsNone(a.orders.Mark(o, "refused", "x"))  # already answered
        self.assertIn("Commande faite", a.lua_list(a.g.STATE.chat)[-1])

    def test_second_strip_waits_for_the_first(self):
        a = self.addon()
        first, second = a.orders.List("char")[1], a.orders.List("char")[2]
        p1 = a.orders.Mark(first, "done", "")
        p2 = a.orders.Mark(second, "refused", "non")
        self.assertEqual(a.strips, [p1])
        a.g.RunTimers()
        self.assertEqual(a.strips, [p1, p2])
        self.assertEqual(len(a.lua_list(a.db.outbox)), 2)

    def test_reason_sanitized(self):
        a = self.addon()
        self.assertEqual(a.orders.CleanReason("  Pas|de;cuir:dispo,\n désolé=  "), "Pas de cuir dispo désolé")
        self.assertEqual(a.orders.CleanReason(None), "")
        self.assertEqual(a.orders.CleanReason("é" * 100), "é" * 80)
        payload = a.orders.Payload("ord-1", "refused", "a|b" + "x" * 200)
        fields = payload.split("|")
        self.assertEqual(len(fields), 13)
        self.assertEqual(fields[10:12], ["ord-1", "refused"])
        self.assertEqual(fields[12], "a b" + "x" * 77)

    def test_fits_the_strip(self):
        a = self.addon()
        a.g.STATE.guild = "Les Chevaliers de la Table Ronde"
        a.g.STATE.battletag = "Quelquunavecunlongnom#123456"
        payload = a.orders.Payload("0123456789abcdef0123456789abcdef", "refused", "é" * 80)
        raw = payload.encode("utf-8") if isinstance(payload, str) else payload
        self.assertLessEqual(len(raw), 240)
        text = raw.decode("utf-8")  # never cut inside a character
        self.assertTrue(text.split("|")[12].startswith("é"))
        self.assertLess(len(text.split("|")[12]), 80)


class PaginationTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon().login()

    def groups(self, orders):
        lua_orders = self.a.orders.ReadSource(self.a.to_lua({"orders": orders}))
        return self.a.orders.Group(lua_orders)

    def test_group_order(self):
        groups = self.groups([order("x2", buyer="Zed", created=50), order("x1", buyer="Zed", created=10),
                              order("y1", buyer="Amy", created=30), order("z1", buyer="zed", created=5)])
        keys = [(g.buyer.name, [o.id for o in g.orders.values()]) for g in groups.values()]
        self.assertEqual(keys, [("Zed", ["z1", "x1", "x2"]), ("Amy", ["y1"])])  # same buyer whatever the case

    def test_group_split_repeats_header(self):
        groups = self.groups([order("o%02d" % i, created=i) for i in range(10)])
        pages = self.a.orders.Paginate(groups, 404, 28, 46)
        shape = [[("H+" if e.continued else "H") if e.header and not e.order else "I" for e in p.values()]
                 for p in pages.values()]
        self.assertEqual(shape, [["H"] + ["I"] * 8, ["H+"] + ["I"] * 2])

    def test_no_lonely_header(self):
        groups = self.groups([order("a%d" % i, buyer="A", created=i) for i in range(7)]
                             + [order("b%d" % i, buyer="B", created=100 + i) for i in range(3)])
        pages = self.a.orders.Paginate(groups, 404, 28, 46)
        self.assertEqual([len(p) for p in pages.values()], [8, 4])  # B starts on page 2, header included

    def test_empty(self):
        pages = self.a.orders.Paginate(self.a.lua.table(), 404, 28, 46)
        self.assertEqual(len(pages), 1)
        self.assertEqual(len(pages[1]), 0)

    def test_invariants(self):
        rnd = random.Random(4)
        for _ in range(60):
            orders = [order("r%d" % i, buyer="B%d" % rnd.randrange(6), created=rnd.randrange(1000))
                      for i in range(rnd.randrange(1, 40))]
            capacity = rnd.choice([74, 120, 200, 404])
            pages = self.a.orders.Paginate(self.groups(orders), capacity, 28, 46)
            seen = []
            for page in pages.values():
                entries = list(page.values())
                self.assertTrue(entries)
                self.assertTrue(entries[-1].order)  # never ends on a header
                self.assertLessEqual(sum(28 if e.header else 46 for e in entries), capacity)
                current = None
                for e in entries:
                    if e.header:
                        current = e.header
                    else:
                        self.assertEqual(e.group.key, current.key)  # under its own buyer's header
                        seen.append(e.order.id)
            self.assertEqual(sorted(seen), sorted(o["id"] for o in orders))

    def test_age(self):
        age = self.a.orders.Age
        self.assertEqual(age(1000, 990), "à l'instant")
        self.assertEqual(age(10000, 10000 - 7200), "il y a 2 h")
        self.assertEqual(age(10000, 10000 - 300), "il y a 5 min")
        self.assertEqual(age(500000, 500000 - 3 * 86400), "il y a 3 j")


class WindowTest(unittest.TestCase):
    def test_smoke(self):
        orders = [order("o%02d" % i, buyer="B%d" % (i % 3), created=1763000000 + i) for i in range(14)]
        orders.append(order("unk", item=99999, itemName=None, note="", created=1))  # first group: on page 1
        a = Addon(orders=orders).login()
        a.g.STATE.itemData[2152] = a.to_lua({"name": "Nécessaire d'armure léger", "quality": 1, "icon": 133611})
        # login notification: toast, sound, one chat line
        self.assertEqual(a.orders.Notify(), 15)
        self.assertEqual(a.g.STATE.sounds, 1)
        self.assertIn("15 commandes en attente", a.lua_list(a.g.STATE.chat)[-1])
        toast = a.g.WallOfShameForeverOrdersToast
        toast.GetScript(toast, "OnClick")(toast, "LeftButton")
        win = a.g.WallOfShameForeverOrders
        self.assertTrue(win.IsShown(win))
        self.assertEqual(win.title._text, "Commandes de Chamy Chan")
        self.assertEqual(win.pageText._text, "Page 1/2")  # 600 px high since v0.6.2
        self.assertEqual(win.total._text, "15 commandes en attente")
        self.assertTrue(a.g.STATE.requested[99999])  # unknown item asked to the server
        a.g.Fire("GET_ITEM_INFO_RECEIVED", 99999, False)
        win.next.GetScript(win.next, "OnClick")(win.next)
        self.assertEqual(a.orders.ui.page, 2)
        # refuse with a reason through the popup
        target = a.orders.List("char")[1]
        a.orders.ShowRefuse(target)
        popup = a.g.WallOfShameForeverOrderRefuse
        popup.edit.SetText(popup.edit, "Plus de cuir|désolé")
        popup.confirm.GetScript(popup.confirm, "OnClick")(popup.confirm)
        self.assertFalse(popup.IsShown(popup))
        self.assertEqual(a.strips[-1].split("|")[11:], ["refused", "Plus de cuir désolé"])
        self.assertEqual(win.total._text, "14 commandes en attente")
        # scope buttons, slash commands, language
        win.scopeAccount.GetScript(win.scopeAccount, "OnClick")(win.scopeAccount)
        self.assertEqual(a.db.ordersScope, "account")
        self.assertTrue(a.db.minimapButton)
        a.g.SlashCmdList.WALLOFSHAMEFOREVER("minimap")
        self.assertFalse(a.db.minimapButton)
        a.g.SlashCmdList.WALLOFSHAMEFOREVER("lang en")
        self.assertEqual(win.title._text, "Orders for Chamy Chan")
        a.g.SlashCmdList.WALLOFSHAMEFOREVER("commandes")
        self.assertFalse(win.IsShown(win))


if __name__ == "__main__":
    unittest.main()


class MaterialsTest(unittest.TestCase):
    """Materials column (v0.6.2): the selected buyer's or the total, "have / needed" from the bags."""

    LEATHER = {"itemId": 2318, "name": "Cuir léger", "qty": 8}
    THREAD = {"itemId": 2320, "name": "Fil grossier", "qty": 2}

    def test_read_and_sum(self):
        a = Addon(orders=[
            order("a", buyer="Liandra", reply="Prête vendredi", reagents=[self.LEATHER, self.THREAD, {"itemId": "x"}]),
            order("b", buyer="Liandra", reagents=[self.LEATHER]),
            order("c", buyer="Grumbar", reagents=[]),
        ]).login()
        pending = a.orders.List("char")
        first = [o for o in pending.values() if o.id == "a"][0]
        self.assertEqual(first.reply, "Prête vendredi")
        self.assertEqual(len(first.reagents), 2)  # the bad entry dropped
        total, unknown = a.orders.Materials(pending)
        self.assertEqual([(m.itemId, m.qty) for m in total.values()], [(2318, 16), (2320, 2)])  # by name
        self.assertFalse(unknown)

    def test_window_buyer_total_and_counts(self):
        a = Addon(orders=[
            order("a", buyer="Liandra", created=1, reagents=[self.LEATHER, self.THREAD]),
            order("b", buyer="Grumbar", created=2, reagents=[self.LEATHER]),
        ]).login()
        a.lua.execute("function GetItemCount(id) return id == 2318 and 10 or 0 end")
        a.orders.Toggle(True)
        win = a.g.WallOfShameForeverOrders
        # Liandra waits the longest: her materials first; 10 leather of 8, 0 thread of 2
        self.assertIn("Liandra", win.matsBuyer.label._text)
        self.assertIn("Il manque 2 objet(s)", win.matsFoot._text)
        win.matsTotal.GetScript(win.matsTotal, "OnClick")(win.matsTotal)
        self.assertIn("Il manque 8 objet(s)", win.matsFoot._text)  # 16 leather for 10, 2 thread
        # a click on Grumbar's header shows his: 8 leather for 10, all there
        header = a.lua.eval("""function(frames, name)
            for _, f in ipairs(frames) do
                local g = rawget(f, "group")
                if g and g.buyer.name == name then return f end
            end
        end""")(a.g.STATE.frames, "Grumbar")
        header._scripts.OnMouseUp(header)
        self.assertIn("Grumbar", win.matsBuyer.label._text)
        self.assertIn("Tout est dans tes sacs", win.matsFoot._text)
        # back to the total; the bags change: the counts follow
        win.matsTotal.GetScript(win.matsTotal, "OnClick")(win.matsTotal)
        a.lua.execute("function GetItemCount(id) return 99 end")
        a.g.Fire("BAG_UPDATE_DELAYED")
        a.g.RunTimers()
        self.assertIn("Tout est dans tes sacs", win.matsFoot._text)

    def test_older_companion(self):
        a = Addon(orders=[order("a")]).login()  # no "reagents": companion older than 0.7.1
        a.orders.Toggle(True)
        win = a.g.WallOfShameForeverOrders
        self.assertIn("Mets à jour le compagnon", win.matsFoot._text)

