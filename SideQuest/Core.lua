-- SideQuest/Core.lua
-- SavedVariables defaults + migrations, lightweight event dispatcher, slash
-- commands, name normalization, record id generation, officer detection and
-- Midnight "secret value" guards.

SideQuest = SideQuest or {}
local SQ = SideQuest

SQ.ADDON_NAME = "SideQuest"
SQ.ADDON_VERSION = "1.0.0" -- stamped literally; packager replaces @project-version@ in the .toc, not here
SQ.CURRENT_DB_VERSION = 3

--------------------------------------------------------------------------
-- SavedVariables defaults + migrations
--------------------------------------------------------------------------

local function defaultDB()
    return {
        version = SQ.CURRENT_DB_VERSION,
        seq = 0,
        lastExport = "",
        pending = {
            sessions = {},
            encounters = {},
            loot = {},
            awards = {},
            -- v2 sections (contract v2): accumulate here, cleared by /sq export clear
            -- like v1 pending.
            roster = nil, -- { taken_at, members = {}, ranks = nil|{} } single latest snapshot, or nil
            professions = {}, -- list of { character, profession, skill, max_skill, scanned_at, recipes }
            signups = {}, -- relayed member sign-ups awaiting export
            bank = {}, -- guild bank log rows
            announcements = {}, -- officer-composed announcements awaiting export
            recruits = {}, -- officer recruit records
            member_notes = {}, -- officer member notes
            battlegrounds = {}, -- recorded battleground scoreboards awaiting export
            guild_log = {}, -- invite/join/quit/remove rows (GuildLog.lua) awaiting export, contract max 500
            recruit_payouts_paid = {}, -- officer-mailed recruitment payouts (Payouts.lua) awaiting export
        },
        standings = {
            generated_at = 0,
            rules = nil, -- nil until first import; Rules.lua keeps its own defaults meanwhile
            rows = {},
        },
        killed_encounters = {},
        events = {},
        pastEvents = {}, -- the site's recent past events, newest first, as answer counts (Events.Load)
        eventsAt = 0, -- generated_at of the import/broadcast the events came from; 0 = never received any
        calendarLinks = {}, -- site event id -> where Calendar.lua last saw its guild announcement (title, at, realm date/time)
        -- GuildLog.lua: every invite/join/quit/remove row this client has ever captured (kind, actor, target, at),
        -- used only to dedupe a repeat QueryGuildEventLog capture against; pruned past 60 days.
        guildLogHistory = {},
        -- directory.md: every member's shared record, keyed by normalized "Name-Realm".
        directory = {},
        -- directory.md: this character's own sell/buy/requests and bag/bank stock, independent of
        -- `settings.share` (which only governs what gets published to the guild directory).
        market = { sell = {}, buy = {}, requests = {} },
        stock = { bags = {}, bank = {}, bank_at = nil },
        -- Bank.lua: content-key -> list of { at, id } already-recorded guild bank
        -- log rows, keyed by everything but time so a repeat capture can match a
        -- row whose reported elapsed time has grown. Survives `/sq export clear`
        -- (pending.bank doesn't); pruned at 120 days.
        bankSeen = {},
        standby = {}, -- list of normalized "Name-Realm"
        settings = {
            officerRankIndex = nil, -- lowest guild rank that counts as officer; 0 is the Guild Master, like GetGuildInfo
            standingsBroadcastThrottle = 2, -- seconds between standings chunk sends
            reduceMotion = false, -- skip window-open/tab-crossfade/wax-seal/toast animation
            share = { prof = true, char = true, cd = true, market = true, stock = true }, -- directory.md
        },
        -- Game import "prices" (contract "Game import"): item_id (number key) ->
        -- { p = unit_price, q = quantity, at = unix timestamp }, replaced wholesale
        -- by each import that includes the field.
        prices = {},
        -- v2: cached imported state (SQI1: "v":2), see addon-contract-v2.md.
        guild = {
            generated_at = 0,
            members = {}, -- public import "members": roster/EP/badges, broadcast to everyone
            news = {}, -- public import "news" + live NEWS items, newest first
        },
        onDemand = {
            sheets = {}, -- member_id (string key) -> { ledger = {}, loot = {} }; officer-held, answers SHEET_Q
            crafters = {}, -- list of { character, member_id, profession, skill, recipes = {ids} }
            recipe_names = {}, -- id (string key) -> name
        },
        officerData = {
            recruits = {},
            member_notes = {},
            inactive = {},
            unseen = {}, -- guild members with no roster sweep, Battle.net login, or raid presence on record at all
            recruit_payouts = {}, -- officer import "recruit_payouts": owed inviters, replaced wholesale each import
        },
        -- Payouts.lua: "<event_id>|<inviter>" -> true once this client has mailed that payout, so the same row
        -- never fires SendMail twice even if the site hasn't processed the export (and so dropped it from the
        -- next import's recruit_payouts) yet. Never cleared by `/sq export clear`.
        paidPayouts = {},
        roster = { taken_at = 0, members = {} }, -- this character's own latest GuildRoster sweep
        professions = {}, -- this character's own latest profession scans, keyed "Character|Profession"
        mySignups = {}, -- event_id -> { status, sentAt, acked }
        addonVersions = {}, -- character -> { version, seenAt } learned from HELLO
        prepAnswers = {}, -- character -> prep report, cleared each time an officer opens a new PREP_Q
        -- ADDON_ACTION_BLOCKED/FORBIDDEN events + handler errors SQ.Fire swallows (Debug console view, GM-only).
        debug = { log = {} },
        ui = {
            pos = nil, width = nil, height = nil, scale = nil, tab = nil,
            -- LibDBIcon-1.0 reads and writes this table: degrees round the rim (0 = right), and hidden or not
            minimap = { hide = false, minimapPos = 190 },
        },
    }
end

SQ.defaultDB = defaultDB

-- Each migration function receives the db at version N and mutates it to N+1.
-- Keyed by the version it upgrades *from*.
local MIGRATIONS = {
    -- 1 -> 2: the minimap button moved to LibDBIcon-1.0, which keeps its position as `minimapPos`
    [1] = function(db)
        local minimap = db.ui.minimap
        if minimap.angle then
            minimap.minimapPos = minimap.angle
            minimap.angle = nil
        end
    end,

    -- 2 -> 3: before this fix, every name read off the guild roster, chat
    -- senders, guild trade skill scans and typed-in text went through the
    -- old realm-only NormalizeName, which on Forever (no realms, "First
    -- Surname" identity) mis-keyed them as "First Surname-<realm>" --
    -- a different string from the player's own correct "First-Surname"
    -- key (SQ.NormalizeUnit, built straight from UnitName's name+surname
    -- return). Rekey every stored character identity to SQ.CanonicalName
    -- now that it exists; non-Forever saves round-trip unchanged since
    -- CanonicalName keeps producing "Name-Realm" there.
    [2] = function(db)
        local function rekey(name)
            if type(name) ~= "string" or name == "" then
                return name
            end
            return (SQ.CanonicalName and SQ.CanonicalName(name)) or name
        end

        -- character -> record maps: merge an old-form entry into the
        -- canonical key, keeping whichever side looks newer.
        local function rekeyMap(tbl, timeField)
            if type(tbl) ~= "table" then
                return
            end
            local renames = {}
            for key in pairs(tbl) do
                local canon = rekey(key)
                if canon ~= key then
                    renames[key] = canon
                end
            end
            for old, canon in pairs(renames) do
                local oldVal, newVal = tbl[old], tbl[canon]
                tbl[old] = nil
                if newVal == nil then
                    tbl[canon] = oldVal
                elseif timeField and type(oldVal) == "table" and type(newVal) == "table" then
                    local oldT, newT = oldVal[timeField] or 0, newVal[timeField] or 0
                    if oldT > newT then
                        tbl[canon] = oldVal
                    end
                end
                -- else: a canonical entry already exists and looks as new
                -- or newer; keep it, drop the stale duplicate.
            end
        end

        -- lists of row tables carrying a `.character` field.
        local function rekeyRows(rows)
            if type(rows) ~= "table" then
                return
            end
            for _, row in ipairs(rows) do
                if type(row) == "table" and row.character then
                    row.character = rekey(row.character)
                end
            end
        end

        rekeyMap(db.directory, "seen_at")
        rekeyMap(db.addonVersions, "seenAt")
        rekeyMap(db.prepAnswers, "at")

        if type(db.standby) == "table" then
            local seen, out = {}, {}
            for _, name in ipairs(db.standby) do
                local canon = rekey(name)
                if not seen[canon] then
                    seen[canon] = true
                    out[#out + 1] = canon
                end
            end
            db.standby = out
        end

        if db.roster then
            rekeyRows(db.roster.members)
        end
        if db.pending and db.pending.roster then
            rekeyRows(db.pending.roster.members)
        end
        if db.pending then
            rekeyRows(db.pending.professions)
            rekeyRows(db.pending.signups)
        end

        -- `professions` is keyed "Character|Profession".
        if type(db.professions) == "table" then
            local renames = {}
            for key, row in pairs(db.professions) do
                local char, prof = key:match("^(.-)%|(.*)$")
                if char then
                    local canon = rekey(char)
                    if canon ~= char then
                        renames[key] = canon .. "|" .. prof
                    end
                end
            end
            for old, newKey in pairs(renames) do
                if db.professions[newKey] == nil then
                    db.professions[newKey] = db.professions[old]
                end
                db.professions[old] = nil
            end
        end
    end,
}

local function ensureDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = v
        elseif type(v) == "table" and type(db[k]) == "table" then
            ensureDefaults(db[k], v)
        end
    end
end

function SQ.InitDB()
    if type(SideQuestDB) ~= "table" then
        SideQuestDB = defaultDB()
        return SideQuestDB
    end

    local db = SideQuestDB
    ensureDefaults(db, defaultDB())

    local version = db.version or 0
    while version < SQ.CURRENT_DB_VERSION do
        local migrate = MIGRATIONS[version]
        if migrate then
            migrate(db)
        end
        version = version + 1
        db.version = version
    end

    return db
end

--------------------------------------------------------------------------
-- Event dispatcher
--------------------------------------------------------------------------

SQ.handlers = {} -- eventName -> list of callbacks

function SQ.On(eventName, callback)
    SQ.handlers[eventName] = SQ.handlers[eventName] or {}
    table.insert(SQ.handlers[eventName], callback)
end

function SQ.Fire(eventName, ...)
    local list = SQ.handlers[eventName]
    if not list then
        return
    end
    for _, cb in ipairs(list) do
        local ok, err = pcall(cb, ...)
        if not ok and SQ.Print then
            SQ.Print("|cffff4444Error|r in handler for " .. tostring(eventName) .. ": " .. tostring(err))
            if SQ.LogDebug then
                SQ.LogDebug({ kind = "error", event = eventName, message = tostring(err) })
            end
        end
    end
end

-- Frame-driven Blizzard event dispatch; wowstub.lua in tests provides CreateFrame.
if CreateFrame then
    SQ.eventFrame = CreateFrame("Frame", "SideQuestEventFrame")
    SQ.eventFrame:SetScript("OnEvent", function(_, event, ...)
        SQ.Fire(event, ...)
    end)

    -- An unknown event throws on Forever instead of being ignored, so every
    -- registration is defensive.
    function SQ.RegisterGameEvent(event)
        pcall(SQ.eventFrame.RegisterEvent, SQ.eventFrame, event)
    end
else
    function SQ.RegisterGameEvent() end
end

--------------------------------------------------------------------------
-- Combat deferral
--------------------------------------------------------------------------

-- UI must never open, flash or animate in combat. Anything that would do
-- so calls SQ.WhenOutOfCombat(fn) instead of running directly; fn runs
-- immediately if we're not in combat, otherwise it is queued and flushed
-- on PLAYER_REGEN_ENABLED (in FIFO order, each run resets combat status).
local combatQueue = {}

function SQ.InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

function SQ.WhenOutOfCombat(fn)
    if not SQ.InCombat() then
        fn()
        return
    end
    table.insert(combatQueue, fn)
end

SQ.On("PLAYER_REGEN_ENABLED", function()
    local queued = combatQueue
    combatQueue = {}
    for _, fn in ipairs(queued) do
        pcall(fn)
    end
end)
SQ.RegisterGameEvent("PLAYER_REGEN_ENABLED")
SQ.RegisterGameEvent("PLAYER_REGEN_DISABLED")

--------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------

function SQ.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffSideQuest|r: " .. tostring(msg))
    end
end

--------------------------------------------------------------------------
-- Items: Forever has C_Item only; the old GetItemInfo global is gone.
--------------------------------------------------------------------------

--- Same returns as GetItemInfo (name, link, quality, ..., equipLoc, icon);
-- nil when the client hasn't cached the item yet.
function SQ.GetItemInfo(item)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn or item == nil then
        return nil
    end
    return fn(item)
end

--- The item's name, or "item <id>" while the client hasn't cached it.
function SQ.ItemName(itemId)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemId)
    name = name or SQ.GetItemInfo(itemId)
    return name or ("item " .. tostring(itemId))
end

--------------------------------------------------------------------------
-- Secret-value guards (Midnight's `issecretvalue`)
--------------------------------------------------------------------------

-- Returns a plain string, or nil if the value is secret and cannot be read.
-- `issecretvalue` does not exist on Mainline builds that predate Midnight,
-- so this must tolerate its absence.
function SQ.Unsecret(value)
    if value == nil then
        return nil
    end
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return nil
    end
    return value
end

function SQ.SafeUnitName(unit)
    local name, realm = UnitName(unit)
    name = SQ.Unsecret(name)
    if not name then
        return nil
    end
    realm = SQ.Unsecret(realm)
    return name, realm
end

function SQ.SafeUnitGUID(unit)
    return SQ.Unsecret(UnitGUID(unit))
end

--------------------------------------------------------------------------
-- Name normalization: Forever has no realms; a character is "First
-- Surname" (CHARACTERNAME_SURNAME_SEPARATOR = " ", confirmed in
-- Ketho/BlizzardInterfaceResources forever branch Resources/LuaEnum.lua's
-- Constants.CharacterNameSeparatorConsts). The client mixes two shapes of
-- that identity across its own APIs: UnitName(unit) returns the two parts
-- separately ("Legs", "Behindhead"); everything else (GetGuildRosterInfo,
-- CHAT_MSG_ADDON senders, GetGuildTradeSkillInfo, typed-in text) hands
-- back one string joined with a space, sometimes with a trailing
-- realm/surname an old call site tacked on. CanonicalName folds every
-- shape into the one key this addon stores and compares everywhere:
-- "First-Surname" (the link form, CHARACTERNAME_LINK_SEPARATOR = "-") on
-- Forever, "Name-Realm" elsewhere -- unchanged from before Forever.
--------------------------------------------------------------------------

--- True on the Forever client (no realms, first-name/surname identity).
-- RegionalUniqueNamesEnabled is Forever's own flag for this (Gethe/wow-ui-
-- source, forever branch). WOW_PROJECT_ID == WOW_PROJECT_CAMELOT (18) is
-- the same check other Forever addons (DBM, BagBrother) use, and is kept
-- as a second signal in case the first is ever renamed or missing.
function SQ.IsForever()
    if type(RegionalUniqueNamesEnabled) == "function" then
        local ok, enabled = pcall(RegionalUniqueNamesEnabled)
        if ok and enabled then
            return true
        end
    end
    if WOW_PROJECT_ID and WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then
        return true
    end
    return false
end

--- Canonicalize any name SideQuest reads off the client or types in by
-- hand into the one key it stores and compares everywhere. `second`, when
-- given, is a true second part (UnitName(unit)'s surname return, or a
-- realm on non-Forever clients) -- never a full name by itself. `name`
-- alone may already be a complete "First Surname"/"First-Surname"
-- (optionally with a stray "-Realm"/"-Surname" tail some call site
-- added); that's told apart from a true pair by whether `name` itself
-- already contains a space or hyphen. Returns nil for a secret or empty
-- name.
function SQ.CanonicalName(name, second)
    name = SQ.Unsecret(name)
    if not name or name == "" then
        return nil
    end
    second = SQ.Unsecret(second)

    if SQ.IsForever() then
        if second and second ~= "" and not name:find(" ", 1, true) and not name:find("-", 1, true) then
            -- A true (first, surname) pair, e.g. straight from UnitName(unit).
            local surname = second:match("^([^-]+)") or second
            return name .. "-" .. surname:gsub("%s", "")
        end
        -- `name` is already a complete identity string: link-ify its
        -- surname separator (prefer the client's own conversion), then
        -- keep only the first two hyphen-joined parts -- dropping any
        -- trailing "-Realm"/"-Surname" an old call site appended.
        local full = name
        if full:find(" ", 1, true) then
            if C_NameUtil and C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator then
                local ok, linked = pcall(C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator, full)
                if ok and linked then
                    full = SQ.Unsecret(linked) or full
                end
            end
            full = full:gsub(" ", "-", 1)
        end
        local first, surname = full:match("^([^-]+)-([^-]+)")
        if not first then
            return full -- single token: nothing to split
        end
        return first .. "-" .. surname
    end

    if name:find("-", 1, true) then
        return name
    end
    local realm = second
    if not realm or realm == "" then
        if GetNormalizedRealmName then
            realm = GetNormalizedRealmName()
        end
    end
    realm = realm or ""
    realm = realm:gsub("%s", "")
    return name .. "-" .. realm
end

SQ.NormalizeName = SQ.CanonicalName

function SQ.NormalizeUnit(unit)
    local name, realm = SQ.SafeUnitName(unit)
    if not name then
        return nil
    end
    return SQ.CanonicalName(name, realm)
end

--- The name the game's whisper/invite/target calls take for `character` (a
-- CanonicalName key). Blizzard's own Forever unit menu builds it with
-- CHARACTERNAME_REALMNAME_SEPARATOR ("-") whenever there's no live unit --
-- names from chat, the roster or the guild list
-- (Blizzard_UnitPopup/Mainline/UnitPopupUtils.lua GetFullPlayerName) -- and
-- the space form only for a unit token. A whisper target with a space
-- would also be split by the /w slash parser. So the canonical
-- "First-Surname" (or "Name-Realm") key is already the game's form.
function SQ.GameName(character)
    return character
end

--- `text` cut to at most `maxBytes` bytes without splitting a UTF-8
-- character. A half character left in SavedVariables makes the file
-- invalid UTF-8, which tools reading it (SideQuest Companion) choke on.
function SQ.Utf8Cut(text, maxBytes)
    text = tostring(text or "")
    if #text <= maxBytes then
        return text
    end
    local cut = maxBytes
    -- step back over continuation bytes (10xxxxxx) so the cut lands before a character's lead byte
    while cut > 0 and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do
        cut = cut - 1
    end
    return text:sub(1, cut)
end

--- Ask the UI to open SideQuest's own whisper box for `character`.
-- Never ChatFrameUtil.SendTell / ChatFrame_SendTell: called from addon code
-- they write the chat box's chatType/tellTarget attributes tainted, every
-- macro line copies those attributes before it runs (Blizzard_ChatFrameBase
-- MacroExecutionManager.lua), and from then on secure macro buttons --
-- another addon's /targetexact button, say -- get TargetUnit blocked with
-- the game blaming SideQuest, until a /reload.
function SQ.Whisper(character)
    local target = SQ.GameName(character)
    if not target or target == "" then
        return
    end
    SQ.Fire("SQ_OPEN_WHISPER", target)
end

--- Send `text` to `target` as a whisper without going through the chat box.
function SQ.SendWhisper(target, text)
    if not target or target == "" or not text or text == "" then
        return false
    end
    -- Forever has no SendChatMessage global; C_ChatInfo.SendChatMessage replaces it.
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then
        return false
    end
    send(text, "WHISPER", nil, target)
    return true
end

--- Invite `character` to the group. Forever has no InviteUnit global;
-- C_PartyInfo.InviteUnit replaces it.
function SQ.Invite(character)
    local target = SQ.GameName(character)
    if not target or target == "" then
        return
    end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(target)
    elseif InviteUnit then
        InviteUnit(target)
    end
end

--- Turn the party into a raid (C_PartyInfo.ConvertToRaid on Forever).
function SQ.ConvertToRaid()
    if C_PartyInfo and C_PartyInfo.ConvertToRaid then
        C_PartyInfo.ConvertToRaid()
    elseif ConvertToRaid then
        ConvertToRaid()
    end
end

--- True when the player leads their party or raid, or isn't in a group.
-- Forever has neither IsRaidLeader nor IsPartyLeader; UnitIsGroupLeader is
-- the API both clients share.
function SQ.IsGroupLeader()
    if not ((IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())) then
        return true
    end
    if UnitIsGroupLeader then
        return SQ.Unsecret(UnitIsGroupLeader("player")) == true
    end
    return (IsRaidLeader and IsRaidLeader()) or (IsPartyLeader and IsPartyLeader()) or false
end

--------------------------------------------------------------------------
-- Record id generation: "<recorderShort>-<serverTime>-<seq>"
--------------------------------------------------------------------------

function SQ.RecorderShort(recorderGUID)
    if not recorderGUID then
        return "UNKNOWN"
    end
    local tail = recorderGUID:match("%-(%w+)$")
    return tail or recorderGUID
end

function SQ.NextId()
    local db = SideQuestDB
    db.seq = (db.seq or 0) + 1
    local guid = SQ.SafeUnitGUID and SQ.SafeUnitGUID("player")
    local recorderShort = SQ.RecorderShort(guid)
    local serverTime = GetServerTime and GetServerTime() or 0
    return recorderShort .. "-" .. tostring(serverTime) .. "-" .. tostring(db.seq)
end

--------------------------------------------------------------------------
-- Officer detection
--------------------------------------------------------------------------

-- Prefer the real officer-note permission; fall back to a configurable
-- guild rank index when the API is unavailable (e.g. no officer note perms
-- granted but the rank should still count as "officer" for loot purposes).
function SQ.IsOfficer()
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote and C_GuildInfo.CanEditOfficerNote() then
        return true
    end
    local idx = SideQuestDB and SideQuestDB.settings and SideQuestDB.settings.officerRankIndex
    if idx and GetGuildInfo then
        local _, _, rankIndex = GetGuildInfo("player")
        if rankIndex ~= nil and rankIndex <= idx then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------
-- Guild membership detection
--------------------------------------------------------------------------

-- The SideQuest guild's exact in-game name, compared against GetGuildInfo
-- ("player")'s own guild-name return -- the same value Sync.lua already
-- stamps onto every export payload's "guild" field.
SQ.GUILD_NAME = "SideQuest"

-- IsInGuild() can read false for a frame or two right after login before the
-- client has the player's own guild data, the same lag CanEditOfficerNote
-- has above; guildMembershipKnown only flips once PLAYER_GUILD_UPDATE or
-- GUILD_ROSTER_UPDATE has fired (or IsInGuild() itself turns true), so a
-- member whose guild info is still loading is never mistaken for someone
-- who isn't in the guild.
local guildMembershipKnown = false

--- Test-only: clears the "has guild info resolved yet" latch between tests.
function SQ.ResetGuildMembershipState()
    guildMembershipKnown = false
end

--- true while in the SideQuest guild, false once confirmed otherwise (a
-- different guild, or no guild at all), nil while that still isn't known.
-- Callers deciding whether to show member-only UI must treat nil as "assume
-- member": a real member never flashes the non-member view while login is
-- still settling, at the cost of a real non-member briefly seeing the member
-- view until the first PLAYER_GUILD_UPDATE/GUILD_ROSTER_UPDATE resolves it.
function SQ.IsGuildMember()
    local inGuild = type(IsInGuild) == "function" and IsInGuild()
    if inGuild then
        guildMembershipKnown = true
        local name = type(GetGuildInfo) == "function" and GetGuildInfo("player")
        if not name then
            return nil -- in a guild whose name hasn't loaded yet
        end
        return name == SQ.GUILD_NAME
    end
    if not guildMembershipKnown then
        return nil
    end
    return false
end

SQ.On("PLAYER_GUILD_UPDATE", function()
    guildMembershipKnown = true
end)
SQ.RegisterGameEvent("PLAYER_GUILD_UPDATE")
SQ.On("GUILD_ROSTER_UPDATE", function()
    guildMembershipKnown = true
end)
SQ.RegisterGameEvent("GUILD_ROSTER_UPDATE")
-- Players with no guild may never get either event; a few seconds into the world, no guild means no guild.
SQ.On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            guildMembershipKnown = true
        end)
    end
