-- Shame Wall Forever: death strip
-- Draws a short-lived strip of colored blocks in the top-left corner so the
-- companion program can read a death in real time from a screen capture.
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

local strip, textures, hideToken = nil, {}, nil

function ns.ShowStrip(payload)
    if not GetPhysicalScreenSize then return end
    local blocks = ns.EncodeStrip(payload)
    if not strip then
        -- WorldFrame stays visible when the UI is hidden with Alt+Z
        strip = CreateFrame("Frame", nil, WorldFrame)
        strip:SetFrameStrata("TOOLTIP")
        strip:SetFrameLevel(10000)
        strip:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, 0)
    end

    -- size of one physical pixel in this frame's units
    local _, physHeight = GetPhysicalScreenSize()
    local size = BLOCK * 768 / (physHeight * strip:GetEffectiveScale())

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
    strip:SetSize(COLS * size, math.ceil(#blocks / COLS) * size)
    strip:Show()

    local token = {}
    hideToken = token
    C_Timer.After(SHOW_TIME, function()
        if hideToken == token then strip:Hide() end
    end)
end
