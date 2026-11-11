-- SideQuest/UI/Main.lua
-- The Guild Sheet: one movable, resizable window that opens on YOU (not a
-- roster grid), with bottom tabs for Guild, Crafters, Events, Ledger, News
-- and (officers) Console. Visual authority: sidequest-guild/website/DESIGN.md
-- (night blue, chamfered chamber framing, ribbon headings, class/quality
-- colours paired with text, no unicode icons, no eyebrow labels), carried
-- in Forever's own chamfered Camelot window chrome (UI/Skin.lua).
-- See .impeccable/surfaces/sidequest-ui-main-lua.md for the direction contract.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
local UI = SideQuest.UI

if not CreateFrame then
    return UI -- headless (no Blizzard UI environment); nothing to build
end

--------------------------------------------------------------------------
-- Visual chrome lives in UI/Skin.lua (loads first, see SideQuest.toc):
-- colors, fonts, the chamfered chamber/ribbon/button/field-well/scroll/tab
-- builders, the native window chrome and the motion helpers. Main.lua
-- only adds the app-domain vocabulary on top of it (class/quality/role
-- colors, the news icon map, item resolution) -- never a second copy of
-- any chrome primitive.
--------------------------------------------------------------------------

local C = UI.Colors
local setColor = UI.SetColor
local makeFontString = UI.MakeFontString
local shade = UI.Shade
local hairline = UI.Hairline
local trackedCaps = UI.TrackedCaps
local MEDIA_TEX = UI.MediaTex
local FONT_DISPLAY, FONT_BODY, FONT_BODY_ITALIC = UI.FontDisplay, UI.FontBody, UI.FontBodyItalic
local createButton = UI.CreateButton
local skinEditBox = UI.SkinEditBox
local createLinkBox = UI.CreateLinkBox
local createCheckbox = UI.CreateCheckbox
local createChamber = UI.CreateChamber
local createRibbon = UI.CreateRibbon
local createSubHeading = UI.CreateSubHeading
local buildScroll = UI.BuildScroll
local setScrollContentHeight = UI.SetScrollContentHeight

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

-- Directory view fallbacks, used only while SideQuest.Data (Data.lua) has
-- not yet populated its tables: a static profession name list (so the
-- Crafters > Professions picker always has something to cycle through)
-- and one placeholder craft cooldown so the Cooldowns view has a shape to
-- show before Data.COOLDOWNS exists. Real data always wins when present.
local PROFESSION_FALLBACK = {
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Inscription", "Jewelcrafting", "Leatherworking", "Mining", "Skinning",
    "Tailoring", "Cooking", "Fishing", "First Aid",
}
local COOLDOWN_FALLBACK = {
    { key = "transmute", label = "Transmute", profession = "Alchemy" },
    { key = "mooncloth", label = "Mooncloth", profession = "Tailoring" },
}
local STANDING_WORD = {
    [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral",
    [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted",
}

-- The five directory sections settings.share toggles, in docs/directory
-- .md's table order, each with the one plain sentence the Sharing
-- checklist shows next to it.
local SHARE_SECTIONS = {
    { key = "prof", label = "Professions", sentence = "Shares your professions, skill levels and known recipes." },
    { key = "char", label = "Character", sentence = "Shares your level, spec, item level, attunements and tracked reputations." },
    { key = "cd", label = "Cooldowns", sentence = "Shares your craft cooldowns and when each is ready." },
    { key = "market", label = "Market", sentence = "Shares what you sell, your standing buy offers and your requests." },
    { key = "stock", label = "Stock", sentence = "Shares the crafting materials you hold in bags and bank." },
}

-- Imported class tokens may arrive lowercase from the site (contract v2
-- `members[].class`, `events[].signups[].role`'s sibling `class`); every
-- CLASS_COLOR/CLASS_WORD lookup goes through this so case never hides the
-- colour, in or out of game.
local function classKey(className)
    if type(issecretvalue) == "function" and issecretvalue(className) then
        return nil
    end
    return className and className:upper() or nil
end

-- News item "kind" -> a game atlas/texture icon + a fallback swatch color
-- (the shipped texture is a Blizzard file path the preview renderer can't
-- fetch; the swatch keeps every kind visually distinct there too). Never
-- the unicode "!"/"?" glyphs DESIGN.md's quest-log uses for events -- those
-- are reserved for open/closed sign-ups, not news kinds.
-- Game atlases per news kind (Forever art). Loot shows the item's own icon in
-- a quality-tinted frame instead, see setNewsIcon.
local NEWS_ICON = {
    boss_kill = "DungeonSkull",
    first_kill = "VignetteKillElite",
    announcement = "communities-icon-notification",
    level = "LevelUp-Dot-Gold",
    joined = "socialqueuing-icon-group",
    badge = "UI-Achievement-Shield-1",
}
local LOOT_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Bag_08"
local NEWS_KIND_WORD = {
    boss_kill = "Boss kill", first_kill = "First kill", loot = "Loot", announcement = "Announcement",
    level = "Level up", joined = "Joined", badge = "Badge",
}
--- Site EventKind -> display label (events.py EVENT_KIND_LABELS), shown next
-- to each event's date/time on the Events tab.
local EVENT_KIND_LABELS = {
    raid = "Raid", dungeon = "Dungeon", world_boss = "World Boss", leveling = "Leveling",
    pvp = "PvP", social = "Social", transmog = "Transmog", other = "Other",
}
-- Site ROLE_KINDS (events.py): only these events carry tank/healer/dps sign-ups and can be
-- raid-invited or placed into groups; the rest take a bare going/maybe/can't RSVP.
local ROLE_KINDS = { raid = true, dungeon = true, world_boss = true }

local WINDOW_MIN_W, WINDOW_MIN_H = 700, 480
local WINDOW_DEFAULT_W, WINDOW_DEFAULT_H = 860, 560
-- The layout is drawn in 860x560 units with 10-13 pt Garamond, which reads
-- small next to the game's own Friz Quadrata windows; 1.25 brings it to the
-- size of Blizzard and big addon option windows. /sq scale changes it.
local WINDOW_DEFAULT_SCALE, WINDOW_SCALE_MIN, WINDOW_SCALE_MAX = 1.25, 0.75, 2
-- room for the tab row hanging below the frame and the crest above it
local WINDOW_OVERHANG_H = 50

-- Non-member join window (contract: website/Discord links, how to join).
local JOIN_W, JOIN_H = 480, 420
local WEBSITE_URL = "https://sidequest-guild.com/"
local DISCORD_URL = "https://discord.gg/nwncP7H9Hh"

-- View as (GM-only UI preview, Core.lua SQ.SetViewAs/ViewAs): display label
-- per role, and the role the "View as" buttons cycle through.
local VIEW_AS_LABEL = { nonmember = "Non-member", member = "Member", officer = "Officer" }
local VIEW_AS_ROLES = { "nonmember", "member", "officer" }

local TABS = { "You", "Guild", "Crafters", "Market", "Raids", "Ledger", "News" }
-- Internal tab keys (and SideQuestDB.ui.tab's saved value) stay as-is;
-- TAB_LABELS only changes what's drawn on the tab button.
local TAB_LABELS = { Raids = "Events" }
local OFFICER_TAB = "Console"
-- "Debug" is appended to every sub-tab list/button but shown only for the
-- Guild Master (UI.RefreshOfficerVisibility); see UI.BuildConsoleDebug.
local CONSOLE_SUBTABS = { "Raid Night", "Loot", "Roster", "Recruits", "Bank", "Announce", "Sync", "Debug" }
local CRAFTERS_SUBTABS = { "Search", "Professions", "Cooldowns" }
local MARKET_SUBTABS = { "Browse", "Mine" }

local function now()
    return GetServerTime and GetServerTime() or 0
end

--- "First-Surname" -> "First Surname" on Forever (CHARACTERNAME_SURNAME_SEPARATOR
-- is a space, not a realm separator -- Forever has no realms); elsewhere
-- "Name-Realm" -> "Name" when the realm matches the player's own
-- (DESIGN.md/finding: realm only shown when it differs from yours). Falls
-- back to the full string when there's no "-" to split.
local function displayName(character)
    if not character then
        return ""
    end
    -- Roster.lua already guards GetGuildRosterInfo's name through
    -- SideQuest.Unsecret before it reaches SavedVariables, but this stays
    -- defensive so an unreadable character never breaks the %- pattern
    -- match below or blanks the row silently -- it says so instead
    -- (PRODUCT.md principle 3).
    if type(issecretvalue) == "function" and issecretvalue(character) then
        return "Unknown"
    end
    if SideQuest.IsForever and SideQuest.IsForever() then
        -- The canonical key IS the link form (CHARACTERNAME_LINK_SEPARATOR
        -- = "-"); showing it as typed (CHARACTERNAME_SURNAME_SEPARATOR =
        -- " ") matches how every other Forever UI displays character names.
        local first, surname = character:match("^(.-)%-(.+)$")
        if first then
            return first .. " " .. surname
        end
        return character
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

--- The item ID typed or shift-clicked into an item box: an ID, a link or a
-- name the client knows.
local function parseItemInput(box)
    local text = box:GetText()
    if SideQuest.Market and SideQuest.Market.ParseItemArg then
        return SideQuest.Market.ParseItemArg(text)
    end
    return parseItemId(text)
end

-- Shift-clicking an item while one of these boxes has focus puts its link in
-- the box, the way the chat box takes links.
local itemLinkBoxes = {}
local function acceptItemLinks(box)
    table.insert(itemLinkBoxes, box)
end
-- Forever has no ChatEdit_InsertLink global; ChatFrameUtil.InsertLink is the
-- Mainline 12.x function HandleModifiedItemClick calls.
local function onInsertLink(link)
    for _, box in ipairs(itemLinkBoxes) do
        if box:IsVisible() and box:HasFocus() then
            box:SetText(link)
            return
        end
    end
end
if hooksecurefunc and ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink)
elseif hooksecurefunc and ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", onInsertLink)
end

--- Escape closes the window (classic WoW special-frame pattern). Only insert into UISpecialFrames: assigning
-- the global itself (even `UISpecialFrames = UISpecialFrames or {}`) taints it, and Blizzard reads it on every
-- Escape press.
local function closeOnEscape(frameName)
    if UISpecialFrames then
        table.insert(UISpecialFrames, frameName)
    end
end

--- Enter in a search field lets go of the keyboard (InputBoxTemplate only
-- does that on Escape) and, given its button, presses it.
local function submitOnEnter(box, btn)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if btn then
            btn:Click()
        end
    end)
end

--- Resolve an item link to its name/quality/icon/slot word/GP cost. Shared
-- by the raider-facing bid popup and the officer console's Loot sub-view,
-- so item resolution (and its "unknown until identified" fallback) lives
-- in exactly one place.
local function resolveItemInfo(itemLink)
    local itemId = parseItemId(itemLink)
    local name, quality, equipLoc, icon
    if itemId then
        local n, _, q, _, _, _, _, _, eq, ic = SideQuest.GetItemInfo(itemId)
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

--- One quest-log row: a gold "!" for something open/pending, a dim "?"
-- once it's done, title + a mist meta line. Never color-only: every state
-- also changes the mark glyph and/or adds text.
local function createQuestLogRow(parent)
    local row = CreateFrame("Button", nil, parent)
    -- width and height both: a row with only a height has no valid rect,
    -- and the game then draws nothing anchored to it
    row:SetSize(520, 32)
    -- the game's own quest marks: "!" while sign-ups are open, "?" once closed
    local mark = row:CreateTexture(nil, "ARTWORK")
    mark:SetSize(16, 16)
    mark:SetPoint("LEFT", 2, 0)
    local title = makeFontString(row, FONT_BODY, 14, C.ink, "LEFT")
    title:SetPoint("LEFT", mark, "RIGHT", 8, 6)
    local meta = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    row.mark, row.title, row.meta = mark, title, meta
    return row
end

--- A news row: the kind's icon, then the line and its meta.
local function createNewsRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(520, 32)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 3, 0)
    local frame = row:CreateTexture(nil, "OVERLAY")
    frame:SetSize(24, 24)
    frame:SetPoint("CENTER", icon, "CENTER")
    frame:SetTexture(MEDIA_TEX .. "IconFrame")
    local title = makeFontString(row, FONT_BODY, 13, C.ink, "LEFT")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 6)
    local meta = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    row.icon, row.frame, row.title, row.meta = icon, frame, title, meta
    return row
end

--- Fill a news row's icon for `item` (News.Get()/GuildNow shape: kind, and
-- for loot item_id and quality).
local function setNewsIcon(row, item)
    if item.kind == "loot" then
        local tex = item.item_id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.item_id)
        row.icon:SetTexture(tex or LOOT_ICON_FALLBACK)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local q = QUALITY_COLOR[item.quality or 1] or QUALITY_COLOR[1]
        row.frame:SetVertexColor(q[1], q[2], q[3], 1)
        row.frame:Show()
    else
        row.icon:SetAtlas(NEWS_ICON[item.kind] or NEWS_ICON.announcement)
        row.frame:Hide()
    end
end

--- Day header for news/quest-log lists ("grouped by day" per finding #9):
-- reuses the sub-heading treatment so there is no second heading style.
local function dayLabel(ts)
    local d = now() - (ts or now())
    if d < 20 * 3600 and date("%j", ts) == date("%j", now()) then
        return "Today"
    elseif date("%j", ts) == date("%j", now() - 86400) then
        return "Yesterday"
    end
    return date("%A, %b %d", ts)
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
-- Directory helpers: relative time, craft-cooldown countdowns, money,
-- fallback labels and the newest "at" across a stored record's sections
-- (its freshness). Shared by Crafters, Market, Guild-detail and Tooltip.
--------------------------------------------------------------------------

--- "Xh ago" / "Xd ago" / "just now" / "never", for a server-time timestamp.
local function ago(ts)
    if not ts or ts <= 0 then
        return "never"
    end
    local ageSeconds = math.max(0, now() - ts)
    local hours = math.floor(ageSeconds / 3600)
    if hours < 1 then
        return "just now"
    elseif hours < 48 then
        return hours .. "h ago"
    end
    return math.floor(hours / 24) .. "d ago"
end

--- "Ready now" / "Ready in Xm" / "Ready in Xh" / "Ready in Xd" for a craft
-- cooldown's ready_at (0 or past means ready now, per docs/directory.md).
local function readyWord(readyAt)
    if not readyAt or readyAt <= now() then
        return "Ready now"
    end
    local secs = readyAt - now()
    local hours = math.floor(secs / 3600)
    if hours < 1 then
        return "Ready in " .. math.max(1, math.floor(secs / 60)) .. "m"
    elseif hours < 48 then
        return "Ready in " .. hours .. "h"
    end
    return "Ready in " .. math.floor(hours / 24) .. "d"
end

--- Copper to "Ng Ns Nc" (docs/directory.md market prices are copper; nil
-- means "whisper me", per the same contract).
local function formatMoney(copper)
    if not copper then
        return "Whisper me"
    end
    copper = math.floor(copper + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100
    local parts = {}
    if gold > 0 then table.insert(parts, gold .. "g") end
    if silver > 0 or gold > 0 then table.insert(parts, silver .. "s") end
    table.insert(parts, cop .. "c")
    return table.concat(parts, " ")
end

--- Copper to display text: SideQuest.Market.FormatPrice once Market.lua
-- has it (the addon's one source of truth for money formatting), else
-- the local fallback above (headless tests/preview before it loads).
local function money(copper)
    if not copper then
        return "Whisper me"
    end
    if SideQuest.Market and SideQuest.Market.FormatPrice then
        return SideQuest.Market.FormatPrice(copper)
    end
    return formatMoney(copper)
end

--- " (AH 1g 20s)" for an item's guild auction-house price (Market
-- .AuctionPrice, from the last game import), or "" when none is known.
local function ahSuffix(itemId)
    local price = SideQuest.Market and SideQuest.Market.AuctionPrice and SideQuest.Market.AuctionPrice(itemId)
    if not price then
        return ""
    end
    return " (AH " .. money(price.p) .. ")"
end

--- Free-text price ("1g20s", "50s", "3g") to copper, or nil: SideQuest
-- .Market.ParsePrice once Market.lua has it, else a plain gold-number
-- fallback so the editor still works in the meantime.
local function parsePrice(text)
    if not text or text == "" then
        return nil
    end
    if SideQuest.Market and SideQuest.Market.ParsePrice then
        return SideQuest.Market.ParsePrice(text)
    end
    local gold = tonumber(text)
    return gold and math.floor(gold * 10000 + 0.5) or nil
end

--- Caps a request note's display length (the contract allows up to 80
-- chars, which would otherwise run under the row's Whisper/Remove button).
local function truncateNote(note, max)
    max = max or 40
    if not note or #note <= max then
        return note
    end
    return note:sub(1, max - 1) .. "..."
end

--- Title-cases a snake/kebab key into a readable label, for attunement or
-- cooldown keys SideQuest.Data hasn't labelled yet.
local function labelFromKey(key)
    if not key then
        return ""
    end
    local words = {}
    for w in tostring(key):gmatch("[^_%-]+") do
        table.insert(words, w:sub(1, 1):upper() .. w:sub(2))
    end
    return table.concat(words, " ")
end

-- Section keys in storage order, per docs/directory.md's "Where it lives".
local DIRECTORY_SECTIONS = { "prof", "char", "cd", "market", "stock" }

--- The newest `at` across a stored directory entry's sections (how fresh
-- that member's record is), falling back to `seen_at`; nil when nothing
-- has ever been heard about them.
local function recordFreshness(entry)
    if not entry then
        return nil
    end
    local newest
    for _, key in ipairs(DIRECTORY_SECTIONS) do
        local sec = entry[key]
        if sec and sec.at and (not newest or sec.at > newest) then
            newest = sec.at
        end
    end
    return newest or entry.seen_at
end

--- Profession names to cycle through: SideQuest.Data.PROFESSIONS once
-- Data.lua has it, else the static fallback (see PROFESSION_FALLBACK).
local function professionNames()
    local data = SideQuest.Data and SideQuest.Data.PROFESSIONS
    if data and #data > 0 then
        local names = {}
        for _, p in ipairs(data) do
            if p.name then
                table.insert(names, p.name)
            end
        end
        if #names > 0 then
            return names
        end
    end
    return PROFESSION_FALLBACK
end

--- Craft cooldown definitions ({key, label, profession}), label-sorted:
-- SideQuest.Data.COOLDOWNS (a dict keyed by cooldown key) once Data.lua
-- has it, else the static fallback.
local function cooldownDefs()
    local data = SideQuest.Data and SideQuest.Data.COOLDOWNS
    if data and next(data) then
        local out = {}
        for key, def in pairs(data) do
            table.insert(out, { key = key, label = def.label, profession = def.profession })
        end
        table.sort(out, function(a, b) return (a.label or a.key) < (b.label or b.key) end)
        return out
    end
    return COOLDOWN_FALLBACK
end

--- An attunement key's label: SideQuest.Data.ATTUNEMENTS (a dict keyed by
-- attunement key) once Data.lua has it, else the key itself, title-cased.
local function attunementLabel(key)
    local data = SideQuest.Data and SideQuest.Data.ATTUNEMENTS
    local def = data and data[key]
    if def and def.label then
        return def.label
    end
    return labelFromKey(key)
end

--- A faction's display label: the live client data when the faction is
-- known there, else SideQuest.Data.REPUTATIONS's own label, else the ID.
local function reputationLabel(factionId)
    local info = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionId)
    if info and info.name then
        return info.name
    end
    local data = SideQuest.Data and SideQuest.Data.REPUTATIONS
    if data then
        for _, r in ipairs(data) do
            if r.faction_id == factionId and r.label then
                return r.label
            end
        end
    end
    return "Faction " .. tostring(factionId)
