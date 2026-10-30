-- SideQuest/UI/Main.lua
-- The Guild Sheet: one movable, resizable window that opens on YOU (not a
-- roster grid), with bottom tabs for Guild, Crafters, Raids, Ledger, News
-- and (officers) Console. Visual authority: sidequest-guild/website/DESIGN.md
-- (night blue, chamber framing, ribbon headings, class/quality colours
-- paired with text, no unicode icons, no eyebrow labels, tabular numerals).
-- See .impeccable/surfaces/sidequest-ui-main-lua.md for the direction contract.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
local UI = SideQuest.UI

if not CreateFrame then
    return UI -- headless (no Blizzard UI environment); nothing to build
end

--------------------------------------------------------------------------
-- Media, tokens, helpers
--------------------------------------------------------------------------

local MEDIA_TEX = "Interface\\AddOns\\SideQuest\\Media\\Textures\\"
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
    -- on filled gold/gold-deep surfaces (the raid-night step plate, and
    -- any future gold-filled text) where the usual warm-white ink would
    -- not contrast.
    inkOnGold = { 0x17 / 255, 0x13 / 255, 0x0c / 255, 1 },
}

-- Role swatch colors (tiny marker next to text -- never the only carrier,
-- a role word always follows). DESIGN.md has no dedicated role palette, so
-- these are chosen to stay distinct from class/quality tokens.
local ROLE_COLOR = {
    tank = { 0.42, 0.56, 0.86, 1 },
    healer = { 0.35, 0.82, 0.46, 1 },
    dps = { 0xa8 / 255, 0x84 / 255, 0x49 / 255, 1 },
}
local ROLE_WORD = { tank = "Tank", healer = "Healer", dps = "DPS" }

-- Standard WoW class colors; Shaman/Warlock lifted per DESIGN.md "lifted to read on night".
local CLASS_COLOR = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1, 0.96, 0.41 }, PRIEST = { 1, 1, 1 }, SHAMAN = { 0.3, 0.55, 1 },
    MAGE = { 0.41, 0.8, 0.94 }, WARLOCK = { 0.64, 0.56, 0.85 }, DRUID = { 1, 0.49, 0.04 },
}
local CLASS_WORD = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local QUALITY_COLOR = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

