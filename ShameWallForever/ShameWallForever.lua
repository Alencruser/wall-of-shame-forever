-- Shame Wall Forever: level-ups, deaths and guild roster for WoW Forever
-- Data travels through invisible addon messages on the guild channel.

local ADDON_NAME, ns = ...
local PREFIX = "SHAMEWALL" -- own network: does not talk to Memento Forever

local db
local playerName
local playerGUID
local rosterReady = false

local DEFAULTS = {
    announceGuild = true, -- post every own level-up in guild chat
    popups = true,        -- big on-screen banner
    selfBanner = true,    -- banner for own level-ups and deaths too
    sound = true,
    discord = true,       -- own deaths for the companion, once officers set the guild up
}
local MAX_OUTBOX = 200 -- WoW writes it only on /reload or logout: room for a PvP evening
local CODE_PATTERN = "swf1%.[%w_%-]+" -- bot connection code, see companion/connection.py

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffc9a227Shame Wall|r: " .. msg)
end

local function ShortName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:match("^[^-]+")) or name
end

local function ClassColored(name, classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return name end
    return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

local function Member(name)
    name = ShortName(name) -- one entry per player, with or without realm
    local m = db.members[name]
    if not m then
        m = { level = 0, deaths = 0 }
        db.members[name] = m
    end
    return m
end

local function AddLog(text)
    table.insert(db.log, 1, date("%d %b %H:%M") .. "  " .. text)
    while #db.log > 100 do table.remove(db.log) end
end

-------------------------------------------------------------------------------
-- WoW-style banners (level-up gold, death red), stacked at the top center
-------------------------------------------------------------------------------

local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
    DRUID = "Druid",
}
local SOUND_LEVEL = 888 -- LEVELUPSOUND
local SOUND_DEATH = 847 -- igQuestFailed
local SHOW_TIME, FADE_IN, FADE_OUT, POP = 5.0, 0.25, 0.8, 0.25
local MAX_BANNERS = 3

local bannerPool, activeBanners = {}, {}

local function LayoutBanners()
    for i, b in ipairs(activeBanners) do
        b:ClearAllPoints()
        b:SetPoint("TOP", UIParent, "TOP", 0, -90 - (i - 1) * 150)
    end
end

local function ReleaseBanner(b)
    b:Hide()
    b.inUse = false
    for i, other in ipairs(activeBanners) do
        if other == b then table.remove(activeBanners, i) break end
    end
    LayoutBanners()
end

local function BannerOnUpdate(b, elapsed)
    b.t = b.t + elapsed
    local t = b.t
    if t < FADE_IN then
        b:SetAlpha(t / FADE_IN)
    elseif t > SHOW_TIME then
        b:SetAlpha(math.max(0, 1 - (t - SHOW_TIME) / FADE_OUT))
    else
        b:SetAlpha(1)
    end
    -- short "pop": starts slightly larger and settles
    if t < POP then
        b:SetScale(1.15 - 0.15 * (t / POP))
    else
        b:SetScale(1)
    end
    -- shine over the banner that flashes briefly
    b.shine:SetAlpha(t < 0.7 and (1 - t / 0.7) * 0.6 or 0)
    if t > SHOW_TIME + FADE_OUT then ReleaseBanner(b) end
end

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local TITLE_FONT = MEDIA .. "Unifraktur.ttf"
-- Text position per banner (pixels in the 440x220 banner, from top left)
local LAYOUT = {
    level = { title = { 124, 89 }, sub = { 126, 116 } },
    death = { title = { 128, 97 }, sub = { 130, 124 } },
}

local function CreateBanner()
    local b = CreateFrame("Frame", nil, UIParent)
    b:SetSize(440, 220)
    b:SetFrameStrata("HIGH")

    b.art = b:CreateTexture(nil, "BACKGROUND")
    b.art:SetAllPoints()

    b.title = b:CreateFontString(nil, "OVERLAY")
    if not b.title:SetFont(TITLE_FONT, 26, "OUTLINE") then
        b.title:SetFont("Fonts\\MORPHEUS.TTF", 22, "OUTLINE") -- fallback if the font is missing
    end
    b.title:SetJustifyH("LEFT")

    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.sub:SetJustifyH("LEFT")

    -- flash on appearance: the banner itself, additively blended
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.shine:SetAllPoints()
    b.shine:SetBlendMode("ADD")

    b:SetScript("OnUpdate", BannerOnUpdate)
    b:Hide()
    table.insert(bannerPool, b)
    return b
