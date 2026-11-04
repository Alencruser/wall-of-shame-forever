-- Wall of Shame Forever: guildmates on the world map.
-- The game only gives a player their own position: each addon sends its own every 15 seconds
-- (when it moved, else every 2 minutes) on the guild channel, or every 30 seconds on the code
-- channel without a guild; the others put a pin on the map.
--   P|mapID|x|y|zone        position on the uiMap mapID (x, y from 0 to 1)
--   P||||instance name|1    in a dungeon, raid or battleground: no coordinates, the last ones stay
--   P|hide                  stopped sharing (option off)
-- Loaded after WallOfShameForever.lua, which gives ns.Send, ns.GetDB, ns.L, ns.ClassColored,
-- ns.ClassName and calls ns.OnPosition, ns.SendPosition, ns.OnShareChanged.

local ADDON_NAME, ns = ...
local PIN_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\pin" -- white disc in a black ring

local SEND_EVERY = 15  -- seconds between two checks of the own position
local SOLO_EVERY = 30  -- without a guild (code channel, through the chat): at most this often
local KEEPALIVE = 120  -- sent at least this often, even without moving
local EXPIRE = 300     -- a pin without news for this long disappears
local MOVE_MIN = 0.002 -- smaller moves (map units) are not sent
local PIN_SIZE = 16

local positions = {} -- [name] = { map, x, y, zone, instance, time }
local lastSent = {}
local pins = {}

local function MapApi()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition
end

-------------------------------------------------------------------------------
-- Own position
-------------------------------------------------------------------------------

local function MyPosition()
    if not MapApi() then return nil end
    local zone = GetRealZoneText() or ""
    local inInstance = IsInInstance and IsInInstance()
    if inInstance then return { instance = true, zone = zone } end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return { map = map, x = x, y = y, zone = zone }
end

-- force: send even without moving (login, someone asked for the state, option turned on)
function ns.SendPosition(force)
    local db = ns.GetDB()
    if not (db and db.shareLocation) then return end
    local p = MyPosition()
    if not p then return end
    local now = GetTime()
    -- without a guild the code channel goes through the chat (anti-spam): every 30 s at most
    if not force and not IsInGuild() and lastSent.time and now - lastSent.time < SOLO_EVERY then return end
    if not force and lastSent.time and now - lastSent.time < KEEPALIVE then
        if p.instance and lastSent.instance and p.zone == lastSent.zone then return end
        if not p.instance and not lastSent.instance and p.map == lastSent.map
            and math.abs(p.x - lastSent.x) < MOVE_MIN and math.abs(p.y - lastSent.y) < MOVE_MIN then
            return
        end
    end
    if p.instance then
        ns.Send(table.concat({ "P", "", "", "", p.zone, "1" }, "|"))
    else
        ns.Send(string.format("P|%d|%.4f|%.4f|%s", p.map, p.x, p.y, p.zone))
    end
    p.time = now
    lastSent = p
end

-- option "show me on the map" changed: tell the others right away
function ns.OnShareChanged()
    local db = ns.GetDB()
    if db.shareLocation then
        ns.SendPosition(true)
    else
        ns.Send("P|hide")
        lastSent = {}
    end
end

-------------------------------------------------------------------------------
-- Pins on the world map
-------------------------------------------------------------------------------

-- Position (0 to 1) of a point of map src on map target, or nil when it is not on it
local function PositionOnMap(src, x, y, target)
    if src == target then return x, y end
    -- target contains src (zone on its continent, continent on Azeroth): its rectangle on target
    local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, src, target)
    if ok and left and right and right > left then
        return left + x * (right - left), top + y * (bottom - top)
    end
    -- other zone of the same continent: through world coordinates
    if C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok2, instance, world = pcall(C_Map.GetWorldPosFromMapPos, src, CreateVector2D(x, y))
        if ok2 and instance and world then
            local ok3, _, pos = pcall(C_Map.GetMapPosFromWorldPos, instance, world, target)
            if ok3 and pos then return pos:GetXY() end
        end
    end
