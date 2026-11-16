-- Wall of Shame Forever: craft orders
-- Guildmates order crafts on Discord; the companion writes this account's orders into a separate
-- addon, WallOfShameForever_Commandes, read at login (only a /reload brings new ones):
--   WallOfShameForever_Orders = { updated = <unix>, orders = { { id, artisan = "Name-Realm",
--       buyer = { name, realm, class, level }, itemId, itemName, qty, note, createdAt }, ... } }
-- The artisan ticks an order "done" or "refused" in our window; the answer goes to the companion
-- like the other events (strip in real time, outbox on /reload or logout):
--   2|O|id|name|realm|guild|level|class|time|battletag|order|status|reason
--   id: name-realm:O:order:status, status: done or refused, reason: may be empty (at most 80
--   characters, cut further so the payload fits the strip)
-- At login the addon writes orderIdentity (battletag and this account's characters) for the
-- companion, so the bot knows which characters' orders belong to this account.
-- Loaded after WallOfShameForever.lua, which gives ns.L, ns.GetDB, ns.Identity, ns.Clean,
-- ns.AddToOutbox, ns.Print, ns.ClassColored; DeathStrip.lua gives ns.ShowStrip and ns.STRIP_MAX_PAYLOAD.

local ADDON_NAME, ns = ...
local Orders = {}
ns.Orders = Orders

local REASON_MAX = 80     -- characters
local MAX_CHARACTERS = 50 -- orderIdentity.characters: this account's characters, newest first
local STRIP_GAP = 3.5     -- seconds between two strips (one is on screen for 3 seconds)

local function L(...) return ns.L(...) end

-- "Chamy Chan-Realm" -> "Chamy Chan"
local function CharName(full)
    return full:match("^(.+)%-[^%-]*$") or full
end

-------------------------------------------------------------------------------
-- Data: no frames here (tested with lupa, see companion/tests/test_orders.py)
-------------------------------------------------------------------------------

-- This character as the payloads write it: "Name-Realm"
function Orders.Me()
    local name, realm = ns.Identity()
    return name .. "-" .. realm
end

-- orderIdentity: the battletag (the last known one when the game gives none) and this account's
-- characters, the current one first, without duplicates
function Orders.UpdateIdentity(db, me, battleTag)
    local identity = type(db.orderIdentity) == "table" and db.orderIdentity or {}
    db.orderIdentity = identity
    if type(battleTag) == "string" and battleTag ~= "" then
        identity.battletag = battleTag
    elseif type(identity.battletag) ~= "string" then
        identity.battletag = ""
    end
    local characters = { me }
    local seen = { [me:lower()] = true }
    for _, character in ipairs(type(identity.characters) == "table" and identity.characters or {}) do
        if type(character) == "string" and character ~= "" and not seen[character:lower()]
            and #characters < MAX_CHARACTERS then
            seen[character:lower()] = true
            characters[#characters + 1] = character
        end
    end
    identity.characters = characters
    return identity
end

-- The companion's orders, checked one by one: nil when the file is missing, else a list (bad
-- entries skipped)
function Orders.ReadSource(source)
    if type(source) ~= "table" or type(source.orders) ~= "table" then return nil end
    local list = {}
    for _, o in ipairs(source.orders) do
        local idType = type(o) == "table" and type(o.id)
        if (idType == "string" or idType == "number") and type(o.artisan) == "string" then
            local buyer = type(o.buyer) == "table" and o.buyer or {}
            local qty = math.floor(tonumber(o.qty) or 1)
            list[#list + 1] = {
                id = tostring(o.id),
                artisan = o.artisan,
                buyer = {
                    name = tostring(buyer.name or "?"),
                    realm = tostring(buyer.realm or ""),
                    class = type(buyer.class) == "string" and buyer.class:upper() or nil,
                    level = tonumber(buyer.level),
                },
                itemId = tonumber(o.itemId),
                itemName = type(o.itemName) == "string" and o.itemName ~= "" and o.itemName or nil,
                qty = qty > 0 and qty or 1,
                note = type(o.note) == "string" and o.note or "",
                createdAt = tonumber(o.createdAt) or 0,
            }
        end
    end
    return list
end

-- Answered orders stay hidden until the companion's file no longer lists them
function Orders.Prune(handled, list)
    local present = {}
    for _, o in ipairs(list) do present[o.id] = true end
    for id in pairs(handled) do
        if not present[id] then handled[id] = nil end
    end
end

-- Orders still to answer: scope "char" = made to this character, "account" = to any character
-- of the account
function Orders.Pending(list, handled, scope, me, characters)
    local mine = { [me:lower()] = true }
    if scope == "account" then
        for _, character in ipairs(characters or {}) do
            if type(character) == "string" then mine[character:lower()] = true end
        end
    end
    local pending = {}
    for _, o in ipairs(list or {}) do
        if not handled[o.id] and mine[o.artisan:lower()] then pending[#pending + 1] = o end
    end
    return pending
end

local function Older(a, b)
    if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end
    return a.id < b.id
end

-- One group per buyer character, the longest waiting first; orders oldest first
function Orders.Group(pending)
    local groups, byKey = {}, {}
    for _, o in ipairs(pending) do
        local key = (o.buyer.name .. "-" .. o.buyer.realm):lower()
        local group = byKey[key]
        if not group then
            group = { key = key, buyer = o.buyer, orders = {} }
            byKey[key] = group
            groups[#groups + 1] = group
        end
        group.orders[#group.orders + 1] = o
    end
    for _, group in ipairs(groups) do
        table.sort(group.orders, Older)
        group.oldest = group.orders[1].createdAt
    end
    table.sort(groups, function(a, b)
        if a.oldest ~= b.oldest then return a.oldest < b.oldest end
        return a.key < b.key
    end)
    return groups
end

-- Pages of rows within a height: { header = group, continued = true|nil } or { order, group }.
-- A buyer's header always has at least one of its orders under it on the same page; a group
-- going on to the next page repeats its header there. Always at least one (maybe empty) page.
function Orders.Paginate(groups, capacity, headerHeight, itemHeight)
    capacity = math.max(capacity, headerHeight + itemHeight)
    local pages = { {} }
    local page, used = pages[1], 0
    local function NewPage()
        page, used = {}, 0
        pages[#pages + 1] = page
    end
    for _, group in ipairs(groups) do
        if used > 0 and used + headerHeight + itemHeight > capacity then NewPage() end
        page[#page + 1] = { header = group }
        used = used + headerHeight
        for _, o in ipairs(group.orders) do
            if used + itemHeight > capacity then
                NewPage()
                page[#page + 1] = { header = group, continued = true }
                used = headerHeight
            end
            page[#page + 1] = { order = o, group = group }
            used = used + itemHeight
        end
    end
    return pages
end

-- At most max bytes, never in the middle of a UTF-8 character
local function CutBytes(text, max)
    if #text <= max then return text end
    local cut = max
    while cut > 0 do
        local byte = text:byte(cut + 1)
        if byte < 0x80 or byte >= 0xC0 then break end -- the next byte starts a character
        cut = cut - 1
    end
    return text:sub(1, cut)
end

local function CutChars(text, max)
    local count, i = 0, 1
    while i <= #text do
        count = count + 1
        if count > max then return text:sub(1, i - 1) end
        local byte = text:byte(i)
        i = i + (byte >= 0xF0 and 4 or byte >= 0xE0 and 3 or byte >= 0xC0 and 2 or 1)
    end
    return text
end

-- Reason typed by the artisan: no payload separators, one line, at most 80 characters
function Orders.CleanReason(reason)
    local text = ns.Clean(reason):gsub("%c", " "):gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$")
    return CutChars(text, REASON_MAX)
end

-- The answer for the companion; the reason is cut so the payload fits the strip
function Orders.Payload(orderId, status, reason)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    orderId = tostring(orderId):gsub("[|%c]", "")
    local base = table.concat({ "2", "O", name .. "-" .. realm .. ":O:" .. orderId .. ":" .. status, name, realm,
        guild, UnitLevel("player"), classFile or "", time(), battleTag, orderId, status }, "|") .. "|"
    local room = (ns.STRIP_MAX_PAYLOAD or 240) - #base
    return base .. CutBytes(Orders.CleanReason(reason), math.max(0, room))
end

-- "2 h ago"
function Orders.Age(now, at)
    local diff = math.max(0, (now or 0) - (at or 0))
    if diff < 60 then return L("orders_age_now") end
    if diff < 3600 then return L("orders_age_min", math.floor(diff / 60)) end
    if diff < 86400 then return L("orders_age_hours", math.floor(diff / 3600)) end
    return L("orders_age_days", math.floor(diff / 86400))
end

-------------------------------------------------------------------------------
-- State, read at login
-------------------------------------------------------------------------------

local db
local source         -- list from the companion's file, nil when it is missing
local me = "?"
local itemWaiting = {} -- item ids asked to the server, shown as soon as they arrive
local Refresh, UpdateBadge -- window and minimap button, below

local function Characters()
    return db and type(db.orderIdentity) == "table" and db.orderIdentity.characters or {}
end

function Orders.List(scope)
    if not db then return {} end
    return Orders.Pending(source, db.ordersHandled, scope, me, Characters())
end

-- Strips one after the other, so two answers clicked quickly both reach the companion
local stripQueue, stripBusy = {}, false
local function NextStrip()
    local payload = table.remove(stripQueue, 1)
    if not payload then
        stripBusy = false
        return
    end
    stripBusy = true
    if ns.ShowStrip then ns.ShowStrip(payload) end
    C_Timer.After(STRIP_GAP, NextStrip)
end

local function QueueStrip(payload)
    stripQueue[#stripQueue + 1] = payload
    if not stripBusy then NextStrip() end
end

-- The artisan's answer: hidden from now on, sent to the companion
function Orders.Mark(order, status, reason)
    if not db or db.ordersHandled[order.id] then return nil end
    db.ordersHandled[order.id] = status
    local payload = Orders.Payload(order.id, status, reason)
    ns.AddToOutbox(payload)
    QueueStrip(payload)
    local what = (order.displayName or order.itemName or "?") .. " \195\151" .. order.qty .. " - " .. order.buyer.name
    ns.Print(L(status == "done" and "orders_marked_done" or "orders_marked_refused", what))
    Refresh()
    UpdateBadge()
    return payload
end

-------------------------------------------------------------------------------
-- Look: dark, gold border (built-in game textures only)
-------------------------------------------------------------------------------

local GOLD = { 0.90, 0.75, 0.28, 1 }
local DIM_GOLD = { 0.90, 0.75, 0.28, 0.45 }
local GREY = { 0.45, 0.45, 0.45, 1 }
local GREEN = { 0.30, 0.80, 0.30, 1 }
local RED = { 0.85, 0.25, 0.20, 1 }
local BG = { 0.045, 0.035, 0.025, 0.97 }
local LIST_BG = { 0.012, 0.010, 0.008, 0.88 }
local BUTTON_BG = { 0.07, 0.06, 0.04, 0.95 }
local ACTIVE_BG = { 0.32, 0.24, 0.07, 0.95 } -- selected "this character / all" button
local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local ICON = "Interface\\Icons\\Trade_BlackSmithing"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "
local ICON_REFUSE = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t "
local TITLE_FONT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\LilitaOne.ttf"

local WIDTH, HEIGHT = 480, 560
local HEADER_H, ITEM_H = 28, 46
local LIST_TOP, LIST_BOTTOM = 98, 46 -- list area inside the window
local CAPACITY = HEIGHT - LIST_TOP - LIST_BOTTOM - 12
local ROW_W = WIDTH - 24 - 12 -- list width minus its padding
local BTN_DONE_W, BTN_REFUSE_W = 74, 84
local NAME_W = ROW_W - 60 - BTN_DONE_W - BTN_REFUSE_W - 22

local function Backdrop(frame, bg, border, edgeSize)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = EDGE, tile = true, tileSize = 8, edgeSize = edgeSize or 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function Line(parent, layer, color)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
    tex:SetHeight(1)
    return tex
end

local function ClickSound()
    if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
end

-- Dark button with a colored border, brighter under the mouse
local function MakeButton(parent, width, color, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 22)
    Backdrop(b, BUTTON_BG, color, 12)
    b.color = color
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER", 0, 0)
    b:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(self.color[1] * 0.35, self.color[2] * 0.35, self.color[3] * 0.35, 0.95)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            local bg = self.active and ACTIVE_BG or BUTTON_BG
            self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        end
    end)
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", function(self)
        ClickSound()
        onClick(self)
    end)
    return b
end

-- Item name, quality and icon; an item the client has not seen yet is asked to the server and
-- the window refreshes when it arrives (GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT)
local function ItemInfo(itemId)
    if not itemId then return nil, nil, nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, quality, icon
    if getInfo then
        local ok, n, _, q, _, _, _, _, _, _, t = pcall(getInfo, itemId)
        if ok then name, quality, icon = n, q, t end
    end
    if not icon then
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        if getIcon then
            local ok, t = pcall(getIcon, itemId)
            if ok then icon = t end
        end
    end
    if not quality and C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, itemId)
        if ok then quality = q end
    end
    if not name then
        itemWaiting[itemId] = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemId) end
    end
    return name, quality, icon
end

local function QualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    if quality and GetItemQualityColor then
        local r, g, b = GetItemQualityColor(quality)
        if r then return r, g, b end
    end
    return 0.85, 0.85, 0.85
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------

local win, popup
local headerRows, itemRows = {}, {}
local state = { page = 1 }
Orders.ui = state -- for the tests

local function Scope()
    return db and db.ordersScope == "account" and "account" or "char"
end

local function NewHeaderRow()
    local r = CreateFrame("Frame", nil, win.list)
    r:SetHeight(HEADER_H)
    r.bar = r:CreateTexture(nil, "BACKGROUND")
    r.bar:SetAllPoints()
    r.bar:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    r.bar:SetBlendMode("ADD")
    r.line = Line(r, "ARTWORK", DIM_GOLD)
    r.line:SetPoint("BOTTOMLEFT", 4, 0)
    r.line:SetPoint("BOTTOMRIGHT", -4, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("LEFT", 10, 0)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.info:SetTextColor(0.7, 0.7, 0.7)
    r.age = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.age:SetPoint("RIGHT", -10, 0)
    return r
end

local function ShowItemTooltip(row)
    local o = row.order
    if not o then return end
    GameTooltip:SetOwner(row.iconFrame, "ANCHOR_RIGHT")
    local shown = false
    if o.itemId and GameTooltip.SetItemByID then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, o.itemId)
    end
    if not shown then GameTooltip:SetText(row.itemName or "?") end
    if o.note ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("orders_note"), GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(o.note, 0.85, 0.85, 0.85, true)
    end
    GameTooltip:Show()
end

local ShowRefuse -- popup, below

local function NewItemRow()
    local r = CreateFrame("Frame", nil, win.list)
    r:SetHeight(ITEM_H)
    r:EnableMouse(true)
    r.shade = r:CreateTexture(nil, "BACKGROUND")
    r.shade:SetAllPoints()
    r.hover = r:CreateTexture(nil, "BORDER")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
    r.hover:Hide()

    r.iconFrame = CreateFrame("Frame", nil, r)
    r.iconFrame:SetSize(34, 34)
    r.iconFrame:SetPoint("LEFT", 18, 0)
    r.icon = r.iconFrame:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT", 1, -1)
    r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.border = r.iconFrame:CreateTexture(nil, "OVERLAY")
    r.border:SetAllPoints()
    r.border:SetTexture("Interface\\Common\\WhiteIconFrame")

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetWidth(NAME_W)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.note:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.note:SetWidth(NAME_W)
    r.note:SetJustifyH("LEFT")
    r.note:SetWordWrap(false)
    r.note:SetTextColor(0.62, 0.62, 0.62)

    r.refuse = MakeButton(r, BTN_REFUSE_W, RED, function(self) ShowRefuse(self:GetParent().order) end)
    r.refuse:SetPoint("RIGHT", -8, 0)
    r.done = MakeButton(r, BTN_DONE_W, GREEN, function(self) Orders.Mark(self:GetParent().order, "done", "") end)
    r.done:SetPoint("RIGHT", r.refuse, "LEFT", -6, 0)

    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        ShowItemTooltip(self)
    end)
    r:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    return r
end

local function FillHeader(r, entry)
    local buyer = entry.header.buyer
    r.bar:SetVertexColor(1, 1, 1, 0.35)
    local c = buyer.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[buyer.class]
    if c then r.bar:SetVertexColor(c.r, c.g, c.b, 0.45) end
    r.name:SetText(ns.ClassColored(buyer.name, buyer.class))
    local info = buyer.level and L("orders_level", buyer.level) or ""
    if entry.continued then info = info .. "  " .. L("orders_continued") end
    r.info:SetText(info)
    r.age:SetText(Orders.Age(time(), entry.header.oldest))
end

local function FillItem(r, entry, index)
    local o = entry.order
    r.order = o
    local name, quality, icon = ItemInfo(o.itemId)
    name = name or o.itemName or L("orders_unknown_item", o.itemId or "?")
    r.itemName = name
    o.displayName = name
    r.shade:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.035 or 0.0)
    r.icon:SetTexture(icon or UNKNOWN_ICON)
    local qr, qg, qb = QualityColor(quality)
    r.border:SetVertexColor(qr, qg, qb)
    r.name:SetTextColor(qr, qg, qb)
    r.name:SetText(name .. "  |cffffffff\195\151" .. o.qty .. "|r")
    local note = o.note ~= "" and ("\194\171 " .. o.note .. " \194\187") or ""
    if Scope() == "account" and o.artisan:lower() ~= me:lower() then
        local artisan = "|cff8f8f8f" .. L("orders_for", CharName(o.artisan)) .. "|r"
        note = note ~= "" and (artisan .. "  " .. note) or artisan
    end
    r.note:SetText(note)
    r.name:ClearAllPoints()
    if note ~= "" then
        r.name:SetPoint("TOPLEFT", r.iconFrame, "TOPRIGHT", 10, -2)
    else
        r.name:SetPoint("LEFT", r.iconFrame, "RIGHT", 10, 0)
    end
    r.done.label:SetText(ICON_READY .. L("orders_done"))
    r.refuse.label:SetText(ICON_REFUSE .. L("orders_refuse"))
end

local function SetScopeButton(b, active)
    b.active = active
    local border = active and GOLD or GREY
    if b.SetBackdropBorderColor then b:SetBackdropBorderColor(border[1], border[2], border[3], border[4]) end
    local bg = active and ACTIVE_BG or BUTTON_BG
    if b.SetBackdropColor then b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if active then b.label:SetTextColor(1, 0.92, 0.6) else b.label:SetTextColor(0.6, 0.6, 0.6) end
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    win.title:SetText(L("orders_title", CharName(me)))
    win.scopeChar.label:SetText(L("orders_scope_char"))
    win.scopeAccount.label:SetText(L("orders_scope_account"))
    SetScopeButton(win.scopeChar, Scope() == "char")
    SetScopeButton(win.scopeAccount, Scope() == "account")

    local pending = Orders.List(Scope())
    local pages = Orders.Paginate(Orders.Group(pending), CAPACITY, HEADER_H, ITEM_H)
    state.pages = pages
    state.page = math.max(1, math.min(state.page, #pages))

    for _, r in ipairs(headerRows) do r:Hide() end
    for _, r in ipairs(itemRows) do r:Hide() end
    local y, headers, items = 6, 0, 0
    for _, entry in ipairs(pages[state.page]) do
        local r, height
        if entry.header then
            headers = headers + 1
            r = headerRows[headers] or NewHeaderRow()
            headerRows[headers] = r
            FillHeader(r, entry)
            height = HEADER_H
        else
            items = items + 1
            r = itemRows[items] or NewItemRow()
            itemRows[items] = r
            FillItem(r, entry, items)
            height = ITEM_H
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", win.list, "TOPLEFT", 6, -y)
        r:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", -6, -y)
        r:Show()
        y = y + height
    end

    if #pending == 0 then
        win.empty.text:SetText(L("orders_empty"))
        win.empty.hint:SetText(L(source and "orders_empty_hint" or "orders_no_file"))
        win.empty:Show()
    else
        win.empty:Hide()
    end
    win.total:SetText(L(#pending == 1 and "orders_count_one" or "orders_count", #pending))
    win.pageText:SetText(L("orders_page", state.page, #pages))
    if state.page > 1 then win.prev:Enable() else win.prev:Disable() end
    if state.page < #pages then win.next:Enable() else win.next:Disable() end
end

local function CreateWindow()
    win = CreateFrame("Frame", "WallOfShameForeverOrders", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    Backdrop(win, BG, GOLD, 16)
    tinsert(UISpecialFrames, "WallOfShameForeverOrders") -- closes with Escape

    -- title band: icon in a gold frame, title, addon name
    local band = win:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", 4, -4)
    band:SetPoint("TOPRIGHT", -4, -4)
    band:SetHeight(56)
    band:SetColorTexture(0.13, 0.095, 0.04, 0.85)
    local bandLine = Line(win, "ARTWORK", GOLD)
    bandLine:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    bandLine:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)

    local iconFrame = CreateFrame("Frame", nil, win)
    iconFrame:SetSize(40, 40)
    iconFrame:SetPoint("TOPLEFT", 14, -12)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local iconBorder = iconFrame:CreateTexture(nil, "OVERLAY")
    iconBorder:SetAllPoints()
    iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    iconBorder:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

    win.title = win:CreateFontString(nil, "OVERLAY")
    if not win.title:SetFont(TITLE_FONT, 20, "OUTLINE") then
        win.title:SetFontObject("GameFontNormalLarge") -- fallback if the font is missing
    end
    win.title:SetTextColor(1, 0.84, 0.4)
    win.title:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 12, -1)
    win.title:SetWidth(WIDTH - 120)
    win.title:SetJustifyH("LEFT")
    win.title:SetWordWrap(false)
    local sub = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Wall of Shame Forever")

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- this character / all my characters
    local function SetScope(scope)
        db.ordersScope = scope
        state.page = 1
        Refresh()
    end
    win.scopeChar = MakeButton(win, 150, GREY, function() SetScope("char") end)
    win.scopeChar:SetPoint("TOPLEFT", 14, -68)
    win.scopeAccount = MakeButton(win, 150, GREY, function() SetScope("account") end)
    win.scopeAccount:SetPoint("LEFT", win.scopeChar, "RIGHT", 6, 0)

    -- list
    win.list = CreateFrame("Frame", nil, win, "BackdropTemplate")
    win.list:SetPoint("TOPLEFT", 12, -LIST_TOP)
    win.list:SetPoint("BOTTOMRIGHT", -12, LIST_BOTTOM)
    Backdrop(win.list, LIST_BG, DIM_GOLD, 12)

    win.empty = CreateFrame("Frame", nil, win.list)
    win.empty:SetSize(360, 140)
    win.empty:SetPoint("CENTER", 0, 20)
    local emptyIcon = win.empty:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetSize(52, 52)
    emptyIcon:SetPoint("TOP", 0, 0)
    emptyIcon:SetTexture(ICON)
    emptyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    emptyIcon:SetDesaturated(true)
    emptyIcon:SetAlpha(0.6)
    win.empty.text = win.empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.empty.text:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -12)
    win.empty.text:SetTextColor(0.75, 0.68, 0.5)
    win.empty.hint = win.empty:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty.hint:SetPoint("TOP", win.empty.text, "BOTTOM", 0, -8)
    win.empty.hint:SetWidth(340)

    -- footer: total, pages
    local footLine = Line(win, "ARTWORK", DIM_GOLD)
    footLine:SetPoint("BOTTOMLEFT", 12, LIST_BOTTOM - 4)
    footLine:SetPoint("BOTTOMRIGHT", -12, LIST_BOTTOM - 4)
    win.total = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.total:SetPoint("BOTTOMLEFT", 18, 17)
    local function PageButton(direction)
        local b = CreateFrame("Button", nil, win)
        b:SetSize(26, 26)
        local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
        b:SetNormalTexture(base .. "Up")
        b:SetPushedTexture(base .. "Down")
        b:SetDisabledTexture(base .. "Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        return b
    end
    win.next = PageButton("Next")
    win.next:SetPoint("BOTTOMRIGHT", -14, 10)
    win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.pageText:SetPoint("RIGHT", win.next, "LEFT", -6, 0)
    win.prev = PageButton("Prev")
    win.prev:SetPoint("RIGHT", win.pageText, "LEFT", -6, 0)
    win.next:SetScript("OnClick", function()
        ClickSound()
        state.page = state.page + 1
        Refresh()
    end)
    win.prev:SetScript("OnClick", function()
        ClickSound()
        state.page = state.page - 1
        Refresh()
    end)

    win:SetScript("OnShow", Refresh)
    win:SetScript("OnHide", function()
        if popup then popup:Hide() end
    end)
    win:Hide()
end

function Orders.Toggle(show)
    if not db then return end
    if not win then CreateWindow() end
    if show == nil then show = not win:IsShown() end
    if show then win:Show() else win:Hide() end
end
ns.ToggleOrders = Orders.Toggle
ns.RefreshOrders = function() Refresh() end

-------------------------------------------------------------------------------
-- Refuse: optional reason
-------------------------------------------------------------------------------

local function CreatePopup()
    popup = CreateFrame("Frame", "WallOfShameForeverOrderRefuse", UIParent, "BackdropTemplate")
    popup:SetSize(360, 168)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetToplevel(true)
    popup:EnableMouse(true)
    Backdrop(popup, BG, GOLD, 16)
    tinsert(UISpecialFrames, "WallOfShameForeverOrderRefuse")

    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup.title:SetPoint("TOP", 0, -16)
    popup.item = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    popup.item:SetPoint("TOP", popup.title, "BOTTOM", 0, -8)
    popup.item:SetWidth(320)
    popup.item:SetWordWrap(false)
    popup.label = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    popup.label:SetPoint("TOPLEFT", 26, -70)
    popup.label:SetTextColor(0.75, 0.75, 0.75)

    popup.edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    popup.edit:SetSize(304, 22)
    popup.edit:SetPoint("TOPLEFT", 30, -86)
    popup.edit:SetAutoFocus(false)
    popup.edit:SetMaxLetters(REASON_MAX)
    popup.count = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.count:SetPoint("TOPRIGHT", popup.edit, "BOTTOMRIGHT", 0, -2)

    local function Confirm()
        local order = popup.order
        local reason = popup.edit:GetText()
        popup:Hide()
        if order then Orders.Mark(order, "refused", reason) end
    end
    popup.edit:SetScript("OnEnterPressed", Confirm)
    popup.edit:SetScript("OnEscapePressed", function() popup:Hide() end)
    popup.edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local _, chars = text:gsub("[^\128-\191]", "")
        popup.count:SetText(chars .. "/" .. REASON_MAX)
    end)

    popup.confirm = MakeButton(popup, 130, RED, Confirm)
    popup.confirm:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
    popup.cancel = MakeButton(popup, 130, GREY, function() popup:Hide() end)
    popup.cancel:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)

    popup:SetScript("OnHide", function()
        popup.order = nil
        popup.edit:ClearFocus()
    end)
    popup:Hide()
end

ShowRefuse = function(order)
    if not order then return end
    if not popup then CreatePopup() end
    popup.order = order
    popup:ClearAllPoints()
    popup:SetPoint("CENTER", win or UIParent, "CENTER", 0, 0)
    popup.title:SetText(L("orders_refuse_title"))
    local name = ItemInfo(order.itemId) or order.itemName or L("orders_unknown_item", order.itemId or "?")
    popup.item:SetText(name .. " \195\151" .. order.qty .. "  |cff8f8f8f-|r  "
        .. ns.ClassColored(order.buyer.name, order.buyer.class))
    popup.label:SetText(L("orders_refuse_reason"))
    popup.confirm.label:SetText(ICON_REFUSE .. L("orders_confirm"))
    popup.cancel.label:SetText(L("orders_cancel"))
    popup.edit:SetText("")
    popup.count:SetText("0/" .. REASON_MAX)
    popup:Show()
    popup.edit:SetFocus()
end
Orders.ShowRefuse = function(order) ShowRefuse(order) end

-------------------------------------------------------------------------------
-- Minimap button: on the rim, dragged around it (angle saved), count badge
-------------------------------------------------------------------------------

local minimapButton
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function PlaceMinimapButton()
    if not (minimapButton and Minimap) then return end
    local radius = math.min(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140) / 2 + 5
    local angle = math.rad(tonumber(db.minimapAngle) or 215)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

UpdateBadge = function()
    if not minimapButton then return end
    local count = #Orders.List("account")
    if count > 0 then
        minimapButton.badgeText:SetText(count > 9 and "9+" or tostring(count))
        minimapButton.badge:Show()
    else
        minimapButton.badge:Hide()
    end
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "WallOfShameForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- red disc with the number of pending orders of the account
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(16, 16)
    b.badge:SetPoint("TOPRIGHT", 2, 1)
    b.badge:SetFrameLevel(b:GetFrameLevel() + 2)
    local disc = b.badge:CreateTexture(nil, "ARTWORK")
    disc:SetAllPoints()
    disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    disc:SetVertexColor(0.75, 0.1, 0.08)
    local ring = b.badge:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", 1, -1)
    ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    b.badgeText = b.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.badgeText:SetPoint("CENTER", 0, 0)
    b.badge:Hide()

    b:SetScript("OnClick", function() Orders.Toggle() end)
    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            db.minimapAngle = math.deg(atan2(py / scale - my, px / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L("minimap_title"), GOLD[1], GOLD[2], GOLD[3])
        local count = #Orders.List("account")
        GameTooltip:AddLine(L(count == 1 and "orders_count_one" or "orders_count", count), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("minimap_click"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L("minimap_drag"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L("minimap_hide"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton = b
    PlaceMinimapButton()
    UpdateBadge()
end

local function ApplyMinimapButton()
    if db.minimapButton then
        CreateMinimapButton()
        if minimapButton then minimapButton:Show() end
    elseif minimapButton then
        minimapButton:Hide()
    end
end

function Orders.ToggleMinimapButton()
    if not db then return end
    db.minimapButton = not db.minimapButton
    ApplyMinimapButton()
    ns.Print(L("minimap_set", L(db.minimapButton and "on" or "off")))
end
ns.ToggleMinimapButton = Orders.ToggleMinimapButton

-------------------------------------------------------------------------------
-- Login notification: toast in the same style, a sound and one chat line
-------------------------------------------------------------------------------

local TOAST_IN, TOAST_HOLD, TOAST_OUT = 0.4, 7, 0.8
local toast

local function CreateToast()
    toast = CreateFrame("Button", "WallOfShameForeverOrdersToast", UIParent, "BackdropTemplate")
    toast:SetSize(320, 62)
    toast:SetPoint("TOP", 0, -170)
    toast:SetFrameStrata("DIALOG")
    toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Backdrop(toast, BG, GOLD, 16)
    local iconFrame = CreateFrame("Frame", nil, toast)
    iconFrame:SetSize(40, 40)
    iconFrame:SetPoint("LEFT", 12, 0)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = iconFrame:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    border:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toast.title:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 10, -3)
    toast.title:SetTextColor(1, 0.84, 0.4)
    toast.hint = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toast.hint:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -5)
    toast.hint:SetTextColor(0.8, 0.8, 0.8)
    toast:SetScript("OnClick", function(self, button)
        self:Hide()
        if button == "LeftButton" then Orders.Toggle(true) end
    end)
    toast:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() then self.t = math.min(self.t, TOAST_IN) end -- stays while hovered
        self.t = self.t + elapsed
        local t = self.t
        if t < TOAST_IN then
            self:SetAlpha(t / TOAST_IN)
        elseif t < TOAST_IN + TOAST_HOLD then
            self:SetAlpha(1)
        elseif t < TOAST_IN + TOAST_HOLD + TOAST_OUT then
            self:SetAlpha(1 - (t - TOAST_IN - TOAST_HOLD) / TOAST_OUT)
        else
            self:Hide()
        end
    end)
    toast:Hide()
end

function Orders.Notify()
    local count = #Orders.List("account")
    if count == 0 then return 0 end
    local text = L(count == 1 and "orders_count_one" or "orders_count", count)
    ns.Print(L("orders_chat", text))
    if not toast then CreateToast() end
    toast.title:SetText(text)
    toast.hint:SetText(L("orders_toast_hint"))
    toast.t = 0
    toast:SetAlpha(0)
    toast:Show()
    if db.sound and PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 618, "SFX")
    end
    return count
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local refreshPending
local function RefreshSoon() -- item data arrives in bursts: one refresh for all of them
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.2, function()
        refreshPending = nil
        Refresh()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, itemId)
    if event == "PLAYER_LOGIN" then
        db = ns.GetDB and ns.GetDB()
        if not db then return end
        if db.minimapButton == nil then db.minimapButton = true end
        if type(db.ordersHandled) ~= "table" then db.ordersHandled = {} end
        me = Orders.Me()
        local _, _, _, battleTag = ns.Identity()
        Orders.UpdateIdentity(db, me, battleTag)
        -- the companion's file, a separate addon loaded before PLAYER_LOGIN (may be missing)
        source = Orders.ReadSource(_G.WallOfShameForever_Orders)
        if source then Orders.Prune(db.ordersHandled, source) end
        ApplyMinimapButton()
        C_Timer.After(8, Orders.Notify) -- after the loading screen and the login chat lines
    elseif itemId and itemWaiting[itemId] then
        itemWaiting[itemId] = nil
        RefreshSoon()
    end
end)