end

local function BannerTexture(kind, classFile)
    if kind == "death" then return MEDIA .. "banners\\death" end
    -- The emblem is part of the artwork; unknown class -> warrior banner
    local key = (classFile and CLASS_NAMES[classFile]) and classFile:lower() or "warrior"
    return MEDIA .. "banners\\" .. key
end

local function ApplyLayout(b, kind, classFile)
    local L = LAYOUT[kind]
    local tex = BannerTexture(kind, classFile)
    b.art:SetTexture(tex)
    b.shine:SetTexture(tex)
    b.title:ClearAllPoints()
    b.title:SetPoint("TOPLEFT", L.title[1], -L.title[2])
    b.title:SetPoint("RIGHT", -60, 0)
    b.sub:ClearAllPoints()
    b.sub:SetPoint("TOPLEFT", L.sub[1], -L.sub[2])
    b.sub:SetPoint("RIGHT", -60, 0)
end

-- kind: "level" or "death"
local function ShowBanner(kind, name, classFile, level, zone)
    if db.popups then
        local b
        for _, pooled in ipairs(bannerPool) do
            if not pooled.inUse then b = pooled break end
        end
        b = b or CreateBanner()
        if #activeBanners >= MAX_BANNERS then ReleaseBanner(activeBanners[1]) end

        local zoneText = (zone and zone ~= "") and ("  -  " .. zone) or ""
        ApplyLayout(b, kind, classFile)

        if kind == "death" then
            b.title:SetText(name .. " has fallen")
            b.title:SetTextColor(0.94, 0.2, 0.16)
            b.sub:SetText("|cffe6dcd2Level " .. (level or "?") .. zoneText .. "|r")
        else
            b.title:SetText("Level " .. (level or "?") .. "!")
            b.title:SetTextColor(1, 0.82, 0.35)
            local className = classFile and CLASS_NAMES[classFile]
            b.sub:SetText(ClassColored(name, classFile)
                .. (className and (" |cffbbbbbb(" .. className .. ")|r") or "") .. zoneText)
        end

        b.t, b.inUse = 0, true
        b:SetAlpha(0)
        b:Show()
        table.insert(activeBanners, b)
        LayoutBanners()
    end
    if db.sound then
        pcall(PlaySound, kind == "death" and SOUND_DEATH or SOUND_LEVEL)
    end
end

-------------------------------------------------------------------------------
-- Without a guild: players who pasted the same code share a hidden private channel,
-- whose name and password are derived from the code
-------------------------------------------------------------------------------

local channelName

local function Hash(s, seed)
    local h = seed
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

local function UpdateChannel()
    -- db.guildName still set while not in a guild = leaving, see CheckGuildLeft
    local solo = not IsInGuild() and not db.guildName
    local wanted = (solo and db.connection) and ("SWF" .. Hash(db.connection, 7)) or nil
    if channelName and channelName ~= wanted then
        LeaveChannelByName(channelName)
        channelName = nil
    end
    if wanted and not channelName then
        JoinChannelByName(wanted, Hash(db.connection, 13))
        if ChatFrame_RemoveChannel then ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, wanted) end
        channelName = wanted
    end
end

-- Left the guild (also kicked while offline): the code goes away with it,
-- so the player no longer reaches the guild's bot
local function CheckGuildLeft()
    if IsInGuild() then
        db.guildName = GetGuildInfo("player") or db.guildName or ""
        return
    end
    if not db.guildName then return end
    C_Timer.After(10, function() -- guild data can arrive late right after login
        if IsInGuild() or not db.guildName then return end
        db.guildName = nil
        if db.connection then
            -- codeRemoved: a private companion build must never put its built-in code back
            -- (write_builtin_code in companion/shamewall_companion.py)
            db.connection, db.codeRemoved = nil, true
            Print("You left your guild: its Discord code was removed.")
        end
        UpdateChannel()
    end)
