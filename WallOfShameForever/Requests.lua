-- Wall of Shame Forever: guild item requests (« Demandes » tab of the « Bagarre club » window).
-- A player asks the guild for an item (« 5 × Murloc Fin, for a quest »): drop it on the slot or Shift+click
-- it (bags, quest log, a chat link), set the quantity, an optional reward (free text) and a note. The guild
-- sees the open requests in this tab and in the item's tooltip; someone takes care of it, the asker closes it.
-- The actions go to the companion like the other events (strip in real time, outbox on /reload or logout):
--   2|R|id|name|realm|guild|level|class|time|battletag|action|request|item|qty|reward|note
--   action: new, take, drop (no longer takes care of it) or close (the asker); request: its id
--   v0.8.3, gifts: give (qty given, reward = mode mail or hand, note = the gift's id), got / notgot (the asker
--   confirms a gift, note = its id). A gift not confirmed within 14 days counts as received (bot).
-- The open requests come back from the bot in the companion's file (WallOfShameForever_Orders.hub.requests),
-- read at login or /reload; until then the actions done here show at once (db.requestsLocal).
-- Loaded after Orders.lua (ns.QueueStrip) and Hub.lua.

local ADDON_NAME, ns = ...
local UI = ns.UI
local Requests = {}
ns.Requests = Requests

local NOTE_MAX, REWARD_MAX = 60, 20
local LOCAL_DAYS = 7          -- a local action not seen in the bot's list is dropped after that
local ROW_H = 52
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function L(...) return ns.L(...) end

local db
local panel
local looted = {}             -- request id → already told in chat this session
local formItem                -- the item in the form's slot

-------------------------------------------------------------------------------
-- Data: no frames here (tested with lupa)
-------------------------------------------------------------------------------

