-- Wall of Shame Forever: the style kit of the windows, in the guild site's « forge » look: red frame with
-- a gold and black double rim, title on a red ribbon (Sansita), gold pill buttons, panels, bars, chips.
-- Textures in media/ui (drawn by tools/ui_textures.py), cut in 9 or 3 pieces so any size keeps sharp
-- corners. Everything here builds pieces; the windows (Hub.lua) put them together.
-- Loaded first after Locales.lua: ns.UI is used by the other files.

local ADDON_NAME, ns = ...
local UI = {}
ns.UI = UI

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local TEX = MEDIA .. "ui\\"
UI.TITLE_FONT = MEDIA .. "fonts\\Sansita-ExtraBoldItalic.ttf"
UI.FALLBACK_FONT = MEDIA .. "LilitaOne.ttf"
local WHITE = "Interface\\Buttons\\WHITE8X8"

UI.INK = { 0.10, 0.043, 0.024 }
UI.GOLD = { 0.94, 0.77, 0.43 }
UI.CREAM = { 0.97, 0.83, 0.54 }
UI.TEXT = { 0.96, 0.87, 0.69 }
UI.MUTED = { 0.79, 0.64, 0.48 }
UI.RED = { 0.79, 0.21, 0.11 }
UI.DARK = { 0.23, 0.035, 0.024 }
UI.OK = { 0.31, 0.82, 0.31 }
UI.BAD = { 1, 0.38, 0.38 }
local VARIANTS = { gold = UI.GOLD, red = UI.RED, dark = UI.DARK }

-- "|cffrrggbb" for a color table
function UI.Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-------------------------------------------------------------------------------
-- Fonts
-------------------------------------------------------------------------------

-- Titles: Sansita, cream with a thick black outline and a black shadow below right (the site's ribbon
-- letters); the game font if the file can't be read
function UI.TitleFont(fs, size, color)
    if not fs:SetFont(UI.TITLE_FONT, size, "THICKOUTLINE") then
        if not fs:SetFont(UI.FALLBACK_FONT, size, "THICKOUTLINE") then fs:SetFontObject("GameFontNormalLarge") end
    end
    local c = color or UI.CREAM
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetShadowColor(UI.INK[1], UI.INK[2], UI.INK[3], 1)
    fs:SetShadowOffset(2, -2)
    return fs
end

