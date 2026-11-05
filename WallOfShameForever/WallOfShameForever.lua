-- Wall of Shame Forever: level-ups, deaths and guild roster for WoW Forever
-- Data travels through invisible addon messages on the guild channel.

local ADDON_NAME, ns = ...
local PREFIX = "WALLOFSHAME" -- own network: does not talk to Memento Forever

local db
local playerName
local playerGUID
local rosterReady = false

local DEFAULTS = {
    announceGuild = true, -- post every own level-up in guild chat
    popups = true,        -- big on-screen banner
    selfBanner = true,    -- banner for own level-ups, deaths and lost duels too
    sound = true,
    volume = 100,         -- banner sounds: 20, 40, 60, 80 or 100 % (one file per volume, media/sounds)
    shareLocation = true, -- own position on the guildmates' world map (GuildMap.lua)
    discord = true,       -- own deaths for the companion, once officers set the guild up
    language = "auto",    -- "auto" (game client's language), "en" or "fr": see Locales.lua
    stripPosition = "TOPLEFT", -- where the companion's strip shows (DeathStrip.lua, ns.STRIP_POSITIONS)
}
local MAX_OUTBOX = 200 -- WoW writes it only on /reload or logout: room for a PvP evening
local CODE_PATTERN = "swf1%.[%w_%-]+" -- bot connection code, see companion/connection.py

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

-- Current language: the option, else the game client's language
local function Lang()
    local option = db and db.language
    if option == "en" or option == "fr" then return option end
    return (GetLocale and GetLocale() == "frFR") and "fr" or "en"
end

-- Translated text (Locales.lua), formatted with the extra arguments
local function L(key, ...)
    local text = ns.LOCALES[Lang()][key] or ns.LOCALES.en[key] or key
    if select("#", ...) > 0 then return text:format(...) end
    return text
end

local function ClassName(classFile)
    return classFile and ns.LOCALES.en["class_" .. classFile] and L("class_" .. classFile) or nil
end

-- Killer for display: environment tokens (Falling, Drowning...) translated, names as they are
local function KillerName(killer)
    if not killer or killer == "" then return nil end
    if ns.LOCALES.en["env_" .. killer] then return L("env_" .. killer) end
    return killer
end

local SetLanguage, ToggleOptions, RefreshOptions -- options, below
local VOLUMES, SnapVolume, PlayBannerSound -- sound, with the banners
local RegisterGameOptions -- game menu > Options > AddOns, with the options panel

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffc9a227Wall of Shame|r: " .. msg)
end

-- One key per player. Forever has first and last names: the game writes "Chamy Chan" in chat and
-- in system messages, but "Chamy-Chan" elsewhere, so a dash left after removing our realm is a space.
local function ShortName(name)
    if not name then return nil end
    local short = Ambiguate and Ambiguate(name, "none") or (name:match("^[^-]+")) or name
    return (short:gsub("%-", " "))
end

-- Our own name and realm. On Forever, UnitFullName("player") gives the first name and the LAST
-- NAME in place of the realm ("Chamy", "Chan"): the real realm comes from GetNormalizedRealmName.
local function MyNameAndRealm()
    local name, second = UnitFullName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    if not realm or realm == "" then realm = second or "" end
    if second and second ~= "" and second ~= realm then name = name .. " " .. second end
    return name, realm
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
-- Banners (level-up gold, death red, duel lost iron), stacked at the top center
-------------------------------------------------------------------------------

-- Game sounds, only if the addon's own sound cannot be played (media/sounds)
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
local TITLE_FONT = MEDIA .. "LilitaOne.ttf"
-- Text centered in the dark panel: distance from the top of the 440x220 banner
local LAYOUT = {
    -- title2/sub2/size2: when the title goes on two lines (no sub2: no subtitle then)
    level = { title = 96, sub = 126, title2 = 88, sub2 = 134 },
    death = { title = 84, sub = 114, title2 = 76, sub2 = 122 },
    -- duel: between the broken swords (down to y 100) and the bottom of the frame (y 150),
    -- narrower (faces on both sides); on two lines, size 14 keeps the zone line in the room
    duel = { title = 103, sub = 133, title2 = 101, sub2 = 136, size2 = 14, inset = 72 },
}
local TEXT_INSET = 60 -- left and right, keeps the text inside the panel (LAYOUT inset overrides)
local TITLE_SIZE = 26

local function CreateBanner()
    local b = CreateFrame("Frame", nil, UIParent)
    b:SetSize(440, 220)
    b:SetFrameStrata("HIGH")

    b.art = b:CreateTexture(nil, "BACKGROUND")
    b.art:SetAllPoints()

    b.title = b:CreateFontString(nil, "OVERLAY")
    b.titleFont = TITLE_FONT
    if not b.title:SetFont(TITLE_FONT, TITLE_SIZE, "OUTLINE") then
        b.titleFont = "Fonts\\MORPHEUS.TTF" -- fallback if the font is missing
        b.title:SetFont(b.titleFont, TITLE_SIZE, "OUTLINE")
    end
    b.title:SetJustifyH("CENTER")
    b.title:SetWordWrap(false)

    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.sub:SetJustifyH("CENTER")
    b.sub:SetWordWrap(false)

    -- flash on appearance: the banner itself, additively blended
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.shine:SetAllPoints()
    b.shine:SetBlendMode("ADD")

    b:SetScript("OnUpdate", BannerOnUpdate)
    b:Hide()
    table.insert(bannerPool, b)
    return b
end

local MIN_ONE_LINE = 20   -- below this size, a title with a line break goes on two lines
local TWO_LINE_SIZE = 19  -- largest size on two lines (LAYOUT size2 overrides)

local function MeasureTitle(b, text, size)
    b.title:SetFont(b.titleFont, size, "OUTLINE")
    b.title:SetText(text)
    local measure = b.title.GetUnboundedStringWidth or b.title.GetStringWidth
    return measure(b.title) or 0
end

-- Title "\n" marks where it may break: one line when it fits (shrunk a little if needed),
-- else two lines. Never cut.
local function SetTitle(b, kind, text)
    local pos = LAYOUT[kind]
    local inset = pos.inset or TEXT_INSET
    local room = 440 - 2 * inset
    local oneLine = (text:gsub("\n", " "))
    local size, lines, shown = TITLE_SIZE, 1, oneLine
    local width = MeasureTitle(b, oneLine, TITLE_SIZE)
    if width > room then
        size = math.floor(TITLE_SIZE * room / width)
        if size < MIN_ONE_LINE and text:find("\n") then
            local widest = 0
            for line in text:gmatch("[^\n]+") do widest = math.max(widest, MeasureTitle(b, line, TITLE_SIZE)) end
            size = math.min(pos.size2 or TWO_LINE_SIZE, math.floor(TITLE_SIZE * room / widest))
            lines, shown = 2, text
        end
    end
    b.title:SetFont(b.titleFont, size, "OUTLINE")
    b.title:SetWordWrap(lines == 2)
    b.title:SetText(shown)

    local titleY, subY = pos.title, pos.sub
    if lines == 2 then titleY, subY = pos.title2, pos.sub2 end
    b.title:ClearAllPoints()
    b.title:SetPoint("TOPLEFT", inset, -titleY)
    b.title:SetPoint("TOPRIGHT", -inset, -titleY)
    b.sub:ClearAllPoints()
    if subY then
        b.sub:SetPoint("TOPLEFT", inset, -subY)
        b.sub:SetPoint("TOPRIGHT", -inset, -subY)
        b.sub:Show()
    else
        b.sub:Hide()
    end
end

-- PlaySoundFile has no volume: each sound exists at 5 volumes
VOLUMES = { 20, 40, 60, 80, 100 }

SnapVolume = function(value)
    local best = VOLUMES[#VOLUMES]
    for _, v in ipairs(VOLUMES) do
        if math.abs(v - (tonumber(value) or 100)) < math.abs(best - (tonumber(value) or 100)) then best = v end
    end
    return best
end

-- the banner's own sound at the chosen volume, else the game's
PlayBannerSound = function(kind)
    local channel = "SFX"
    local file = MEDIA .. "sounds\\" .. kind .. "_" .. SnapVolume(db.volume) .. ".ogg"
    local ok, played = pcall(PlaySoundFile, file, channel)
    if not (ok and played) then
        pcall(PlaySound, kind == "level" and SOUND_LEVEL or SOUND_DEATH, channel)
    end
end

-- kind: "level", "death" or "duel".
-- death: other = killer (mob, player or environment token); duel: name lost against other.
-- variant = number of the French sentence, drawn by the dead or the loser so that the whole
-- guild shows the same one
local function ShowBanner(kind, name, classFile, level, zone, other, otherClass, variant)
    if db.popups then
        local b
        for _, pooled in ipairs(bannerPool) do
            if not pooled.inUse then b = pooled break end
        end
        b = b or CreateBanner()
        if #activeBanners >= MAX_BANNERS then ReleaseBanner(activeBanners[1]) end

        local zoneText = (zone and zone ~= "") and ("  -  " .. zone) or ""
        local tex = MEDIA .. "banners\\" .. kind
        b.art:SetTexture(tex)
        b.shine:SetTexture(tex)
        local texts = ns.LOCALES[Lang()]

        if kind == "death" then
            -- French: a sentence of its own for falls, drowning, lava and fire (drawn by the dead),
            -- else with the killer
            local killer = KillerName(other)
            local envSentences = other and texts.banner_death_env and texts.banner_death_env[other]
            if envSentences then
                local sentence = envSentences[variant] or envSentences[math.random(#envSentences)]
                SetTitle(b, kind, sentence:format(name))
            elseif killer and texts.banner_death_by then
                SetTitle(b, kind, L("banner_death_by", name, killer))
            else
                SetTitle(b, kind, L("banner_death", name))
            end
            b.title:SetTextColor(0.94, 0.2, 0.16)
            b.sub:SetText("|cffe6dcd2" .. L("banner_death_sub", level or "?", zoneText) .. "|r")
        elseif kind == "duel" then
            b.title:SetTextColor(0.9, 0.9, 0.9)
            local variants = texts.banner_duel_variants -- French: sentence drawn by the loser
            if variants then
                local sentence = variants[variant] or variants[math.random(#variants)]
                local who = { winner = other or "?", loser = name }
                SetTitle(b, kind, (sentence:gsub("{(%a+)}", function(key) return who[key] end)))
                b.sub:SetText((zone and zone ~= "") and ("|cffe6dcd2" .. zone .. "|r") or "")
            else
                SetTitle(b, kind, L("banner_duel", name))
                b.sub:SetText("|cffe6dcd2" .. L("banner_duel_against") .. "|r " .. ClassColored(other or "?", otherClass)
                    .. "|cffe6dcd2" .. zoneText .. "|r")
            end
        else
            SetTitle(b, kind, L("banner_level", level or "?"))
            b.title:SetTextColor(1, 0.82, 0.35)
            local className = ClassName(classFile)
            b.sub:SetText(ClassColored(name, classFile)
                .. (className and (" |cffbbbbbb(" .. className .. ")|r") or "") .. zoneText)
        end

        b.t, b.inUse = 0, true
        b:SetAlpha(0)
        b:Show()
        table.insert(activeBanners, b)
        LayoutBanners()
        if db.sound then PlayBannerSound(kind) end -- never a sound without its banner
    end
end

-------------------------------------------------------------------------------
-- Without a guild: players who pasted the same code share a hidden private channel,
-- whose name and password are derived from the code
-------------------------------------------------------------------------------

local channelName
local recentMessages = {} -- last addon messages received, for /wos debug

-- 8 hex digits, written by hand: string.format("%x") on numbers above 2^31 depends on the
-- client's Lua build (error, or another value on another system), and every player with the
-- same code must get the very same channel name
local HEX = "0123456789abcdef"
local function Hash(s, seed)
    local h = seed
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
    local out = ""
    for _ = 1, 8 do
        local digit = h % 16
        out = HEX:sub(digit + 1, digit + 1) .. out
        h = (h - digit) / 16
    end
    return out
end

local function UpdateChannel()
    -- db.guildName still set while not in a guild = leaving, see CheckGuildLeft
    local solo = not IsInGuild() and not db.guildName
    local wanted = (solo and db.connection) and ("WOS" .. Hash(db.connection, 7)) or nil
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
            -- (write_builtin_code in companion/wallofshame_companion.py)
            db.connection, db.codeRemoved = nil, true
            Print(L("left_guild_code"))
        end
        UpdateChannel()
    end)
end

-- Without a guild, the code channel. The client refuses addon messages on a custom channel
-- and lets an addon write on a channel only during a player action (key or mouse press):
-- the messages become chat lines "WOS:..." ("|" written "~"), queued and sent one by one at the
-- next presses, then hidden from the chat on every side (chat filter, below).
local CHAT_TAG = "WOS:"
local CHAT_GAP = 1 -- seconds between two lines, against the chat's anti-spam
local chatQueue, lastChatSend, chatSent = {}, 0, 0

local function QueueChat(msg)
    if msg:sub(1, 2) == "P|" then -- only the newest position (or "hide") is worth sending
        for i = #chatQueue, 1, -1 do
            if chatQueue[i]:sub(1, #CHAT_TAG + 2) == CHAT_TAG .. "P~" then table.remove(chatQueue, i) end
        end
    end
    chatQueue[#chatQueue + 1] = CHAT_TAG .. (msg:gsub("|", "~"))
    while #chatQueue > 20 do table.remove(chatQueue, 1) end
end

-- From a key or mouse press only (the game requires it for channels)
local function FlushChat()
    if #chatQueue == 0 or not channelName or IsInGuild() then return end
    local now = GetTime()
    if now - lastChatSend < CHAT_GAP then return end
    local id = GetChannelName(channelName)
    if not id or id == 0 then return end
    lastChatSend, chatSent = now, chatSent + 1
    SendChatMessage(table.remove(chatQueue, 1), "CHANNEL", nil, id)
end

-- A keyboard frame that lets every key through (propagation) and flushes the queue on the way,
-- plus mouse clicks in the world. Set up out of combat only: without propagation, a keyboard
-- frame would swallow the keys.
local keyHook
local function SetupKeyHook()
    if keyHook or (InCombatLockdown and InCombatLockdown()) then return end
    local f = CreateFrame("Frame", nil, UIParent)
    if not (f.SetPropagateKeyboardInput and pcall(f.SetPropagateKeyboardInput, f, true)) then return end
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", FlushChat)
    keyHook = f
    if WorldFrame and WorldFrame.HookScript then WorldFrame:HookScript("OnMouseDown", FlushChat) end
end

-- Hide our lines and the channel's join notices from every chat window
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", function(_, _, text)
        return type(text) == "string" and text:sub(1, #CHAT_TAG) == CHAT_TAG
    end)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", function(_, _, _, _, _, channelString, _, _, _, _, baseName)
        local name = tostring(baseName or "") .. " " .. tostring(channelString or "")
        return name:find("WOS%x%x%x%x%x%x%x%x") ~= nil
    end)
end

local function Send(msg)
    if IsInGuild() then
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD") end
    elseif channelName then
        QueueChat(msg)
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

-- WoW Forever: addons may not listen to the combat log, but the death recap (the game's
-- "Death Recap" window) lists the last hits taken, with the attacker's name and GUID.
-- Returns the last hit as { name, guid, sig } (sig: tells this death from the previous one).
local function RecapHit()
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or type(events) ~= "table" or #events == 0 then return nil end
    local last = events[1]
    for _, e in ipairs(events) do
        if (tonumber(e.timestamp) or 0) > (tonumber(last.timestamp) or 0) then last = e end
    end
    local name, guid = last.sourceName, last.sourceGUID
    local env = last.environmentalType
    if env and env ~= "" then
        env = tostring(env):lower():gsub("^%l", string.upper) -- FALLING -> Falling
        name, guid = ns.LOCALES.en["env_" .. env] and env or "Environment", nil
    end
    if not name or name == "" then return nil end
    return { name = name, guid = guid,
        sig = table.concat({ #events, tostring(last.timestamp), tostring(last.sourceGUID), tostring(last.amount) }, ":") }
end

-- The recap of this death, not the previous one (it stays readable until the next death)
local function FreshRecapHit()
    local hit = RecapHit()
    if hit and hit.sig ~= (db and db.lastRecap) then return hit end
end

-- killer name and level ("" when unknown)
local function Killer()
    local hit = lastHit
    if not hit or GetTime() - hit.time > KILLER_MEMORY then
        hit = FreshRecapHit()
        if hit and db then db.lastRecap = hit.sig end
    end
    if not hit then return "", "" end
    local level = FindUnitLevel(hit.guid)
    return hit.name or "", level and tostring(level) or ""
end

local function KillerText(killer, killerLevel)
    if not killer or killer == "" then return "" end
    killer = KillerName(killer)
    local level = tonumber(killerLevel)
    if not level then return L("killed_by", killer) end
    return L("killed_by_level", killer, level < 0 and "??" or level)
end

-------------------------------------------------------------------------------
-- Guild roster (window)
-------------------------------------------------------------------------------

local window, rows = nil, {}

local function FormatSeen(m)
    if m.online then return "|cff00ff00" .. L("online") .. "|r" end
    if not m.lastSeen then return "-" end
    local diff = time() - m.lastSeen
    if diff < 3600 then return L("seen_min", math.floor(diff / 60)) end
    if diff < 86400 then return L("seen_hours", math.floor(diff / 3600)) end
    return L("seen_days", math.floor(diff / 86400))
end

local HEADERS = { "col_name", "col_level", "col_zone", "col_seen", "col_deaths" }

local function RefreshWindow()
    if not window or not window:IsShown() then return end
    for c, key in ipairs(HEADERS) do window.headers[c]:SetText(L(key)) end
    window.optionsButton:SetText(L("options_button"))

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
            and L(m.deaths == 1 and "death_count_one" or "death_count", m.deaths) or "")
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    child:SetHeight(math.max(1, #list * 16))
    window.count:SetText(L("member_count", #list))
end

local function CreateWindow()
    window = CreateFrame("Frame", "WallOfShameForeverFrame", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(540, 400)
    window:SetPoint("CENTER")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "WallOfShameForeverFrame") -- closes with Escape

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.title:SetPoint("TOP", 0, -6)
    window.title:SetText("Wall of Shame Forever")

    window.headers = {}
    local x = { 0, 150, 195, 345, 425 }
    for c = 1, 5 do
        local h = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", 16 + x[c], -32)
        window.headers[c] = h
    end

    window.scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    window.scroll:SetPoint("TOPLEFT", 16, -50)
    window.scroll:SetPoint("BOTTOMRIGHT", -32, 30)
    local child = CreateFrame("Frame", nil, window.scroll)
    child:SetSize(500, 1)
    window.scroll:SetScrollChild(child)

    window.count = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.count:SetPoint("BOTTOMLEFT", 16, 10)

    window.optionsButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.optionsButton:SetSize(110, 20)
    window.optionsButton:SetPoint("BOTTOMRIGHT", -12, 6)
    window.optionsButton:SetScript("OnClick", function() ToggleOptions(true) end)

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
    local name, realm = MyNameAndRealm()
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
    AddLog(L("log_own_level", newLevel))
    if db.announceGuild and IsInGuild() then
        SendChatMessage(L("guild_level_up", ShortName(playerName), newLevel), "GUILD")
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

-- Duel lost against a guildmate: the loser tells the guild, everyone gets the banner
local function OnDuelLost(winner)
    local zone = GetRealZoneText() or ""
    local winnerClass = db.members[ShortName(winner)] and db.members[ShortName(winner)].class
    -- the loser draws the French sentence, so every guildmate shows the same one
    local variant = math.random(#ns.LOCALES.fr.banner_duel_variants)
    Send(table.concat({ "U", ShortName(winner), zone, winnerClass or "", variant }, "|"))
    AddLog(L("log_own_duel_lost", ShortName(winner)))
    if db.selfBanner then
        local _, classFile = UnitClass("player")
        ShowBanner("duel", ShortName(playerName), classFile, nil, zone, ShortName(winner), winnerClass, variant)
    end
end

local function OnSystemMessage(msg)
    local winner, loser = DuelResult(msg or "")
    if not winner then return end
    if ShortName(loser) == ShortName(playerName) and IsGuildmate(winner) then
        OnDuelLost(winner)
        return
    end
    if ShortName(winner) ~= ShortName(playerName) or not IsGuildmate(loser) then return end
    -- on the strip too: posted right away, with a screenshot of the winner's screen
    local payload = QueueScore("W", { ShortName(loser), GetRealZoneText() or "" })
    if payload then ns.ShowStrip(payload) end
    AddLog(L("log_duel_won", ShortName(loser)))
end

-- Killing blow on a hostile player (the other faction)
OnKillingBlow = function(guid, victim, flags)
    if not (guid and guid:find("^Player%-")) then return end
    local hostile = COMBATLOG_OBJECT_REACTION_HOSTILE and bit and bit.band(flags or 0, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
    if not hostile then return end
    local _, victimClass = GetPlayerInfoByGUID(guid)
    local level = FindUnitLevel(guid)
    QueueScore("K", { ShortName(victim) or "", level and tostring(level) or "", victimClass or "", GetRealZoneText() or "" })
    AddLog(L("log_killing_blow", ShortName(victim) or "?"))
end

local function OnOwnDeath()
    local level, zone, classFile = MyStatus()
    local killer, killerLevel = Killer()
    lastHit = nil
    local me = Member(playerName)
    me.deaths = (me.deaths or 0) + 1
    -- killer fields at the end: older versions just ignore them
    -- French sentence for a fall, drowning, lava or fire: drawn here, the same for everyone
    local envSentences = ns.LOCALES.fr.banner_death_env[killer]
    local variant = envSentences and math.random(#envSentences) or nil
    Send(table.concat({ "D", level, zone, classFile, me.deaths, killer, killerLevel, variant or "" }, "|"))
    AddLog(L("log_own_death", level, zone, KillerText(killer, killerLevel)))
    if db.selfBanner then
        ShowBanner("death", ShortName(playerName), classFile, level, zone, killer, nil, variant)
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
        if first and db.discord then Print(L("discord_ready")) end
        QueueLevel(UnitLevel("player"))
    end
end

local function OnAddonMessage(text, sender)
    if not sender then return end
    local isSelf = ShortName(sender) == ShortName(playerName)

    local kind, a, b, c, d, e, f, g = strsplit("|", text)
    local m = Member(sender)
    m.hasAddon, m.online, m.lastSeen, m.inGuild = true, true, time(), true

    if kind == "H" then
        -- Someone logged in and asks for the current state: reply after a short delay
        if not isSelf then
            C_Timer.After(math.random() * 5, function()
                local level, zone, classFile = MyStatus()
                Send(table.concat({ "S", level, zone, classFile, Member(playerName).deaths or 0 }, "|"))
                if ns.SendPosition then ns.SendPosition(true) end -- their map gets our pin right away
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
            Print(L("chat_level_up", who, level, b or ""))
            AddLog(L("log_level", ShortName(sender), level))
            ShowBanner("level", ShortName(sender), m.class, level, b)
        end
    elseif kind == "D" then
        local level = tonumber(a)
        m.level, m.zone, m.class = level or m.level, b, (c ~= "" and c) or m.class
        m.deaths = tonumber(d) or ((m.deaths or 0) + 1)
        if not isSelf then
            local who = ClassColored(ShortName(sender), m.class)
            local killedBy = KillerText(e, f)
            Print(L("chat_death", who, a or "?", b or "", killedBy))
            AddLog(L("log_death", ShortName(sender), a or "?", b or "", killedBy))
            ShowBanner("death", ShortName(sender), m.class, a, b, e, nil, tonumber(g)) -- g: sentence number
        end
    elseif kind == "P" then
        -- position for the world map (GuildMap.lua)
        if not isSelf and ns.OnPosition then ns.OnPosition(ShortName(sender), a, b, c, d, e) end
    elseif kind == "U" then
        -- sender lost a duel against a (guildmate) winner: a = winner, b = zone, c = winner class,
        -- d = number of the French sentence
        if not isSelf and a and a ~= "" then
            local winnerClass = (c ~= "" and c) or (db.members[a] and db.members[a].class)
            Print(L("chat_duel_lost", ClassColored(ShortName(sender), m.class), ClassColored(a, winnerClass),
                (b and b ~= "") and (" (" .. b .. ")") or ""))
            AddLog(L("log_duel_lost", ShortName(sender), a))
            ShowBanner("duel", ShortName(sender), m.class, nil, b, a, winnerClass, tonumber(d))
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
                Print(L("guild_level_up", ClassColored(ShortName(name), classFile), level))
                AddLog(L("log_level", ShortName(name), level))
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
    if ns.RefreshMapPins then ns.RefreshMapPins() end
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
frame:RegisterEvent("CHAT_MSG_CHANNEL")
if CombatLogGetCurrentEventInfo then
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        WallOfShameForeverDB = WallOfShameForeverDB or {}
        db = WallOfShameForeverDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        db.members = db.members or {}
        db.log = db.log or {}
        db.outbox = db.outbox or {}
        -- before 0.2.1, "Chamy-Chan" and "Chamy Chan" were two players: keep one
        local dashed = {}
        for key in pairs(db.members) do
            if key:find("-", 1, true) then dashed[#dashed + 1] = key end
        end
        for _, key in ipairs(dashed) do
            local fixed = key:gsub("%-", " ")
            db.members[fixed] = db.members[fixed] or db.members[key]
            db.members[key] = nil
        end
        -- Private build for a guild (PrivateCode.lua, not in the public addon): as if the player
        -- had typed /wos code. Never after leaving a guild (codeRemoved), and the officers' code
        -- in the guild information still takes over (ReadConnection).
        local builtin = ns.BUILTIN_CODE
        if not db.connection and not db.codeRemoved and type(builtin) == "string"
            and builtin:match("^" .. CODE_PATTERN .. "$") then
            db.connection = builtin
        end
    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        local name, realm = MyNameAndRealm()
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
        Print(L("loaded"))
        pcall(RegisterGameOptions)
        SetupKeyHook()
    elseif event == "PLAYER_LEVEL_UP" then
        OnOwnLevelUp((...))
    elseif event == "PLAYER_DEAD" then
        -- short delay so the killing blow is already in the combat log; without the combat log
        -- (WoW Forever), wait up to 3 seconds for the death recap of this death
        local tries = 0
        local function Wait()
            tries = tries + 1
            if lastHit or tries >= 6 or not (C_DeathRecap and C_DeathRecap.GetRecapEvents) or FreshRecapHit() then
                OnOwnDeath()
            else
                C_Timer.After(0.5, Wait)
            end
        end
        C_Timer.After(0.5, Wait)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage((...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        wipe(levelCache)
        SetupKeyHook() -- if the login happened in combat
    elseif event == "CHAT_MSG_CHANNEL" then
        -- without a guild: "WOS:..." lines on the code channel (see QueueChat)
        local text, sender, _, channelString, _, _, _, _, baseName = ...
        if not (channelName and not IsInGuild() and type(text) == "string"
            and text:sub(1, #CHAT_TAG) == CHAT_TAG) then return end
        local from = tostring(baseName or "") .. " " .. tostring(channelString or "")
        if not from:lower():find(channelName:lower(), 1, true) then return end
        local msg = text:sub(#CHAT_TAG + 1):gsub("~", "|")
        table.insert(recentMessages, 1, { time = time(), sender = sender, channel = "CODE",
            from = channelString, kind = msg:sub(1, 1), kept = true })
        recentMessages[9] = nil
        OnAddonMessage(msg, sender)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender, _, _, _, fromChannel = ...
        if prefix ~= PREFIX then return end
        local ours = channel == "GUILD" or (channel == "CHANNEL" and channelName and not IsInGuild()
            and (not fromChannel or fromChannel:lower():find(channelName:lower(), 1, true)))
        -- for /wos debug: the last messages received, kept or not
        table.insert(recentMessages, 1, { time = time(), sender = sender, channel = channel,
            from = fromChannel, kind = (text or ""):sub(1, 1), kept = ours and true or false })
        recentMessages[9] = nil
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
    Print(L(label) .. ": " .. L(db[key] and "on" or "off"))
    RefreshOptions()
end

-- language option: "auto", "en" or "fr"
SetLanguage = function(lang)
    db.language = lang
    Print(L("lang_set", L("lang_" .. lang)))
    RefreshWindow()
    RefreshOptions()
end

-------------------------------------------------------------------------------
-- Options panel (/wos options, button in the roster window, game menu > Options > AddOns)
-------------------------------------------------------------------------------

local options

local function TestBanners()
    local _, classFile = UnitClass("player")
    ShowBanner("level", ShortName(playerName), classFile, 13, GetRealZoneText())
    C_Timer.After(1.5, function()
        ShowBanner("death", ShortName(playerName), classFile, 11, GetRealZoneText(), "Hogger")
    end)
    C_Timer.After(3, function()
        ShowBanner("duel", ShortName(playerName), classFile, nil, GetRealZoneText(), "Grumbar", "WARRIOR")
    end)
end

local function Heading(parent, y)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", 16, y)
    return h
end

-- Check box bound to db[key]; onChange runs after the value is saved
local function CheckBox(parent, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    cb.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetScript("OnClick", onClick)
    return cb
end

local function Checked(cb)
    return cb:GetChecked() and true or false -- 1/nil on older clients
end

local function CreateOptions()
    options = CreateFrame("Frame", "WallOfShameForeverOptions", UIParent, "BasicFrameTemplateWithInset")
    options:SetSize(360, 520)
    options:SetPoint("CENTER")
    options:SetMovable(true)
    options:EnableMouse(true)
    options:RegisterForDrag("LeftButton")
    options:SetScript("OnDragStart", options.StartMoving)
    options:SetScript("OnDragStop", options.StopMovingOrSizing)
    options:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "WallOfShameForeverOptions") -- closes with Escape

    options.title = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    options.title:SetPoint("TOP", 0, -6)

    options.checks = {}
    local function Bound(key, x, y)
        local cb = CheckBox(options, x, y, function(self)
            db[key] = Checked(self)
            if key == "shareLocation" and ns.OnShareChanged then ns.OnShareChanged() end
            RefreshOptions()
        end)
        cb.key = key
        options.checks[#options.checks + 1] = cb
        return cb
    end

    -- Banners: all of them (and their sound), or only your own
    options.bannersHeading = Heading(options, -34)
    options.popups = Bound("popups", 20, -52)
    options.selfBanner = Bound("selfBanner", 20, -76)

    -- Sound
    options.soundHeading = Heading(options, -112)
    options.sound = Bound("sound", 20, -130)
    options.volumeLabel = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    options.volumeLabel:SetPoint("TOPLEFT", 26, -164)
    local slider = CreateFrame("Slider", nil, options)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(180, 16)
    slider:SetPoint("TOPLEFT", 130, -162)
    slider:SetMinMaxValues(VOLUMES[1], VOLUMES[#VOLUMES])
    slider:SetValueStep(20)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider.track = slider:CreateTexture(nil, "BACKGROUND")
    slider.track:SetPoint("LEFT", 4, 0)
    slider.track:SetPoint("RIGHT", -4, 0)
    slider.track:SetHeight(6)
    slider.track:SetColorTexture(0, 0, 0, 0.6)
    slider.value = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    slider.value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    slider:SetScript("OnValueChanged", function(self, value)
        local volume = SnapVolume(value)
        self.value:SetText(volume .. " %")
        if self.refreshing or volume == db.volume then return end
        db.volume = volume
        -- preview at the new volume, at most every 0.3 s while dragging
        local now = GetTime()
        if db.popups and db.sound and (not self.lastPreview or now - self.lastPreview > 0.3) then
            self.lastPreview = now
            PlayBannerSound("level")
        end
    end)
    options.volume = slider

    -- Map
    options.mapHeading = Heading(options, -200)
    options.shareLocation = Bound("shareLocation", 20, -218)

    -- Language
    options.languageHeading = Heading(options, -260)
    options.languages = {}
    for i, lang in ipairs({ "auto", "fr", "en" }) do
        local cb = CheckBox(options, 20, -278 - (i - 1) * 24, function()
            SetLanguage(lang)
        end)
        cb.lang = lang
        options.languages[i] = cb
    end

    -- Companion: where its strip shows, a small screen of 3 x 3 boxes (never the middle one)
    options.stripHeading = Heading(options, -364)
    local screen = CreateFrame("Frame", nil, options)
    screen:SetSize(96, 60)
    screen:SetPoint("TOPLEFT", 24, -386)
    local bg = screen:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    options.stripCells = {}
    local grid = { { "TOPLEFT", "TOP", "TOPRIGHT" }, { "LEFT", false, "RIGHT" },
        { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }
    for row, positions in ipairs(grid) do
        for col, pos in ipairs(positions) do
            local cell = CreateFrame("Button", nil, screen)
            cell:SetSize(28, 16)
            cell:SetPoint("TOPLEFT", 4 + (col - 1) * 30, -4 - (row - 1) * 18)
            cell.tex = cell:CreateTexture(nil, "ARTWORK")
            cell.tex:SetAllPoints()
            if pos then
                cell.pos = pos
                local glow = cell:CreateTexture(nil, "HIGHLIGHT")
                glow:SetAllPoints()
                glow:SetColorTexture(1, 1, 1, 0.3)
                cell:SetScript("OnClick", function()
                    db.stripPosition = pos
                    if ns.PreviewStrip then ns.PreviewStrip() end
                    RefreshOptions()
                end)
                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(L("strip_pos_" .. pos))
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
                options.stripCells[#options.stripCells + 1] = cell
            else
                cell.tex:SetColorTexture(0.12, 0.12, 0.12, 0.8) -- the middle: not allowed
                cell:EnableMouse(false)
            end
        end
    end
    options.stripName = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    options.stripName:SetPoint("TOPLEFT", screen, "TOPRIGHT", 14, -4)
    options.stripHint = options:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    options.stripHint:SetPoint("TOPLEFT", options.stripName, "BOTTOMLEFT", 0, -6)
    options.stripHint:SetWidth(200)
    options.stripHint:SetJustifyH("LEFT")

    options.test = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    options.test:SetSize(200, 24)
    options.test:SetPoint("BOTTOM", 0, 16)
    options.test:SetScript("OnClick", TestBanners)

    options:SetScript("OnShow", function() RefreshOptions() end)
    options:Hide()
end

-- greyed out and not clickable when it has no effect
local function SetActive(active, ...)
    for i = 1, select("#", ...) do
        local widget = select(i, ...)
        widget:SetAlpha(active and 1 or 0.4)
        if widget.EnableMouse then widget:EnableMouse(active and true or false) end
    end
end

-- Texts in the current language and every control from the saved settings
RefreshOptions = function()
    if not options or not options:IsShown() then return end
    options.title:SetText(L("options_title"))
    options.bannersHeading:SetText(L("sect_banners"))
    options.soundHeading:SetText(L("sect_sound"))
    options.mapHeading:SetText(L("sect_map"))
    options.languageHeading:SetText(L("sect_language"))
    local labels = { popups = "opt_popups", selfBanner = "opt_self", sound = "opt_sound",
        shareLocation = "opt_share_location" }
    for _, cb in ipairs(options.checks) do
        cb.label:SetText(L(labels[cb.key]))
        cb:SetChecked(db[cb.key] and true or false)
    end
    options.volumeLabel:SetText(L("opt_volume"))
    options.volume.refreshing = true
    options.volume:SetValue(db.volume)
    options.volume.value:SetText(db.volume .. " %")
    options.volume.refreshing = false
    -- no banners: no own banners and no sound either; no sound: no volume
    SetActive(db.popups, options.selfBanner, options.selfBanner.label, options.soundHeading,
        options.sound, options.sound.label)
    SetActive(db.popups and db.sound, options.volume, options.volumeLabel, options.volume.value)
    for _, cb in ipairs(options.languages) do
        cb.label:SetText(L(cb.lang == "auto" and "lang_auto" or ("lang_" .. cb.lang)))
        cb:SetChecked(db.language == cb.lang)
    end
    options.stripHeading:SetText(L("sect_companion"))
    local stripPos = ns.StripPosition and ns.StripPosition() or "TOPLEFT"
    for _, cell in ipairs(options.stripCells) do
        if cell.pos == stripPos then
            cell.tex:SetColorTexture(1, 0.82, 0, 0.95)
        else
            cell.tex:SetColorTexture(0.4, 0.4, 0.4, 0.8)
        end
    end
    options.stripName:SetText(L("strip_pos_" .. stripPos))
    options.stripHint:SetText(L("opt_strip_hint"))
    options.test:SetText(L("btn_test"))
end

ToggleOptions = function(show)
    if not options then CreateOptions() end
    if show == nil then show = not options:IsShown() end
    if show then options:Show() else options:Hide() end
end

-- Game menu > Options > AddOns: a page with a button to our panel (the panel stays our own,
-- so it looks the same on every client)
RegisterGameOptions = function()
    local page = CreateFrame("Frame")
    page.name = "Wall of Shame Forever"
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Wall of Shame Forever")
    local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", 16, -50)
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame.IsShown and InterfaceOptionsFrame:IsShown() then
            HideUIPanel(InterfaceOptionsFrame)
        end
        if GameMenuFrame and GameMenuFrame.IsShown and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        ToggleOptions(true)
    end)
    page:SetScript("OnShow", function() open:SetText(L("btn_open_options")) end)
    open:SetText(L("btn_open_options"))
    if type(Settings) == "table" and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(page, page.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
end

SLASH_WALLOFSHAMEFOREVER1 = "/wos"
SLASH_WALLOFSHAMEFOREVER2 = "/wallofshame"
local GUILD_INFO_MAX = 500

-- Officers: put the bot's code in the guild information, where every member's addon reads it
-- /wos debug: where does the sharing get stuck (guild, code, channel, messages received)
local function Debug()
    local function yes(v) return v and "|cff00ff00yes|r" or "|cffff3333no|r" end
    local function line(text) DEFAULT_CHAT_FRAME:AddMessage("  " .. text) end
    Print("debug")
    local metadata = (type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    line("version " .. tostring(metadata and metadata(ADDON_NAME, "Version") or "?")
        .. ", client " .. tostring((select(4, GetBuildInfo()))) .. " " .. tostring(GetLocale and GetLocale()))
    line("in a guild: " .. yes(IsInGuild()) .. " " .. tostring(GetGuildInfo("player") or "")
        .. (db.guildName and (" (remembered: " .. db.guildName .. ")") or ""))
    line("code: " .. tostring(db.connection or "none") .. ", strip: " .. tostring(ns.StripPosition and ns.StripPosition()))
    local id = channelName and GetChannelName(channelName) or 0
    line("code channel: " .. tostring(channelName or "none (in a guild or no code)")
        .. (channelName and (", joined: " .. yes(id and id > 0) .. " (#" .. tostring(id) .. ")") or ""))
    local registered = C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered
        and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)
    line("addon messages registered: " .. yes(registered))
    if not IsInGuild() and channelName then
        line("sending on the code channel: at the next key press, waiting: " .. #chatQueue
            .. ", sent: " .. chatSent .. ", key hook: " .. yes(keyHook))
    end
    line("map: " .. yes(C_Map and C_Map.GetMapRectOnMap) .. ", sharing my position: " .. yes(db.shareLocation))
    local seen = {}
    for name, m in pairs(db.members) do
        if m.hasAddon and name ~= ShortName(playerName) then
            seen[#seen + 1] = name .. (m.lastSeen and (" " .. (time() - m.lastSeen) .. "s") or "")
        end
    end
    line("players seen with the addon: " .. (#seen > 0 and table.concat(seen, ", ") or "|cffff3333none|r"))
    if #recentMessages == 0 then line("messages received: |cffff3333none|r") end
    for _, r in ipairs(recentMessages) do
        line(string.format("%ds ago, %s from %s%s: %s", time() - r.time, tostring(r.channel), tostring(r.sender),
            r.from and r.from ~= "" and (" (" .. r.from .. ")") or "", r.kept and ("kept, " .. r.kind) or "|cffff3333ignored|r"))
    end
end

local function SetConnection(code)
    if not code:match("^" .. CODE_PATTERN .. "$") then
        Print(L("code_invalid"))
        return
    end
    if not IsInGuild() then
        -- no guild yet: personal code, replaced by the guild's one once the guild exists
        db.connection, db.guildName, db.codeRemoved = code, nil, nil
        UpdateChannel()
        QueueLevel(UnitLevel("player"))
        Print(L("code_saved_solo"))
        return
    end
    if not (CanEditGuildInfo and CanEditGuildInfo() and SetGuildInfoText) then
        Print(L("code_no_rights"))
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
        Print(L("guild_info_too_long"))
        return
    end
    SetGuildInfoText(newInfo)
    db.connection, db.codeRemoved = code, nil
    Print(L("code_saved_guild"))
end

SlashCmdList.WALLOFSHAMEFOREVER = function(raw)
    raw = (raw or ""):match("^%s*(.-)%s*$")
    local msg = raw:lower()
    local code = raw:match("^[Cc][Oo][Dd][Ee]%s+(%S+)$") -- the code is case-sensitive
    if code then
        SetConnection(code)
    elseif msg == "" then
        ToggleWindow()
    elseif msg == "log" then
        Print(L("recent_events"))
        for i = 1, math.min(20, #db.log) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. db.log[i])
        end
        if #db.log == 0 then DEFAULT_CHAT_FRAME:AddMessage("  " .. L("nothing_yet")) end
    elseif msg == "guild" then
        Toggle("announceGuild", "opt_guild")
    elseif msg == "popup" then
        Toggle("popups", "opt_popups")
    elseif msg == "self" then
        Toggle("selfBanner", "opt_self")
    elseif msg == "map" or msg == "carte" then
        Toggle("shareLocation", "opt_share_location")
        if ns.OnShareChanged then ns.OnShareChanged() end
    elseif msg == "sound" then
        Toggle("sound", "opt_sound")
    elseif msg == "lang" or msg == "langue" or msg:match("^langu?e?%s") then
        local lang = msg:match("%s+(%a+)$")
        if lang == "auto" or lang == "en" or lang == "fr" then
            SetLanguage(lang)
        else
            Print(L("lang_set", L("lang_" .. db.language)))
            Print(L("lang_usage"))
        end
    elseif msg == "options" or msg == "option" or msg == "config" or msg == "settings" then
        ToggleOptions()
    elseif msg == "volume" or msg:match("^volume%s") then
        local value = tonumber(msg:match("%s+(%d+)$"))
        if value and value >= 1 and value <= 100 then
            db.volume = SnapVolume(value)
            Print(L("volume_set", db.volume))
            RefreshOptions()
        else
            Print(L("volume_set", db.volume))
            Print(L("volume_usage"))
        end
    elseif msg == "strip" or msg:match("^strip%s") then
        local args = { topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT", left = "LEFT", right = "RIGHT",
            bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT" }
        local pos = args[msg:match("^strip%s+(%a+)$") or ""]
        if pos then
            db.stripPosition = pos
            if ns.PreviewStrip then ns.PreviewStrip() end
            RefreshOptions()
        end
        Print(L("strip_pos_set", L("strip_pos_" .. ns.StripPosition())))
        if not pos then Print(L("strip_usage")) end
    elseif msg == "test" then
        TestBanners()
    elseif msg == "sync" then
        RequestRoster()
        Send("H")
        Print(L("sync_requested"))
    elseif msg == "discord" then
        Toggle("discord", "opt_discord")
        if not db.connection then
            Print(L("discord_not_set"))
        end
    elseif msg == "debug" then
        Debug()
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
        Print(L("strip_test"))
    else
        Print(L("commands"))
        for _, line in ipairs(L("help")) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
    end
end

-- For GuildMap.lua (loaded after this file)
ns.Send = Send
ns.GetDB = function() return db end
ns.L = L
ns.ClassColored = ClassColored
ns.ClassName = ClassName
