-- SideQuest/Battlegrounds.lua
-- Battleground scoreboards (contract v2 "battlegrounds"): when a match ends,
-- request the final score data and record one row per player from the next
-- score update. Everything is read only after PVP_MATCH_COMPLETE:
-- C_PvP.GetScoreInfo is marked SecretInActivePvPMatch in
-- Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua (forever
-- branch of Gethe/wow-ui-source), so it stays unreadable (SQ.Unsecret
-- returns nil) until the match is over. PVP_MATCH_COMPLETE,
-- UPDATE_BATTLEFIELD_SCORE, C_PvP.GetScoreInfo, C_PvP.GetActiveMatchDuration,
-- GetNumBattlefieldScores, GetBattlefieldWinner, RequestBattlefieldScoreData,
-- GetInstanceInfo and UnitFactionGroup all confirmed to exist on Forever, in
-- that same file and Ketho/BlizzardInterfaceResources' Resources/GlobalAPI.lua
-- (forever branch). PVP_MATCH_ACTIVE exists too but isn't needed: gating on
-- "a match completed, score data not yet consumed" already keeps the addon
-- from reading anything while the match is active.

SideQuest = SideQuest or {}
SideQuest.Battlegrounds = {}
local Battlegrounds = SideQuest.Battlegrounds
local SQ = SideQuest

local MAX_PENDING = 50
local MAX_PLAYERS = 80
local FACTION_WORD = { [0] = "horde", [1] = "alliance" }

local function now()
    return GetServerTime and GetServerTime() or 0
end

local function nonNegInt(v)
    v = tonumber(v)
    if not v or v < 0 then
        return 0
    end
    return math.floor(v)
end

-- Set by PVP_MATCH_COMPLETE; consumed (and cleared either way, success or
-- skip) by the next UPDATE_BATTLEFIELD_SCORE so a match is only ever
-- processed once, no matter how many score updates follow.
local pendingMatch = nil

local function recorderName()
    local name = UnitName and SQ.Unsecret((UnitName("player")))
    return name or "Unknown"
end

local function myFactionWord()
    local token = UnitFactionGroup and SQ.Unsecret((UnitFactionGroup("player")))
    if token == "Horde" then
        return "horde"
    elseif token == "Alliance" then
        return "alliance"
    end
    return nil
end

local function winnerWord()
    local winner = GetBattlefieldWinner and SQ.Unsecret(GetBattlefieldWinner())
    if winner == 0 then
        return "horde"
    elseif winner == 1 then
        return "alliance"
    end
    return nil
end

local function matchDuration()
    if C_PvP and C_PvP.GetActiveMatchDuration then
        local secs = SQ.Unsecret(C_PvP.GetActiveMatchDuration())
        if secs then
            return nonNegInt(secs)
        end
    end
    return 0
end

local function captureInstanceInfo()
    if not GetInstanceInfo then
        return nil, nil
    end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return SQ.Unsecret(name), SQ.Unsecret(instanceID)
end

--- Read one player's row off the scoreboard; nil if the row or its name is
-- unreadable (can't tell who it is, so it can't be kept).
local function readScoreRow(index)
    if not (C_PvP and C_PvP.GetScoreInfo) then
        return nil
    end
    local info = C_PvP.GetScoreInfo(index)
    if not info then
        return nil
    end
    local name = SQ.Unsecret(info.name)
    if not name then
        return nil
    end
    local faction = SQ.Unsecret(info.faction)
    return {
        name = name,
        faction = FACTION_WORD[faction] or "horde",
        race = SQ.Unsecret(info.raceName) or "",
        class = SQ.Unsecret(info.classToken) or "",
        killing_blows = nonNegInt(SQ.Unsecret(info.killingBlows)),
        honorable_kills = nonNegInt(SQ.Unsecret(info.honorableKills)),
        deaths = nonNegInt(SQ.Unsecret(info.deaths)),
        honor_gained = nonNegInt(SQ.Unsecret(info.honorGained)),
        damage_done = nonNegInt(SQ.Unsecret(info.damageDone)),
        healing_done = nonNegInt(SQ.Unsecret(info.healingDone)),
    }
end

local function appendMatch(match)
    local list = SideQuestDB.pending.battlegrounds
    for _, existing in ipairs(list) do
        if existing.id == match.id then
            return
        end
    end
    table.insert(list, match)
    while #list > MAX_PENDING do
        table.remove(list, 1)
    end
    SQ.Fire("SQ_BATTLEGROUND_RECORDED", match)
end

SQ.On("PVP_MATCH_COMPLETE", function()
    local mapName, instanceID = captureInstanceInfo()
    pendingMatch = {
        ended_at = now(),
        duration = matchDuration(),
        winner = winnerWord(),
        map = mapName or "",
        instance_id = instanceID or 0,
        my_faction = myFactionWord(),
        recorder = recorderName(),
    }
    if RequestBattlefieldScoreData then
        RequestBattlefieldScoreData()
    end
end)
SQ.RegisterGameEvent("PVP_MATCH_COMPLETE")

SQ.On("UPDATE_BATTLEFIELD_SCORE", function()
    if not pendingMatch then
        return
    end
    if not GetNumBattlefieldScores then
        pendingMatch = nil
        return
    end
    local total = GetNumBattlefieldScores() or 0
    if total == 0 then
        return -- score data hasn't arrived yet; wait for the next update
    end

    local players = {}
    for i = 1, math.min(total, MAX_PLAYERS) do
        local row = readScoreRow(i)
        if row then
            table.insert(players, row)
        end
    end

    local match = pendingMatch
    pendingMatch = nil
    -- The site rejects a whole export with one invalid match, so a match it can't place (no side, no end time) is
    -- dropped here rather than sent.
    if #players == 0 or not match.my_faction or match.ended_at <= 0 then
        return -- scoreboard unreadable; skip the match entirely
    end

    appendMatch({
        id = match.recorder .. "-" .. tostring(match.ended_at),
        map = match.map ~= "" and match.map or "Battleground",
        instance_id = match.instance_id,
        ended_at = match.ended_at,
        duration = match.duration,
        winner = match.winner,
        my_faction = match.my_faction,
        players = players,
    })
end)
SQ.RegisterGameEvent("UPDATE_BATTLEFIELD_SCORE")

return Battlegrounds