-- Small gold caption in Sansita (« Pour Lex Orcist · niv. 22 »), like the site's lines under a title
function UI.Caption(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if not fs:SetFont(UI.TITLE_FONT, size or 13, "OUTLINE") then fs:SetFontObject("GameFontNormalSmall") end
    fs:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
    fs:SetShadowColor(UI.INK[1], UI.INK[2], UI.INK[3], 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Body text: the game font (every accent and language), light parchment color
function UI.Text(parent, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    local c = color or UI.TEXT
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    return fs
end

-------------------------------------------------------------------------------
-- Slicing: 9 pieces (frames, panels) and 3 pieces (ribbon, pills, bars)
-------------------------------------------------------------------------------

-- tex: file; tw, th: its size; c: corner in texture pixels; size: corner on screen; inset: how far the
-- pieces go out of the frame (a shadow goes out)
function UI.Nine(frame, tex, tw, th, c, size, layer, inset, sub)
    inset = inset or 0
    local pieces = {}
    local u, v = c / tw, c / th
    local function piece(l, r, t, b)
        local p = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        p:SetTexture(tex)
        p:SetTexCoord(l, r, t, b)
        pieces[#pieces + 1] = p
        return p
    end
    local tl = piece(0, u, 0, v); tl:SetSize(size, size); tl:SetPoint("TOPLEFT", -inset, inset)
    local tr = piece(1 - u, 1, 0, v); tr:SetSize(size, size); tr:SetPoint("TOPRIGHT", inset, inset)
    local bl = piece(0, u, 1 - v, 1); bl:SetSize(size, size); bl:SetPoint("BOTTOMLEFT", -inset, -inset)
    local br = piece(1 - u, 1, 1 - v, 1); br:SetSize(size, size); br:SetPoint("BOTTOMRIGHT", inset, -inset)
    local t = piece(u, 1 - u, 0, v); t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local b = piece(u, 1 - u, 1 - v, 1); b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local l = piece(0, u, v, 1 - v); l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local r = piece(1 - u, 1, v, 1 - v); r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local m = piece(u, 1 - u, v, 1 - v); m:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); m:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    return pieces
end

-- Horizontal: caps of `cap` screen pixels at both ends, the middle stretched. vMax: the part of the
-- texture's height that is drawn (a pill uses its top 39 of 64 pixels).
function UI.Three(frame, tex, tw, capPx, cap, vMax, layer, sub)
    local u = capPx / tw
    local pieces = {}
    local function piece(l, r)
        local p = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        p:SetTexture(tex)
        p:SetTexCoord(l, r, 0, vMax or 1)
        pieces[#pieces + 1] = p
        return p
    end
    local left = piece(0, u); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(cap)
    local right = piece(1 - u, 1); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(cap)
    local mid = piece(u, 1 - u); mid:SetPoint("TOPLEFT", left, "TOPRIGHT"); mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return pieces
end

local function Tint(pieces, c, a)
    for _, p in ipairs(pieces) do p:SetVertexColor(c[1], c[2], c[3], a or 1) end
end
UI.Tint = Tint

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------

-- Dresses a frame as a window: soft shadow, rim, lit middle, parchment grain
function UI.Window(frame)
    UI.Nine(frame, TEX .. "shadow", 64, 64, 24, 40, "BACKGROUND", 18, -8)
    UI.Nine(frame, TEX .. "frame", 128, 128, 48, 48, "BACKGROUND", 0, -4)
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetTexture(TEX .. "glow")
    glow:SetPoint("TOPLEFT", 24, -24)
    glow:SetPoint("BOTTOMRIGHT", -24, 24)
    glow:SetAlpha(0.9)
    local grain = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    grain:SetPoint("TOPLEFT", 22, -22)
    grain:SetPoint("BOTTOMRIGHT", -22, 22)
    local tiled = pcall(grain.SetTexture, grain, TEX .. "grain", "REPEAT", "REPEAT")
    if tiled then
        local function Fit()
            local w, h = grain:GetSize()
            if w and w > 0 then grain:SetTexCoord(0, w / 128, 0, h / 128) end
        end
        frame:HookScript("OnSizeChanged", Fit)
        Fit()
    else
        grain:SetTexture(TEX .. "grain")
    end
    grain:SetAlpha(0.8)
    frame.glow, frame.grain = glow, grain
    return frame
end

-- Fade in on show (off with the « animations » option), and Escape closes it
function UI.Appear(frame, db)
    if not frame.CreateAnimationGroup then return end
    local ag = frame:CreateAnimationGroup()
    local fade = ag and ag.CreateAnimation and ag:CreateAnimation("Alpha")
    if not fade then return end
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.15)
    frame:HookScript("OnShow", function()
        if db and db.animations == false then return end
        ag:Stop()
        ag:Play()
    end)
end

-- A movable window: dragged anywhere on its frame, kept on screen, position saved in db[key]
function UI.Movable(frame, db, key)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if db and key then
            local point, _, rel, x, y = self:GetPoint(1)
            db[key] = { point = point, rel = rel, x = x, y = y }
        end
    end)
    local saved = db and key and db[key]
    frame:ClearAllPoints()
    if type(saved) == "table" and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.rel or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-------------------------------------------------------------------------------
-- Ribbon title
-------------------------------------------------------------------------------

-- A title on the red ribbon; its width follows the text (:SetText)
function UI.Ribbon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    size = size or 20
    local h = math.floor(size * 1.9)
    f:SetHeight(h)
    UI.Three(f, TEX .. "ribbon", 512, 48, math.floor(h * 0.75), 1, "ARTWORK")
    f.text = f:CreateFontString(nil, "OVERLAY")
    UI.TitleFont(f.text, size)
    f.text:SetPoint("CENTER", 0, 1)
    function f:SetText(text)
        self.text:SetText(text)
        self:SetWidth(math.max(h * 2, (self.text:GetStringWidth() or 0) + h * 1.3))
    end
    return f
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------

local function ClickSound()
    if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
end
UI.ClickSound = ClickSound

-- Gold pill (variant "red": the active tab, "dark": a secondary action). b.label, b:SetVariant(v),
-- b:SetLabel(text) (width follows the text when no width is given)
function UI.Button(parent, opts)
    opts = opts or {}
    local h = opts.height or 26
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(opts.width or 80, h + 3)
    b.pieces = UI.Three(b, TEX .. "pill", 128, 20, math.floor((h + 3) * 20 / 39), 39 / 64, "BACKGROUND")
    b.label = b:CreateFontString(nil, "OVERLAY")
    if not b.label:SetFont(UI.TITLE_FONT, opts.size or 13, "") then b.label:SetFontObject("GameFontHighlightSmall") end
    b.label:SetPoint("CENTER", 0, 2)
    b.autoWidth = not opts.width
    function b:SetVariant(v)
        self.variant = v or "gold"
        local c = VARIANTS[self.variant] or UI.GOLD
        Tint(self.pieces, c)
        local t = self.variant == "gold" and UI.INK or UI.CREAM
        self.label:SetTextColor(t[1], t[2], t[3])
    end
    function b:SetLabel(text)
        self.label:SetText(text)
        if self.autoWidth then self:SetWidth(math.max(h * 2, (self.label:GetStringWidth() or 0) + h + 6)) end
    end
    b:SetVariant(opts.variant)
    b:SetScript("OnEnter", function(self)
        local c = VARIANTS[self.variant] or UI.GOLD
        Tint(self.pieces, { math.min(1, c[1] * 1.15 + 0.06), math.min(1, c[2] * 1.15 + 0.06), math.min(1, c[3] * 1.15 + 0.06) })
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetVariant(self.variant)
        if self.tip then GameTooltip:Hide() end
    end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 0, 0) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 2) end)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    if opts.onClick then
        b:SetScript("OnClick", function(self)
            ClickSound()
            opts.onClick(self)
        end)
    end
    if opts.text then b:SetLabel(opts.text) end
    return b
