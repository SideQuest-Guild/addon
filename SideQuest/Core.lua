-- SideQuest/Core.lua
-- SavedVariables defaults + migrations, lightweight event dispatcher, slash
-- commands, name normalization, record id generation, officer detection and
-- Midnight "secret value" guards.

SideQuest = SideQuest or {}
local SQ = SideQuest

SQ.ADDON_NAME = "SideQuest"
SQ.ADDON_VERSION = "1.0.0" -- stamped literally; packager replaces @project-version@ in the .toc, not here
SQ.CURRENT_DB_VERSION = 1

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
            roster = nil, -- { taken_at, members = {} } single latest snapshot, or nil
            professions = {}, -- list of { character, profession, skill, max_skill, scanned_at, recipes }
            signups = {}, -- relayed member sign-ups awaiting export
            bank = {}, -- guild bank log rows
            announcements = {}, -- officer-composed announcements awaiting export
            recruits = {}, -- officer recruit records
            member_notes = {}, -- officer member notes
        },
        standings = {
            generated_at = 0,
            rules = nil, -- nil until first import; Rules.lua keeps its own defaults meanwhile
            rows = {},
        },
        killed_encounters = {},
        events = {},
        standby = {}, -- list of normalized "Name-Realm"
        settings = {
            officerRankIndex = nil, -- lowest guild rank that counts as officer; 0 is the Guild Master, like GetGuildInfo
            standingsBroadcastThrottle = 2, -- seconds between standings chunk sends
        },
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
        },
        roster = { taken_at = 0, members = {} }, -- this character's own latest GuildRoster sweep
        professions = {}, -- this character's own latest profession scans, keyed "Character|Profession"
        mySignups = {}, -- event_id -> { status, sentAt, acked }
        addonVersions = {}, -- character -> { version, seenAt } learned from HELLO
        prepAnswers = {}, -- character -> prep report, cleared each time an officer opens a new PREP_Q
        ui = { pos = nil, width = nil, height = nil, scale = nil, tab = nil },
    }
end

SQ.defaultDB = defaultDB

-- Each migration function receives the db at version N and mutates it to N+1.
-- Keyed by the version it upgrades *from*.
local MIGRATIONS = {
    -- [0] = function(db) ... end,  -- example for a future bump
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
        end
    end
end

-- Frame-driven Blizzard event dispatch; wowstub.lua in tests provides CreateFrame.
if CreateFrame then
    SQ.eventFrame = CreateFrame("Frame", "SideQuestEventFrame")
    SQ.eventFrame:SetScript("OnEvent", function(_, event, ...)
        SQ.Fire(event, ...)
    end)

    function SQ.RegisterGameEvent(event)
        SQ.eventFrame:RegisterEvent(event)
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
-- Name normalization: "Name-Realm"
--------------------------------------------------------------------------

function SQ.NormalizeName(name, realm)
    if not name or name == "" then
        return nil
    end
    if name:find("-", 1, true) then
        return name
    end
    realm = realm
    if not realm or realm == "" then
        if GetNormalizedRealmName then
            realm = GetNormalizedRealmName()
        end
    end
    realm = realm or ""
    realm = realm:gsub("%s", "")
    return name .. "-" .. realm
end

function SQ.NormalizeUnit(unit)
    local name, realm = SQ.SafeUnitName(unit)
    if not name then
        return nil
    end
    return SQ.NormalizeName(name, realm)
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

if _G then
    SLASH_SIDEQUEST1 = "/sq"
    SlashCmdList = SlashCmdList or {}
    SlashCmdList["SIDEQUEST"] = dispatchSlash
end

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
