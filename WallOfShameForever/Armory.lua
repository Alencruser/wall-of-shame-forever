-- Wall of Shame Forever: the character's gear, stats and talents for the site's « Armurerie »
-- (members of the guild's Discord only). Read at login, when gear or talents change, on a level-up and at
-- logout; queued for the bot only when the gear, the talents or the level changed (stats alone move with
-- every buff). Off with the « Show my gear on the site » option: the bot is told to hide the character.
--   2|G|id|name|realm|guild|level|class|time|battletag|race|gear|stats|talents
--   gear: slot=item.enchant.suffix.ilvl.quality, separated by ";" (inventory slots 1 to 19), or "off"; a negative
--   suffix is the item's first bonus (WoW Forever's random suffixes)
--   stats: key=value, separated by ";" (see STATS; a value the client does not give is left out)
--   talents: tree/points/talent,talent,... trees separated by ";"; talent: spell.tier.column.rank.max.name
--   (spell: the talent's spell, 0 if the client did not give it). WoW Forever (trait tree): no tree name, the
--   field holds "@" and the links between talents instead: "@1.2>3.2 2.3>3.3" (from tier.column to tier.column)
--   id: name-realm:G:time, a new one per reading (the bot keeps the latest)
-- Loaded after WallOfShameForever.lua, which gives ns.GetDB, ns.Identity, ns.Clean, ns.AddToOutbox.

local ADDON_NAME, ns = ...
local Armory = {}
ns.Armory = Armory

local db
local pending

-- Calls a game function that may not exist on this client; its results, or nothing
local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local results = { pcall(fn, ...) }
    if not results[1] then return end
    return select(2, unpack(results))
end

-- A number for the payload: whole numbers as they are, others with 2 decimals at most
local function Num(v)
    v = tonumber(v)
    if not v then return nil end
    if v == math.floor(v) then return tostring(v) end
    return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

-------------------------------------------------------------------------------
-- Data: no frames here (tested with lupa, see companion/tests/test_armory.py)
-------------------------------------------------------------------------------

-- slot=item.enchant.suffix.ilvl.quality for every slot that holds something
function Armory.ReadGear()
    local list = {}
    for slot = 1, 19 do
        local link = Call(GetInventoryItemLink, "player", slot)
        local itemString = type(link) == "string" and link:match("item:([%-%d:]*)")
        if itemString then
            local f = { strsplit(":", itemString) }
            local id = tonumber(f[1])
            if id and id > 0 then
                local ilvl = Call(C_Item and C_Item.GetDetailedItemLevelInfo, link)
                    or Call(GetDetailedItemLevelInfo, link) or select(4, Call(GetItemInfo, link))
                local quality = Call(GetInventoryItemQuality, "player", slot)
                -- WoW Forever: the random suffix (« de brigandage ») is a bonus of the item (its link like the
                -- current game's: item:id:enchant:4 gems:suffix:unique:level:spec:mask:context:count:bonuses…),
                -- sent as a negative suffix (v0.9.2) so that the companion 0.8.3 passes it as it is
                local suffix = tonumber(f[7]) or 0
                if suffix == 0 and (tonumber(f[13]) or 0) > 0 and tonumber(f[14]) then suffix = -tonumber(f[14]) end
                list[#list + 1] = slot .. "=" .. table.concat({ id, tonumber(f[2]) or 0, suffix,
                    tonumber(ilvl) or 0, tonumber(quality) or "" }, ".")
            end
        end
    end
    return table.concat(list, ";")
end

-- The stats of the game's character sheet. Each entry: key, function giving the value.
local function Stat(i, total)
    local _, value, pos, neg = Call(UnitStat, "player", i)
    if total then return value end
    if pos or neg then return (pos or 0) + (neg or 0) end
end
local function AttackPower(fn)
    local base, pos, neg = Call(fn, "player")
    if base then return base + (pos or 0) + (neg or 0) end
end
local function BestSchool(fn)
    local best
    for school = 2, 7 do
        local v = tonumber((Call(fn, school)))
        if v and (not best or v > best) then best = v end
    end
    return best
end
local STATS = {
    { "str", function() return Stat(1, true) end }, { "strB", function() return Stat(1) end },
    { "agi", function() return Stat(2, true) end }, { "agiB", function() return Stat(2) end },
    { "sta", function() return Stat(3, true) end }, { "staB", function() return Stat(3) end },
    { "int", function() return Stat(4, true) end }, { "intB", function() return Stat(4) end },
    { "spi", function() return Stat(5, true) end }, { "spiB", function() return Stat(5) end },
    { "armor", function() return select(2, Call(UnitArmor, "player")) end },
    { "hp", function() return Call(UnitHealthMax, "player") end },
    { "power", function() return Call(UnitPowerMax, "player") end },
    { "powerType", function() return Call(UnitPowerType, "player") end },
    -- melee
    { "ap", function() return AttackPower(UnitAttackPower) end },
    { "dmgMin", function() return (Call(UnitDamage, "player")) end },
    { "dmgMax", function() return select(2, Call(UnitDamage, "player")) end },
    { "speed", function() return (Call(UnitAttackSpeed, "player")) end },
    { "hit", function() return Call(GetHitModifier) end },
    { "crit", function() return Call(GetCritChance) end },
    -- ranged
    { "rap", function() return AttackPower(UnitRangedAttackPower) end },
    { "rspeed", function() return (Call(UnitRangedDamage, "player")) end },
    { "rdmgMin", function() return select(2, Call(UnitRangedDamage, "player")) end },
    { "rdmgMax", function() return select(3, Call(UnitRangedDamage, "player")) end },
    { "rcrit", function() return Call(GetRangedCritChance) end },
    -- spells: schools 2 holy, 3 fire, 4 nature, 5 frost, 6 shadow, 7 arcane
    { "sp", function() return BestSchool(GetSpellBonusDamage) end },
    { "sp2", function() return Call(GetSpellBonusDamage, 2) end },
    { "sp3", function() return Call(GetSpellBonusDamage, 3) end },
    { "sp4", function() return Call(GetSpellBonusDamage, 4) end },
    { "sp5", function() return Call(GetSpellBonusDamage, 5) end },
    { "sp6", function() return Call(GetSpellBonusDamage, 6) end },
    { "sp7", function() return Call(GetSpellBonusDamage, 7) end },
    { "heal", function() return Call(GetSpellBonusHealing) end },
    { "scrit", function() return BestSchool(GetSpellCritChance) end },
    { "shit", function() return Call(GetSpellHitModifier) end },
    { "mp5", function() local base = Call(GetManaRegen) return base and base * 5 end },
    { "mp5c", function() return select(2, Call(GetManaRegen)) and select(2, Call(GetManaRegen)) * 5 end },
    -- defense; resistances 2 fire, 3 nature, 4 frost, 5 shadow, 6 arcane
    { "def", function() local base, mod = Call(UnitDefense, "player") return base and base + (mod or 0) end },
    { "dodge", function() return Call(GetDodgeChance) end },
    { "parry", function() return Call(GetParryChance) end },
    { "block", function() return Call(GetBlockChance) end },
    { "res2", function() return select(2, Call(UnitResistance, "player", 2)) end },
    { "res3", function() return select(2, Call(UnitResistance, "player", 3)) end },
    { "res4", function() return select(2, Call(UnitResistance, "player", 4)) end },
    { "res5", function() return select(2, Call(UnitResistance, "player", 5)) end },
    { "res6", function() return select(2, Call(UnitResistance, "player", 6)) end },
}

function Armory.ReadStats()
    local list = {}
    for _, entry in ipairs(STATS) do
        local ok, value = pcall(entry[2])
        local text = ok and Num(value)
        if text then list[#list + 1] = entry[1] .. "=" .. text end
    end
    return table.concat(list, ";")
end

-- The talent's spell, from a hidden tooltip (the client gives no other way to it)
local scanTip
local function TalentSpell(tab, index)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "WallOfShameForeverScanTip", UIParent, "GameTooltipTemplate")
        if not scanTip then return 0 end
        Call(scanTip.SetOwner, scanTip, WorldFrame or UIParent, "ANCHOR_NONE")
    end
    if not (scanTip.SetTalent and scanTip.GetSpell) then return 0 end
    Call(scanTip.ClearLines, scanTip)
    Call(scanTip.SetTalent, scanTip, tab, index)
    local _, spell = Call(scanTip.GetSpell, scanTip)
    return tonumber(spell) or 0
end

local function CleanName(text) -- the talents' separators never appear in a name
    return (ns.Clean(text):gsub("[/%.]", " "))
end

-- WoW Forever: no Classic talent functions (GetTalentInfo…), the talents are a trait tree (C_Traits) holding the
-- class's 3 trees side by side, left to right as in Classic. Each talent has a position: its tree from the
-- gaps between positions, its tier from top to bottom and its column from left to right (600 apart).
local GAP = 1500 -- more than this between two talents side by side: the next tree
local STEP = 600

local function SpellName(spell)
    return Call(C_Spell and C_Spell.GetSpellName, spell) or (Call(GetSpellInfo, spell)) or ""
end

function Armory.ReadTraitTalents()
    local T = C_Traits
    local config = Call(C_ClassTalents and C_ClassTalents.GetActiveConfigID)
    local info = config and type(T) == "table" and Call(T.GetConfigInfo, config)
    if type(info) ~= "table" or type(info.treeIDs) ~= "table" then return "" end
    local talents = {}
    for _, treeID in ipairs(info.treeIDs) do
        for _, nodeID in ipairs(Call(T.GetTreeNodes, treeID) or {}) do
            local node = Call(T.GetNodeInfo, config, nodeID)
            if type(node) == "table" and node.isVisible ~= false and node.posX and node.posY then
                local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs or {})[1]
                local entry = entryID and Call(T.GetEntryInfo, config, entryID)
                local def = entry and entry.definitionID and Call(T.GetDefinitionInfo, entry.definitionID)
                local spell = def and (def.overriddenSpellID or def.spellID)
                if spell then
                    local targets = {}
                    for _, edge in ipairs(node.visibleEdges or {}) do
                        if edge.targetNode then targets[#targets + 1] = edge.targetNode end
                    end
                    talents[#talents + 1] = { id = nodeID, targets = targets, x = node.posX, y = node.posY, spell = spell,
                        rank = tonumber(node.activeRank or node.currentRank) or 0, max = tonumber(node.maxRanks) or 0,
                        name = (def.overrideName and def.overrideName ~= "") and def.overrideName or SpellName(spell) }
                end
            end
        end
    end
    if #talents == 0 then return "" end
    -- trees: split where two positions side by side are far apart
    table.sort(talents, function(a, b) return a.x < b.x end)
    local groups, last = {}, nil
    for _, t in ipairs(talents) do
        if not last or t.x - last > GAP then groups[#groups + 1] = {} end
        table.insert(groups[#groups], t)
        last = t.x
    end
    local out = {}
    for _, group in ipairs(groups) do
        local minX, minY = math.huge, math.huge
        for _, t in ipairs(group) do
            minX, minY = math.min(minX, t.x), math.min(minY, t.y)
        end
        table.sort(group, function(a, b) return a.y < b.y or (a.y == b.y and a.x < b.x) end)
        local list, points, place = {}, 0, {}
        for _, t in ipairs(group) do
            t.tier = math.floor((t.y - minY) / STEP + 0.5) + 1
            t.column = math.floor((t.x - minX) / STEP + 0.5) + 1
            place[t.id] = t.tier .. "." .. t.column
        end
        local links = {}
        for _, t in ipairs(group) do
            points = points + t.rank
            list[#list + 1] = table.concat({ t.spell, t.tier, t.column, t.rank, t.max, CleanName(t.name) }, ".")
            for _, target in ipairs(t.targets) do
                if place[target] then links[#links + 1] = place[t.id] .. ">" .. place[target] end
            end
        end
        -- no name from the game: the bot names the trees by class and order. The tree's name field carries the
        -- links between talents instead (v0.9.2, the companion 0.8.3 passes it as it is): "@tier.col>tier.col …"
        out[#out + 1] = "@" .. table.concat(links, " ") .. "/" .. points .. "/" .. table.concat(list, ",")
    end
    return table.concat(out, ";")
end

function Armory.ReadTalents()
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" then return Armory.ReadTraitTalents() end
    local trees = {}
    for tab = 1, tonumber((Call(GetNumTalentTabs))) or 0 do
        -- the tree's name: the first text GetTalentTabInfo gives (its results differ between clients)
        local treeName = ""
        for _, v in ipairs({ Call(GetTalentTabInfo, tab) }) do
            if type(v) == "string" and not tonumber(v) then treeName = v break end
        end
        local talents, points = {}, 0
        for i = 1, tonumber((Call(GetNumTalents, tab))) or 0 do
            local name, _, tier, column, rank, maxRank = Call(GetTalentInfo, tab, i)
            if name then
                rank = tonumber(rank) or 0
                points = points + rank
                talents[#talents + 1] = table.concat({ TalentSpell(tab, i), tonumber(tier) or 0, tonumber(column) or 0,
                    rank, tonumber(maxRank) or 0, CleanName(name) }, ".")
            end
        end
        trees[#trees + 1] = CleanName(treeName) .. "/" .. points .. "/" .. table.concat(talents, ",")
    end
    return table.concat(trees, ";")
end

function Armory.Payload(gear, stats, talents)
    local name, realm, guild, battleTag = ns.Identity()
    local _, classFile = UnitClass("player")
    local race = Call(UnitRace, "player")
    return table.concat({ "2", "G", name .. "-" .. realm .. ":G:" .. time(), name, realm, guild,
        UnitLevel("player"), classFile or "", time(), battleTag, ns.Clean(race), gear, stats, talents }, "|")
end

-- Only the latest reading of this character waits in the outbox
local function ReplaceInOutbox(payload)
    local name, realm = ns.Identity()
    local prefix = name .. "-" .. realm .. ":G:"
    for i = #db.outbox, 1, -1 do
        if (select(3, strsplit("|", db.outbox[i]))):sub(1, #prefix) == prefix then table.remove(db.outbox, i) end
    end
    ns.AddToOutbox(payload)
end

-- Reads and queues if something changed since the last reading queued. Returns true if queued.
function Armory.Queue()
    if not (db and db.discord and db.connection) then return false end
    local name, realm = ns.Identity()
    local key = name .. "-" .. realm
    db.gearSent = type(db.gearSent) == "table" and db.gearSent or {}
    if db.shareGear == false then
        if db.gearSent[key] == "off" then return false end
        ReplaceInOutbox(Armory.Payload("off", "", ""))
        db.gearSent[key] = "off"
        return true
    end
    local gear, talents = Armory.ReadGear(), Armory.ReadTalents()
    if gear == "" then return false end -- the client did not give the gear yet
    local signature = UnitLevel("player") .. "|" .. gear .. "|" .. talents
    if db.gearSent[key] == signature then return false end
    ReplaceInOutbox(Armory.Payload(gear, Armory.ReadStats(), talents))
    db.gearSent[key] = signature
    Armory.Report()
    return true
end

-- Once per character: what this client gave, for the bot's debug.jsonl (checks the real client)
function Armory.Report()
    local name, realm, guild, battleTag = ns.Identity()
    local key = name .. "-" .. realm
    db.gearReported = type(db.gearReported) == "table" and db.gearReported or {}
    -- v0.9.1: again, with the talents read from the trait tree (WoW Forever)
    if db.gearReported[key .. "#2"] then return end
    db.gearReported[key .. "#2"] = true
    local missing = {}
    for _, fn in ipairs({ "UnitStat", "UnitArmor", "UnitAttackPower", "UnitDamage", "UnitAttackSpeed", "GetHitModifier",
        "GetCritChance", "UnitRangedAttackPower", "UnitRangedDamage", "GetRangedCritChance", "GetSpellBonusDamage",
        "GetSpellBonusHealing", "GetSpellCritChance", "GetSpellHitModifier", "GetManaRegen", "UnitDefense",
        "GetDodgeChance", "GetParryChance", "GetBlockChance", "UnitResistance", "GetNumTalentTabs", "GetTalentTabInfo",
        "GetTalentInfo", "GetDetailedItemLevelInfo" }) do
        if type(_G[fn]) ~= "function" then missing[#missing + 1] = fn end
    end
    local tabInfo = {}
    for _, v in ipairs({ Call(GetTalentTabInfo, 1) }) do tabInfo[#tabInfo + 1] = tostring(v) end
    local talents = Armory.ReadTalents()
    local details = table.concat({ "missing=" .. table.concat(missing, ","), "tab1=" .. table.concat(tabInfo, ","),
        "stats=" .. Armory.ReadStats(), "talents=" .. talents:sub(1, 300) }, "~"):gsub("|", "/"):sub(1, 1500)
    local _, classFile = UnitClass("player")
    ns.AddToOutbox(table.concat({ "2", "X", key .. ":X:" .. time() .. ":armory", name, realm, guild,
        UnitLevel("player"), classFile or "", time(), battleTag, "armurerie", details }, "|"))
end

-- New connection code (another bot or Discord server): everything is sent again
function Armory.Resend()
    if not db or type(db.gearSent) ~= "table" then return end
    local name, realm = ns.Identity()
    db.gearSent[name .. "-" .. realm] = nil
    Armory.Schedule(2)
end

-- The option changed (« Show my gear on the site »)
function Armory.OnOptionChanged()
    Armory.Schedule(0)
end

-- Gear changes come several at once (a whole set): read once, a moment after the last one
function Armory.Schedule(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 3, function()
        pending = nil
        Armory.Queue()
    end)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
    "PLAYER_LEVEL_UP", "PLAYER_LOGOUT" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        db = ns.GetDB and ns.GetDB()
        if db and db.shareGear == nil then db.shareGear = true end
        Armory.Schedule(8) -- the client gives item levels and talents a moment after login
    elseif event == "PLAYER_LOGOUT" then
        Armory.Queue() -- right away: the game writes SavedVariables just after
    else
        Armory.Schedule(3)
    end
end)