end

--------------------------------------------------------------------------
-- Exports for sibling UI files (BidPopup.lua): the app-domain vocabulary.
-- Chrome primitives (colors, fonts, chamber/ribbon/button/...) are
-- already exported by UI/Skin.lua.
--------------------------------------------------------------------------

UI.RoleColor, UI.RoleWord = ROLE_COLOR, ROLE_WORD
UI.ClassColor, UI.ClassWord, UI.QualityColor = CLASS_COLOR, CLASS_WORD, QUALITY_COLOR
UI.ClassKey = classKey
UI.CreateQuestLogRow = createQuestLogRow
UI.SetStateText = setStateText
UI.ClassText = classText
UI.CreateNameRow = createNameRow
UI.SetNameRow = setNameRow
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

--- The "previewing as <role>" bar with a "Back to my view" button, shown
-- only while SideQuest.ViewAs() is set. It sits inside the window (a bar
-- above the window's edge ends up off screen when the window is near the
-- top, and the window is clamped to the screen, not the bar). Both the main
-- and join windows get one, and closing either window also ends the
-- preview (endViewAsOnHide), so the GM can never get stuck.
local function createViewAsBanner(ownerFrame)
    local banner = CreateFrame("Frame", nil, ownerFrame)
    banner:SetSize(420, 28)
    banner:SetFrameLevel(ownerFrame:GetFrameLevel() + 20)
    local bg = banner:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(banner)
    bg:SetColorTexture(0.30, 0.19, 0.04, 0.95)
    local label = makeFontString(banner, FONT_BODY, 12, C.ink, "LEFT")
    label:SetPoint("LEFT", 10, 0)
    shade(label)
    local exitBtn = createButton(banner, "primary", "Back to my view", 130, 20)
    exitBtn:SetPoint("RIGHT", -4, 0)
    exitBtn:SetScript("OnClick", function()
        SideQuest.SetViewAs(nil)
    end)
    banner.label, banner.exitBtn = label, exitBtn
    banner:Hide()
    return banner
end

--- Closing a window while previewing ends the preview. UI.RefreshViewAs
-- hides and reopens the windows itself, so it sets UI.rebuildingViewAs.
local function endViewAsOnHide(frame)
    frame:HookScript("OnHide", function()
        if not UI.rebuildingViewAs and SideQuest.ViewAs() then
            SideQuest.SetViewAs(nil)
            SideQuest.Print("Back to your own view.")
        end
    end)
end

function UI.BuildMainFrame()
    if UI.main then
        return UI.main
    end

    local main = CreateFrame("Frame", "SideQuestMainFrame", UIParent, "BackdropTemplate")
    main:SetSize(SideQuestDB.ui.width or WINDOW_DEFAULT_W, SideQuestDB.ui.height or WINDOW_DEFAULT_H)
    -- Above the world-facing HUD (quest/waypoint arrows and their labels
    -- live at MEDIUM and would otherwise draw over and between the
    -- chambers); toplevel so it rises over other panels when clicked.
    main:SetFrameStrata("HIGH")
    main:SetToplevel(true)
    -- a bigger scale or a smaller screen never leaves it half off-screen
    main:SetClampedToScreen(true)
    local pos = SideQuestDB.ui.pos
    if pos then
        main:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        main:SetPoint("CENTER")
    end
    UI.ApplyWindowScale(main)
    -- Night ground under the native title band (PortraitFrameTemplate's Bg
    -- runs from (2, -21) to (-2, 2)).
    local fill = main:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", 2, -UI.WINDOW_TITLE_H)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    setColor(fill, C.night)

    -- Forever's own chrome: the gilded, chamfered Camelot portrait frame with
    -- the guild crest in its ring, the title in its band, its close button.
    local closeBtn = UI.ApplyWindowChrome(main, "SideQuest")
    closeBtn:SetScript("OnClick", function()
        main:Hide()
    end)

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

    closeOnEscape("SideQuestMainFrame")

    local resizeGrip = CreateFrame("Button", nil, main)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeGrip:SetScript("OnMouseDown", function()
        main:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        main:StopMovingOrSizing()
        saveGeometry()
    end)

    --------------------------------------------------------------
    -- The Great Hall painting under the title band, fading into night at
    -- its foot; the crest's ring overlaps its top-left corner the way a
    -- character portrait overlaps a native window. The freshness line sits
    -- on its own scrim at the right.
    --------------------------------------------------------------
    local header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT", 2, -UI.WINDOW_TITLE_H)
    header:SetPoint("TOPRIGHT", -2, -UI.WINDOW_TITLE_H)
    header:SetHeight(78)
    local strip = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    strip:SetAllPoints(header)
    strip:SetTexture(MEDIA_TEX .. "HeaderStrip")
    local foot = header:CreateTexture(nil, "BACKGROUND", nil, 2)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(30)
    foot:SetColorTexture(1, 1, 1, 1)
    foot:SetGradient("VERTICAL", CreateColor(C.night[1], C.night[2], C.night[3], 1),
        CreateColor(C.night[1], C.night[2], C.night[3], 0))

    local freshScrim = header:CreateTexture(nil, "ARTWORK")
    freshScrim:SetSize(200, 20)
    freshScrim:SetPoint("BOTTOMRIGHT", -6, 10)
    freshScrim:SetColorTexture(1, 1, 1, 1)
    freshScrim:SetGradient("HORIZONTAL", CreateColor(C.night[1], C.night[2], C.night[3], 0),
        CreateColor(C.night[1], C.night[2], C.night[3], 0.85))
    local freshness = makeFontString(header, FONT_BODY_ITALIC, 12, C.mist, "RIGHT")
    freshness:SetPoint("RIGHT", freshScrim, "RIGHT", -8, 0)
    shade(freshness)
    main.freshness = freshness

    --------------------------------------------------------------
    -- Body: everything between the painting and the frame's foot. The tab
    -- row hangs below the window like the Character frame's.
    --------------------------------------------------------------
    local body = CreateFrame("Frame", nil, main)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 6, 0)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -6, 0)
    body:SetPoint("BOTTOM", main, "BOTTOM", 0, 8)
    main.body = body

    UI.main = main
    UI.panels = {}
    UI.tabButtons = {}

    local allTabs = {}
    for _, t in ipairs(TABS) do
        table.insert(allTabs, t)
    end
    table.insert(allTabs, OFFICER_TAB)

    -- PanelTabButtonTemplate placement: the first tab at (11, 2) under the
    -- frame's bottom-left, each next one 3 to the right of the last.
    local prev
    for _, tabName in ipairs(allTabs) do
        local btn = UI.CreatePanelTab(main, TAB_LABELS[tabName] or tabName, false, tabName == OFFICER_TAB)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        else
            btn:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 11, 2)
        end
        prev = btn
        UI.SetPanelTabSelected(btn, false)
        btn:SetScript("OnClick", function()
            UI.ShowTab(tabName)
        end)
        if tabName == OFFICER_TAB then
            btn:Hide() -- shown only for officers, see UI.RefreshOfficerVisibility
        end
        UI.tabButtons[tabName] = btn
    end

    UI.BuildYouPanel(body)
    UI.BuildGuildPanel(body)
    UI.BuildCraftersPanel(body)
    UI.BuildMarketPanel(body)
    UI.BuildRaidsPanel(body)
    UI.BuildLedgerPanel(body)
    UI.BuildNewsPanel(body)
    UI.BuildConsolePanel(body)

    main.viewAsBanner = createViewAsBanner(main)
    main.viewAsBanner:SetPoint("TOP", header, "TOP", 0, -8)
    endViewAsOnHide(main)

    UI.RefreshOfficerVisibility()
    UI.RefreshFreshness()

    return main
end

--------------------------------------------------------------------------
-- Non-member join window: what SideQuest is + how to join, shown instead
-- of the tabbed window for a player who installed the addon but isn't
-- (yet) in the guild. Same chrome/chamber/ribbon vocabulary as the main
-- window, just a single pane -- see SideQuest.IsGuildMember (Core.lua).
--------------------------------------------------------------------------

function UI.BuildJoinFrame()
    if UI.joinFrame then
        return UI.joinFrame
    end

    local frame = CreateFrame("Frame", "SideQuestJoinFrame", UIParent, "BackdropTemplate")
    frame:SetSize(JOIN_W, JOIN_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetPoint("CENTER")
    UI.ApplyWindowScale(frame)

    local fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", 2, -UI.WINDOW_TITLE_H)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    setColor(fill, C.night)

    local closeBtn = UI.ApplyWindowChrome(frame, "SideQuest")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    closeOnEscape("SideQuestJoinFrame")

    local chamber = createChamber(frame, "SideQuestJoinChamber")
    chamber:SetPoint("TOPLEFT", 14, -(UI.WINDOW_TITLE_H + 14))
    chamber:SetPoint("BOTTOMRIGHT", -14, 14)
    createRibbon(chamber, "Join SideQuest")

    local contentW = JOIN_W - 2 * 14 - 2 * 8

    -- Two short lines rather than one long wrapped paragraph: the preview
    -- renderer (tests/preview/record.lua) doesn't simulate word-wrap, so a
    -- long single-line FontString would read fine in game but overflow the
    -- chamber on screen there.
    local intro1 = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    intro1:SetPoint("TOPLEFT", 0, -30)
    intro1:SetText("SideQuest is a guild on WoW: Forever (Alliance, Normal).")

    local intro2 = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    intro2:SetPoint("TOPLEFT", intro1, "BOTTOMLEFT", 0, -3)
    intro2:SetText("This addon runs our loot points, events and directory,")

    local intro3 = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    intro3:SetPoint("TOPLEFT", intro2, "BOTTOMLEFT", 0, -3)
    intro3:SetText("and opens up once you're a member.")

    local howHeading = createSubHeading(chamber.inner, "How to join")
    howHeading:SetPoint("TOPLEFT", intro3, "BOTTOMLEFT", 0, -20)
    howHeading:SetWidth(contentW)

    local howText1 = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    howText1:SetPoint("TOPLEFT", howHeading, "BOTTOMLEFT", 0, -10)
    howText1:SetText("Join the Discord and ask for an invite, or whisper")

    local howText2 = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    howText2:SetPoint("TOPLEFT", howText1, "BOTTOMLEFT", 0, -3)
    howText2:SetText("an officer in game -- officers are listed on the site.")

    local websiteLabel = makeFontString(chamber.inner, FONT_DISPLAY, 11, C.gold, "LEFT")
    websiteLabel:SetPoint("TOPLEFT", howText2, "BOTTOMLEFT", 0, -20)
    websiteLabel:SetText(trackedCaps("Website"))

    local websiteBox = createLinkBox(chamber.inner, WEBSITE_URL)
    websiteBox:SetSize(contentW, 20)
    websiteBox:SetPoint("TOPLEFT", websiteLabel, "BOTTOMLEFT", 0, -4)

    local websiteHint = makeFontString(chamber.inner, FONT_BODY_ITALIC, 10, C.mist2, "LEFT")
    websiteHint:SetPoint("TOPLEFT", websiteBox, "BOTTOMLEFT", 0, -3)
    websiteHint:SetText("Click to select, Ctrl+C to copy")

    local discordLabel = makeFontString(chamber.inner, FONT_DISPLAY, 11, C.gold, "LEFT")
    discordLabel:SetPoint("TOPLEFT", websiteHint, "BOTTOMLEFT", 0, -16)
    discordLabel:SetText(trackedCaps("Discord"))

    local discordBox = createLinkBox(chamber.inner, DISCORD_URL)
    discordBox:SetSize(contentW, 20)
    discordBox:SetPoint("TOPLEFT", discordLabel, "BOTTOMLEFT", 0, -4)

    local discordHint = makeFontString(chamber.inner, FONT_BODY_ITALIC, 10, C.mist2, "LEFT")
    discordHint:SetPoint("TOPLEFT", discordBox, "BOTTOMLEFT", 0, -3)
    discordHint:SetText("Click to select, Ctrl+C to copy")

    frame.intro, frame.howText = intro1, howText1
    frame.websiteBox, frame.discordBox = websiteBox, discordBox
    frame.websiteHint, frame.discordHint = websiteHint, discordHint
    frame.viewAsBanner = createViewAsBanner(frame)
    frame.viewAsBanner:SetPoint("BOTTOM", chamber, "BOTTOM", 0, 10)
    frame.viewAsBanner:SetWidth(contentW)
    endViewAsOnHide(frame)

    UI.joinFrame = frame
    return frame
end

--- Opens the non-member join window in place of the tabbed one. Never
-- opens or flashes in combat, same as UI.Show.
function UI.ShowJoin()
    SideQuest.WhenOutOfCombat(function()
        local frame = UI.BuildJoinFrame()
        frame:Show()
        UI.PlayOpenAnim(frame)
    end)
end

--------------------------------------------------------------------------
-- Whisper box: SideQuest's own one-line whisper, so the Whisper buttons
-- never touch the game's chat box (see SideQuest.Whisper in Core.lua).
-- Replies arrive in chat as usual.
--------------------------------------------------------------------------

function UI.BuildWhisperFrame()
    if UI.whisperFrame then
        return UI.whisperFrame
    end
    local frame = createChamber(UIParent, "SideQuestWhisperFrame")
    frame:SetSize(380, 112)
    -- over the main window (HIGH)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetPoint("CENTER", 0, 120)
    UI.ApplyWindowScale(frame)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    closeOnEscape("SideQuestWhisperFrame")
    createRibbon(frame, "Whisper")

    local inner = frame.inner
    local title = makeFontString(inner, FONT_BODY, 13, C.ink, "LEFT")
    title:SetPoint("TOPLEFT", 6, -28)

    local box = CreateFrame("EditBox", nil, inner, "InputBoxTemplate")
    box:SetSize(250, 20)
    box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 6, -8)
    box:SetAutoFocus(false)
    box:SetMaxLetters(255)
    skinEditBox(box, "Message")

    local sendBtn = createButton(inner, "primary", "Send", 70, 22)
    sendBtn:SetPoint("LEFT", box, "RIGHT", 10, 0)

    local hint = makeFontString(inner, FONT_BODY_ITALIC, 10, C.mist2, "LEFT")
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -6)
    hint:SetText("Enter sends, Esc closes. Replies show in chat.")

    local function send()
        if SideQuest.SendWhisper(frame.target, box:GetText()) then
            box:SetText("")
            frame:Hide()
        end
    end
    sendBtn:SetScript("OnClick", send)
    box:SetScript("OnEnterPressed", send)
    box:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)

    frame.title, frame.box, frame.sendBtn = title, box, sendBtn
    UI.whisperFrame = frame
    return frame
end

--- Not a protected frame, so it opens in combat too.
function UI.OpenWhisper(target)
    local frame = UI.BuildWhisperFrame()
    frame.target = target
    frame.title:SetText(target)
    frame.box:SetText("")
    frame:Show()
    frame.box:SetFocus()
end

SideQuest.On("SQ_OPEN_WHISPER", UI.OpenWhisper)

function UI.RefreshOfficerVisibility()
    local btn = UI.tabButtons and UI.tabButtons[OFFICER_TAB]
    if not btn then
        return
    end
    if SideQuest.DisplayIsOfficer() then
        btn:Show()
    else
        btn:Hide()
        if UI.activeTab == OFFICER_TAB then
            UI.ShowTab("You")
        end
    end

    local consolePanel = UI.panels and UI.panels[OFFICER_TAB]
    local debugBtn = consolePanel and consolePanel.subButtons and consolePanel.subButtons["Debug"]
    if debugBtn then
        if SideQuest.DisplayIsGuildMaster() then
            debugBtn:Show()
        else
            debugBtn:Hide()
            if consolePanel.activeSub == "Debug" then
                UI.ShowConsoleSub("Raid Night")
            end
        end
    end
end

--- Shows/hides and labels the view-as banner on whichever windows exist.
function UI.UpdateViewAsBanner()
    local role = SideQuest.ViewAs and SideQuest.ViewAs()
    for _, frame in ipairs({ UI.main, UI.joinFrame }) do
        if frame and frame.viewAsBanner then
            if role then
                frame.viewAsBanner.label:SetText("Previewing as " .. (VIEW_AS_LABEL[role] or role))
                frame.viewAsBanner:Show()
            else
                frame.viewAsBanner:Hide()
            end
        end
    end
end

--- SQ_VIEW_AS_CHANGED: rebuild whichever window is open so it reflects the
-- new role (a non-member preview needs the join pane instead of the
-- tabbed window and vice versa), then restore the banner.
function UI.RefreshViewAs()
    local wasOpen = (UI.main and UI.main:IsShown()) or (UI.joinFrame and UI.joinFrame:IsShown())
    UI.rebuildingViewAs = true
    if UI.main then UI.main:Hide() end
    if UI.joinFrame then UI.joinFrame:Hide() end
    UI.rebuildingViewAs = false
    UI.RefreshOfficerVisibility()
    UI.UpdateViewAsBanner()
    if wasOpen then
        UI.Show()
        UI.UpdateViewAsBanner()
    end
end

function UI.RefreshFreshness()
    local main = UI.main
    if not main or not main.freshness then
        return
    end
    local at = SideQuestDB.guild and SideQuestDB.guild.generated_at or 0
    if at <= 0 then
        setStateText(main.freshness, "No site data yet -- ask an officer", true)
        return
    end
    local ageSeconds = math.max(0, now() - at)
    local hours = math.floor(ageSeconds / 3600)
    local text
    if hours < 1 then
        text = "Site data from just now"
    elseif hours < 48 then
        text = "Site data from " .. hours .. "h ago"
    else
        text = "Site data from " .. math.floor(hours / 24) .. "d ago"
    end
    setStateText(main.freshness, text, false)
end

function UI.ShowTab(tabName)
    for name, panel in pairs(UI.panels) do
        if name == tabName then
            panel:Show()
            UI.PlayCrossfade(panel)
        else
            panel:Hide()
        end
    end
    for name, btn in pairs(UI.tabButtons) do
        UI.SetPanelTabSelected(btn, name == tabName)
    end
    UI.activeTab = tabName
    SideQuestDB.ui.tab = tabName
    if tabName == "You" then
        UI.RefreshYou()
    elseif tabName == "Guild" then
        UI.RefreshGuild()
    elseif tabName == "Crafters" then
        UI.RefreshCrafters()
    elseif tabName == "Market" then
        UI.RefreshMarket()
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
-- until PLAYER_REGEN_ENABLED). A player who isn't in the SideQuest guild
-- gets the single-pane join window instead of the tabbed one; `nil`
-- (membership not known yet) is treated as "assume member" so a real
-- member never flashes the join pane while login is still settling.
function UI.Show()
    if SideQuest.DisplayIsGuildMember() == false then
        UI.ShowJoin()
        return
    end
    SideQuest.WhenOutOfCombat(function()
        local main = UI.BuildMainFrame()
        main:Show()
        UI.PlayOpenAnim(main)
        UI.ShowTab(UI.activeTab or SideQuestDB.ui.tab or "You")
    end)
