-- SideQuest/Standings.lua
-- Stores the last imported standings and layers on local provisional deltas
-- from awards that have not been exported/imported back yet. Officers
-- broadcast standings to the guild after an import; members request on
-- login.

SideQuest = SideQuest or {}
SideQuest.Standings = {}
local Standings = SideQuest.Standings

local function now()
    return GetServerTime and GetServerTime() or 0
end

function Standings.LoadFromImport(payload)
    SideQuestDB.standings = {
        generated_at = payload.generated_at,
        rules = payload.rules,
        rows = payload.standings or {},
    }
    if payload.rules then
        SideQuest.Rules.LoadFromImport(payload.rules)
    end
    if payload.killed_encounters then
        SideQuestDB.killed_encounters = payload.killed_encounters
    end
    if payload.events then
        SideQuestDB.events = payload.events
    end
end

--- Sum of not-yet-exported-or-cleared award amounts per character, split by
-- kind, since those are the only awards still "local only".
local function provisionalDeltas()
    local deltas = {} -- character -> { ep = n, gp = n }
    for _, award in ipairs((SideQuestDB.pending and SideQuestDB.pending.awards) or {}) do
        if not award.voided then
            local d = deltas[award.character]
            if not d then
                d = { ep = 0, gp = 0 }
                deltas[award.character] = d
            end
            d[award.kind] = (d[award.kind] or 0) + (award.amount or 0)
        end
    end
    return deltas
end

--- Rows for display: imported standings with local pending awards layered
-- on top as a provisional PR. Characters with pending awards but no stored
-- row are not fabricated here (that resolution is the site's job); the UI
-- should show them in a separate "pending" section if desired.
function Standings.GetDisplayRows()
    local base = (SideQuestDB.standings and SideQuestDB.standings.rows) or {}
    local deltas = provisionalDeltas()
    local rows = {}
    for i, row in ipairs(base) do
        local copy = {}
        for k, v in pairs(row) do
            copy[k] = v
        end
        local delta
        for _, charName in ipairs(row.characters or {}) do
            if deltas[charName] then
                delta = delta or { ep = 0, gp = 0 }
                delta.ep = delta.ep + deltas[charName].ep
                delta.gp = delta.gp + deltas[charName].gp
            end
        end
        if delta then
            copy.ep = (copy.ep or 0) + delta.ep
            copy.gp = (copy.gp or 0) + delta.gp
            local rules = SideQuest.Rules.Get()
            copy.gp = math.max(rules.min_gp, copy.gp)
            copy.pr = copy.gp > 0 and (copy.ep / copy.gp) or 0
            copy.provisional = true
        end
        rows[i] = copy
    end
    return rows
end

--------------------------------------------------------------------------
-- Broadcast (officer -> guild) / request (member -> officer)
--------------------------------------------------------------------------

function Standings.BroadcastAfterImport()
    if not SideQuest.IsOfficer() then
        return
    end
    local payload = {
        generated_at = SideQuestDB.standings.generated_at,
        rows = SideQuestDB.standings.rows,
    }
    local json = SideQuestJSON.encode(payload)
    SideQuest.Comm.BroadcastStandings(json)
end

Standings.answeredRequestAt = 0

function Standings.RequestOnLogin()
    -- members request; a small random delay avoids a thundering herd, and we
    -- only need one answer so we stop listening once we have one.
    local delay = math.random(1, 5)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            SideQuest.Comm.SendRaw("STANDINGS_REQ|" .. tostring(SideQuestDB.standings.generated_at or 0), "GUILD")
        end)
    else
        SideQuest.Comm.SendRaw("STANDINGS_REQ|" .. tostring(SideQuestDB.standings.generated_at or 0), "GUILD")
    end
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, sender)
    if msgType == "STANDINGS_REQ" then
        if not SideQuest.IsOfficer() then
            return
        end
        local theirGenAt = tonumber(payload) or 0
        local myGenAt = (SideQuestDB.standings and SideQuestDB.standings.generated_at) or 0
        if myGenAt <= theirGenAt then
            return -- we have nothing newer to offer
        end
        local t = now()
        if t - Standings.answeredRequestAt < 5 then
            return -- suppress: someone else likely already answered recently
        end
        Standings.answeredRequestAt = t
        local delay = math.random(1, 3)
        local send = function()
            Standings.BroadcastAfterImport()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, send)
        else
            send()
        end
    elseif msgType == "STANDINGS" then
        local ok, data = pcall(SideQuestJSON.decode, payload)
        if ok and type(data) == "table" and (not SideQuestDB.standings.generated_at
            or (data.generated_at or 0) > SideQuestDB.standings.generated_at) then
            SideQuestDB.standings.generated_at = data.generated_at
            SideQuestDB.standings.rows = data.rows
            SideQuest.Fire("SQ_STANDINGS_UPDATED")
        end
    end
end)

SideQuest.On("PLAYER_ENTERING_WORLD", function()
    if not SideQuest.IsOfficer() then
        Standings.RequestOnLogin()
    end
end)

return Standings
