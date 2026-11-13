-- SideQuest/GuildLog.lua
-- Captures who invited whom (contract v2 "guild_log"): officer-only, from the in-game guild event log
-- (QueryGuildEventLog/GetNumGuildEvents/GetGuildEventInfo, confirmed on Forever 1.60.1). The log's export is
-- officer-only (same as the officer note), so a member's client never even asks for it.
--
-- GetGuildEventInfo(i) returns (type, player1, player2, rank, year, month, day, hour), where year/month/day/hour
-- are elapsed time *since* the event, not a date -- the same shape GetGuildRosterLastOnline and the guild bank
-- log use. Confirmed against Gethe/wow-ui-source (forever branch) Blizzard_Communities/GuildInfo.lua and
-- tekkub/wow-globalstrings GUILDEVENT_TYPE_* format strings for which player is which:
--   invite: "%s invites %s"          -- player1 = inviter (actor), player2 = invitee (target)
--   join:   "%s joins the guild"     -- player1 = the member who joined (actor), no target
--   quit:   "%s leaves the guild"    -- player1 = the member who left (actor), no target
--   remove: "%s removes %s..."       -- player1 = the officer who removed (actor), player2 = removed (target)
-- promote/demote exist too but the contract doesn't want them (not needed; keeps the export small).

SideQuest = SideQuest or {}
SideQuest.GuildLog = {}
local GuildLog = SideQuest.GuildLog

local HOUR = 3600
local DEDUPE_WINDOW = 2 * HOUR -- contract: same kind+actor+target within 2 hours counts as the same entry
local HISTORY_PRUNE_AGE = 60 * 24 * HOUR -- contract: local history keeps 60 days
local PENDING_CAP = 500 -- contract: guild_log export caps at 500; mirrored here so pending never grows past it
local REQUEST_THROTTLE = 300 -- seconds between QueryGuildEventLog requests

-- GetGuildEventInfo "type" strings this addon keeps; player2 is only meaningful for these two.
local KEPT_KINDS = { invite = true, join = true, quit = true, remove = true }
local HAS_TARGET = { invite = true, remove = true }

local function now()
    return GetServerTime and GetServerTime() or 0
end

function GuildLog.IsAvailable()
    return type(GetNumGuildEvents) == "function" and type(GetGuildEventInfo) == "function"
end

-- year/month/day/hour are elapsed time, not a date; round down to the hour (the log only gives whole hours).
local function estimateAt(years, months, days, hours)
    local elapsedHours = (years or 0) * 365 * 24 + (months or 0) * 30 * 24 + (days or 0) * 24 + (hours or 0)
    local nowHour = math.floor(now() / HOUR) * HOUR
    return nowHour - elapsedHours * HOUR
end

local function pruneHistory()
    local history = SideQuestDB.guildLogHistory
    local cutoff = now() - HISTORY_PRUNE_AGE
    local kept = {}
    for _, e in ipairs(history) do
        if e.at >= cutoff then
            kept[#kept + 1] = e
        end
    end
    SideQuestDB.guildLogHistory = kept
end

-- Matches (kind, actor, target) against guildLogHistory within DEDUPE_WINDOW of `at`, skipping history entries
-- already matched earlier in this same capture pass (so two real same-kind-actor-target events within the window
-- still count as two if the log genuinely holds two rows -- matching Bank.lua's recordIfNew pattern). Returns
-- true (and appends to history) when this is a new entry.
local function recordIfNew(kind, actor, target, at, matchedThisPass)
    local history = SideQuestDB.guildLogHistory
    for i, e in ipairs(history) do
        if not matchedThisPass[i] and e.kind == kind and e.actor == actor and e.target == target
            and math.abs(e.at - at) <= DEDUPE_WINDOW then
            matchedThisPass[i] = true
            return false
        end
    end
    history[#history + 1] = { kind = kind, actor = actor, target = target, at = at }
    matchedThisPass[#history] = true
    return true
end

local function capPending()
    local pending = SideQuestDB.pending.guild_log
    local overflow = #pending - PENDING_CAP
    if overflow > 0 then
        for _ = 1, overflow do
            table.remove(pending, 1)
        end
    end
end

--- Capture whatever QueryGuildEventLog has already delivered into
-- pending.guild_log, deduped against guildLogHistory. Officer-only (the
-- log export itself is officer-only). Returns the number of new rows, or
-- nil if the API is unavailable or the caller isn't an officer.
function GuildLog.Capture()
    if not SideQuest.IsOfficer() or not GuildLog.IsAvailable() then
        return nil
    end
    pruneHistory()
    local matchedThisPass = {}
    local added = 0
    local total = GetNumGuildEvents() or 0
    for i = 1, total do
        local kind, player1, player2, _, years, months, days, hours = GetGuildEventInfo(i)
        if KEPT_KINDS[kind] then
            local actorRaw = SideQuest.Unsecret(player1)
            local actor = actorRaw and SideQuest.NormalizeName(actorRaw)
            if actor then
                local target = nil
                if HAS_TARGET[kind] then
                    local targetRaw = SideQuest.Unsecret(player2)
                    target = targetRaw and SideQuest.NormalizeName(targetRaw)
                end
                local at = estimateAt(years, months, days, hours)
                if recordIfNew(kind, actor, target, at, matchedThisPass) then
                    table.insert(SideQuestDB.pending.guild_log, { kind = kind, actor = actor, target = target, at = at })
                    added = added + 1
                end
            end
        end
    end
    capPending()
    if added > 0 then
        SideQuest.Fire("SQ_GUILD_LOG_CAPTURED", added)
    end
    return added
end

--- Ask the server for the guild event log; results land asynchronously via
-- GUILD_EVENT_LOG_UPDATE, captured below. At most once every
-- REQUEST_THROTTLE seconds. Officer-only, like the capture itself.
GuildLog.lastRequestAt = nil

function GuildLog.RequestCapture()
    if not SideQuest.IsOfficer() or type(QueryGuildEventLog) ~= "function" then
        return
    end
    local t = now()
    if GuildLog.lastRequestAt and t - GuildLog.lastRequestAt < REQUEST_THROTTLE then
        return
    end
    GuildLog.lastRequestAt = t
    QueryGuildEventLog()
end

-- Request on login and whenever the officer's roster sweep runs (contract: "Request the log when the roster
-- sweep runs and on login"); Roster.lua fires SQ_ROSTER_UPDATED after every successful sweep, auto or manual.
SideQuest.On("PLAYER_ENTERING_WORLD", function()
    GuildLog.RequestCapture()
end)

SideQuest.On("SQ_ROSTER_UPDATED", function()
    GuildLog.RequestCapture()
end)

SideQuest.On("GUILD_EVENT_LOG_UPDATE", function()
    GuildLog.Capture()
end)
SideQuest.RegisterGameEvent("GUILD_EVENT_LOG_UPDATE")

return GuildLog