end

--- Sets the window's scale from SideQuestDB.ui.scale (default 1.25), shrunk
-- if needed so the frame and its tab row still fit the screen's height.
function UI.ApplyWindowScale(main)
    main = main or UI.main
    if not main then
        return
    end
    local scale = SideQuestDB.ui.scale or WINDOW_DEFAULT_SCALE
    local screenH = UIParent:GetHeight() or 0
    local frameH = (main:GetHeight() or 0) + WINDOW_OVERHANG_H
    if screenH > 0 and frameH > 0 then
        scale = math.min(scale, screenH / frameH)
    end
    main:SetScale(scale)
end

SideQuest.RegisterSlash("scale", function(rest)
    local arg = (rest or ""):lower()
    local value = tonumber(arg)
    if arg == "reset" then
        SideQuestDB.ui.scale = nil
    elseif value and value >= WINDOW_SCALE_MIN and value <= WINDOW_SCALE_MAX then
        SideQuestDB.ui.scale = value
    else
        SideQuest.Print(string.format("Usage: /sq scale <%.2f-%.2f> or /sq scale reset (now %.2f)",
            WINDOW_SCALE_MIN, WINDOW_SCALE_MAX, SideQuestDB.ui.scale or WINDOW_DEFAULT_SCALE))
        return
    end
    UI.ApplyWindowScale()
    SideQuest.Print(string.format("Window scale: %.2f", SideQuestDB.ui.scale or WINDOW_DEFAULT_SCALE))
end, "scale <0.75-2>|reset - make the SideQuest window bigger or smaller")

function UI.Toggle()
    if UI.joinFrame and UI.joinFrame:IsShown() then
        UI.joinFrame:Hide()
        return
    end
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

    -- state lines ("No standings yet -- ...") run longer than the column:
    -- they wrap at the sub-headings' width instead of running under the
    -- scroll bar and off the chamber
    local function wrapToColumn(fs)
        fs:SetWidth(320)
        fs:SetWordWrap(true)
        return fs
    end
    local nameRow = createNameRow(content, 16)
    nameRow:SetPoint("TOPLEFT", 0, 0)
    local rankText = wrapToColumn(makeFontString(content, FONT_BODY, 12, C.mist, "LEFT"))
    rankText:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -4)
    local prText = wrapToColumn(makeFontString(content, FONT_BODY, 13, C.ink, "LEFT"))
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
    local historyEmpty = wrapToColumn(makeFontString(content, FONT_BODY, 11, C.mist2, "LEFT"))
    historyEmpty:SetPoint("TOPLEFT", historyHeading, "BOTTOMLEFT", 0, -6)
    historyEmpty:Hide()

    local nextEventHeading = createSubHeading(content, "Next event")
    nextEventHeading:SetPoint("TOPLEFT", baselineText, "BOTTOMLEFT", 0, -14)
    nextEventHeading:SetWidth(320)
    local nextEventTitle = wrapToColumn(makeFontString(content, FONT_BODY, 13, C.ink, "LEFT"))
    nextEventTitle:SetPoint("TOPLEFT", nextEventHeading, "BOTTOMLEFT", 0, -6)
    local nextEventMeta = wrapToColumn(makeFontString(content, FONT_BODY, 11, C.mist2, "LEFT"))
    nextEventMeta:SetPoint("TOPLEFT", nextEventTitle, "BOTTOMLEFT", 0, -2)

    local answerButtons = {}
    for i, answer in ipairs({ { "going", "Going" }, { "maybe", "Maybe" }, { "cant", "Can't" } }) do
        local btn = createButton(content, "quiet", answer[2], 72, 24)
        btn:SetPoint("TOPLEFT", nextEventMeta, "BOTTOMLEFT", (i - 1) * 78, -8)
        answerButtons[answer[1]] = btn
    end
    local signupState = wrapToColumn(makeFontString(content, FONT_BODY, 11, C.mist2, "LEFT"))
    signupState:SetPoint("TOPLEFT", answerButtons.going, "BOTTOMLEFT", 0, -8)

    local badgesHeading = createSubHeading(content, "Badges")
    badgesHeading:SetPoint("TOPLEFT", signupState, "BOTTOMLEFT", 0, -16)
    badgesHeading:SetWidth(320)
    local badgesText = wrapToColumn(makeFontString(content, FONT_BODY, 12, C.flavor, "LEFT"))
    badgesText:SetPoint("TOPLEFT", badgesHeading, "BOTTOMLEFT", 0, -6)
    local epgpAltsText = wrapToColumn(makeFontString(content, FONT_BODY, 12, C.mist, "LEFT"))
    epgpAltsText:SetPoint("TOPLEFT", badgesText, "BOTTOMLEFT", 0, -6)

    -- Sharing: five checkboxes for settings.share, one plain sentence each
    -- on what it shares with the guild's directory.
    local sharingHeading = createSubHeading(content, "Sharing")
    sharingHeading:SetPoint("TOPLEFT", epgpAltsText, "BOTTOMLEFT", 0, -16)
    sharingHeading:SetWidth(320)
    local sharingRows = {}
    local prevAnchor = sharingHeading
    for _, section in ipairs(SHARE_SECTIONS) do
        local cb = createCheckbox(content, 16)
        cb:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -8)
        local labelFS = makeFontString(content, FONT_BODY, 12, C.ink, "LEFT")
        labelFS:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        labelFS:SetText(section.label)
        local sentenceFS = makeFontString(content, FONT_BODY_ITALIC, 10, C.mist2, "LEFT")
        sentenceFS:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 2, -2)
        sentenceFS:SetWidth(310)
        if sentenceFS.SetWordWrap then sentenceFS:SetWordWrap(true) end
        sentenceFS:SetText(section.sentence)
        cb:SetScript("OnClick", function()
            SideQuestDB.settings.share = SideQuestDB.settings.share or {}
            SideQuestDB.settings.share[section.key] = cb:GetChecked() and true or false
        end)
        sharingRows[section.key] = { checkbox = cb, sentence = sentenceFS }
        prevAnchor = sentenceFS
    end
    you.sharingHeading, you.sharingRows = sharingHeading, sharingRows

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
        you.nextEventHeading:SetPoint("TOPLEFT", you.baselineText, "BOTTOMLEFT", 0, -14)
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
            row.week:SetText(date("%b %d", weekStart))
            row.ep:SetText(string.format("%.0f", epTotals[i]))
            row.gp:SetText(string.format("%.0f", gpTotals[i]))
        end
    else
        you.historyTable:Hide()
        you.baselineText:Hide()
        you.historyEmpty:Show()
        setStateText(you.historyEmpty, "No sheet yet -- opening Ledger asks an officer for yours.", true)
        -- hidden regions still hold their space as anchors: hang the next
        -- section off the line that is showing
        you.nextEventHeading:SetPoint("TOPLEFT", you.historyEmpty, "BOTTOMLEFT", 0, -14)
    end

    -- next event + sign-up state, with the current answer highlighted
    local nextEvt = SideQuest.Events.Upcoming()[1]
    if nextEvt then
        you.nextEventTitle:SetText(nextEvt.title or "Event")
        local secs = (nextEvt.starts_at or 0) - now()
        you.nextEventMeta:SetText((secs > 0 and ("in " .. math.floor(secs / 3600) .. "h  --  ") or "in progress  --  ")
            .. date("%a %H:%M", nextEvt.starts_at or now()))
        local state, status = SideQuest.Signups.MyState(nextEvt.id)
        local statusToAnswer = { signed = "going", tentative = "maybe", absent = "cant" }
        local currentAnswer = statusToAnswer[status]
        for answer, btn in pairs(you.answerButtons) do
            btn:Show()
            btn:SetScript("OnClick", function()
                SideQuest.Signups.Answer(nextEvt.id, answer)
                UI.RefreshYou()
            end)
            btn:SetSelected(answer == currentAnswer)
        end
        if state == "sent" then
            setStateText(you.signupState, "Sent -- waiting for an officer", false)
        elseif state == "saved" then
            setStateText(you.signupState, "Saved (" .. status .. ") -- reaches the site at the next sync", false)
        else
            setStateText(you.signupState, "Not signed yet", false)
        end
        you.badgesHeading:SetPoint("TOPLEFT", you.signupState, "BOTTOMLEFT", 0, -16)
    else
        setStateText(you.nextEventTitle, "No events scheduled yet", true)
        you.nextEventMeta:SetText("")
        setStateText(you.signupState, "", false)
        -- nothing to answer: no buttons, and badges follow the title
        for _, btn in pairs(you.answerButtons) do
            btn:SetSelected(false)
            btn:Hide()
        end
        you.badgesHeading:SetPoint("TOPLEFT", you.nextEventTitle, "BOTTOMLEFT", 0, -16)
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
    for _, section in ipairs(SHARE_SECTIONS) do
        local share = SideQuestDB.settings.share
        local checked = not share or share[section.key] ~= false
        you.sharingRows[section.key].checkbox:SetChecked(checked)
    end
    -- the You column is a fixed stack: name, PR, four weeks, next event,
    -- answers, badges, guild EP line, sharing checklist
    setScrollContentHeight(you.scroll, 610)

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
    local shownOnline = math.min(#onlineRows, #guildNow.onlineList.rows)
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
    -- the list is only as tall as its rows, so "See all" and the news
    -- follow the count instead of leaving five empty lines
    guildNow.onlineList:SetHeight(math.max(1, 14 * shownOnline))

    local newsItems = SideQuest.News.Get()
    for _, row in ipairs(guildNow.newsRows) do
        row:Hide()
    end
    if #newsItems == 0 then
        if not guildNow.emptyText then
            guildNow.emptyText = makeFontString(guildNow.newsContent, FONT_BODY, 12, C.mist2, "LEFT")
            guildNow.emptyText:SetPoint("TOPLEFT")
            guildNow.emptyText:SetWidth(300)
            guildNow.emptyText:SetWordWrap(true)
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
        row.meta:SetText((item.character and (displayName(item.character) .. "  ") or "") .. date("%m/%d %H:%M", item.at or now()))
        row:Show()
    end
    setScrollContentHeight(guildNow.newsScroll, 32 * shown)

    UI.RefreshFreshness()
end

--------------------------------------------------------------------------
-- GUILD tab: roster+, header row, search + online/class/rank filters,
-- alts grouped under their main (expand/collapse), online first
--------------------------------------------------------------------------

-- A member's directory detail, shown inline under their row once clicked:
-- level/spec/item level, professions with skill, attunements, tracked
-- reputations, cooldowns and how fresh the record is.
local GUILD_DETAIL_INDENT, GUILD_DETAIL_LINE = 28, 16

local function buildGuildDetail(content)
    local block = CreateFrame("Frame", nil, content)
    block:SetWidth(540)
    block.nameRow = createNameRow(block, 14)
    block.nameRow:SetPoint("TOPLEFT", GUILD_DETAIL_INDENT, 0)
    block.metaText = makeFontString(block, FONT_BODY, 12, C.mist, "LEFT")
    block.metaText:SetPoint("LEFT", block.nameRow, "RIGHT", 10, 0)
    block.freshnessText = makeFontString(block, FONT_BODY_ITALIC, 10, C.mist2, "LEFT")
    block.freshnessText:SetPoint("TOPLEFT", block.nameRow, "BOTTOMLEFT", 0, -4)

    block.profHeading = createSubHeading(block, "Professions")
    block.profHeading:SetWidth(520)
    block.attuneHeading = createSubHeading(block, "Attunements")
    block.attuneHeading:SetWidth(520)
    block.attuneText = makeFontString(block, FONT_BODY, 12, C.mist, "LEFT")
    block.attuneText:SetWidth(500)
    if block.attuneText.SetWordWrap then block.attuneText:SetWordWrap(true) end
    block.repHeading = createSubHeading(block, "Reputations")
    block.repHeading:SetWidth(520)
    block.cdHeading = createSubHeading(block, "Cooldowns")
    block.cdHeading:SetWidth(520)
    block.profRows, block.repRows, block.cdRows = {}, {}, {}
    return block
end

--- A character's equipped item level from the last site import ("Game
-- import" contract GameImportCharacter.item_level, additive): nil when
-- the import has no entry for them, or when an import predating the
-- field is all the addon has. Only consulted when the live directory
-- hasn't scanned this character's gear yet.
local function importItemLevel(character)
    for _, member in ipairs((SideQuestDB.guild and SideQuestDB.guild.members) or {}) do
        for _, char in ipairs(member.characters or {}) do
            if char.name == character then
                return char.item_level
            end
        end
    end
    return nil
end

--- Fills `block` with `character`'s directory record and returns the
-- height it used, so the caller can offset rows below it.
function UI.PaintGuildDetail(block, character)
    local Directory = SideQuest.Directory
    local entry = Directory and Directory.Get and Directory.Get(character)
    local charData = entry and entry.char and entry.char.d
    local profData = entry and entry.prof and entry.prof.d
    local cdData = entry and entry.cd and entry.cd.d

    setNameRow(block.nameRow, character, charData and charData.class)
    local metaParts = {}
    if charData and charData.level then table.insert(metaParts, "Level " .. charData.level) end
    if charData and charData.spec then table.insert(metaParts, charData.spec) end
    local ilvl = (charData and charData.item_level) or importItemLevel(character)
    if ilvl then table.insert(metaParts, "ilvl " .. string.format("%.1f", ilvl)) end
    block.metaText:SetText(table.concat(metaParts, "  --  "))
    local freshness = recordFreshness(entry)
    setStateText(block.freshnessText, freshness and ("Record " .. ago(freshness)) or "No directory record yet", not freshness)

    local y = 34
    local function listOrEmpty(heading, list, rows, emptyKey, emptyMsg, lineFn)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", 20, -y)
        y = y + 18
        for _, r in ipairs(rows) do r:Hide() end
        if list and #list > 0 then
            if block[emptyKey] then block[emptyKey]:Hide() end
            for i, item in ipairs(list) do
                local row = rows[i]
                if not row then
                    row = makeFontString(block, FONT_BODY, 12, C.mist, "LEFT")
                    rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", GUILD_DETAIL_INDENT, -y)
                row:SetText(lineFn(item))
                row:Show()
                y = y + GUILD_DETAIL_LINE
            end
        else
            if not block[emptyKey] then
                block[emptyKey] = makeFontString(block, FONT_BODY_ITALIC, 11, C.mist2, "LEFT")
            end
            block[emptyKey]:ClearAllPoints()
            block[emptyKey]:SetPoint("TOPLEFT", GUILD_DETAIL_INDENT, -y)
            block[emptyKey]:SetText(emptyMsg)
            block[emptyKey]:Show()
            y = y + GUILD_DETAIL_LINE
        end
        y = y + 6
    end

    listOrEmpty(block.profHeading, profData and profData.professions, block.profRows, "profEmptyText",
        "No professions on record.", function(p)
            return p.name .. ": " .. (p.skill or 0) .. " / " .. (p.max_skill or "--")
        end)

    block.attuneHeading:ClearAllPoints()
    block.attuneHeading:SetPoint("TOPLEFT", 20, -y)
    y = y + 18
    block.attuneText:ClearAllPoints()
    block.attuneText:SetPoint("TOPLEFT", GUILD_DETAIL_INDENT, -y)
    if charData and charData.attunements and #charData.attunements > 0 then
        local labels = {}
        for _, key in ipairs(charData.attunements) do
            table.insert(labels, attunementLabel(key))
        end
        block.attuneText:SetText(table.concat(labels, ", "))
    else
        block.attuneText:SetText("None on record.")
    end
    y = y + GUILD_DETAIL_LINE + 6

    listOrEmpty(block.repHeading, charData and charData.reputations, block.repRows, "repEmptyText",
        "No tracked reputations on record.", function(rep)
            local label = reputationLabel(rep.faction_id)
            return label .. ": " .. (STANDING_WORD[rep.standing] or "--") .. (rep.value and (" (" .. rep.value .. ")") or "")
        end)

    listOrEmpty(block.cdHeading, cdData and cdData.cooldowns, block.cdRows, "cdEmptyText",
        "No tracked cooldowns on record.", function(cd)
            local def
            for _, d in ipairs(cooldownDefs()) do
                if d.key == cd.key then def = d break end
            end
            return (def and (def.label or labelFromKey(def.key)) or labelFromKey(cd.key)) .. ": " .. readyWord(cd.ready_at)
        end)

    y = y + 4
    block:SetHeight(y)
    return y
end

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
    submitOnEnter(searchBox) -- it filters as you type; Enter just lets go

    local onlineOnly = createCheckbox(chamber.inner, 16)
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
    header:SetPoint("TOPRIGHT", -28, -58)
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
    headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -3)

    local scroll, content = buildScroll(chamber.inner, -80)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    chamber.expanded = {}
    chamber.detailBlock = buildGuildDetail(content)
    panel.chamber = chamber
end

-- Whisper/Invite sit right of the Last seen column, never over a column's
-- text: the row runs on past Last seen just far enough to hold them.
local GUILD_ROW_LAST_SEEN_W = 64
local GUILD_ROW_BUTTON_W, GUILD_ROW_BUTTON_GAP = 66, 6