-- Imported class tokens may arrive lowercase from the site (contract v2
-- `members[].class`, `events[].signups[].role`'s sibling `class`); every
-- CLASS_COLOR/CLASS_WORD lookup goes through this so case never hides the
-- colour, in or out of game.
local function classKey(className)
    return className and className:upper() or nil
end

-- News item "kind" -> a game atlas/texture icon + a fallback swatch color
-- (the shipped texture is a Blizzard file path the preview renderer can't
-- fetch; the swatch keeps every kind visually distinct there too). Never
-- the unicode "!"/"?" glyphs DESIGN.md's quest-log uses for events -- those
-- are reserved for open/closed sign-ups, not news kinds.
local NEWS_ICON = {
    boss_kill = { tex = "Interface\\RaidFrame\\ReadyCheck-Ready", color = { 0xd8 / 255, 0xab / 255, 0x5c / 255, 1 } },
    first_kill = { tex = "Interface\\RaidFrame\\ReadyCheck-Ready", color = { 0xd8 / 255, 0xab / 255, 0x5c / 255, 1 } },
    loot = { tex = "Interface\\Icons\\INV_Misc_Bag_08", color = nil }, -- color filled per-item (quality) at render time
    announcement = { tex = "Interface\\COMMON\\VoiceChat-Speaker-On", color = { 1, 0xd3 / 255, 0x6a / 255, 1 } },
    level = { tex = "Interface\\Icons\\Achievement_Level_10", color = { 0x2e / 255, 0x4a / 255, 0x85 / 255, 1 } },
    joined = { tex = "Interface\\Icons\\INV_Misc_GroupLooking", color = { 150 / 255, 172 / 255, 210 / 255, 0.6 } },
    badge = { tex = "Interface\\Icons\\INV_Misc_Trophy_01", color = { 0xa8 / 255, 0x84 / 255, 0x49 / 255, 1 } },
}
local NEWS_KIND_WORD = {
    boss_kill = "Boss kill", first_kill = "First kill", loot = "Loot", announcement = "Announcement",
    level = "Level up", joined = "Joined", badge = "Badge",
}

-- WoW FontStrings have no letter-spacing; tracked caps are built by hand
-- with U+2009 (thin space) between glyphs (verified present in all three
-- shipped fonts' cmaps; U+200A hair space is not -- see Media/PROVENANCE.md).
local THIN_SPACE = "\xE2\x80\x89" -- UTF-8 for U+2009
local function trackedCaps(text)
    local out = {}
    for i = 1, #text do
        out[#out + 1] = text:sub(i, i)
    end
    return table.concat(out, THIN_SPACE):upper()
end
UI.TrackedCaps = trackedCaps

local WINDOW_MIN_W, WINDOW_MIN_H = 700, 480
local WINDOW_DEFAULT_W, WINDOW_DEFAULT_H = 860, 560

local TABS = { "You", "Guild", "Crafters", "Raids", "Ledger", "News" }
local OFFICER_TAB = "Console"
local CONSOLE_SUBTABS = { "Raid Night", "Loot", "Roster", "Recruits", "Bank", "Announce", "Sync" }

local function now()
    return GetServerTime and GetServerTime() or 0
end

--- "Name-Realm" -> "Name" when the realm matches the player's own (DESIGN.md/
-- finding: realm only shown when it differs from yours); falls back to the
-- full string when there's no "-realm" suffix to strip.
local function displayName(character)
    if not character then
        return ""
    end
    local name, realm = character:match("^(.-)%-(.+)$")
    if not name then
        return character
    end
    local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
    if myRealm and realm == myRealm then
        return name
    end
    return character
end
UI.DisplayName = displayName

local INVTYPE_WORD = {
    INVTYPE_HEAD = "Head", INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_LEGS = "Legs",
    INVTYPE_SHOULDER = "Shoulder", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_FEET = "Feet",
    INVTYPE_NECK = "Neck", INVTYPE_WRIST = "Wrist", INVTYPE_CLOAK = "Back", INVTYPE_FINGER = "Ring",
    INVTYPE_HOLDABLE = "Held in off-hand", INVTYPE_SHIELD = "Shield", INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "One-Hand", INVTYPE_WEAPONMAINHAND = "Main Hand", INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_THROWN = "Thrown", INVTYPE_RELIC = "Relic",
}

--- Parse an item id out of either a bare id or an "item:<id>[:...]" link
-- string (Comm/Loot pass the raw contract link, not a full |c|H|h hyperlink).
local function parseItemId(itemLink)
    if not itemLink then
        return nil
    end
    return tonumber(itemLink) or tonumber(tostring(itemLink):match("item:(%d+)"))
end

--- Resolve an item link to its name/quality/icon/slot word/GP cost. Shared
-- by the raider-facing bid popup and the officer console's Loot sub-view,
-- so item resolution (and its "unknown until identified" fallback) lives
-- in exactly one place.
local function resolveItemInfo(itemLink)
    local itemId = parseItemId(itemLink)
    local name, quality, equipLoc, icon
    if itemId and GetItemInfo then
        local n, _, q, _, _, _, _, _, eq, ic = GetItemInfo(itemId)
        name, quality, equipLoc, icon = n, q, eq, ic
    end
    if itemId and not equipLoc and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, eq, ic = C_Item.GetItemInfoInstant(itemId)
        equipLoc, icon = eq, ic or icon
    end
    name = name or tostring(itemLink)
    quality = quality or 1
    local gp = SideQuest.Rules and SideQuest.Rules.ComputeGP and SideQuest.Rules.ComputeGP(equipLoc, "ms")
    return {
        name = name, quality = quality, equipLoc = equipLoc, icon = icon, gp = gp,
        slotWord = equipLoc and (INVTYPE_WORD[equipLoc] or equipLoc) or nil,
    }
end

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

--- A hairline 1px rule using a color texture (DESIGN.md's only border/
-- divider device: rgba(255,255,255,0.09) ink hairline on a dark field).
local function hairline(parent, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    if width then
        line:SetWidth(width)
    end
    setColor(line, { 1, 1, 1, 0.09 })
    return line
end

--- Four gold corner brackets from the shared texture, flipped per corner
-- via tex coords (no rotation API needed for 90-degree reflections).
local function addCornerBrackets(frame, size)
    size = size or 20
    local coords = {
        TOPLEFT = { 0, 0, 1, 0, 0, 1, 1, 1 },
        TOPRIGHT = { 1, 0, 0, 0, 1, 1, 0, 1 },
        BOTTOMLEFT = { 0, 1, 1, 1, 0, 0, 1, 0 },
        BOTTOMRIGHT = { 1, 1, 0, 1, 1, 0, 0, 0 },
    }
    frame.corners = {}
    for point, quad in pairs(coords) do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetSize(size, size)
        tex:SetPoint(point, 2, point:find("TOP") and -2 or 2)
        if tex.SetTexture then
            tex:SetTexture(MEDIA_TEX .. "CornerBracket")
        end
        if tex.SetTexCoord then
            tex:SetTexCoord(unpack(quad))
        end
        frame.corners[point] = tex
    end
end

--- Draw a 1px hairline border on all four edges of `frame` in `color`
-- (DESIGN.md: "Never a solid or saturated border" -- always a hairline).
local function addBorder(frame, color, thickness)
    thickness = thickness or 1
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetHeight(thickness)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT")
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    setColor(top, color)
    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    setColor(bottom, color)
    local left = frame:CreateTexture(nil, "BORDER")
    left:SetWidth(thickness)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    setColor(left, color)
    local right = frame:CreateTexture(nil, "BORDER")
    right:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    setColor(right, color)
    return { top = top, bottom = bottom, left = left, right = right }
end

--- Room button chrome (DESIGN.md "Room buttons"): `kind = "primary"` is a
-- royal fill with a gold-deep 1px edge and ink caps label (a form's
-- submit/commit action); `kind = "quiet"` (default) is a dark well with a
-- stone edge and mist label (secondary/toggle actions). Hover brightens
-- the fill and turns the edge gold; disabled dims both and swaps in a
-- tooltip reason via `btn:SetEnabled(enabled, reasonText)`. Replaces
-- every stock "UIPanelButtonTemplate" button -- that template's red/gray
-- chrome is never themed and clashes with the night-blue rooms.
local function createButton(parent, kind, text, width, height)
    kind = (kind == "primary") and "primary" or "quiet"
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 90, height or 20)
    local well = btn:CreateTexture(nil, "BACKGROUND")
    well:SetAllPoints(btn)
    local border = addBorder(btn, kind == "primary" and C.goldDeep or C.stone, 1)
    local label = makeFontString(btn, FONT_BODY, 11, kind == "primary" and C.ink or C.mist, "CENTER")
    label:SetPoint("CENTER")
    if text then
        label:SetText(text)
    end
    btn.well, btn.border, btn.label, btn.kind = well, border, label, kind
    local function paint(hover, enabled)
        local fillC = kind == "primary" and (hover and C.royal2 or C.royal) or (hover and C.night2 or C.night)
        setColor(well, fillC)
        if well.SetAlpha then well:SetAlpha(enabled and 1 or 0.4) end
        local edgeC = (hover and enabled) and C.gold or (kind == "primary" and C.goldDeep or C.stone)
        for _, seg in pairs(border) do
            setColor(seg, edgeC)
            if seg.SetAlpha then seg:SetAlpha(enabled and 1 or 0.5) end
        end
        local labelC = not enabled and C.inkFaint or (kind == "primary" and C.ink or ((hover) and C.gold or C.mist))
        label:SetTextColor(labelC[1], labelC[2], labelC[3], 1)
    end
    btn.__enabled = true
    paint(false, true)
    btn:SetScript("OnEnter", function()
        paint(true, btn.__enabled)
        if not btn.__enabled and btn.__disabledReason and GameTooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(btn.__disabledReason)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        paint(false, btn.__enabled)
        if GameTooltip then GameTooltip:Hide() end
    end)
    btn.SetText = function(_, t) label:SetText(t) end
    btn.GetText = function() return label:GetText() end
    local nativeSetEnabled = btn.SetEnabled
    btn.SetEnabled = function(self, enabled, reason)
        enabled = not not enabled
        self.__enabled = enabled
        self.__disabledReason = (not enabled) and reason or nil
        if nativeSetEnabled then nativeSetEnabled(self, enabled) end
        paint(false, enabled)
    end
    btn.Disable = function(self) self:SetEnabled(false) end
    btn.Enable = function(self) self:SetEnabled(true) end
    return btn
end

--- Field-well chrome for EditBoxes (DESIGN.md "Forms (rooms)" `.field`):
-- a dark well with a stone edge that warms toward gold on focus, plus
-- placeholder text in mist shown only while the field is empty. Stock
-- InputBoxTemplate chrome renders as bare unboxed text with no well and
-- no placeholder at all.
local function skinEditBox(editBox, placeholderText)
    local well = editBox:CreateTexture(nil, "BACKGROUND")
    well:SetAllPoints(editBox)
    setColor(well, C.night)
    local border = addBorder(editBox, C.stone, 1)
    local placeholder = makeFontString(editBox, FONT_BODY, 12, C.mist2, "LEFT")
    placeholder:SetPoint("LEFT", 4, 0)
    placeholder:SetText(placeholderText or "Search")
    local function refresh()
        placeholder:SetShown(not editBox.GetText or editBox:GetText() == "")
    end
    if editBox.HookScript then
        editBox:HookScript("OnTextChanged", refresh)
        editBox:HookScript("OnEditFocusGained", function()
            for _, seg in pairs(border) do setColor(seg, C.gold) end
        end)
        editBox:HookScript("OnEditFocusLost", function()
            for _, seg in pairs(border) do setColor(seg, C.stone) end
        end)
    end
    refresh()
    editBox.well, editBox.border, editBox.placeholder = well, border, placeholder
    return editBox
end

--- A chamber: night gradient fill, stone outer hairline, gold-deep inner
-- hairline 5px in, bracketed gold corners. The only container used in tab
-- content.
local function createChamber(parent, name)
    local chamber = CreateFrame("Frame", name, parent, "BackdropTemplate")
    local fill = chamber:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(chamber)
    setColor(fill, C.night3)
    addBorder(chamber, C.stone, 1)
    local inner = CreateFrame("Frame", nil, chamber)
    inner:SetPoint("TOPLEFT", 5, -5)
    inner:SetPoint("BOTTOMRIGHT", -5, 5)
    addBorder(inner, C.goldDeep, 1)
    addCornerBrackets(chamber, 20)
    chamber.inner = inner
    return chamber
end

--- Ribbon heading centered on a chamber's top edge: royal fill, gold-deep
-- top/bottom lines, notched end caps, tracked display caps. "Nothing sits
-- above the ribbon" and there is no eyebrow label anywhere in this UI.
local function createRibbon(chamber, text, height)
    height = height or 26
    local ribbon = CreateFrame("Frame", nil, chamber)
    ribbon:SetHeight(height)
    ribbon:SetPoint("TOP", chamber, "TOP", 0, height / 2)
    ribbon:SetPoint("LEFT", chamber, "LEFT", 24, 0)
    ribbon:SetPoint("RIGHT", chamber, "RIGHT", -24, 0)
    local fill = ribbon:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(ribbon)
    setColor(fill, C.royal)
    local topLine = hairline(ribbon)
    topLine:SetPoint("TOPLEFT", ribbon, "TOPLEFT")
    topLine:SetPoint("TOPRIGHT", ribbon, "TOPRIGHT")
    setColor(topLine, C.goldDeep)
    local botLine = hairline(ribbon)
    botLine:SetPoint("BOTTOMLEFT", ribbon, "BOTTOMLEFT")
    botLine:SetPoint("BOTTOMRIGHT", ribbon, "BOTTOMRIGHT")
    setColor(botLine, C.goldDeep)
    local leftCap = ribbon:CreateTexture(nil, "OVERLAY")
    leftCap:SetSize(16, height)
    leftCap:SetPoint("RIGHT", ribbon, "LEFT", 0, 0)
    if leftCap.SetTexture then leftCap:SetTexture(MEDIA_TEX .. "RibbonEndCapLeft") end
    local rightCap = ribbon:CreateTexture(nil, "OVERLAY")
    rightCap:SetSize(16, height)
    rightCap:SetPoint("LEFT", ribbon, "RIGHT", 0, 0)
    if rightCap.SetTexture then rightCap:SetTexture(MEDIA_TEX .. "RibbonEndCapRight") end
    local label = makeFontString(ribbon, FONT_DISPLAY, 14, C.ink, "CENTER")
    label:SetPoint("CENTER", ribbon, "CENTER", 0, 0)
    label:SetText(trackedCaps(text))
    ribbon.label = label
    return ribbon
end

--- A sub-heading: tracked display caps followed by a gold-deep line that
-- fades out to the right (DESIGN.md ".chamber h3"/".sub-title"). Used for
-- every section inside a chamber that is not the ribbon itself -- never an
-- eyebrow label sitting above unrelated content.
local function createSubHeading(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(14)
    local label = makeFontString(row, FONT_DISPLAY, 11, C.gold, "LEFT")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(trackedCaps(text))
    local line = hairline(row)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    setColor(line, C.goldDeep)
    row.label, row.line = label, line
    return row
end

--- One quest-log row: a gold "!" for something open/pending, a dim "?"
-- once it's done, title + a mist meta line. Never color-only: every state
-- also changes the mark glyph and/or adds text.
local function createQuestLogRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(32)
    local mark = makeFontString(row, FONT_DISPLAY, 16, C.gold)
    mark:SetPoint("LEFT", 2, 0)
    local title = makeFontString(row, FONT_BODY, 14, C.ink, "LEFT")
    title:SetPoint("LEFT", mark, "RIGHT", 8, 6)
    local meta = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    row.mark, row.title, row.meta = mark, title, meta
    return row
end

--- A news row with a kind icon (texture + fallback swatch) instead of the
-- quest-log "!"/"?" marks, which are reserved for sign-up state.
local function createNewsRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(32)
    local swatch = row:CreateTexture(nil, "BACKGROUND")
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", 2, 0)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER", swatch, "CENTER", 0, 0)
    local title = makeFontString(row, FONT_BODY, 13, C.ink, "LEFT")
    title:SetPoint("LEFT", swatch, "RIGHT", 8, 6)
    local meta = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    row.swatch, row.icon, row.title, row.meta = swatch, icon, title, meta
    return row
end

--- Fill a news row's icon for `item` (News.Get()/GuildNow shape: kind,
-- quality for loot). Falls back to a generic swatch for unknown kinds.
local function setNewsIcon(row, item)
    local info = NEWS_ICON[item.kind] or NEWS_ICON.announcement
    if row.icon.SetTexture then
        row.icon:SetTexture(info.tex)
    end
    local color = info.color
    if item.kind == "loot" then
        color = QUALITY_COLOR[item.quality or 1] or QUALITY_COLOR[1]
    end
    setColor(row.swatch, color or C.stone2)
end

--- Day header for news/quest-log lists ("grouped by day" per finding #9):
-- reuses the sub-heading treatment so there is no second heading style.
local function dayLabel(ts)
    local d = now() - (ts or now())
    if d < 20 * 3600 and os.date("%j", ts) == os.date("%j", now()) then
        return "Today"
    elseif os.date("%j", ts) == os.date("%j", now() - 86400) then
        return "Yesterday"
    end
    return os.date("%A, %b %d", ts)
end

--- Empty/error copy in the product's voice (PRODUCT.md principle 3: every
-- automatic thing that can't run says so with the manual path).
local function setStateText(fs, text, isError)
    fs:SetText(text)
    if fs.SetTextColor then
        local c = isError and C.errorC or C.mist2
        fs:SetTextColor(c[1], c[2], c[3], 1)
    end
end

--- A scroll region: ScrollFrame + content child, with a themed scrollbar
-- track drawn beside it (the preview renderer clips children to this
-- frame's rect and paints the same track/thumb it draws for real play).
local function buildScroll(parent, top)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, top or -14)
    scroll:SetPoint("BOTTOMRIGHT", -28, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    local track = parent:CreateTexture(nil, "BACKGROUND")
    track:SetWidth(4)
    track:SetPoint("TOP", scroll, "TOP", 0, 0)
    track:SetPoint("BOTTOM", scroll, "BOTTOM", 0, 0)
    track:SetPoint("RIGHT", scroll, "RIGHT", 18, 0)
    setColor(track, C.stone2)
    local thumb = parent:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(4)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    setColor(thumb, C.goldDeep)
    scroll.track, scroll.thumb = track, thumb
    return scroll, content
end

--- Set a scrollbar thumb's height to the visible/content ratio (called
-- after a list is laid out, so the track always reflects how much more
-- there is to see -- the actual clip + scroll-position math is the
-- preview renderer's job, same as the real UIPanelScrollFrameTemplate's).
local function sizeScrollThumb(scroll, contentHeight)
    if not scroll.thumb or not scroll.GetHeight then
        return
    end
    local visible = 1
    local ratio = math.min(1, visible / math.max(1, contentHeight / 1))
    scroll.thumb:SetHeight(math.max(16, 200 * ratio))
end

local function createNameRow(parent, size)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize((size or 13) * 10, (size or 13) + 2)
    local nameFS = makeFontString(row, FONT_BODY, size or 13, C.ink, "LEFT")
    nameFS:SetPoint("LEFT", 0, 0)
    local classFS = makeFontString(row, FONT_BODY, (size or 13) - 1, C.mist, "LEFT")
    classFS:SetPoint("LEFT", nameFS, "RIGHT", 6, 0)
    row.nameFS, row.classFS = nameFS, classFS
    return row
end

--- Fill a name row: the character/display name in class colour, then the
-- class word in mist, as two fontstrings (DESIGN.md: class colour always
-- paired with text, never a lone colour). `errorText`, when given, takes
-- over the whole row in the error voice.
local function setNameRow(row, character, className, errorText)
    if errorText then
        setStateText(row.nameFS, errorText, true)
        row.classFS:SetText("")
        return
    end
    local key = classKey(className)
    local color = (key and CLASS_COLOR[key]) or C.ink
    row.nameFS:SetTextColor(color[1], color[2], color[3], 1)
    row.nameFS:SetText(displayName(character))
    row.classFS:SetText(key and CLASS_WORD[key] or "")
end

local function classText(fs, character, className)
    local key = classKey(className)
    local color = (key and CLASS_COLOR[key]) or C.ink
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:SetText(displayName(character) .. (key and (" " .. CLASS_WORD[key]) or ""))
end

--------------------------------------------------------------------------
-- Exports for sibling UI files (BidPopup.lua): one chamber/ribbon/colour
-- vocabulary, never a second copy of it.
--------------------------------------------------------------------------

UI.Colors = C
UI.RoleColor, UI.RoleWord = ROLE_COLOR, ROLE_WORD
UI.ClassColor, UI.ClassWord, UI.QualityColor = CLASS_COLOR, CLASS_WORD, QUALITY_COLOR
UI.ClassKey = classKey
UI.SetColor = setColor
UI.MakeFontString = makeFontString
UI.Shade = shade
UI.Hairline = hairline
UI.AddBorder = addBorder
UI.CreateButton = createButton
UI.SkinEditBox = skinEditBox
UI.CreateChamber = createChamber
UI.CreateRibbon = createRibbon
UI.CreateSubHeading = createSubHeading
UI.CreateQuestLogRow = createQuestLogRow
UI.SetStateText = setStateText
UI.BuildScroll = buildScroll
UI.ClassText = classText
UI.CreateNameRow = createNameRow
UI.SetNameRow = setNameRow
UI.MediaTex = MEDIA_TEX
UI.FontDisplay, UI.FontBody, UI.FontBodyItalic = FONT_DISPLAY, FONT_BODY, FONT_BODY_ITALIC
UI.TrackedCaps = trackedCaps
UI.ParseItemId = parseItemId
UI.ResolveItemInfo = resolveItemInfo

--------------------------------------------------------------------------
-- Main frame: shell, position/size/scale persistence, combat deferral
--------------------------------------------------------------------------

local function saveGeometry()
    local main = UI.main
    if not main then
        return
    end
    local point, _, _, x, y = main:GetPoint()
    SideQuestDB.ui.pos = { point = point or "CENTER", x = x or 0, y = y or 0 }
    SideQuestDB.ui.width = main:GetWidth()
    SideQuestDB.ui.height = main:GetHeight()
end

function UI.BuildMainFrame()
    if UI.main then
        return UI.main
    end

    local main = CreateFrame("Frame", "SideQuestMainFrame", UIParent, "BackdropTemplate")
    main:SetSize(SideQuestDB.ui.width or WINDOW_DEFAULT_W, SideQuestDB.ui.height or WINDOW_DEFAULT_H)
    local pos = SideQuestDB.ui.pos
    if pos then
        main:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        main:SetPoint("CENTER")
    end
    if SideQuestDB.ui.scale and main.SetScale then
        main:SetScale(SideQuestDB.ui.scale)
    end
    local fill = main:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(main)
    setColor(fill, C.night)
    local edge = main:CreateTexture(nil, "BORDER")
    edge:SetAllPoints(main)
    setColor(edge, C.stone)

    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveGeometry()
    end)
    main:SetResizable(true)
    if main.SetResizeBounds then
        main:SetResizeBounds(WINDOW_MIN_W, WINDOW_MIN_H)
    elseif main.SetMinResize then
        main:SetMinResize(WINDOW_MIN_W, WINDOW_MIN_H)
    end
    main:Hide()

    -- Escape closes the window (classic WoW special-frame pattern).
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, "SideQuestMainFrame")

    local resizeGrip = CreateFrame("Button", nil, main)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetScript("OnMouseDown", function()
        main:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        main:StopMovingOrSizing()
        saveGeometry()
    end)

    --------------------------------------------------------------
    -- Header strip: crest, tracked wordmark (shaded for legibility over
    -- the painted art), freshness line (on its own local scrim)
    --------------------------------------------------------------
    local header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(110)
    local strip = header:CreateTexture(nil, "BACKGROUND")
    strip:SetAllPoints(header)
    if strip.SetTexture then
        strip:SetTexture(MEDIA_TEX .. "HeaderStrip")
    end
    local crest = header:CreateTexture(nil, "ARTWORK")
    crest:SetSize(48, 48)
    crest:SetPoint("LEFT", 14, 0)
    if crest.SetTexture then
        crest:SetTexture(MEDIA_TEX .. "Crest")
    end
    local wordmark = makeFontString(header, FONT_DISPLAY, 22, C.ink, "LEFT")
    wordmark:SetPoint("LEFT", crest, "RIGHT", 14, 6)
    wordmark:SetText(trackedCaps("SideQuest"))
    shade(wordmark)

    -- freshness: a local scrim (dark veil) behind the line, not just a
    -- shadow, so it stays legible over the busiest part of the painting.
    local freshScrim = header:CreateTexture(nil, "ARTWORK")
    freshScrim:SetSize(190, 22)
    freshScrim:SetPoint("RIGHT", -6, 0)
    setColor(freshScrim, C.menuVeil)
    local freshness = makeFontString(header, FONT_BODY, 12, C.mist, "RIGHT")
    freshness:SetPoint("RIGHT", -16, 0)
    main.freshness = freshness

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        main:Hide()
    end)

    --------------------------------------------------------------
    -- Body (tab content lives here) + bottom tab bar, inset to match the
    -- chamber below it so the tab row never overlaps the chamber corners
    --------------------------------------------------------------
    local TAB_HEIGHT, TAB_BAR_HEIGHT = 32, 40
    local tabBar = CreateFrame("Frame", nil, main)
    tabBar:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 12, 4)
    tabBar:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -12, 4)
    tabBar:SetHeight(TAB_BAR_HEIGHT)
    main.tabBar = tabBar

    local body = CreateFrame("Frame", nil, main)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    body:SetPoint("BOTTOMLEFT", tabBar, "TOPLEFT")
    body:SetPoint("BOTTOMRIGHT", tabBar, "TOPRIGHT")
    main.body = body

    UI.main = main
    UI.panels = {}
    UI.tabButtons = {}

    local allTabs = {}
    for _, t in ipairs(TABS) do
        table.insert(allTabs, t)
    end
    table.insert(allTabs, OFFICER_TAB)

    -- WINDOW_DEFAULT_W matches the actual default window width (and the
    -- preview's render width), so the tab row fills the bar exactly and
    -- lines up under the chamber's inset edges instead of a narrower,
    -- stale WINDOW_MIN_W grid.
    local tabWidth = math.max(60, math.floor(WINDOW_DEFAULT_W - 24) / #allTabs)
    for i, tabName in ipairs(allTabs) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetSize(tabWidth, TAB_HEIGHT)
        btn:SetPoint("LEFT", (i - 1) * tabWidth, 0)
        local well = btn:CreateTexture(nil, "BACKGROUND")
        well:SetAllPoints(btn)
        setColor(well, C.night2)
        local border = addBorder(btn, C.stone, 1)
        local label = makeFontString(btn, FONT_BODY, 12, C.mist, "CENTER")
        label:SetPoint("CENTER")
        label:SetText(trackedCaps(tabName))
        btn.well, btn.label, btn.border = well, label, border
        btn:SetScript("OnClick", function()
            UI.ShowTab(tabName)
        end)
        btn:SetScript("OnEnter", function()
            if UI.activeTab ~= tabName then
                setColor(well, C.royal2)
            end
        end)
        btn:SetScript("OnLeave", function()
            setColor(well, UI.activeTab == tabName and C.royal or C.night2)
        end)
        if tabName == OFFICER_TAB then
            btn:Hide() -- shown only for officers, see UI.RefreshOfficerVisibility
        end
        UI.tabButtons[tabName] = btn
    end

    UI.BuildYouPanel(body)
    UI.BuildGuildPanel(body)
    UI.BuildCraftersPanel(body)
    UI.BuildRaidsPanel(body)
    UI.BuildLedgerPanel(body)
    UI.BuildNewsPanel(body)
    UI.BuildConsolePanel(body)

    UI.RefreshOfficerVisibility()
    UI.RefreshFreshness()

    return main
end

function UI.RefreshOfficerVisibility()
    local btn = UI.tabButtons and UI.tabButtons[OFFICER_TAB]
    if not btn then
        return
    end
    if SideQuest.IsOfficer() then
        btn:Show()
    else
        btn:Hide()
        if UI.activeTab == OFFICER_TAB then
            UI.ShowTab("You")
        end
    end
end

function UI.RefreshFreshness()
    local main = UI.main
    if not main or not main.freshness then
        return
    end
    local at = SideQuestDB.guild and SideQuestDB.guild.generated_at or 0
    if at <= 0 then
        setStateText(main.freshness, "Never synced -- ask an officer", true)
        return
    end
    local ageSeconds = math.max(0, now() - at)
    local hours = math.floor(ageSeconds / 3600)
    local text
    if hours < 1 then
        text = "Synced just now"
    elseif hours < 48 then
        text = "Synced " .. hours .. "h ago"
    else
        text = "Synced " .. math.floor(hours / 24) .. "d ago"
    end
    setStateText(main.freshness, text, false)
end

--- Tab chrome: dark well + stone edge; the current tab takes a royal fill
-- with a gold-deep edge; the officer tab keeps a gold-deep edge even when
-- not current (DESIGN.md: "Console = gold-edged").
function UI.ShowTab(tabName)
    for name, panel in pairs(UI.panels) do
        if name == tabName then
            panel:Show()
        else
            panel:Hide()
        end
    end
    for name, btn in pairs(UI.tabButtons) do
        local isActive = name == tabName
        setColor(btn.well, isActive and C.royal or C.night2)
        if btn.label and btn.label.SetTextColor then
            local c = isActive and C.gold or C.mist
            btn.label:SetTextColor(c[1], c[2], c[3], 1)
        end
        local edgeColor = (isActive or name == OFFICER_TAB) and C.goldDeep or C.stone
        for _, line in pairs(btn.border or {}) do
            setColor(line, edgeColor)
        end
    end
    UI.activeTab = tabName
    SideQuestDB.ui.tab = tabName
    if tabName == "You" then
        UI.RefreshYou()
    elseif tabName == "Guild" then
        UI.RefreshGuild()
    elseif tabName == "Crafters" then
        UI.RefreshCrafters()
    elseif tabName == "Raids" then
        UI.RefreshRaids()
    elseif tabName == "Ledger" then
        UI.RefreshLedger()
    elseif tabName == "News" then
        UI.RefreshNews()
    elseif tabName == OFFICER_TAB then
        UI.RefreshConsole()
    end
end

--- Open the window. Never opens, flashes or animates in combat (queued
-- until PLAYER_REGEN_ENABLED).
function UI.Show()
    SideQuest.WhenOutOfCombat(function()
        local main = UI.BuildMainFrame()
        main:Show()
        UI.ShowTab(UI.activeTab or SideQuestDB.ui.tab or "You")
    end)
end

function UI.Toggle()
    if UI.main and UI.main:IsShown() then
        UI.main:Hide()
        return
    end
    UI.Show()
end

--------------------------------------------------------------------------
-- YOU tab (first viewport): YOU chamber + GUILD NOW chamber side by side.
-- Everything below the ribbon lives in a scroll child so content never
-- clips the chamber and there's never a dead gap above the badges.
--------------------------------------------------------------------------

function UI.BuildYouPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    UI.panels.You = panel

    local you = createChamber(panel, "SideQuestYouChamber")
    you:SetPoint("TOPLEFT", 12, -12)
    you:SetPoint("BOTTOMLEFT", 12, 12)
    you:SetWidth(380)
    createRibbon(you, "You")

    local scroll, content = buildScroll(you.inner, -30)
    you.scroll, you.content = scroll, content

    local nameRow = createNameRow(content, 16)
    nameRow:SetPoint("TOPLEFT", 0, 0)
    local rankText = makeFontString(content, FONT_BODY, 12, C.mist, "LEFT")
    rankText:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -4)
    local prText = makeFontString(content, FONT_BODY, 13, C.ink, "LEFT")
    prText:SetPoint("TOPLEFT", rankText, "BOTTOMLEFT", 0, -10)

    -- EP/GP history: a compact labelled table (four weeks, dated, EP and GP
    -- as separate tabular-numeral columns) rather than bars, which can't
    -- carry a legend/baseline clearly at 0.64 scale.
    local historyHeading = createSubHeading(content, "EP / GP, last 4 weeks")
    historyHeading:SetPoint("TOPLEFT", prText, "BOTTOMLEFT", 0, -14)
    historyHeading:SetWidth(320)
    local historyTable = CreateFrame("Frame", nil, content)
    historyTable:SetPoint("TOPLEFT", historyHeading, "BOTTOMLEFT", 0, -6)
    historyTable:SetSize(320, 16 * 5)
    local histHeader = { week = makeFontString(historyTable, FONT_BODY, 10, C.mist2, "LEFT"),
        ep = makeFontString(historyTable, FONT_BODY, 10, C.mist2, "RIGHT"),
        gp = makeFontString(historyTable, FONT_BODY, 10, C.mist2, "RIGHT") }
    histHeader.week:SetPoint("TOPLEFT", 0, 0)
    histHeader.week:SetText(trackedCaps("Week"))
    histHeader.ep:SetPoint("TOPLEFT", 190, 0)
    histHeader.ep:SetWidth(55)
    histHeader.ep:SetText(trackedCaps("EP"))
    histHeader.gp:SetPoint("TOPLEFT", 255, 0)
    histHeader.gp:SetWidth(55)
    histHeader.gp:SetText(trackedCaps("GP"))
    historyTable.rows = {}
    for i = 1, 4 do
        local weekFS = makeFontString(historyTable, FONT_BODY, 12, C.ink, "LEFT")
        weekFS:SetPoint("TOPLEFT", 0, -16 * i)
        local epFS = makeFontString(historyTable, FONT_BODY, 12, C.gold, "RIGHT")
        epFS:SetPoint("TOPLEFT", 190, -16 * i)
        epFS:SetWidth(55)
        local gpFS = makeFontString(historyTable, FONT_BODY, 12, C.mist, "RIGHT")
        gpFS:SetPoint("TOPLEFT", 255, -16 * i)
        gpFS:SetWidth(55)
        historyTable.rows[i] = { week = weekFS, ep = epFS, gp = gpFS }
    end
    local baselineText = makeFontString(content, FONT_BODY_ITALIC, 10, C.inkFaint, "LEFT")
    baselineText:SetPoint("TOPLEFT", historyTable, "BOTTOMLEFT", 0, -2)
    baselineText:SetText("GP floor 100 -- it never decays below this baseline.")
    local historyEmpty = makeFontString(content, FONT_BODY, 11, C.mist2, "LEFT")
    historyEmpty:SetPoint("TOPLEFT", historyHeading, "BOTTOMLEFT", 0, -6)
    historyEmpty:Hide()

    local nextEventHeading = createSubHeading(content, "Next event")
    nextEventHeading:SetPoint("TOPLEFT", baselineText, "BOTTOMLEFT", 0, -14)
    nextEventHeading:SetWidth(320)
    local nextEventTitle = makeFontString(content, FONT_BODY, 13, C.ink, "LEFT")
    nextEventTitle:SetPoint("TOPLEFT", nextEventHeading, "BOTTOMLEFT", 0, -6)
    local nextEventMeta = makeFontString(content, FONT_BODY, 11, C.mist2, "LEFT")
    nextEventMeta:SetPoint("TOPLEFT", nextEventTitle, "BOTTOMLEFT", 0, -2)

    local answerButtons = {}
    for i, answer in ipairs({ { "going", "Going" }, { "maybe", "Maybe" }, { "cant", "Can't" } }) do
        local btn = createButton(content, "quiet", answer[2], 70, 22)
        btn:SetPoint("TOPLEFT", nextEventMeta, "BOTTOMLEFT", (i - 1) * 74, -8)
        local selectedEdge = addBorder(btn, C.gold, 2)
        for _, line in pairs(selectedEdge) do
            line:Hide()
        end
        btn.selectedEdge = selectedEdge
        answerButtons[answer[1]] = btn
    end
    local signupState = makeFontString(content, FONT_BODY, 11, C.mist2, "LEFT")
    signupState:SetPoint("TOPLEFT", answerButtons.going, "BOTTOMLEFT", 0, -8)

    local badgesHeading = createSubHeading(content, "Badges")
    badgesHeading:SetPoint("TOPLEFT", signupState, "BOTTOMLEFT", 0, -16)
    badgesHeading:SetWidth(320)
    local badgesText = makeFontString(content, FONT_BODY, 12, C.flavor, "LEFT")
    badgesText:SetPoint("TOPLEFT", badgesHeading, "BOTTOMLEFT", 0, -6)
    badgesText:SetWidth(320)
    if badgesText.SetWordWrap then
        badgesText:SetWordWrap(true)
    end
    local epgpAltsText = makeFontString(content, FONT_BODY, 12, C.mist, "LEFT")
    epgpAltsText:SetPoint("TOPLEFT", badgesText, "BOTTOMLEFT", 0, -6)

    you.nameRow, you.rankText, you.prText = nameRow, rankText, prText
    you.historyHeading, you.historyTable, you.baselineText, you.historyEmpty =
        historyHeading, historyTable, baselineText, historyEmpty
    you.nextEventHeading, you.nextEventTitle, you.nextEventMeta, you.answerButtons, you.signupState =
        nextEventHeading, nextEventTitle, nextEventMeta, answerButtons, signupState
    you.badgesHeading, you.badgesText, you.epgpAltsText = badgesHeading, badgesText, epgpAltsText
    panel.you = you

    --------------------------------------------------------------
    -- GUILD NOW: online count, a short who's-on list, then the news feed
    --------------------------------------------------------------
    local guildNow = createChamber(panel, "SideQuestGuildNowChamber")
    guildNow:SetPoint("TOPRIGHT", -12, -12)
    guildNow:SetPoint("BOTTOMRIGHT", -12, 12)
    guildNow:SetPoint("LEFT", you, "RIGHT", 12, 0)
    createRibbon(guildNow, "Guild Now")

    local onlineText = makeFontString(guildNow.inner, FONT_BODY, 13, C.gold, "LEFT")
    onlineText:SetPoint("TOPLEFT", 14, -30)
    guildNow.onlineText = onlineText

    local ONLINE_LIST_ROWS = 5
    local onlineList = CreateFrame("Frame", nil, guildNow.inner)
    onlineList:SetPoint("TOPLEFT", onlineText, "BOTTOMLEFT", 0, -6)
    onlineList:SetSize(260, 14 * ONLINE_LIST_ROWS)
    onlineList.rows = {}
    for i = 1, ONLINE_LIST_ROWS do
        local row = createNameRow(onlineList, 11)
        row:SetPoint("TOPLEFT", 0, -14 * (i - 1))
        local zoneFS = makeFontString(onlineList, FONT_BODY, 10, C.mist2, "RIGHT")
        zoneFS:SetPoint("TOPRIGHT", 0, -14 * (i - 1))
        row.zoneFS = zoneFS
        onlineList.rows[i] = row
    end
    local seeAllBtn = createButton(guildNow.inner, "quiet", "See all", 90, 18)
    seeAllBtn:SetPoint("TOPLEFT", onlineList, "BOTTOMLEFT", 0, -2)
    seeAllBtn:SetScript("OnClick", function()
        UI.ShowTab("Guild")
    end)
    guildNow.onlineList, guildNow.seeAllBtn = onlineList, seeAllBtn

    local newsHeading = createSubHeading(guildNow.inner, "News")
    newsHeading:SetPoint("TOPLEFT", seeAllBtn, "BOTTOMLEFT", 0, -10)
    newsHeading:SetWidth(260)
    guildNow.newsHeading = newsHeading

    local newsScroll, newsContent = buildScroll(guildNow.inner, nil)
    newsScroll:ClearAllPoints()
    newsScroll:SetPoint("TOPLEFT", newsHeading, "BOTTOMLEFT", 0, -6)
    newsScroll:SetPoint("BOTTOMRIGHT", -28, 14)
    guildNow.newsScroll, guildNow.newsContent = newsScroll, newsContent
    guildNow.newsRows = {}
    panel.guildNow = guildNow
end

function UI.RefreshYou()
    local panel = UI.panels and UI.panels.You
    if not panel then
        return
    end
    local you, guildNow = panel.you, panel.guildNow
    local me = SideQuest.NormalizeUnit("player")
    local member, myChar

    for _, m in ipairs((SideQuestDB.guild and SideQuestDB.guild.members) or {}) do
        for _, c in ipairs(m.characters or {}) do
            if c.name == me then
                member, myChar = m, c
            end
        end
    end

    if member then
        setNameRow(you.nameRow, member.main or me, myChar and myChar.class)
        local altCount = member.characters and math.max(0, #member.characters - 1) or 0
        you.rankText:SetText((member.rank or "Member") .. (altCount > 0 and ("  --  " .. altCount .. " alt(s)") or ""))
    else
        setNameRow(you.nameRow, nil, nil, "Not linked yet")
        setStateText(you.rankText, "Claim your character on the site, then sync.", true)
    end

    local rows = SideQuest.Standings.GetDisplayRows()
    local myRow, rank, total = nil, nil, #rows
    for i, row in ipairs(rows) do
        for _, char in ipairs(row.characters or {}) do
            if char == me then
                myRow, rank = row, i
            end
        end
    end
    if myRow then
        you.prText:SetText(string.format("PR %.3f  --  rank %d of %d", myRow.pr or 0, rank, total))
    else
        setStateText(you.prText, "No standings yet -- an officer imports them after the first raid.", true)
    end

    -- four-week EP/GP table, drawn from the sheet (if we've asked and gotten an answer)
    local sheet = SideQuest.Sheet.lastAnswer
    if sheet and sheet.found and sheet.ledger and #sheet.ledger > 0 then
        you.historyTable:Show()
        you.baselineText:Show()
        you.historyEmpty:Hide()
        local cutoff = now() - 28 * 24 * 60 * 60
        local epTotals, gpTotals = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
        for _, entry in ipairs(sheet.ledger) do
            if entry.at and entry.at >= cutoff then
                local weekIdx = math.min(4, math.floor((now() - entry.at) / (7 * 24 * 60 * 60)) + 1)
                local slot = 5 - weekIdx
                if entry.kind == "ep" then
                    epTotals[slot] = epTotals[slot] + (entry.amount or 0)
                elseif entry.kind == "gp" then
                    gpTotals[slot] = gpTotals[slot] + (entry.amount or 0)
                end
            end
        end
        for i = 1, 4 do
            local weekStart = now() - (4 - i + 1) * 7 * 24 * 60 * 60
            local row = you.historyTable.rows[i]
            row.week:SetText(os.date("%b %d", weekStart))
            row.ep:SetText(string.format("%.0f", epTotals[i]))
            row.gp:SetText(string.format("%.0f", gpTotals[i]))
        end
    else
        you.historyTable:Hide()
        you.baselineText:Hide()
        you.historyEmpty:Show()
        setStateText(you.historyEmpty, "No sheet yet -- opening Ledger asks an officer for yours.", true)
    end

    -- next event + sign-up state, with the current answer highlighted
    local events = SideQuest.Events.Get()
    local nextEvt = events[1]
    if nextEvt then
        you.nextEventTitle:SetText(nextEvt.title or "Raid")
        local secs = (nextEvt.starts_at or 0) - now()
        you.nextEventMeta:SetText((secs > 0 and ("in " .. math.floor(secs / 3600) .. "h  --  ") or "in progress  --  ")
            .. os.date("%a %H:%M", nextEvt.starts_at or now()))
        local state, status = SideQuest.Signups.MyState(nextEvt.id)
        local statusToAnswer = { signed = "going", tentative = "maybe", absent = "cant" }
        local currentAnswer = statusToAnswer[status]
        for answer, btn in pairs(you.answerButtons) do
            btn:SetScript("OnClick", function()
                SideQuest.Signups.Answer(nextEvt.id, answer)
                UI.RefreshYou()
            end)
            local selected = answer == currentAnswer
            for _, line in pairs(btn.selectedEdge) do
                line:SetShown(selected)
            end
            setColor(btn.well or btn, selected and C.royal or C.night2)
        end
        if state == "sent" then
            setStateText(you.signupState, "Sent -- waiting for an officer", false)
        elseif state == "saved" then
            setStateText(you.signupState, "Saved (" .. status .. ") -- reaches the site at the next sync", false)
        else
            setStateText(you.signupState, "Not signed yet", false)
        end
    else
        setStateText(you.nextEventTitle, "No raids scheduled yet", true)
        you.nextEventMeta:SetText("")
        setStateText(you.signupState, "", false)
        for _, btn in pairs(you.answerButtons) do
            for _, line in pairs(btn.selectedEdge) do
                line:Hide()
            end
        end
    end

    local badges = (member and member.badges) or {}
    if #badges > 0 then
        local names = {}
        for _, b in ipairs(badges) do
            table.insert(names, b.name)
        end
        you.badgesText:SetText(table.concat(names, ", "))
    else
        setStateText(you.badgesText, "None yet", true)
    end
    local altNames = {}
    for _, c in ipairs((member and member.characters) or {}) do
        if c.name ~= (member.main or me) then
            table.insert(altNames, displayName(c.name))
        end
    end
    you.epgpAltsText:SetText(string.format("Guild EP %.0f  --  attendance %.0f%%  --  alts: %s",
        (member and member.guild_ep) or 0, (member and (member.attendance_rate or 0) * 100) or 0,
        #altNames > 0 and table.concat(altNames, ", ") or "none"))

    -- GUILD NOW
    local rosterMembers = (SideQuestDB.roster and SideQuestDB.roster.members) or {}
    local online = 0
    local onlineRows = {}
    for _, m in ipairs(rosterMembers) do
        if m.online then
            online = online + 1
            table.insert(onlineRows, m)
        end
    end
    table.sort(onlineRows, function(a, b) return (a.character or "") < (b.character or "") end)
    guildNow.onlineText:SetText(online .. " online")
    for i, row in ipairs(guildNow.onlineList.rows) do
        local m = onlineRows[i]
        if m then
            setNameRow(row, m.character, m.class)
            row.zoneFS:SetText(m.zone or "")
            row:Show()
            row.zoneFS:Show()
        else
            row:Hide()
            row.zoneFS:Hide()
        end
    end

    local newsItems = SideQuest.News.Get()
    for _, row in ipairs(guildNow.newsRows) do
        row:Hide()
    end
    if #newsItems == 0 then
        if not guildNow.emptyText then
            guildNow.emptyText = makeFontString(guildNow.newsContent, FONT_BODY, 12, C.mist2, "LEFT")
            guildNow.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(guildNow.emptyText, "No news yet -- boss kills, loot and announcements show up here.", true)
    elseif guildNow.emptyText then
        guildNow.emptyText:SetText("")
    end
    local shown = math.min(#newsItems, 5)
    for i = 1, shown do
        local item = newsItems[i]
        local row = guildNow.newsRows[i]
        if not row then
            row = createNewsRow(guildNow.newsContent)
            guildNow.newsRows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -32 * (i - 1))
        setNewsIcon(row, item)
        row.title:SetText(item.text or NEWS_KIND_WORD[item.kind] or item.kind)
        row.meta:SetText((item.character and (displayName(item.character) .. "  ") or "") .. os.date("%m/%d %H:%M", item.at or now()))
        row:Show()
    end

    UI.RefreshFreshness()
end

--------------------------------------------------------------------------
-- GUILD tab: roster+, header row, search + online/class/rank filters,
-- alts grouped under their main (expand/collapse), online first
--------------------------------------------------------------------------

function UI.BuildGuildPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.Guild = panel

    local chamber = createChamber(panel, "SideQuestGuildChamber")
    chamber:SetPoint("TOPLEFT", 12, -12)
    chamber:SetPoint("BOTTOMRIGHT", -12, 12)
    createRibbon(chamber, "Guild")

    local searchBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("TOPLEFT", 14, -30)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function()
        UI.RefreshGuild()
    end)
    skinEditBox(searchBox, "Search members")
    chamber.searchBox = searchBox

    local onlineOnly = CreateFrame("CheckButton", nil, chamber.inner, "UICheckButtonTemplate")
    onlineOnly:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    local onlineOnlyLabel = makeFontString(chamber.inner, FONT_BODY, 11, C.mist, "LEFT")
    onlineOnlyLabel:SetPoint("LEFT", onlineOnly, "RIGHT", 2, 0)
    onlineOnlyLabel:SetText("Online only")
    onlineOnly:SetScript("OnClick", function() UI.RefreshGuild() end)
    chamber.onlineOnly = onlineOnly

    local classFilterBtn = createButton(chamber.inner, "quiet", "Class: All", 100, 20)
    classFilterBtn:SetPoint("LEFT", onlineOnlyLabel, "RIGHT", 14, 0)
    chamber.classFilter = nil
    classFilterBtn:SetScript("OnClick", function()
        local order = { nil, "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
        local idx = 1
        for i, v in ipairs(order) do
            if v == chamber.classFilter then idx = i end
        end
        chamber.classFilter = order[(idx % #order) + 1]
        classFilterBtn:SetText("Class: " .. (chamber.classFilter and CLASS_WORD[chamber.classFilter] or "All"))
        UI.RefreshGuild()
    end)
    chamber.classFilterBtn = classFilterBtn

    local rankFilterBtn = createButton(chamber.inner, "quiet", "Rank: All", 110, 20)
    rankFilterBtn:SetPoint("LEFT", classFilterBtn, "RIGHT", 6, 0)
    chamber.rankFilter = nil
    rankFilterBtn:SetScript("OnClick", function()
        local ranks, seen = { nil }, {}
        for _, r in ipairs(SideQuest.Roster.MergedRows()) do
            if r.rank and not seen[r.rank] then
                seen[r.rank] = true
                table.insert(ranks, r.rank)
            end
        end
        local idx = 1
        for i, v in ipairs(ranks) do
            if v == chamber.rankFilter then idx = i end
        end
        chamber.rankFilter = ranks[(idx % #ranks) + 1]
        rankFilterBtn:SetText("Rank: " .. (chamber.rankFilter or "All"))
        UI.RefreshGuild()
    end)
    chamber.rankFilterBtn = rankFilterBtn

    -- header row: Name | Level | Rank | Zone | Last seen
    local header = CreateFrame("Frame", nil, chamber.inner)
    header:SetPoint("TOPLEFT", 14, -58)
    header:SetPoint("RIGHT", -28, 0)
    header:SetHeight(16)
    local COLS = { name = 0, level = 230, rank = 300, zone = 420, lastSeen = 540 }
    chamber.cols = COLS
    local function headerLabel(text, x, w, justify)
        local fs = makeFontString(header, FONT_BODY, 10, C.mist2, justify or "LEFT")
        fs:SetPoint("TOPLEFT", x, 0)
        if w then fs:SetWidth(w) end
        fs:SetText(trackedCaps(text))
        return fs
    end
    headerLabel("Name", COLS.name)
    headerLabel("Level", COLS.level, 40, "RIGHT")
    headerLabel("Rank", COLS.rank)
    headerLabel("Zone", COLS.zone)
    headerLabel("Last seen", COLS.lastSeen)
    local headerLine = hairline(chamber.inner)
    headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    headerLine:SetPoint("RIGHT", -28, 0)

    local scroll, content = buildScroll(chamber.inner, -80)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    chamber.expanded = {}
    panel.chamber = chamber
end


local function buildGuildRow(content)
    local ui = CreateFrame("Button", nil, content)
    ui:SetSize(560, 22)
    ui.indent = CreateFrame("Frame", nil, ui)
    ui.indent:SetPoint("LEFT", 0, 0)
    ui.expandBtn = createButton(ui, "quiet", nil, 18, 18)
    ui.expandBtn:SetPoint("LEFT", ui.indent, "LEFT", 0, 0)
    ui.statusIcon = ui:CreateTexture(nil, "ARTWORK")
    ui.statusIcon:SetSize(8, 8)
    ui.statusIcon:SetPoint("LEFT", ui.expandBtn, "RIGHT", 4, 0)
    ui.nameRow = createNameRow(ui, 13)
    ui.nameRow:SetPoint("LEFT", ui.statusIcon, "RIGHT", 6, 0)
    ui.statusWord = makeFontString(ui, FONT_BODY, 10, C.mist2, "LEFT")
    ui.levelText = makeFontString(ui, FONT_BODY, 12, C.ink, "RIGHT")
    ui.levelText:SetWidth(40)
    ui.rankText = makeFontString(ui, FONT_BODY, 12, C.mist, "LEFT")
    ui.zoneText = makeFontString(ui, FONT_BODY, 12, C.mist, "LEFT")
    ui.lastSeenText = makeFontString(ui, FONT_BODY, 11, C.mist2, "LEFT")
    ui.whisperBtn = createButton(ui, "quiet", "Whisper", 66, 18)
    ui.whisperBtn:SetPoint("RIGHT", -76, 0)
    ui.inviteBtn = createButton(ui, "quiet", "Invite", 66, 18)
    ui.inviteBtn:SetPoint("RIGHT", 0, 0)
    ui.whisperBtn:Hide()
    ui.inviteBtn:Hide()
    ui:SetScript("OnEnter", function()
        ui.whisperBtn:Show()
        ui.inviteBtn:Show()
    end)
    ui:SetScript("OnLeave", function()
        if not ui.selected then
            ui.whisperBtn:Hide()
            ui.inviteBtn:Hide()
        end
    end)
    return ui
end

function UI.RefreshGuild()
    local panel = UI.panels and UI.panels.Guild
    if not panel then
        return
    end
    local chamber = panel.chamber
    if not SideQuest.Roster.IsAvailable() and not (SideQuestDB.guild and #SideQuestDB.guild.members > 0) then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "Roster API unavailable here; sync from the site for a snapshot.", true)
        for _, r in ipairs(chamber.rows) do r:Hide() end
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    local query = (chamber.searchBox:GetText() or ""):lower()
    local rows = SideQuest.Roster.MergedRows()

    -- group by member (main + alts), keeping the main row's identity for sort/filter
    local groups, order = {}, {}
    for _, r in ipairs(rows) do
        local key = r.member_id or ("char:" .. r.character)
        if not groups[key] then
            groups[key] = { main = nil, alts = {}, online = false }
            table.insert(order, key)
        end
        local g = groups[key]
        g.online = g.online or r.online
        if r.is_main or not g.main then
            if g.main then table.insert(g.alts, g.main) end
            g.main = r
        else
            table.insert(g.alts, r)
        end
    end

    local shownGroups = {}
    for _, key in ipairs(order) do
        local g = groups[key]
        local name = (g.main.member_name or g.main.character or ""):lower()
        local matchesQuery = query == "" or name:find(query, 1, true)
        local matchesOnline = not chamber.onlineOnly:GetChecked() or g.online
        local matchesClass = not chamber.classFilter or g.main.class == chamber.classFilter
            or (function() for _, a in ipairs(g.alts) do if a.class == chamber.classFilter then return true end end return false end)()
        local matchesRank = not chamber.rankFilter or g.main.rank == chamber.rankFilter
        if matchesQuery and matchesOnline and matchesClass and matchesRank then
            table.insert(shownGroups, g)
        end
    end
    table.sort(shownGroups, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.main.member_name or a.main.character or "") < (b.main.member_name or b.main.character or "")
    end)

    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if #shownGroups == 0 then
        if not chamber.noResultText then
            chamber.noResultText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.noResultText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.noResultText, query == "" and "No members match these filters." or "No one matches '" .. query .. "'.", true)
        return
    elseif chamber.noResultText then
        chamber.noResultText:SetText("")
    end

    local COLS = chamber.cols
    local function paintRow(ui, r, indent)
        ui.indent:SetWidth(indent)
        setColor(ui.statusIcon, r.online and C.online or C.offline)
        setNameRow(ui.nameRow, r.character, r.class)
        ui.statusWord:ClearAllPoints()
        ui.statusWord:SetPoint("LEFT", ui.nameRow, "RIGHT", 8, 0)
        ui.statusWord:SetText(r.online and "Online" or "Offline")
        ui.levelText:ClearAllPoints()
        ui.levelText:SetPoint("LEFT", COLS.level, 0)
        ui.levelText:SetText(r.level and tostring(r.level) or "--")
        ui.rankText:ClearAllPoints()
        ui.rankText:SetPoint("LEFT", COLS.rank, 0)
        ui.rankText:SetText(r.rank or "")
        ui.zoneText:ClearAllPoints()
        ui.zoneText:SetPoint("LEFT", COLS.zone, 0)
        ui.zoneText:SetText(r.zone or "")
        ui.lastSeenText:ClearAllPoints()
        ui.lastSeenText:SetPoint("LEFT", COLS.lastSeen, 0)
        ui.lastSeenText:SetText(r.online and "now" or (r.last_online_hours and (r.last_online_hours .. "h ago") or "--"))
        ui.whisperBtn:SetScript("OnClick", function()
            if ChatFrame_SendTell then ChatFrame_SendTell(r.character) end
        end)
        ui.inviteBtn:SetScript("OnClick", function()
            if InviteUnit then InviteUnit(r.character) end
        end)
        ui.inviteBtn:SetEnabled(SideQuest.IsOfficer())
        ui:SetScript("OnClick", function()
            for _, other in ipairs(chamber.rows) do
                other.selected = false
            end
            ui.selected = true
        end)
        ui:Show()
    end

    local i = 0
    for _, g in ipairs(shownGroups) do
        i = i + 1
        local ui = chamber.rows[i]
        if not ui then
            ui = buildGuildRow(chamber.content)
            chamber.rows[i] = ui
        end
        local expandKey = g.main.member_id or g.main.character
        local hasAlts = #g.alts > 0
        ui.expandBtn:SetText(hasAlts and (chamber.expanded[expandKey] and "-" or "+") or "")
        ui.expandBtn:SetEnabled(hasAlts)
        ui.expandBtn:SetScript("OnClick", function()
            chamber.expanded[expandKey] = not chamber.expanded[expandKey]
            UI.RefreshGuild()
        end)
        ui:SetPoint("TOPLEFT", 0, -24 * (i - 1))
        paintRow(ui, g.main, 20)
        if hasAlts and chamber.expanded[expandKey] then
            for _, alt in ipairs(g.alts) do
                i = i + 1
                local altUi = chamber.rows[i]
                if not altUi then
                    altUi = buildGuildRow(chamber.content)
                    chamber.rows[i] = altUi
                end
                altUi:SetPoint("TOPLEFT", 0, -24 * (i - 1))
                paintRow(altUi, alt, 46)
            end
        end
    end
    sizeScrollThumb(chamber.scroll, 24 * i)
end

--------------------------------------------------------------------------
-- CRAFTERS tab: search recipes/profession, profession summary row,
-- results as recipe -> crafters (online first, skill, whisper)
--------------------------------------------------------------------------

function UI.BuildCraftersPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.Crafters = panel

    local chamber = createChamber(panel, "SideQuestCraftersChamber")
    chamber:SetPoint("TOPLEFT", 12, -12)
    chamber:SetPoint("BOTTOMRIGHT", -12, 12)
    createRibbon(chamber, "Crafters")

    local searchBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    skinEditBox(searchBox, "Search recipes or crafters")
    searchBox:SetSize(260, 20)
    searchBox:SetPoint("TOPLEFT", 14, -30)
    searchBox:SetAutoFocus(false)
    local searchBtn = createButton(chamber.inner, "primary", "Search", 80, 20)
    searchBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    searchBtn:SetScript("OnClick", function()
        local text = searchBox:GetText()
        if text and text ~= "" then
            SideQuest.Crafters.Query(text)
            UI.RefreshCrafters()
        end
    end)
    chamber.searchBox, chamber.searchBtn = searchBox, searchBtn

    local summaryText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist2, "LEFT")
    summaryText:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -8)
    chamber.summaryText = summaryText

    local scroll, content = buildScroll(chamber.inner, -76)
    chamber.scroll, chamber.content, chamber.groupRows = scroll, content, {}
    panel.chamber = chamber
end

function UI.RefreshCrafters()
    local panel = UI.panels and UI.panels.Crafters
    if not panel then
        return
    end
    local chamber = panel.chamber

    for _, g in ipairs(chamber.groupRows) do
        g.header:Hide()
        for _, r in ipairs(g.rows) do r:Hide() end
    end

    -- bucket by recipe name (or by profession, when a crafter matched on
    -- profession rather than a specific recipe); professions also get a
    -- one-line summary count.
    local recipeBuckets, recipeOrder = {}, {}
    local professionCounts, professionOrder = {}, {}
    local total = 0
    for character, row in pairs(SideQuest.Crafters.results or {}) do
        total = total + 1
        if not professionCounts[row.profession] then
            professionCounts[row.profession] = 0
            table.insert(professionOrder, row.profession)
        end
        professionCounts[row.profession] = professionCounts[row.profession] + 1
        if row.recipes and #row.recipes > 0 then
            for _, recipe in ipairs(row.recipes) do
                if not recipeBuckets[recipe.name] then
                    recipeBuckets[recipe.name] = {}
                    table.insert(recipeOrder, recipe.name)
                end
                table.insert(recipeBuckets[recipe.name], { character = character, skill = row.skill, online = row.online and true or false })
            end
        else
            local key = "Profession: " .. (row.profession or "?")
            if not recipeBuckets[key] then
                recipeBuckets[key] = {}
                table.insert(recipeOrder, key)
            end
            table.insert(recipeBuckets[key], { character = character, skill = row.skill, online = row.online and true or false })
        end
    end

    local summaryParts = {}
    for _, prof in ipairs(professionOrder) do
        table.insert(summaryParts, prof .. " (" .. professionCounts[prof] .. ")")
    end
    if #summaryParts > 0 then
        chamber.summaryText:SetTextColor(C.mist2[1], C.mist2[2], C.mist2[3], 1)
        chamber.summaryText:SetText(table.concat(summaryParts, "  --  "))
    else
        chamber.summaryText:SetText("")
    end

    if total == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "Search a recipe or profession above to see who can craft it.", false)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    local y = 0
    local gi = 0
    for _, recipeName in ipairs(recipeOrder) do
        gi = gi + 1
        local g = chamber.groupRows[gi]
        if not g then
            g = { header = createSubHeading(chamber.content, ""), rows = {} }
            g.header:SetWidth(540)
            chamber.groupRows[gi] = g
        end
        g.header:ClearAllPoints()
        g.header:SetPoint("TOPLEFT", 0, -y)
        g.header.label:SetText(trackedCaps(recipeName))
        g.header:Show()
        y = y + 18

        local crafters = recipeBuckets[recipeName]
        table.sort(crafters, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.character < b.character
        end)
        for ri, entry in ipairs(crafters) do
            local row = g.rows[ri]
            if not row then
                row = CreateFrame("Frame", nil, chamber.content)
                row:SetSize(540, 20)
                row.nameRow = createNameRow(row, 12)
                row.nameRow:SetPoint("LEFT", 4, 0)
                row.skillText = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
                row.whisperBtn = createButton(row, "quiet", "Whisper", 66, 18)
                row.whisperBtn:SetPoint("RIGHT", 0, 0)
                g.rows[ri] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            setNameRow(row.nameRow, entry.character, nil)
            row.skillText:ClearAllPoints()
            row.skillText:SetPoint("LEFT", row.nameRow, "RIGHT", 10, 0)
            row.skillText:SetText((entry.skill and ("skill " .. entry.skill) or "") .. (entry.online and "  (online)" or "  (offline)"))
            row.whisperBtn:SetScript("OnClick", function()
                if ChatFrame_SendTell then ChatFrame_SendTell(entry.character) end
            end)
            row:Show()
            y = y + 20
        end
        y = y + 6
    end
    sizeScrollThumb(chamber.scroll, y)
end

--------------------------------------------------------------------------
-- RAIDS tab: date/time, role counts, your answer, officer actions
--------------------------------------------------------------------------

function UI.BuildRaidsPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.Raids = panel

    local chamber = createChamber(panel, "SideQuestRaidsChamber")
    chamber:SetPoint("TOPLEFT", 12, -12)
    chamber:SetPoint("BOTTOMRIGHT", -12, 12)
    createRibbon(chamber, "Raids")

    local scroll, content = buildScroll(chamber.inner, -34)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    panel.chamber = chamber
end

local function disableWithReason(btn, reasonText, enabled, reason)
    btn:SetEnabled(enabled)
    if reasonText then
        reasonText:SetText(enabled and "" or reason)
    end
end

function UI.RefreshRaids()
    local panel = UI.panels and UI.panels.Raids
    if not panel then
        return
    end
    local chamber = panel.chamber
    local events = SideQuest.Events.Get()
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if #events == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "No raids scheduled yet.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    local isOfficer = SideQuest.IsOfficer()
    local y = 0
    for i, evt in ipairs(events) do
        local row = chamber.rows[i]
        if not row then
            row = createQuestLogRow(chamber.content)
            row:SetHeight(isOfficer and 86 or 64)
            row.roleCounts = makeFontString(row, FONT_BODY, 11, C.mist, "LEFT")
            row.roleCounts:SetPoint("TOPLEFT", row.meta, "BOTTOMLEFT", 0, -4)
            row.answers = {}
            for j, a in ipairs({ { "going", "Going" }, { "maybe", "Maybe" }, { "cant", "Can't" } }) do
                local btn = createButton(row, "quiet", a[2], 60, 20)
                btn:SetPoint("TOPLEFT", row.roleCounts, "BOTTOMLEFT", (j - 1) * 64, -6)
                row.answers[a[1]] = btn
            end
            row.inviteBtn = createButton(row, "primary", "Invite signed", 120, 20)
            row.inviteBtn:SetPoint("TOPLEFT", row.answers.going, "BOTTOMLEFT", 0, -6)
            row.placeBtn = createButton(row, "primary", "Place groups", 120, 20)
            row.placeBtn:SetPoint("LEFT", row.inviteBtn, "RIGHT", 8, 0)
            row.officerReason = makeFontString(row, FONT_BODY, 10, C.errorC, "LEFT")
            row.officerReason:SetPoint("TOPLEFT", row.inviteBtn, "BOTTOMLEFT", 0, -2)
            chamber.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        y = y + (isOfficer and 92 or 70)
        local isOpen = (evt.starts_at or 0) > now()
        row.mark:SetText(isOpen and "!" or "?")
        row.title:SetText(evt.title or "Raid")
        row.meta:SetText((evt.kind or "raid") .. "  --  " .. os.date("%A %b %d, %H:%M", evt.starts_at or now()))

        local roleCounts = { tank = 0, healer = 0, dps = 0 }
        for _, s in ipairs(evt.signups or {}) do
            if s.status == "signed" and roleCounts[s.role] ~= nil then
                roleCounts[s.role] = roleCounts[s.role] + 1
            end
        end
        row.roleCounts:SetText(string.format("Signed: Tank %d  --  Healer %d  --  DPS %d  (%d total)",
            roleCounts.tank, roleCounts.healer, roleCounts.dps, #(evt.signups or {})))

        local _, status = SideQuest.Signups.MyState(evt.id)
        local statusToAnswer = { signed = "going", tentative = "maybe", absent = "cant" }
        local currentAnswer = statusToAnswer[status]
        for answer, btn in pairs(row.answers) do
            btn:SetScript("OnClick", function()
                SideQuest.Signups.Answer(evt.id, answer)
                UI.RefreshRaids()
            end)
            setColor(btn.well or btn, answer == currentAnswer and C.royal or C.night2)
        end

        row.inviteBtn:SetShown(isOfficer)
        row.placeBtn:SetShown(isOfficer)
        row.officerReason:SetShown(isOfficer)
        if isOfficer then
            local inCombat = SideQuest.InCombat()
            local isLeader = type(IsRaidLeader) == "function" and IsRaidLeader()
                or type(IsPartyLeader) == "function" and IsPartyLeader()
                or not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup())
            local enabled = not inCombat and isLeader
            local reason = inCombat and "Disabled in combat" or (not isLeader and "Disabled: you are not the raid leader" or "")
            disableWithReason(row.inviteBtn, row.officerReason, enabled, reason)
            disableWithReason(row.placeBtn, row.officerReason, enabled, reason)
            row.inviteBtn:SetScript("OnClick", function()
                SideQuest.Events.InviteSigned(evt.id)
            end)
            row.placeBtn:SetScript("OnClick", function()
                SideQuest.Prep.PlaceGroups(evt.id)
            end)
        end
        row:Show()
    end
    sizeScrollThumb(chamber.scroll, y)
end

--------------------------------------------------------------------------
-- LEDGER tab: standings table, your sheet history (with loading/offline
-- states), recent loot log with quality-coloured item icons
--------------------------------------------------------------------------

function UI.BuildLedgerPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.Ledger = panel

    local chamber = createChamber(panel, "SideQuestLedgerChamber")
    chamber:SetPoint("TOPLEFT", 12, -12)
    chamber:SetPoint("BOTTOMRIGHT", -12, 12)
    createRibbon(chamber, "Ledger")

    local sheetBtn = createButton(chamber.inner, "primary", "Ask for my sheet", 140, 20)
    sheetBtn:SetPoint("TOPLEFT", 14, -30)
    sheetBtn:SetScript("OnClick", function()
        chamber.sheetState = "loading"
        chamber.sheetAskedAt = now()
        SideQuest.Sheet.Request()
        UI.RefreshLedger()
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function()
                if chamber.sheetState == "loading" and chamber.sheetAskedAt and (now() - chamber.sheetAskedAt) >= 8 then
                    chamber.sheetState = "timeout"
                    UI.RefreshLedger()
                end
            end)
        end
    end)
    chamber.sheetBtn = sheetBtn
    chamber.sheetState = SideQuest.Sheet.lastAnswer and "answered" or "idle"

    local header = CreateFrame("Frame", nil, chamber.inner)
    header:SetPoint("TOPLEFT", sheetBtn, "BOTTOMLEFT", 0, -12)
    header:SetPoint("RIGHT", -28, 0)
    header:SetHeight(14)
    local LCOLS = { name = 4, ep = 300, gp = 370, pr = 440, rank = 500 }
    chamber.ledgerCols = LCOLS
    local function lh(text, x, justify)
        local fs = makeFontString(header, FONT_BODY, 10, C.mist2, justify or "RIGHT")
        fs:SetPoint("TOPLEFT", x, 0)
        fs:SetText(trackedCaps(text))
        return fs
    end
    local nameHdr = makeFontString(header, FONT_BODY, 10, C.mist2, "LEFT")
    nameHdr:SetPoint("TOPLEFT", LCOLS.name, 0)
    nameHdr:SetText(trackedCaps("Name"))
    lh("EP", LCOLS.ep)
    lh("GP", LCOLS.gp)
    lh("PR", LCOLS.pr)
    local rankHdr = makeFontString(header, FONT_BODY, 10, C.mist2, "LEFT")
    rankHdr:SetPoint("TOPLEFT", LCOLS.rank, 0)
    rankHdr:SetText(trackedCaps("Rank"))
    local headerLine = hairline(chamber.inner)
    headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    headerLine:SetPoint("RIGHT", -28, 0)

    local scroll, content = buildScroll(chamber.inner, -76)
    chamber.scroll, chamber.content, chamber.rows, chamber.lootRows = scroll, content, {}, {}
    panel.chamber = chamber
end

function UI.RefreshLedger()
    local panel = UI.panels and UI.panels.Ledger
    if not panel then
        return
    end
    local chamber = panel.chamber
    local me = SideQuest.NormalizeUnit("player")
    local LCOLS = chamber.ledgerCols
    local rows = SideQuest.Standings.GetDisplayRows()
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if #rows == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "No standings yet -- an officer imports them after the first raid.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    for i, row in ipairs(rows) do
        local ui = chamber.rows[i]
        if not ui then
            ui = CreateFrame("Frame", nil, chamber.content)
            ui:SetSize(560, 20)
            ui.highlight = ui:CreateTexture(nil, "BACKGROUND")
            ui.highlight:SetAllPoints(ui)
            setColor(ui.highlight, C.royal2)
            ui.highlight:Hide()
            ui.nameRow = createNameRow(ui, 13)
            ui.nameRow:SetPoint("LEFT", LCOLS.name, 0)
            ui.epText = makeFontString(ui, FONT_BODY, 12, C.gold, "RIGHT")
            ui.epText:SetPoint("LEFT", LCOLS.ep, 0)
            ui.epText:SetWidth(60)
            ui.gpText = makeFontString(ui, FONT_BODY, 12, C.mist, "RIGHT")
            ui.gpText:SetPoint("LEFT", LCOLS.gp, 0)
            ui.gpText:SetWidth(60)
            ui.prText = makeFontString(ui, FONT_BODY, 12, C.ink, "RIGHT")
            ui.prText:SetPoint("LEFT", LCOLS.pr, 0)
            ui.prText:SetWidth(50)
            ui.rankText = makeFontString(ui, FONT_BODY, 11, C.mist2, "LEFT")
            ui.rankText:SetPoint("LEFT", LCOLS.rank, 0)
            chamber.rows[i] = ui
        end
        ui:SetPoint("TOPLEFT", 0, -22 * (i - 1))
        setNameRow(ui.nameRow, row.name or row.main, row.class)
        ui.epText:SetText(string.format("%.0f", row.ep or 0))
        ui.gpText:SetText(string.format("%.0f", row.gp or 0))
        ui.prText:SetText(string.format("%.3f%s", row.pr or 0, row.provisional and "*" or ""))
        ui.rankText:SetText(row.trial and "Trial" or "")
        local isMe = false
        for _, char in ipairs(row.characters or {}) do
            if char == me then isMe = true end
        end
        ui.highlight:SetShown(isMe)
        ui:Show()
    end

    -- your sheet history: loading / no-officer-online / answered states
    local sheet = SideQuest.Sheet.lastAnswer
    local loot = (sheet and sheet.loot) or {}
    for _, r in ipairs(chamber.lootRows) do
        r:Hide()
    end
    local lootTop = -22 * (#rows + 1)
    if not chamber.lootHeading then
        chamber.lootHeading = createSubHeading(chamber.content, "Your recent loot")
        chamber.lootHeading:SetWidth(540)
        chamber.lootStateText = makeFontString(chamber.content, FONT_BODY, 11, C.mist2, "LEFT")
    end
    chamber.lootHeading:ClearAllPoints()
    chamber.lootHeading:SetPoint("TOPLEFT", 0, lootTop)
    chamber.lootStateText:ClearAllPoints()
    chamber.lootStateText:SetPoint("TOPLEFT", 0, lootTop - 18)

    if chamber.sheetState == "loading" then
        setStateText(chamber.lootStateText, "Asking an officer for your sheet...", false)
    elseif chamber.sheetState == "timeout" or (sheet and sheet.found == false) then
        setStateText(chamber.lootStateText, "No officer online to answer -- try again later.", true)
    elseif #loot == 0 then
        setStateText(chamber.lootStateText, "Ask for your sheet above to see it.", true)
    else
        chamber.lootStateText:SetText("")
    end

    for i, item in ipairs(loot) do
        local ui = chamber.lootRows[i]
        if not ui then
            ui = CreateFrame("Frame", nil, chamber.content)
            ui:SetSize(560, 20)
            ui.swatch = ui:CreateTexture(nil, "BACKGROUND")
            ui.swatch:SetSize(16, 16)
            ui.swatch:SetPoint("LEFT", 0, 0)
            ui.icon = ui:CreateTexture(nil, "ARTWORK")
            ui.icon:SetSize(14, 14)
            ui.icon:SetPoint("CENTER", ui.swatch, "CENTER")
            ui.nameText = makeFontString(ui, FONT_BODY, 12, C.ink, "LEFT")
            ui.nameText:SetPoint("LEFT", ui.swatch, "RIGHT", 8, 0)
            chamber.lootRows[i] = ui
        end
        ui:SetPoint("TOPLEFT", 0, lootTop - 22 - 20 * i)
        local qColor = QUALITY_COLOR[item.quality or 1] or QUALITY_COLOR[1]
        setColor(ui.swatch, qColor)
        if ui.icon.SetTexture and item.item_id and C_Item and C_Item.GetItemInfoInstant then
            local _, _, _, _, icon = C_Item.GetItemInfoInstant(item.item_id)
            if icon then ui.icon:SetTexture(icon) end
        end
        ui.nameText:SetTextColor(qColor[1], qColor[2], qColor[3], 1)
        ui.nameText:SetText((item.item_name or "Item") .. "  GP " .. (item.gp or 0) .. "  (" .. (item.response or "ms") .. ")")
        ui:Show()
    end
    sizeScrollThumb(chamber.scroll, (22 * (#rows + 1)) + 40 + 20 * #loot)
end

--------------------------------------------------------------------------
-- NEWS tab: one icon per kind, grouped by day
--------------------------------------------------------------------------

function UI.BuildNewsPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.News = panel

    local chamber = createChamber(panel, "SideQuestNewsChamber")
    chamber:SetPoint("TOPLEFT", 12, -12)
    chamber:SetPoint("BOTTOMRIGHT", -12, 12)
    createRibbon(chamber, "News")

    local scroll, content = buildScroll(chamber.inner, -34)
    chamber.scroll, chamber.content, chamber.rows, chamber.dayHeadings = scroll, content, {}, {}
    panel.chamber = chamber
end

function UI.RefreshNews()
    local panel = UI.panels and UI.panels.News
    if not panel then
        return
    end
    local chamber = panel.chamber
    local items = SideQuest.News.Get()
    for _, r in ipairs(chamber.rows) do r:Hide() end
    for _, h in ipairs(chamber.dayHeadings) do h:Hide() end
    if #items == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "Nothing's happened yet.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    local y, hi, ri, lastDay = 0, 0, 0, nil
    for _, item in ipairs(items) do
        local day = dayLabel(item.at or now())
        if day ~= lastDay then
            hi = hi + 1
            local h = chamber.dayHeadings[hi]
            if not h then
                h = createSubHeading(chamber.content, "")
                h:SetWidth(540)
                chamber.dayHeadings[hi] = h
            end
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, -y)
            h.label:SetText(trackedCaps(day))
            h:Show()
            y = y + 20
            lastDay = day
        end
        ri = ri + 1
        local row = chamber.rows[ri]
        if not row then
            row = createNewsRow(chamber.content)
            chamber.rows[ri] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        setNewsIcon(row, item)
        row.title:SetText(item.text or NEWS_KIND_WORD[item.kind] or item.kind)
        row.meta:SetText((item.character and (displayName(item.character) .. "  ") or "") .. os.date("%H:%M", item.at or now()))
        row:Show()
        y = y + 32
    end
    sizeScrollThumb(chamber.scroll, y)
end

--------------------------------------------------------------------------
-- Announcement toast
--------------------------------------------------------------------------

function UI.BuildToast()
    if UI.toast then
        return UI.toast
    end
    local toast = CreateFrame("Frame", "SideQuestToast", UIParent, "BackdropTemplate")
    toast:SetSize(360, 56)
    toast:SetPoint("TOP", 0, -60)
    local fill = toast:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(toast)
    setColor(fill, C.night3)
    local edge = toast:CreateTexture(nil, "BORDER")
    edge:SetAllPoints(toast)
    setColor(edge, C.goldDeep)
    local officerText = makeFontString(toast, FONT_BODY, 12, C.gold, "CENTER")
    officerText:SetPoint("TOP", 0, -8)
    local textFs = makeFontString(toast, FONT_BODY_ITALIC, 14, C.flavor, "CENTER")
    textFs:SetPoint("CENTER", 0, -4)
    if textFs.SetWordWrap then
        textFs:SetWidth(330)
        textFs:SetWordWrap(true)
    end
    toast.officerText, toast.textFs = officerText, textFs
    toast:Hide()
    UI.toast = toast
    return toast
end

function UI.ShowToast(item)
    -- announcements never show during combat; queue like everything else
    SideQuest.WhenOutOfCombat(function()
        local toast = UI.BuildToast()
        toast.officerText:SetText(displayName(item.officer) or "An officer")
        toast.textFs:SetText(item.text or "")
        toast:Show()
        if C_Timer and C_Timer.After then
            C_Timer.After(6, function()
                toast:Hide()
            end)
        end
    end)
end

SideQuest.On("SQ_ANNOUNCEMENT_RECEIVED", function(item)
    UI.ShowToast(item)
end)

--------------------------------------------------------------------------
-- CONSOLE tab (officers/GMs only, gold-edged): sub-views, tabs chrome
--------------------------------------------------------------------------

function UI.BuildConsolePanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels[OFFICER_TAB] = panel

    local subBar = CreateFrame("Frame", nil, panel)
    subBar:SetPoint("TOPLEFT", 12, -12)
    subBar:SetPoint("TOPRIGHT", -12, -12)
    subBar:SetHeight(26)
    local subWidth = math.floor((WINDOW_DEFAULT_W - 24) / #CONSOLE_SUBTABS)
    panel.subButtons = {}
    for i, name in ipairs(CONSOLE_SUBTABS) do
        local btn = CreateFrame("Button", nil, subBar)
        btn:SetSize(subWidth, 24)
        btn:SetPoint("LEFT", (i - 1) * subWidth, 0)
        local well = btn:CreateTexture(nil, "BACKGROUND")
        well:SetAllPoints(btn)
        setColor(well, C.night2)
        local border = addBorder(btn, C.goldDeep, 1) -- console sub-tabs are gold-edged throughout
        local label = makeFontString(btn, FONT_BODY, 11, C.mist, "CENTER")
        label:SetPoint("CENTER")
        label:SetText(trackedCaps(name))
        btn.well, btn.label, btn.border = well, label, border
        btn:SetScript("OnClick", function()
            UI.ShowConsoleSub(name)
        end)
        panel.subButtons[name] = btn
    end

    panel.subPanels = {}
    UI.BuildConsoleRaidNight(panel)
    UI.BuildConsoleLoot(panel)
    UI.BuildConsoleRoster(panel)
    UI.BuildConsoleRecruits(panel)
    UI.BuildConsoleBank(panel)
    UI.BuildConsoleAnnounce(panel)
    UI.BuildConsoleSync(panel)
end

function UI.ShowConsoleSub(name)
    local panel = UI.panels[OFFICER_TAB]
    for subName, sub in pairs(panel.subPanels) do
        if subName == name then
            sub:Show()
        else
            sub:Hide()
        end
    end
    for subName, btn in pairs(panel.subButtons) do
        setColor(btn.well, subName == name and C.royal or C.night2)
        if btn.label and btn.label.SetTextColor then
            local c = subName == name and C.gold or C.mist
            btn.label:SetTextColor(c[1], c[2], c[3], 1)
        end
    end
    panel.activeSub = name
    if name == "Raid Night" then
        UI.RefreshConsoleRaidNight()
    elseif name == "Loot" then
        UI.RefreshBidRanking()
    elseif name == "Roster" then
        UI.RefreshConsoleRoster()
    elseif name == "Recruits" then
        UI.RefreshConsoleRecruits()
    elseif name == "Bank" then
        UI.RefreshConsoleBank()
    elseif name == "Sync" then
        UI.RefreshConsoleSync()
    end
end

function UI.RefreshConsole()
    if not SideQuest.IsOfficer() then
        return
    end
    UI.ShowConsoleSub(UI.panels[OFFICER_TAB].activeSub or "Raid Night")
end

local function makeConsoleSub(panel, key)
    local sub = CreateFrame("Frame", nil, panel)
    -- subBar sits at TOPLEFT(12,-12) with height 26, so its bottom edge is
    -- 38px below panel.top; the chamber's ribbon is centred ON its own top
    -- edge (half above it), so the chamber itself must start well below
    -- that before the ribbon clears the sub-tab strip instead of touching it.
    sub:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -60)
    sub:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
    sub:Hide()
    panel.subPanels[key] = sub
    return sub
end

-- Raid Night: the numbered course (Prep, Invite, Start, each boss, Loot,
-- End); each step punches as it's done and shows its time, plus roster
-- presence, the standby list and the auto-award log with Undo.

function UI.BuildConsoleRaidNight(panel)
    local sub = makeConsoleSub(panel, "Raid Night")
    local chamber = createChamber(sub, "SideQuestRaidNightChamber")
    chamber:SetAllPoints(sub)
    createRibbon(chamber, "Raid Night")

    local scroll, content = buildScroll(chamber.inner, -30)
    chamber.scroll, chamber.content = scroll, content

    local courseHeading = createSubHeading(content, "Tonight's course")
    courseHeading:SetPoint("TOPLEFT", 0, 0)
    courseHeading:SetWidth(520)
    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", courseHeading, "BOTTOMLEFT", 0, -6)
    list:SetPoint("RIGHT", 0, 0)
    chamber.stepRows = {}

    local steps = {
        { key = "prep", label = "Prep -- ask the raid to report readiness", action = function()
            SideQuest.Prep.RequestCheck({})
        end },
        { key = "invite", label = "Invite -- bring in everyone signed", action = function()
            local evt = SideQuest.Events.Get()[1]
            if evt then SideQuest.Events.InviteSigned(evt.id) end
        end },
        { key = "start", label = "Start raid -- on-time EP, begin recording", action = function()
            SideQuest.Recorder.StartRaid()
        end },
        { key = "boss", label = "Boss -- encounters record automatically", action = nil },
        { key = "loot", label = "Loot -- open bidding from the Loot sub-view", action = function()
            UI.ShowConsoleSub("Loot")
        end },
        { key = "end", label = "End raid -- full-night EP, stop recording", action = function()
            SideQuest.Recorder.EndRaid()
        end },
    }
    chamber.steps = steps
    list:SetHeight(26 * #steps)

    for i, step in ipairs(steps) do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(500, 24)
        row:SetPoint("TOPLEFT", 0, -26 * (i - 1))
        -- one number, in a gold-deep plate (never doubled with the label).
        local numPlate = row:CreateTexture(nil, "BACKGROUND")
        numPlate:SetSize(20, 20)
        numPlate:SetPoint("LEFT", 0, 0)
        setColor(numPlate, C.goldDeep)
        local num = makeFontString(row, FONT_DISPLAY, 12, C.inkOnGold, "CENTER")
        num:SetPoint("CENTER", numPlate, "CENTER", 0, 0)
        num:SetText(tostring(i))
        local label = makeFontString(row, FONT_BODY, 13, C.ink, "LEFT")
        label:SetPoint("LEFT", numPlate, "RIGHT", 10, 0)
        label:SetWidth(280)
        label:SetText(step.label)
        -- state + time, each its own right-aligned column.
        local timeText = makeFontString(row, FONT_BODY, 11, C.mist2, "RIGHT")
        timeText:SetPoint("RIGHT", 0, 0)
        timeText:SetWidth(70)
        local btn = step.action and createButton(row, "primary", "Mark done", 90, 22) or nil
        if btn then
            btn:SetPoint("RIGHT", timeText, "LEFT", -8, 0)
            btn:SetScript("OnClick", function()
                if step.action then step.action() end
                step.doneAt = now()
                UI.RefreshConsoleRaidNight()
            end)
        end
        row.numPlate, row.num, row.label, row.timeText, row.btn = numPlate, num, label, timeText, btn
        chamber.stepRows[i] = row
    end

    local presenceHeading = createSubHeading(content, "Roster presence")
    presenceHeading:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -10)
    presenceHeading:SetWidth(520)
    local presenceText = makeFontString(content, FONT_BODY, 12, C.mist, "LEFT")
    presenceText:SetPoint("TOPLEFT", presenceHeading, "BOTTOMLEFT", 0, -6)
    presenceText:SetWidth(520)
    if presenceText.SetWordWrap then presenceText:SetWordWrap(true) end

    local standbyHeading = createSubHeading(content, "Standby")
    standbyHeading:SetPoint("TOPLEFT", presenceText, "BOTTOMLEFT", 0, -10)
    standbyHeading:SetWidth(520)
    local standbyText = makeFontString(content, FONT_BODY, 12, C.mist, "LEFT")
    standbyText:SetPoint("TOPLEFT", standbyHeading, "BOTTOMLEFT", 0, -6)
    standbyText:SetWidth(520)
    if standbyText.SetWordWrap then standbyText:SetWordWrap(true) end

    local awardHeading = createSubHeading(content, "Auto-award log")
    awardHeading:SetPoint("TOPLEFT", standbyText, "BOTTOMLEFT", 0, -10)
    awardHeading:SetWidth(520)
    local awardList = CreateFrame("Frame", nil, content)
    awardList:SetPoint("TOPLEFT", awardHeading, "BOTTOMLEFT", 0, -6)
    awardList:SetPoint("RIGHT", 0, 0)
    chamber.awardRows = {}

    chamber.presenceText, chamber.standbyText, chamber.awardHeading, chamber.awardList =
        presenceText, standbyText, awardHeading, awardList
    panel.raidNightChamber = chamber
end

function UI.RefreshConsoleRaidNight()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.raidNightChamber then
        return
    end
    local chamber = panel.raidNightChamber
    -- the first not-yet-done step after at least one done step is "current" (mid-course)
    local sawDone, current = false, nil
    for i, step in ipairs(chamber.steps) do
        if step.doneAt then
            sawDone = true
        elseif sawDone and not current then
            current = i
        end
    end
    for i, step in ipairs(chamber.steps) do
        local row = chamber.stepRows[i]
        if step.doneAt then
            row.timeText:SetText(os.date("%H:%M", step.doneAt))
            row.label:SetTextColor(C.mist2[1], C.mist2[2], C.mist2[3], 1)
            setColor(row.numPlate, C.stone)
            if row.btn then
                row.btn:SetText("Done")
                row.btn:Disable()
            end
        elseif i == current then
            row.timeText:SetText("In progress")
            row.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3], 1)
            setColor(row.numPlate, C.gold)
        else
            row.timeText:SetText("")
            row.label:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
            setColor(row.numPlate, C.goldDeep)
        end
    end

    -- roster presence (who the recorder currently counts as raid/standby)
    local present = SideQuest.Recorder.present or {}
    local raidNames, standbyFromPresent = {}, {}
    for char, status in pairs(present) do
        if status == "standby" then
            table.insert(standbyFromPresent, displayName(char))
        else
            table.insert(raidNames, displayName(char))
        end
    end
    table.sort(raidNames)
    chamber.presenceText:SetText(#raidNames > 0 and (#raidNames .. " in raid: " .. table.concat(raidNames, ", "))
        or "No one marked present yet -- recording starts this automatically.")

    local standby = SideQuestDB.standby or {}
    local standbyNames = {}
    for _, char in ipairs(standby) do
        table.insert(standbyNames, displayName(char))
    end
    for _, n in ipairs(standbyFromPresent) do
        table.insert(standbyNames, n)
    end
    if #standbyNames > 0 then
        chamber.standbyText:SetText(table.concat(standbyNames, ", "))
    else
        setStateText(chamber.standbyText, "No one on standby.", true)
    end

    -- auto-award log with Undo (most recent first)
    local awards = SideQuestDB.pending.awards or {}
    for _, r in ipairs(chamber.awardRows) do r:Hide() end
    if #awards == 0 then
        if not chamber.awardEmptyText then
            chamber.awardEmptyText = makeFontString(chamber.awardList, FONT_BODY, 11, C.mist2, "LEFT")
        end
        setStateText(chamber.awardEmptyText, "No awards recorded yet tonight.", true)
    elseif chamber.awardEmptyText then
        chamber.awardEmptyText:SetText("")
    end
    local shown = math.min(#awards, 8)
    for i = 1, shown do
        local award = awards[#awards - i + 1]
        local row = chamber.awardRows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.awardList)
            row:SetSize(500, 18)
            row.text = makeFontString(row, FONT_BODY, 11, C.ink, "LEFT")
            row.text:SetPoint("LEFT")
            row.undoBtn = createButton(row, "quiet", "Undo", 50, 16)
            row.undoBtn:SetPoint("RIGHT")
            chamber.awardRows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -18 * (i - 1))
        local voided = award.voided
        row.text:SetTextColor(voided and C.mist2[1] or C.ink[1], voided and C.mist2[2] or C.ink[2], voided and C.mist2[3] or C.ink[3], 1)
        row.text:SetText(string.format("%s%s %s %+d (%s)%s", voided and "[voided] " or "", displayName(award.character or ""),
            award.kind == "ep" and "EP" or "GP", award.amount or 0, award.reason or "", award.note and (" -- " .. award.note) or ""))
        row.undoBtn:SetShown(not voided)
        row.undoBtn:SetScript("OnClick", function()
            SideQuest.Recorder.Undo(award.id)
            UI.RefreshConsoleRaidNight()
        end)
        row:Show()
    end
    chamber.awardHeading.label:SetText(trackedCaps("Auto-award log (" .. #awards .. ")"))
end

-- Loot sub-view: the item up for bid (icon, quality-colour name, slot, GP
-- cost), each response ranked per contract order with PR/EP columns and
-- a per-row Award button, plus Close bidding and the time left.
function UI.BuildConsoleLoot(panel)
    local sub = makeConsoleSub(panel, "Loot")
    local chamber = createChamber(sub, "SideQuestConsoleLootChamber")
    chamber:SetAllPoints(sub)
    createRibbon(chamber, "Loot")

    local openLootBtn = createButton(chamber.inner, "primary", "Open bidding (loot window)", 180, 22)
    openLootBtn:SetPoint("TOPLEFT", 14, -30)
    openLootBtn:SetScript("OnClick", function()
        for _, item in ipairs(SideQuest.Loot.GetLootWindowItems()) do
            SideQuest.Loot.OpenBid(item.link)
        end
    end)
    local closeBtn = createButton(chamber.inner, "primary", "Close bidding", 130, 22)
    closeBtn:SetPoint("LEFT", openLootBtn, "RIGHT", 8, 0)
    closeBtn:SetScript("OnClick", function()
        SideQuest.Loot.CloseBid()
        UI.RefreshBidRanking()
    end)

    -- the item up for bid: icon (quality-colour swatch), name in its
    -- quality colour, slot + GP cost, and the time left -- the loot
    -- window itself only shows a raw link, never what's about to be awarded.
    local iconSwatch = chamber.inner:CreateTexture(nil, "BACKGROUND")
    iconSwatch:SetSize(32, 32)
    iconSwatch:SetPoint("TOPLEFT", openLootBtn, "BOTTOMLEFT", 0, -10)
    local icon = chamber.inner:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER", iconSwatch, "CENTER")
    local itemText = makeFontString(chamber.inner, FONT_DISPLAY, 13, C.ink, "LEFT")
    itemText:SetPoint("TOPLEFT", iconSwatch, "TOPRIGHT", 10, -2)
    local slotGpText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist, "LEFT")
    slotGpText:SetPoint("TOPLEFT", itemText, "BOTTOMLEFT", 0, -4)
    local timeLeftText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist2, "LEFT")
    timeLeftText:SetPoint("TOPLEFT", slotGpText, "BOTTOMLEFT", 0, -2)

    local header = CreateFrame("Frame", nil, chamber.inner)
    header:SetPoint("TOPLEFT", timeLeftText, "BOTTOMLEFT", 0, -10)
    header:SetHeight(14)
    local COLS = { rank = 0, name = 40, pr = 330, ep = 400, award = 470 }
    chamber.bidCols = COLS
    local rankHdr = makeFontString(header, FONT_BODY, 10, C.mist2, "LEFT")
    rankHdr:SetPoint("LEFT", COLS.rank, 0)
    rankHdr:SetText(trackedCaps("Rank"))
    local nameHdr = makeFontString(header, FONT_BODY, 10, C.mist2, "LEFT")
    nameHdr:SetPoint("LEFT", COLS.name, 0)
    nameHdr:SetText(trackedCaps("Character  --  response"))
    local prHdr = makeFontString(header, FONT_BODY, 10, C.mist2, "RIGHT")
    prHdr:SetPoint("LEFT", COLS.pr, 0)
    prHdr:SetWidth(60)
    prHdr:SetText(trackedCaps("PR"))
    local epHdr = makeFontString(header, FONT_BODY, 10, C.mist2, "RIGHT")
    epHdr:SetPoint("LEFT", COLS.ep, 0)
    epHdr:SetWidth(60)
    epHdr:SetText(trackedCaps("EP"))

    local scroll, content = buildScroll(chamber.inner, -140)
    chamber.scroll, chamber.content, chamber.bidRows = scroll, content, {}
    chamber.iconSwatch, chamber.icon, chamber.itemText, chamber.slotGpText, chamber.timeLeftText =
        iconSwatch, icon, itemText, slotGpText, timeLeftText
    panel.lootChamber = chamber
end

function UI.RefreshBidRanking(bid)
    local panel = UI.panels and UI.panels[OFFICER_TAB]
    if not panel or not panel.lootChamber then
        return
    end
    local chamber = panel.lootChamber
    bid = bid or SideQuest.Loot.activeBid
    for _, r in ipairs(chamber.bidRows) do
        r:Hide()
    end
    if not bid then
        setColor(chamber.iconSwatch, C.stone2)
        if chamber.icon.SetTexture then chamber.icon:SetTexture(nil) end
        setStateText(chamber.itemText, "No item up for bid.", true)
        chamber.slotGpText:SetText("")
        chamber.timeLeftText:SetText("")
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "No responses yet.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    -- the item itself: icon/name in quality colour, slot + GP, time left
    local info = UI.ResolveItemInfo(bid.itemLink)
    local qColor = QUALITY_COLOR[info.quality] or QUALITY_COLOR[1]
    setColor(chamber.iconSwatch, qColor)
    if info.icon and chamber.icon.SetTexture then
        chamber.icon:SetTexture(info.icon)
    end
    chamber.itemText:SetTextColor(qColor[1], qColor[2], qColor[3], 1)
    chamber.itemText:SetText(info.name)
    chamber.slotGpText:SetText((info.slotWord or "Slot unknown") .. (info.gp and ("  --  GP " .. info.gp) or ""))
    local remaining = math.max(0, (bid.startedAt or now()) + (bid.timeout or 30) - now())
    chamber.timeLeftText:SetText(remaining .. "s remaining")

    local prByChar, epByChar = {}, {}
    for _, row in ipairs(SideQuest.Standings.GetDisplayRows()) do
        for _, char in ipairs(row.characters or {}) do
            prByChar[char], epByChar[char] = row.pr or 0, row.ep or 0
        end
    end
    local bids = {}
    for character, response in pairs(bid.responses or {}) do
        table.insert(bids, { character = character, response = response, pr = prByChar[character] or 0, ep = epByChar[character] or 0 })
    end
    local ranked = SideQuest.Loot.RankBids(bids, now())
    local COLS = chamber.bidCols
    for i, entry in ipairs(ranked) do
        local row = chamber.bidRows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.content)
            row:SetSize(760, 22)
            row.rankText = makeFontString(row, FONT_DISPLAY, 13, C.gold, "LEFT")
            row.rankText:SetPoint("LEFT", COLS.rank, 0)
            row.nameRow = createNameRow(row, 12)
            row.nameRow:SetPoint("LEFT", COLS.name, 0)
            row.responseText = makeFontString(row, FONT_BODY, 12, C.mist, "LEFT")
            row.prText = makeFontString(row, FONT_BODY, 12, C.gold, "RIGHT")
            row.prText:SetPoint("LEFT", COLS.pr, 0)
            row.prText:SetWidth(60)
            row.epText = makeFontString(row, FONT_BODY, 12, C.mist, "RIGHT")
            row.epText:SetPoint("LEFT", COLS.ep, 0)
            row.epText:SetWidth(60)
            row.awardBtn = createButton(row, "primary", "Award", 80, 20)
            row.awardBtn:SetPoint("LEFT", COLS.award, 0)
            chamber.bidRows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -22 * (i - 1))
        row.rankText:SetText(tostring(i))
        setNameRow(row.nameRow, entry.character, nil)
        row.responseText:ClearAllPoints()
        row.responseText:SetPoint("LEFT", row.nameRow, "RIGHT", 8, 0)
        row.responseText:SetText("(" .. entry.response .. ")")
        row.prText:SetText(string.format("%.3f", entry.pr or 0))
        row.epText:SetText(string.format("%.0f", entry.ep or 0))
        row.awardBtn:SetScript("OnClick", function()
            SideQuest.Loot.AwardLoot(
                { item_id = UI.ParseItemId(bid.itemLink), item_name = info.name, quality = info.quality, inv_type = info.equipLoc },
                entry.character, entry.response)
            SideQuest.Loot.CloseBid()
            UI.RefreshBidRanking()
        end)
        row:Show()
    end
end

SideQuest.On("SQ_BID_OPENED", function(bid)
    UI.ShowTab(OFFICER_TAB)
    UI.ShowConsoleSub("Loot")
    UI.RefreshBidRanking(bid)
end)

-- Roster management sub-view: inactivity, rank suggestions, notes, main/alt
function UI.BuildConsoleRoster(panel)
    local sub = makeConsoleSub(panel, "Roster")
    local chamber = createChamber(sub, "SideQuestConsoleRosterChamber")
    chamber:SetAllPoints(sub)
    createRibbon(chamber, "Roster")

    local sweepBtn = createButton(chamber.inner, "primary", "Sweep roster", 140, 22)
    sweepBtn:SetPoint("TOPLEFT", 14, -30)
    sweepBtn:SetScript("OnClick", function()
        SideQuest.Roster.Sweep()
        UI.RefreshConsoleRoster()
    end)

    local scroll, content = buildScroll(chamber.inner, -58)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    panel.rosterChamber = chamber
end

function UI.RefreshConsoleRoster()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.rosterChamber then
        return
    end
    local chamber = panel.rosterChamber
    local inactive = SideQuestDB.officerData.inactive or {}
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if not SideQuest.Roster.IsAvailable() then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "Guild roster API unavailable here; use the site's roster page instead.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end
    local y = 0
    if not chamber.inactiveHeading then
        chamber.inactiveHeading = createSubHeading(chamber.content, "Inactive members")
        chamber.inactiveHeading:SetWidth(520)
    end
    chamber.inactiveHeading:ClearAllPoints()
    chamber.inactiveHeading:SetPoint("TOPLEFT", 0, -y)
    chamber.inactiveHeading.label:SetText(trackedCaps("Inactive members (" .. #inactive .. ")"))
    y = y + 20
    if #inactive == 0 then
        if not chamber.inactiveEmpty then
            chamber.inactiveEmpty = makeFontString(chamber.content, FONT_BODY, 11, C.mist2, "LEFT")
        end
        chamber.inactiveEmpty:ClearAllPoints()
        chamber.inactiveEmpty:SetPoint("TOPLEFT", 0, -y)
        setStateText(chamber.inactiveEmpty, "No inactivity flagged.", true)
        y = y + 20
    elseif chamber.inactiveEmpty then
        chamber.inactiveEmpty:SetText("")
    end
    for i, m in ipairs(inactive) do
        local row = chamber.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.content)
            row:SetSize(500, 20)
            row.text = makeFontString(row, FONT_BODY, 12, C.ink, "LEFT")
            row.text:SetPoint("LEFT")
            row.rankBtn = createButton(row, "quiet", "Suggest: demote", 130, 18)
            row.rankBtn:SetPoint("RIGHT")
            chamber.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.text:SetText(m.name .. " -- last seen " .. os.date("%Y-%m-%d", m.last_seen_at or 0)
            .. (m.last_raid_at and (", last raid " .. os.date("%Y-%m-%d", m.last_raid_at)) or ", never raided"))
        row.rankBtn:SetScript("OnClick", function()
            SideQuest.Recruits.AddNote(m.name, "Rank suggestion: demote for inactivity")
        end)
        row:Show()
        y = y + 22
    end
    sizeScrollThumb(chamber.scroll, y)
end

-- Recruits sub-view: applicants/trials, checklist, votes
function UI.BuildConsoleRecruits(panel)
    local sub = makeConsoleSub(panel, "Recruits")
    local chamber = createChamber(sub, "SideQuestConsoleRecruitsChamber")
    chamber:SetAllPoints(sub)
    createRibbon(chamber, "Recruits")

    local scroll, content = buildScroll(chamber.inner, -34)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    panel.recruitsChamber = chamber
end

function UI.RefreshConsoleRecruits()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.recruitsChamber then
        return
    end
    local chamber = panel.recruitsChamber
    local recruits = SideQuest.Recruits.List()
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if #recruits == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "No recruits yet.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end
    local CHECK_DEFS = {
        { key = "gear_check", label = "Gear" }, { key = "first_raid", label = "First raid" },
        { key = "vouched", label = "Vouched" }, { key = "talked", label = "Talked" },
    }
    for i, r in ipairs(recruits) do
        local row = chamber.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.content)
            row:SetSize(560, 54)
            row.nameRow = createNameRow(row, 13)
            row.nameRow:SetPoint("TOPLEFT")
            row.statusText = makeFontString(row, FONT_BODY, 11, C.mist, "LEFT")
            -- votes sit in the recruit's own row, next to their status --
            -- never pinned to the row's far edge, well clear of the name.
            row.yesBtn = createButton(row, "quiet", "Yes", 44, 18)
            row.noBtn = createButton(row, "quiet", "No", 44, 18)
            row.checks = {}
            for ci, def in ipairs(CHECK_DEFS) do
                local tick = row:CreateTexture(nil, "ARTWORK")
                tick:SetSize(10, 10)
                tick:SetPoint("TOPLEFT", row.nameRow, "BOTTOMLEFT", (ci - 1) * 90, -6)
                local label = makeFontString(row, FONT_BODY, 10, C.mist2, "LEFT")
                label:SetPoint("LEFT", tick, "RIGHT", 4, 0)
                label:SetText(def.label)
                row.checks[def.key] = { tick = tick, label = label }
            end
            row.votesText = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
            row.votesText:SetPoint("TOPLEFT", row.nameRow, "BOTTOMLEFT", 0, -22)
            chamber.rows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -58 * (i - 1))
        setNameRow(row.nameRow, r.character, r.class)
        row.statusText:ClearAllPoints()
        row.statusText:SetPoint("LEFT", row.nameRow, "RIGHT", 10, 0)
        row.statusText:SetText("(" .. (r.status or "applicant") .. ")")
        row.yesBtn:ClearAllPoints()
        row.yesBtn:SetPoint("LEFT", row.statusText, "RIGHT", 14, 0)
        row.noBtn:ClearAllPoints()
        row.noBtn:SetPoint("LEFT", row.yesBtn, "RIGHT", 6, 0)
        for key, ui in pairs(row.checks) do
            local checked = r.checklist and r.checklist[key]
            setColor(ui.tick, checked and C.gold or C.stone2)
        end
        local votes = {}
        for _, v in ipairs(r.votes or {}) do
            table.insert(votes, displayName(v.officer) .. ": " .. v.vote)
        end
        row.votesText:SetText(#votes > 0 and ("Votes: " .. table.concat(votes, ", ")) or "No votes yet.")
        row.yesBtn:SetScript("OnClick", function()
            SideQuest.Recruits.Vote(r.id, "yes")
            UI.RefreshConsoleRecruits()
        end)
        row.noBtn:SetScript("OnClick", function()
            SideQuest.Recruits.Vote(r.id, "no")
            UI.RefreshConsoleRecruits()
        end)
        row:Show()
    end
    sizeScrollThumb(chamber.scroll, 58 * #recruits)
end

-- Bank ledger sub-view
function UI.BuildConsoleBank(panel)
    local sub = makeConsoleSub(panel, "Bank")
    local chamber = createChamber(sub, "SideQuestConsoleBankChamber")
    chamber:SetAllPoints(sub)
    createRibbon(chamber, "Bank")

    local captureBtn = createButton(chamber.inner, "primary", "Capture open tab", 150, 22)
    captureBtn:SetPoint("TOPLEFT", 14, -30)
    captureBtn:SetScript("OnClick", function()
        SideQuest.Bank.CaptureOpenTab(1)
        UI.RefreshConsoleBank()
    end)

    local scroll, content = buildScroll(chamber.inner, -58)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    panel.bankChamber = chamber
end

function UI.RefreshConsoleBank()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.bankChamber then
        return
    end
    local chamber = panel.bankChamber
    local rows = SideQuestDB.pending.bank or {}
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if not SideQuest.Bank.IsAvailable() then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "Guild bank log API unavailable here; record deposits/withdrawals on the site.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end
    for i, b in ipairs(rows) do
        local row = chamber.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.content)
            row:SetSize(500, 18)
            row.text = makeFontString(row, FONT_BODY, 11, C.ink, "LEFT")
            row.text:SetPoint("LEFT")
            chamber.rows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -20 * (i - 1))
        row.text:SetText(b.kind .. "  " .. (b.item_name or "") .. " x" .. (b.count or 0) .. "  " .. displayName(b.character or ""))
        row:Show()
    end
    sizeScrollThumb(chamber.scroll, 20 * #rows)
end

-- Announce sub-view: compose -> toast + guild chat + queued for Discord,
-- plus a recent list of what's already gone out.
function UI.BuildConsoleAnnounce(panel)
    local sub = makeConsoleSub(panel, "Announce")
    local chamber = createChamber(sub, "SideQuestConsoleAnnounceChamber")
    chamber:SetAllPoints(sub)
    createRibbon(chamber, "Announce")

    local editBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    editBox:SetSize(400, 20)
    editBox:SetPoint("TOPLEFT", 14, -30)
    editBox:SetAutoFocus(false)
    skinEditBox(editBox, "Announcement text")

    local discordCheck = CreateFrame("CheckButton", nil, chamber.inner, "UICheckButtonTemplate")
    discordCheck:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -8)
    local discordLabel = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    discordLabel:SetPoint("LEFT", discordCheck, "RIGHT", 2, 0)
    discordLabel:SetText("Also post to Discord")

    local postBtn = createButton(chamber.inner, "primary", "Post", 100, 22)
    postBtn:SetPoint("TOPLEFT", discordCheck, "BOTTOMLEFT", 0, -10)
    postBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        if text and text ~= "" then
            SideQuest.Announce.Post(text, discordCheck:GetChecked())
            editBox:SetText("")
            UI.RefreshConsoleAnnounce()
        end
    end)

    local recentHeading = createSubHeading(chamber.inner, "Recently posted")
    recentHeading:SetPoint("TOPLEFT", postBtn, "BOTTOMLEFT", 0, -14)
    recentHeading:SetWidth(520)
    local recentList = CreateFrame("Frame", nil, chamber.inner)
    recentList:SetPoint("TOPLEFT", recentHeading, "BOTTOMLEFT", 0, -6)
    recentList:SetPoint("RIGHT", -14, 0)
    chamber.recentRows = {}
    chamber.recentHeading, chamber.recentList = recentHeading, recentList
    panel.announceChamber = chamber
    UI.RefreshConsoleAnnounce()
end

function UI.RefreshConsoleAnnounce()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.announceChamber then
        return
    end
    local chamber = panel.announceChamber
    local items = SideQuestDB.pending.announcements or {}
    for _, r in ipairs(chamber.recentRows) do r:Hide() end
    if #items == 0 then
        if not chamber.recentEmpty then
            chamber.recentEmpty = makeFontString(chamber.recentList, FONT_BODY, 11, C.mist2, "LEFT")
        end
        setStateText(chamber.recentEmpty, "Nothing posted this session yet.", true)
        return
    elseif chamber.recentEmpty then
        chamber.recentEmpty:SetText("")
    end
    local shown = math.min(#items, 5)
    for i = 1, shown do
        local item = items[#items - i + 1]
        local row = chamber.recentRows[i]
        if not row then
            row = makeFontString(chamber.recentList, FONT_BODY_ITALIC, 12, C.flavor, "LEFT")
            chamber.recentRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -18 * (i - 1))
        row:SetText("\"" .. item.text .. "\"  --  " .. os.date("%m/%d %H:%M", item.at or now())
            .. (item.discord and "  (Discord queued)" or ""))
        row:Show()
    end
end

-- Sync sub-view: export/import, last sync, pending counts per section
function UI.BuildConsoleSync(panel)
    local sub = makeConsoleSub(panel, "Sync")
    local chamber = createChamber(sub, "SideQuestConsoleSyncChamber")
    chamber:SetAllPoints(sub)
    createRibbon(chamber, "Sync")

    local lastSyncText = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    lastSyncText:SetPoint("TOPLEFT", 14, -30)
    chamber.lastSyncText = lastSyncText

    local exportBtn = createButton(chamber.inner, "primary", "Export", 120, 22)
    exportBtn:SetPoint("TOPLEFT", lastSyncText, "BOTTOMLEFT", 0, -10)
    exportBtn:SetScript("OnClick", function()
        SideQuest.Fire("SQ_SHOW_EXPORT", SideQuest.Sync.BuildExport())
    end)

    local importBtn = createButton(chamber.inner, "primary", "Import", 120, 22)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetScript("OnClick", function()
        SideQuest.Fire("SQ_SHOW_IMPORT")
    end)

    local editBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    editBox:SetSize(500, 20)
    editBox:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -10)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEnterPressed", function(self)
        SideQuest.Sync.ImportString(self:GetText())
        UI.RefreshConsoleSync()
    end)
    skinEditBox(editBox, "Paste import text")

    local pendingHeading = createSubHeading(chamber.inner, "Pending (not yet exported)")
    pendingHeading:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -14)
    pendingHeading:SetWidth(520)

    -- two labelled columns instead of one long "--"-joined line.
    local PENDING_KEYS = {
        { key = "sessions", label = "Sessions" }, { key = "encounters", label = "Encounters" },
        { key = "loot", label = "Loot" }, { key = "awards", label = "Awards" },
        { key = "professions", label = "Professions" }, { key = "signups", label = "Signups" },
        { key = "bank", label = "Bank" }, { key = "announcements", label = "Announcements" },
        { key = "recruits", label = "Recruits" }, { key = "member_notes", label = "Member notes" },
        { key = "roster", label = "Roster" },
    }
    chamber.pendingKeys = PENDING_KEYS
    local pendingGrid = CreateFrame("Frame", nil, chamber.inner)
    pendingGrid:SetPoint("TOPLEFT", pendingHeading, "BOTTOMLEFT", 0, -8)
    local gridRows = math.ceil(#PENDING_KEYS / 2)
    pendingGrid:SetSize(520, 16 * gridRows)
    chamber.pendingCells = {}
    local COLW = 230
    for i = 1, gridRows do
        for col = 1, 2 do
            local label = makeFontString(pendingGrid, FONT_BODY, 11, C.mist2, "LEFT")
            label:SetPoint("TOPLEFT", (col - 1) * COLW, -16 * (i - 1))
            local value = makeFontString(pendingGrid, FONT_BODY, 11, C.gold, "LEFT")
            value:SetPoint("LEFT", label, "RIGHT", 6, 0)
            table.insert(chamber.pendingCells, { label = label, value = value })
        end
    end
    chamber.pendingHeading, chamber.editBox = pendingHeading, editBox
    panel.syncChamber = chamber
end

function UI.RefreshConsoleSync()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.syncChamber then
        return
    end
    local chamber = panel.syncChamber
    local at = SideQuestDB.guild and SideQuestDB.guild.generated_at or 0
    if at > 0 then
        chamber.lastSyncText:SetText("Last sync: " .. os.date("%Y-%m-%d %H:%M", at))
    else
        setStateText(chamber.lastSyncText, "Never synced yet.", true)
    end
    local p = SideQuestDB.pending
    for i, def in ipairs(chamber.pendingKeys) do
        local cell = chamber.pendingCells[i]
        local count = def.key == "roster" and (p.roster and 1 or 0) or #(p[def.key] or {})
        cell.label:SetText(trackedCaps(def.label))
        cell.value:SetText(tostring(count))
    end
end

function UI.ShowExportBox(str)
    local chamber = UI.panels[OFFICER_TAB].syncChamber
    UI.ShowTab(OFFICER_TAB)
    UI.ShowConsoleSub("Sync")
    chamber.editBox:SetText(str)
    chamber.editBox:HighlightText()
    chamber.editBox:SetFocus()
end

function UI.ShowImportBox()
    local chamber = UI.panels[OFFICER_TAB].syncChamber
    UI.ShowTab(OFFICER_TAB)
    UI.ShowConsoleSub("Sync")
    chamber.editBox:SetText("")
    chamber.editBox:SetFocus()
end

--------------------------------------------------------------------------
-- Event wiring
--------------------------------------------------------------------------

SideQuest.On("SQ_PROMPT_RECORD", function()
    SideQuest.Print("You're in a raid instance. Use /sq or the Console's Raid Night step to start recording if you're officer of the night.")
end)

SideQuest.On("SQ_SHOW_EXPORT", function(str)
    UI.Show()
    UI.ShowExportBox(str)
end)

SideQuest.On("SQ_SHOW_IMPORT", function()
    UI.Show()
    UI.ShowImportBox()
end)

SideQuest.On("SQ_OPEN_MAIN_WINDOW", function()
    UI.Toggle()
end)

SideQuest.On("SQ_STANDINGS_UPDATED", function()
    if UI.activeTab == "You" then UI.RefreshYou() end
    if UI.activeTab == "Ledger" then UI.RefreshLedger() end
end)

SideQuest.On("SQ_IMPORT_APPLIED", function()
    UI.RefreshOfficerVisibility()
    UI.RefreshFreshness()
end)

SideQuest.On("SQ_GUILD_UPDATED", function()
    if UI.activeTab == "You" then UI.RefreshYou() end
    if UI.activeTab == "Guild" then UI.RefreshGuild() end
    UI.RefreshFreshness()
end)

SideQuest.On("SQ_NEWS_UPDATED", function()
    if UI.activeTab == "You" then UI.RefreshYou() end
    if UI.activeTab == "News" then UI.RefreshNews() end
end)

SideQuest.On("SQ_CRAFT_ANSWER", function()
    if UI.activeTab == "Crafters" then UI.RefreshCrafters() end
end)

SideQuest.On("SQ_SHEET_ANSWERED", function()
    local chamber = UI.panels and UI.panels.Ledger and UI.panels.Ledger.chamber
    if chamber then
        chamber.sheetState = "answered"
    end
    if UI.activeTab == "You" then UI.RefreshYou() end
    if UI.activeTab == "Ledger" then UI.RefreshLedger() end
end)

SideQuest.On("SQ_RECRUIT_SAVED", function()
    if UI.activeTab == OFFICER_TAB then UI.RefreshConsoleRecruits() end
end)

SideQuest.On("SQ_PREP_ANSWER", function() end) -- surfaced via the Raid Night step buttons' tooltips in-game

return UI
