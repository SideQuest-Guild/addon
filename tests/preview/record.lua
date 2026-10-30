#!/usr/bin/env luajit
-- tests/preview/record.lua
-- Builds the real SideQuest UI under the WoW API stub with synthetic,
-- labelled demo data, resolves every visible frame's WoW anchors
-- (SetPoint/SetAllPoints/SetSize) into absolute CSS pixel rects, and
-- emits one static HTML page per view (tab, console sub-view, the bid
-- popup, the announcement toast) at the default size and at UI scale
-- 0.64. This is a LAYOUT CHECK, not a pixel-identical render of the
-- game: see tests/preview/README.md.

local SCRIPT_DIR = arg and arg[0] and arg[0]:match("(.*/)") or "./"
local ROOT = SCRIPT_DIR .. "../../"
local OUT_DIR = SCRIPT_DIR .. "out/"
os.execute("mkdir -p " .. OUT_DIR)

dofile(ROOT .. "tests/wowstub.lua")

--------------------------------------------------------------------------
-- 1. Patch the stub's generic method dispatch to also record every call
--    (SetPoint, SetAllPoints, SetSize, SetScale, texture/font setters,
--    SetEnabled, ...) into a per-object `__geo` log, keyed by method.
--------------------------------------------------------------------------

local origIndex = WowStub.FrameMeta.__index
WowStub.FrameMeta.__index = function(t, k)
    local fn = origIndex(t, k)
    if not fn then
        return nil
    end
    return function(self, ...)
        self.__geo = self.__geo or {}
        self.__geo[#self.__geo + 1] = { method = k, args = { ... } }
        return fn(self, ...)
    end
end

--------------------------------------------------------------------------
-- 2. Load the addon under the patched stub.
--------------------------------------------------------------------------

local ADDON_FILES = {
    "SideQuest/Libs/Json.lua", "SideQuest/Libs/Base64.lua", "SideQuest/Core.lua", "SideQuest/Rules.lua",
    "SideQuest/Codec.lua", "SideQuest/Comm.lua", "SideQuest/Recorder.lua", "SideQuest/Loot.lua",
    "SideQuest/Standings.lua", "SideQuest/Events.lua", "SideQuest/Roster.lua", "SideQuest/Professions.lua",
    "SideQuest/News.lua", "SideQuest/Signups.lua", "SideQuest/Sheet.lua", "SideQuest/Crafters.lua",
    "SideQuest/Announce.lua", "SideQuest/Recruits.lua", "SideQuest/Bank.lua", "SideQuest/Prep.lua",
    "SideQuest/Sync.lua", "SideQuest/UI/Main.lua", "SideQuest/UI/BidPopup.lua",
}
for _, f in ipairs(ADDON_FILES) do
    dofile(ROOT .. f)
end
SideQuest.InitDB()

--------------------------------------------------------------------------
-- 3. Synthetic, labelled demo data (PRODUCT.md: no real roster/kills/loot
--    exist yet; preview data must be synthetic and labelled so).
--------------------------------------------------------------------------

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local RANKS = { "Guild Master", "Officer", "Raider", "Member", "Trial" }

local function demoName(i)
    return "Demo" .. i
end

WowStub.realm = "Whitemane"
WowStub.guildName = "SideQuest"
WowStub.isOfficer = true
WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-DEMO0001" })
WowStub.time = 1793500000

-- 20-person guild roster sweep + public import members
local ZONES = { "Ironforge", "Stormwind", "Darnassus" }
local rosterMembers, publicMembers = {}, {}
for i = 1, 20 do
    local class = CLASSES[((i - 1) % #CLASSES) + 1]
    local online = i <= 9
    table.insert(rosterMembers, {
        character = demoName(i) .. "-Whitemane", rank = RANKS[((i - 1) % #RANKS) + 1], rank_index = ((i - 1) % 5),
        level = 30, class = class, zone = online and ZONES[((i - 1) % #ZONES) + 1] or nil, online = online,
        last_online_hours = online and 0 or (i * 3),
    })
    local characters = { { name = demoName(i) .. "-Whitemane", class = class, level = 30, is_main = true } }
    if i == 1 then
        -- demonstrate an alt on the player's own member row (You tab "N alt(s)")
        table.insert(characters, { name = "Demo1Alt-Whitemane", class = "MAGE", level = 30, is_main = false })
    end
    table.insert(publicMembers, {
        member_id = i, name = "Demo Member " .. i, main = demoName(i) .. "-Whitemane", class = class,
        rank = RANKS[((i - 1) % #RANKS) + 1], raid_status = i <= 15 and "raider" or "trial",
        guild_ep = 100 + i * 5, attendance_rate = 0.8, events_attended = 10,
        badges = i == 1 and { { id = "first-blood", name = "First Blood" } } or {},
        characters = characters,
    })
end
SideQuestDB.roster = { taken_at = WowStub.time, members = rosterMembers }
SideQuestDB.guild.generated_at = WowStub.time - 2 * 3600
SideQuestDB.guild.members = publicMembers

-- standings (PR with rank context)
local standingsRows = {}
for i = 1, 20 do
    table.insert(standingsRows, {
        member_id = i, name = "Demo Member " .. i, main = demoName(i) .. "-Whitemane",
        class = CLASSES[((i - 1) % #CLASSES) + 1], characters = { demoName(i) .. "-Whitemane" },
        ep = 200 - i * 4, gp = 150, pr = (200 - i * 4) / 150, trial = i > 15,
    })
end
SideQuestDB.standings = { generated_at = WowStub.time, rules = nil, rows = standingsRows }

-- my sheet (4-week EP/GP history table + loot log)
SideQuest.Sheet.lastAnswer = {
    found = true, member_id = 1,
    ledger = {
        { at = WowStub.time - 3 * 24 * 3600, kind = "ep", amount = 20, reason = "boss_kill", note = "Demo Boss (week 1)" },
        { at = WowStub.time - 3 * 24 * 3600, kind = "gp", amount = 100, reason = "loot", note = "Demo Glory of the Defender" },
        { at = WowStub.time - 9 * 24 * 3600, kind = "ep", amount = 15, reason = "progress", note = "Demo Boss (week 2)" },
        { at = WowStub.time - 16 * 24 * 3600, kind = "ep", amount = 10, reason = "on_time", note = "week 3" },
        { at = WowStub.time - 23 * 24 * 3600, kind = "ep", amount = 25, reason = "full_night", note = "week 4" },
    },
    loot = {
        { at = WowStub.time - 3 * 24 * 3600, item_id = 30896, item_name = "Demo Glory of the Defender", quality = 4, gp = 100, response = "ms" },
        { at = WowStub.time - 9 * 24 * 3600, item_id = 2, item_name = "Demo Mistake Band", quality = 2, gp = 55, response = "os" },
    },
}

-- next raid event, mid-course, with sign-ups (role-balanced, for the Raids tab's role counts)
SideQuestDB.events = {
    { id = "2b3c4d5e-6f70-4a1b-9c2d-3e4f5a6b7c8e", title = "Demo Raid Night: Hyjal Summit", kind = "raid", starts_at = WowStub.time + 2 * 3600, size = 20, signups = {
        { character = "Demo2", class = "WARRIOR", role = "tank", status = "signed", group = 1 },
        { character = "Demo6", class = "SHAMAN", role = "tank", status = "signed", group = 1 },
        { character = "Demo3", class = "PRIEST", role = "healer", status = "signed", group = 1 },
        { character = "Demo4", class = "MAGE", role = "dps", status = "signed", group = 2 },
        { character = "Demo5", class = "ROGUE", role = "dps", status = "signed", group = 2 },
        { character = "Demo7", class = "HUNTER", role = "dps", status = "signed", group = 2 },
        { character = "Demo8", class = "WARLOCK", role = "dps", status = "tentative", group = nil },
    } },
}
SideQuestDB.mySignups["2b3c4d5e-6f70-4a1b-9c2d-3e4f5a6b7c8e"] = { status = "signed", sentAt = WowStub.time, acked = true }

-- news feed (boss kill, loot, announcement, level, joined, badge -- spread
-- across two days so the News tab's day grouping has more than one group)
SideQuestDB.guild.news = {
    { id = "n1", at = WowStub.time - 1800, kind = "boss_kill", text = "Demo Boss defeated (Hyjal Summit)", character = "Demo2-Whitemane" },
    { id = "n2", at = WowStub.time - 3600, kind = "loot", text = "Demo Glory of the Defender awarded", character = "Demo1-Whitemane", item_id = 30896, quality = 4 },
    { id = "n3", at = WowStub.time - 5400, kind = "announcement", text = "Flasks for Friday please", character = "Demo1-Whitemane" },
    { id = "n4", at = WowStub.time - 90000, kind = "level", text = "Demo7 reached level 30", character = "Demo7-Whitemane" },
    { id = "n5", at = WowStub.time - 95000, kind = "joined", text = "Demo7 joined the guild", character = "Demo7-Whitemane" },
    { id = "n6", at = WowStub.time - 100000, kind = "badge", text = "Demo1 earned First Blood", character = "Demo1-Whitemane" },
}

-- crafters directory results (shape matches Crafters.lua's actual answer:
-- character -> { profession, skill, recipes = {id,name}, online }, never
-- the old-fixture-only "offline"/"results" sub-table)
SideQuest.Crafters.results = {
    ["Demo4-Whitemane"] = { character = "Demo4-Whitemane", profession = "Blacksmithing", skill = 150, online = true,
        recipes = { { id = 1, name = "Demo Copper Chain Pants" } } },
    ["Demo6-Whitemane"] = { character = "Demo6-Whitemane", profession = "Blacksmithing", skill = 120, online = true,
        recipes = { { id = 1, name = "Demo Copper Chain Pants" } } },
    ["Demo9-Whitemane"] = { character = "Demo9-Whitemane", profession = "Tailoring", skill = 140, online = false,
        recipes = {} },
}

-- a recruit, with checklist + a vote
SideQuestDB.officerData.recruits = {
    { id = "r1", character = "DemoRecruit-Whitemane", class = "MAGE", status = "trial", note = "Found in LFG",
      checklist = { talked = true, gear_check = true, first_raid = false, vouched = false },
      votes = { { officer = "Demo1-Whitemane", vote = "yes", at = WowStub.time } }, at = WowStub.time },
}
SideQuestDB.pending.bank = {
    { id = "b1", at = WowStub.time, character = "Demo5-Whitemane", kind = "deposit", item_id = 1, item_name = "Demo Linen Cloth", count = 20, money = 0, tab = 1 },
}
SideQuestDB.pending.announcements = {
    { id = "ann-demo-1", text = "Flasks for Friday please", officer = "Demo1-Whitemane", at = WowStub.time - 5400, discord = true },
}
SideQuestDB.officerData.inactive = {
    { member_id = 18, name = "Demo Member 18", last_seen_at = WowStub.time - 20 * 24 * 3600, last_raid_at = WowStub.time - 30 * 24 * 3600 },
}

-- bid popup demo item: a chest piece, so main-spec GP should compute to
-- 100 (regression check for the "Estimated GP: 0" bug -- see BidPopup.lua)
WowStub.items = WowStub.items or {}
WowStub.items[30896] = {
    itemId = 30896, name = "Demo Glory of the Defender", quality = 4, equipLoc = "INVTYPE_CHEST",
    icon = "Interface\\Icons\\INV_Chest_Plate04", itemType = "Armor", itemSubType = "Plate", classID = 4, subclassID = 4,
}

--------------------------------------------------------------------------
-- 4. Anchor resolver: walk WowStub.frames (creation order) and compute
--    an absolute CSS rect (left, top, width, height, in pixels, origin
--    top-left) for every object, from its recorded SetPoint/SetAllPoints/
--    SetSize calls. WoW's y-offset convention (positive = up) is negated
--    to CSS's (positive = down); anchor point fractions (TOPLEFT=0,0 ...
--    BOTTOMRIGHT=1,1) are identical in both, since they name physical
--    edges, not axis direction.
--------------------------------------------------------------------------

local FRAC = {
    TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}

local resolved = {} -- obj -> { left, top, width, height }

local function lastCallsOf(obj, method)
    local out = {}
    for _, call in ipairs(obj.__geo or {}) do
        if call.method == method then
            out[#out + 1] = call.args
        end
    end
    return out
end

--- Current SetPoint anchors for `obj`, honoring call order: a later
-- SetPoint for the same corner replaces the earlier one, and a
-- ClearAllPoints call drops every anchor recorded before it. Without this,
-- re-anchoring a frame after creation (e.g. buildScroll()'s default
-- TOPLEFT/BOTTOMRIGHT followed by a ClearAllPoints + repositioned
-- TOPLEFT/BOTTOMRIGHT, as GuildNow's news scroll does to sit under its
-- sub-heading) left both the stale and fresh anchors in play; resolveRect
-- picked the first (stale) one for position, so the news feed rendered at
-- its pre-move spot, overlapping the online list above it.
local function currentAnchors(obj)
    local byPoint, order = {}, {}
    for _, call in ipairs(obj.__geo or {}) do
        if call.method == "ClearAllPoints" then
            byPoint, order = {}, {}
        elseif call.method == "SetPoint" then
            local point = call.args[1]
            if not byPoint[point] then
                order[#order + 1] = point
            end
            byPoint[point] = call.args
        end
    end
    local out = {}
    for _, point in ipairs(order) do
        out[#out + 1] = byPoint[point]
    end
    return out
end

local function normalizePoint(obj, args)
    local point, a2, a3, a4, a5 = args[1], args[2], args[3], args[4], args[5]
    local relativeTo, relativePoint, x, y
    if type(a2) == "table" then
        relativeTo = a2
        if type(a3) == "string" then
            relativePoint, x, y = a3, a4 or 0, a5 or 0
        else
            relativePoint, x, y = point, a3 or 0, a4 or 0
        end
    else
        relativeTo = obj.__parent
        if type(a2) == "string" then
            relativePoint, x, y = a2, a3 or 0, a4 or 0
        else
            relativePoint, x, y = point, a2 or 0, a3 or 0
        end
    end
    return point, relativeTo, relativePoint, x, y
end

local function resolveRect(obj) -- memoized, recursive on relativeTo/parent (creation order makes this safe)
    if resolved[obj] then
        return resolved[obj]
    end
    if obj.__name == "UIParent" then
        resolved[obj] = { left = 0, top = 0, width = 1280, height = 800 }
        return resolved[obj]
    end

    -- explicit size wins: SetSize, or SetWidth/SetHeight independently
    local width, height
    for _, args in ipairs(lastCallsOf(obj, "SetSize")) do
        width, height = args[1], args[2]
    end
    for _, args in ipairs(lastCallsOf(obj, "SetWidth")) do
        width = args[1]
    end
    for _, args in ipairs(lastCallsOf(obj, "SetHeight")) do
        height = args[1]
    end

    -- SetAllPoints: copy the target's rect outright
    local allPoints = lastCallsOf(obj, "SetAllPoints")
    if #allPoints > 0 then
        local target = allPoints[#allPoints][1]
        if type(target) == "table" then
            local r = resolveRect(target)
            resolved[obj] = { left = r.left, top = r.top, width = r.width, height = r.height }
            return resolved[obj]
        end
    end

    local points = currentAnchors(obj)
    local anchors = {}
    for _, args in ipairs(points) do
        local point, relativeTo, relativePoint, x, y = normalizePoint(obj, args)
        relativeTo = relativeTo or obj.__parent
        if relativeTo and FRAC[point] and FRAC[relativePoint] then
            local r = resolveRect(relativeTo)
            local fx, fy = FRAC[point][1], FRAC[point][2]
            local rfx, rfy = FRAC[relativePoint][1], FRAC[relativePoint][2]
            local absX = r.left + rfx * r.width + x
            local absY = r.top + rfy * r.height - y -- negate WoW's up-positive y offset
            table.insert(anchors, { fx = fx, fy = fy, absX = absX, absY = absY })
        end
    end

    if not width or not height then
        local minFx, maxFx, minFy, maxFy, atMinFx, atMaxFx, atMinFy, atMaxFy
        for _, a in ipairs(anchors) do
            if not minFx or a.fx < minFx then minFx, atMinFx = a.fx, a.absX end
            if not maxFx or a.fx > maxFx then maxFx, atMaxFx = a.fx, a.absX end
            if not minFy or a.fy < minFy then minFy, atMinFy = a.fy, a.absY end
            if not maxFy or a.fy > maxFy then maxFy, atMaxFy = a.fy, a.absY end
        end
        if not width and minFx and maxFx and minFx ~= maxFx then
            width = (atMaxFx - atMinFx) / (maxFx - minFx)
        end
        if not height and minFy and maxFy and minFy ~= maxFy then
            height = (atMaxFy - atMinFy) / (maxFy - minFy)
        end
    end

    -- fontstrings/textures with no size info size themselves to content
    -- (best-effort estimate: real average glyph advance for the shipped
    -- serif body/display fonts is closer to ~0.56em than a flat 7px, so a
    -- short name anchored next to a following fontstring -- e.g. the name
    -- row's "Demo" followed by its class word -- was estimated narrower
    -- than the font actually renders it, and the next element's anchor
    -- landed on top of the real (wider) text instead of beside it).
    if not width or not height then
        if obj.__kind == "FontString" then
            local text = obj.GetText and obj.GetText() or ""
            -- codepoints, not bytes: tracked-caps headings join every
            -- glyph with a 3-byte U+2009 thin space, which inflated #text
            -- (a byte count) far past the actual glyph count and pushed
            -- anything anchored off a heading's RIGHT edge (e.g. a
            -- sub-heading's fading line) well past where the text ends.
            local _, codepoints = text:gsub("[^\128-\191]", "")
            local fontCalls = lastCallsOf(obj, "SetFont")
            local fontSize = (#fontCalls > 0 and fontCalls[#fontCalls][2]) or 13
            width = width or math.max(10, codepoints * fontSize * 0.56)
            height = height or 14
        else
            width = width or 10
            height = height or 10
        end
    end

    -- Position each axis from whichever anchor actually pins it: an edge
    -- anchor (fx/fy 0 or 1, e.g. RIGHT) always wins over a center anchor
    -- (fx/fy 0.5, e.g. TOP/BOTTOM, which only pin the other axis) on that
    -- axis -- matching real WoW, where a TOP+BOTTOM+RIGHT anchor combo
    -- (stretch vertically, pin horizontally to the right edge, as the
    -- scrollbar track does against its ScrollFrame) positions from RIGHT
    -- on X, not from TOP's implied center. Without this the first anchor
    -- in call order won both axes, so the track rendered at the stretch
    -- anchor's horizontal center instead of the chamber's right edge.
    local function pickAxis(frac)
        local best, bestIsEdge
        for _, a in ipairs(anchors) do
            local f = a[frac]
            local isEdge = (f == 0 or f == 1)
            if not best or (isEdge and not bestIsEdge) then
                best, bestIsEdge = a, isEdge
            end
        end
        return best
    end
    local left, top
    local ax, ay = pickAxis("fx"), pickAxis("fy")
    if ax then
        left = ax.absX - ax.fx * width
    elseif obj.__parent then
        left = resolveRect(obj.__parent).left
    else
        left = 0
    end
    if ay then
        top = ay.absY - ay.fy * height
    elseif obj.__parent then
        top = resolveRect(obj.__parent).top
    else
        top = 0
    end

    resolved[obj] = { left = left, top = top, width = width, height = height, anchor = anchors[1] }
    return resolved[obj]
end

--------------------------------------------------------------------------
-- 5. HTML emission
--------------------------------------------------------------------------

local MEDIA_TTF = {
    ["LibertinusSerifDisplay"] = { file = "LibertinusSerifDisplay.ttf", css = "SQ Display" },
    ["EBGaramond"] = { file = "EBGaramond.ttf", css = "SQ Body" },
    ["EBGaramond-Italic"] = { file = "EBGaramond-Italic.ttf", css = "SQ Body Italic" },
}

local function fontCssName(wowPath)
    for key, info in pairs(MEDIA_TTF) do
        if wowPath and wowPath:find(key, 1, true) then
            return info.css
        end
    end
    return "SQ Body"
end

local function textureCssUrl(wowPath)
    if not wowPath then
        return nil
    end
    local name = wowPath:match("([^\\]+)$")
    if not name then
        return nil
    end
    return "../tex/" .. name .. ".png"
end

local function lastColorOf(obj)
    for name, set in pairs({ SetColorTexture = true, SetVertexColor = true }) do
        local calls = lastCallsOf(obj, name)
        if #calls > 0 then
            local a = calls[#calls]
            return a[1], a[2], a[3], a[4] or 1
        end
    end
    return nil
end

local function esc(s)
    s = tostring(s or "")
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

--- Collect every visible (IsShown) descendant of `root`, in creation order.
local function visibleDescendants(root)
    local list = {}
    for _, entry in ipairs(WowStub.frames) do
        local obj = entry.frame
        local anc = obj
        local ok = (obj == root)
        while anc and anc.__parent do
            anc = anc.__parent
            if anc == root then
                ok = true
                break
            end
        end
        if ok and obj ~= root then
            -- every ancestor up to root must be shown
            local visible = obj.IsShown and obj.IsShown()
            local p = obj.__parent
            while visible and p and p ~= root do
                visible = p.IsShown and p.IsShown()
                p = p.__parent
            end
            if visible then
                table.insert(list, obj)
            end
        end
    end
    return list
end

local function anchoredStyle(r, rootRect, stageWidth)
    -- Horizontal/vertical placement using the object's own first anchor
    -- fraction, so right- and center-anchored text (freshness line, ribbon
    -- labels, ...) is positioned precisely instead of guessing a pixel
    -- width for text whose real width only the browser's font metrics know.
    local anchor = r.anchor
    local fx = anchor and anchor.fx or 0
    local fy = anchor and anchor.fy or 0
    local transforms = {}
    local parts = {}
    if fx >= 1 then
        table.insert(parts, string.format("right:%.1fpx;", stageWidth - (anchor.absX - rootRect.left)))
    elseif fx > 0 then
        table.insert(parts, string.format("left:%.1fpx;", anchor.absX - rootRect.left))
        table.insert(transforms, "translateX(-50%)")
    else
        table.insert(parts, string.format("left:%.1fpx;", r.left - rootRect.left))
    end
    if fy > 0 and fy < 1 and anchor then
        table.insert(parts, string.format("top:%.1fpx;", anchor.absY - rootRect.top))
        table.insert(transforms, "translateY(-50%)")
    else
        table.insert(parts, string.format("top:%.1fpx;", r.top - rootRect.top))
    end
    if #transforms > 0 then
        table.insert(parts, "transform:" .. table.concat(transforms, " ") .. ";")
    end
    return table.concat(parts)
end

--- Nearest ancestor ScrollFrame of `obj`, or nil. WoW ScrollFrames always
-- clip their scroll child to the frame's own rect; buildScroll() in
-- Main.lua parents every list's rows under one, so this is how the
-- renderer finds what to clip rows to (finding: lists must clip/scroll
-- instead of running under the tab bar).
local function findScrollAncestor(obj)
    local p = obj.__parent
    while p do
        if p.__kind == "ScrollFrame" then
            return p
        end
        p = p.__parent
    end
    return nil
end

--- CSS clip-path insets (in px, relative to `r`'s own box) that clip `r`
-- to `clipRect`, both already in the same absolute coordinate space
-- resolveRect() produces. Over-clipping (insets summing past the box's
-- own size) just renders nothing, which is correct for rows scrolled
-- fully out of view.
local function clipPathFor(r, clipRect)
    local insetTop = math.max(0, clipRect.top - r.top)
    local insetLeft = math.max(0, clipRect.left - r.left)
    local insetRight = math.max(0, (r.left + r.width) - (clipRect.left + clipRect.width))
    local insetBottom = math.max(0, (r.top + r.height) - (clipRect.top + clipRect.height))
    if insetTop == 0 and insetLeft == 0 and insetRight == 0 and insetBottom == 0 then
        return ""
    end
    return string.format("clip-path:inset(%.1fpx %.1fpx %.1fpx %.1fpx);", insetTop, insetRight, insetBottom, insetLeft)
end

local function emitView(name, root, width, height, scale)
    local body = {}
    local fontsUsed = {}
    local rootRect = resolveRect(root)
    -- a font must still be legible once the whole stage is scaled down to
    -- 0.64; clamp every FontString's effective rendered size to at least
    -- MIN_RENDERED_PX post-scale rather than letting it shrink linearly.
    local MIN_RENDERED_PX = 8
    for _, obj in ipairs(visibleDescendants(root)) do
        local r = resolveRect(obj)
        local style
        if obj.__kind == "FontString" then
            style = "position:absolute;" .. anchoredStyle(r, rootRect, width)
        else
            style = string.format(
                "position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;",
                r.left - rootRect.left, r.top - rootRect.top, r.width, r.height)
        end
        local scrollAncestor = findScrollAncestor(obj)
        if scrollAncestor then
            style = style .. clipPathFor(r, resolveRect(scrollAncestor))
        end
        if obj.__kind == "Texture" then
            local tex = lastCallsOf(obj, "SetTexture")
            local url = #tex > 0 and type(tex[#tex][1]) == "string" and textureCssUrl(tex[#tex][1]) or nil
            if url then
                style = style .. "background-image:url('" .. url .. "');background-size:100% 100%;"
            else
                local cr, cg, cb, ca = lastColorOf(obj)
                if cr then
                    style = style .. string.format("background-color:rgba(%d,%d,%d,%.2f);",
                        math.floor(cr * 255), math.floor(cg * 255), math.floor(cb * 255), ca)
                end
            end
            table.insert(body, string.format('<div class="r tex" style="%s"></div>', style))
        elseif obj.__kind == "FontString" then
            local fontCalls = lastCallsOf(obj, "SetFont")
            local fontFile, fontSize = nil, 13
            if #fontCalls > 0 then
                fontFile, fontSize = fontCalls[#fontCalls][1], fontCalls[#fontCalls][2] or 13
            end
            if scale < 1 and fontSize * scale < MIN_RENDERED_PX then
                fontSize = MIN_RENDERED_PX / scale
            end
            local cssFont = fontCssName(fontFile)
            fontsUsed[cssFont] = true
            local colorCalls = lastCallsOf(obj, "SetTextColor")
            local cr, cg, cb, ca = 0.95, 0.94, 0.91, 1
            if #colorCalls > 0 then
                local a = colorCalls[#colorCalls]
                cr, cg, cb, ca = a[1] or cr, a[2] or cg, a[3] or cb, a[4] or 1
            end
            style = style .. string.format(
                "font-family:'%s';font-size:%.1fpx;color:rgba(%d,%d,%d,%.2f);" ..
                "font-variant-numeric:tabular-nums;white-space:pre;overflow:visible;",
                cssFont, fontSize, math.floor(cr * 255), math.floor(cg * 255), math.floor(cb * 255), ca)
            local text = obj.GetText and obj.GetText() or ""
            table.insert(body, string.format('<div class="r fs" style="%s">%s</div>', style, esc(text)))
        else
            -- Button (and any other) frames store their label via SetText
            -- directly on the object in this stub (no child FontString the
            -- way a real UIPanelButtonTemplate routes it); render it so
            -- every control's label is checkable here even though the
            -- template's own button-face chrome still isn't reproduced.
            local btnText = obj.GetText and obj.GetText()
            if btnText and btnText ~= "" then
                fontsUsed["SQ Body"] = true
                style = style .. "display:flex;align-items:center;justify-content:center;" ..
                    "font-family:'SQ Body';font-size:11px;color:#c4cddd;overflow:hidden;white-space:nowrap;"
                table.insert(body, string.format('<div class="r frame" style="%s">%s</div>', style, esc(btnText)))
            else
                table.insert(body, string.format('<div class="r frame" style="%s"></div>', style))
            end
        end
    end

    local fontFaces = {}
    for _, info in pairs(MEDIA_TTF) do
        if fontsUsed[info.css] then
            table.insert(fontFaces, string.format(
                "@font-face { font-family: '%s'; src: url('../fonts/%s'); }", info.css, info.file))
        end
    end

    local html = string.format([[<!doctype html>
<html><head><meta charset="utf-8"><title>%s</title>
<style>
%s
html, body { margin: 0; background: #05070c; }
.stage { position: relative; width: %dpx; height: %dpx; transform: scale(%s); transform-origin: top left; overflow: hidden; }
.r { box-sizing: border-box; }
.footer { font: 11px sans-serif; color: #889; background: #000c; padding: 6px 10px; max-width: 640px; }
</style></head>
<body>
<div class="stage">
%s
</div>
<div class="footer">SideQuest layout preview -- %s @ %dx%d, UI scale %s. Layout check only, not pixel-identical
to the game (stock Blizzard template chrome -- button borders, the scroll frame's native up/down arrow buttons,
close-button texture -- is not rendered; list clipping and the themed scrollbar track/thumb are). Headings/body
text use the shipped EB Garamond / Libertinus Serif Display TTFs (OFL); the game's default Friz Quadrata is
proprietary and is not reproduced here.</div>
</body></html>]],
        esc(name), table.concat(fontFaces, "\n"), width, height, tostring(scale), table.concat(body, "\n"),
        esc(name), width, height, tostring(scale))

    local path = OUT_DIR:gsub("out/$", "") .. "html/" .. name .. ".html"
    os.execute("mkdir -p " .. (OUT_DIR:gsub("out/$", "") .. "html"))
    local fh = io.open(path, "w")
    fh:write(html)
    fh:close()
    print("wrote " .. path)
end

--------------------------------------------------------------------------
-- 6. Build the UI and render every required view at both scales.
--------------------------------------------------------------------------

local UI = SideQuest.UI
UI.Show() -- out of combat, builds + shows

-- an open bid, responses ranked per contract order (ms raider/trial > os > alt)
SideQuest.Loot.activeBid = {
    itemLink = "item:30896:Demo Glory of the Defender", startedAt = WowStub.time - 10, timeout = 30,
    responses = { ["Demo2-Whitemane"] = "ms", ["Demo4-Whitemane"] = "ms", ["Demo6-Whitemane"] = "os", ["Demo9-Whitemane"] = "alt" },
}

local VIEWS = {
    { name = "you", setup = function() UI.ShowTab("You") end },
    { name = "guild", setup = function() UI.ShowTab("Guild") end },
    { name = "crafters", setup = function() UI.ShowTab("Crafters") end },
    { name = "raids", setup = function() UI.ShowTab("Raids") end },
    { name = "ledger", setup = function() UI.ShowTab("Ledger") end },
    { name = "news", setup = function() UI.ShowTab("News") end },
    { name = "console-raid-night", setup = function() UI.ShowTab("Console"); UI.ShowConsoleSub("Raid Night") end },
    { name = "console-loot", setup = function() UI.ShowTab("Console"); UI.ShowConsoleSub("Loot") end },
    { name = "console-roster", setup = function() UI.ShowTab("Console"); UI.ShowConsoleSub("Roster") end },
    { name = "console-recruits", setup = function() UI.ShowTab("Console"); UI.ShowConsoleSub("Recruits") end },
    { name = "console-bank", setup = function() UI.ShowTab("Console"); UI.ShowConsoleSub("Bank") end },
    { name = "console-announce", setup = function() UI.ShowTab("Console"); UI.ShowConsoleSub("Announce") end },
    { name = "console-sync", setup = function() UI.ShowTab("Console"); UI.ShowConsoleSub("Sync") end },
}

local ALL_NAMES = {}
local function emit(name, root, w, h, scale)
    resolved = {}
    emitView(name, root, w, h, scale)
    table.insert(ALL_NAMES, name)
end

for _, view in ipairs(VIEWS) do
    view.setup()
    if view.name == "console-raid-night" then
        local chamber = UI.panels.Console.raidNightChamber
        chamber.steps[1].doneAt = WowStub.time - 1800
        chamber.steps[2].doneAt = WowStub.time - 1500
        chamber.steps[3].doneAt = WowStub.time - 1200
        SideQuest.Recorder.present = {
            ["Demo2-Whitemane"] = "raid", ["Demo3-Whitemane"] = "raid", ["Demo4-Whitemane"] = "raid",
            ["Demo6-Whitemane"] = "standby",
        }
        SideQuestDB.standby = { "Demo6-Whitemane" }
        SideQuestDB.pending.awards = {
            { id = "aw1", kind = "ep", character = "Demo2-Whitemane", amount = 10, reason = "boss_kill", note = "Demo Boss", at = WowStub.time - 1200, voided = false },
            { id = "aw2", kind = "ep", character = "Demo3-Whitemane", amount = 5, reason = "on_time", at = WowStub.time - 1700, voided = false },
            { id = "aw3", kind = "gp", character = "Demo1-Whitemane", amount = 100, reason = "loot", note = "Demo Glory of the Defender", loot_id = "l1", at = WowStub.time - 900, voided = true },
        }
        UI.RefreshConsoleRaidNight()
    end
    emit(view.name, UI.main, 860, 560, 1)
    emit(view.name .. "-064", UI.main, 860, 560, 0.64)
end

-- bid popup (own top-level frame, not a main-window tab)
UI.ShowBidPopup("item:30896:Demo Glory of the Defender", 30)
emit("bidpopup", UI.bidPopup, 320, 220, 1)
emit("bidpopup-064", UI.bidPopup, 320, 220, 0.64)

-- announcement toast
SideQuest.Fire("SQ_ANNOUNCEMENT_RECEIVED", { officer = "Demo1-Whitemane", text = "Demo announcement: flasks for Friday please" })
emit("toast", UI.toast, 360, 56, 1)
emit("toast-064", UI.toast, 360, 56, 0.64)

local galleryItems = {}
for _, n in ipairs(ALL_NAMES) do
    table.insert(galleryItems, string.format(
        '<a href="html/%s.html" target="preview"><div class="thumb">%s</div></a>', n, n))
end
local indexHtml = string.format([[<!doctype html>
<html><head><meta charset="utf-8"><title>SideQuest preview gallery</title>
<style>
body { margin: 0; background: #0a0f1a; color: #c4cddd; font: 13px sans-serif; display: flex; height: 100vh; }
nav { width: 220px; overflow-y: auto; padding: 10px; border-right: 1px solid #333; }
nav a { display: block; color: #d8ab5c; text-decoration: none; padding: 4px 0; }
nav a:hover { color: #fff; }
iframe { flex: 1; border: 0; background: #000; }
</style></head>
<body>
<nav>%s</nav>
<iframe name="preview" src="html/%s.html"></iframe>
</body></html>]], table.concat(galleryItems, "\n"), ALL_NAMES[1])
local fh = io.open(SCRIPT_DIR .. "index.html", "w")
fh:write(indexHtml)
fh:close()

print("Preview HTML generation complete: " .. #ALL_NAMES .. " views.")