-- UTF-8 text cut to n characters, without payload separators or line breaks
local function Short(text, n)
    text = ns.Clean(tostring(text or "")):gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local out, count = {}, 0
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > n then break end
        out[#out + 1] = ch
    end
    return table.concat(out)
end
Requests.Short = Short

local function NewId()
    return string.format("%x%03d", time(), math.random(0, 999))
end

-- The bot's open requests (nil without a companion 0.8.0 or a bot that knows the player)
local function BotList()
    local file = _G.WallOfShameForever_Orders
    local hub = type(file) == "table" and type(file.hub) == "table" and file.hub
    return hub and type(hub.requests) == "table" and hub.requests or nil
end

local function LocalActions()
    if not db then return {} end
    if type(db.requestsLocal) ~= "table" then db.requestsLocal = {} end
    return db.requestsLocal
end

-- gifts announced here (gift id → { request, qty, mode, at, by }) and confirmations done here (gift id →
-- { request, action, at }), shown until the bot's list has them
local function LocalGifts()
    if not db then return {} end
    if type(db.requestGifts) ~= "table" then db.requestGifts = {} end
    return db.requestGifts
end

local function LocalConfirms()
    if not db then return {} end
    if type(db.requestConfirms) ~= "table" then db.requestConfirms = {} end
    return db.requestConfirms
end

-- « id;name;qty;mode;status » (status p pending, r received, x not received) → table
local function ParseGift(text)
    local id, name, qty, mode, status = tostring(text):match("^([^;]+);([^;]*);(%d+);(%a+);(%a)$")
    if not id then return nil end
    return { id = id, name = name, qty = tonumber(qty), mode = mode, status = status }
end

local function FindGift(req, id)
    for _, g in ipairs(req.gifts) do
        if g.id == id then return g end
    end
end

local function AddWaiting(req, mode, n)
    if mode == "mail" then req.waitMail = req.waitMail + n else req.waitHand = req.waitHand + n end
end

-- The gifts announced or confirmed here, on top of the bot's numbers; then what is left and what to confirm
local function Overlay(list)
    local now, bot = time(), BotList()
    local byId = {}
    for _, req in ipairs(list) do byId[req.id] = req end
    local gifts, confirms = LocalGifts(), LocalConfirms()
    for id, g in pairs(gifts) do
        local req = byId[g.request]
        if (req and FindGift(req, id)) or now - (g.at or 0) > LOCAL_DAYS * 86400 or (bot and not req) then
            gifts[id] = nil
        elseif req then
            table.insert(req.gifts, 1, { id = id, name = g.by or "?", qty = g.qty, mode = g.mode, status = "p", pending = true })
            AddWaiting(req, g.mode, g.qty)
            req.pending = true
        end
    end
    for id, c in pairs(confirms) do
        local req = byId[c.request]
        local gift = req and FindGift(req, id)
        if (gift and gift.status ~= "p") or now - (c.at or 0) > LOCAL_DAYS * 86400 or (bot and not req) then
            confirms[id] = nil
        elseif gift then
            gift.status, gift.pending = c.action == "got" and "r" or "x", true
            AddWaiting(req, gift.mode, -gift.qty)
            if c.action == "got" then req.received = req.received + gift.qty end
        end
    end
    for _, req in ipairs(list) do
        req.waiting = req.waitMail + req.waitHand
        req.left = math.max(0, req.qty - req.received - req.waiting)
        req.toConfirm = {}
        if req.mine then
            for _, g in ipairs(req.gifts) do
                if g.status == "p" and not g.pending then req.toConfirm[#req.toConfirm + 1] = g end
            end
        end
    end
    return list
end

-- What the tab shows: the bot's list with this player's actions not seen there yet (a new request, a
-- request closed, taken or dropped here). Local actions the bot already shows, or too old, are forgotten.
function Requests.List()
    local bot = BotList() or {}
    local actions = LocalActions()
    local now = time()
    local list, seen = {}, {}
    for _, r in ipairs(bot) do
        if type(r) == "table" and r.id and tonumber(r.item) then
            local a = actions[r.id]
            local copy = { id = tostring(r.id), item = tonumber(r.item), qty = tonumber(r.qty) or 1,
                reward = tostring(r.reward or ""), note = tostring(r.note or ""), by = tostring(r.by or "?"),
                byClass = r.byClass ~= "" and r.byClass or nil, at = tonumber(r.at) or 0,
                takers = tostring(r.takers or ""), mine = r.mine == true, taking = r.taking == true,
                received = tonumber(r.received) or 0, waitMail = tonumber(r.waitMail) or 0,
                waitHand = tonumber(r.waitHand) or 0, gifts = {} }
            if type(r.gifts) == "table" then
                for _, text in ipairs(r.gifts) do
                    local gift = ParseGift(text)
                    if gift then copy.gifts[#copy.gifts + 1] = gift end
                end
            end
            seen[copy.id] = true
            if a and a.action == "new" then actions[copy.id] = nil end -- the bot has it now
            if a and (a.action == "take" and copy.taking or a.action == "drop" and not copy.taking) then
                actions[copy.id] = nil
            elseif a and a.action == "take" then
                copy.taking, copy.pending = true, true
            elseif a and a.action == "drop" then
                copy.taking, copy.pending = false, true
            end
            if not (a and a.action == "close") then list[#list + 1] = copy end
        end
    end
    for id, a in pairs(actions) do
        if now - (a.at or 0) > LOCAL_DAYS * 86400 then
            actions[id] = nil
        elseif a.action == "close" and not seen[id] and BotList() then
            actions[id] = nil -- closed on the bot too
        elseif a.action == "new" and not seen[id] then
            table.insert(list, 1, { id = id, item = a.item, qty = a.qty, reward = a.reward or "", note = a.note or "",
                by = a.by or "?", byClass = a.byClass, at = a.at, takers = "", mine = true, taking = false,
                pending = true, received = 0, waitMail = 0, waitHand = 0, gifts = {} })
        end
    end
    return Overlay(list)
end

-- The payload for the companion; the note is cut so it fits the strip
function Requests.Payload(action, request, item, qty, reward, note)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    local key = name .. "-" .. realm
    -- a gift's id in the event's id: two gifts or confirmations in the same second stay two events
    local gift = (action == "give" or action == "got" or action == "notgot") and (":" .. tostring(note)) or ""
    local base = table.concat({ "2", "R", key .. ":R:" .. request .. ":" .. action .. gift .. ":" .. time(), name, realm, guild,
        UnitLevel("player"), classFile or "", time(), battleTag, action, request, item or "", qty or "",
        Short(reward, REWARD_MAX) }, "|") .. "|"
    local room = (ns.STRIP_MAX_PAYLOAD or 240) - #base
    local text = Short(note, NOTE_MAX)
    while #text > room and #text > 0 do text = Short(text, select(2, text:gsub("[^\128-\191]", "")) - 1) end
    return base .. (room > 0 and text or "")
end

local function Send(payload)
    ns.AddToOutbox(payload)
    if ns.QueueStrip then ns.QueueStrip(payload) end
end

-- A new request. Returns its id, or nil and why
function Requests.New(item, qty, reward, note)
    if not db then return nil, "no db" end
    item, qty = tonumber(item), math.floor(tonumber(qty) or 1)
    if not item or item <= 0 then return nil, "req_err_item" end
    if qty < 1 or qty > 999 then return nil, "req_err_qty" end
    local id = NewId()
    local name = ns.Identity()
    local _, classFile = UnitClass("player")
    LocalActions()[id] = { action = "new", at = time(), item = item, qty = qty, reward = Short(reward, REWARD_MAX),
        note = Short(note, NOTE_MAX), by = name, byClass = classFile }
    Send(Requests.Payload("new", id, item, qty, reward, note))
    return id
end

-- take, drop or close
function Requests.Act(request, action)
    if not db or not request then return nil end
    LocalActions()[request.id] = { action = action, at = time() }
    local payload = Requests.Payload(action, request.id)
    Send(payload)
    return payload
end

-- Announce a gift on someone's request: qty (1 to what is still needed), mode mail or hand. Returns the
-- gift's id, or nil and why
function Requests.Give(req, qty, mode)
    if not db or not req or req.mine then return nil, "req_err_give_qty" end
    qty = math.floor(tonumber(qty) or 0)
    if qty < 1 or qty > (req.left or req.qty) then return nil, "req_err_give_qty" end
    if mode ~= "mail" and mode ~= "hand" then return nil, "req_err_give_mode" end
    local id = "g" .. NewId()
    LocalGifts()[id] = { request = req.id, qty = qty, mode = mode, at = time(), by = (ns.Identity()) }
    Send(Requests.Payload("give", req.id, req.item, qty, mode, id))
    return id
end

-- The asker confirms a gift: received (got = true) or not
function Requests.Confirm(req, gift, got)
    if not db or not req or not gift then return nil end
    local action = got and "got" or "notgot"
    LocalConfirms()[gift.id] = { request = req.id, action = action, at = time() }
    local payload = Requests.Payload(action, req.id, "", "", "", gift.id)
    Send(payload)
    return payload
end

-- Open requests of the others for this item, still needed (tooltip, loot)
function Requests.ForItem(itemId)
    local out = {}
    for _, r in ipairs(Requests.List()) do
        if r.item == itemId and not r.mine and r.qty - r.received > 0 then out[#out + 1] = r end
    end
    return out
end

-- « mail 20, in person 10 »
local function ModesText(req)
    local parts = {}
    if req.waitMail > 0 then parts[#parts + 1] = L("req_mode_mail_n", req.waitMail) end
    if req.waitHand > 0 then parts[#parts + 1] = L("req_mode_hand_n", req.waitHand) end
    return table.concat(parts, ", ")
end
Requests.ModesText = ModesText

-- « Received 20/100 · 30 on the way (mail 20, in person 10) »
function Requests.StatusText(req)
    local parts = {}
    if req.received > 0 or req.waiting > 0 then
        parts[1] = L("req_received", req.received, req.qty)
        if req.waiting > 0 then parts[2] = L("req_waiting", req.waiting, ModesText(req)) end
        if req.mine and req.received >= req.qty then parts[#parts + 1] = L("req_complete") end
    elseif req.takers ~= "" then
        parts[1] = L("req_takers", req.takers)
    else
        parts[1] = L("req_nobody")
    end
    return table.concat(parts, "  \194\183  ")
end

-- the gifts to confirm on my requests (tab label, login notice)
function Requests.ToConfirm()
    local out = {}
    for _, r in ipairs(Requests.List()) do
        for _, g in ipairs(r.toConfirm) do out[#out + 1] = { req = r, gift = g } end
    end
    return out
end

local function ItemId(link)
    return tonumber(type(link) == "string" and link:match("item:(%d+)"))
end
Requests.ItemId = ItemId

-------------------------------------------------------------------------------
-- The tab
-------------------------------------------------------------------------------

local function ItemInfo(id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, quality, icon
    if getInfo then
        local ok, n, _, q, _, _, _, _, _, _, t = pcall(getInfo, id)
        if ok then name, quality, icon = n, q, t end
    end
    if not icon then
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        if getIcon then
            local ok, t = pcall(getIcon, id)
            if ok then icon = t end
        end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return name, icon, c and c.hex or "|cffffffff"
end

local function Refresh()
    if not (panel and panel:IsShown()) then return end
    local f = panel.form
    f.cap:SetText(L("req_new"))
    f.hint:SetText(formItem and "" or L("req_drop_hint"))
    if formItem then
        local name, icon, hex = ItemInfo(formItem)
        f.slotIcon:SetTexture(icon or UNKNOWN_ICON)
        f.itemName:SetText(hex .. (name or ("#" .. formItem)) .. "|r")
    else
        f.slotIcon:SetTexture(nil)
        f.itemName:SetText("")
    end
    f.qtyLabel:SetText(L("req_qty"))
    f.rewardLabel:SetText(L("req_reward"))
    f.noteLabel:SetText(L("req_note"))
    f.publish:SetLabel(L("req_publish"))
    if formItem then f.publish:Enable() else f.publish:Disable() end

    local list = Requests.List()
    panel.listCap:SetText(L("req_open", #list))
    for _, r in ipairs(panel.rows) do r:Hide() end
    for i, req in ipairs(list) do
        local r = panel.rows[i] or panel.NewRow()
        panel.rows[i] = r
        r.req = req
        local name, icon, hex = ItemInfo(req.item)
        r.icon:SetTexture(icon or UNKNOWN_ICON)
        r.name:SetText(hex .. (name or ("#" .. req.item)) .. "|r  |cffffffff\195\151" .. req.qty .. "|r")
        local by = ns.ClassColored and ns.ClassColored(req.by, req.byClass) or req.by
        local parts = { L("req_by", by) }
        if req.note ~= "" then parts[#parts + 1] = "\194\171 " .. req.note .. " \194\187" end
        if req.reward ~= "" then parts[#parts + 1] = "|cffffd36b" .. L("req_reward_is", req.reward) .. "|r" end
        r.line:SetText(table.concat(parts, "  "))
        local status = Requests.StatusText(req)
        if req.pending then status = status .. "  |cff8f8f8f" .. L("req_pending") .. "|r" end
        r.status:SetText(status)
        r.close:Hide()
        r.button:Enable()
        if req.mine and #req.toConfirm > 0 then
            r.button:SetLabel(L("req_confirm_n", #req.toConfirm))
            r.button:SetVariant("gold")
            r.close:SetLabel(L("req_close"))
            r.close:Show()
        elseif req.mine then
            r.button:SetLabel(L("req_close"))
            r.button:SetVariant("dark")
        elseif req.left > 0 then
            r.button:SetLabel(L("req_give"))
            r.button:SetVariant("gold")
        else
            r.button:SetLabel(L("req_covered"))
            r.button:SetVariant("dark")
            r.button:Disable()
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel.scroll.child, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", panel.scroll.child, "RIGHT", -10, 0)
        r:Show()
    end
    panel.empty:SetText(#list == 0 and L(BotList() and "req_empty" or "req_no_data") or "")
    panel.scroll:SetContentHeight(#list * ROW_H)
end
Requests.Refresh = Refresh

local function SetItem(item)
    if not panel then return end
    formItem = item
    Refresh()
end
Requests.SetItem = SetItem

local function Edit(parent, width, maxLetters, numeric)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 22)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters)
    if numeric and e.SetNumeric then e:SetNumeric(true) end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

local function Build(parent)
    panel = CreateFrame("Frame", "WallOfShameForeverRequests", parent)
    panel:SetAllPoints()

    -- new request: the item slot, quantity, reward, note, publish
    local f = CreateFrame("Frame", nil, panel)
    panel.form = f
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("TOPRIGHT", 0, 0)
    f:SetHeight(118)
    UI.Panel(f)
    f.cap = UI.Caption(f, 15)
    f.cap:SetPoint("TOPLEFT", 16, -12)

    f.slot = CreateFrame("Button", nil, f)
    f.slot:SetSize(44, 44)
    f.slot:SetPoint("TOPLEFT", 16, -38)
    local bg = f.slot:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    bg:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    f.slotIcon = f.slot:CreateTexture(nil, "ARTWORK")
    f.slotIcon:SetPoint("TOPLEFT", 3, -3)
    f.slotIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    local border = f.slot:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    border:SetVertexColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
    local function TakeCursor()
        if not GetCursorInfo then return end
        -- two values: « GetCursorInfo and GetCursorInfo() » would keep only the first (v0.8.2 fix)
        local kind, id = GetCursorInfo()
        if kind == "item" and tonumber(id) then
            SetItem(tonumber(id))
            if ClearCursor then ClearCursor() end
            return true
        end
    end
    f.slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.slot:SetScript("OnReceiveDrag", TakeCursor)
    f.slot:SetScript("OnClick", function(_, button)
        if TakeCursor() then return end
        if button == "RightButton" then SetItem(nil) end
    end)
    f.slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if formItem and GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, formItem) then
            GameTooltip:AddLine(L("req_slot_clear"), 0.7, 0.7, 0.7, true)
        else
            GameTooltip:SetText(L("req_drop_hint"), 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    f.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.itemName = UI.Text(f, "GameFontNormalLarge")
    f.itemName:SetPoint("LEFT", f.slot, "RIGHT", 12, 8)
    f.itemName:SetWidth(330)
    f.itemName:SetWordWrap(false)
    f.hint = UI.Text(f, "GameFontHighlight", UI.MUTED)
    f.hint:SetPoint("LEFT", f.slot, "RIGHT", 12, 0)
    f.hint:SetWidth(330)

    f.qtyLabel = UI.Text(f, "GameFontHighlightSmall", UI.MUTED)
    f.qtyLabel:SetPoint("TOPLEFT", 420, -36)
    f.qty = Edit(f, 56, 3, true)
    f.qty:SetPoint("TOPLEFT", f.qtyLabel, "BOTTOMLEFT", 6, -2)
    f.qty:SetText("1")
    f.rewardLabel = UI.Text(f, "GameFontHighlightSmall", UI.MUTED)
    f.rewardLabel:SetPoint("TOPLEFT", 490, -36)
    f.reward = Edit(f, 140, REWARD_MAX)
    f.reward:SetPoint("TOPLEFT", f.rewardLabel, "BOTTOMLEFT", 6, -2)
    f.noteLabel = UI.Text(f, "GameFontHighlightSmall", UI.MUTED)
    f.noteLabel:SetPoint("TOPLEFT", 80, -88)
    f.note = Edit(f, 420, NOTE_MAX)
    f.note:SetPoint("LEFT", f.noteLabel, "RIGHT", 10, 0)
    f.publish = UI.Button(f, { width = 130, onClick = function()
        local id, err = Requests.New(formItem, f.qty:GetText(), f.reward:GetText(), f.note:GetText())
        if not id then
            ns.Print(L(err or "req_err_item"))
            return
        end
        formItem = nil
        f.qty:SetText("1")
        f.reward:SetText("")
        f.note:SetText("")
        ns.Print(L("req_sent"))
        Refresh()
        if ns.Hub then ns.Hub.Refresh() end
    end })
    f.publish:SetPoint("BOTTOMRIGHT", -16, 14)

    -- the open requests
    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -12)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    UI.Panel(list)
    panel.listCap = UI.Caption(list, 15)
    panel.listCap:SetPoint("TOPLEFT", 16, -12)
    panel.scroll = UI.Scroll(list)
    panel.scroll:SetPoint("TOPLEFT", 12, -36)
    panel.scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    panel.empty = UI.Text(list, "GameFontHighlight", UI.MUTED)
    panel.empty:SetPoint("TOPLEFT", 16, -44)
    panel.empty:SetPoint("RIGHT", -16, 0)
    panel.rows = {}
    function panel.NewRow()
        local r = CreateFrame("Frame", nil, panel.scroll.child)
        r:SetHeight(ROW_H)
        r:EnableMouse(true)
        r.iconFrame = CreateFrame("Frame", nil, r)
        r.iconFrame:SetSize(36, 36)
        r.iconFrame:SetPoint("LEFT", 4, 0)
        r.icon = r.iconFrame:CreateTexture(nil, "ARTWORK")
        r.icon:SetAllPoints()
        r.name = UI.Text(r, "GameFontNormal")
        r.name:SetPoint("TOPLEFT", r.iconFrame, "TOPRIGHT", 10, -1)
        r.name:SetPoint("RIGHT", -230, 0)
        r.name:SetWordWrap(false)
        r.line = UI.Text(r, "GameFontHighlightSmall")
        r.line:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        r.line:SetPoint("RIGHT", -230, 0)
        r.line:SetWordWrap(false)
        r.status = UI.Text(r, "GameFontHighlightSmall", UI.MUTED)
        r.status:SetPoint("TOPLEFT", r.line, "BOTTOMLEFT", 0, -3)
        r.status:SetPoint("RIGHT", -230, 0)
        r.status:SetWordWrap(false)
        local function Close(req)
            Requests.Act(req, "close")
            ns.Print(L("req_did_close", (ItemInfo(req.item)) or ("#" .. req.item)))
            Refresh()
            if ns.Hub then ns.Hub.Refresh() end
        end
        r.button = UI.Button(r, { width = 136, height = 22, size = 12, onClick = function(self)
            local req = self:GetParent().req
            if not req then return end
            if req.mine and #req.toConfirm > 0 then
                Requests.ShowConfirm(req)
            elseif req.mine then
                Close(req)
            else
                Requests.ShowGive(req)
            end
        end })
        r.button:SetPoint("RIGHT", -4, 0)
        r.close = UI.Button(r, { width = 76, height = 22, size = 12, variant = "dark", onClick = function(self)
            local req = self:GetParent().req
            if req then Close(req) end
        end })
        r.close:SetPoint("RIGHT", r.button, "LEFT", -6, 0)
        r.close:Hide()
        r.sep = UI.Line(r, 0.12)
        r.sep:SetPoint("BOTTOMLEFT", 0, 0)
        r.sep:SetPoint("BOTTOMRIGHT", 0, 0)
        r:SetScript("OnEnter", function(self)
            if not (self.req and GameTooltip.SetItemByID) then return end
            GameTooltip:SetOwner(self.iconFrame, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetItemByID, GameTooltip, self.req.item)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end

    panel:SetScript("OnShow", Refresh)
    panel:Hide()
    return panel
end

-------------------------------------------------------------------------------
-- « Je donne… » window: how many (up to what is still needed), by mail or in person
-------------------------------------------------------------------------------

local giveWin, confirmWin

local function FindRequest(id)
    for _, r in ipairs(Requests.List()) do
        if r.id == id then return r end
    end
end

local function SmallWindow(name, width, height, key)
    local w = CreateFrame("Frame", name, UIParent)
    w:SetSize(width, height)
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    UI.Window(w)
    UI.Movable(w, db, key)
    UI.Appear(w, db)
    tinsert(UISpecialFrames, name)
    w.ribbon = UI.Ribbon(w, 18)
    w.ribbon:SetPoint("TOP", 0, 14)
    w.close = UI.Close(w, function() w:Hide() end)
    w.close:SetPoint("TOPRIGHT", -24, -24)
    w.item = UI.Text(w, "GameFontNormalLarge")
    w.item:SetPoint("TOPLEFT", 34, -50)
    w.item:SetPoint("RIGHT", -60, 0)
    w.item:SetWordWrap(false)
    w.info = UI.Text(w, "GameFontHighlightSmall", UI.MUTED)
    w.info:SetPoint("TOPLEFT", w.item, "BOTTOMLEFT", 0, -6)
    w.info:SetPoint("RIGHT", -34, 0)
    w:Hide()
    return w
end

local function ItemTitle(req)
    local name, _, hex = ItemInfo(req.item)
    return hex .. (name or ("#" .. req.item)) .. "|r"
end

local function RefreshGive()
    local w = giveWin
    local req = w and w.req
    if not req then return end
    w.ribbon:SetText(L("req_give_title"))
    w.item:SetText(ItemTitle(req))
    local by = ns.ClassColored and ns.ClassColored(req.by, req.byClass) or req.by
    w.info:SetText(L("req_give_left", req.left, req.qty, by))
    w.qtyLabel:SetText(L("req_give_qty"))
    w.howLabel:SetText(L("req_give_how"))
    for mode, b in pairs(w.modes) do
        b:SetLabel(L("req_mode_" .. mode))
        b:SetVariant(w.mode == mode and "gold" or "dark")
    end
    w.ok:SetLabel(L("req_give_ok"))
    if w.mode and req.left > 0 then w.ok:Enable() else w.ok:Disable() end
end

local function CreateGiveWindow()
    local w = SmallWindow("WallOfShameForeverGive", 420, 250, "givePosition")
    w.qtyLabel = UI.Text(w, "GameFontHighlight", UI.MUTED)
    w.qtyLabel:SetPoint("TOPLEFT", 34, -110)
    w.qty = Edit(w, 56, 3, true)
    w.qty:SetPoint("LEFT", w.qtyLabel, "RIGHT", 12, 0)
    w.howLabel = UI.Text(w, "GameFontHighlight", UI.MUTED)
    w.howLabel:SetPoint("TOPLEFT", 34, -148)
    w.modes = {}
    local prev
    for _, mode in ipairs({ "mail", "hand" }) do
        local b = UI.Button(w, { width = 120, height = 24, size = 12, onClick = function()
            w.mode = mode
            RefreshGive()
        end })
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("LEFT", w.howLabel, "RIGHT", 12, 0) end
        w.modes[mode] = b
        prev = b
    end
    w.ok = UI.Button(w, { width = 220, onClick = function()
        local req = w.req
        if not req then return end
        local qty = w.qty:GetText()
        local id, err = Requests.Give(req, qty, w.mode)
        if not id then
            ns.Print(L(err or "req_err_give_qty"))
            return
        end
        ns.Print(L("req_did_give", tonumber(qty), ItemTitle(req), L("req_via_" .. w.mode)))
        w:Hide()
        Refresh()
        if ns.Hub then ns.Hub.Refresh() end
    end })
    w.ok:SetPoint("BOTTOM", 0, 34)
    giveWin = w
end

function Requests.ShowGive(req)
    if not db or not req then return end
    if not giveWin then CreateGiveWindow() end
    if giveWin.req ~= req then giveWin.mode = nil end
    giveWin.req = req
    giveWin.qty:SetText(tostring(req.left))
    giveWin:Show()
    RefreshGive()
end

function Requests.GiveWindow()
    return giveWin
end

-------------------------------------------------------------------------------
-- « À confirmer » window (the asker): each gift announced, Reçu / Pas reçu
-------------------------------------------------------------------------------

local CONFIRM_ROW_H = 34

local function RefreshConfirm()
    local w = confirmWin
    if not (w and w.reqId) then return end
    local req = FindRequest(w.reqId)
    if not req or #req.toConfirm == 0 then
        w:Hide()
        return
    end
    w.req = req
    w.ribbon:SetText(L("req_confirm_title"))
    w.item:SetText(ItemTitle(req))
    w.info:SetText(Requests.StatusText(req))
    for _, row in ipairs(w.rows) do row:Hide() end
    for i, gift in ipairs(req.toConfirm) do
        local row = w.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, w)
            row:SetHeight(CONFIRM_ROW_H)
            row.text = UI.Text(row, "GameFontHighlight")
            row.text:SetPoint("LEFT", 0, 0)
            row.text:SetPoint("RIGHT", -200, 0)
            row.text:SetWordWrap(false)
            row.no = UI.Button(row, { width = 96, height = 22, size = 12, variant = "red", onClick = function(self)
                local g = self:GetParent().gift
                Requests.Confirm(w.req, g, false)
                ns.Print(L("req_did_notgot", g.name))
                RefreshConfirm()
                Refresh()
                if ns.Hub then ns.Hub.Refresh() end
            end })
            row.no:SetPoint("RIGHT", 0, 0)
            row.yes = UI.Button(row, { width = 90, height = 22, size = 12, onClick = function(self)
                local g = self:GetParent().gift
                Requests.Confirm(w.req, g, true)
                ns.Print(L("req_did_got", g.name))
                RefreshConfirm()
                Refresh()
                if ns.Hub then ns.Hub.Refresh() end
            end })
            row.yes:SetPoint("RIGHT", row.no, "LEFT", -6, 0)
            w.rows[i] = row
        end
        row.gift = gift
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 34, -100 - (i - 1) * CONFIRM_ROW_H)
        row:SetPoint("RIGHT", -34, 0)
        row.text:SetText(L("req_gift_line", gift.name, gift.qty, L("req_via_" .. (gift.mode == "mail" and "mail" or "hand"))))
        row.yes:SetLabel(L("req_got"))
        row.no:SetLabel(L("req_notgot"))
        row:Show()
    end
    w.hint:SetText(L("req_confirm_hint"))
    w:SetHeight(150 + #req.toConfirm * CONFIRM_ROW_H)
end

local function CreateConfirmWindow()
    local w = SmallWindow("WallOfShameForeverConfirm", 520, 200, "confirmPosition")
    w.rows = {}
    w.hint = UI.Text(w, "GameFontHighlightSmall", UI.MUTED)
    w.hint:SetPoint("BOTTOM", 0, 28)
    confirmWin = w
end

function Requests.ShowConfirm(req)
    if not db or not req then return end
    if not confirmWin then CreateConfirmWindow() end
    confirmWin.reqId = req.id
    confirmWin:Show()
    RefreshConfirm()
end

function Requests.ConfirmWindow()
    return confirmWin
end

-- At login (the companion's file is read then): a chat line per new gift announced on my requests
local function NoticeGifts()
    if type(db.giftsTold) ~= "table" then db.giftsTold = {} end
    local told, now, current = db.giftsTold, time(), {}
    for _, c in ipairs(Requests.ToConfirm()) do
        current[c.gift.id] = true
        if not told[c.gift.id] then
            told[c.gift.id] = now
            ns.Print(L("req_gift_notice", c.gift.name, c.gift.qty, ItemTitle(c.req), L("req_via_" .. (c.gift.mode == "mail" and "mail" or "hand"))))
        end
    end
    for id, at in pairs(told) do
        if not current[id] and now - at > 30 * 86400 then told[id] = nil end
    end
end
Requests.NoticeGifts = NoticeGifts

ns.Hub.Register({ key = "requests", order = 25,
    label = function()
        local n = 0
        for _, r in ipairs(Requests.List()) do if not r.mine then n = n + 1 end end
        local c = #Requests.ToConfirm()
        if c > 0 then return L("hub_tab_requests_confirm", n, c) end
        return L("hub_tab_requests", n)
    end,
    build = Build, refresh = function() Refresh() end })

-------------------------------------------------------------------------------
-- Shift+click an item (bags, quest log, chat link) while the tab is open: it goes in the slot
-------------------------------------------------------------------------------

-- Shift+click goes through several functions depending on where (bags, quest log, chat link) and on the
-- client: all of them are listened to. In the bags, without a chat line open, the game opens the stack
-- split window too: closed when the item went in the slot.
local function OnInsertLink(text)
    if not (panel and panel:IsShown() and panel:IsVisible()) then return end
    local id = ItemId(text)
    if not id then return end
    SetItem(id)
    if StackSplitFrame and C_Timer then
        C_Timer.After(0, function()
            if StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
        end)
    end
end

local function HookLinks()
    if type(hooksecurefunc) ~= "function" then return end
    if type(ChatEdit_InsertLink) == "function" then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
    if type(HandleModifiedItemClick) == "function" then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if not IsModifiedClick or IsModifiedClick("CHATLINK") then OnInsertLink(link) end
        end)
    end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
        hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
    end
end
Requests.OnInsertLink = OnInsertLink

-------------------------------------------------------------------------------
-- Tooltip: « Demandé par Chamy Chan (5) » on an item someone asked for; a chat line when you loot it
-------------------------------------------------------------------------------

local function AddTooltipLines(tooltip, id)
    if not (db and id) then return end
    for _, r in ipairs(Requests.ForItem(id)) do
        local by = ns.ClassColored and ns.ClassColored(r.by, r.byClass) or r.by
        tooltip:AddLine(L("req_tooltip", by, r.qty - r.received), UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
    end
end

local function HookTooltips()
    if type(TooltipDataProcessor) == "table" and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            AddTooltipLines(tooltip, data and tonumber(data.id))
        end)
        return
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                AddTooltipLines(self, ItemId(link))
            end)
        end
    end
end

local function OnLoot(message, who)
    local id = ItemId(message)
    if not id then return end
    local me = UnitName and UnitName("player")
    if who and who ~= "" and me and Ambiguate and Ambiguate(who, "short") ~= me then return end
    for _, r in ipairs(Requests.ForItem(id)) do
        if not looted[r.id] then
            looted[r.id] = true
            local by = ns.ClassColored and ns.ClassColored(r.by, r.byClass) or r.by
            ns.Print(L("req_loot", by, r.qty - r.received, message:match("|c.-|r") or ("#" .. id)))
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, a, b)
    if event == "PLAYER_LOGIN" then
        db = ns.GetDB and ns.GetDB()
        if not db then return end
        LocalActions()
        HookTooltips()
        HookLinks()
        NoticeGifts()
    elseif event == "CHAT_MSG_LOOT" then
        OnLoot(a, b)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if panel and panel:IsShown() then Refresh() end
    end
end)
