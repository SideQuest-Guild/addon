-- SideQuest/Recorder.lua
-- Officer-side raid night recording: sessions, roster presence, encounters,
-- automatic EP awards, standby and undo.

SideQuest = SideQuest or {}
SideQuest.Recorder = {}
local Recorder = SideQuest.Recorder

local EVENT_LINK_WINDOW = 3 * 60 * 60 -- ±3h

Recorder.current = nil -- pointer into SideQuestDB.pending.sessions, the in-progress session
Recorder.killedThisSession = {} -- encounter_id -> true, reset per session
Recorder.started = false
Recorder.startedAt = nil -- when Start raid was clicked this session
Recorder.ended = false
Recorder.endedAt = nil -- when End raid was clicked this session
Recorder.prepDoneAt = nil -- when Prep was marked done this session
Recorder.inviteDoneAt = nil -- when Invite was marked done this session
Recorder.present = {} -- charName -> "raid" | "standby": who is here right now (EP goes only to them)

local RESUME_WINDOW = 8 * 60 * 60

-- The in-memory pointers above are lost on /reload; SideQuestDB.recording keeps enough to resume the same session.
local function saveRecordingState()
    if not Recorder.current then
        SideQuestDB.recording = nil
        return
    end
    SideQuestDB.recording = {
        session_id = Recorder.current.id,
        started = Recorder.started,
        started_at = Recorder.startedAt,
        ended = Recorder.ended,
        ended_at = Recorder.endedAt,
        killed = Recorder.killedThisSession,
        prep_done_at = Recorder.prepDoneAt,
        invite_done_at = Recorder.inviteDoneAt,
    }
end

local function pending()
    return SideQuestDB.pending
end

local function now()
    return GetServerTime and GetServerTime() or 0
end

--------------------------------------------------------------------------
-- Session lifecycle
--------------------------------------------------------------------------

function Recorder.FindLinkedEvent(startedAt)
    local best, bestDelta = nil, math.huge
    for _, evt in ipairs(SideQuestDB.events or {}) do
        if evt.kind == "raid" or evt.kind == "dungeon" then
            local delta = math.abs((evt.starts_at or 0) - startedAt)
            if delta <= EVENT_LINK_WINDOW and delta < bestDelta then
                best, bestDelta = evt, delta
            end
        end
    end
    return best and best.id or nil
end

--- Another officer currently recording `instanceID` (or any instance, if
-- `instanceID` is nil), per the latest HELLO heard from them; nil if none.
-- Never matches ourselves.
function Recorder.OtherRecorder(instanceID)
    local me = SideQuest.NormalizeUnit("player")
    for char, info in pairs(SideQuestDB.addonVersions or {}) do
        if char ~= me and info.recording and (not instanceID or info.recording.instance_id == instanceID) then
            return { character = char, recording = info.recording }
        end
    end
    return nil
end

--- Whether the current player may start recording right now, and why not
-- if not. Matches the Raid Night recording control's disabled-reason text.
function Recorder.CanRecord()
    if not SideQuest.IsOfficer() then
        return false, "Only officers record raids"
    end
    if not (IsInInstance and IsInInstance()) then
        return false, "Zone into the raid to record"
    end
    local _, instanceType = IsInInstance()
    if instanceType ~= "raid" then
        return false, "Zone into the raid to record"
    end
    return true, nil
end