end

-- Round gold close button
function UI.Close(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(TEX .. "close")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(TEX .. "close")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    b:SetScript("OnMouseDown", function() t:SetPoint("TOPLEFT", 0, -1); t:SetPoint("BOTTOMRIGHT", 0, -1) end)
    b:SetScript("OnMouseUp", function() t:SetAllPoints() end)
    b:SetScript("OnClick", function()
        ClickSound()
        onClick()
    end)
    return b
end

-------------------------------------------------------------------------------
-- Panels, chips, bars, lines
-------------------------------------------------------------------------------

-- Dark see-through panel with rounded corners and a faint gold border
function UI.Panel(frame)
    frame.panel = UI.Nine(frame, TEX .. "panel", 64, 64, 16, 14, "BACKGROUND")
    return frame
end

-- Small pill with text (Alliance / Horde, statuses): :SetText, :SetVariant
function UI.Chip(parent, variant)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(19)
    f.pieces = UI.Three(f, TEX .. "pill", 128, 20, 10, 39 / 64, "BACKGROUND")
    f.text = f:CreateFontString(nil, "OVERLAY")
    if not f.text:SetFont(UI.TITLE_FONT, 11, "") then f.text:SetFontObject("GameFontHighlightSmall") end
    f.text:SetPoint("CENTER", 0, 1)
    function f:SetVariant(v)
        local c = VARIANTS[v] or UI.GOLD
        Tint(self.pieces, c)
        local t = (v or "gold") == "gold" and UI.INK or UI.CREAM
        self.text:SetTextColor(t[1], t[2], t[3])
    end
    function f:SetText(text)
        self.text:SetText(text)
        self:SetWidth((self.text:GetStringWidth() or 0) + 18)
    end
    f:SetVariant(variant)
    return f
end

-- Progress bar: gold fill in a black capsule; :SetValue(0..1)
function UI.Bar(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    height = height or 14
    f:SetHeight(height)
    UI.Three(f, TEX .. "bar", 64, 8, height / 2, 16 / 32, "BACKGROUND")
    f.fill = CreateFrame("Frame", nil, f)
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    UI.Three(f.fill, TEX .. "barfill", 64, 8, height / 2, 16 / 32, "ARTWORK")
    function f:SetValue(v)
        v = math.max(0, math.min(1, tonumber(v) or 0))
        local w = (self:GetWidth() or 0) * v
        self.fill:SetShown(w >= height)
        self.fill:SetWidth(math.max(height, w))
        self.value = v
    end
    f:SetScript("OnSizeChanged", function(self) self:SetValue(self.value or 0) end)
    return f
end

-- Thin gold line
function UI.Line(parent, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    t:SetVertexColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], alpha or 0.25)
    t:SetHeight(1)
    return t
end

-------------------------------------------------------------------------------
-- Scrolling list: mouse wheel and a thin gold thumb
-------------------------------------------------------------------------------

-- Returns the scroll frame; put content in scroll.child and call scroll:SetContentHeight(h)
function UI.Scroll(parent)
    local s = CreateFrame("ScrollFrame", nil, parent)
    s.child = CreateFrame("Frame", nil, s)
    s.child:SetSize(1, 1)
    s:SetScrollChild(s.child)
    s.thumb = s:CreateTexture(nil, "OVERLAY")
    s.thumb:SetTexture(WHITE)
    s.thumb:SetVertexColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.7)
    s.thumb:SetWidth(3)
    s.content = 1
    local function Update()
        local view = s:GetHeight() or 1
        local max = math.max(0, s.content - view)
        local pos = math.min(max, math.max(0, s:GetVerticalScroll() or 0))
        if max <= 0 then
            s.thumb:Hide()
            return
        end
        local h = math.max(20, view * view / s.content)
        s.thumb:SetHeight(h)
        s.thumb:ClearAllPoints()
        s.thumb:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, -(view - h) * pos / max)
        s.thumb:Show()
    end
    function s:SetContentHeight(h)
        self.content = math.max(1, h)
        self.child:SetHeight(self.content)
        self.child:SetWidth(math.max(1, self:GetWidth() or 1))
        local max = math.max(0, self.content - (self:GetHeight() or 0))
        if (self:GetVerticalScroll() or 0) > max then self:SetVerticalScroll(max) end
        Update()
    end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, self.content - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
        Update()
    end)
    s:SetScript("OnSizeChanged", function(self)
        self.child:SetWidth(math.max(1, self:GetWidth() or 1))
        Update()
    end)
    return s
end
