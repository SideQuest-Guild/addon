-- SideQuest/UI/Skin.lua
-- Shared visual chrome: colors/fonts, the native Forever/Camelot window
-- frame (NineSliceUtil + a PortraitFrameTemplate layout with Camelot's
-- offset overrides baked in), chamfered chambers/buttons/wells/tabs cut in
-- the guild site's citadel language, and the addon's motion vocabulary
-- (window open, tab crossfade, the raid-night wax-seal stamp, toast
-- slide-in). Every builder here is reused by every tab/sub-tab in
-- Main.lua and by BidPopup.lua -- there is exactly one of each component.
-- Loads before Main.lua/BidPopup.lua (see SideQuest.toc); those files pull
-- every primitive back out of the UI table instead of redefining it.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
local UI = SideQuest.UI

if not CreateFrame then
    return UI -- headless (no Blizzard UI environment); nothing to build
end

--------------------------------------------------------------------------
-- Media, tokens
--------------------------------------------------------------------------

local MEDIA_TEX = "Interface\\AddOns\\SideQuest\\Media\\Skin\\"
local FONT_DISPLAY = "Interface\\AddOns\\SideQuest\\Media\\Fonts\\LibertinusSerifDisplay.ttf"
local FONT_BODY = "Interface\\AddOns\\SideQuest\\Media\\Fonts\\EBGaramond.ttf"
local FONT_BODY_ITALIC = "Interface\\AddOns\\SideQuest\\Media\\Fonts\\EBGaramond-Italic.ttf"

-- DESIGN.md color tokens, RGBA 0-1.
local C = {
    night = { 0x0a / 255, 0x0f / 255, 0x1a / 255, 1 },
    night2 = { 0x10 / 255, 0x1a / 255, 0x2c / 255, 1 },
    night3 = { 0x18 / 255, 0x25 / 255, 0x3d / 255, 1 },
    royal = { 0x22 / 255, 0x38 / 255, 0x6a / 255, 1 },
    royal2 = { 0x2e / 255, 0x4a / 255, 0x85 / 255, 1 },
    stone = { 150 / 255, 172 / 255, 210 / 255, 0.26 },
    stone2 = { 150 / 255, 172 / 255, 210 / 255, 0.13 },
    gold = { 0xd8 / 255, 0xab / 255, 0x5c / 255, 1 },
    goldDeep = { 0xa8 / 255, 0x84 / 255, 0x49 / 255, 1 },
    goldHi = { 0xf0 / 255, 0xdc / 255, 0xae / 255, 1 },
    ink = { 0xf2 / 255, 0xef / 255, 0xe9 / 255, 1 },
    inkMuted = { 0xcf / 255, 0xca / 255, 0xc1 / 255, 1 },
    inkFaint = { 0x9d / 255, 0x97 / 255, 0x8d / 255, 1 },
    mist = { 0xc4 / 255, 0xcd / 255, 0xdd / 255, 1 },
    mist2 = { 0x96 / 255, 0xa2 / 255, 0xb8 / 255, 1 },
    flavor = { 1, 0xd3 / 255, 0x6a / 255, 1 },
    errorC = { 0xe0 / 255, 0xa4 / 255, 0x79 / 255, 1 },
    menuVeil = { 14 / 255, 14 / 255, 15 / 255, 0.55 },
    online = { 0.35, 0.86, 0.4, 1 },
    offline = { 0.5, 0.5, 0.52, 1 },
    -- DESIGN.md button-primary textColor ("#17130c"): near-black ink used
    -- on filled gold/gold-deep surfaces (the raid-night step plate) where
    -- the usual warm-white ink would not contrast.
    inkOnGold = { 0x17 / 255, 0x13 / 255, 0x0c / 255, 1 },
}

local function setColor(region, color)
    if region.SetColorTexture then
        region:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    elseif region.SetTexture then
        region:SetTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

