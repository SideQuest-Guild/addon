-- SideQuest/Events.lua
-- Upcoming events imported from the site, plus the officer "Invite signed"
-- action.

SideQuest = SideQuest or {}
SideQuest.Events = {}
local Events = SideQuest.Events

function Events.Get()
    return SideQuestDB.events or {}
end

function Events.Find(eventId)
    for _, evt in ipairs(Events.Get()) do
        if evt.id == eventId then
            return evt
        end
    end
    return nil
end

--- Signed, non-bench sign-ups in chart order (group, then original order).
function Events.SignedRoster(evt)
    local roster = {}
    for i, signup in ipairs(evt.signups or {}) do
        if signup.status == "signed" and not signup.bench then
            roster[#roster + 1] = { signup = signup, order = i }
        end
    end
    table.sort(roster, function(a, b)
        local ga, gb = a.signup.group or math.huge, b.signup.group or math.huge
        if ga ~= gb then
            return ga < gb
        end
        return a.order < b.order
    end)
    local out = {}
    for i, entry in ipairs(roster) do
        out[i] = entry.signup
    end
    return out
end

--- Invite every signed, non-benched sign-up for the event, converting the
-- current group to a raid first when the headcount requires it.
function Events.InviteSigned(eventId)
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can mass-invite.")
        return
    end
    local evt = Events.Find(eventId)
    if not evt then
        SideQuest.Print("Unknown event " .. tostring(eventId))
        return
    end

    local roster = Events.SignedRoster(evt)
    local currentCount = GetNumGroupMembers and GetNumGroupMembers() or 0
    if (currentCount + #roster) > 5 and not (IsInRaid and IsInRaid()) then
        if ConvertToRaid then
            ConvertToRaid()
        end
    end

    local invited = {}
    for _, signup in ipairs(roster) do
        if InviteUnit then
            InviteUnit(signup.character)
        end
        invited[#invited + 1] = signup.character
    end
    SideQuest.Print("Invited " .. #invited .. " signed member(s) for " .. tostring(evt.title))
    return invited
end

return Events
