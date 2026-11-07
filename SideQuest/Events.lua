-- SideQuest/Events.lua
-- Events imported from the site (upcoming with sign-ups, recent past ones
-- as answer counts), plus the officer "Invite signed" action. Officers get
-- them from the site's import; everyone else from an officer's standings
-- broadcast (Standings.lua).

SideQuest = SideQuest or {}
SideQuest.Events = {}
local Events = SideQuest.Events

-- Same as the site's import window: an event stays "upcoming" until 6h after it starts.
Events.UPCOMING_GRACE = 6 * 3600

local function now()
    return GetServerTime and GetServerTime() or 0
end

function Events.Get()
    return SideQuestDB.events or {}
end

--- Whether site events ever reached this addon (an import or an officer's
-- broadcast), even if none were scheduled.
function Events.EverReceived()
    return (SideQuestDB.eventsAt or 0) > 0 or #Events.Get() > 0
end

--- Imported events that haven't passed yet, soonest first. The stored list
-- only changes on an import, so events that started since then drop out here.
function Events.Upcoming()
    local cutoff = now() - Events.UPCOMING_GRACE
    local out = {}
    for _, evt in ipairs(Events.Get()) do
        if (evt.starts_at or 0) >= cutoff then
            out[#out + 1] = evt
        end
    end
    return out
end

local function compactPast(evt)
    local counts = { signed = 0, tentative = 0, absent = 0 }
    for _, s in ipairs(evt.signups or {}) do
        if counts[s.status] then
            counts[s.status] = counts[s.status] + 1
        end
    end
    return {
        id = evt.id, title = evt.title, kind = evt.kind, starts_at = evt.starts_at, size = evt.size,
        going = evt.going or counts.signed, maybe = evt.maybe or counts.tentative, cant = evt.cant or counts.absent,
    }
end

--- Events that already happened, newest first: the site's recent past events
-- plus imported ones that have passed since the import.
function Events.Past()
    local cutoff = now() - Events.UPCOMING_GRACE
    local out, seen = {}, {}
    for _, evt in ipairs(Events.Get()) do
        if (evt.starts_at or 0) < cutoff and evt.id and not seen[evt.id] then
            seen[evt.id] = true
            out[#out + 1] = compactPast(evt)
        end
    end
    for _, evt in ipairs(SideQuestDB.pastEvents or {}) do
        if evt.id and not seen[evt.id] then
            seen[evt.id] = true
            out[#out + 1] = evt
        end
    end
    table.sort(out, function(a, b) return (a.starts_at or 0) > (b.starts_at or 0) end)
    return out
end

--- Store the site's events from an import or an officer's broadcast. Past
-- events keep only their answer counts, which keeps the broadcast small.
-- `past` is nil from sites/officers that predate past events: keep what we had.
function Events.Load(upcoming, past, generatedAt)
    SideQuestDB.events = upcoming
    if past then
        local rows = {}
        for i, evt in ipairs(past) do
            rows[i] = compactPast(evt)
        end
        SideQuestDB.pastEvents = rows
    end
    SideQuestDB.eventsAt = generatedAt or now()
    SideQuest.Fire("SQ_EVENTS_UPDATED")
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
        SideQuest.ConvertToRaid()
    end

    local invited = {}
    for _, signup in ipairs(roster) do
        SideQuest.Invite(signup.character)
        invited[#invited + 1] = signup.character
    end
    SideQuest.Print("Invited " .. #invited .. " signed member(s) for " .. tostring(evt.title))
    return invited
end

return Events
