-- Wall of Shame Forever: guild item requests (« Demandes » tab of the « Bagarre club » window).
-- A player asks the guild for an item (« 5 × Murloc Fin, for a quest »): drop it on the slot or Shift+click
-- it (bags, quest log, a chat link), set the quantity, an optional reward (free text) and a note. The guild
-- sees the open requests in this tab and in the item's tooltip; someone takes care of it, the asker closes it.
-- The actions go to the companion like the other events (strip in real time, outbox on /reload or logout):
--   2|R|id|name|realm|guild|level|class|time|battletag|action|request|item|qty|reward|note
--   action: new, take, drop (no longer takes care of it) or close (the asker); request: its id
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
                takers = tostring(r.takers or ""), mine = r.mine == true, taking = r.taking == true }
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
                pending = true })
        end
    end
    return list
end

-- The payload for the companion; the note is cut so it fits the strip
function Requests.Payload(action, request, item, qty, reward, note)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    local key = name .. "-" .. realm
    local base = table.concat({ "2", "R", key .. ":R:" .. request .. ":" .. action .. ":" .. time(), name, realm, guild,
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

-- Open requests of the others for this item (tooltip, loot)
function Requests.ForItem(itemId)
    local out = {}
    for _, r in ipairs(Requests.List()) do
        if r.item == itemId and not r.mine then out[#out + 1] = r end
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
        local status = req.takers ~= "" and L("req_takers", req.takers) or L("req_nobody")
        if req.pending then status = status .. "  |cff8f8f8f" .. L("req_pending") .. "|r" end
        r.status:SetText(status)
        if req.mine then
            r.button:SetLabel(L("req_close"))
            r.button:SetVariant("dark")
        elseif req.taking then
            r.button:SetLabel(L("req_drop"))
            r.button:SetVariant("dark")
        else
            r.button:SetLabel(L("req_take"))
            r.button:SetVariant("gold")
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
    f.qty = Edit(f, 46, 3, true)
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
        r.name:SetPoint("RIGHT", -150, 0)
        r.name:SetWordWrap(false)
        r.line = UI.Text(r, "GameFontHighlightSmall")
        r.line:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        r.line:SetPoint("RIGHT", -150, 0)
        r.line:SetWordWrap(false)
        r.status = UI.Text(r, "GameFontHighlightSmall", UI.MUTED)
        r.status:SetPoint("TOPLEFT", r.line, "BOTTOMLEFT", 0, -3)
        r.status:SetPoint("RIGHT", -150, 0)
        r.status:SetWordWrap(false)
        r.button = UI.Button(r, { width = 136, height = 22, size = 12, onClick = function(self)
            local req = self:GetParent().req
            if not req then return end
            local action = req.mine and "close" or req.taking and "drop" or "take"
            Requests.Act(req, action)
            ns.Print(L("req_did_" .. action, (ItemInfo(req.item)) or ("#" .. req.item)))
            Refresh()
            if ns.Hub then ns.Hub.Refresh() end
        end })
        r.button:SetPoint("RIGHT", -4, 0)
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

ns.Hub.Register({ key = "requests", order = 25,
    label = function()
        local n = 0
        for _, r in ipairs(Requests.List()) do if not r.mine then n = n + 1 end end
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
        tooltip:AddLine(L("req_tooltip", by, r.qty), UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
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
            ns.Print(L("req_loot", by, r.qty, message:match("|c.-|r") or ("#" .. id)))
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
    elseif event == "CHAT_MSG_LOOT" then
        OnLoot(a, b)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if panel and panel:IsShown() then Refresh() end
    end
end)