local function makeFontString(parent, font, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if fs.SetFont then
        fs:SetFont(font or FONT_BODY, size or 13, "")
    end
    if color and fs.SetTextColor then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    if justify and fs.SetJustifyH then
        fs:SetJustifyH(justify)
    end
    return fs
end

--- Text-shadow ("shade" in DESIGN.md): legibility over busy painted art.
local function shade(fs)
    if fs.SetShadowOffset then
        fs:SetShadowOffset(1, -1)
    end
    if fs.SetShadowColor then
        fs:SetShadowColor(0, 0, 0, 0.85)
    end
    return fs
end

--- A hairline 1px rule (table row dividers and small rules inside chambers).
local function hairline(parent, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    if width then
        line:SetWidth(width)
    end
    setColor(line, { 1, 1, 1, 0.09 })
    return line
end

-- WoW FontStrings have no letter-spacing; tracked caps are built by hand
-- with U+2009 (thin space) between glyphs (verified present in all three
-- shipped fonts' cmaps; U+200A hair space is not -- see Media/PROVENANCE.md).
-- Decimal escapes: the game runs Lua 5.1, which has no hex escape and
-- would print the letters "xE2x80x89" instead.
local THIN_SPACE = "\226\128\137" -- UTF-8 for U+2009
local function trackedCaps(text)
    local out = {}
    for i = 1, #text do
        out[#out + 1] = text:sub(i, i)
    end
    return table.concat(out, THIN_SPACE):upper()
end

--------------------------------------------------------------------------
-- Slicers for the addon's own art. Every texture in Media/Skin is drawn at
-- 2x (tools/skin-art/render.mjs), so slice sizes are given in source
-- pixels and halved on screen: a 24 px corner covers 12 UI units.
--------------------------------------------------------------------------

local function skinTexture(frame, texName, layer, subLevel)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel)
    if t.SetTexture then
        t:SetTexture(MEDIA_TEX .. texName)
    end
    return t
end

--- 9-slice: four fixed corners, four stretched edges, empty centre (the
-- frame's own fill shows through). `cornerPx` is the corner in source px.
local function sliceNineSlice(frame, texName, texW, texH, cornerPx, layer)
    local uvX, uvY = cornerPx / texW, cornerPx / texH
    local corner = cornerPx / 2
    local function mk()
        return skinTexture(frame, texName, layer or "BORDER")
    end
    local tl, tr, bl, br = mk(), mk(), mk(), mk()
    tl:SetSize(corner, corner)
    tl:SetPoint("TOPLEFT")
    tl:SetTexCoord(0, uvX, 0, uvY)
    tr:SetSize(corner, corner)
    tr:SetPoint("TOPRIGHT")
    tr:SetTexCoord(1 - uvX, 1, 0, uvY)
    bl:SetSize(corner, corner)
    bl:SetPoint("BOTTOMLEFT")
    bl:SetTexCoord(0, uvX, 1 - uvY, 1)
    br:SetSize(corner, corner)
    br:SetPoint("BOTTOMRIGHT")
    br:SetTexCoord(1 - uvX, 1, 1 - uvY, 1)
    local top, bottom, left, right = mk(), mk(), mk(), mk()
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    top:SetTexCoord(uvX, 1 - uvX, 0, uvY)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    bottom:SetTexCoord(uvX, 1 - uvX, 1 - uvY, 1)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    left:SetTexCoord(0, uvX, uvY, 1 - uvY)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    right:SetTexCoord(1 - uvX, 1, uvY, 1 - uvY)
    return { tl = tl, tr = tr, bl = bl, br = br, top = top, bottom = bottom, left = left, right = right }
end

--- Horizontal 3-slice filling `frame`: fixed end caps (`capPx` source px)
-- and a stretched middle. Used by buttons, wells and ribbons. `vMax` is the
-- art's share of the file's height when it sits on a taller power-of-two
-- canvas (48 px of art in a 64 px file = 0.75).
local function sliceThreeSliceH(frame, texName, texW, capPx, layer, subLevel, vMax)
    local uv = capPx / texW
    local cap = capPx / 2
    vMax = vMax or 1
    local left = skinTexture(frame, texName, layer, subLevel)
    left:SetWidth(cap)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetTexCoord(0, uv, 0, vMax)
    local right = skinTexture(frame, texName, layer, subLevel)
    right:SetWidth(cap)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetTexCoord(1 - uv, 1, 0, vMax)
    local mid = skinTexture(frame, texName, layer, subLevel)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    mid:SetTexCoord(uv, 1 - uv, 0, vMax)
    return { left = left, mid = mid, right = right }
end

local function forSlices(slices, fn)
    for _, piece in pairs(slices) do
        fn(piece)
    end
end

--- Tints every piece of a sliced set (state changes reuse one texture).
local function tintSlices(slices, r, g, b, a)
    forSlices(slices, function(piece)
        piece:SetVertexColor(r, g, b, a or 1)
    end)
end

--------------------------------------------------------------------------
-- Chamber: the site's chamber cut in Forever's chamfered shape. A gilded
-- rim with a soft inner shadow and the guild-gold-deep hairline (all in
-- Chamber.tga), a night gradient fill, and a faceted diamond riveted onto
-- each cut corner.
--------------------------------------------------------------------------

local CHAMBER_TEX, CHAMBER_CORNER_PX = 64, 24
-- Centre of the rim's diagonal cut, from the corner, in UI units: the rim
-- line runs 2.5 px in and the cut is 14 px (see render.mjs).
local CHAMBER_RIVET = 4.4

local function nightFill(frame, inset)
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    fill:SetPoint("TOPLEFT", inset or 2, -(inset or 2))
    fill:SetPoint("BOTTOMRIGHT", -(inset or 2), inset or 2)
    if fill.SetGradient and CreateColor then
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetGradient("VERTICAL", CreateColor(C.night[1], C.night[2], C.night[3], 0.97),
            CreateColor(C.night2[1], C.night2[2], C.night2[3], 0.97))
    else
        setColor(fill, C.night2)
    end
    return fill
end

local function createChamber(parent, name)
    local chamber = CreateFrame("Frame", name, parent)
    nightFill(chamber)
    chamber.rim = sliceNineSlice(chamber, "Chamber", CHAMBER_TEX, CHAMBER_TEX, CHAMBER_CORNER_PX)

    -- Content area: clear of the rim and its hairline (5 units in).
    local inner = CreateFrame("Frame", nil, chamber)
    inner:SetPoint("TOPLEFT", 8, -8)
    inner:SetPoint("BOTTOMRIGHT", -8, 8)
    chamber.inner = inner

    chamber.diamonds = {}
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local d = skinTexture(chamber, "Diamond", "OVERLAY", 2)
        d:SetSize(9, 9)
        local xo = point:find("LEFT") and CHAMBER_RIVET or -CHAMBER_RIVET
        local yo = point:find("TOP") and -CHAMBER_RIVET or CHAMBER_RIVET
        d:SetPoint("CENTER", chamber, point, xo, yo)
        chamber.diamonds[point] = d
    end
    return chamber
end

--------------------------------------------------------------------------
-- Ribbon heading: the site's royal swallowtail ribbon (Ribbon.tga, 3-sliced)
-- centred on the chamber's top edge and sized to its label, never to the
-- chamber, so it reads as a banner and not a title bar.
--------------------------------------------------------------------------

local RIBBON_TEX_W, RIBBON_CAP_PX, RIBBON_H = 256, 40, 32

-- The client loads an addon font file the first time it draws it, and
-- GetStringWidth reads 0 until then, so a ribbon or tab sized only at build
-- time collapses to its padding. `fitToText` sizes the frame now and again
-- every time it shows, retrying for a couple of seconds while the label
-- still measures 0. Returns the refit function for callers that change the
-- label later.
local FIT_RETRIES, FIT_RETRY_DELAY = 20, 0.1

local function fitToText(frame, label, fit)
    local function attempt(triesLeft)
        local w = label.GetStringWidth and label:GetStringWidth() or 0
        fit(w)
        local text = label:GetText()
        if w <= 0 and text and text ~= "" and triesLeft > 0 and C_Timer then
            C_Timer.After(FIT_RETRY_DELAY, function()
                attempt(triesLeft - 1)
            end)
        end
    end
    local function refit()
        attempt(FIT_RETRIES)
    end
    frame:HookScript("OnShow", refit)
    refit()
    return refit
end

local function createRibbon(chamber, text)
    local ribbon = CreateFrame("Frame", nil, chamber)
    ribbon:SetHeight(RIBBON_H)
    ribbon:SetPoint("CENTER", chamber, "TOP", 0, 0)
    ribbon:SetFrameLevel(chamber:GetFrameLevel() + 5)
    ribbon.slices = sliceThreeSliceH(ribbon, "Ribbon", RIBBON_TEX_W, RIBBON_CAP_PX, "ARTWORK")
    local label = makeFontString(ribbon, FONT_DISPLAY, 12, C.ink, "CENTER")
    label:SetPoint("CENTER", 0, 1)
    shade(label)
    ribbon.label = label
    label:SetText(trackedCaps(text or ""))
    local refit = fitToText(ribbon, label, function(w)
        ribbon:SetWidth(math.max(132, w + 2 * (RIBBON_CAP_PX / 2) + 28))
    end)
    function ribbon:SetLabel(t)
        label:SetText(trackedCaps(t or ""))
        refit()
    end
    return ribbon
end

--- Sub-heading: tracked caps, then the site's divider: a small diamond and a
-- gold-deep line fading to the right. Nothing sits above a sub-heading.
local function createSubHeading(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(14)
    local label = makeFontString(row, FONT_DISPLAY, 11, C.gold, "LEFT")
    label:SetPoint("LEFT")
    label:SetText(trackedCaps(text))
    local gem = skinTexture(row, "Diamond", "ARTWORK")
    gem:SetSize(6, 6)
    gem:SetPoint("LEFT", label, "RIGHT", 8, 0)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", gem, "RIGHT", 3, 0)
    line:SetPoint("RIGHT")
    line:SetColorTexture(1, 1, 1, 1)
    if line.SetGradient and CreateColor then
        line:SetGradient("HORIZONTAL", CreateColor(C.goldDeep[1], C.goldDeep[2], C.goldDeep[3], 0.9),
            CreateColor(C.goldDeep[1], C.goldDeep[2], C.goldDeep[3], 0))
    else
        setColor(line, C.goldDeep)
    end
    row.label, row.gem, row.line = label, gem, line
    return row
end

--------------------------------------------------------------------------
-- Buttons: chamfered 3-slice art. Primary = royal body in a gilded rim;
-- quiet = night body in a bronze rim. Hover lights a warm inner glow (ADD),
-- pressed sinks the label a pixel and darkens, disabled desaturates and
-- explains why in a tooltip. `SetSelected` turns a quiet button primary
-- (the chosen answer in a group).
--------------------------------------------------------------------------

local BTN_TEX_W, BTN_CAP_PX, BTN_V = 128, 16, 48 / 64
local BTN_TEX = { primary = "ButtonPrimary", quiet = "ButtonQuiet" }

local function setSliceTexture(slices, texName)
    forSlices(slices, function(piece)
        piece:SetTexture(MEDIA_TEX .. texName)
    end)
end

local function createButton(parent, kind, text, width, height)
    kind = (kind == "primary") and "primary" or "quiet"
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 90, height or 24)
    local slices = sliceThreeSliceH(btn, BTN_TEX[kind], BTN_TEX_W, BTN_CAP_PX, "BACKGROUND", nil, BTN_V)
    local glow = sliceThreeSliceH(btn, "ButtonGlow", BTN_TEX_W, BTN_CAP_PX, "ARTWORK", nil, BTN_V)
    forSlices(glow, function(piece)
        piece:SetBlendMode("ADD")
        piece:SetAlpha(0)
    end)
    local label = makeFontString(btn, FONT_BODY, 12, C.ink, "CENTER")
    label:SetPoint("CENTER", 0, 1)
    shade(label)
    if text then
        label:SetText(text)
    end
    btn.slices, btn.glow, btn.label, btn.kind = slices, glow, label, kind
    btn.__enabled, btn.__selected = true, false

    local function paint(hover, pressed)
        local enabled = btn.__enabled
        local face = (btn.__selected or btn.kind == "primary") and "primary" or "quiet"
        forSlices(slices, function(piece)
            piece:SetDesaturated(not enabled)
            local v = pressed and 0.8 or 1
            piece:SetVertexColor(v, v, v, enabled and 1 or 0.55)
        end)
        forSlices(glow, function(piece)
            piece:SetAlpha((enabled and hover and not pressed) and 0.55 or 0)
        end)
        local col
        if not enabled then
            col = C.inkFaint
        elseif face == "primary" then
            col = C.ink
        else
            col = hover and C.goldHi or C.mist
        end
        label:SetTextColor(col[1], col[2], col[3], 1)
        label:ClearAllPoints()
        label:SetPoint("CENTER", 0, pressed and 0 or 1)
    end
    btn.Paint = paint
    paint(false, false)

    btn:SetScript("OnEnter", function()
        paint(true, false)
        if not btn.__enabled and btn.__disabledReason and GameTooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(btn.__disabledReason)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        paint(false, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    btn:SetScript("OnMouseDown", function()
        if btn.__enabled then paint(true, true) end
    end)
    btn:SetScript("OnMouseUp", function()
        paint(btn:IsMouseOver(), false)
    end)
    btn.SetText = function(_, t) label:SetText(t) end
    btn.GetText = function() return label:GetText() end
    local nativeSetEnabled = btn.SetEnabled
    btn.SetEnabled = function(self, enabled, reason)
        enabled = not not enabled
        self.__enabled = enabled
        self.__disabledReason = (not enabled) and reason or nil
        if nativeSetEnabled then nativeSetEnabled(self, enabled) end
        paint(false, false)
    end
    btn.Disable = function(self) self:SetEnabled(false) end
    btn.Enable = function(self) self:SetEnabled(true) end
    --- A quiet button that is the chosen one of a group wears the primary face.
    btn.SetSelected = function(self, selected)
        self.__selected = not not selected
        setSliceTexture(slices, BTN_TEX[(self.__selected or self.kind == "primary") and "primary" or "quiet"])
        paint(false, false)
    end
    return btn
end

--------------------------------------------------------------------------
-- Field wells (EditBoxes): a sunken chamfered well (FieldWell.tga,
-- 3-sliced); the rim warms to gold while focused; placeholder text shows
-- only while empty.
--------------------------------------------------------------------------

local WELL_TEX_W, WELL_CAP_PX, WELL_V = 128, 16, 48 / 64

local function skinEditBox(editBox, placeholderText)
    local slices = sliceThreeSliceH(editBox, "FieldWell", WELL_TEX_W, WELL_CAP_PX, "BACKGROUND", nil, WELL_V)
    if editBox.SetTextInsets then
        editBox:SetTextInsets(9, 9, 0, 0)
    end
    local placeholder = makeFontString(editBox, FONT_BODY_ITALIC, 12, C.mist2, "LEFT")
    placeholder:SetPoint("LEFT", 9, 0)
    placeholder:SetText(placeholderText or "Search")
    local function refresh()
        placeholder:SetShown(not editBox.GetText or editBox:GetText() == "")
    end
    if editBox.HookScript then
        editBox:HookScript("OnTextChanged", refresh)
        editBox:HookScript("OnEditFocusGained", function()
            tintSlices(slices, 1, 0.86, 0.6, 1)
        end)
        editBox:HookScript("OnEditFocusLost", function()
            tintSlices(slices, 1, 1, 1, 1)
        end)
    end
    refresh()
    editBox.slices, editBox.placeholder = slices, placeholder
    return editBox
end

--------------------------------------------------------------------------
-- Checkboxes: Forever's own checkbox-minimal / checkmark-minimal atlases.
--------------------------------------------------------------------------

local function createCheckbox(parent, size)
    size = size or 16
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(size, size)
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cb)
    bg:SetAtlas("checkbox-minimal")
    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetAllPoints(cb)
    check:SetAtlas("checkmark-minimal")
    if cb.SetCheckedTexture then
        cb:SetCheckedTexture(check)
    end
    cb.bg, cb.check = bg, check
    return cb
end

--- Forever's own collapse/expand arrow button (common-button-collapseExpand),
-- pointing down while collapsed and up while open.
local function createExpandButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)
    local art = btn:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(btn)
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(btn)
    hover:SetAtlas("common-button-collapseExpand-hover")
    hover:SetBlendMode("ADD")
    function btn:SetExpanded(open)
        art:SetAtlas(open and "common-button-collapseExpand-up" or "common-button-collapseExpand-down")
    end
    btn:SetExpanded(false)
    return btn
end

--------------------------------------------------------------------------
-- Scroll region: ScrollFrame + content child, with a slim gilded thumb
-- (ScrollThumb.tga) in a dark channel along the chamber's right inner edge.
--------------------------------------------------------------------------

local function buildScroll(parent, top)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, top or -14)
    scroll:SetPoint("BOTTOMRIGHT", -24, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    -- The template hides its slider (thumb and channel with it) whenever
    -- the content fits, instead of parking an inert thumb at the top.
    scroll.scrollBarHideable = true

    -- The template's own slider does the scrolling (wheel, drag, range);
    -- it is reskinned rather than replaced: a dark channel, the gilded
    -- chamfered thumb, and its arrow buttons made invisible and inert (the
    -- template re-shows them whenever the range changes, so hiding alone
    -- would not stick).
    local bar = scroll.ScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
        bar:SetWidth(8)
        for _, arrow in ipairs({ bar.ScrollUpButton, bar.ScrollDownButton }) do
            arrow:SetAlpha(0)
            arrow:EnableMouse(false)
            arrow:SetSize(1, 1)
        end
        local channel = bar:CreateTexture(nil, "BACKGROUND")
        channel:SetWidth(3)
        channel:SetPoint("TOP")
        channel:SetPoint("BOTTOM")
        channel:SetColorTexture(0, 0, 0, 0.55)
        local thumb = bar.ThumbTexture or bar:GetThumbTexture()
        thumb:SetTexture(MEDIA_TEX .. "ScrollThumb")
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetSize(8, 32)
        scroll.channel = channel
    end
    return scroll, content
end

--- Gives a scroll region's content its laid-out height, so the scroll range
-- (and the slider) match what's in the list.
local function setScrollContentHeight(scroll, contentHeight)
    local content = scroll:GetScrollChild()
    content:SetHeight(math.max(1, contentHeight or 0))
    if scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end
end

--------------------------------------------------------------------------
-- Native window chrome: Forever's own gilded, chamfered portrait frame via
-- NineSliceUtil.ApplyLayout. The layout is Blizzard's PortraitFrameTemplate
-- (Blizzard_SharedXML/Mainline/NineSliceLayouts.lua) with Camelot's
-- offset overrides (Blizzard_SharedXML/Camelot/NineSliceLayoutOverrides.lua)
-- applied by hand, since an addon frame doesn't inherit the XML template:
--   TopRightCorner: x += -2; BottomLeftCorner: y = -8;
--   BottomRightCorner: x += -2, y = -8.
-- Forever resolves these atlas names to its Camelot art; other clients draw
-- their own portrait-frame metal.
--------------------------------------------------------------------------

local PORTRAIT_FRAME_LAYOUT = {
    TopLeftCorner = { layer = "OVERLAY", atlas = "UI-Frame-PortraitMetal-CornerTopLeft", x = -13, y = 16 },
    TopRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopRight", x = 4 - 2, y = 16 },
    BottomLeftCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft", x = -13, y = -8 },
    BottomRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight", x = 4 - 2, y = -8 },
    TopEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeTop", x = 0, y = 0, x1 = 0, y1 = 0 },
    BottomEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom", x = 0, y = 0, x1 = 0, y1 = 0 },
    LeftEdge = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeLeft", x = 0, y = 0, x1 = 0, y1 = 0 },
    RightEdge = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeRight", x = 0, y = 0, x1 = 0, y1 = 0 },
}

-- Native metrics from PortraitFrameTemplate: the background starts under the
-- 21-unit title band; the portrait is 62 units at (-5, 7); the title text
-- sits in the band between the portrait and the close button.
UI.WINDOW_TITLE_H = 21

--- Applies the native chrome, the crest in the portrait ring, the title in
-- the title band and the native close button. Returns the close button so
-- Main.lua can wire it to the frame it owns.
local function applyWindowChrome(main, title)
    NineSliceUtil.ApplyLayout(main, PORTRAIT_FRAME_LAYOUT)

    -- The crest is drawn already round (CrestPortrait.tga), under the
    -- corner piece's portrait ring, where a native window shows a face.
    local crest = main:CreateTexture(nil, "OVERLAY", nil, -1)
    crest:SetSize(58, 58)
    crest:SetPoint("TOPLEFT", main, "TOPLEFT", -3, 5)
    crest:SetTexture(MEDIA_TEX .. "CrestPortrait")
    main.crest = crest

    local titleText = makeFontString(main, FONT_DISPLAY, 13, C.gold, "CENTER")
    titleText:SetPoint("TOPLEFT", main, "TOPLEFT", 60, -1)
    titleText:SetPoint("TOPRIGHT", main, "TOPRIGHT", -60, -1)
    titleText:SetHeight(UI.WINDOW_TITLE_H - 2)
    titleText:SetText(trackedCaps(title or "SideQuest"))
    shade(titleText)
    main.titleText = titleText

    local closeBtn = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", 1, 0)
    main.closeBtn = closeBtn
    return closeBtn
end

--------------------------------------------------------------------------
-- Tabs: Blizzard's PanelTabButtonTemplate rebuilt from its atlases (an
-- addon button can't inherit the XML mixins without the template's
-- OnLoad side effects). Bottom tabs hang off the window's bottom edge like
-- the Character frame's; `isTop` flips them to hang above a panel, exactly
-- as PanelTopTabButtonMixin does. On Forever the idle tab is Camelot art.
--------------------------------------------------------------------------

local TAB_SIDES_PADDING, TOP_TAB_HEIGHT_PCT = 20, 0.75

local function createPanelTab(parent, text, isTop, isOfficer)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(isTop and 26 or 32)
    tab.isTop = isTop
    local function piece(atlas, layer, point, x)
        local t = tab:CreateTexture(nil, layer or "BACKGROUND")
        t:SetAtlas(atlas, true)
        if isTop then
            t:SetTexCoord(0, 1, 1, 1 - TOP_TAB_HEIGHT_PCT)
            t:SetHeight((t:GetHeight() or 36) * TOP_TAB_HEIGHT_PCT)
            t:SetPoint("BOTTOM" .. point, tab, "BOTTOM" .. point, x, 0)
        else
            t:SetPoint("TOP" .. point, tab, "TOP" .. point, x, 0)
        end
        return t
    end
    local function middle(atlas, left, right, layer)
        local t = tab:CreateTexture(nil, layer or "BACKGROUND")
        t:SetAtlas(atlas, true)
        t:SetHorizTile(true)
        if isTop then
            t:SetTexCoord(0, 1, 1, 1 - TOP_TAB_HEIGHT_PCT)
            t:SetHeight((t:GetHeight() or 36) * TOP_TAB_HEIGHT_PCT)
        end
        t:SetPoint("TOPLEFT", left, "TOPRIGHT")
        t:SetPoint("TOPRIGHT", right, "TOPLEFT")
        return t
    end
    tab.Left = piece("uiframe-tab-left", nil, "LEFT", -3)
    tab.Right = piece("uiframe-tab-right", nil, "RIGHT", 7)
    tab.Middle = middle("_uiframe-tab-center", tab.Left, tab.Right)
    tab.LeftActive = piece("uiframe-activetab-left", nil, "LEFT", -1)
    tab.RightActive = piece("uiframe-activetab-right", nil, "RIGHT", 8)
    tab.MiddleActive = middle("_uiframe-activetab-center", tab.LeftActive, tab.RightActive)
    local lh = piece("uiframe-tab-left", "HIGHLIGHT", "LEFT", -3)
    local rh = piece("uiframe-tab-right", "HIGHLIGHT", "RIGHT", 7)
    local mh = middle("_uiframe-tab-center", lh, rh, "HIGHLIGHT")
    for _, h in ipairs({ lh, rh, mh }) do
        h:SetBlendMode("ADD")
        h:SetAlpha(0.4)
    end

    local label = makeFontString(tab, FONT_DISPLAY, 11, C.gold, "CENTER")
    label:SetText(trackedCaps(text))
    shade(label)
    tab.label = label
    if isOfficer then
        local mark = skinTexture(tab, "Diamond", "OVERLAY")
        mark:SetSize(7, 7)
        mark:SetPoint("RIGHT", label, "LEFT", -5, 0)
        tab.mark = mark
    end
    fitToText(tab, label, function(w)
        tab:SetWidth(w + TAB_SIDES_PADDING + (isOfficer and 22 or 12))
    end)
    return tab
end

--- PanelTemplates_SelectTab / _DeselectTab, including their text offsets.
local function setPanelTabSelected(tab, selected)
    tab.Left:SetShown(not selected)
    tab.Middle:SetShown(not selected)
    tab.Right:SetShown(not selected)
    tab.LeftActive:SetShown(selected)
    tab.MiddleActive:SetShown(selected)
    tab.RightActive:SetShown(selected)
    local y = selected and -3 or 2
    if tab.isTop then
        y = selected and (3 - 7) or (-2 - 6)
    end
    tab.label:ClearAllPoints()
    tab.label:SetPoint("CENTER", tab, "CENTER", tab.mark and 6 or 0, y)
    local col = selected and C.ink or C.gold
    tab.label:SetTextColor(col[1], col[2], col[3], 1)
    tab.selected = selected
end

--------------------------------------------------------------------------
-- Motion: never in combat, never with reduceMotion on. One authored
-- moment (the wax seal); everything else is a quick, consistent
-- ease-out -- never a second, competing entrance style.
--------------------------------------------------------------------------

local function motionAllowed()
    if SideQuest.InCombat and SideQuest.InCombat() then
        return false
    end
    if SideQuestDB and SideQuestDB.settings and SideQuestDB.settings.reduceMotion then
        return false
    end
    return true
end
UI.MotionAllowed = motionAllowed

--- Window open: alpha 0->1 + scale 0.98->1, ~150ms ease-out.
local function playOpenAnim(frame)
    if not motionAllowed() or not frame.CreateAnimationGroup then
        return
    end
    if frame.__openAnim and frame.__openAnim:IsPlaying() then
        return
    end
    local ag = frame:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.15)
    a:SetSmoothing("OUT")
    local s = ag:CreateAnimation("Scale")
    s:SetScaleFrom(0.98, 0.98)
    s:SetScaleTo(1, 1)
    s:SetDuration(0.15)
    s:SetSmoothing("OUT")
    frame.__openAnim = ag
    ag:Play()
end

--- Tab/panel crossfade, ~120ms. One animation group per panel, reused.
local function playCrossfade(panel)
    if not motionAllowed() or not panel.CreateAnimationGroup then
        return
    end
    if not panel.__fade then
        local ag = panel:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.12)
        a:SetSmoothing("OUT")
        panel.__fade = ag
    end
    panel.__fade:Stop()
    panel.__fade:Play()
end

--- Toast slide-in with its ribbon, ~160ms ease-out.
local function playToastIn(toast)
    if not motionAllowed() or not toast.CreateAnimationGroup then
        return
    end
    local ag = toast:CreateAnimationGroup()
    local t = ag:CreateAnimation("Translate")
    t:SetOffset(0, 24)
    t:SetDuration(0.16)
    t:SetSmoothing("OUT")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.16)
    a:SetSmoothing("OUT")
    ag:Play()
