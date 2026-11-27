-- Wall of Shame Forever: the « Bagarre club » window. One window with tabs: Guilde (roster, from
-- WallOfShameForever.lua), Commandes (Orders.lua), and three tabs filled from the guild's bot through the
-- companion's file (WallOfShameForever_Orders.hub, read at login or /reload): Hauts faits (titles,
-- achievements count, the next ones, rank at the bank), Activités (planned outings) and Objectifs (bank goal
-- and guild challenges). The texts come already worded by the bot (amounts, durations).
-- Look: UI.lua. Loaded last: the other files register their tab with ns.Hub.Register.

local ADDON_NAME, ns = ...
local UI = ns.UI
local Hub = {}
ns.Hub = Hub

local WIDTH, HEIGHT = 900, 620
local PAD = 32
local function L(...) return ns.L(...) end

local db
local hub -- the window
local tabs, order = {}, {}
local current
local activityWin, chosenRole -- an activity's window (Activités), below

-- The bot's data for the tabs (nil without a companion, or a companion older than 0.7.9)
function Hub.Data()
    local file = _G.WallOfShameForever_Orders
    return type(file) == "table" and type(file.hub) == "table" and file.hub or nil
end

-- A tab: { key, order, label = function() → text, build = function(panel), refresh = function(panel) }
function Hub.Register(tab)
    tabs[tab.key] = tab
    order[#order + 1] = tab
    table.sort(order, function(a, b) return a.order < b.order end)
end

local function RefreshTabs()
    for _, t in ipairs(order) do
        if t.button then
            t.button:SetLabel(t.label())
            t.button:SetVariant(t.key == current and "red" or "gold")
        end
    end
    local x = 0
    for _, t in ipairs(order) do
        if t.button then
            t.button:ClearAllPoints()
            t.button:SetPoint("TOPLEFT", hub.tabsRow, "TOPLEFT", x, 0)
            x = x + t.button:GetWidth() + 8
        end
    end
end

local function RefreshHeader()
    hub.ribbon:SetText(GetGuildInfo and GetGuildInfo("player") or "Wall of Shame Forever")
    local name = ns.Identity() or "?"
    local level = UnitLevel and UnitLevel("player") or 0
    hub.sub:SetText(L("hub_sub", name, level))
    hub.optionsButton:SetLabel(L("hub_options"))
    local file = _G.WallOfShameForever_Orders
    local updated = type(file) == "table" and tonumber(file.updated)
    hub.updated:SetText(updated and ns.Orders and ns.Orders.Age and L("hub_updated", ns.Orders.Age(time(), updated)) or "")
end

function Hub.Refresh()
    if not (hub and hub:IsShown()) then return end
    RefreshHeader()
    RefreshTabs()
    local t = tabs[current]
    if t and t.refresh and t.panel then t.refresh(t.panel) end
end

local function Create()
    hub = CreateFrame("Frame", "WallOfShameForeverHub", UIParent)
    hub:SetSize(WIDTH, HEIGHT)
    hub:SetFrameStrata("DIALOG")
    hub:SetToplevel(true)
    UI.Window(hub)
    UI.Movable(hub, db, "hubPosition")
    UI.Appear(hub, db)
    tinsert(UISpecialFrames, "WallOfShameForeverHub") -- closes with Escape

    hub.ribbon = UI.Ribbon(hub, 24)
    hub.ribbon:SetPoint("TOPLEFT", PAD - 6, -24)
    hub.sub = UI.Caption(hub, 15)
    hub.sub:SetPoint("LEFT", hub.ribbon, "RIGHT", 12, 0)
    hub.close = UI.Close(hub, function() Hub.Hide() end)
    hub.close:SetPoint("TOPRIGHT", -26, -28)
    hub.optionsButton = UI.Button(hub, { variant = "dark", onClick = function()
        if ns.ToggleOptions then ns.ToggleOptions(true) end
    end })
    hub.optionsButton:SetPoint("RIGHT", hub.close, "LEFT", -10, 0)

    hub.tabsRow = CreateFrame("Frame", nil, hub)
    hub.tabsRow:SetPoint("TOPLEFT", PAD, -78)
    hub.tabsRow:SetPoint("TOPRIGHT", -PAD, -78)
    hub.tabsRow:SetHeight(30)
    for _, t in ipairs(order) do
        t.button = UI.Button(hub.tabsRow, { onClick = function() Hub.Show(t.key) end })
    end

    hub.content = CreateFrame("Frame", nil, hub)
    hub.content:SetPoint("TOPLEFT", PAD, -118)
    hub.content:SetPoint("BOTTOMRIGHT", -PAD, 30)

    hub.updated = UI.Text(hub, "GameFontDisableSmall")
    hub.updated:SetPoint("BOTTOMRIGHT", -PAD - 4, 12)

    hub:SetScript("OnShow", function()
        Hub.Refresh()
    end)
    hub:SetScript("OnHide", function()
        local t = tabs[current]
        if t and t.panel then t.panel:Hide() end -- the panel goes with the window (its own state too)
        if ns.OnHubHidden then ns.OnHubHidden() end
        if activityWin then activityWin:Hide() end
    end)
    hub:Hide()
end

-- Opens the window on that tab (default: the last one)
function Hub.Show(key)
    db = db or (ns.GetDB and ns.GetDB())
    if not db then return end
    if not hub then Create() end
    key = tabs[key] and key or current or (db.hubTab and tabs[db.hubTab] and db.hubTab) or "guild"
    for k, t in pairs(tabs) do
        if k ~= key and t.panel then t.panel:Hide() end
    end
    current = key
    db.hubTab = key
    local t = tabs[key]
    if t and not t.panel then
        t.panel = t.build(hub.content)
    end
    hub:Show()
    if t and t.panel then t.panel:Show() end
    Hub.Refresh()
end

-- A tab's panel once built (tests)
function Hub.Panel(key)
    return tabs[key] and tabs[key].panel
end

function Hub.Hide()
    if hub then hub:Hide() end
end

function Hub.IsShown(key)
    return hub and hub:IsShown() and (key == nil or key == current) or false
end

-- Toggle: open on that tab, or close when it is already the one shown
function Hub.Toggle(key)
    if Hub.IsShown(key) then Hub.Hide() else Hub.Show(key) end
end

-------------------------------------------------------------------------------
-- Shared bits of the bot's tabs
-------------------------------------------------------------------------------

local function Box(parent)
    local f = CreateFrame("Frame", nil, parent)
    UI.Panel(f)
    return f
end

-- Message when the bot's data is not there (no companion, too old, player unknown to the bot)
local function NoData(panel)
    panel.noData = UI.Text(panel, "GameFontHighlight", UI.MUTED)
    panel.noData:SetPoint("CENTER", 0, 10)
    panel.noData:SetWidth(560)
    panel.noData:SetJustifyH("CENTER")
    panel.noData:SetSpacing(4)
end

local function ShowNoData(panel, missing)
    panel.noData:SetText(missing and L("hub_no_data") or "")
    panel.noData:SetShown(missing)
    if panel.body then panel.body:SetShown(not missing) end
end

-- An item with a name, a progress text, a bar and a line under it (achievements, challenges)
local function ProgressItem(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(58)
    f.name = UI.Text(f, "GameFontNormal", UI.CREAM)
    f.name:SetPoint("TOPLEFT", 0, 0)
    f.count = UI.Text(f, "GameFontHighlight", UI.MUTED)
    f.count:SetPoint("TOPRIGHT", 0, 0)
    f.count:SetJustifyH("RIGHT")
    f.bar = UI.Bar(f, 12)
    f.bar:SetPoint("TOPLEFT", 0, -20)
    f.bar:SetPoint("TOPRIGHT", 0, -20)
    f.desc = UI.Text(f, "GameFontHighlightSmall", UI.MUTED)
    f.desc:SetPoint("TOPLEFT", 0, -38)
    f.desc:SetPoint("TOPRIGHT", 0, -38)
    f.desc:SetWordWrap(false)
    return f
end

local function DayMonth(at)
    return date("%d/%m", at)
end

-------------------------------------------------------------------------------
-- Hauts faits: titles, achievements count, the next ones, rank at the bank
-------------------------------------------------------------------------------

local function BuildTitles(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    NoData(panel)
    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetAllPoints()

    local left = Box(panel.body)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", panel.body, "BOTTOM", -8, 0)
    panel.titlesCap = UI.Caption(left, 15)
    panel.titlesCap:SetPoint("TOPLEFT", 16, -14)
    panel.titleLines = {}
    for i = 1, 3 do
        local row = left:CreateFontString(nil, "OVERLAY")
        UI.TitleFont(row, 19)
        row:SetPoint("TOPLEFT", 16, -42 - (i - 1) * 34)
        row:SetPoint("RIGHT", -16, 0)
        row:SetJustifyH("LEFT")
        row:SetWordWrap(false)
        panel.titleLines[i] = row
    end
    panel.trophiesCap = UI.Caption(left, 15)
    panel.trophiesCap:SetPoint("TOPLEFT", 16, -160)
    panel.trophies = left:CreateFontString(nil, "OVERLAY")
    UI.TitleFont(panel.trophies, 30)
    panel.trophies:SetPoint("TOPLEFT", 16, -184)
    panel.trophiesBar = UI.Bar(left, 12)
    panel.trophiesBar:SetPoint("TOPLEFT", 16, -230)
    panel.trophiesBar:SetPoint("TOPRIGHT", -16, -230)
    panel.rankCap = UI.Caption(left, 15)
    panel.rankCap:SetPoint("TOPLEFT", 16, -268)
    panel.rank = left:CreateFontString(nil, "OVERLAY")
    UI.TitleFont(panel.rank, 30)
    panel.rank:SetPoint("TOPLEFT", 16, -292)
    panel.rankText = UI.Text(left, "GameFontHighlight", UI.MUTED)
    panel.rankText:SetPoint("LEFT", panel.rank, "RIGHT", 10, -2)
    panel.rankText:SetPoint("RIGHT", -16, 0)

    local right = Box(panel.body)
    right:SetPoint("TOPLEFT", panel.body, "TOP", 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.nextCap = UI.Caption(right, 15)
    panel.nextCap:SetPoint("TOPLEFT", 16, -14)
    panel.next = {}
    for i = 1, 3 do
        local item = ProgressItem(right)
        item:SetPoint("TOPLEFT", 16, -44 - (i - 1) * 76)
        item:SetPoint("RIGHT", -16, 0)
        panel.next[i] = item
    end
    panel.nextNone = UI.Text(right, "GameFontHighlight", UI.MUTED)
    panel.nextNone:SetPoint("TOPLEFT", 16, -48)
    panel.nextNone:SetPoint("RIGHT", -16, 0)
    return panel
end

local function RefreshTitles(panel)
    local data = Hub.Data()
    ShowNoData(panel, not data)
    if not data then return end
    local titles = type(data.titles) == "table" and data.titles or {}
    panel.titlesCap:SetText(L("hub_titles"))
    for i, key in ipairs({ "bank", "follow", "craft" }) do
        local t = titles[key]
        local value = type(t) == "string" and t ~= "" and t or nil
        panel.titleLines[i]:SetText(L("hub_title_" .. key, value or ("|cff9b968b" .. L("hub_title_none") .. "|r")))
    end
    local got, total = tonumber(data.trophies) or 0, tonumber(data.trophiesTotal) or 0
    panel.trophiesCap:SetText(L("hub_trophies_cap"))
    panel.trophies:SetText(L("hub_trophies", got, total))
    panel.trophiesBar:SetValue(total > 0 and got / total or 0)
    panel.rankCap:SetText(L("hub_rank_cap"))
    local rank, of, move = tonumber(data.rank) or 0, tonumber(data.rankOf) or 0, tonumber(data.rankMove) or 0
    if rank > 0 then
        panel.rank:SetText(L("hub_rank", rank))
        local moveText = move > 0 and ("  |cff4fd04f" .. L("hub_rank_up", move) .. "|r")
            or move < 0 and ("  |cffff6060" .. L("hub_rank_down", -move) .. "|r") or ""
        panel.rankText:SetText(L("hub_rank_of", of) .. moveText)
    else
        panel.rank:SetText("-")
        panel.rankText:SetText(L("hub_rank_none"))
    end
    panel.nextCap:SetText(L("hub_next"))
    local list = type(data.next) == "table" and data.next or {}
    for i, item in ipairs(panel.next) do
        local a = list[i]
        if type(a) == "table" then
            item.name:SetText(tostring(a.name or "?"))
            item.count:SetText(tostring(a.progress or ""))
            item.desc:SetText(tostring(a.desc or ""))
            item.bar:SetValue(tonumber(a.share) or 0)
            item:Show()
        else
            item:Hide()
        end
    end
    panel.nextNone:SetText(#list == 0 and L("hub_next_none") or "")
end

-------------------------------------------------------------------------------
-- Activités: the next outings (made on Discord). A click opens the activity: date, organizer, levels,
-- the group, and signing up with the character played (dungeon: with a role), or leaving. The sign-up
-- goes to the bot through the companion (2|A|...); until the bot's list says so, shown here at once
-- (db.activitiesLocal).
--   2|A|id|name|realm|guild|level|class|time|battletag|action|activity|role
--   action: join or leave; activity: the id of its Discord card; role: tank, heal, dps (dungeon) or empty
-------------------------------------------------------------------------------

local EVENT_H = 64
local GROUP_SIZE = 5
local ROLES = { "tank", "heal", "dps" }
local ROLE_SLOTS = { tank = 1, heal = 1, dps = 3 }
-- roles each class can take (the bot's rule, activity.js)
local CLASS_ROLES = {
    WARRIOR = { tank = true, dps = true }, PALADIN = { tank = true, heal = true, dps = true },
    DRUID = { tank = true, heal = true, dps = true }, PRIEST = { heal = true, dps = true },
    SHAMAN = { heal = true, dps = true }, HUNTER = { dps = true }, ROGUE = { dps = true }, MAGE = { dps = true },
    WARLOCK = { dps = true },
}

local function ActivityActions()
    if not db then return {} end
    if type(db.activitiesLocal) ~= "table" then db.activitiesLocal = {} end
    return db.activitiesLocal
end

-- The activity as this player sees it: signed up or not, with what was just done here
function Hub.ActivityState(e)
    local a = ActivityActions()[e.id]
    local joined, role, pending = e.joined == true, e.myRole or "", false
    if a then
        local done = (a.action == "join") == joined
        if done or time() - (a.at or 0) > 86400 then
            ActivityActions()[e.id] = nil
        else
            joined, role, pending = a.action == "join", a.role or "", true
        end
    end
    return joined, role, pending
end

function Hub.ActivityPayload(action, id, role)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    local now = time()
    return table.concat({ "2", "A", name .. "-" .. realm .. ":A:" .. id .. ":" .. action .. ":" .. now, name, realm, guild,
        UnitLevel("player"), classFile or "", now, battleTag, action, id, role or "" }, "|")
end

-- Sign up (role for a dungeon) or leave. Returns the payload sent
function Hub.SignUp(e, action, role)
    if not (db and e and e.id) then return nil end
    ActivityActions()[e.id] = { action = action, role = role or "", at = time() }
    local payload = Hub.ActivityPayload(action, e.id, role)
    ns.AddToOutbox(payload)
    if ns.QueueStrip then ns.QueueStrip(payload) end
    return payload
end

local function RoleLabel(role)
    return role ~= "" and L("role_" .. role) or ""
end

local function DayText(at)
    local days = { strsplit(",", L("hub_days")) }
    local t = date("*t", at)
    return (days[t.wday] or "") .. " " .. date("%d/%m", at) .. " · " .. date("%H:%M", at)
end

local function Until(at)
    local diff = (at or 0) - time()
    if diff <= 3600 then return L("hub_event_soon") end
    if diff < 86400 then return L("hub_event_in_hours", math.floor(diff / 3600)) end
    return L("hub_event_in_days", math.floor(diff / 86400))
end

local function RefreshActivity()
    local w = activityWin
    local e = w and w.event
    if not (e and w:IsShown()) then return end
    local title = tostring(e.title or "")
    w.ribbon:SetText(title ~= "" and title or tostring(e.label or "?"))
    w.when:SetText(DayText(e.at) .. "  ·  " .. Until(e.at))
    w.chip:SetText(tostring(e.label or ""))
    local lines = { L("act_by", tostring(e.by or "?")) }
    if (e.level or "") ~= "" then lines[#lines + 1] = L("act_levels", e.level) end
    if (tonumber(e.levelMin) or 0) > 0 then lines[#lines + 1] = L("act_level_min", e.levelMin) end
    w.info:SetText(table.concat(lines, "\n"))

    -- the group: by role for a dungeon (slots), else numbered
    local group = {}
    for _, g in ipairs(type(e.group) == "table" and e.group or {}) do
        local name, role, level = strsplit(";", tostring(g))
        group[#group + 1] = { name = name or "?", role = role or "", level = level or "" }
    end
    w.groupCap:SetText(L("act_group", #group, tonumber(e.size) or GROUP_SIZE))
    local out = {}
    local function Line(m)
        return m and ("|cfff6deb0" .. m.name .. "|r" .. (m.level ~= "" and ("  |cff9b968b" .. L("hub_event_level", m.level) .. "|r") or ""))
            or "|cff6f6a60—|r"
    end
    if e.type == "donjon" then
        for _, role in ipairs(ROLES) do
            local taken = {}
            for _, m in ipairs(group) do if m.role == role then taken[#taken + 1] = m end end
            for slot = 1, ROLE_SLOTS[role] do
                out[#out + 1] = "|cffffd36b" .. RoleLabel(role) .. "|r  " .. Line(taken[slot])
            end
        end
    else
        for slot = 1, GROUP_SIZE do out[#out + 1] = slot .. ".  " .. Line(group[slot]) end
    end
    w.group:SetText(table.concat(out, "\n"))

    -- this character: sign up (with a role for a dungeon) or leave
    local joined, myRole, pending = Hub.ActivityState(e)
    local name = ns.Identity() or "?"
    local level = UnitLevel and UnitLevel("player") or 0
    local _, classFile = UnitClass("player")
    local allowed = CLASS_ROLES[classFile or ""] or { tank = true, heal = true, dps = true }
    local free = type(e.free) == "table" and e.free or {}
    local full = (tonumber(e.members) or 0) >= (tonumber(e.size) or GROUP_SIZE)
    local tooLow = (tonumber(e.levelMin) or 0) > level
    local dungeon = e.type == "donjon"
    for _, role in ipairs(ROLES) do
        local b = w.roles[role]
        b:SetShown(dungeon and not joined)
        b:SetLabel(RoleLabel(role))
        local ok = allowed[role] and (tonumber(free[role]) or 0) > 0
        if ok then b:Enable() else b:Disable() end
        if chosenRole == role and not ok then chosenRole = nil end
        b:SetVariant(chosenRole == role and "red" or "gold")
    end
    if dungeon and not chosenRole then
        local only
        for _, role in ipairs(ROLES) do
            if allowed[role] and (tonumber(free[role]) or 0) > 0 then only = only and "many" or role end
        end
        if only and only ~= "many" then chosenRole = only end -- one possible role: chosen at once
        for _, role in ipairs(ROLES) do w.roles[role]:SetVariant(chosenRole == role and "red" or "gold") end
    end

    local status
    if joined then
        status = L(pending and "act_joined_pending" or "act_joined", myRole ~= "" and (" (" .. RoleLabel(myRole) .. ")") or "")
        w.action:SetLabel(L("act_leave"))
        w.action:SetVariant("dark")
        w.action:Enable()
    else
        w.action:SetLabel(L("act_join", name, level))
        w.action:SetVariant("gold")
        if full then
            status = L("act_full")
        elseif tooLow then
            status = L("act_too_low", e.levelMin)
        elseif dungeon and not chosenRole then
            status = L("act_pick_role")
        else
            status = pending and L("act_left_pending") or ""
        end
        if full or tooLow or (dungeon and not chosenRole) then w.action:Disable() else w.action:Enable() end
    end
    w.status:SetText(status)
end

local function CreateActivityWindow()
    local w = CreateFrame("Frame", "WallOfShameForeverActivity", UIParent)
    w:SetSize(480, 470)
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    UI.Window(w)
    UI.Movable(w, db, "activityPosition")
    UI.Appear(w, db)
    tinsert(UISpecialFrames, "WallOfShameForeverActivity")
    w.ribbon = UI.Ribbon(w, 18)
    w.ribbon:SetPoint("TOP", 0, 14)
    w.close = UI.Close(w, function() w:Hide() end)
    w.close:SetPoint("TOPRIGHT", -24, -24)
    w.chip = UI.Chip(w, "dark")
    w.chip:SetPoint("TOPLEFT", 34, -46)
    w.when = UI.Caption(w, 15)
    w.when:SetPoint("LEFT", w.chip, "RIGHT", 10, 0)
    w.info = UI.Text(w, "GameFontHighlight")
    w.info:SetPoint("TOPLEFT", 34, -76)
    w.info:SetPoint("RIGHT", -34, 0)
    w.info:SetSpacing(4)
    local box = CreateFrame("Frame", nil, w)
    box:SetPoint("TOPLEFT", 28, -140)
    box:SetPoint("TOPRIGHT", -28, -140)
    box:SetHeight(170)
    UI.Panel(box)
    w.groupCap = UI.Caption(box, 15)
    w.groupCap:SetPoint("TOPLEFT", 14, -12)
    w.group = UI.Text(box, "GameFontHighlight")
    w.group:SetPoint("TOPLEFT", 14, -36)
    w.group:SetPoint("RIGHT", -14, 0)
    w.group:SetSpacing(5)
    w.roles = {}
    local prev
    for _, role in ipairs(ROLES) do
        local b = UI.Button(w, { width = 90, onClick = function()
            chosenRole = role
            RefreshActivity()
        end })
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", 34, -326) end
        w.roles[role] = b
        prev = b
    end
    w.status = UI.Text(w, "GameFontHighlight", UI.MUTED)
    w.status:SetPoint("TOPLEFT", 34, -366)
    w.status:SetPoint("RIGHT", -34, 0)
    w.action = UI.Button(w, { width = 300, onClick = function()
        local e = w.event
        if not e then return end
        local joined = Hub.ActivityState(e)
        if joined then
            Hub.SignUp(e, "leave")
            ns.Print(L("act_left_sent", tostring(e.title ~= "" and e.title or e.label)))
        else
            Hub.SignUp(e, "join", e.type == "donjon" and chosenRole or "")
            ns.Print(L("act_join_sent", tostring(e.title ~= "" and e.title or e.label)))
        end
        RefreshActivity()
        Hub.Refresh()
    end })
    w.action:SetPoint("BOTTOM", 0, 52)
    w.hint = UI.Text(w, "GameFontHighlightSmall", UI.MUTED)
    w.hint:SetPoint("BOTTOM", 0, 26)
    w:SetScript("OnShow", RefreshActivity)
    w:Hide()
    activityWin = w
end

-- Opens an activity's window (tests: Hub.ActivityWindow())
function Hub.ShowActivity(e)
    if not db then return end
    if not activityWin then CreateActivityWindow() end
    if activityWin.event ~= e then chosenRole = nil end
    activityWin.event = e
    activityWin.hint:SetText(L("act_hint"))
    activityWin:Show()
    RefreshActivity()
end

function Hub.ActivityWindow()
    return activityWin
end

local function BuildEvents(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    NoData(panel)
    panel.body = Box(panel)
    panel.body:SetAllPoints()
    panel.cap = UI.Caption(panel.body, 15)
    panel.cap:SetPoint("TOPLEFT", 16, -14)
    panel.rows = {}
    for i = 1, 6 do
        local r = CreateFrame("Button", nil, panel.body)
        r:SetHeight(EVENT_H - 8)
        r:SetPoint("TOPLEFT", 16, -42 - (i - 1) * EVENT_H)
        r:SetPoint("RIGHT", -16, 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.08)
        r:SetScript("OnClick", function(self)
            if self.event then
                UI.ClickSound()
                Hub.ShowActivity(self.event)
            end
        end)
        r.when = UI.Button(r, { width = 92, height = 44, size = 13 })
        r.when:SetPoint("LEFT", 0, 0)
        r.when:EnableMouse(false)
        r.when.label:SetSpacing(2)
        r.title = UI.Text(r, "GameFontNormalLarge", UI.CREAM)
        r.title:SetPoint("TOPLEFT", r.when, "TOPRIGHT", 14, -4)
        r.chip = UI.Chip(r, "dark")
        r.chip:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
        r.joined = UI.Chip(r, "red")
        r.joined:SetPoint("LEFT", r.chip, "RIGHT", 6, 0)
        r.by = UI.Text(r, "GameFontHighlight", UI.MUTED)
        r.by:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -6)
        r.left = UI.Text(r, "GameFontHighlightSmall", UI.MUTED)
        r.left:SetPoint("RIGHT", 0, 8)
        r.left:SetJustifyH("RIGHT")
        r.more = UI.Caption(r, 13)
        r.more:SetPoint("RIGHT", 0, -10)
        r.line = UI.Line(r)
        r.line:SetPoint("BOTTOMLEFT", 0, -4)
        r.line:SetPoint("BOTTOMRIGHT", 0, -4)
        panel.rows[i] = r
    end
    panel.none = UI.Text(panel.body, "GameFontHighlight", UI.MUTED)
    panel.none:SetPoint("TOPLEFT", 16, -48)
    panel.hint = UI.Text(panel.body, "GameFontHighlightSmall", UI.MUTED)
    panel.hint:SetPoint("BOTTOMLEFT", 16, 14)
    return panel
end

local function RefreshEvents(panel)
    local data = Hub.Data()
    ShowNoData(panel, not data)
    if not data then return end
    panel.cap:SetText(L("hub_events"))
    panel.hint:SetText(L("hub_events_hint"))
    local days = { strsplit(",", L("hub_days")) }
    local list = type(data.activities) == "table" and data.activities or {}
    for i, r in ipairs(panel.rows) do
        local e = list[i]
        if type(e) == "table" and tonumber(e.at) then
            r.event = e
            local t = date("*t", e.at)
            r.when:SetLabel((days[t.wday] or "") .. "\n" .. date("%H:%M", e.at))
            local title = tostring(e.title or "")
            r.title:SetText(title ~= "" and title or tostring(e.label or "?"))
            r.chip:SetText(tostring(e.label or ""))
            r.chip:SetShown(title ~= "" and (e.label or "") ~= "")
            local joined = e.id and Hub.ActivityState(e)
            r.joined:SetText(L("act_joined_chip"))
            r.joined:SetShown(joined and true or false)
            local level = (e.level or "") ~= "" and (" · " .. L("hub_event_level", e.level)) or ""
            r.by:SetText(L("hub_event_by", tostring(e.by or "?"), tonumber(e.members) or 0) .. level)
            r.left:SetText(Until(e.at))
            r.more:SetText(e.id and L("act_more") or "")
            r:Show()
        else
            r.event = nil
            r:Hide()
        end
    end
    panel.none:SetText(#list == 0 and L("hub_events_none") or "")
    RefreshActivity()
end

-------------------------------------------------------------------------------
-- Objectifs: the bank goal and the guild challenges
-------------------------------------------------------------------------------

local function BuildGoals(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    NoData(panel)
    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetAllPoints()

    local bank = Box(panel.body)
    bank:SetPoint("TOPLEFT", 0, 0)
    bank:SetPoint("TOPRIGHT", 0, 0)
    bank:SetHeight(150)
    panel.bankCap = UI.Caption(bank, 15)
    panel.bankCap:SetPoint("TOPLEFT", 16, -14)
    panel.goal = UI.Text(bank, "GameFontNormalLarge", UI.CREAM)
    panel.goal:SetPoint("TOPLEFT", 16, -40)
    panel.amount = bank:CreateFontString(nil, "OVERLAY")
    UI.TitleFont(panel.amount, 18)
    panel.amount:SetPoint("TOPRIGHT", -16, -38)
    panel.bar = UI.Bar(bank, 18)
    panel.bar:SetPoint("TOPLEFT", 16, -70)
    panel.bar:SetPoint("TOPRIGHT", -16, -70)
    panel.marks = {}
    for i = 1, 4 do
        local m = UI.Text(bank, "GameFontHighlightSmall", UI.MUTED)
        panel.marks[i] = m
    end
    panel.mine = UI.Text(bank, "GameFontHighlight")
    panel.mine:SetPoint("BOTTOMLEFT", 16, 16)
    panel.record = UI.Text(bank, "GameFontHighlight")
    panel.record:SetPoint("BOTTOMRIGHT", -16, 16)
    panel.record:SetJustifyH("RIGHT")

    local ch = Box(panel.body)
    ch:SetPoint("TOPLEFT", bank, "BOTTOMLEFT", 0, -14)
    ch:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.chCap = UI.Caption(ch, 15)
    panel.chCap:SetPoint("TOPLEFT", 16, -14)
    panel.challenges = {}
    for i = 1, 4 do
        local item = ProgressItem(ch)
        item:SetPoint("TOPLEFT", 16, -42 - (i - 1) * 64)
        item:SetPoint("RIGHT", -16, 0)
        panel.challenges[i] = item
    end
    panel.chNone = UI.Text(ch, "GameFontHighlight", UI.MUTED)
    panel.chNone:SetPoint("TOPLEFT", 16, -46)
    return panel
end

local function RefreshGoals(panel)
    local data = Hub.Data()
    ShowNoData(panel, not data)
    if not data then return end
    local b = type(data.bank) == "table" and data.bank or {}
    panel.bankCap:SetText(L("hub_bank"))
    panel.goal:SetText(tostring(b.goal or ""))
    panel.amount:SetText(tostring(b.moneyText or "?") .. " / " .. tostring(b.targetText or "?"))
    panel.bar:SetValue(tonumber(b.share) or 0)
    local width = panel.bar:GetWidth() or 0
    local marks = type(b.milestones) == "table" and b.milestones or {}
    for i, m in ipairs(panel.marks) do
        local ms = marks[i]
        if type(ms) == "table" and tonumber(ms.percent) then
            m:SetText((ms.reached and "|cff4fd04f" or "") .. ms.percent .. " %" .. (ms.reached and "|r" or ""))
            m:ClearAllPoints()
            m:SetPoint("TOP", panel.bar, "BOTTOMLEFT", width * ms.percent / 100 - (ms.percent == 100 and 14 or 0), -4)
            m:Show()
        else
            m:Hide()
        end
    end
    panel.mine:SetText((b.mine or "") ~= "" and L("hub_bank_mine", b.mine) or "")
    panel.record:SetText((b.record or "") ~= "" and L("hub_bank_record", b.record) or "")

    panel.chCap:SetText(L("hub_challenges"))
    local list = type(data.challenges) == "table" and data.challenges or {}
    for i, item in ipairs(panel.challenges) do
        local c = list[i]
        if type(c) == "table" then
            item.name:SetText(tostring(c.title or "?"))
            item.count:SetText(tostring(c.progress or ""))
            item.bar:SetValue(tonumber(c.share) or 0)
            local when = c.upcoming and tonumber(c.starts) and L("hub_challenge_from", DayMonth(c.starts))
                or tonumber(c.ends) and L("hub_challenge_until", DayMonth(c.ends - 1)) or ""
            local reward = (c.reward or "") ~= "" and ("  ·  " .. L("hub_challenge_reward", c.reward)) or ""
            item.desc:SetText(when .. reward)
            item:Show()
        else
            item:Hide()
        end
    end
    panel.chNone:SetText(#list == 0 and L("hub_challenges_none") or "")
end

Hub.Register({ key = "titles", order = 30, label = function() return L("hub_tab_titles") end,
    build = BuildTitles, refresh = RefreshTitles })
Hub.Register({ key = "events", order = 40, label = function() return L("hub_tab_events") end,
    build = BuildEvents, refresh = RefreshEvents })
Hub.Register({ key = "goals", order = 50, label = function() return L("hub_tab_goals") end,
    build = BuildGoals, refresh = RefreshGoals })