--- Explicit "Record this raid". Must be called by an officer while inside a
-- raid instance. Creates and opens a new pending session. If another
-- officer is already recording this instance (per their last HELLO) and
-- `force` is not set, prints a warning and returns nil plus that officer's
-- info instead of starting, so the caller can ask to click again to confirm.
function Recorder.StartRecording(instanceName, instanceID, difficultyID, size, force)
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can record a raid.")
        return nil
    end
    if Recorder.current then
        SideQuest.Print("Already recording this raid (" .. (Recorder.current.instance_name or "?") .. ").")
        return Recorder.current
    end
    if not force then
        local other = Recorder.OtherRecorder(instanceID)
        if other then
            SideQuest.Print((other.character or "another officer")
                .. " is already recording this raid. Click Start recording again to record anyway.")
            return nil, other
        end
    end

    local startedAt = now()
    local session = {
        id = SideQuest.NextId(),
        event_id = Recorder.FindLinkedEvent(startedAt),
        instance_name = instanceName,
        instance_id = instanceID,
        difficulty_id = difficultyID,
        size = size,
        started_at = startedAt,
        ended_at = nil,
        members = {},
    }
    table.insert(pending().sessions, session)
    Recorder.current = session
    Recorder.killedThisSession = {}
    Recorder.started = false
    Recorder.startedAt = nil
    Recorder.ended = false
    Recorder.endedAt = nil
    Recorder.prepDoneAt = nil
    Recorder.inviteDoneAt = nil
    SideQuestDB.standby = {} -- a new night starts with an empty standby list
    saveRecordingState()

    SideQuest.Comm.AnnounceRecorder(SideQuest.NormalizeUnit("player"))
    SideQuest.Prep.SayHello() -- tells other officers' "who can record" lists we're recording now
    SideQuest.Print("Recording started for " .. tostring(instanceName) .. ". Other officers should not also record.")
    Recorder.UpdateRoster()

    return session
end

function Recorder.StopRecording()
    if not Recorder.current then
        return
    end
    if not Recorder.current.ended_at then
        Recorder.current.ended_at = now()
    end
    Recorder.current = nil
    Recorder.present = {}
    saveRecordingState()
    SideQuest.Prep.SayHello() -- clears us from other officers' "who can record" lists
end

--- After a /reload or relog inside the same raid, pick the unfinished session back up instead of dropping it.
function Recorder.TryResume(instanceID)
    local state = SideQuestDB.recording
    if not state or Recorder.current then
        return false
    end
    for _, session in ipairs(pending().sessions) do
        if session.id == state.session_id then
            if session.ended_at or session.instance_id ~= instanceID or now() - (session.started_at or 0) > RESUME_WINDOW then
                SideQuestDB.recording = nil
                return false
            end
            Recorder.current = session
            Recorder.started = state.started and true or false
            Recorder.startedAt = state.started_at
            Recorder.ended = state.ended and true or false
            Recorder.endedAt = state.ended_at
            Recorder.killedThisSession = state.killed or {}
            Recorder.prepDoneAt = state.prep_done_at
            Recorder.inviteDoneAt = state.invite_done_at
            Recorder.UpdateRoster()
            SideQuest.Print("Resumed recording " .. tostring(session.instance_name) .. ".")
            return true
        end
    end
    SideQuestDB.recording = nil
    return false
end

--------------------------------------------------------------------------
-- Roster presence
--------------------------------------------------------------------------

function Recorder.UpdateRoster()
    local session = Recorder.current
    if not session then
        return
    end
    if not (IsInRaid and IsInRaid()) then
        return
    end

    local t = now()
    local present = {}
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
        local unit = "raid" .. i
        local charName = SideQuest.NormalizeUnit(unit)
        if charName then
            present[charName] = "raid"
            local class = UnitClass and select(2, UnitClass(unit)) or nil
            local member = session.members[charName]
            if not member then
                member = { character = charName, class = class, first_seen = t, last_seen = t, standby = false }
                session.members[charName] = member
            else
                member.last_seen = t
                member.class = member.class or class
                member.standby = false -- in the raid at some point tonight
            end
        end
    end

    -- standby members outside the raid still get presence rows (standby=true)
    for _, charName in ipairs(SideQuestDB.standby or {}) do
        if not present[charName] then
            present[charName] = "standby"
            local member = session.members[charName]
            if not member then
                session.members[charName] = { character = charName, class = nil, first_seen = t, last_seen = t, standby = true }
            else
                member.last_seen = t
            end
        end
    end
    Recorder.present = present
end

--------------------------------------------------------------------------
-- Encounters
--------------------------------------------------------------------------

function Recorder.OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    local session = Recorder.current
    if not session then
        return
    end
    Recorder.UpdateRoster()

    local characters = {}
    local standby = {}
    for charName, where in pairs(Recorder.present) do
        if where == "standby" then
            table.insert(standby, charName)
        else
            table.insert(characters, charName)
        end
    end
    table.sort(characters)
    table.sort(standby)

    local row = {
        id = SideQuest.NextId(),
        session_id = session.id,
        encounter_id = encounterID,
        name = encounterName,
        size = groupSize,
        difficulty_id = difficultyID,
        success = false,
        started_at = now(),
        ended_at = nil,
        characters = characters,
        standby = standby,
        voided = false,
    }
    table.insert(pending().encounters, row)
    Recorder.activeEncounterRow = row