end

--- The one authored moment: a wax seal bearing the crest is pressed onto a
-- completed raid-night step. It drops in large and transparent and lands
-- (scale 1.7 -> 0.94 -> 1, alpha 0 -> 1) in ~230ms, ease-out, then rests at
-- a slight tilt like a hand-pressed seal. Returns the seal so the caller
-- keeps it shown; callers pass `playAnim=false` when repainting, so a seal
-- stamps once.
local function stampWaxSeal(parent, point, relFrame, relPoint, x, y, playAnim)
    local seal = skinTexture(parent, "WaxSeal", "OVERLAY", 3)
    seal:SetSize(24, 24)
    seal:SetPoint(point, relFrame, relPoint, x, y)
    seal:SetRotation(math.rad(-8))
    if playAnim and motionAllowed() and seal.CreateAnimationGroup then
        local ag = seal:CreateAnimationGroup()
        local press = ag:CreateAnimation("Scale")
        press:SetScaleFrom(1.7, 1.7)
        press:SetScaleTo(0.94, 0.94)
        press:SetDuration(0.17)
        press:SetSmoothing("IN")
        press:SetOrder(1)
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0)
        fade:SetToAlpha(1)
        fade:SetDuration(0.12)
        fade:SetSmoothing("OUT")
        fade:SetOrder(1)
        -- Scale animations multiply and an earlier order holds its end state,
        -- so the settle grows 0.94 back to exactly 1.
        local settle = ag:CreateAnimation("Scale")
        settle:SetScaleFrom(1, 1)
        settle:SetScaleTo(1 / 0.94, 1 / 0.94)
        settle:SetDuration(0.06)
        settle:SetSmoothing("OUT")
        settle:SetOrder(2)
        ag:Play()
    end
    return seal