local function buildGuildRow(content, cols)
    local ui = CreateFrame("Button", nil, content)
    local buttonsLeft = cols.lastSeen + GUILD_ROW_LAST_SEEN_W
    ui:SetSize(buttonsLeft + 2 * GUILD_ROW_BUTTON_W + GUILD_ROW_BUTTON_GAP, 22)
    -- Everything in the row anchors to the row itself: a region anchored to
    -- a frame whose rect is invalid (one point and no explicit height, as a
    -- width-only spacer frame had here) is never drawn in game, which is
    -- what blanked every name, gem and status word in the Guild tab.
    ui.expandBtn = UI.CreateExpandButton(ui)
    ui.expandBtn:SetPoint("LEFT", 0, 0)
    ui.statusIcon = ui:CreateTexture(nil, "ARTWORK")
    ui.statusIcon:SetSize(10, 10)
    ui.statusIcon:SetTexture(MEDIA_TEX .. "Gem")
    ui.statusIcon:SetPoint("LEFT", 20, 0)
    ui.nameRow = createNameRow(ui, 13)
    ui.nameRow:SetPoint("LEFT", ui.statusIcon, "RIGHT", 6, 0)
    ui.levelText = makeFontString(ui, FONT_BODY, 12, C.ink, "RIGHT")
    ui.levelText:SetWidth(40)
    ui.levelText:SetPoint("LEFT", cols.level, 0)
    ui.rankText = makeFontString(ui, FONT_BODY, 12, C.mist, "LEFT")
    ui.rankText:SetPoint("LEFT", cols.rank, 0)
    ui.zoneText = makeFontString(ui, FONT_BODY, 12, C.mist, "LEFT")
    ui.zoneText:SetPoint("LEFT", cols.zone, 0)
    -- Last seen doubles as the word that goes with the online gem
    -- (DESIGN.md: online state is the gem plus the word).
    ui.lastSeenText = makeFontString(ui, FONT_BODY, 11, C.mist2, "LEFT")
    ui.lastSeenText:SetPoint("LEFT", cols.lastSeen, 0)
    ui.whisperBtn = createButton(ui, "quiet", "Whisper", GUILD_ROW_BUTTON_W, 18)
    ui.whisperBtn:SetPoint("LEFT", buttonsLeft, 0)
    ui.inviteBtn = createButton(ui, "quiet", "Invite", GUILD_ROW_BUTTON_W, 18)
    ui.inviteBtn:SetPoint("LEFT", ui.whisperBtn, "RIGHT", GUILD_ROW_BUTTON_GAP, 0)
    ui.whisperBtn:Hide()
    ui.inviteBtn:Hide()
    -- Whisper/Invite sit inside the row's own hit rect, so moving the
    -- pointer onto either child button still fires the row's OnLeave (the
    -- child takes mouse focus) even though the pointer never left the row;
    -- that used to hide the buttons right back under the pointer, which
    -- immediately re-triggered the row's OnEnter -- an endless flicker.
    -- ui:IsMouseOver() is true for the whole time the pointer is anywhere
    -- over the row OR either button, so only a real exit hides them. The
    -- buttons' own OnLeave (createButton's hover-paint reset) is hooked,
    -- not replaced, as a backstop for the same reason.
    local function updateHoverButtons()
        if ui.selected or ui:IsMouseOver() then
            ui.whisperBtn:Show()
            ui.inviteBtn:Show()
        else
            ui.whisperBtn:Hide()
            ui.inviteBtn:Hide()
        end
    end
    ui:SetScript("OnEnter", updateHoverButtons)
    ui:SetScript("OnLeave", updateHoverButtons)
    ui.whisperBtn:HookScript("OnLeave", updateHoverButtons)
    ui.inviteBtn:HookScript("OnLeave", updateHoverButtons)
    ui.updateHoverButtons = updateHoverButtons
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
        chamber.detailBlock:Hide()
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
    -- shown again below only under its member's row; left up, it would
    -- sit over the empty-list line at its last position
    chamber.detailBlock:Hide()
    if #shownGroups == 0 then
        if not chamber.noResultText then
            chamber.noResultText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.noResultText:SetPoint("TOPLEFT")
            chamber.noResultText:SetWidth(500)
            chamber.noResultText:SetWordWrap(true)
        end
        local message
        if #order == 0 then
            -- No member groups at all, before any filter is applied: nobody has ever
            -- been imported or swept, not "filters hide everyone".
            message = "No guild data yet -- SideQuest Companion loads it at login, "
                .. "or ask an officer to paste the site's import with /sq import."
        elseif query ~= "" then
            message = "No one matches '" .. query .. "'."
        else
            message = "No members match these filters."
        end
        setStateText(chamber.noResultText, message, true)
        return
    elseif chamber.noResultText then
        chamber.noResultText:SetText("")
    end

    local function paintRow(ui, r, indent)
        ui.expandBtn:ClearAllPoints()
        ui.expandBtn:SetPoint("LEFT", indent - 20, 0)
        ui.statusIcon:ClearAllPoints()
        ui.statusIcon:SetPoint("LEFT", indent, 0)
        local gem = r.online and C.online or C.offline
        ui.statusIcon:SetVertexColor(gem[1], gem[2], gem[3], 1)
        setNameRow(ui.nameRow, r.character, r.class)
        ui.levelText:SetText(r.level and tostring(r.level) or "--")
        ui.rankText:SetText(r.rank or "")
        ui.zoneText:SetText(r.zone or "")
        -- same tint as the gem: online reads green, offline muted
        ui.lastSeenText:SetText(r.online and "Online"
            or (r.last_online_hours and (r.last_online_hours .. "h ago") or "Offline"))
        ui.lastSeenText:SetTextColor(gem[1], gem[2], gem[3], 1)
        ui.whisperBtn:SetScript("OnClick", function()
            SideQuest.Whisper(r.character)
        end)
        ui.inviteBtn:SetScript("OnClick", function()
            SideQuest.Invite(r.character)
        end)
        ui.inviteBtn:SetEnabled(SideQuest.DisplayIsOfficer())
        ui.selected = (chamber.selectedCharacter == r.character)
        ui.updateHoverButtons()
        ui:SetScript("OnClick", function()
            chamber.selectedCharacter = (chamber.selectedCharacter == r.character) and nil or r.character
            UI.RefreshGuild()
        end)
        ui:Show()
    end

    local y, i = 0, 0
    for _, g in ipairs(shownGroups) do
        i = i + 1
        local ui = chamber.rows[i]
        if not ui then
            ui = buildGuildRow(chamber.content, chamber.cols)
            chamber.rows[i] = ui
        end
        local expandKey = g.main.member_id or g.main.character
        local hasAlts = #g.alts > 0
        ui.expandBtn:SetExpanded(chamber.expanded[expandKey])
        ui.expandBtn:SetShown(hasAlts)
        ui.expandBtn:SetScript("OnClick", function()
            chamber.expanded[expandKey] = not chamber.expanded[expandKey]
            UI.RefreshGuild()
        end)
        ui:SetPoint("TOPLEFT", 0, -y)
        paintRow(ui, g.main, 20)
        y = y + 24
        if chamber.selectedCharacter == g.main.character then
            chamber.detailBlock:ClearAllPoints()
            chamber.detailBlock:SetPoint("TOPLEFT", 20, -y)
            local used = UI.PaintGuildDetail(chamber.detailBlock, g.main.character)
            chamber.detailBlock:Show()
            y = y + used
        end
        if hasAlts and chamber.expanded[expandKey] then
            for _, alt in ipairs(g.alts) do
                i = i + 1
                local altUi = chamber.rows[i]
                if not altUi then
                    altUi = buildGuildRow(chamber.content, chamber.cols)
                    chamber.rows[i] = altUi
                end
                altUi:SetPoint("TOPLEFT", 0, -y)
                paintRow(altUi, alt, 46)
                y = y + 24
                if chamber.selectedCharacter == alt.character then
                    chamber.detailBlock:ClearAllPoints()
                    chamber.detailBlock:SetPoint("TOPLEFT", 20, -y)
                    local used = UI.PaintGuildDetail(chamber.detailBlock, alt.character)
                    chamber.detailBlock:Show()
                    y = y + used
                end
            end
        end
    end
    setScrollContentHeight(chamber.scroll, y)
end

--------------------------------------------------------------------------
-- CRAFTERS tab: three sub-views on native top tabs (the Console's
-- pattern) -- Search (recipe/profession lookup: the legacy CRAFT_Q
-- answers plus the directory's instant WhoCrafts), Professions (who has
-- a profession, best skill first, online first) and Cooldowns (who has a
-- craft cooldown and when it's ready). The selected sub-tab names the
-- view, so these chambers carry no ribbon of their own.
--------------------------------------------------------------------------

function UI.BuildCraftersPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.Crafters = panel

    local CRAFTERS_TAB_TOP = 30
    panel.subButtons = {}
    local prev
    for _, name in ipairs(CRAFTERS_SUBTABS) do
        local btn = UI.CreatePanelTab(panel, name, true)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        else
            btn:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 26, -CRAFTERS_TAB_TOP)
        end
        prev = btn
        UI.SetPanelTabSelected(btn, false)
        btn:SetScript("OnClick", function()
            UI.ShowCraftersSub(name)
        end)
        panel.subButtons[name] = btn
    end
    panel.tabTop = CRAFTERS_TAB_TOP
    panel.subPanels = {}

    UI.BuildCraftersSearch(panel)
    UI.BuildCraftersProfessions(panel)
    UI.BuildCraftersCooldowns(panel)
end

function UI.ShowCraftersSub(name)
    local panel = UI.panels.Crafters
    for subName, sub in pairs(panel.subPanels) do
        if subName == name then
            sub:Show()
            UI.PlayCrossfade(sub)
        else
            sub:Hide()
        end
    end
    for subName, btn in pairs(panel.subButtons) do
        UI.SetPanelTabSelected(btn, subName == name)
    end
    panel.activeSub = name
    if name == "Search" then
        UI.RefreshCraftersSearch()
    elseif name == "Professions" then
        UI.RefreshCraftersProfessions()
    elseif name == "Cooldowns" then
        UI.RefreshCraftersCooldowns()
    end
end

function UI.RefreshCrafters()
    local panel = UI.panels and UI.panels.Crafters
    if not panel then
        return
    end
    UI.ShowCraftersSub(panel.activeSub or "Search")
end

local function makeCraftersSub(panel, key)
    local sub = CreateFrame("Frame", nil, panel)
    sub:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -panel.tabTop)
    sub:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 6)
    sub:Hide()
    panel.subPanels[key] = sub
    return sub
end

-- Search: recipe/profession text search, answered from both the legacy
-- CRAFT_Q/CRAFT_A results and the directory's instant WhoCrafts lookup.

function UI.BuildCraftersSearch(panel)
    local sub = makeCraftersSub(panel, "Search")
    local chamber = createChamber(sub, "SideQuestCraftersSearchChamber")
    chamber:SetAllPoints(sub)

    local searchBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    skinEditBox(searchBox, "Search recipes or crafters")
    searchBox:SetSize(260, 20)
    searchBox:SetPoint("TOPLEFT", 14, -10)
    searchBox:SetAutoFocus(false)
    local searchBtn = createButton(chamber.inner, "primary", "Search", 80, 20)
    searchBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    searchBtn:SetScript("OnClick", function()
        local text = searchBox:GetText()
        if text and text ~= "" then
            if SideQuest.Crafters and SideQuest.Crafters.Query then
                SideQuest.Crafters.Query(text)
            end
            chamber.lastQuery = text
            UI.RefreshCraftersSearch()
        end
    end)
    chamber.searchBox, chamber.searchBtn = searchBox, searchBtn
    submitOnEnter(searchBox, searchBtn)

    local summaryText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist2, "LEFT")
    summaryText:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -8)
    chamber.summaryText = summaryText

    local scroll, content = buildScroll(chamber.inner, -56)
    chamber.scroll, chamber.content, chamber.groupRows = scroll, content, {}
    panel.searchChamber = chamber
end

function UI.RefreshCraftersSearch()
    local panel = UI.panels and UI.panels.Crafters
    if not panel or not panel.searchChamber then
        return
    end
    local chamber = panel.searchChamber

    for _, g in ipairs(chamber.groupRows) do
        g.header:Hide()
        for _, r in ipairs(g.rows) do r:Hide() end
    end

    -- bucket by recipe name (or by profession, when a crafter matched on
    -- profession rather than a specific recipe), merging the legacy
    -- CRAFT_Q answers with the directory's instant WhoCrafts so the same
    -- character never appears twice under one recipe.
    local recipeBuckets, recipeOrder, seenInRecipe = {}, {}, {}
    local professionMembers, professionOrder = {}, {}
    local seenCharacters, total = {}, 0

    local function countProfession(profession, character)
        if not profession then
            return
        end
        if not professionMembers[profession] then
            professionMembers[profession] = {}
            table.insert(professionOrder, profession)
        end
        professionMembers[profession][character] = true
    end

    local function addEntry(recipeKey, character, skill, online)
        local dedupeKey = recipeKey .. "\0" .. character
        if seenInRecipe[dedupeKey] then
            return
        end
        seenInRecipe[dedupeKey] = true
        if not recipeBuckets[recipeKey] then
            recipeBuckets[recipeKey] = {}
            table.insert(recipeOrder, recipeKey)
        end
        table.insert(recipeBuckets[recipeKey], { character = character, skill = skill, online = online and true or false })
    end

    for character, row in pairs(SideQuest.Crafters.results or {}) do
        if not seenCharacters[character] then
            seenCharacters[character] = true
            total = total + 1
        end
        countProfession(row.profession, character)
        if row.recipes and #row.recipes > 0 then
            for _, recipe in ipairs(row.recipes) do
                addEntry(recipe.name, character, row.skill, row.online)
            end
        else
            addEntry("Profession: " .. (row.profession or "?"), character, row.skill, row.online)
        end
    end

    local query = chamber.lastQuery
    if query and query ~= "" and SideQuest.Directory and SideQuest.Directory.WhoCrafts then
        for _, hit in ipairs(SideQuest.Directory.WhoCrafts(query) or {}) do
            if not seenCharacters[hit.character] then
                seenCharacters[hit.character] = true
                total = total + 1
            end
            countProfession(hit.profession, hit.character)
            local recipeKey = hit.recipe_name or ("Profession: " .. (hit.profession or "?"))
            addEntry(recipeKey, hit.character, hit.skill, hit.online)
        end
    end

    local summaryParts = {}
    for _, prof in ipairs(professionOrder) do
        local count = 0
        for _ in pairs(professionMembers[prof]) do count = count + 1 end
        table.insert(summaryParts, prof .. " (" .. count .. ")")
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
                SideQuest.Whisper(entry.character)
            end)
            row:Show()
            y = y + 20
        end
        y = y + 6
    end
    setScrollContentHeight(chamber.scroll, y)
end


--- The learned-recipe count for one member's profession (ByProfession
-- doesn't carry it, so this reads the member's own prof section) and
-- when that member was last heard from at all (Directory.Get's seen_at).
local function craftersRecipeCount(character, profession)
    local Directory = SideQuest.Directory
    local d = Directory and Directory.Section and Directory.Section(character, "prof")
    if not d or not d.professions then
        return nil
    end
    for _, p in ipairs(d.professions) do
        if p.name == profession and p.recipes then
            return #p.recipes
        end
    end
    return nil
end

local function craftersLastSeen(character)
    local Directory = SideQuest.Directory
    local entry = Directory and Directory.Get and Directory.Get(character)
    return entry and entry.seen_at
end

-- Professions: every member's professions by default (online first, then
-- by profession, best skill first); the button narrows to one profession
-- and cycles back round to all. Each row shows the recipe count and when
-- that member was last seen.

local function professionLabel(profession)
    return "Profession: " .. (profession or "All")
end

function UI.BuildCraftersProfessions(panel)
    local sub = makeCraftersSub(panel, "Professions")
    local chamber = createChamber(sub, "SideQuestCraftersProfessionsChamber")
    chamber:SetAllPoints(sub)

    -- chamber.profession nil means all; a click steps All -> first ->
    -- ... -> last -> All
    local professionBtn = createButton(chamber.inner, "quiet", professionLabel(nil), 190, 20)
    professionBtn:SetPoint("TOPLEFT", 14, -10)
    professionBtn:SetScript("OnClick", function()
        local names = professionNames()
        local nextName = names[1]
        for i, v in ipairs(names) do
            if v == chamber.profession then
                nextName = names[i + 1]
            end
        end
        chamber.profession = nextName
        UI.RefreshCraftersProfessions()
    end)
    chamber.professionBtn = professionBtn

    local header = CreateFrame("Frame", nil, chamber.inner)
    header:SetPoint("TOPLEFT", 14, -44)
    header:SetPoint("TOPRIGHT", -28, -44)
    header:SetHeight(16)
    local COLS = { name = 0, profession = 150, skill = 250, recipes = 360, lastSeen = 430 }
    chamber.cols = COLS
    local function headerLabel(text, x, w, justify)
        local fs = makeFontString(header, FONT_BODY, 10, C.mist2, justify or "LEFT")
        fs:SetPoint("TOPLEFT", x, 0)
        if w then fs:SetWidth(w) end
        fs:SetText(trackedCaps(text))
        return fs
    end
    headerLabel("Name", COLS.name)
    headerLabel("Profession", COLS.profession)
    headerLabel("Skill / Max", COLS.skill, 90, "RIGHT")
    headerLabel("Recipes", COLS.recipes, 60, "RIGHT")
    headerLabel("Last seen", COLS.lastSeen)
    local headerLine = hairline(chamber.inner)
    headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -3)

    local scroll, content = buildScroll(chamber.inner, -66)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    panel.professionsChamber = chamber
end

