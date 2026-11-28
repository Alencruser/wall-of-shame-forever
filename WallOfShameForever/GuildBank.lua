-- Wall of Shame Forever: guild bank money log
-- When the guild bank opens, the addon asks the server for the money log ("Journal des richesses",
-- no click on the tab needed, and no tab-view right needed) and queues it for the bot, which merges
-- the readings of every guildmate and keeps each member's deposits and withdrawals:
--   2|B|id|name|realm|guild|level|class|time|battletag|money|lines
--   money: the bank's balance in copper (GetGuildBankMoney, empty if unknown)
--   lines: type:copper:years:months:days:hours:who, separated by ";", in the game's order (oldest
--   first). type as the game gives it ("deposit", "withdraw", "repair", ...), the age is relative to
--   time (the reading), who: the name the log shows (no realm for the reader's realm).
--   id: name-realm:B:time, a new one per reading.
-- A reading is queued only when the log changed since the last one queued for this guild (same
-- transactions in the same order: only their ages moved, nothing new for the bot).
-- Then the item tabs' logs (v0.9.4), one tab after the other (the server answers one query at a time),
-- for the guild score: an item deposited or withdrawn is worth part of its auction house price.
--   2|I|id|name|realm|guild|level|class|time|battletag|lines
--   lines: type:item:count:years:months:days:hours:who:price:age:tab, separated by ";", deposits and
--   withdrawals only (moves left out). price: Auctionator's price of one (copper, empty without
--   Auctionator or never seen), age: days since Auctionator saw it (empty if unknown or older than 21).
--   id: name-realm:I:time. Tabs the character can't see give nothing.
-- Loaded after WallOfShameForever.lua, which gives ns.GetDB, ns.Identity, ns.Clean, ns.AddToOutbox.

local ADDON_NAME, ns = ...
local GuildBank = {}
ns.GuildBank = GuildBank