end

local function SecondsText(seconds)
    if seconds < 60 then return ns.L("map_seconds", seconds) end
    return ns.L("map_minutes", math.floor(seconds / 60))
end

local function PinTooltip(pin)
    local p, m = positions[pin.name], ns.GetDB().members[pin.name]
    if not p then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.ClassColored(pin.name, m and m.class))
    if m and m.level and m.level > 0 then
        GameTooltip:AddLine(ns.L("map_level", m.level, ns.ClassName(m.class) or ""), 1, 1, 1)
    end
    if p.instance then
        GameTooltip:AddLine(ns.L("map_instance", p.instance), 1, 0.82, 0)
    elseif p.zone and p.zone ~= "" then
        GameTooltip:AddLine(p.zone, 1, 1, 1)
    end
    GameTooltip:AddLine(ns.L("map_seen", SecondsText(math.floor(GetTime() - p.time))), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreatePin(canvas)
    local pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    -- our own image (the client's party icon is missing on some clients): the class colour
    -- tints the white disc, the black ring stays black
    pin.dot = pin:CreateTexture(nil, "OVERLAY")
    pin.dot:SetAllPoints()
    pin.dot:SetTexture(PIN_TEXTURE)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", PinTooltip)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

local function Visible(name, p, now)
    if now - p.time > EXPIRE or not p.map then return false end
    local m = ns.GetDB().members[name]
    return not (m and (m.online == false or m.inGuild == false))
end

local function RefreshPins()
    if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID) then return end
    local target = WorldMapFrame:GetMapID()
    local canvas = (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
    if not (target and canvas) then return end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local now, count = GetTime(), 0
    for name, p in pairs(positions) do
        if Visible(name, p, now) then
            local x, y = PositionOnMap(p.map, p.x, p.y, target)
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                count = count + 1
                local pin = pins[count]
                if not pin then
                    pin = CreatePin(canvas)
                    pins[count] = pin
                end
                local m = ns.GetDB().members[name]
                local color = m and m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
                if color then pin.dot:SetVertexColor(color.r, color.g, color.b) else pin.dot:SetVertexColor(1, 1, 1) end
                pin.name = name
                pin:SetFrameLevel(canvas:GetFrameLevel() + 100)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width, -y * height)
                pin:SetAlpha(p.instance and 0.6 or 1) -- in an instance: last known position, faded
                pin:Show()
            end
        end
    end
    for i = count + 1, #pins do pins[i]:Hide() end
end
ns.RefreshMapPins = RefreshPins

-- from OnAddonMessage, never for our own messages
function ns.OnPosition(name, a, b, c, d, e)
    if a == "hide" then
        positions[name] = nil
    else
        local p = positions[name] or {}
        if e == "1" then
            p.instance = d ~= "" and d or "?" -- keeps the last coordinates
        else
            local map, x, y = tonumber(a), tonumber(b), tonumber(c)
            if not (map and x and y) then return end
            p.map, p.x, p.y, p.instance = map, x, y, nil
        end
        p.zone, p.time = d, GetTime()
        positions[name] = p
    end
    RefreshPins()
end

-------------------------------------------------------------------------------
-- Start: hooks on the world map, timer for the own position
-------------------------------------------------------------------------------

local hooked = false
local function HookWorldMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", RefreshPins)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", RefreshPins) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_WorldMap" then HookWorldMap() end
        return
    end
    if not MapApi() then return end -- client without the map API: no map feature
    HookWorldMap()
    C_Timer.After(6, function() ns.SendPosition(true) end) -- after the login hello (5 s)
    C_Timer.NewTicker(SEND_EVERY, function()
        ns.SendPosition(false)
        RefreshPins() -- removes expired pins while the map is open
    end)
end)