function UI.RefreshCraftersProfessions()
    local panel = UI.panels and UI.panels.Crafters
    if not panel or not panel.professionsChamber then
        return
    end
    local chamber = panel.professionsChamber
    chamber.professionBtn:SetText(professionLabel(chamber.profession))

    for _, r in ipairs(chamber.rows) do r:Hide() end

    if not (SideQuest.Directory and SideQuest.Directory.ByProfession) then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "The directory hasn't synced professions yet.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    local members = SideQuest.Directory.ByProfession(chamber.profession) or {}
    -- Offline/imported crafters (contract SQI1 on-demand "crafters",
    -- additive): a character+profession the live directory already has
    -- wins (fresher skill, recipe counts, online state); the import only
    -- fills in characters/professions the directory hasn't seen at all.
    -- Cooldowns stay live-only -- the import carries none.
    local seenKey = {}
    for _, m in ipairs(members) do
        seenKey[m.character .. "\0" .. (m.profession or "")] = true
    end
    for _, row in ipairs((SideQuestDB.onDemand and SideQuestDB.onDemand.crafters) or {}) do
        local key = row.character .. "\0" .. (row.profession or "")
        if not seenKey[key] and (chamber.profession == nil or row.profession == chamber.profession) then
            seenKey[key] = true
            table.insert(members, { character = row.character, profession = row.profession, skill = row.skill, online = false })
        end
    end
    table.sort(members, function(a, b)
        local aOnline, bOnline = a.online and true or false, b.online and true or false
        if aOnline ~= bOnline then return aOnline end
        if a.profession ~= b.profession then return (a.profession or "") < (b.profession or "") end
        if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) > (b.skill or 0) end
        return a.character < b.character
    end)

    if #members == 0 then
        if not chamber.noResultText then
            chamber.noResultText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.noResultText:SetPoint("TOPLEFT")
            chamber.noResultText:SetWidth(500)
            chamber.noResultText:SetWordWrap(true)
        end
        setStateText(chamber.noResultText, chamber.profession
            and ("No one in the directory has " .. chamber.profession .. " yet.")
            or "No one has shared their professions yet -- skill levels sync automatically once you're "
                .. "out of combat; open a profession window to also share its recipes.", false)
        return
    elseif chamber.noResultText then
        chamber.noResultText:SetText("")
    end

    local COLS = chamber.cols
    for i, m in ipairs(members) do
        local row = chamber.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.content)
            row:SetSize(560, 22)
            row.nameRow = createNameRow(row, 12)
            row.nameRow:SetPoint("LEFT", 0, 0)
            row.skillText = makeFontString(row, FONT_BODY, 12, C.ink, "RIGHT")
            row.skillText:SetWidth(90)
            row.recipesText = makeFontString(row, FONT_BODY, 12, C.mist, "RIGHT")
            row.recipesText:SetWidth(60)
            row.professionText = makeFontString(row, FONT_BODY, 12, C.mist, "LEFT")
            row.professionText:SetWidth(95)
            row.lastSeenText = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
            row.lastSeenText:SetWidth(60)
            row.whisperBtn = createButton(row, "quiet", "Whisper", 66, 18)
            row.whisperBtn:SetPoint("RIGHT", 0, 0)
            chamber.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -22 * (i - 1))
        setNameRow(row.nameRow, m.character, nil)
        row.professionText:ClearAllPoints()
        row.professionText:SetPoint("LEFT", COLS.profession, 0)
        row.professionText:SetText(m.profession or "")
        row.skillText:ClearAllPoints()
        row.skillText:SetPoint("LEFT", COLS.skill, 0)
        row.skillText:SetText((m.skill or 0) .. " / " .. (m.max_skill or "--"))
        row.recipesText:ClearAllPoints()
        row.recipesText:SetPoint("LEFT", COLS.recipes, 0)
        local recipeCount = craftersRecipeCount(m.character, m.profession)
        row.recipesText:SetText(recipeCount and tostring(recipeCount) or "--")
        row.lastSeenText:ClearAllPoints()
        row.lastSeenText:SetPoint("LEFT", COLS.lastSeen, 0)
        row.lastSeenText:SetText(m.online and "Online" or ago(craftersLastSeen(m.character)))
        local seenColor = m.online and C.online or C.offline
        row.lastSeenText:SetTextColor(seenColor[1], seenColor[2], seenColor[3], 1)
        row.whisperBtn:SetScript("OnClick", function()
            SideQuest.Whisper(m.character)
        end)
        row:Show()
    end
    setScrollContentHeight(chamber.scroll, 22 * #members)
end

-- Cooldowns: every tracked craft cooldown, who has it and when it's ready
-- (ready-first, soonest-ready-next).

function UI.BuildCraftersCooldowns(panel)
    local sub = makeCraftersSub(panel, "Cooldowns")
    local chamber = createChamber(sub, "SideQuestCraftersCooldownsChamber")
    chamber:SetAllPoints(sub)

    local scroll, content = buildScroll(chamber.inner, -10)
    chamber.scroll, chamber.content, chamber.groupRows = scroll, content, {}
    panel.cooldownsChamber = chamber
end

function UI.RefreshCraftersCooldowns()
    local panel = UI.panels and UI.panels.Crafters
    if not panel or not panel.cooldownsChamber then
        return
    end
    local chamber = panel.cooldownsChamber
    for _, g in ipairs(chamber.groupRows) do
        g.header:Hide()
        for _, r in ipairs(g.rows) do r:Hide() end
    end

    if not (SideQuest.Directory and SideQuest.Directory.Cooldowns) then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "The directory hasn't synced cooldowns yet.", true)
        return
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end

    local y, gi, any = 0, 0, false
    for _, def in ipairs(cooldownDefs()) do
        local holders = SideQuest.Directory.Cooldowns(def.key) or {}
        if #holders > 0 then
            any = true
            gi = gi + 1
            local g = chamber.groupRows[gi]
            if not g then
                g = { header = createSubHeading(chamber.content, ""), rows = {} }
                g.header:SetWidth(540)
                chamber.groupRows[gi] = g
            end
            g.header:ClearAllPoints()
            g.header:SetPoint("TOPLEFT", 0, -y)
            g.header.label:SetText(trackedCaps((def.label or labelFromKey(def.key)) .. (def.profession and (" (" .. def.profession .. ")") or "")))
            g.header:Show()
            y = y + 18

            table.sort(holders, function(a, b)
                local aReady, bReady = (a.ready_at or 0) <= now(), (b.ready_at or 0) <= now()
                if aReady ~= bReady then return aReady end
                return (a.ready_at or 0) < (b.ready_at or 0)
            end)
            for ri, h in ipairs(holders) do
                local row = g.rows[ri]
                if not row then
                    row = CreateFrame("Frame", nil, chamber.content)
                    row:SetSize(540, 20)
                    row.nameRow = createNameRow(row, 12)
                    row.nameRow:SetPoint("LEFT", 4, 0)
                    row.readyText = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
                    row.whisperBtn = createButton(row, "quiet", "Whisper", 66, 18)
                    row.whisperBtn:SetPoint("RIGHT", 0, 0)
                    g.rows[ri] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                setNameRow(row.nameRow, h.character, h.class)
                row.readyText:ClearAllPoints()
                row.readyText:SetPoint("LEFT", row.nameRow, "RIGHT", 10, 0)
                row.readyText:SetText(readyWord(h.ready_at))
                row.whisperBtn:SetScript("OnClick", function()
                    SideQuest.Whisper(h.character)
                end)
                row:Show()
                y = y + 20
            end
            y = y + 6
        end
    end
    if not any then
        if not chamber.emptyText2 then
            chamber.emptyText2 = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText2:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText2, "No one in the directory has a tracked cooldown yet.", false)
    elseif chamber.emptyText2 then
        chamber.emptyText2:SetText("")
    end
    setScrollContentHeight(chamber.scroll, y)
end

--------------------------------------------------------------------------
-- MARKET tab: Browse (who sells/buys an item and for how much, standing
-- requests, a "who has it" stock lookup) and Mine (the player's own sell,
-- buy and request editor with price-suggestion hints).
--------------------------------------------------------------------------

function UI.BuildMarketPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.Market = panel

    local MARKET_TAB_TOP = 30
    panel.subButtons = {}
    local prev
    for _, name in ipairs(MARKET_SUBTABS) do
        local btn = UI.CreatePanelTab(panel, name, true)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        else
            btn:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 26, -MARKET_TAB_TOP)
        end
        prev = btn
        UI.SetPanelTabSelected(btn, false)
        btn:SetScript("OnClick", function()
            UI.ShowMarketSub(name)
        end)
        panel.subButtons[name] = btn
    end
    panel.tabTop = MARKET_TAB_TOP
    panel.subPanels = {}

    UI.BuildMarketBrowse(panel)
    UI.BuildMarketMine(panel)
end

function UI.ShowMarketSub(name)
    local panel = UI.panels.Market
    for subName, sub in pairs(panel.subPanels) do
        if subName == name then
            sub:Show()
            UI.PlayCrossfade(sub)
        else
            sub:Hide()
        end
    end
    for subName, btn in pairs(panel.subButtons) do
        UI.SetPanelTabSelected(btn, subName == name)
    end
    panel.activeSub = name
    if name == "Browse" then
        UI.RefreshMarketBrowse()
    elseif name == "Mine" then
        UI.RefreshMarketMine()
    end
end

function UI.RefreshMarket()
    local panel = UI.panels and UI.panels.Market
    if not panel then
        return
    end
    UI.ShowMarketSub(panel.activeSub or "Browse")
end

local function makeMarketSub(panel, key)
    local sub = CreateFrame("Frame", nil, panel)
    sub:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -panel.tabTop)
    sub:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 6)
    sub:Hide()
    panel.subPanels[key] = sub
    return sub
end

-- Browse: an item lookup (sellers and their price, standing buy offers,
-- who has it in bags/bank), plus the guild's full standing-requests feed.

function UI.BuildMarketBrowse(panel)
    local sub = makeMarketSub(panel, "Browse")
    local chamber = createChamber(sub, "SideQuestMarketBrowseChamber")
    chamber:SetAllPoints(sub)

    local lookupBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    skinEditBox(lookupBox, "Item name, link or ID")
    lookupBox:SetSize(180, 20)
    lookupBox:SetPoint("TOPLEFT", 14, -10)
    lookupBox:SetAutoFocus(false)
    acceptItemLinks(lookupBox)
    local lookupBtn = createButton(chamber.inner, "primary", "Who has it", 110, 20)
    lookupBtn:SetPoint("LEFT", lookupBox, "RIGHT", 8, 0)
    lookupBtn:SetScript("OnClick", function()
        local itemId = parseItemInput(lookupBox)
        if itemId then
            chamber.lookupItemId = itemId
            UI.RefreshMarketBrowse()
        end
    end)
    chamber.lookupBox, chamber.lookupBtn = lookupBox, lookupBtn
    submitOnEnter(lookupBox, lookupBtn)

    local resultHeading = createSubHeading(chamber.inner, "Item")
    resultHeading:SetPoint("TOPLEFT", lookupBox, "BOTTOMLEFT", 0, -10)
    resultHeading:SetWidth(540)
    chamber.resultHeading = resultHeading

    local scroll, content = buildScroll(chamber.inner, -72)
    chamber.scroll, chamber.content = scroll, content
    chamber.sellRows, chamber.buyRows, chamber.holdRows, chamber.requestRows = {}, {}, {}, {}
    chamber.sectionHeads = {}
    panel.browseChamber = chamber
end

--- One compact "name -- detail" row shared by sellers/buyers/holders/
-- requests, since none of those lists need more than a whisper button.
local function marketRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(540, 20)
    row.nameRow = createNameRow(row, 12)
    row.nameRow:SetPoint("LEFT", 4, 0)
    row.detailText = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
    row.whisperBtn = createButton(row, "quiet", "Whisper", 66, 18)
    row.whisperBtn:SetPoint("RIGHT", 0, 0)
    return row
end

local function paintMarketRow(row, character, detail, class)
    row:Show()
    setNameRow(row.nameRow, character, class)
    row.detailText:ClearAllPoints()
    row.detailText:SetPoint("LEFT", row.nameRow, "RIGHT", 10, 0)
    row.detailText:SetText(detail)
    row.whisperBtn:SetScript("OnClick", function()
        SideQuest.Whisper(character)
    end)
end

function UI.RefreshMarketBrowse()
    local panel = UI.panels and UI.panels.Market
    if not panel or not panel.browseChamber then
        return
    end
    local chamber = panel.browseChamber
    for _, rows in ipairs({ chamber.sellRows, chamber.buyRows, chamber.holdRows, chamber.requestRows }) do
        for _, row in ipairs(rows) do row:Hide() end
    end
    for _, head in pairs(chamber.sectionHeads) do head:Hide() end
    chamber.stateLines = chamber.stateLines or {}
    for _, fs in pairs(chamber.stateLines) do fs:Hide() end

    local Directory = SideQuest.Directory
    local y = 0

    local function heading(key, title)
        local head = chamber.sectionHeads[key]
        if not head then
            head = createSubHeading(chamber.content, "")
            head:SetWidth(540)
            chamber.sectionHeads[key] = head
        end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", 0, -y)
        head.label:SetText(trackedCaps(title))
        head:Show()
        y = y + 18
    end

    -- one plain line in the list's flow, placed at the current y each time
    local function stateLine(key, text)
        local fs = chamber.stateLines[key]
        if not fs then
            fs = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            fs:SetWidth(540)
            fs:SetWordWrap(true)
            chamber.stateLines[key] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        setStateText(fs, text, false)
        fs:Show()
        y = y + 26
    end

    local function section(key, title, list, rowSet, detailFn)
        if #list == 0 then
            return
        end
        heading(key, title)
        for i, entry in ipairs(list) do
            local row = rowSet[i]
            if not row then
                row = marketRow(chamber.content)
                rowSet[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            paintMarketRow(row, entry.character, detailFn(entry), entry.class)
            y = y + 20
        end
        y = y + 6
    end

    if chamber.lookupItemId then
        local itemId = chamber.lookupItemId
        local itemName = SideQuest.ItemName(itemId)
        chamber.resultHeading.label:SetText(trackedCaps(itemName))

        local sellers = Directory.WhoSells(itemId)
        section("sell", "Sellers", sellers, chamber.sellRows, function(e)
            return money(e.price) .. (e.qty and (" (" .. e.qty .. ")") or "") .. ahSuffix(itemId)
        end)

        local buyers = Directory.WhoBuys(itemId)
        section("buy", "Standing buy offers", buyers, chamber.buyRows, function(e)
            return money(e.price) .. ahSuffix(itemId)
        end)

        local holders = Directory.WhoHas(itemId)
        section("hold", "Who has it", holders, chamber.holdRows, function(e)
            local parts = {}
            if e.bags and e.bags > 0 then table.insert(parts, e.bags .. " in bags") end
            if e.bank and e.bank > 0 then table.insert(parts, e.bank .. " in bank") end
            return #parts > 0 and table.concat(parts, ", ") or "none counted"
        end)

        if #sellers == 0 and #buyers == 0 and #holders == 0 then
            stateLine("item", "No one in the directory sells, wants or carries " .. itemName
                .. " yet. Post a request on Mine and the guild will see it.")
        end
    else
        chamber.resultHeading.label:SetText(trackedCaps("Item"))
        stateLine("item", "Type an item name or ID, or shift-click an item into the box, then press Who has it.")
    end

    local requests = Directory.Requests()
    if #requests == 0 then
        heading("requests", "Requests")
        stateLine("requests", "No one has asked the guild for anything yet.")
    else
        section("requests", "Requests", requests, chamber.requestRows, function(e)
            local bits = { (e.qty or 1) .. "x " .. SideQuest.ItemName(e.item_id) }
            if e.price then table.insert(bits, "up to " .. money(e.price)) end
            if e.note and e.note ~= "" then table.insert(bits, truncateNote(e.note, 40)) end
            return table.concat(bits, " -- ")
        end)
    end

    setScrollContentHeight(chamber.scroll, y)
end

-- Mine: the player's own sell, buy and request editor, each with a
-- Market.SuggestPrice hint next to the price field when available.

local function buildMarketEditorRow(parent, placeholderItem, extraFields, buttonText)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(540, 24)
    local itemBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    skinEditBox(itemBox, placeholderItem)
    itemBox:SetSize(140, 20)
    itemBox:SetPoint("LEFT", 8, 0) -- InputBoxTemplate's Left texture is
    -- anchored 5px outside the edit box's own frame (see
    -- InputBoxVisualTemplate in Blizzard_SharedXML/Shared/InputBox); at
    -- x=0 that bleed sits past the scroll content's left edge and the
    -- ScrollFrame clips it off, cutting the box's left border/text. An
    -- 8px gap (matching the gap used between the other fields below)
    -- keeps the whole border on-screen.
    itemBox:SetAutoFocus(false)
    acceptItemLinks(itemBox)
    row.itemBox = itemBox

    local anchor = itemBox
    row.fields = {}
    for _, field in ipairs(extraFields) do
        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        skinEditBox(box, field.placeholder)
        box:SetSize(field.width, 20)
        box:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        box:SetAutoFocus(false)
        if field.numeric then box:SetNumeric(true) end
        row.fields[field.key] = box
        anchor = box
    end

    local hintText = makeFontString(row, FONT_BODY_ITALIC, 10, C.mist2, "LEFT")
    hintText:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    row.hintText = hintText

    local addBtn = createButton(row, "primary", buttonText, 80, 20)
    addBtn:SetPoint("RIGHT", 0, 0)
    row.addBtn = addBtn
    return row
end

function UI.BuildMarketMine(panel)
    local sub = makeMarketSub(panel, "Mine")
    local chamber = createChamber(sub, "SideQuestMarketMineChamber")
    chamber:SetAllPoints(sub)

    local scroll, content = buildScroll(chamber.inner, -10)
    chamber.scroll, chamber.content = scroll, content

    -- Headings and editors are built once and repositioned every refresh
    -- (their y depends on how many rows the section above has); the list
    -- rows below each editor are pooled the same way every other dynamic
    -- list in this file is.
    local sellHeading = createSubHeading(content, "Sell")
    sellHeading:SetWidth(540)
    local sellEditor = buildMarketEditorRow(content, "Item name, link or ID", {
        { key = "price", placeholder = "Price (e.g. 1g20s)", width = 100, numeric = false },
        { key = "qty", placeholder = "Qty", width = 50, numeric = true },
    }, "Sell")
    sellEditor.addBtn:SetScript("OnClick", function()
        local itemId = parseItemInput(sellEditor.itemBox)
        local price = parsePrice(sellEditor.fields.price:GetText())
        local qty = tonumber(sellEditor.fields.qty:GetText()) or 1
        if itemId and SideQuest.Market and SideQuest.Market.SetSell then
            SideQuest.Market.SetSell(itemId, price, qty, false)
            UI.RefreshMarketMine()
        end
    end)
    sellEditor.itemBox:HookScript("OnTextChanged", function()
        local itemId = parseItemInput(sellEditor.itemBox)
        local suggestion = itemId and SideQuest.Market and SideQuest.Market.SuggestPrice and SideQuest.Market.SuggestPrice(itemId)
        sellEditor.hintText:SetText(suggestion and ("Suggested " .. money(suggestion)) or "")
    end)

    local buyHeading = createSubHeading(content, "Buy")
    buyHeading:SetWidth(540)
    local buyEditor = buildMarketEditorRow(content, "Item name, link or ID", {
        { key = "price", placeholder = "Price (e.g. 1g20s)", width = 100, numeric = false },
    }, "Buy")
    buyEditor.addBtn:SetScript("OnClick", function()
        local itemId = parseItemInput(buyEditor.itemBox)
        local price = parsePrice(buyEditor.fields.price:GetText())
        if itemId and price and SideQuest.Market and SideQuest.Market.SetBuy then
            SideQuest.Market.SetBuy(itemId, price)
            UI.RefreshMarketMine()
        end
    end)
    buyEditor.itemBox:HookScript("OnTextChanged", function()
        local itemId = parseItemInput(buyEditor.itemBox)
        local suggestion = itemId and SideQuest.Market and SideQuest.Market.SuggestPrice and SideQuest.Market.SuggestPrice(itemId)
        buyEditor.hintText:SetText(suggestion and ("Suggested " .. money(suggestion)) or "")
    end)

    local requestHeading = createSubHeading(content, "Requests")
    requestHeading:SetWidth(540)
    local requestEditor = buildMarketEditorRow(content, "Item name, link or ID", {
        { key = "qty", placeholder = "Qty", width = 40, numeric = true },
        { key = "price", placeholder = "Up to (e.g. 1g20s)", width = 100, numeric = false },
        { key = "note", placeholder = "Note (optional)", width = 140, numeric = false },
    }, "Request")
    requestEditor.addBtn:SetScript("OnClick", function()
        local itemId = parseItemInput(requestEditor.itemBox)
        local qty = tonumber(requestEditor.fields.qty:GetText()) or 1
        local price = parsePrice(requestEditor.fields.price:GetText())
        local note = requestEditor.fields.note:GetText()
        if itemId and SideQuest.Market and SideQuest.Market.AddRequest then
            SideQuest.Market.AddRequest(itemId, qty, price, note)
            UI.RefreshMarketMine()
        end
    end)

    chamber.sellHeading, chamber.sellEditor = sellHeading, sellEditor
    chamber.buyHeading, chamber.buyEditor = buyHeading, buyEditor
    chamber.requestHeading, chamber.requestEditor = requestHeading, requestEditor
    chamber.sellListRows, chamber.buyListRows, chamber.requestListRows = {}, {}, {}
    panel.mineChamber = chamber
end

--- One "item -- price/qty" editor-list row with a Remove button.
local function buildMineListRow(parent, removeFn)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(500, 18)
    row.text = makeFontString(row, FONT_BODY, 12, C.ink, "LEFT")
    row.text:SetPoint("LEFT", 0, 0)
    row.removeBtn = createButton(row, "quiet", "Remove", 66, 16)
    row.removeBtn:SetPoint("RIGHT", 0, 0)
    row.removeBtn:SetScript("OnClick", function() removeFn(row.key) end)
    return row
end