end

local function Send(msg)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    elseif channelName then
        local id = GetChannelName(channelName)
        if id and id > 0 then C_ChatInfo.SendAddonMessage(PREFIX, msg, "CHANNEL", id) end
    end
end

local function MyStatus()
    local _, classFile = UnitClass("player")
    return UnitLevel("player"), GetRealZoneText() or "", classFile or ""
end

local function RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

-------------------------------------------------------------------------------
-- Killer tracking: last damage taken, from the combat log
-------------------------------------------------------------------------------

local lastHit -- { name, guid, time }
local levelCache = {}
local KILLER_MEMORY = 30 -- seconds: an older hit is not the killer

-- Level of a unit the game can see (target, mouseover, nameplates); -1 = skull
local LEVEL_UNITS = { "target", "mouseover", "targettarget", "pettarget",
    "party1target", "party2target", "party3target", "party4target" }
local function FindUnitLevel(guid)
    if not guid then return nil end
    if levelCache[guid] then return levelCache[guid] end
    for _, unit in ipairs(LEVEL_UNITS) do
        if UnitGUID(unit) == guid then levelCache[guid] = UnitLevel(unit) return levelCache[guid] end
    end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitGUID(unit) == guid then levelCache[guid] = UnitLevel(unit) return levelCache[guid] end
    end
end

local OnKillingBlow -- leaderboard section, below

local function OnCombatLog()
    local _, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, dstFlags, _, envType = CombatLogGetCurrentEventInfo()
    if sub == "PARTY_KILL" and srcGUID == playerGUID then
        OnKillingBlow(dstGUID, dstName, dstFlags)
        return
    end
    if dstGUID ~= playerGUID then return end
    if sub == "ENVIRONMENTAL_DAMAGE" then
        lastHit = { name = envType or "Environment", time = GetTime() } -- Falling, Drowning, Lava...
    elseif sub == "SPELL_INSTAKILL" or (sub:find("_DAMAGE$") and srcName) then
        lastHit = { name = srcName, guid = srcGUID, time = GetTime() }
        FindUnitLevel(srcGUID) -- while it is still visible
    end
end

-- killer name and level ("" when unknown)
local function Killer()
    if not lastHit or GetTime() - lastHit.time > KILLER_MEMORY then return "", "" end
    local level = FindUnitLevel(lastHit.guid)
    return lastHit.name or "", level and tostring(level) or ""
end

local function KillerText(killer, killerLevel)
    if not killer or killer == "" then return "" end
    local level = tonumber(killerLevel)
    if not level then return ", killed by " .. killer end
    return ", killed by " .. killer .. " (level " .. (level < 0 and "??" or level) .. ")"
end

-------------------------------------------------------------------------------
-- Guild roster (window)
-------------------------------------------------------------------------------

local window, rows = nil, {}

local function FormatSeen(m)
    if m.online then return "|cff00ff00online|r" end
    if not m.lastSeen then return "-" end
    local diff = time() - m.lastSeen
    if diff < 3600 then return math.floor(diff / 60) .. " min" end
    if diff < 86400 then return math.floor(diff / 3600) .. " h" end
    return math.floor(diff / 86400) .. " d"
end