end)

--- true when in the SideQuest guild and at guild rank index 0 (Guild
-- Master, GetGuildInfo's own rankIndex return).
function SQ.IsGuildMaster()
    if SQ.IsGuildMember() ~= true then
        return false
    end
    if type(GetGuildInfo) ~= "function" then
        return false
    end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

--------------------------------------------------------------------------
-- Debug log: ADDON_ACTION_BLOCKED/FORBIDDEN events and handler errors
-- SQ.Fire already swallows, so the GM can see what went wrong without
-- reproducing it live. Capped at DEBUG_LOG_MAX entries, newest first.
-- Cheap to record for everyone; only the Console "Debug" sub-view
-- (GM-only, UI/Main.lua) reads it.
--------------------------------------------------------------------------

local DEBUG_LOG_MAX = 50

function SQ.LogDebug(entry)
    if not SideQuestDB then
        return
    end
    SideQuestDB.debug = SideQuestDB.debug or { log = {} }
    entry.at = entry.at or (GetServerTime and GetServerTime() or 0)
    table.insert(SideQuestDB.debug.log, 1, entry)
    for i = #SideQuestDB.debug.log, DEBUG_LOG_MAX + 1, -1 do
        table.remove(SideQuestDB.debug.log, i)
    end
end

local function onActionBlocked(eventName)
    return function(addonName, functionName)
        if addonName ~= SQ.ADDON_NAME then
            return
        end
        -- no stack: the game reports this after the fact, so debugstack()
        -- here would only show this handler, never the blocked caller
        SQ.LogDebug({ kind = "blocked", event = eventName, func = functionName })
    end
end
SQ.On("ADDON_ACTION_BLOCKED", onActionBlocked("ADDON_ACTION_BLOCKED"))
SQ.RegisterGameEvent("ADDON_ACTION_BLOCKED")
SQ.On("ADDON_ACTION_FORBIDDEN", onActionBlocked("ADDON_ACTION_FORBIDDEN"))
SQ.RegisterGameEvent("ADDON_ACTION_FORBIDDEN")

--------------------------------------------------------------------------
-- "View as": a GM-only, session-only (never saved, /reload clears it)
-- override that makes the Display* checks below report a different role,
-- so the GM can preview what a member/officer/non-member sees. Never
-- touches SQ.IsGuildMember/IsOfficer/IsGuildMaster themselves -- exports,
-- comms, the HELLO officer flag and recorder rights all read those real
-- checks and are unaffected; only UI/Main.lua's drawing decisions consult
-- the Display* wrappers.
--------------------------------------------------------------------------

local viewAsRole = nil -- nil (off), "nonmember", "member", "officer"

--- Test-only: clears the view-as override between tests.
function SQ.ResetViewAsState()
    viewAsRole = nil
end

--- Turns the override on (GM only -- a non-GM call is a silent no-op, same
-- as a real non-GM having no way to reach the Debug view) or off (role =
-- nil always succeeds, so Exit/the join pane's banner always works).
-- Fires SQ_VIEW_AS_CHANGED either way so UI/Main.lua can rebuild.
function SQ.SetViewAs(role)
    if role ~= "nonmember" and role ~= "member" and role ~= "officer" then
        role = nil
    end
    if role ~= nil and not SQ.IsGuildMaster() then
        return false
    end
    viewAsRole = role
    SQ.Fire("SQ_VIEW_AS_CHANGED", viewAsRole)
    return true
end

function SQ.ViewAs()
    return viewAsRole
end

--- Display-only guild membership: what UI/Main.lua should draw.
function SQ.DisplayIsGuildMember()
    if viewAsRole == "nonmember" then
        return false
    elseif viewAsRole == "member" or viewAsRole == "officer" then
        return true
    end
    return SQ.IsGuildMember()
end

--- Display-only officer status: what UI/Main.lua should draw.
function SQ.DisplayIsOfficer()
    if viewAsRole == "nonmember" or viewAsRole == "member" then
        return false
    elseif viewAsRole == "officer" then
        return true
    end
    return SQ.IsOfficer()
end

--- Display-only GM status: what UI/Main.lua should draw. Any active
-- override hides the GM-only Debug view, including "Officer".
function SQ.DisplayIsGuildMaster()
    if viewAsRole ~= nil then
        return false
    end
    return SQ.IsGuildMaster()
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

SQ.slashHandlers = {}

function SQ.RegisterSlash(keyword, handler, help)
    SQ.slashHandlers[keyword] = { handler = handler, help = help }
end

local function dispatchSlash(msg)
    msg = msg or ""
    local keyword, rest = msg:match("^(%S*)%s*(.-)$")
    keyword = (keyword or ""):lower()

    if keyword == "" then
        SQ.Fire("SQ_OPEN_MAIN_WINDOW")
        return
    end

    local entry = SQ.slashHandlers[keyword]
    if entry then
        entry.handler(rest)
        return
    end

    if keyword == "help" then
        SQ.Print("Commands:")
        for kw, e in pairs(SQ.slashHandlers) do
            SQ.Print("  /sq " .. kw .. (e.help and (" - " .. e.help) or ""))
        end
        return
    end

    SQ.Print("Unknown command '" .. keyword .. "'. Try /sq help.")
end

SQ.DispatchSlash = dispatchSlash

-- Only add a key: never assign SlashCmdList itself (not even `SlashCmdList = SlashCmdList or {}`). That taints
-- the global, and Blizzard reads it before running every non-secure slash command, so a macro's /tm then gets
-- SetRaidTarget forbidden with SideQuest blamed.
if SlashCmdList then
    SLASH_SIDEQUEST1 = "/sq"
    SlashCmdList["SIDEQUEST"] = dispatchSlash
end

SQ.RegisterSlash("share", function(rest)
    local section, onOff = rest:match("^(%S*)%s*(%S*)$")
    section = (section or ""):lower()
    local share = SideQuestDB.settings.share
    local valid = { prof = true, char = true, cd = true, market = true, stock = true }
    if not valid[section] then
        SQ.Print("Usage: /sq share <prof|char|cd|market|stock> on|off")
        return
    end
    if onOff == "on" then
        share[section] = true
    elseif onOff == "off" then
        share[section] = false
    else
        SQ.Print("Usage: /sq share <prof|char|cd|market|stock> on|off")
        return
    end
    SQ.Print("Sharing " .. section .. ": " .. (share[section] and "on" or "off"))
end, "share <prof|char|cd|market|stock> on|off - what the directory sends about you")

SQ.RegisterSlash("dir", function()
    local character = SQ.NormalizeUnit("player")
    local entry = character and SideQuestDB.directory[character]
    local sections = {}
    for _, section in ipairs({ "prof", "char", "cd", "market", "stock" }) do
        table.insert(sections, section .. "=" .. (SideQuestDB.settings.share[section] and "on" or "off"))
    end
    local known = 0
    for _ in pairs(SideQuestDB.directory) do
        known = known + 1
    end
    SQ.Print("Directory: " .. known .. " character(s) known. Sharing " .. table.concat(sections, ", ") .. ".")
    if entry and entry.seen_at then
        SQ.Print("My record last updated " .. tostring(entry.seen_at) .. ".")
    end
end, "dir - directory sharing status")

SQ.RegisterSlash("viewas", function(rest)
    local arg = (rest or ""):lower()
    local ROLES = { nonmember = "nonmember", member = "member", officer = "officer", off = nil }
    if arg == "" or not (arg == "off" or ROLES[arg]) then
        SQ.Print("Usage: /sq viewas member|officer|nonmember|off")
        return
    end
    local role = (arg ~= "off") and ROLES[arg] or nil
    if role ~= nil and not SQ.IsGuildMaster() then
        SQ.Print("Only the Guild Master can use View as.")
        return
    end
    SQ.SetViewAs(role)
    SQ.Print("Viewing as: " .. (SQ.ViewAs() or "yourself"))
end, "viewas member|officer|nonmember|off - GM-only UI preview")

--------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------

local function onAddonLoaded(name)
    if name ~= SQ.ADDON_NAME then
        return
    end
    SQ.InitDB()
    SQ.Fire("SQ_READY")
end

SQ.On("ADDON_LOADED", onAddonLoaded)
SQ.RegisterGameEvent("ADDON_LOADED")
SQ.RegisterGameEvent("PLAYER_ENTERING_WORLD")
SQ.RegisterGameEvent("GROUP_ROSTER_UPDATE")
SQ.RegisterGameEvent("ENCOUNTER_START")
SQ.RegisterGameEvent("ENCOUNTER_END")
SQ.RegisterGameEvent("CHAT_MSG_LOOT")
SQ.RegisterGameEvent("CHAT_MSG_ADDON")

return SQ