function UI.RefreshMarketMine()
    local panel = UI.panels and UI.panels.Market
    if not panel or not panel.mineChamber then
        return
    end
    local chamber = panel.mineChamber
    local mine = SideQuest.Directory and SideQuest.Directory.Get and SideQuest.Directory.Get(SideQuest.NormalizeUnit("player"))
    local marketData = mine and mine.market and mine.market.d or {}

    local y = 0
    local function section(heading, editor, list, rows, formatFn, removeFn)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", 0, -y)
        y = y + 18
        editor:ClearAllPoints()
        editor:SetPoint("TOPLEFT", 0, -y)
        y = y + 24 + 6
        for _, r in ipairs(rows) do r:Hide() end
        for i, entry in ipairs(list or {}) do
            local row = rows[i]
            if not row then
                row = buildMineListRow(chamber.content, removeFn)
                rows[i] = row
            end
            row.key = entry.item_id or entry.id
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 20, -y)
            row.text:SetText(formatFn(entry))
            row:Show()
            y = y + 18
        end
        y = y + 14
    end

    section(chamber.sellHeading, chamber.sellEditor, marketData.sell, chamber.sellListRows, function(e)
        local name = SideQuest.ItemName(e.item_id)
        return name .. " -- " .. money(e.price) .. ahSuffix(e.item_id) .. " x" .. (e.qty or 1)
    end, function(itemId)
        if SideQuest.Market and SideQuest.Market.RemoveSell then
            SideQuest.Market.RemoveSell(itemId)
            UI.RefreshMarketMine()
        end
    end)

    section(chamber.buyHeading, chamber.buyEditor, marketData.buy, chamber.buyListRows, function(e)
        local name = SideQuest.ItemName(e.item_id)
        return name .. " -- " .. money(e.price) .. ahSuffix(e.item_id)
    end, function(itemId)
        if SideQuest.Market and SideQuest.Market.RemoveBuy then
            SideQuest.Market.RemoveBuy(itemId)
            UI.RefreshMarketMine()
        end
    end)

    section(chamber.requestHeading, chamber.requestEditor, marketData.requests, chamber.requestListRows, function(e)
        local name = SideQuest.ItemName(e.item_id)
        return (e.qty or 1) .. "x " .. name .. (e.price and (" up to " .. money(e.price)) or "") .. (e.note and e.note ~= "" and (" -- " .. truncateNote(e.note, 50)) or "")
    end, function(id)
        if SideQuest.Market and SideQuest.Market.RemoveRequest then
            SideQuest.Market.RemoveRequest(id)
            UI.RefreshMarketMine()
        end
    end)

    setScrollContentHeight(chamber.scroll, y)
end

--------------------------------------------------------------------------
-- EVENTS tab: date/time, role counts, your answer, officer actions
--------------------------------------------------------------------------

