-- Wall of Shame Forever: follow time
-- Time this character spends auto-following a member of its guild (/follow), for the guild's Discord
-- bot, which ranks who follows the most. One session per follow, from AUTOFOLLOW_BEGIN (the game gives
-- the target's name) to AUTOFOLLOW_END, a new target, /reload or logout. A target outside the guild is
-- not counted.
--   2|F|id|name|realm|guild|level|class|time|battletag|target|start|seconds|done
--   start: when the follow began (fixed for the session), seconds: time followed so far, done: 1 when
--   the session is over. id: name-realm:F:start:seconds, a new one per update; the bot keeps the
--   highest seconds per follower and start, so an update received twice never counts twice.
-- SavedVariables are lost when the game crashes: every 5 minutes during a follow, the addon shows a
-- strip (read live by the companion), so a crash costs at most the last minutes. The end of a session
-- is shown on a strip too, and queued in the outbox as a fallback (only the latest update of a
-- session waits there).
-- Loaded after WallOfShameForever.lua (ns.GetDB, ns.Identity, ns.Clean, ns.AddToOutbox,
-- ns.IsGuildMember) and DeathStrip.lua (ns.ShowStrip, ns.StripBusy).

local ADDON_NAME, ns = ...
local Follow = {}
ns.Follow = Follow

local STRIP_EVERY = 300 -- seconds between two strips during a follow
local RETRY = 4         -- seconds to wait when another strip is on screen
local MAX_RETRIES = 5

local db
local session -- { target, start, token }

local function Enabled()
    return db and db.discord and db.connection
end

function Follow.Payload(s, now, done)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    local seconds = math.max(0, now - s.start)
    return table.concat({ "2", "F", name .. "-" .. realm .. ":F:" .. s.start .. ":" .. seconds, name, realm, guild,
        UnitLevel("player"), classFile or "", now, battleTag, ns.Clean(s.target), s.start, seconds,
        done and "1" or "0" }, "|")
end

-- Only the latest update of a session waits in the outbox
local function Queue(payload, s)
    local name, realm = ns.Identity()
    local prefix = name .. "-" .. realm .. ":F:" .. s.start .. ":"
    for i = #db.outbox, 1, -1 do
        if (select(3, strsplit("|", db.outbox[i]))):sub(1, #prefix) == prefix then table.remove(db.outbox, i) end
    end
    ns.AddToOutbox(payload)
end

-- Strip when the screen is free (a death or level-up strip is never cut short)
local function ShowWhenFree(payload, tries)
    if not ns.ShowStrip then return end
    if ns.StripBusy and ns.StripBusy() and (tries or 0) < MAX_RETRIES then
        C_Timer.After(RETRY, function() ShowWhenFree(payload, (tries or 0) + 1) end)
        return
    end
    ns.ShowStrip(payload)
end

local function Tick(s)
    if session ~= s then return end -- ended, or another follow since
    local payload = Follow.Payload(s, time(), false)
    Queue(payload, s)
    ShowWhenFree(payload)
    C_Timer.After(STRIP_EVERY, function() Tick(s) end)
end

-- Ends the current session. strip: false at logout (the screen is going away)
function Follow.Stop(strip)
    local s = session
    session = nil
    if not (s and Enabled()) then return end
    local payload = Follow.Payload(s, time(), true)
    Queue(payload, s)
    if strip ~= false then ShowWhenFree(payload) end
end

function Follow.Start(target)
    Follow.Stop()
    if not (Enabled() and target and target ~= "" and ns.IsGuildMember(target)) then return end
    local s = { target = target, start = time() }
    session = s
    C_Timer.After(STRIP_EVERY, function() Tick(s) end)
end

function Follow.Current() return session end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({ "AUTOFOLLOW_BEGIN", "AUTOFOLLOW_END", "PLAYER_LOGOUT" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_LOGIN" then
        db = ns.GetDB and ns.GetDB()
    elseif event == "AUTOFOLLOW_BEGIN" then
        Follow.Start(arg)
    elseif event == "AUTOFOLLOW_END" then
        Follow.Stop()
    elseif event == "PLAYER_LOGOUT" then -- logout or /reload: the game writes SavedVariables just after
        Follow.Stop(false)
    end
end)
