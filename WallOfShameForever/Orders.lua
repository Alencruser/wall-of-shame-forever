-- Wall of Shame Forever: craft orders
-- Guildmates order crafts on Discord; the companion writes this account's orders into a separate
-- addon, WallOfShameForever_Commandes, read at login (only a /reload brings new ones):
--   WallOfShameForever_Orders = { updated = <unix>, orders = { { id, artisan = "Name-Realm",
--       buyer = { name, realm, class, level }, itemId, itemName, qty, note, createdAt,
--       reply, reagents = { { itemId, name, qty }, ... } }, ... } }
--   reply and reagents: companion 0.7.1 and later (reagents: the materials of the whole order)
--   placed (companion 0.7.2 and later): the player's own orders as a buyer, see Orders.ReadPlaced
-- The artisan ticks an order "done" or "refused" in our window; the answer goes to the companion
-- like the other events (strip in real time, outbox on /reload or logout):
--   2|O|id|name|realm|guild|level|class|time|battletag|order|status|reason
--   id: name-realm:O:order:status, status: done or refused, reason: may be empty (at most 80
--   characters, cut further so the payload fits the strip)
-- The buyer confirms in "My orders" that a done order reached them: same event, status received
-- (companion 0.7.8 and later passes it; the bot checks the sender is the buyer).
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

-- The key of a character for comparisons: its name only, lower case. On Forever the realm changes
-- (CAMWOWEU5Realm2PvP, another number another day) or is empty; the bot keys characters by name too.
local function CharKey(full)
    return CharName(tostring(full or "")):lower()
end
Orders.CharKey = CharKey

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

-- Materials of a whole order: nil = a companion older than 0.7.1 (it does not pass them), {} = the
-- bot does not know the recipe
local function ReadReagents(raw)
    if type(raw) ~= "table" then return nil end
    local reagents = {}
    for _, r in ipairs(raw) do
        local id = type(r) == "table" and tonumber(r.itemId)
        local count = type(r) == "table" and tonumber(r.qty)
        if id and count and count > 0 then
            reagents[#reagents + 1] = { itemId = id, qty = math.floor(count),
                name = type(r.name) == "string" and r.name ~= "" and r.name or nil }
        end
    end
    return reagents
end

local function ValidId(o)
    local idType = type(o) == "table" and type(o.id)
    return idType == "string" or idType == "number"
end

-- The companion's orders, checked one by one: nil when the file is missing, else a list (bad
-- entries skipped)
function Orders.ReadSource(source)
    if type(source) ~= "table" or type(source.orders) ~= "table" then return nil end
    local list = {}
    for _, o in ipairs(source.orders) do
        if ValidId(o) and type(o.artisan) == "string" then
            local buyer = type(o.buyer) == "table" and o.buyer or {}
            local qty = math.floor(tonumber(o.qty) or 1)
            local reagents = ReadReagents(o.reagents)
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
                reply = type(o.reply) == "string" and o.reply or "",
                reagents = reagents,
                createdAt = tonumber(o.createdAt) or 0,
            }
        end
    end
    return list
end

local PLACED_STATUS = { pending = true, done = true, refused = true }

-- The player's own orders as a buyer ("My orders" tab): nil when the companion does not write them
-- (older than 0.7.2), else a list. status: pending, done or refused (done: until received, then 7
-- days; refused: 7 days). receivedAt: 0 = done but not received yet, nil = companion older than 0.7.8
function Orders.ReadPlaced(source)
    if type(source) ~= "table" or type(source.placed) ~= "table" then return nil end
    local list = {}
    for _, o in ipairs(source.placed) do
        if ValidId(o) and type(o.artisan) == "string" and PLACED_STATUS[o.status] then
            local qty = math.floor(tonumber(o.qty) or 1)
            list[#list + 1] = {
                id = tostring(o.id),
                artisan = o.artisan,
                artisanClass = type(o.artisanClass) == "string" and o.artisanClass:upper() or nil,
                buyer = type(o.buyer) == "string" and o.buyer or "",
                status = o.status,
                reason = type(o.reason) == "string" and o.reason or "",
                itemId = tonumber(o.itemId),
                itemName = type(o.itemName) == "string" and o.itemName ~= "" and o.itemName or nil,
                qty = qty > 0 and qty or 1,
                note = type(o.note) == "string" and o.note or "",
                reply = type(o.reply) == "string" and o.reply or "",
                reagents = ReadReagents(o.reagents),
                createdAt = tonumber(o.createdAt) or 0,
                updatedAt = tonumber(o.updatedAt) or tonumber(o.createdAt) or 0,
                receivedAt = tonumber(o.receivedAt),
            }
        end
    end
    return list