end

--------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------

UI.Colors = C
UI.SetColor = setColor
UI.MakeFontString = makeFontString
UI.Shade = shade
UI.Hairline = hairline
UI.TrackedCaps = trackedCaps
UI.MediaTex = MEDIA_TEX
UI.FontDisplay, UI.FontBody, UI.FontBodyItalic = FONT_DISPLAY, FONT_BODY, FONT_BODY_ITALIC

UI.SliceNineSlice = sliceNineSlice
UI.SliceThreeSliceH = sliceThreeSliceH
UI.TintSlices = tintSlices

UI.CreateChamber = createChamber
UI.CreateRibbon = createRibbon
UI.CreateSubHeading = createSubHeading
UI.CreateButton = createButton
UI.SkinEditBox = skinEditBox
UI.CreateCheckbox = createCheckbox
UI.CreateExpandButton = createExpandButton
UI.BuildScroll = buildScroll
UI.SetScrollContentHeight = setScrollContentHeight

UI.ApplyWindowChrome = applyWindowChrome
UI.CreatePanelTab = createPanelTab
UI.SetPanelTabSelected = setPanelTabSelected

UI.PlayOpenAnim = playOpenAnim
UI.PlayCrossfade = playCrossfade
UI.PlayToastIn = playToastIn
UI.StampWaxSeal = stampWaxSeal

return UI
