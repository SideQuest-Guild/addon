-- SideQuest/Signups.lua
-- In-game sign-ups (contract v2 "signups"): a member answers Going/Maybe/
-- Can't for an imported event; officers' addons queue it into
-- pending.signups and ack it back so the member's UI can show "Sent" then
-- "Saved" state.

SideQuest = SideQuest or {}
SideQuest.Signups = {}
local Signups = SideQuest.Signups

local function now()
    return GetServerTime and GetServerTime() or 0
end

local STATUS_MAP = { going = "signed", maybe = "tentative", cant = "absent" }

--- Member action: answer an event. Sends a SIGNUP message to the guild
-- (officers queue it) and marks it locally as "sent, waiting for ack".
function Signups.Answer(eventId, answer, comment, role)
    local status = STATUS_MAP[answer]
    if not status then
        SideQuest.Print("Unknown sign-up answer '" .. tostring(answer) .. "'")
        return
    end
    local character = SideQuest.NormalizeUnit("player")
    local payload = {
        id = SideQuest.NextId(),
        event_id = eventId,
        character = character,
        status = status,
        role = role,
        class = select(1, UnitClass and UnitClass("player")) or nil,
        comment = comment,
        at = now(),
    }
    SideQuestDB.mySignups[eventId] = { status = status, sentAt = now(), acked = false, payload = payload }
    SideQuest.Comm.SendSignup(payload)
    SideQuest.Fire("SQ_SIGNUP_SENT", eventId, status)
end

--- Current local view of my sign-up for an event: "none" | "sent" | "saved".
function Signups.MyState(eventId)
    local row = SideQuestDB.mySignups[eventId]
    if not row then
        return "none", nil
    end
    return row.acked and "saved" or "sent", row.status
end

--------------------------------------------------------------------------
-- Officer side: queue incoming SIGNUP messages, ack them.
--------------------------------------------------------------------------

local function officerQueueSignup(payload)
    local queue = SideQuestDB.pending.signups
    for i, existing in ipairs(queue) do
        if existing.id == payload.id then
            queue[i] = payload
            return
        end
    end
    table.insert(queue, payload)
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, _sender)
    if msgType == "SIGNUP" then
        local ok, decoded = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        if SideQuest.IsOfficer() then
            officerQueueSignup(decoded)
            SideQuest.Comm.SendSignupAck({ id = decoded.id, event_id = decoded.event_id, character = decoded.character })
            SideQuest.Fire("SQ_SIGNUP_QUEUED", decoded)
        end
    elseif msgType == "SIGNUP_ACK" then
        local ok, decoded = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        local row = SideQuestDB.mySignups[decoded.event_id]
        if row and row.payload and row.payload.id == decoded.id then
            row.acked = true
            SideQuest.Fire("SQ_SIGNUP_ACKED", decoded.event_id)
        end
    end
end)

return Signups
