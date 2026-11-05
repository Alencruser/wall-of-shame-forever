-- Wall of Shame Forever: death strip
-- Draws a short-lived strip of colored blocks in a corner or at the middle of an edge of the
-- game screen (option, top left by default) so the companion program can read a death in real
-- time from a screen capture. It looks at every position, the player sets nothing there.
-- The decoder lives in companion/strip.py: keep both in sync.

local _, ns = ...

local BLOCK = 4     -- block size in physical pixels
local COLS = 48     -- blocks per row
local SHOW_TIME = 3 -- seconds on screen
local MAX_PAYLOAD = 240
-- Every channel uses 4 levels (0, 85, 170, 255): survives gamma and brightness settings
local HEADER = {
    { 0, 0, 0 }, { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 }, -- calibration
    { 3, 0, 3 }, { 0, 3, 0 }, { 3, 3, 0 }, { 0, 0, 3 }, -- magic
}

local function Fletcher16(s)
    local a, b = 0, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 255
        b = (b + a) % 255
    end
    return a, b
end

-- Returns the list of blocks, each { r, g, b } with levels 0..3:
-- header, then length (2 bytes), payload, checksum (2 bytes), 2 bits per channel
function ns.EncodeStrip(payload)
    payload = payload:sub(1, MAX_PAYLOAD)
    local bytes = { math.floor(#payload / 256), #payload % 256 }
    for i = 1, #payload do bytes[#bytes + 1] = payload:byte(i) end
    local a, b = Fletcher16(payload)
    bytes[#bytes + 1] = a
    bytes[#bytes + 1] = b

    local digits = {}
    for _, byte in ipairs(bytes) do
        digits[#digits + 1] = math.floor(byte / 64) % 4
        digits[#digits + 1] = math.floor(byte / 16) % 4
        digits[#digits + 1] = math.floor(byte / 4) % 4
        digits[#digits + 1] = byte % 4
    end

    local blocks = {}
    for _, h in ipairs(HEADER) do blocks[#blocks + 1] = h end
    for i = 1, #digits, 3 do
        blocks[#blocks + 1] = { digits[i], digits[i + 1] or 0, digits[i + 2] or 0 }
    end
    return blocks
end

-- Where the strip can be (never in the middle of the screen). The frame always has room for the
-- longest payload, so the blocks start at the same spot whatever the length: the companion
-- computes it from the window size (companion/strip.py, POSITIONS and MAX_HEIGHT)
ns.STRIP_POSITIONS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local VALID = {}
for _, p in ipairs(ns.STRIP_POSITIONS) do VALID[p] = true end
local MAX_ROWS = math.ceil((#HEADER + math.ceil((MAX_PAYLOAD + 4) * 4 / 3)) / COLS)

function ns.StripPosition()
    local db = ns.GetDB and ns.GetDB()
    local p = db and db.stripPosition
    return VALID[p] and p or "TOPLEFT"
end

-- size of one block (BLOCK physical pixels) in the units of a frame on WorldFrame
local function BlockSize(frame)
    local _, physHeight = GetPhysicalScreenSize()
    return BLOCK * 768 / (physHeight * frame:GetEffectiveScale())
end

local function NewFrame()
    -- WorldFrame stays visible when the UI is hidden with Alt+Z
    local f = CreateFrame("Frame", nil, WorldFrame)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(10000)
    return f
end

local function Place(frame, size)
    local p = ns.StripPosition()
    frame:ClearAllPoints()
    frame:SetPoint(p, WorldFrame, p, 0, 0)
    frame:SetSize(COLS * size, MAX_ROWS * size)
end

local strip, textures, hideToken = nil, {}, nil

function ns.ShowStrip(payload)
    if not GetPhysicalScreenSize then return end
    local blocks = ns.EncodeStrip(payload)
    strip = strip or NewFrame()
    local size = BlockSize(strip)
    Place(strip, size)

    for i, block in ipairs(blocks) do
        local tex = textures[i]
        if not tex then
            tex = strip:CreateTexture(nil, "OVERLAY")
            textures[i] = tex
        end
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", strip, "TOPLEFT", col * size, -row * size)
        tex:SetSize(size, size)
        tex:SetColorTexture(block[1] / 3, block[2] / 3, block[3] / 3)
        tex:Show()
    end
    for i = #blocks + 1, #textures do textures[i]:Hide() end
    strip:Show()

    local token = {}
    hideToken = token
    C_Timer.After(SHOW_TIME, function()
        if hideToken == token then strip:Hide() end
    end)
end

-- Options: shows for 2 seconds where the strip goes, as a plain golden box (one colour: the
-- companion never reads it as a strip)
local preview, previewToken
function ns.PreviewStrip()
    if not GetPhysicalScreenSize then return end
    if not preview then
        preview = NewFrame()
        local fill = preview:CreateTexture(nil, "OVERLAY")
        fill:SetAllPoints()
        fill:SetColorTexture(1, 0.82, 0.2, 0.8)
    end
    Place(preview, BlockSize(preview))
    preview:Show()
    local token = {}
    previewToken = token
    C_Timer.After(2, function()
        if previewToken == token then preview:Hide() end
    end)
end