function UI.BuildRaidsPanel(body)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints(body)
    panel:Hide()
    UI.panels.Raids = panel

    local chamber = createChamber(panel, "SideQuestRaidsChamber")
    chamber:SetPoint("TOPLEFT", 12, -12)
    chamber:SetPoint("BOTTOMRIGHT", -12, 12)
    createRibbon(chamber, "Events")

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
    local events = SideQuest.Events.Upcoming()
    local past = SideQuest.Events.Past()
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    chamber.pastRows = chamber.pastRows or {}
    for _, r in ipairs(chamber.pastRows) do
        r:Hide()
    end
    if not chamber.emptyText then
        chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
        chamber.emptyText:SetPoint("TOPLEFT")
        chamber.emptyText:SetWidth(500)
        chamber.emptyText:SetWordWrap(true)
    end

    local isOfficer = SideQuest.DisplayIsOfficer()
    local y = 0
    if #events == 0 then
        -- tell "nothing ever arrived" apart from a site with nothing coming up
        local text
        if SideQuest.Events.EverReceived() then
            text = "No events scheduled right now."
        elseif isOfficer then
            text = "No event data yet -- SideQuest Companion brings it in when you close WoW, for your next login, "
                .. "or paste the site's import with /sq import."
        else
            text = "No event data yet -- it comes from an officer's SideQuest while one is online."
        end
        setStateText(chamber.emptyText, text, true)
        y = 44
    else
        chamber.emptyText:SetText("")
    end
    for i, evt in ipairs(events) do
        local row = chamber.rows[i]
        if not row then
            row = createQuestLogRow(chamber.content)
            -- these rows grow downward (counts, answers, officer actions):
            -- pin the mark to the top instead of the row's middle
            row.mark:ClearAllPoints()
            row.mark:SetPoint("TOPLEFT", 2, -10)
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
        local isRoleKind = ROLE_KINDS[evt.kind] == true
        local showsOfficerActions = isOfficer and isRoleKind
        -- title..answer buttons end at 73, the officer reason line at 111
        local rowHeight = showsOfficerActions and 112 or 76
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        y = y + rowHeight + 10
        local isOpen = (evt.starts_at or 0) > now()
        row.mark:SetAtlas(isOpen and "QuestNormal" or "QuestTurnin")
        row.title:SetText(evt.title or "Event")
        row.meta:SetText((EVENT_KIND_LABELS[evt.kind] or "Event") .. "  --  " .. date("%A %b %d, %H:%M", evt.starts_at or now()))

        if isRoleKind then
            local roleCounts = { tank = 0, healer = 0, dps = 0 }
            for _, s in ipairs(evt.signups or {}) do
                if s.status == "signed" and roleCounts[s.role] ~= nil then
                    roleCounts[s.role] = roleCounts[s.role] + 1
                end
            end
            row.roleCounts:SetText(string.format("Signed: Tank %d  --  Healer %d  --  DPS %d  (%d total)",
                roleCounts.tank, roleCounts.healer, roleCounts.dps, #(evt.signups or {})))
        else
            local answerCounts = { signed = 0, tentative = 0, absent = 0 }
            for _, s in ipairs(evt.signups or {}) do
                if answerCounts[s.status] ~= nil then
                    answerCounts[s.status] = answerCounts[s.status] + 1
                end
            end
            row.roleCounts:SetText(string.format("Going %d  --  Maybe %d  --  Can't %d",
                answerCounts.signed, answerCounts.tentative, answerCounts.absent))
        end

        local _, status = SideQuest.Signups.MyState(evt.id)
        local statusToAnswer = { signed = "going", tentative = "maybe", absent = "cant" }
        local currentAnswer = statusToAnswer[status]
        for answer, btn in pairs(row.answers) do
            btn:SetScript("OnClick", function()
                SideQuest.Signups.Answer(evt.id, answer)
                UI.RefreshRaids()
            end)
            btn:SetSelected(answer == currentAnswer)
        end

        row.inviteBtn:SetShown(showsOfficerActions)
        row.placeBtn:SetShown(showsOfficerActions)
        row.officerReason:SetShown(showsOfficerActions)
        if showsOfficerActions then
            local inCombat = SideQuest.InCombat()
            local isLeader = SideQuest.IsGroupLeader()
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

    if #past > 0 then
        if not chamber.pastHeading then
            chamber.pastHeading = createSubHeading(chamber.content, "Past events")
            chamber.pastHeading:SetWidth(520)
        end
        chamber.pastHeading:ClearAllPoints()
        chamber.pastHeading:SetPoint("TOPLEFT", 0, -y)
        chamber.pastHeading:Show()
        y = y + 24
        for i, evt in ipairs(past) do
            local row = chamber.pastRows[i]
            if not row then
                row = createQuestLogRow(chamber.content)
                row.mark:SetAtlas("QuestTurnin")
                chamber.pastRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            y = y + 40
            row.title:SetText(evt.title or "Event")
            row.meta:SetText(string.format("%s  --  %s  --  Going %d, Maybe %d, Can't %d",
                EVENT_KIND_LABELS[evt.kind] or "Event", date("%a %b %d, %H:%M", evt.starts_at or now()),
                evt.going or 0, evt.maybe or 0, evt.cant or 0))
            row:Show()
        end
    elseif chamber.pastHeading then
        chamber.pastHeading:Hide()
    end
    setScrollContentHeight(chamber.scroll, y)
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
    header:SetWidth(560)
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
    headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -3)

    -- button (-30..-50), header (-62..-76), rule at -79: the list starts below it
    local scroll, content = buildScroll(chamber.inner, -84)
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
    setScrollContentHeight(chamber.scroll, (22 * (#rows + 1)) + 40 + 20 * #loot)
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
        row.meta:SetText((item.character and (displayName(item.character) .. "  ") or "") .. date("%H:%M", item.at or now()))
        row:Show()
        y = y + 32
    end
    setScrollContentHeight(chamber.scroll, y)
end

--------------------------------------------------------------------------
-- Announcement toast
--------------------------------------------------------------------------

function UI.BuildToast()
    if UI.toast then
        return UI.toast
    end
    local toast = createChamber(UIParent, "SideQuestToast")
    toast:SetSize(360, 80)
    toast:SetPoint("TOP", 0, -60)
    toast:SetFrameStrata("DIALOG")
    local ribbon = createRibbon(toast, "Announcement", 22)
    local officerText = makeFontString(toast.inner, FONT_BODY, 12, C.gold, "CENTER")
    officerText:SetPoint("TOP", 0, -10)
    local textFs = makeFontString(toast.inner, FONT_BODY_ITALIC, 14, C.flavor, "CENTER")
    textFs:SetPoint("CENTER", 0, -8)
    if textFs.SetWordWrap then
        textFs:SetWidth(300)
        textFs:SetWordWrap(true)
    end
    toast.ribbon, toast.officerText, toast.textFs = ribbon, officerText, textFs
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
        UI.PlayToastIn(toast)
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

    -- Native top tabs standing on the sub-view chamber's top edge, the way
    -- Forever's profession frames carry theirs. The selected tab names the
    -- view, so Console chambers carry no ribbon of their own.
    local CONSOLE_TAB_TOP = 30
    panel.subButtons = {}
    local prev
    for _, name in ipairs(CONSOLE_SUBTABS) do
        local btn = UI.CreatePanelTab(panel, name, true)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        else
            btn:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 26, -CONSOLE_TAB_TOP)
        end
        prev = btn
        UI.SetPanelTabSelected(btn, false)
        btn:SetScript("OnClick", function()
            UI.ShowConsoleSub(name)
        end)
        if name == "Debug" then
            btn:Hide() -- shown only for the Guild Master, see UI.RefreshOfficerVisibility
        end
        panel.subButtons[name] = btn
    end
    panel.tabTop = CONSOLE_TAB_TOP

    panel.subPanels = {}
    UI.BuildConsoleRaidNight(panel)
    UI.BuildConsoleLoot(panel)
    UI.BuildConsoleRoster(panel)
    UI.BuildConsoleRecruits(panel)
    UI.BuildConsoleBank(panel)
    UI.BuildConsoleAnnounce(panel)
    UI.BuildConsoleSync(panel)
    UI.BuildConsoleDebug(panel)
end

function UI.ShowConsoleSub(name)
    local panel = UI.panels[OFFICER_TAB]
    for subName, sub in pairs(panel.subPanels) do
        if subName == name then
            sub:Show()
            UI.PlayCrossfade(sub)
        else
            sub:Hide()
        end
    end
    for subName, btn in pairs(panel.subButtons) do
        UI.SetPanelTabSelected(btn, subName == name)
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
    elseif name == "Debug" then
        UI.RefreshConsoleDebug()
    end
end

function UI.RefreshConsole()
    if not SideQuest.DisplayIsOfficer() then
        return
    end
    UI.ShowConsoleSub(UI.panels[OFFICER_TAB].activeSub or "Raid Night")
end

local function makeConsoleSub(panel, key)
    local sub = CreateFrame("Frame", nil, panel)
    -- The chamber's top edge is the line the sub-tabs stand on.
    sub:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -panel.tabTop)
    sub:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 6)
    sub:Hide()
    panel.subPanels[key] = sub
    return sub
end

-- Raid Night: a recording control (Start/Stop, status, who else can
-- record), the numbered course (Prep, Invite, Start, each boss, Loot, End)
-- tied to the real recording state, roster presence, the standby list and
-- the auto-award log with Undo.

-- "who can record" row text: recording/ready state, or "unknown" if the
-- sender's HELLO predates the officer/recording fields.
local function knownOfficerLine(entry)
    if entry.officer == nil then
        return displayName(entry.character) .. " -- version " .. tostring(entry.version or "?") .. ", unknown"
    elseif entry.recording then
        return displayName(entry.character) .. " -- recording " .. tostring(entry.recording.instance or "a raid")
            .. " since " .. date("%H:%M", entry.recording.since or now())
    else
        return displayName(entry.character) .. " -- ready"
    end
end

function UI.BuildConsoleRaidNight(panel)
    local sub = makeConsoleSub(panel, "Raid Night")
    local chamber = createChamber(sub, "SideQuestRaidNightChamber")
    chamber:SetAllPoints(sub)

    -- Recording control lives above the scroll, like the Roster tab's
    -- Sweep button: the one action that matters most on this view, always
    -- visible. It's the only place that actually starts or stops a
    -- session; the course's Start raid/End raid steps below still award
    -- their EP but never toggle recording.
    local recordBtn = createButton(chamber.inner, "primary", "Start recording", 170, 24)
    recordBtn:SetPoint("TOPLEFT", 14, -30)
    recordBtn:SetScript("OnClick", function()
        UI.OnClickRecordButton()
    end)
    local recordStatusText = makeFontString(chamber.inner, FONT_BODY, 12, C.mist, "LEFT")
    recordStatusText:SetPoint("LEFT", recordBtn, "RIGHT", 10, 0)
    recordStatusText:SetWidth(380)
    if recordStatusText.SetWordWrap then recordStatusText:SetWordWrap(true) end
    chamber.recordBtn, chamber.recordStatusText, chamber.recordConfirmArmed = recordBtn, recordStatusText, false

    local scroll, content = buildScroll(chamber.inner, -62)
    chamber.scroll, chamber.content = scroll, content

    local whoHeading = createSubHeading(content, "Who can record")
    whoHeading:SetPoint("TOPLEFT", 0, 0)
    whoHeading:SetWidth(520)
    local whoList = CreateFrame("Frame", nil, content)
    whoList:SetPoint("TOPLEFT", whoHeading, "BOTTOMLEFT", 0, -6)
    whoList:SetPoint("TOPRIGHT", whoHeading, "BOTTOMRIGHT", 0, -6)
    chamber.whoHeading, chamber.whoList, chamber.whoRows = whoHeading, whoList, {}

    local courseHeading = createSubHeading(content, "Tonight's course")
    courseHeading:SetPoint("TOPLEFT", whoList, "BOTTOMLEFT", 0, -10)
    courseHeading:SetWidth(520)
    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", courseHeading, "BOTTOMLEFT", 0, -6)
    list:SetPoint("TOPRIGHT", courseHeading, "BOTTOMRIGHT", 0, -6)
    chamber.stepRows = {}

    local steps = {
        { key = "prep", label = "Prep -- ask the raid to report readiness", action = function()
            SideQuest.Prep.RequestCheck({})
            SideQuest.Recorder.MarkPrepDone()
        end },
        { key = "invite", label = "Invite -- bring in everyone signed", action = function()
            local evt = SideQuest.Events.Upcoming()[1]
            if evt then SideQuest.Events.InviteSigned(evt.id) end
            SideQuest.Recorder.MarkInviteDone()
        end },
        { key = "start", label = "Start raid -- on-time EP", action = function()
            SideQuest.Recorder.StartRaid()
        end },
        { key = "boss", label = "Boss -- encounters record automatically", action = nil },
        { key = "loot", label = "Loot -- open bidding from the Loot sub-view", action = function()
            UI.ShowConsoleSub("Loot")
        end },
        { key = "end", label = "End raid -- full-night EP", action = function()
            SideQuest.Recorder.EndRaid()
        end },
    }
    chamber.steps = steps
    list:SetHeight(26 * #steps)

    for i, step in ipairs(steps) do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(500, 24)
        row:SetPoint("TOPLEFT", 0, -26 * (i - 1))
        -- one number, on a chamfered metal plate tinted per state (never
        -- doubled with the label).
        local numPlate = row:CreateTexture(nil, "BACKGROUND")
        numPlate:SetSize(22, 22)
        numPlate:SetPoint("LEFT", 0, 0)
        numPlate:SetTexture(MEDIA_TEX .. "Plate")
        numPlate:SetTexCoord(0, 0.75, 0, 0.75) -- 48 px of art in a 64 px file
        numPlate:SetVertexColor(C.goldDeep[1], C.goldDeep[2], C.goldDeep[3], 1)
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
                if step.key == "loot" then
                    step.doneAt = now()
                end
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
    awardList:SetPoint("TOPRIGHT", awardHeading, "BOTTOMRIGHT", 0, -6)
    awardList:SetHeight(18 * 8) -- the newest 8 awards
    chamber.awardRows = {}

    chamber.presenceText, chamber.standbyText, chamber.awardHeading, chamber.awardList =
        presenceText, standbyText, awardHeading, awardList
    panel.raidNightChamber = chamber
end

--- Start/Stop recording click handler: delegates all the conflict/officer/
-- instance logic to Recorder.CanRecord and Recorder.StartRecording, and
-- only tracks the local "has the user clicked once already" latch for the
-- double-record confirm.
function UI.OnClickRecordButton()
    local Recorder = SideQuest.Recorder
    local panel = UI.panels[OFFICER_TAB]
    local chamber = panel and panel.raidNightChamber
    if not chamber then
        return
    end
    if Recorder.current then
        Recorder.StopRecording()
        chamber.recordConfirmArmed = false
        UI.RefreshConsoleRaidNight()
        return
    end
    local ok = Recorder.CanRecord()
    if not ok then
        return
    end
    local name, _, difficultyID, _, _, _, _, instanceID, groupSize = GetInstanceInfo()
    local session, other = Recorder.StartRecording(name, instanceID, difficultyID, groupSize, chamber.recordConfirmArmed)
    chamber.recordConfirmArmed = (session == nil and other ~= nil)
    UI.RefreshConsoleRaidNight()
end

function UI.RefreshConsoleRaidNight()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.raidNightChamber then
        return
    end
    local chamber = panel.raidNightChamber
    local Recorder = SideQuest.Recorder

    -- Recording control: status line + Start/Stop button, the only place
    -- that actually starts or stops a session.
    local canRecord, cantReason = Recorder.CanRecord()
    local instanceID = nil
    if IsInInstance and IsInInstance() then
        local _, instanceType = IsInInstance()
        if instanceType == "raid" then
            instanceID = select(8, GetInstanceInfo())
        end
    end
    if Recorder.current then
        chamber.recordConfirmArmed = false
        local raidCount = 0
        for _, status in pairs(Recorder.present) do
            if status == "raid" then raidCount = raidCount + 1 end
        end
        chamber.recordBtn:SetText("Stop recording")
        chamber.recordBtn:SetEnabled(true)
        local bosses = Recorder.EncounterCountThisSession()
        setStateText(chamber.recordStatusText, string.format("Recording %s since %s -- %d %s, %d %s",
            tostring(Recorder.current.instance_name or "raid"), date("%H:%M", Recorder.current.started_at or now()),
            bosses, bosses == 1 and "boss" or "bosses", raidCount, raidCount == 1 and "player" or "players"))
    else
        local other = Recorder.OtherRecorder(instanceID)
        if other then
            chamber.recordBtn:SetText(chamber.recordConfirmArmed and "Start anyway?"
                or (displayName(other.character) .. " is already recording"))
            chamber.recordBtn:SetEnabled(canRecord, cantReason)
            setStateText(chamber.recordStatusText, displayName(other.character) .. " is recording this raid.")
        else
            chamber.recordConfirmArmed = false
            chamber.recordBtn:SetText("Start recording")
            chamber.recordBtn:SetEnabled(canRecord, cantReason)
            setStateText(chamber.recordStatusText, canRecord and "Not recording." or cantReason, not canRecord)
        end
    end

    -- Who can record: self, plus officers heard from recently who can.
    local whoLines = {}
    if Recorder.current then
        table.insert(whoLines, "You -- recording " .. tostring(Recorder.current.instance_name or "a raid")
            .. " since " .. date("%H:%M", Recorder.current.started_at or now()))
    elseif canRecord then
        table.insert(whoLines, "You -- ready")
    else
        table.insert(whoLines, "You -- " .. cantReason)
    end
    for _, entry in ipairs(SideQuest.Prep.KnownOfficers(600)) do
        table.insert(whoLines, knownOfficerLine(entry))
    end
    for _, r in ipairs(chamber.whoRows) do r:Hide() end
    for i, line in ipairs(whoLines) do
        local row = chamber.whoRows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.whoList)
            row:SetSize(500, 18)
            row.text = makeFontString(row, FONT_BODY, 11, C.ink, "LEFT")
            row.text:SetPoint("LEFT")
            chamber.whoRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -18 * (i - 1))
        row.text:SetText(line)
        row:Show()
    end
    chamber.whoList:SetHeight(18 * #whoLines)

    -- course steps: Prep/Invite/Start raid/End raid read from the real
    -- recording state, not from a click alone; Boss and Loot are handled
    -- below the generic loop.
    local recording = Recorder.current ~= nil
    chamber.steps[1].doneAt = Recorder.prepDoneAt
    chamber.steps[2].doneAt = Recorder.inviteDoneAt
    chamber.steps[3].doneAt = Recorder.started and Recorder.startedAt or nil
    chamber.steps[6].doneAt = Recorder.ended and Recorder.endedAt or nil

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
            row.timeText:SetText(date("%H:%M", step.doneAt))
            row.label:SetTextColor(C.mist2[1], C.mist2[2], C.mist2[3], 1)
            row.numPlate:SetVertexColor(C.stone[1], C.stone[2], C.stone[3], 1)
            row.num:Hide() -- the seal stands in for the number once a step is done
            if row.btn then
                row.btn:SetText("Done")
                row.btn:Disable()
            end
            if not row.seal then
                -- the one authored moment: a wax seal bearing the crest
                -- stamps onto the plate the first time this step is seen
                -- done; it is never replayed on later refreshes, and the
                -- seal itself (not an animation) is what persists.
                row.seal = UI.StampWaxSeal(row, "CENTER", row.numPlate, "CENTER", 0, 0, true)
            end
        elseif i == current then
            row.timeText:SetText("In progress")
            row.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3], 1)
            row.numPlate:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
            row.num:Show()
        else
            row.timeText:SetText("")
            row.label:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
            row.numPlate:SetVertexColor(C.goldDeep[1], C.goldDeep[2], C.goldDeep[3], 1)
            row.num:Show()
        end
        if row.btn and not step.doneAt and (step.key == "start" or step.key == "end") then
            row.btn:SetEnabled(recording, "Start recording first")
        end
        if step.key == "boss" then
            row.timeText:SetText(Recorder.EncounterCountThisSession() .. " recorded")
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

    -- a standby player is usually in both lists (the standby roster and the recorder's presence), so list each once
    local standbyNames, seen = {}, {}
    local function addStandby(name)
        if not seen[name] then
            seen[name] = true
            table.insert(standbyNames, name)
        end
    end
    for _, char in ipairs(SideQuestDB.standby or {}) do
        addStandby(displayName(char))
    end
    for _, n in ipairs(standbyFromPresent) do
        addStandby(n)
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
    -- who-can-record, course, presence and standby above the award log, then one line per award
    setScrollContentHeight(chamber.scroll, 330 + 18 * #whoLines + 18 * shown)
end

-- Council award: officers pick the winner, item, its kind (contract:
-- chase, legendary = legendary/special/rare, tier = crafted tier) and a
-- required one-line reason, independent of the ranked bid table above
-- (council items are never auto-ranked -- Loot.GroupFor drops them).
local COUNCIL_KINDS = { { "chase", "Chase" }, { "legendary", "Legendary" }, { "tier", "Tier" } }
local COUNCIL_TIER_SLOTS = {
    { "INVTYPE_HEAD", "Head" }, { "INVTYPE_SHOULDER", "Shoulder" }, { "INVTYPE_CHEST", "Chest" },
    { "INVTYPE_HAND", "Hands" }, { "INVTYPE_LEGS", "Legs" },
}

--- Recompute the council-award form's GP preview and the Award button's
-- enabled state from whatever is currently typed/selected. Called after
-- every edit so Award stays disabled until item, winner, kind (and slot,
-- for tier) and a 1-200 char reason are all present.
local function refreshCouncilAward(chamber)
    for _, kind in ipairs(COUNCIL_KINDS) do
        chamber.councilKindButtons[kind[1]]:SetSelected(chamber.councilKind == kind[1])
    end
    local showSlots = chamber.councilKind == "tier"
    for _, slot in ipairs(COUNCIL_TIER_SLOTS) do
        local btn = chamber.councilSlotButtons[slot[1]]
        btn:SetShown(showSlots)
        btn:SetSelected(showSlots and chamber.councilSlot == slot[1])
    end

    local itemId = parseItemInput(chamber.councilItemBox)
    local info = itemId and resolveItemInfo(tostring(itemId)) or nil
    local reason = chamber.councilReasonBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
    local winner = chamber.councilWinnerBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")

    local gp
    if info and chamber.councilKind then
        if chamber.councilKind == "chase" then
            gp = SideQuest.Rules.ComputeGP(info.equipLoc, "council", { isChase = true })
        elseif chamber.councilKind == "legendary" then
            gp = SideQuest.Rules.ComputeGP(info.equipLoc, "council", { isLegendary = true })
        elseif chamber.councilKind == "tier" and chamber.councilSlot then
            gp = SideQuest.Rules.ComputeGP(info.equipLoc, "council",
                { isTierToken = true, tierSlotInvType = chamber.councilSlot })
        end
    end
    chamber.councilGpText:SetText(gp and ("GP " .. gp) or "")

    local valid = itemId ~= nil and winner ~= "" and chamber.councilKind ~= nil
        and (chamber.councilKind ~= "tier" or chamber.councilSlot ~= nil)
        and reason ~= "" and #reason <= 200
    chamber.councilAwardBtn:SetEnabled(valid,
        "Pick the item, winner, kind (and slot for tier), and write a one-line reason.")
    chamber.councilValid = valid
end

-- Loot sub-view: the item up for bid (icon, quality-colour name, slot, GP
-- cost), each response ranked per contract order with PR/EP columns and
-- a per-row Award button, plus Close bidding and the time left.
function UI.BuildConsoleLoot(panel)
    local sub = makeConsoleSub(panel, "Loot")
    local chamber = createChamber(sub, "SideQuestConsoleLootChamber")
    chamber:SetAllPoints(sub)

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
    local iconSwatch = chamber.inner:CreateTexture(nil, "OVERLAY")
    iconSwatch:SetSize(34, 34)
    iconSwatch:SetPoint("TOPLEFT", openLootBtn, "BOTTOMLEFT", 0, -10)
    iconSwatch:SetTexture(MEDIA_TEX .. "IconFrame")
    local icon = chamber.inner:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("CENTER", iconSwatch, "CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local itemText = makeFontString(chamber.inner, FONT_DISPLAY, 13, C.ink, "LEFT")
    itemText:SetPoint("TOPLEFT", iconSwatch, "TOPRIGHT", 10, -2)
    local slotGpText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist, "LEFT")
    slotGpText:SetPoint("TOPLEFT", itemText, "BOTTOMLEFT", 0, -4)
    local timeLeftText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist2, "LEFT")
    timeLeftText:SetPoint("TOPLEFT", slotGpText, "BOTTOMLEFT", 0, -2)

    local header = CreateFrame("Frame", nil, chamber.inner)
    header:SetPoint("TOPLEFT", timeLeftText, "BOTTOMLEFT", 0, -10)
    header:SetSize(530, 14)
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
    -- reserve the chamber's bottom strip for the council-award form below
    scroll:SetPoint("BOTTOMRIGHT", -24, 172)
    chamber.scroll, chamber.content, chamber.bidRows = scroll, content, {}
    chamber.iconSwatch, chamber.icon, chamber.itemText, chamber.slotGpText, chamber.timeLeftText =
        iconSwatch, icon, itemText, slotGpText, timeLeftText

    -- Council award: a self-contained form (not tied to the ranked bid
    -- table, since council responses are never auto-ranked) pinned to the
    -- chamber's bottom strip so it never collides with however tall the
    -- bid list grows.
    local councilHeading = createSubHeading(chamber.inner, "Council award")
    councilHeading:SetPoint("BOTTOMLEFT", chamber.inner, "BOTTOMLEFT", 14, 148)
    councilHeading:SetWidth(700)

    local councilItemBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    councilItemBox:SetSize(150, 20)
    councilItemBox:SetPoint("TOPLEFT", councilHeading, "BOTTOMLEFT", 0, -8)
    councilItemBox:SetAutoFocus(false)
    skinEditBox(councilItemBox, "Item name, link or ID")
    acceptItemLinks(councilItemBox)

    local councilWinnerBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    councilWinnerBox:SetSize(140, 20)
    councilWinnerBox:SetPoint("LEFT", councilItemBox, "RIGHT", 8, 0)
    councilWinnerBox:SetAutoFocus(false)
    councilWinnerBox:SetMaxLetters(64)
    skinEditBox(councilWinnerBox, "Winner's character name")

    local councilKindButtons = {}
    local prevKindBtn
    for _, kind in ipairs(COUNCIL_KINDS) do
        local btn = createButton(chamber.inner, "quiet", kind[2], 70, 20)
        if prevKindBtn then
            btn:SetPoint("LEFT", prevKindBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("LEFT", councilWinnerBox, "RIGHT", 8, 0)
        end
        councilKindButtons[kind[1]] = btn
        prevKindBtn = btn
    end

    local councilSlotButtons = {}
    local prevSlotBtn
    for _, slot in ipairs(COUNCIL_TIER_SLOTS) do
        local btn = createButton(chamber.inner, "quiet", slot[2], 62, 18)
        if prevSlotBtn then
            btn:SetPoint("LEFT", prevSlotBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", councilItemBox, "BOTTOMLEFT", 0, -8)
        end
        councilSlotButtons[slot[1]] = btn
        prevSlotBtn = btn
    end

    local councilReasonBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    councilReasonBox:SetSize(280, 20)
    councilReasonBox:SetPoint("TOPLEFT", councilItemBox, "BOTTOMLEFT", 0, -36)
    councilReasonBox:SetAutoFocus(false)
    councilReasonBox:SetMaxLetters(200)
    skinEditBox(councilReasonBox, "Reason (required, posted to #loot-log)")

    local councilGpText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist, "LEFT")
    councilGpText:SetPoint("LEFT", councilReasonBox, "RIGHT", 10, 0)

    local councilAwardBtn = createButton(chamber.inner, "primary", "Award by council", 150, 22)
    councilAwardBtn:SetPoint("LEFT", councilGpText, "RIGHT", 10, 0)

    chamber.councilItemBox, chamber.councilWinnerBox, chamber.councilReasonBox = councilItemBox, councilWinnerBox, councilReasonBox
    chamber.councilGpText, chamber.councilAwardBtn = councilGpText, councilAwardBtn
    chamber.councilKindButtons, chamber.councilSlotButtons = councilKindButtons, councilSlotButtons

    councilItemBox:SetScript("OnTextChanged", function() refreshCouncilAward(chamber) end)
    councilWinnerBox:SetScript("OnTextChanged", function() refreshCouncilAward(chamber) end)
    councilReasonBox:SetScript("OnTextChanged", function() refreshCouncilAward(chamber) end)
    for _, kind in ipairs(COUNCIL_KINDS) do
        councilKindButtons[kind[1]]:SetScript("OnClick", function()
            chamber.councilKind = kind[1]
            if kind[1] ~= "tier" then
                chamber.councilSlot = nil
            end
            refreshCouncilAward(chamber)
        end)
    end
    for _, slot in ipairs(COUNCIL_TIER_SLOTS) do
        councilSlotButtons[slot[1]]:SetScript("OnClick", function()
            chamber.councilSlot = slot[1]
            refreshCouncilAward(chamber)
        end)
    end
    councilAwardBtn:SetScript("OnClick", function()
        if not chamber.councilValid then
            return
        end
        local itemId = parseItemInput(councilItemBox)
        local info = resolveItemInfo(tostring(itemId))
        local trimmedWinner = councilWinnerBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        local winner = SideQuest.NormalizeName(trimmedWinner)
        local reason = councilReasonBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        local gpOpts = { councilKind = chamber.councilKind, councilReason = reason }
        if chamber.councilKind == "chase" then
            gpOpts.isChase = true
        elseif chamber.councilKind == "legendary" then
            gpOpts.isLegendary = true
        elseif chamber.councilKind == "tier" then
            gpOpts.isTierToken = true
            gpOpts.tierSlotInvType = chamber.councilSlot
        end
        local lootId = SideQuest.Loot.AwardLoot(
            { item_id = itemId, item_name = info.name, quality = info.quality, inv_type = info.equipLoc },
            winner, "council", nil, nil, gpOpts)
        if lootId then
            councilItemBox:SetText("")
            councilWinnerBox:SetText("")
            councilReasonBox:SetText("")
            chamber.councilKind = nil
            chamber.councilSlot = nil
            refreshCouncilAward(chamber)
        end
    end)

    panel.lootChamber = chamber
    refreshCouncilAward(chamber)
end

function UI.RefreshBidRanking(bid)
    local panel = UI.panels and UI.panels[OFFICER_TAB]
    if not panel or not panel.lootChamber then
        return
    end
    local chamber = panel.lootChamber
    refreshCouncilAward(chamber)
    bid = bid or SideQuest.Loot.activeBid
    for _, r in ipairs(chamber.bidRows) do
        r:Hide()
    end
    if not bid then
        chamber.iconSwatch:SetVertexColor(C.mist2[1], C.mist2[2], C.mist2[3], 0.6)
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
    chamber.iconSwatch:SetVertexColor(qColor[1], qColor[2], qColor[3], 1)
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
    setScrollContentHeight(chamber.scroll, 22 * #ranked)
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

    local sweepBtn = createButton(chamber.inner, "primary", "Read roster now", 160, 22)
    sweepBtn:SetPoint("TOPLEFT", 14, -30)
    sweepBtn:SetScript("OnClick", function()
        SideQuest.Roster.Sweep()
        UI.RefreshConsoleRoster()
    end)

    local sweepHint = makeFontString(chamber.inner, FONT_BODY_ITALIC, 10, C.mist2, "LEFT")
    sweepHint:SetPoint("TOPLEFT", sweepBtn, "BOTTOMLEFT", 0, -4)
    sweepHint:SetText("Reads the guild roster now and sends it with the next sync. Removes no one.")

    local scroll, content = buildScroll(chamber.inner, -78)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    chamber.sweepBtn, chamber.sweepHint = sweepBtn, sweepHint
    panel.rosterChamber = chamber
end

function UI.RefreshConsoleRoster()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.rosterChamber then
        return
    end
    local chamber = panel.rosterChamber
    local inactive = SideQuestDB.officerData.inactive or {}
    local unseen = SideQuestDB.officerData.unseen or {}
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
        setStateText(chamber.inactiveEmpty, "No one has been away more than 14 days.", true)
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
        local levelPart = m.level and (" -- level " .. tostring(m.level)) or ""
        local lastSeenPart = m.last_seen_at
            and (" -- last seen " .. date("%Y-%m-%d", m.last_seen_at))
            or " -- no login on record"
        local lastRaidPart = m.last_raid_at and (", last raid " .. date("%Y-%m-%d", m.last_raid_at)) or ""
        row.text:SetText(m.name .. levelPart .. lastSeenPart .. lastRaidPart)
        row.rankBtn:SetScript("OnClick", function()
            SideQuest.Recruits.AddNote(m.name, "Rank suggestion: demote for inactivity")
        end)
        row:Show()
        y = y + 22
    end
    if not chamber.unseenText then
        chamber.unseenText = makeFontString(chamber.content, FONT_BODY, 11, C.mist2, "LEFT")
    end
    chamber.unseenText:ClearAllPoints()
    chamber.unseenText:SetPoint("TOPLEFT", 0, -y)
    if #unseen == 1 then
        chamber.unseenText:SetText("1 member has no login on record yet.")
        y = y + 20
    elseif #unseen > 1 then
        chamber.unseenText:SetText(#unseen .. " members have no login on record yet.")
        y = y + 20
    else
        chamber.unseenText:SetText("")
    end
    setScrollContentHeight(chamber.scroll, y)
end

-- Recruits sub-view: applicants/trials, checklist, votes, and an add-recruit
-- form. Recruits are officer-only data, shared with other officers over
-- OFFICER and with the site's Officers page via the next export.
local RECRUIT_STATUSES = { "applicant", "trial", "accepted", "declined" }

local function nextRecruitStatus(status)
    for i, s in ipairs(RECRUIT_STATUSES) do
        if s == status then
            return RECRUIT_STATUSES[(i % #RECRUIT_STATUSES) + 1]
        end
    end
    return RECRUIT_STATUSES[1]
end

-- Prefill the add-recruit name/class from the current target, if it's a
-- player not already on the guild roster. UnitExists/UnitIsPlayer/UnitName/
-- UnitClass can all read as secret on Forever, so every value runs through
-- SQ.Unsecret before use.
local function targetRecruitPrefill()
    if not (UnitExists and SideQuest.Unsecret(UnitExists("target"))) then
        return nil
    end
    if not (UnitIsPlayer and SideQuest.Unsecret(UnitIsPlayer("target"))) then
        return nil
    end
    local character = SideQuest.NormalizeUnit("target")
    if not character then
        return nil
    end
    for _, m in ipairs((SideQuestDB.roster and SideQuestDB.roster.members) or {}) do
        if m.character == character then
            return nil -- already in the guild
        end
    end
    local class = UnitClass and SideQuest.Unsecret(select(2, UnitClass("target")))
    return character, class
end

function UI.BuildConsoleRecruits(panel)
    local sub = makeConsoleSub(panel, "Recruits")
    local chamber = createChamber(sub, "SideQuestConsoleRecruitsChamber")
    chamber:SetAllPoints(sub)

    local introLine1 = makeFontString(chamber.inner, FONT_BODY, 11, C.mist, "LEFT")
    introLine1:SetPoint("TOPLEFT", 14, -10)
    introLine1:SetText("Track applicants and trials: tick the checklist and vote on each.")
    local introLine2 = makeFontString(chamber.inner, FONT_BODY, 11, C.mist, "LEFT")
    introLine2:SetPoint("TOPLEFT", introLine1, "BOTTOMLEFT", 0, -2)
    introLine2:SetText("Shared with every officer, and with the site's Officers page.")

    local addHeading = createSubHeading(chamber.inner, "Add recruit")
    addHeading:SetPoint("TOPLEFT", introLine2, "BOTTOMLEFT", 0, -10)
    addHeading:SetWidth(540)

    local nameBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    nameBox:SetSize(150, 20)
    nameBox:SetPoint("TOPLEFT", addHeading, "BOTTOMLEFT", 0, -8)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(64)
    skinEditBox(nameBox, "Character name")
    nameBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput then
            chamber.nameEdited = true
        end
    end)

    local noteBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    noteBox:SetSize(250, 20)
    noteBox:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(500)
    skinEditBox(noteBox, "Note (optional)")

    local addBtn = createButton(chamber.inner, "primary", "Add", 76, 20)
    addBtn:SetPoint("LEFT", noteBox, "RIGHT", 8, 0)
    addBtn:SetScript("OnClick", function()
        local raw = nameBox:GetText()
        local class = nil
        if chamber.prefillCharacter and raw and SideQuest.NormalizeName(raw) == chamber.prefillCharacter then
            class = chamber.prefillClass
        end
        local recruit, err = SideQuest.Recruits.AddCandidate(raw, class, noteBox:GetText())
        if recruit then
            nameBox:SetText("")
            noteBox:SetText("")
            chamber.nameEdited = false
            UI.RefreshConsoleRecruits()
        elseif err then
            SideQuest.Print(err)
        end
    end)

    chamber.nameBox, chamber.noteBox, chamber.addBtn = nameBox, noteBox, addBtn

    local scroll, content = buildScroll(chamber.inner, -96)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    panel.recruitsChamber = chamber
end

function UI.RefreshConsoleRecruits()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.recruitsChamber then
        return
    end
    local chamber = panel.recruitsChamber
    local isOfficer = SideQuest.DisplayIsOfficer()
    chamber.addBtn:SetEnabled(isOfficer, "Only officers can add recruits.")

    if not chamber.nameEdited and chamber.nameBox:GetText() == "" then
        local character, class = targetRecruitPrefill()
        chamber.prefillCharacter, chamber.prefillClass = character, class
        if character then
            chamber.nameBox:SetText(character)
        end
    end

    local recruits = SideQuest.Recruits.List()
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if #recruits == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "No recruits yet. Add one above, or on the site's Officers page.", true)
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
            row.statusBtn = createButton(row, "quiet", "", 84, 18)
            -- votes sit in the recruit's own row, next to their status --
            -- never pinned to the row's far edge, well clear of the name.
            row.yesBtn = createButton(row, "quiet", "Yes", 44, 18)
            row.noBtn = createButton(row, "quiet", "No", 44, 18)
            row.checks = {}
            for ci, def in ipairs(CHECK_DEFS) do
                -- an empty box until done, then the box with its check: the
                -- state reads by shape, never by colour alone
                local box = row:CreateTexture(nil, "ARTWORK")
                box:SetSize(14, 14)
                box:SetPoint("TOPLEFT", row.nameRow, "BOTTOMLEFT", (ci - 1) * 96, -6)
                box:SetAtlas("checkbox-minimal")
                local tick = row:CreateTexture(nil, "OVERLAY")
                tick:SetSize(14, 14)
                tick:SetPoint("CENTER", box, "CENTER")
                tick:SetAtlas("checkmark-minimal")
                local label = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
                label:SetPoint("LEFT", box, "RIGHT", 5, 0)
                label:SetText(def.label)
                row.checks[def.key] = { tick = tick, label = label }
            end
            row.votesText = makeFontString(row, FONT_BODY, 11, C.mist2, "LEFT")
            row.votesText:SetPoint("TOPLEFT", row.nameRow, "BOTTOMLEFT", 0, -28)
            chamber.rows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -58 * (i - 1))
        setNameRow(row.nameRow, r.character, r.class)
        row.statusBtn:ClearAllPoints()
        row.statusBtn:SetPoint("LEFT", row.nameRow, "RIGHT", 10, 0)
        row.statusBtn:SetText("(" .. (r.status or "applicant") .. ")")
        row.statusBtn:SetEnabled(isOfficer, "Only officers can change a recruit's status.")
        row.statusBtn:SetScript("OnClick", function()
            SideQuest.Recruits.SetStatus(r.id, nextRecruitStatus(r.status or "applicant"))
            UI.RefreshConsoleRecruits()
        end)
        row.yesBtn:ClearAllPoints()
        row.yesBtn:SetPoint("LEFT", row.statusBtn, "RIGHT", 14, 0)
        row.noBtn:ClearAllPoints()
        row.noBtn:SetPoint("LEFT", row.yesBtn, "RIGHT", 6, 0)
        for key, ui in pairs(row.checks) do
            local checked = r.checklist and r.checklist[key]
            ui.tick:SetShown(checked and true or false)
            local col = checked and C.ink or C.mist2
            ui.label:SetTextColor(col[1], col[2], col[3], 1)
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
    setScrollContentHeight(chamber.scroll, 58 * #recruits)
end

-- Bank ledger sub-view
function UI.BuildConsoleBank(panel)
    local sub = makeConsoleSub(panel, "Bank")
    local chamber = createChamber(sub, "SideQuestConsoleBankChamber")
    chamber:SetAllPoints(sub)

    local captureBtn = createButton(chamber.inner, "primary", "Capture bank log", 150, 22)
    captureBtn:SetPoint("TOPLEFT", 14, -30)
    captureBtn:SetScript("OnClick", function()
        SideQuest.Bank.RequestCapture()
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
    elseif #rows == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "Open the guild bank to read its log; rows appear here automatically.", true)
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
    setScrollContentHeight(chamber.scroll, 20 * #rows)
end

-- Announce sub-view: compose -> toast + guild chat + queued for Discord,
-- plus a recent list of what's already gone out.
function UI.BuildConsoleAnnounce(panel)
    local sub = makeConsoleSub(panel, "Announce")
    local chamber = createChamber(sub, "SideQuestConsoleAnnounceChamber")
    chamber:SetAllPoints(sub)

    local editBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    editBox:SetSize(400, 20)
    editBox:SetPoint("TOPLEFT", 14, -30)
    editBox:SetAutoFocus(false)
    skinEditBox(editBox, "Announcement text")

    local discordCheck = createCheckbox(chamber.inner, 16)
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
    recentList:SetPoint("TOPRIGHT", recentHeading, "BOTTOMRIGHT", 0, -6)
    recentList:SetHeight(18 * 5) -- the newest 5 posts
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
        row:SetText("\"" .. item.text .. "\"  --  " .. date("%m/%d %H:%M", item.at or now())
            .. (item.discord and "  (Discord queued)" or ""))
        row:Show()
    end
end

-- Sync sub-view: export/import, last sync, pending counts per section
function UI.BuildConsoleSync(panel)
    local sub = makeConsoleSub(panel, "Sync")
    local chamber = createChamber(sub, "SideQuestConsoleSyncChamber")
    chamber:SetAllPoints(sub)

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

    local editBox = CreateFrame("EditBox", nil, chamber.inner, "InputBoxTemplate")
    editBox:SetSize(500, 20)
    editBox:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -10)
    editBox:SetAutoFocus(false)
    skinEditBox(editBox, "Paste import text")

    local importResult = makeFontString(chamber.inner, FONT_BODY, 11, C.mist, "LEFT")
    importResult:SetPoint("LEFT", importBtn, "RIGHT", 12, 0)
    importResult:SetWidth(240)
    chamber.importResult = importResult

    -- Import applies whatever is pasted in the box; with nothing pasted it
    -- just puts the cursor there.
    local function runImport()
        local text = (editBox:GetText() or ""):match("^%s*(.-)%s*$")
        if text == "" or text:sub(1, 5) == "SQX1:" then
            editBox:SetText("")
            editBox:SetFocus()
            setStateText(importResult, "Paste the site's import text in the box, then click Import.", false)
            return
        end
        if SideQuest.Sync.ImportString(text) then
            editBox:SetText("")
            editBox:ClearFocus()
            setStateText(importResult, "Imported.", false)
        else
            setStateText(importResult, "That isn't a SideQuest import -- see chat for why.", true)
        end
        UI.RefreshConsoleSync()
    end
    importBtn:SetScript("OnClick", runImport)
    editBox:SetScript("OnEnterPressed", runImport)

    local syncHelpText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist2, "LEFT")
    syncHelpText:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -10)
    syncHelpText:SetWidth(520)
    if syncHelpText.SetWordWrap then syncHelpText:SetWordWrap(true) end
    syncHelpText:SetText("SideQuest Companion uploads Export on its own after /reload or logout, and loads "
        .. "the site's latest Import the next time you log in -- nothing to paste. Without it, paste Export above "
        .. "on sidequest-guild.com/officers/sync/, then paste the site's Import text above or with /sq import.")
    chamber.syncHelpText = syncHelpText

    local pendingHeading = createSubHeading(chamber.inner, "Pending (not yet exported)")
    pendingHeading:SetPoint("TOPLEFT", syncHelpText, "BOTTOMLEFT", 0, -14)
    pendingHeading:SetWidth(520)

    -- two labelled columns instead of one long "--"-joined line.
    local PENDING_KEYS = {
        { key = "sessions", label = "Sessions" }, { key = "encounters", label = "Encounters" },
        { key = "loot", label = "Loot" }, { key = "awards", label = "Awards" },
        { key = "professions", label = "Professions" }, { key = "signups", label = "Signups" },
        { key = "bank", label = "Bank" }, { key = "announcements", label = "Announcements" },
        { key = "recruits", label = "Recruits" }, { key = "member_notes", label = "Member notes" },
        { key = "battlegrounds", label = "Battlegrounds" }, { key = "roster", label = "Roster" },
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

    -- Guild calendar: one change per click, since the game only adds calendar events inside a click.
    local calendarHeading = createSubHeading(chamber.inner, "Guild calendar")
    calendarHeading:SetPoint("TOPLEFT", pendingGrid, "BOTTOMLEFT", 0, -14)
    calendarHeading:SetWidth(520)
    local calendarBtn = createButton(chamber.inner, "quiet", "Update calendar", 140, 22)
    calendarBtn:SetPoint("TOPLEFT", calendarHeading, "BOTTOMLEFT", 0, -8)
    calendarBtn:SetScript("OnClick", function()
        StaticPopup_Hide("SIDEQUEST_CALENDAR_PENDING")
        SideQuest.Calendar.Step()
    end)
    local calendarText = makeFontString(chamber.inner, FONT_BODY, 11, C.mist2, "LEFT")
    calendarText:SetPoint("LEFT", calendarBtn, "RIGHT", 10, 0)
    calendarText:SetWidth(370)

    chamber.pendingHeading, chamber.editBox, chamber.importBtn = pendingHeading, editBox, importBtn
    chamber.calendarBtn, chamber.calendarText = calendarBtn, calendarText
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
        chamber.lastSyncText:SetText("Site data from: " .. date("%Y-%m-%d %H:%M", at))
    else
        setStateText(chamber.lastSyncText, "No site data imported yet.", true)
    end
    local p = SideQuestDB.pending
    for i, def in ipairs(chamber.pendingKeys) do
        local cell = chamber.pendingCells[i]
        local count = def.key == "roster" and (p.roster and 1 or 0) or #(p[def.key] or {})
        cell.label:SetText(trackedCaps(def.label))
        cell.value:SetText(tostring(count))
    end
    UI.RefreshConsoleCalendar()
end

--- The Sync tab's guild calendar row: how many changes the next clicks will make, or why it can't run.
function UI.RefreshConsoleCalendar()
    local panel = UI.panels[OFFICER_TAB]
    local chamber = panel and panel.syncChamber
    if not chamber then
        return
    end
    local Calendar = SideQuest.Calendar
    Calendar.Request()
    local actions, reason = Calendar.Plan()
    if not actions then
        chamber.calendarBtn:SetEnabled(false, reason)
        setStateText(chamber.calendarText, reason, Calendar.loaded)
        return
    end
    local adds, removes = 0, 0
    for _, a in ipairs(actions) do
        if a.op == "add" then adds = adds + 1 else removes = removes + 1 end
    end
    if #actions == 0 then
        if #SideQuest.Events.Upcoming() == 0 then
            chamber.calendarBtn:SetEnabled(false, "No upcoming site events.")
            setStateText(chamber.calendarText, SideQuest.Events.EverReceived()
                and "The site has no events in the next 14 days. Schedule one there and SideQuest Companion "
                    .. "brings it in after you next close WoW."
                or "No site data yet. SideQuest Companion brings it in when you close WoW, for your next login.",
                true)
        else
            chamber.calendarBtn:SetEnabled(false, "Nothing to change.")
            setStateText(chamber.calendarText, "Matches the site's events.")
        end
        return
    end
    local parts = {}
    if adds > 0 then parts[#parts + 1] = adds .. " to add" end
    if removes > 0 then parts[#parts + 1] = removes .. " to take off" end
    local summary = table.concat(parts, ", ")
    if Calendar.IsBusy() then
        chamber.calendarBtn:SetEnabled(false, "The calendar is saving the last change.")
        setStateText(chamber.calendarText, summary .. ". Saving the last change...")
        return
    end
    chamber.calendarBtn:SetEnabled(true)
    setStateText(chamber.calendarText, summary .. ". One change per click.")
end

--- Debug sub-view (Guild Master only, see UI.RefreshOfficerVisibility):
-- ADDON_ACTION_BLOCKED/FORBIDDEN events and swallowed handler errors
-- (SQ.LogDebug, Core.lua), newest first, a Clear button, a read-only Copy
-- box holding the full text, and "View as" preview buttons.
function UI.BuildConsoleDebug(panel)
    local sub = makeConsoleSub(panel, "Debug")
    local chamber = createChamber(sub, "SideQuestConsoleDebugChamber")
    chamber:SetAllPoints(sub)

    local clearBtn = createButton(chamber.inner, "quiet", "Clear", 80, 22)
    clearBtn:SetPoint("TOPLEFT", 14, -30)
    clearBtn:SetScript("OnClick", function()
        SideQuestDB.debug = { log = {} }
        UI.RefreshConsoleDebug()
    end)

    local viewAsLabel = makeFontString(chamber.inner, FONT_DISPLAY, 11, C.gold, "LEFT")
    viewAsLabel:SetPoint("LEFT", clearBtn, "RIGHT", 16, 0)
    viewAsLabel:SetText(trackedCaps("View as"))

    local viewAsButtons = {}
    local prevBtn = nil
    for _, role in ipairs(VIEW_AS_ROLES) do
        local btn = createButton(chamber.inner, "quiet", VIEW_AS_LABEL[role], 90, 22)
        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
        else
            btn:SetPoint("LEFT", viewAsLabel, "RIGHT", 10, 0)
        end
        btn:SetScript("OnClick", function()
            SideQuest.SetViewAs(role)
        end)
        viewAsButtons[role] = btn
        prevBtn = btn
    end
    chamber.viewAsButtons = viewAsButtons

    local copyLabel = makeFontString(chamber.inner, FONT_DISPLAY, 11, C.gold, "LEFT")
    copyLabel:SetPoint("TOPLEFT", clearBtn, "BOTTOMLEFT", 0, -14)
    copyLabel:SetText(trackedCaps("Copy"))

    local copyBox = createLinkBox(chamber.inner, "")
    copyBox:SetSize(540, 20)
    copyBox:SetPoint("TOPLEFT", copyLabel, "BOTTOMLEFT", 0, -4)
    chamber.copyBox = copyBox

    local scroll, content = buildScroll(chamber.inner, -112)
    chamber.scroll, chamber.content, chamber.rows = scroll, content, {}
    chamber.clearBtn = clearBtn
    panel.debugChamber = chamber
end

function UI.RefreshConsoleDebug()
    local panel = UI.panels[OFFICER_TAB]
    if not panel or not panel.debugChamber then
        return
    end
    local chamber = panel.debugChamber
    local log = (SideQuestDB.debug and SideQuestDB.debug.log) or {}
    for _, r in ipairs(chamber.rows) do
        r:Hide()
    end
    if #log == 0 then
        if not chamber.emptyText then
            chamber.emptyText = makeFontString(chamber.content, FONT_BODY, 12, C.mist2, "LEFT")
            chamber.emptyText:SetPoint("TOPLEFT")
        end
        setStateText(chamber.emptyText, "Nothing logged yet.", true)
    elseif chamber.emptyText then
        chamber.emptyText:SetText("")
    end
    local lines = {}
    for i, e in ipairs(log) do
        local when = date and date("%Y-%m-%d %H:%M:%S", e.at or 0) or tostring(e.at or 0)
        local what, stack
        if e.kind == "blocked" then
            -- the game already names it with "()"; the stack recorded by
            -- older versions was only SideQuest's own event handler, so skip it
            local func = e.func or "?"
            what = func .. (func:find("%)$") and "" or "()") .. " (" .. (e.event or "?") .. ")"
        else
            what = (e.event or "?") .. ": " .. (e.message or "?")
            stack = e.stack
        end
        local firstStackLine = stack and stack:match("[^\n]+")
        local summary = when .. "  [" .. e.kind .. "]  " .. what .. (firstStackLine and ("  -- " .. firstStackLine) or "")
        local row = chamber.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, chamber.content)
            row:SetSize(560, 16)
            row.text = makeFontString(row, FONT_BODY, 11, C.ink, "LEFT")
            row.text:SetPoint("LEFT")
            chamber.rows[i] = row
        end
        row:SetPoint("TOPLEFT", 0, -16 * (i - 1))
        row.text:SetText(summary)
        row:Show()
        table.insert(lines, summary .. (stack and ("\n" .. stack) or ""))
    end
    setScrollContentHeight(chamber.scroll, 16 * #log)
    chamber.copyBox:SetLinkText(table.concat(lines, "\n\n"))
    for role, btn in pairs(chamber.viewAsButtons) do
        btn:SetSelected(SideQuest.ViewAs() == role)
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
    SideQuest.Print("You're in a raid instance. Click Start recording on the Console's Raid Night tab, or type /sq record, to start recording tonight.")
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

SideQuest.On("SQ_VIEW_AS_CHANGED", function()
    UI.RefreshViewAs()
end)

SideQuest.On("SQ_STANDINGS_UPDATED", function()
    if UI.activeTab == "You" then UI.RefreshYou() end
    if UI.activeTab == "Ledger" then UI.RefreshLedger() end
end)

SideQuest.On("SQ_EVENTS_UPDATED", function()
    if UI.activeTab == "You" then UI.RefreshYou() end
    if UI.activeTab == "Raids" then UI.RefreshRaids() end
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

SideQuest.On("SQ_BANK_CAPTURED", function()
    if UI.activeTab == OFFICER_TAB then UI.RefreshConsoleBank() end
end)

local function refreshCalendarRow()
    local panel = UI.panels and UI.panels[OFFICER_TAB]
    if UI.activeTab == OFFICER_TAB and panel and panel.activeSub == "Sync" then
        UI.RefreshConsoleCalendar()
    end
end
SideQuest.On("SQ_CALENDAR_CHANGED", refreshCalendarRow)
SideQuest.On("SQ_IMPORT_APPLIED", refreshCalendarRow)

SideQuest.On("SQ_PREP_ANSWER", function() end) -- surfaced via the Raid Night step buttons' tooltips in-game

-- The directory updates constantly (every received DIR_R/DIR_L section);
-- debounce to at most one refresh every 2 s, and only for whichever
-- directory-backed tab is actually open.
local directoryRefreshPending = false
SideQuest.On("SQ_DIRECTORY_UPDATED", function()
    if directoryRefreshPending then
        return
    end
    directoryRefreshPending = true
    local function run()
        directoryRefreshPending = false
        if not UI.main or not UI.main:IsShown() then
            return
        end
        if UI.activeTab == "Crafters" then
            UI.RefreshCrafters()
        elseif UI.activeTab == "Market" then
            UI.RefreshMarket()
        elseif UI.activeTab == "Guild" then
            UI.RefreshGuild()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(2, run)
    else
        run()
    end
end)

return UI