local function RefreshWindow()
    if not window or not window:IsShown() then return end

    local list = {}
    for name, m in pairs(db.members) do
        if m.inGuild ~= false then
            table.insert(list, { name = name, m = m })
        end
    end
    table.sort(list, function(a, b)
        if a.m.level ~= b.m.level then return a.m.level > b.m.level end
        return a.name < b.name
    end)

    local child = window.scroll:GetScrollChild()
    for i, entry in ipairs(list) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, child)
            row:SetSize(500, 16)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
            row.cols = {}
            local x = { 0, 150, 195, 345, 425 }
            local w = { 145, 40, 145, 75, 60 }
            for c = 1, 5 do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("LEFT", x[c], 0)
                fs:SetWidth(w[c])
                fs:SetJustifyH("LEFT")
                row.cols[c] = fs
            end
            rows[i] = row
        end
        local m = entry.m
        local addonMark = m.hasAddon and " |cff33ff99*|r" or ""
        row.cols[1]:SetText(ClassColored(ShortName(entry.name), m.class) .. addonMark)
        row.cols[2]:SetText(m.level > 0 and m.level or "?")
        row.cols[3]:SetText(m.zone or "")
        row.cols[4]:SetText(FormatSeen(m))
        row.cols[5]:SetText(m.deaths and m.deaths > 0
            and (m.deaths .. (m.deaths == 1 and " death" or " deaths")) or "")
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    child:SetHeight(math.max(1, #list * 16))
    window.count:SetText(#list .. " members  (|cff33ff99*|r = has the addon)")
end

local function CreateWindow()
    window = CreateFrame("Frame", "ShameWallForeverFrame", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(540, 400)
    window:SetPoint("CENTER")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "ShameWallForeverFrame") -- closes with Escape

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.title:SetPoint("TOP", 0, -6)
    window.title:SetText("Shame Wall Forever")

    local headers = { "Name", "Lvl", "Zone", "Last seen", "Deaths" }
    local x = { 0, 150, 195, 345, 425 }
    for c = 1, 5 do
        local h = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", 16 + x[c], -32)
        h:SetText(headers[c])
    end

    window.scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    window.scroll:SetPoint("TOPLEFT", 16, -50)
    window.scroll:SetPoint("BOTTOMRIGHT", -32, 30)
    local child = CreateFrame("Frame", nil, window.scroll)
    child:SetSize(500, 1)
    window.scroll:SetScrollChild(child)

    window.count = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.count:SetPoint("BOTTOMLEFT", 16, 10)

    window:SetScript("OnShow", function()
        RequestRoster()
        RefreshWindow()
    end)
    window:Hide()
end

local function ToggleWindow()
    if not window then CreateWindow() end
    if window:IsShown() then window:Hide() else window:Show() end
end

-------------------------------------------------------------------------------
-- Events: level-up, death, messages
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Outbox for the companion (SavedVariables). Payloads: see companion/events.py
--   2|D|id|name|realm|guild|level|class|zone|killer|killerLevel|time|battletag
--   2|L|id|name|realm|guild|level|class|time|battletag|up|zone   (up: 1 = level-up, 0 = login)
-------------------------------------------------------------------------------

-- The battletag lets the bot find the Discord member (its battletag directory)
local function Identity()
    local name, realm = UnitFullName("player")
    realm = realm or GetNormalizedRealmName() or ""
    local battleTag = BNGetInfo and select(2, BNGetInfo()) or ""
    return name, realm, GetGuildInfo("player") or "", battleTag or ""
end

local function OutboxId(payload)
    return select(3, strsplit("|", payload))
end

local function AddToOutbox(payload)
    local id = OutboxId(payload)
    for _, queued in ipairs(db.outbox) do
        if OutboxId(queued) == id then return end
    end
    table.insert(db.outbox, payload)
    while #db.outbox > MAX_OUTBOX do table.remove(db.outbox, 1) end
end

local function DeathPayload(id, level, zone, classFile, killer, killerLevel)
    local name, realm, guild, battleTag = Identity()
    return table.concat({ "2", "D", id, name, realm, guild, level, classFile, zone, killer, killerLevel,
        time(), battleTag }, "|")
end

local function LevelPayload(id, level, up)
    local name, realm, guild, battleTag = Identity()
    local _, classFile = UnitClass("player")
    return table.concat({ "2", "L", id, name, realm, guild, level, classFile or "", time(), battleTag,
        up and "1" or "0", GetRealZoneText() or "" }, "|")
end

-- Current level for the bot, which keeps the highest level per class (battletag directory,
-- /activite) and posts real level-ups (up). Only the latest level of this character stays in
-- the outbox; the login snapshot never replaces a level-up of the same level.
local function QueueLevel(level, up)
    if not (db.discord and db.connection) then return end
    local name, realm = Identity()
    local prefix = name .. "-" .. realm .. ":L"
    for i = #db.outbox, 1, -1 do
        local id = OutboxId(db.outbox[i])
        if id:sub(1, #prefix) == prefix and id ~= prefix .. level then table.remove(db.outbox, i) end
    end
    local payload = LevelPayload(prefix .. level, level, up)
    AddToOutbox(payload)
    if up then ns.ShowStrip(payload) end -- posted right away, like a death
end

local function OnOwnLevelUp(newLevel)
    local _, zone, classFile = MyStatus()
    local me = Member(playerName)
    me.level, me.zone, me.class, me.hasAddon = newLevel, zone, classFile, true
    Send(table.concat({ "L", newLevel, zone, classFile }, "|"))
    AddLog("You reached level " .. newLevel)
    if db.announceGuild and IsInGuild() then
        SendChatMessage(ShortName(playerName) .. " has reached level " .. newLevel .. "!", "GUILD")
    end
    if db.selfBanner then
        ShowBanner("level", ShortName(playerName), classFile, newLevel, zone)
    end
    QueueLevel(newLevel, true)
end

-- Own death for the companion: outbox in SavedVariables + strip on screen.
-- Only the player who dies reports it; guildmates never send others' deaths.
local function QueueForDiscord(level, zone, classFile, killer, killerLevel)
    local name, realm = Identity()
    local payload = DeathPayload(name .. "-" .. realm .. ":" .. time(), level, zone, classFile, killer, killerLevel)
    AddToOutbox(payload)
    ns.ShowStrip(payload)
end

-------------------------------------------------------------------------------
-- Leaderboard (bot's ranking channel): duels won against guildmates, killing blows on
-- players of the other faction. Each player reports only their own wins.
--   2|W|id|name|realm|guild|level|class|time|battletag|opponent|zone   (also on the strip)
--   2|K|id|name|realm|guild|level|class|time|battletag|victim|victimLevel|victimClass|zone
-------------------------------------------------------------------------------

local scoreCount = 0

local function ScorePayload(id, kind, fields)
    local name, realm, guild, battleTag = Identity()
    local _, classFile = UnitClass("player")
    local payload = { "2", kind, id, name, realm, guild, UnitLevel("player"), classFile or "", time(), battleTag }
    for _, field in ipairs(fields) do payload[#payload + 1] = field end
    return table.concat(payload, "|")
end

-- Returns the payload, or nil when the guild is not set up for Discord
local function QueueScore(kind, fields)
    if not (db.discord and db.connection) then return nil end
    local name, realm = Identity()
    scoreCount = scoreCount + 1
    local payload = ScorePayload(name .. "-" .. realm .. ":" .. kind .. time() .. "." .. scoreCount, kind, fields)
    AddToOutbox(payload)
    return payload
end

-- Duel system message ("%1$s has defeated %2$s in a duel", localized) as a Lua pattern;
-- order: which format argument each capture is (1 = winner, 2 = loser)
local function FormatPattern(format)
    if type(format) ~= "string" then return nil end
    local order = {}
    local pattern = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%(%d)%%%$s", function(n)
        order[#order + 1] = tonumber(n)
        return "(.+)"
    end)
    pattern = pattern:gsub("%%s", function()
        order[#order + 1] = #order + 1
        return "(.+)"
    end)
    return "^" .. pattern .. "$", order
end

local function DuelResult(msg)
    for _, format in ipairs({ DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT }) do
        local pattern, order = FormatPattern(format)
        if pattern then
            local captures = { msg:match(pattern) }
            if #captures == 2 then
                local byArg = {}
                for i, arg in ipairs(order) do byArg[arg] = captures[i] end
                return byArg[1], byArg[2]
            end
        end
    end
end

-- Guildmate: in the guild roster; without a guild yet, a player sharing our code (private channel)
local function IsGuildmate(name)
    local m = name and db.members[ShortName(name)]
    if not m or m.inGuild == false or ShortName(name) == ShortName(playerName) then return false end
    return IsInGuild() or m.hasAddon == true
end

local function OnSystemMessage(msg)
    local winner, loser = DuelResult(msg or "")
    if not winner or ShortName(winner) ~= ShortName(playerName) or not IsGuildmate(loser) then return end
    -- on the strip too: posted right away, with a screenshot of the winner's screen
    local payload = QueueScore("W", { ShortName(loser), GetRealZoneText() or "" })
    if payload then ns.ShowStrip(payload) end
    AddLog("You won a duel against " .. ShortName(loser))
end

-- Killing blow on a hostile player (the other faction)
OnKillingBlow = function(guid, victim, flags)
    if not (guid and guid:find("^Player%-")) then return end
    local hostile = COMBATLOG_OBJECT_REACTION_HOSTILE and bit and bit.band(flags or 0, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
    if not hostile then return end
    local _, victimClass = GetPlayerInfoByGUID(guid)
    local level = FindUnitLevel(guid)
    QueueScore("K", { ShortName(victim) or "", level and tostring(level) or "", victimClass or "", GetRealZoneText() or "" })
    AddLog("Killing blow on " .. (ShortName(victim) or "?"))
end

local function OnOwnDeath()
    local level, zone, classFile = MyStatus()
    local killer, killerLevel = Killer()
    lastHit = nil
    local me = Member(playerName)
    me.deaths = (me.deaths or 0) + 1
    -- killer fields at the end: older versions just ignore them
    Send(table.concat({ "D", level, zone, classFile, me.deaths, killer, killerLevel }, "|"))
    AddLog("You died (level " .. level .. ", " .. zone .. KillerText(killer, killerLevel) .. ")")
    if db.selfBanner then
        ShowBanner("death", ShortName(playerName), classFile, level, zone)
    end
    if db.discord and db.connection then
        QueueForDiscord(level, zone, classFile, killer, killerLevel)
    end
end

-- The bot's connection code for the companion, read from the guild information text:
-- only officers can edit it, every member can read it, so players have nothing to set up.
local function ReadConnection()
    local code = GetGuildInfoText and (GetGuildInfoText() or ""):match(CODE_PATTERN)
    if code and code ~= db.connection then
        local first = db.connection == nil
        db.connection, db.codeRemoved = code, nil
        if first and db.discord then Print("Discord deaths are set up for your guild.") end
        QueueLevel(UnitLevel("player"))
    end
end

local function OnAddonMessage(text, sender)
    if not sender then return end
    local isSelf = ShortName(sender) == ShortName(playerName)

    local kind, a, b, c, d, e, f = strsplit("|", text)
    local m = Member(sender)
    m.hasAddon, m.online, m.lastSeen, m.inGuild = true, true, time(), true

    if kind == "H" then
        -- Someone logged in and asks for the current state: reply after a short delay
        if not isSelf then
            C_Timer.After(math.random() * 5, function()
                local level, zone, classFile = MyStatus()
                Send(table.concat({ "S", level, zone, classFile, Member(playerName).deaths or 0 }, "|"))
            end)
        end
    elseif kind == "S" then
        m.level = tonumber(a) or m.level
        m.zone, m.class = b, (c ~= "" and c) or m.class
        m.deaths = tonumber(d) or m.deaths
    elseif kind == "L" then
        local level = tonumber(a)
        m.level, m.zone, m.class = level or m.level, b, (c ~= "" and c) or m.class
        if not isSelf and level then
            local who = ClassColored(ShortName(sender), m.class)
            Print(who .. " has reached level " .. level .. "! (" .. (b or "") .. ")")
            AddLog(ShortName(sender) .. " reached level " .. level)
            ShowBanner("level", ShortName(sender), m.class, level, b)
        end
    elseif kind == "D" then
        local level = tonumber(a)
        m.level, m.zone, m.class = level or m.level, b, (c ~= "" and c) or m.class
        m.deaths = tonumber(d) or ((m.deaths or 0) + 1)
        if not isSelf then
            local who = ClassColored(ShortName(sender), m.class)
            local killedBy = KillerText(e, f)
            Print("|cffff3333Death:|r " .. who .. " (level " .. (a or "?") .. ") has died - " .. (b or "") .. killedBy)
            AddLog(ShortName(sender) .. " died (level " .. (a or "?") .. ", " .. (b or "") .. killedBy .. ")")
            ShowBanner("death", ShortName(sender), m.class, a, b)
        end
    end
    RefreshWindow()
end

-- Read the guild roster from the game: levels of all members, even without the addon
local function OnRosterUpdate()
    if not IsInGuild() then return end
    CheckGuildLeft() -- remembers the guild
    ReadConnection()
    UpdateChannel() -- joined a guild: back to the guild channel
    local num = GetNumGuildMembers()
    if not num or num == 0 then return end

    local seen = {}
    for i = 1, num do
        local name, _, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            seen[ShortName(name)] = true
            local m = Member(name)
            local old = m.level or 0
            -- Detect level-ups from members WITHOUT the addon (chat line only, no popup)
            if rosterReady and not m.hasAddon and old > 0 and level and level > old
                and ShortName(name) ~= ShortName(playerName) then
                Print(ClassColored(ShortName(name), classFile) .. " has reached level " .. level .. "!")
                AddLog(ShortName(name) .. " reached level " .. level)
            end
            m.level = level or old
            m.class = classFile or m.class
            m.inGuild = true
            if online then
                m.online, m.lastSeen = true, time()
                if zone and zone ~= "" then m.zone = zone end
            else
                m.online = false
            end
        end
    end
    -- Members who left the guild are hidden
    for name, m in pairs(db.members) do
        if not seen[name] then m.inGuild = false end
    end
    rosterReady = true
    RefreshWindow()
end

-------------------------------------------------------------------------------
-- Startup and slash commands
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
if CombatLogGetCurrentEventInfo then
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        ShameWallForeverDB = ShameWallForeverDB or {}
        db = ShameWallForeverDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        db.members = db.members or {}
        db.log = db.log or {}
        db.outbox = db.outbox or {}
    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        local name, realm = UnitFullName("player")
        realm = realm or GetNormalizedRealmName() or ""
        playerName = realm ~= "" and (name .. "-" .. realm) or name
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        local level, zone, classFile = MyStatus()
        local me = Member(playerName)
        me.level, me.zone, me.class, me.hasAddon = level, zone, classFile, true
        RequestRoster()
        -- Send our own state too: only the others reply to our own H
        C_Timer.After(5, function()
            CheckGuildLeft()
            UpdateChannel() -- channels cannot be joined right at login
            QueueLevel(UnitLevel("player")) -- current level, also for characters made before the addon
            Send("H")
            local statusLevel, statusZone, statusClass = MyStatus()
            Send(table.concat({ "S", statusLevel, statusZone, statusClass, Member(playerName).deaths or 0 }, "|"))
        end)
        Print("loaded. |cffffff00/swf|r opens the guild roster, |cffffff00/swf help|r lists all commands.")
    elseif event == "PLAYER_LEVEL_UP" then
        OnOwnLevelUp((...))
    elseif event == "PLAYER_DEAD" then
        -- short delay so the killing blow is already in the combat log
        C_Timer.After(0.5, OnOwnDeath)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage((...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        wipe(levelCache)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender, _, _, _, fromChannel = ...
        if prefix ~= PREFIX then return end
        local ours = channel == "GUILD" or (channel == "CHANNEL" and channelName and not IsInGuild()
            and (not fromChannel or fromChannel:lower():find(channelName:lower(), 1, true)))
        if ours then OnAddonMessage(text, sender) end
    elseif event == "GUILD_ROSTER_UPDATE" then
        OnRosterUpdate()
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- joined or left a guild: guild channel or private channel
        if playerName then
            C_Timer.After(2, function()
                CheckGuildLeft()
                UpdateChannel()
            end)
        end
    end
end)

local function Toggle(key, label)
    db[key] = not db[key]
    Print(label .. ": " .. (db[key] and "|cff00ff00on|r" or "|cffff3333off|r"))
end

SLASH_SHAMEWALLFOREVER1 = "/swf"
SLASH_SHAMEWALLFOREVER2 = "/shamewall"
local GUILD_INFO_MAX = 500

-- Officers: put the bot's code in the guild information, where every member's addon reads it
local function SetConnection(code)
    if not code:match("^" .. CODE_PATTERN .. "$") then
        Print("This is not a valid code: copy it again from the bot on Discord.")
        return
    end
    if not IsInGuild() then
        -- no guild yet: personal code, replaced by the guild's one once the guild exists
        db.connection, db.guildName, db.codeRemoved = code, nil, nil
        UpdateChannel()
        QueueLevel(UnitLevel("player"))
        Print("Code saved: deaths are shared with everyone who pasted it, in game and on Discord. "
            .. "Type /reload once so the companion gets it.")
        return
    end
    if not (CanEditGuildInfo and CanEditGuildInfo() and SetGuildInfoText) then
        Print("Only members allowed to edit the guild information can set the code.")
        return
    end
    local info = GetGuildInfoText() or ""
    local newInfo
    if info:find(CODE_PATTERN) then
        newInfo = (info:gsub(CODE_PATTERN, code, 1))
    else
        newInfo = (info ~= "" and (info .. "\n") or "") .. "Code companion: " .. code
    end
    if #newInfo > GUILD_INFO_MAX then
        Print("The guild information is too long: shorten it, then try again.")
        return
    end
    SetGuildInfoText(newInfo)
    db.connection, db.codeRemoved = code, nil
    Print("Code saved in the guild information: every member gets it automatically.")
end

SlashCmdList.SHAMEWALLFOREVER = function(raw)
    raw = (raw or ""):match("^%s*(.-)%s*$")
    local msg = raw:lower()
    local code = raw:match("^[Cc][Oo][Dd][Ee]%s+(%S+)$") -- the code is case-sensitive
    if code then
        SetConnection(code)
    elseif msg == "" then
        ToggleWindow()
    elseif msg == "log" then
        Print("Recent events:")
        for i = 1, math.min(20, #db.log) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. db.log[i])
        end
        if #db.log == 0 then DEFAULT_CHAT_FRAME:AddMessage("  (nothing yet)") end
    elseif msg == "guild" then
        Toggle("announceGuild", "Level-ups in guild chat")
    elseif msg == "popup" then
        Toggle("popups", "On-screen banners")
    elseif msg == "self" then
        Toggle("selfBanner", "Own banners")
    elseif msg == "sound" then
        Toggle("sound", "Sound")
    elseif msg == "test" then
        local _, classFile = UnitClass("player")
        ShowBanner("level", ShortName(playerName), classFile, 13, GetRealZoneText())
        C_Timer.After(1.5, function()
            ShowBanner("death", ShortName(playerName), classFile, 11, GetRealZoneText())
        end)
    elseif msg == "sync" then
        RequestRoster()
        Send("H")
        Print("Requested the current state from the guild.")
    elseif msg == "discord" then
        Toggle("discord", "Own deaths to Discord (needs the companion program)")
        if not db.connection then
            Print("Not set up for your guild yet: an officer types /swf code <code from the bot>.")
        end
    elseif msg == "flush" then
        ReloadUI() -- WoW only writes SavedVariables on reload or logout
    elseif msg == "striptest" or msg == "striptest level" or msg == "striptest duel" then
        local level, zone, classFile = MyStatus()
        if msg == "striptest duel" then
            ns.ShowStrip(ScorePayload("test:" .. time(), "W", { "Test Dummy", zone }))
        elseif msg == "striptest level" then
            ns.ShowStrip(LevelPayload("test:" .. time(), level, true))
        else
            ns.ShowStrip(DeathPayload("test:" .. time(), level, zone, classFile, "Test Dummy", "-1"))
        end
        Print("Test strip shown for 3 seconds: the bot posts a TEST card (bot admins only), deleted after a minute.")
    else
        Print("Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf - open/close the guild roster")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf log - last 20 level-ups and deaths")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf guild - toggle own level-ups in guild chat")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf popup - toggle on-screen banners")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf self - toggle banners for your own level-ups and deaths")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf sound - toggle sound")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf sync - request the current state from the guild")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf test - preview banners and sound")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf discord - toggle sending own deaths to Discord (on by default)")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf code <code> - officers: set the Discord bot's code for the whole guild")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf flush - reload the UI so the companion gets pending deaths")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf striptest - send a test death through the companion (bot admins only)")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf striptest level - send a test level-up through the companion (bot admins only)")
        DEFAULT_CHAT_FRAME:AddMessage("  /swf striptest duel - send a test duel win through the companion (bot admins only)")
    end
end