end

-- Awards go to who is in the raid or on standby right now, never to someone who left earlier in the night.
local function awardToSessionMembers(session, amount, reason, note)
    Recorder.UpdateRoster()
    local names = {}
    for charName in pairs(Recorder.present) do
        table.insert(names, charName)
    end
    table.sort(names)
    local ids = {}
    for _, charName in ipairs(names) do
        table.insert(ids, Recorder.AwardEP(charName, amount, reason, note, session.id))
    end
    return ids
end

function Recorder.OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    local session = Recorder.current
    local row = Recorder.activeEncounterRow
    if not session or not row or row.encounter_id ~= encounterID then
        return
    end
    row.ended_at = now()
    row.success = success and true or false
    Recorder.activeEncounterRow = nil

    local alreadyKilled = false
    for _, id in ipairs(SideQuestDB.killed_encounters or {}) do
        if id == encounterID then
            alreadyKilled = true
            break
        end
    end

    if row.success then
        awardToSessionMembers(session, SideQuest.Rules.Get().ep.boss_kill, "boss_kill", encounterName)
        SideQuest.Fire("SQ_ENCOUNTER_RECORDED", row, not alreadyKilled)
        if not alreadyKilled then
            table.insert(SideQuestDB.killed_encounters, encounterID)
        end
        Recorder.killedThisSession[encounterID] = true
    else
        if not alreadyKilled and not Recorder.killedThisSession[encounterID] then
            awardToSessionMembers(session, SideQuest.Rules.Get().ep.progress, "progress", encounterName)
            Recorder.killedThisSession[encounterID] = true -- once per boss per night, win or lose from here on
        end
    end
    saveRecordingState()
end

--- How many encounter rows (wipes and kills) this session has recorded,
-- for the course's Boss step.
function Recorder.EncounterCountThisSession()
    local session = Recorder.current
    if not session then
        return 0
    end
    local count = 0
    for _, row in ipairs(pending().encounters) do
        if row.session_id == session.id then
            count = count + 1
        end
    end
    return count
end

--------------------------------------------------------------------------
-- Course steps: Prep, Invite, Start raid, End raid
--------------------------------------------------------------------------

--- Mark the Prep course step done; persisted with the recording state if a
-- session is open so it survives a /reload, transient otherwise.
function Recorder.MarkPrepDone()
    Recorder.prepDoneAt = Recorder.prepDoneAt or now()
    if Recorder.current then
        saveRecordingState()
    end
end

--- Mark the Invite course step done; same persistence rule as MarkPrepDone.
function Recorder.MarkInviteDone()
    Recorder.inviteDoneAt = Recorder.inviteDoneAt or now()
    if Recorder.current then
        saveRecordingState()
    end
end

function Recorder.StartRaid()
    local session = Recorder.current
    if not session or Recorder.started then
        return
    end
    Recorder.UpdateRoster()
    Recorder.started = true
    Recorder.startedAt = now()
    awardToSessionMembers(session, SideQuest.Rules.Get().ep.on_time, "on_time", "Start raid")
    saveRecordingState()
end

function Recorder.EndRaid()
    local session = Recorder.current
    if not session or Recorder.ended then
        return
    end
    Recorder.UpdateRoster()
    Recorder.ended = true
    Recorder.endedAt = now()
    session.ended_at = now()
    awardToSessionMembers(session, SideQuest.Rules.Get().ep.full_night, "full_night", "End raid")
    saveRecordingState()
end

--------------------------------------------------------------------------
-- Standby roster
--------------------------------------------------------------------------

function Recorder.AddStandby(charName)
    SideQuestDB.standby = SideQuestDB.standby or {}
    for _, c in ipairs(SideQuestDB.standby) do
        if c == charName then
            return
        end
    end
    table.insert(SideQuestDB.standby, charName)
end

function Recorder.RemoveStandby(charName)
    local list = SideQuestDB.standby or {}
    for i, c in ipairs(list) do
        if c == charName then
            table.remove(list, i)
            return
        end
    end