local MAX_READINGS = 5   -- readings of this character waiting in the outbox (older ones dropped)
local QUERY_DELAY = 0.5  -- seconds after the bank opens (the game's bank UI loads on demand)
local READ_WINDOW = 60   -- seconds after a query: a log read later could be stale (ages moved)
local TAB_DELAY = 0.7    -- seconds between two item tab queries
local AUCTIONATOR_ID = "WallOfShameForever"

local db
local queriedAt

-------------------------------------------------------------------------------
-- Data: no frames here (tested with lupa, see companion/tests/test_guild_bank.py)
-------------------------------------------------------------------------------

-- The money log as the game gives it: { { type, who, copper, years, months, days, hours }, ... }
function GuildBank.ReadLog()
    if type(GetNumGuildBankMoneyTransactions) ~= "function" then return {} end
    local lines = {}
    for i = 1, GetNumGuildBankMoneyTransactions() or 0 do
        local kind, who, copper, years, months, days, hours = GetGuildBankMoneyTransaction(i)
        if kind and who then
            lines[#lines + 1] = { kind, who, copper or 0, years or 0, months or 0, days or 0, hours or 0 }
        end
    end
    return lines
end

-- Same transactions in the same order (ages left out: they move with time)
function GuildBank.Signature(lines)
    local list = {}
    for _, l in ipairs(lines) do list[#list + 1] = l[1] .. ":" .. l[3] .. ":" .. l[2] end
    return table.concat(list, ";")
end

function GuildBank.Payload(lines)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    local list = {}
    for _, l in ipairs(lines) do
        list[#list + 1] = table.concat({ ns.Clean(l[1]), l[3], l[4], l[5], l[6], l[7], ns.Clean(l[2]) }, ":")
    end
    local money = type(GetGuildBankMoney) == "function" and GetGuildBankMoney() or ""
    return table.concat({ "2", "B", name .. "-" .. realm .. ":B:" .. time(), name, realm, guild,
        UnitLevel("player"), classFile or "", time(), battleTag, money or "", table.concat(list, ";") }, "|")
end

-- Queues the log if it changed since the last reading queued for this guild. Returns true if queued.
function GuildBank.Queue(lines)
    if not (db and db.discord and db.connection) or #lines == 0 then return false end
    local name, realm, guild = ns.Identity()
    if guild == "" then return false end
    db.bankLogSent = type(db.bankLogSent) == "table" and db.bankLogSent or {}
    local signature = GuildBank.Signature(lines)
    if db.bankLogSent[guild] == signature then return false end
    -- only the latest readings of this character stay in the outbox: room for deaths and levels
    local prefix, mine = name .. "-" .. realm .. ":B:", {}
    for i, payload in ipairs(db.outbox) do
        if (select(3, strsplit("|", payload))):sub(1, #prefix) == prefix then mine[#mine + 1] = i end
    end
    for k = #mine - MAX_READINGS + 1, 1, -1 do table.remove(db.outbox, mine[k]) end
    ns.AddToOutbox(GuildBank.Payload(lines))
    db.bankLogSent[guild] = signature
    return true
end

-------------------------------------------------------------------------------
-- Item tabs (v0.9.4)
-------------------------------------------------------------------------------

-- Auctionator's price of one and its age in days (nil, nil without Auctionator or never seen)
function GuildBank.Price(link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemLink and type(link) == "string") then return nil, nil end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, AUCTIONATOR_ID, link)
    if not ok or type(price) ~= "number" or price <= 0 then return nil, nil end
    local okAge, age = pcall(api.GetAuctionAgeByItemLink, AUCTIONATOR_ID, link)
    return math.floor(price), okAge and type(age) == "number" and age or nil
end

-- Deposits and withdrawals of every item tab the game has the log of:
-- { { type, who, item, count, years, months, days, hours, price, age, tab }, ... }
function GuildBank.ReadItemLogs()
    local lines = {}
    if type(GetNumGuildBankTransactions) ~= "function" or type(GetNumGuildBankTabs) ~= "function" then return lines end
    for tab = 1, GetNumGuildBankTabs() or 0 do
        for i = 1, GetNumGuildBankTransactions(tab) or 0 do
            local kind, who, link, count, _, _, years, months, days, hours = GetGuildBankTransaction(tab, i)
            local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
            if (kind == "deposit" or kind == "withdraw") and who and item then
                local price, age = GuildBank.Price(link)
                lines[#lines + 1] = { kind, who, item, count or 1, years or 0, months or 0, days or 0, hours or 0, price, age, tab }
            end
        end
    end
    return lines
end

function GuildBank.ItemSignature(lines)
    local list = {}
    for _, l in ipairs(lines) do list[#list + 1] = l[11] .. ":" .. l[1] .. ":" .. l[3] .. ":" .. l[4] .. ":" .. l[2] end
    return table.concat(list, ";")
end

function GuildBank.ItemPayload(lines)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    local list = {}
    for _, l in ipairs(lines) do
        list[#list + 1] = table.concat({ l[1], l[3], l[4], l[5], l[6], l[7], l[8], ns.Clean(l[2]), l[9] or "", l[10] or "", l[11] }, ":")
    end
    return table.concat({ "2", "I", name .. "-" .. realm .. ":I:" .. time(), name, realm, guild,
        UnitLevel("player"), classFile or "", time(), battleTag, table.concat(list, ";") }, "|")
end

-- Same rules as the money log: only when it changed, at most MAX_READINGS of this character waiting
function GuildBank.QueueItems(lines)
    if not (db and db.discord and db.connection) or #lines == 0 then return false end
    local name, realm, guild = ns.Identity()
    if guild == "" then return false end
    db.bankItemsSent = type(db.bankItemsSent) == "table" and db.bankItemsSent or {}
    local signature = GuildBank.ItemSignature(lines)
    if db.bankItemsSent[guild] == signature then return false end
    local prefix, mine = name .. "-" .. realm .. ":I:", {}
    for i, payload in ipairs(db.outbox) do
        if (select(3, strsplit("|", payload))):sub(1, #prefix) == prefix then mine[#mine + 1] = i end
    end
    for k = #mine - MAX_READINGS + 1, 1, -1 do table.remove(db.outbox, mine[k]) end
    ns.AddToOutbox(GuildBank.ItemPayload(lines))
    db.bankItemsSent[guild] = signature
    return true
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

-- Item tabs one after the other, then read them all
local function QueryItemTab(tab)
    local tabs = type(GetNumGuildBankTabs) == "function" and GetNumGuildBankTabs() or 0
    if tab > tabs then
        C_Timer.After(TAB_DELAY, function() GuildBank.QueueItems(GuildBank.ReadItemLogs()) end)
        return
    end
    QueryGuildBankLog(tab)
    C_Timer.After(TAB_DELAY, function() QueryItemTab(tab + 1) end)
end

local function Query()
    -- the money log is the tab after the last item tab
    if type(QueryGuildBankLog) ~= "function" or not MAX_GUILDBANK_TABS then return end
    queriedAt = time()
    QueryGuildBankLog(MAX_GUILDBANK_TABS + 1)
    C_Timer.After(TAB_DELAY * 2, function() QueryItemTab(1) end)
end

local function OnBankOpened()
    C_Timer.After(QUERY_DELAY, Query)
end

local GUILD_BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({ "GUILDBANKFRAME_OPENED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "GUILDBANKLOG_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_LOGIN" then
        db = ns.GetDB and ns.GetDB()
    elseif event == "GUILDBANKFRAME_OPENED" then
        OnBankOpened()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if GUILD_BANKER and arg == GUILD_BANKER then OnBankOpened() end
    elseif event == "GUILDBANKLOG_UPDATE" then
        -- also fires for the item tabs' logs: the money log is read, unchanged ones are skipped
        if queriedAt and time() - queriedAt <= READ_WINDOW then GuildBank.Queue(GuildBank.ReadLog()) end
    end
end)
