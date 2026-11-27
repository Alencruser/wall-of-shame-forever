-- Wall of Shame Forever: tells the player in chat when the addon or the companion is out of date (v0.9.3).
-- Two sources:
--   - the guildmates: every addon gives its version in its login and status messages (H, S); a guildmate with
--     a newer version means a newer one is out
--   - the bot: the latest versions published (CurseForge for the addon, GitHub for the companion), in the
--     companion's file (WallOfShameForever_Orders.hub.latest), with the companion's own version (.companion;
--     none: a companion older than 0.8.4)
-- One line per version and per session at most.
-- Loaded after WallOfShameForever.lua, which gives ns.Print, ns.L.

local ADDON_NAME, ns = ...
local Updates = {}
ns.Updates = Updates

local told = {} -- "addon:0.9.4" / "companion:0.8.5" already said this session
local OLDEST_SILENT_COMPANION = "0.8.3" -- a file without the companion's version: written by 0.8.3 or older

-- "v0.9.3" → { 0, 9, 3 }; nil if it is not a version
local function Parts(version)
    local a, b, c = tostring(version or ""):match("^v?(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

-- true when a is newer than b (both "x.y.z", with or without the "v")
function Updates.Newer(a, b)
    local pa, pb = Parts(a), Parts(b)
    if not (pa and pb) then return false end
    for i = 1, 3 do
        if pa[i] ~= pb[i] then return pa[i] > pb[i] end
    end
    return false
end

-- This addon's version, "0.9.3"
function Updates.Mine()
    local metadata = (type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = type(metadata) == "function" and metadata(ADDON_NAME, "Version") or ""
    return (tostring(version or ""):gsub("^v", ""))
end

local function Tell(kind, latest, mine)
    local key = kind .. ":" .. latest
    if told[key] then return false end
    told[key] = true
    if kind == "addon" then
        ns.Print(ns.L("update_addon", latest, mine))
    else
        ns.Print(ns.L(mine and "update_companion" or "update_companion_old", latest, mine))
    end
    return true
end

-- A guildmate's version (their H or S message). Returns true if the player was told.
function Updates.Seen(version)
    local mine = Updates.Mine()
    version = tostring(version or ""):gsub("^v", "")
    if Updates.Newer(version, mine) then return Tell("addon", version, mine) end
    return false
end

-- The bot's latest versions, from the companion's file
function Updates.CheckFile()
    local file = WallOfShameForever_Orders
    local latest = type(file) == "table" and type(file.hub) == "table" and type(file.hub.latest) == "table" and file.hub.latest
    if not latest then return end
    local mine = Updates.Mine()
    if Updates.Newer(latest.addon, mine) then Tell("addon", tostring(latest.addon):gsub("^v", ""), mine) end
    local companion = type(file.companion) == "string" and file.companion or nil
    if Updates.Newer(latest.companion, companion or OLDEST_SILENT_COMPANION) then
        Tell("companion", tostring(latest.companion), companion)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    C_Timer.After(12, Updates.CheckFile) -- after the login lines
end)