end

--------------------------------------------------------------------------
-- EP/GP award bookkeeping + undo
--------------------------------------------------------------------------

function Recorder.AwardEP(character, amount, reason, note, sessionId)
    if amount == nil then
        return nil
    end
    local award = {
        id = SideQuest.NextId(),
        session_id = sessionId,
        kind = "ep",
        character = character,
        amount = amount,
        reason = reason,
        note = note,
        loot_id = nil,
        at = now(),
        officer = SideQuest.NormalizeUnit("player"),
        voided = false,
    }
    table.insert(pending().awards, award)
    SideQuest.Print(character .. " +" .. tostring(amount) .. " EP (" .. reason .. ") " .. (note or "")
        .. "  [Undo: /sq undo " .. award.id .. "]")
    return award.id
end

--- Void an award/loot/encounter row by id. The same id is re-exported with
-- voided=true per the contract; nothing is deleted locally.
function Recorder.Undo(id)
    for _, list in ipairs({ pending().awards, pending().loot, pending().encounters }) do
        for _, row in ipairs(list) do
            if row.id == id then
                row.voided = true
                SideQuest.Print("Undid " .. id)
                return true
            end
        end
    end
    SideQuest.Print("Nothing found to undo for id " .. tostring(id))
    return false
end

--------------------------------------------------------------------------
-- Event wiring
--------------------------------------------------------------------------

SideQuest.On("PLAYER_ENTERING_WORLD", function()
    if not (IsInInstance and IsInInstance()) then
        return
    end
    local _, instanceType = IsInInstance()
    if instanceType ~= "raid" or not SideQuest.IsOfficer() or Recorder.current then
        return
    end
    local instanceID = GetInstanceInfo and select(8, GetInstanceInfo()) or nil
    if not Recorder.TryResume(instanceID) then
        SideQuest.Fire("SQ_PROMPT_RECORD")
    end
end)

SideQuest.On("GROUP_ROSTER_UPDATE", function()
    Recorder.UpdateRoster()
end)

SideQuest.On("ENCOUNTER_START", function(encounterID, name, difficultyID, groupSize)
    Recorder.OnEncounterStart(encounterID, name, difficultyID, groupSize)
end)

SideQuest.On("ENCOUNTER_END", function(encounterID, name, difficultyID, groupSize, success)
    Recorder.OnEncounterEnd(encounterID, name, difficultyID, groupSize, success == 1 or success == true)
end)

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, sender)
    if msgType == "RECORDER" then
        -- legacy/compat: an older client announcing it's recording, no instance or HELLO detail.
        local char = payload
        local info = SideQuestDB.addonVersions[char] or {}
        info.seenAt = now()
        info.officer = true
        info.recording = info.recording or { instance = nil, instance_id = nil, since = now() }
        SideQuestDB.addonVersions[char] = info
    elseif msgType == "STANDBY_REQ" then
        if SideQuest.IsOfficer() then
            -- officer UI surfaces the request; auto-add is left to the UI to confirm
            SideQuest.Fire("SQ_STANDBY_REQUESTED", payload, sender)
        end
    end
end)

SideQuest.RegisterSlash("standby", function(rest)
    local who = SideQuest.NormalizeUnit("player")
    if SideQuest.IsOfficer() and Recorder.current then
        Recorder.AddStandby(who)
        SideQuest.Print("Added yourself to standby.")
    else
        local ok = SideQuest.Comm.RequestStandby(who)
        if ok then
            SideQuest.Print("Requested standby.")
        else
            SideQuest.Print("Could not reach the raid (addon messages may be blocked here). Ask an officer to add you.")
        end
    end
end, "mark yourself as standby for tonight's raid")

SideQuest.RegisterSlash("record", function(rest)
    if Recorder.current then
        Recorder.StopRecording()
        SideQuest.Print("Recording stopped.")
        return
    end
    local ok, reason = Recorder.CanRecord()
    if not ok then
        SideQuest.Print(reason)
        return
    end
    local name, _, difficultyID, _, _, _, _, instanceID, groupSize = GetInstanceInfo()
    Recorder.StartRecording(name, instanceID, difficultyID, groupSize)
end, "start or stop recording the current raid")

return Recorder