end

-- Materials of these orders added up: { { itemId, name, qty } } by name; unknown = true when an
-- order came without its materials (companion older than 0.7.1). An order already done or refused
-- (buyer side) needs nothing any more.
function Orders.Materials(orders)
    local list, byId, unknown = {}, {}, false
    for _, o in ipairs(orders or {}) do
        if o.status and o.status ~= "pending" then
            -- nothing to gather
        elseif type(o.reagents) ~= "table" then
            unknown = true
        else
            for _, r in ipairs(o.reagents) do
                local m = byId[r.itemId]
                if not m then
                    m = { itemId = r.itemId, name = r.name, qty = 0 }
                    byId[r.itemId] = m
                    list[#list + 1] = m
                end
                m.qty = m.qty + r.qty
            end
        end
    end
    table.sort(list, function(a, b)
        local an, bn = a.name or "", b.name or ""
        if an ~= bn then return an < bn end
        return a.itemId < b.itemId
    end)
    return list, unknown
end

-- How many of an item the player has, bags and bank (the bank as last seen)
function Orders.Owned(itemId)
    if not GetItemCount then return 0 end
    local ok, count = pcall(GetItemCount, itemId, true)
    return ok and tonumber(count) or 0
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
    local mine = { [CharKey(me)] = true }
    if scope == "account" then
        for _, character in ipairs(characters or {}) do
            if type(character) == "string" then mine[CharKey(character)] = true end
        end
    end
    local pending = {}
    for _, o in ipairs(list or {}) do
        if not handled[o.id] and mine[CharKey(o.artisan)] then pending[#pending + 1] = o end
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
        local key = CharKey(o.buyer.name .. "-")
        local group = byKey[key]
        if not group then
            -- label, class: the name on the materials button (both tabs)
            group = { key = key, buyer = o.buyer, label = o.buyer.name, class = o.buyer.class, orders = {} }
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

-- "My orders" tab: one group per artisan. Orders still pending first (oldest first), then the done
-- and refused ones (latest first); artisans with something pending first.
function Orders.GroupPlaced(placed)
    local groups, byKey = {}, {}
    for _, o in ipairs(placed or {}) do
        local key = CharKey(o.artisan)
        local group = byKey[key]
        if not group then
            group = { key = key, artisan = o.artisan, label = CharName(o.artisan), class = o.artisanClass,
                orders = {}, pending = 0 }
            byKey[key] = group
            groups[#groups + 1] = group
        end
        group.orders[#group.orders + 1] = o
        if o.status == "pending" then group.pending = group.pending + 1 end
    end
    for _, group in ipairs(groups) do
        table.sort(group.orders, function(a, b)
            local ap, bp = a.status == "pending", b.status == "pending"
            if ap ~= bp then return ap end
            if ap then return Older(a, b) end
            if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
            return a.id < b.id
        end)
        group.oldest = group.orders[1].createdAt
        group.latest = 0
        for _, o in ipairs(group.orders) do group.latest = math.max(group.latest, o.updatedAt) end
    end
    table.sort(groups, function(a, b)
        if (a.pending > 0) ~= (b.pending > 0) then return a.pending > 0 end
        if a.pending > 0 and a.oldest ~= b.oldest then return a.oldest < b.oldest end
        if a.pending == 0 and a.latest ~= b.latest then return a.latest > b.latest end
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
local placedSource   -- the player's own orders (buyer side), nil before companion 0.7.2
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

-- "My orders" tab: the player's own orders (nil before companion 0.7.2)
function Orders.Placed()
    return placedSource
end

-- A done order the buyer can still confirm: the companion says it is not received (receivedAt 0) and
-- the button was not clicked since the file was written
function Orders.CanReceive(o, received)
    return o.status == "done" and o.receivedAt == 0 and not (received and received[o.id])
end

-- Puts this item's name in the auction house search and runs it, when the auction house is open
-- (the classic one, or the newer one). True when a search was started.
function Orders.AuctionOpen()
    return (AuctionFrame and AuctionFrame:IsShown())
        or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or false
end

function Orders.SearchAuction(name)
    if type(name) ~= "string" or name == "" then return false end
    if AuctionFrame and AuctionFrame:IsShown() and BrowseName then
        if AuctionFrameTab1 and AuctionFrameTab_OnClick and PanelTemplates_GetSelectedTab
            and PanelTemplates_GetSelectedTab(AuctionFrame) ~= 1 then
            pcall(AuctionFrameTab_OnClick, AuctionFrameTab1, "LeftButton", false, 1) -- the Browse tab
        end
        BrowseName:SetText(name)
        if AuctionFrameBrowse_Search then
            pcall(AuctionFrameBrowse_Search)
        elseif BrowseSearchButton then
            BrowseSearchButton:Click()
        end
        return true
    end
    local ah = AuctionHouseFrame
    if ah and ah:IsShown() and ah.SearchBar then
        if ah.SearchBar.SearchBox then ah.SearchBar.SearchBox:SetText(name) end
        if ah.SearchBar.StartSearch then pcall(ah.SearchBar.StartSearch, ah.SearchBar) end
        return true
    end
    return false
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
ns.QueueStrip = QueueStrip -- the item requests share the queue (Requests.lua)

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

-- The buyer has the item: received, sent to the companion; the button goes until the next file
-- A pending order of mine I no longer want (« My orders » tab, addon 0.8.0): cancelled on the bot through
-- the companion; shown cancelled here at once (db.ordersCancelled, until the next file)
function Orders.CanCancel(o, cancelled)
    return o.status == "pending" and not (cancelled and cancelled[o.id])
end

function Orders.CancelPlaced(order)
    if not db or not Orders.CanCancel(order, db.ordersCancelled) then return nil end
    db.ordersCancelled[order.id] = time()
    local payload = Orders.Payload(order.id, "cancelled", "")
    ns.AddToOutbox(payload)
    QueueStrip(payload)
    ns.Print(L("orders_marked_cancelled", (order.displayName or order.itemName or "?") .. " \195\151" .. order.qty))
    Refresh()
    return payload
end

-- « Annuler » asks first (a click too fast costs nothing)
local function AskCancel(order)
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
        return Orders.CancelPlaced(order)
    end
    StaticPopupDialogs.WOS_CANCEL_ORDER = StaticPopupDialogs.WOS_CANCEL_ORDER or {
        button1 = YES or "Oui", button2 = NO or "Non", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data) Orders.CancelPlaced(data) end,
    }
    StaticPopupDialogs.WOS_CANCEL_ORDER.text = L("orders_cancel_confirm")
    StaticPopup_Show("WOS_CANCEL_ORDER", (order.displayName or order.itemName or "?") .. " \195\151" .. order.qty, nil, order)
end

function Orders.MarkReceived(order)
    if not db or not Orders.CanReceive(order, db.ordersReceived) then return nil end
    db.ordersReceived[order.id] = time()
    local payload = Orders.Payload(order.id, "received", "")
    ns.AddToOutbox(payload)
    QueueStrip(payload)
    ns.Print(L("orders_marked_received", (order.displayName or order.itemName or "?") .. " \195\151" .. order.qty))
    Refresh()
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
-- the guild's logo (media/ui/icon, from the site; tools/ui_textures.py), round for the minimap button
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\ui\\icon"
local ICON_ROUND = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\ui\\icon_round"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "
local ICON_REFUSE = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t "
local TITLE_FONT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\LilitaOne.ttf"

-- Two columns: the orders on the left, their materials on the right
-- the « Commandes » tab of the « Bagarre club » window (Hub.lua): its content area
local WIDTH, HEIGHT = 836, 472
local HEADER_H, ITEM_H = 28, 46
local LIST_TOP, LIST_BOTTOM = 42, 40 -- list area inside the tab
local LIST_W = 500                   -- orders column
local MATS_GAP = 10                  -- between the two columns
local CAPACITY = HEIGHT - LIST_TOP - LIST_BOTTOM - 12
local ROW_W = LIST_W - 12 -- list width minus its padding
local BTN_DONE_W, BTN_REFUSE_W = 74, 84
local NAME_W = ROW_W - 60 - BTN_DONE_W - BTN_REFUSE_W - 22
local MAT_H = 24                     -- one material line
local MATS_HEAD, MATS_FOOT = 64, 34  -- materials column: title and buttons, missing count
local MAT_ROWS = math.floor((HEIGHT - LIST_TOP - LIST_BOTTOM - MATS_HEAD - MATS_FOOT) / MAT_H)
local OK_COLOR, SHORT_COLOR = "|cff4fd04f", "|cffff6060"

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

-- Pill button of the style kit (UI.lua): gold; RED gives the dark one (refuse, cancel)
local function MakeButton(parent, width, color, onClick)
    return ns.UI.Button(parent, { width = width, height = 22, size = 12,
        variant = color == RED and "dark" or "gold", onClick = onClick })
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
local headerRows, itemRows, matRows = {}, {}, {}
-- page: orders page; sel: per tab, the group shown in the materials column (a buyer to craft for, or
-- an artisan you ordered from); mats: "buyer" (that group) or "total"
local state = { page = 1, mats = "buyer", sel = {} }
Orders.ui = state -- for the tests

local function Scope()
    return db and db.ordersScope == "account" and "account" or "char"
end

-- "craft": orders to make (artisan side); "placed": the player's own orders (buyer side)
local function Tab()
    return db and db.ordersTab == "placed" and "placed" or "craft"
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
    -- a click shows this buyer's materials in the right column; gold mark on the one shown
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetPoint("TOPLEFT", 0, -3)
    r.mark:SetPoint("BOTTOMLEFT", 0, 3)
    r.mark:SetWidth(3)
    r.mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(self)
        if not self.group then return end
        ClickSound()
        state.sel[Tab()], state.mats = self.group.key, "buyer"
        Refresh()
    end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L(Tab() == "placed" and "orders_artisan_click" or "orders_buyer_click"), 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    if o.status then -- one of my orders: where it stands
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(row.statusText or "")
        if o.status == "refused" and o.reason ~= "" then
            GameTooltip:AddLine(L("orders_refused_reason", o.reason), 1, 0.45, 0.45, true)
        end
    end
    if o.note ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L(o.status and "orders_my_note" or "orders_note"), GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(o.note, 0.85, 0.85, 0.85, true)
    end
    if o.reply ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L(o.status and "orders_reply_artisan" or "orders_reply"), GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(o.reply, 0.62, 0.83, 1, true)
    end
    if type(o.reagents) == "table" and #o.reagents > 0 and (o.status or "pending") == "pending" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("orders_materials_for", o.qty), GOLD[1], GOLD[2], GOLD[3])
        for _, r in ipairs(o.reagents) do
            local name = ItemInfo(r.itemId) or r.name or L("orders_unknown_item", r.itemId)
            local have = Orders.Owned(r.itemId)
            GameTooltip:AddDoubleLine(name, (have >= r.qty and OK_COLOR or SHORT_COLOR) .. have .. " / " .. r.qty .. "|r",
                0.85, 0.85, 0.85)
        end
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

    r.refuse = MakeButton(r, BTN_REFUSE_W, RED, function(self)
        local o = self:GetParent().order
        if o.status then AskCancel(o) else ShowRefuse(o) end -- « My orders »: cancel my pending order
    end)
    r.refuse:SetPoint("RIGHT", -8, 0)
    r.done = MakeButton(r, BTN_DONE_W, GREEN, function(self)
        local o = self:GetParent().order
        if o.status then Orders.MarkReceived(o) else Orders.Mark(o, "done", "") end -- "My orders": received
    end)
    r.done:SetPoint("RIGHT", r.refuse, "LEFT", -6, 0)
    -- "My orders" tab: the status instead of the buttons
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.status:SetPoint("RIGHT", -12, 0)
    r.status:SetJustifyH("RIGHT")

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

-- A group's header: the buyer (to craft) or the artisan (my orders), with a gold mark on the one
-- whose materials are shown
local function FillHeader(r, entry)
    local g = entry.header
    r.group = g
    r.mark:SetShown(state.mats == "buyer" and state.sel[Tab()] == g.key)
    r.bar:SetVertexColor(1, 1, 1, 0.35)
    local c = g.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[g.class]
    if c then r.bar:SetVertexColor(c.r, c.g, c.b, 0.45) end
    r.name:SetText(ns.ClassColored(g.label, g.class))
    local info, age
    if g.artisan then
        info = g.pending > 0 and L("orders_placed_pending", g.pending) or ""
        age = g.pending > 0 and Orders.Age(time(), g.oldest) or ""
    else
        info = g.buyer.level and L("orders_level", g.buyer.level) or ""
        age = Orders.Age(time(), g.oldest)
    end
    if entry.continued then info = info .. "  " .. L("orders_continued") end
    r.info:SetText(info)
    r.age:SetText(age)
end

local STATUS_COLOR = { pending = "|cffffd200", done = "|cff4fd04f", refused = "|cffff6060", received = "|cff9fd4ff",
    cancelled = "|cff8f8f8f" }

local function CancelledHere(o)
    return o.status == "pending" and db and db.ordersCancelled[o.id]
end

local function Received(o)
    return o.status == "done" and ((o.receivedAt or 0) > 0 or (db and db.ordersReceived[o.id]))
end

-- One of my orders: status on the right, and under the name what to do about it
local function FillPlacedText(r, o)
    local status = Received(o) and "received" or CancelledHere(o) and "cancelled" or o.status
    r.statusText = STATUS_COLOR[status] .. L("orders_status_" .. status) .. "|r"
    r.status:SetText(r.statusText)
    local line
    if Received(o) then
        line = "|cff9fd4ff" .. L("orders_received_line", CharName(o.artisan)) .. "|r"
    elseif o.status == "done" then -- receivedAt 0: the Received button is there
        line = "|cff4fd04f" .. L(o.receivedAt == 0 and "orders_pickup_confirm" or "orders_pickup", CharName(o.artisan)) .. "|r"
    elseif o.status == "refused" then
        line = o.reason ~= "" and ("|cffff8080" .. L("orders_refused_reason", o.reason) .. "|r") or ""
    else
        line = "|cff8f8f8f" .. Orders.Age(time(), o.createdAt) .. "|r"
    end
    if o.reply ~= "" then line = line .. "  |cff9fd4ff\194\171 " .. o.reply .. " \194\187|r" end
    return line
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
    local note
    if o.status then -- "My orders" tab: status, or "Received" on a done order to confirm
        local canReceive = Orders.CanReceive(o, db and db.ordersReceived)
        local canCancel = Orders.CanCancel(o, db and db.ordersCancelled)
        r.done:SetShown(canReceive)
        r.refuse:SetShown(canCancel)
        r.status:SetShown(not canReceive and not canCancel)
        note = FillPlacedText(r, o)
    else
        r.done:Show()
        r.refuse:Show()
        r.status:Hide()
        r.statusText = nil
        note = o.note ~= "" and ("\194\171 " .. o.note .. " \194\187") or ""
        if Scope() == "account" and CharKey(o.artisan) ~= CharKey(me) then
            local artisan = "|cff8f8f8f" .. L("orders_for", CharName(o.artisan)) .. "|r"
            note = note ~= "" and (artisan .. "  " .. note) or artisan
        end
    end
    r.note:SetText(note)
    r.name:ClearAllPoints()
    if note ~= "" then
        r.name:SetPoint("TOPLEFT", r.iconFrame, "TOPRIGHT", 10, -2)
    else
        r.name:SetPoint("LEFT", r.iconFrame, "RIGHT", 10, 0)
    end
    r.done.label:SetText(ICON_READY .. L(o.status and "orders_received_button" or "orders_done"))
    r.refuse.label:SetText(o.status and L("orders_cancel_button") or (ICON_REFUSE .. L("orders_refuse")))
end

local SetScopeButton -- below

-- One line of the materials column: icon, name in its quality color, "have / needed"
local function NewMatRow()
    local r = CreateFrame("Frame", nil, win.mats)
    r:SetHeight(MAT_H)
    r:EnableMouse(true)
    r.iconFrame = CreateFrame("Frame", nil, r)
    r.iconFrame:SetSize(20, 20)
    r.iconFrame:SetPoint("LEFT", 8, 0)
    r.icon = r.iconFrame:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", -8, 0)
    r.count:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.iconFrame, "RIGHT", 7, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        if not self.itemId then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if not (GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, self.itemId)) then
            GameTooltip:SetText(self.name:GetText() or "?")
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("orders_have_hint"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(L(Orders.AuctionOpen() and "orders_ah_click" or "orders_ah_closed"), 0.4, 0.8, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- with the auction house open: search this material there
    r:SetScript("OnMouseUp", function(self)
        if Orders.SearchAuction(self.searchName) then ClickSound() end
    end)
    return r
end

-- Materials column: the selected group's orders (a buyer, or an artisan in "My orders"), or all of
-- them (Total). Only orders still pending count.
local function RefreshMaterials(groups, pending)
    local tab = Tab()
    local group
    for _, g in ipairs(groups) do
        if g.key == state.sel[tab] then group = g end
    end
    if not group then
        group = groups[1]
        state.sel[tab] = group and group.key or nil
    end
    local showTotal = state.mats == "total" or not group
    local list, unknown = Orders.Materials(showTotal and pending or group.orders)

    win.matsBuyer.label:SetText(group and ns.ClassColored(group.label, group.class) or "-")
    SetScopeButton(win.matsBuyer, not showTotal)
    SetScopeButton(win.matsTotal, showTotal)
    if group then win.matsBuyer:Enable() else win.matsBuyer:Disable() end
    win.matsTitle:SetText(L(tab == "placed" and "orders_shopping" or "orders_materials"))
    win.matsTotal.label:SetText(L("orders_materials_total"))

    for _, r in ipairs(matRows) do r:Hide() end
    local shown = math.min(#list, #list > MAT_ROWS and MAT_ROWS - 1 or MAT_ROWS)
    local missing = 0
    for i, m in ipairs(list) do
        local have = Orders.Owned(m.itemId)
        missing = missing + math.max(0, m.qty - have)
        if i <= shown then
            local r = matRows[i] or NewMatRow()
            matRows[i] = r
            local name, quality, icon = ItemInfo(m.itemId)
            r.itemId = m.itemId
            r.searchName = name or m.name -- the game's name (client language) for the auction house
            r.icon:SetTexture(icon or UNKNOWN_ICON)
            r.name:SetText(name or m.name or L("orders_unknown_item", m.itemId))
            r.name:SetTextColor(QualityColor(quality))
            r.count:SetText((have >= m.qty and OK_COLOR or SHORT_COLOR) .. have .. " / " .. m.qty .. "|r")
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", win.mats, "TOPLEFT", 4, -(MATS_HEAD + (i - 1) * MAT_H))
            r:SetPoint("TOPRIGHT", win.mats, "TOPRIGHT", -4, -(MATS_HEAD + (i - 1) * MAT_H))
            r:Show()
        end
    end
    win.matsMore:SetText(#list > shown and L("orders_materials_more", #list - shown) or "")

    if #pending == 0 then
        win.matsFoot:SetText("")
    elseif unknown then
        win.matsFoot:SetText("|cffffd200" .. L("orders_materials_update") .. "|r")
    elseif #list == 0 then
        win.matsFoot:SetText(L("orders_materials_none"))
    elseif missing == 0 then
        win.matsFoot:SetText(OK_COLOR .. L("orders_materials_ok") .. "|r")
    else
        win.matsFoot:SetText(SHORT_COLOR .. L("orders_materials_missing", missing) .. "|r")
    end
end

-- the selected one (tab, scope, materials of) is red, the others gold, like the site's tabs
SetScopeButton = function(b, active)
    b.active = active
    b:SetVariant(active and "red" or "gold")
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    local tab = Tab()
    win.title:SetText(L("orders_title", CharName(me)))
    win.scopeChar.label:SetText(L("orders_scope_char"))
    win.scopeAccount.label:SetText(L("orders_scope_account"))
    SetScopeButton(win.scopeChar, Scope() == "char")
    SetScopeButton(win.scopeAccount, Scope() == "account")
    -- the scope (this character / all) only means something for the orders to craft
    win.scopeChar:SetShown(tab == "craft")
    win.scopeAccount:SetShown(tab == "craft")

    local toCraft = Orders.List(Scope())
    local placed = placedSource or {}
    local placedPending = {}
    for _, o in ipairs(placed) do
        if o.status == "pending" and not CancelledHere(o) then placedPending[#placedPending + 1] = o end
    end
    win.tabCraft.label:SetText(L("orders_tab_craft", #toCraft))
    win.tabPlaced.label:SetText(L("orders_tab_placed", #placedPending))
    SetScopeButton(win.tabCraft, tab == "craft")
    SetScopeButton(win.tabPlaced, tab == "placed")

    -- shown: the orders listed; pending: the ones whose materials count
    local shown, pending, groups
    if tab == "placed" then
        shown, pending, groups = placed, placedPending, Orders.GroupPlaced(placed)
    else
        shown, pending, groups = toCraft, toCraft, Orders.Group(toCraft)
    end
    RefreshMaterials(groups, pending) -- first: it picks the group whose header gets the gold mark
    local pages = Orders.Paginate(groups, CAPACITY, HEADER_H, ITEM_H)
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

    if #shown == 0 then
        if tab == "placed" then
            win.empty.text:SetText(L("orders_placed_empty"))
            win.empty.hint:SetText(L(placedSource and "orders_placed_empty_hint" or "orders_placed_update"))
        else
            win.empty.text:SetText(L("orders_empty"))
            win.empty.hint:SetText(L(source and "orders_empty_hint" or "orders_no_file"))
        end
        win.empty:Show()
    else
        win.empty:Hide()
    end
    if tab == "placed" then
        win.total:SetText(L("orders_placed_count", #pending))
    else
        win.total:SetText(L(#pending == 1 and "orders_count_one" or "orders_count", #pending))
    end
    win.pageText:SetText(L("orders_page", state.page, #pages))
    if state.page > 1 then win.prev:Enable() else win.prev:Disable() end
    if state.page < #pages then win.next:Enable() else win.next:Disable() end
end

local function CreateWindow(parent)
    win = CreateFrame("Frame", "WallOfShameForeverOrders", parent)
    win:SetAllPoints()

    -- « Commandes de Chamy Chan », under the materials column
    win.title = ns.UI.Caption(win, 14)
    win.title:SetPoint("BOTTOMRIGHT", -8, 14)
    win.title:SetJustifyH("RIGHT")

    -- this character / all my characters
    local function SetScope(scope)
        db.ordersScope = scope
        state.page = 1
        Refresh()
    end
    win.scopeAccount = MakeButton(win, 150, GREY, function() SetScope("account") end)
    win.scopeAccount:SetPoint("TOPRIGHT", 0, -4)
    win.scopeChar = MakeButton(win, 150, GREY, function() SetScope("char") end)
    win.scopeChar:SetPoint("RIGHT", win.scopeAccount, "LEFT", -6, 0)

    -- tabs: orders to craft (artisan) / my own orders (buyer)
    local function SetTab(tab)
        db.ordersTab = tab
        state.page, state.mats = 1, "buyer"
        Refresh()
    end
    win.tabCraft = MakeButton(win, 170, GREY, function() SetTab("craft") end)
    win.tabCraft:SetPoint("TOPLEFT", 0, -4)
    win.tabPlaced = MakeButton(win, 170, GREY, function() SetTab("placed") end)
    win.tabPlaced:SetPoint("LEFT", win.tabCraft, "RIGHT", 6, 0)

    -- list (left column)
    win.list = CreateFrame("Frame", nil, win)
    win.list:SetPoint("TOPLEFT", 0, -LIST_TOP)
    win.list:SetPoint("BOTTOMLEFT", 0, LIST_BOTTOM)
    win.list:SetWidth(LIST_W)
    ns.UI.Panel(win.list)

    -- materials (right column): the selected buyer's or the total, "have / needed"
    win.mats = CreateFrame("Frame", nil, win)
    win.mats:SetPoint("TOPLEFT", win.list, "TOPRIGHT", MATS_GAP, 0)
    win.mats:SetPoint("BOTTOMRIGHT", 0, LIST_BOTTOM)
    ns.UI.Panel(win.mats)
    win.matsTitle = ns.UI.Caption(win.mats, 15)
    win.matsTitle:SetPoint("TOPLEFT", 12, -10)
    local matsWidth = WIDTH - LIST_W - MATS_GAP
    local half = math.floor((matsWidth - 30) / 2)
    win.matsBuyer = MakeButton(win.mats, half, GREY, function()
        state.mats = "buyer"
        Refresh()
    end)
    win.matsBuyer:SetPoint("TOPLEFT", 10, -32)
    win.matsTotal = MakeButton(win.mats, half, GREY, function()
        state.mats = "total"
        Refresh()
    end)
    win.matsTotal:SetPoint("LEFT", win.matsBuyer, "RIGHT", 8, 0)
    win.matsTotal.label:SetText(L("orders_materials_total"))
    local matsLine = Line(win.mats, "ARTWORK", DIM_GOLD)
    matsLine:SetPoint("TOPLEFT", 8, -(MATS_HEAD - 6))
    matsLine:SetPoint("TOPRIGHT", -8, -(MATS_HEAD - 6))
    win.matsMore = win.mats:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.matsMore:SetPoint("TOPLEFT", 14, -(MATS_HEAD + (MAT_ROWS - 1) * MAT_H + 6))
    local footLineMats = Line(win.mats, "ARTWORK", DIM_GOLD)
    footLineMats:SetPoint("BOTTOMLEFT", 8, MATS_FOOT)
    footLineMats:SetPoint("BOTTOMRIGHT", -8, MATS_FOOT)
    win.matsFoot = win.mats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.matsFoot:SetPoint("BOTTOMLEFT", 12, 12)
    win.matsFoot:SetPoint("BOTTOMRIGHT", -12, 12)
    win.matsFoot:SetJustifyH("LEFT")

    win.empty = CreateFrame("Frame", nil, win.list)
    win.empty:SetSize(360, 140)
    win.empty:SetPoint("CENTER", 0, 20)
    local emptyIcon = win.empty:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetSize(52, 52)
    emptyIcon:SetPoint("TOP", 0, 0)
    emptyIcon:SetTexture(ICON)
    emptyIcon:SetDesaturated(true)
    emptyIcon:SetAlpha(0.6)
    win.empty.text = win.empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.empty.text:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -12)
    win.empty.text:SetTextColor(0.75, 0.68, 0.5)
    win.empty.hint = win.empty:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty.hint:SetPoint("TOP", win.empty.text, "BOTTOM", 0, -8)
    win.empty.hint:SetWidth(340)

    -- footer: total, pages
    win.total = ns.UI.Caption(win, 15)
    win.total:SetPoint("BOTTOMLEFT", 6, 14)
    local function PageButton(direction)
        local b = ns.UI.Button(win, { width = 34, height = 22, text = direction == "Next" and ">" or "<" })
        return b
    end
    win.next = PageButton("Next")
    win.next:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", LIST_W, 6) -- under the orders column
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
    return win
end

ns.Hub.Register({ key = "orders", order = 20,
    label = function() return L("hub_tab_orders", db and #Orders.List(Scope()) or 0) end,
    build = CreateWindow, refresh = function() Refresh() end })

-- The « Commandes » tab of the « Bagarre club » window: open (show true), closed (false) or the other way
function Orders.Toggle(show)
    if not db then return end
    if show == nil then show = not ns.Hub.IsShown("orders") end
    if show then ns.Hub.Show("orders") else ns.Hub.Hide() end
end
ns.ToggleOrders = Orders.Toggle
ns.RefreshOrders = function() Refresh() end

-------------------------------------------------------------------------------
-- Refuse: optional reason
-------------------------------------------------------------------------------

local function CreatePopup()
    popup = CreateFrame("Frame", "WallOfShameForeverOrderRefuse", UIParent)
    popup:SetSize(400, 196)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetToplevel(true)
    popup:EnableMouse(true)
    ns.UI.Window(popup)
    tinsert(UISpecialFrames, "WallOfShameForeverOrderRefuse")

    popup.ribbon = ns.UI.Ribbon(popup, 16)
    popup.ribbon:SetPoint("TOP", 0, 12)
    popup.title = { SetText = function(_, text) popup.ribbon:SetText(text) end }
    popup.item = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    popup.item:SetPoint("TOP", 0, -34)
    popup.item:SetWidth(320)
    popup.item:SetWordWrap(false)
    popup.label = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    popup.label:SetPoint("TOPLEFT", 40, -64)
    popup.label:SetTextColor(0.75, 0.75, 0.75)

    popup.edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    popup.edit:SetSize(304, 22)
    popup.edit:SetPoint("TOPLEFT", 46, -80)
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
    popup.confirm:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 26)
    popup.cancel = MakeButton(popup, 130, GREY, function() popup:Hide() end)
    popup.cancel:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 26)

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
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(ICON_ROUND) -- the guild's logo, cut round for the ring
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
    local list = Orders.List("account")
    local count = #list
    if count == 0 then return 0 end
    local text = L(count == 1 and "orders_count_one" or "orders_count", count)
    -- for which characters (« pour Isa Lice, Chamy Chan »): the tab shows this character's by default
    local names, seen = {}, {}
    for _, o in ipairs(list) do
        local k = CharKey(o.artisan)
        if not seen[k] then
            seen[k] = true
            names[#names + 1] = CharName(o.artisan)
        end
    end
    if #names > 3 then names = { names[1], names[2], names[3], "\226\128\166" } end
    text = L("orders_for_chars", text, table.concat(names, ", "))
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
-- BAG_UPDATE_DELAYED: materials bought, looted or crafted, the "have / needed" counts follow
for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "BAG_UPDATE_DELAYED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, itemId)
    if event == "PLAYER_LOGIN" then
        db = ns.GetDB and ns.GetDB()
        if not db then return end
        if db.minimapButton == nil then db.minimapButton = true end
        if type(db.ordersHandled) ~= "table" then db.ordersHandled = {} end
        if type(db.ordersReceived) ~= "table" then db.ordersReceived = {} end
        if type(db.ordersCancelled) ~= "table" then db.ordersCancelled = {} end
        me = Orders.Me()
        local _, _, _, battleTag = ns.Identity()
        Orders.UpdateIdentity(db, me, battleTag)
        -- the companion's file, a separate addon loaded before PLAYER_LOGIN (may be missing)
        source = Orders.ReadSource(_G.WallOfShameForever_Orders)
        if source then Orders.Prune(db.ordersHandled, source) end
        placedSource = Orders.ReadPlaced(_G.WallOfShameForever_Orders)
        if placedSource then
            Orders.Prune(db.ordersReceived, placedSource)
            -- a cancel the bot has (no longer pending in the file), or an order gone: forgotten
            for id in pairs(db.ordersCancelled) do
                local still
                for _, o in ipairs(placedSource) do
                    if o.id == id and o.status == "pending" then still = true end
                end
                if not still then db.ordersCancelled[id] = nil end
            end
        end
        ApplyMinimapButton()
        C_Timer.After(8, Orders.Notify) -- after the loading screen and the login chat lines
    elseif event == "BAG_UPDATE_DELAYED" then
        if win and win:IsShown() then RefreshSoon() end
    elseif itemId and itemWaiting[itemId] then
        itemWaiting[itemId] = nil
        RefreshSoon()
    end
end)
