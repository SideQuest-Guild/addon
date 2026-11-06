-- SideQuest/Calendar.lua
-- Puts the site's upcoming events (SideQuestDB.events, from the last import) on the in-game guild calendar as
-- guild announcements, and takes them off again when the site moves or cancels them.
--
-- The game only lets C_Calendar.AddEvent run inside a click or key press, so an officer applies the plan one change
-- per click (Console > Sync, or /sq calendar). Calendar events carry no site id, so an announcement matches a site
-- event by its title and its start in realm time. SideQuestDB.calendarLinks remembers where each site event was last
-- seen on the calendar, which is how a moved or cancelled event's old announcement is found and removed.

SideQuest = SideQuest or {}
SideQuest.Calendar = {}
local Calendar = SideQuest.Calendar

local TITLE_MAX_BYTES = 31 -- the calendar's title box takes 31 letters; bytes is the safe reading of that
local BUSY_TIMEOUT = 10 -- seconds to wait for the server to confirm a change before allowing the next one
local REQUEST_THROTTLE = 60 -- seconds between C_Calendar.OpenCalendar requests
local EVENT_URL = "https://sidequest-guild.com/events/detail/?id="

-- Site EventKind -> label and calendar event type, for every kind the import can carry.
local KINDS = {
    raid = { label = "Raid", type = "Raid" },
    dungeon = { label = "Dungeon", type = "Dungeon" },
    world_boss = { label = "World Boss", type = "Raid" },
    leveling = { label = "Leveling" },
    pvp = { label = "PvP", type = "PvP" },
    social = { label = "Social", type = "Meeting" },
    transmog = { label = "Transmog", type = "Meeting" },
    other = { label = "Other" },
}

-- Enum.CalendarEventType values, for clients where the Enum table isn't filled in.
local EVENT_TYPE_FALLBACK = { Raid = 0, Dungeon = 1, PvP = 2, Meeting = 3, Other = 4 }

Calendar.busyUntil = 0
Calendar.lastRequestAt = nil
-- Set by the first CALENDAR_UPDATE_EVENT_LIST. Until then the calendar reads as empty, and planning against it
-- would add every event a second time.
Calendar.loaded = false

local function now()
    return GetServerTime and GetServerTime() or 0
end

local function eventType(name)
    local enum = Enum and Enum.CalendarEventType
    return (enum and enum[name]) or EVENT_TYPE_FALLBACK[name]
end

local function links()
    return SideQuestDB.calendarLinks
end

--- Whether this client has the calendar calls the sync needs.
function Calendar.IsAvailable()
    return C_Calendar ~= nil and C_Calendar.AddEvent ~= nil and C_Calendar.GetDayEvent ~= nil
        and C_DateAndTime ~= nil and C_DateAndTime.GetCurrentCalendarTime ~= nil
end

--------------------------------------------------------------------------
-- Realm time
--------------------------------------------------------------------------

-- Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's days_from_civil).
local function daysFromCivil(y, m, d)
    if m <= 2 then
        y = y - 1
    end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

--- Seconds the realm's wall clock runs ahead of UTC, rounded to the quarter hour (the calendar has no seconds).
function Calendar.RealmOffset()
    local t = C_DateAndTime.GetCurrentCalendarTime()
    local wallAsUtc = daysFromCivil(t.year, t.month, t.monthDay) * 86400 + t.hour * 3600 + t.minute * 60
    return math.floor((wallAsUtc - now()) / 900 + 0.5) * 900
end

--- A Unix time as the realm's calendar date and time: { year, month, day, hour, minute }.
function Calendar.ToRealmTime(ts, offset)
    local t = date("!*t", ts + (offset or Calendar.RealmOffset()))
    return { year = t.year, month = t.month, day = t.day, hour = t.hour, minute = t.min }
end

local function placeKey(p)
    return string.format("%04d-%02d-%02d %02d:%02d", p.year, p.month, p.day, p.hour, p.minute)
end

--------------------------------------------------------------------------
-- What the calendar should hold
--------------------------------------------------------------------------

--- The site title cut to what the calendar keeps, never splitting a UTF-8 character.
function Calendar.Title(title)
    title = tostring(title or "Event")
    if #title <= TITLE_MAX_BYTES then
        return title
    end
    local cut = TITLE_MAX_BYTES
    -- step back over continuation bytes (10xxxxxx) so the cut lands before a character's lead byte
    while cut > 0 and title:byte(cut + 1) and title:byte(cut + 1) >= 128 and title:byte(cut + 1) < 192 do
        cut = cut - 1
    end
    return title:sub(1, cut)
end

local function description(evt)
    local kind = KINDS[evt.kind]
    return (kind and kind.label or "Guild event") .. " from sidequest-guild.com. Sign up in the SideQuest addon (/sq) or at "
        .. EVENT_URL .. tostring(evt.id)
end

local function desired(evt, offset)
    local place = Calendar.ToRealmTime(evt.starts_at, offset)
    return { title = Calendar.Title(evt.title), at = evt.starts_at, year = place.year, month = place.month,
        day = place.day, hour = place.hour, minute = place.minute }
end

--------------------------------------------------------------------------
-- Reading the calendar
--------------------------------------------------------------------------

local unreadable = {} -- sentinel: the calendar holds secret values right now

-- Where a guild announcement with this title and start sits on the calendar: (monthOffset, day, index), nil when
-- it isn't there, or `unreadable` when the calendar can't be read right now.
local function findAnnouncement(place)
    local shown = C_Calendar.GetMonthInfo(0)
    local monthOffset = (place.year * 12 + place.month) - (shown.year * 12 + shown.month)
    for index = 1, C_Calendar.GetNumDayEvents(monthOffset, place.day) do
        local e = C_Calendar.GetDayEvent(monthOffset, place.day, index)
        if e and e.calendarType == "GUILD_ANNOUNCEMENT" then
            local title = SideQuest.Unsecret(e.title)
            if title == nil then
                return unreadable
            end
            if title == place.title and e.startTime.hour == place.hour and e.startTime.minute == place.minute then
                return { monthOffset = monthOffset, day = place.day, index = index }
            end
        end
    end
    return nil
end

local function samePlace(a, b)
    return a.title == b.title and placeKey(a) == placeKey(b)
end

--- The changes that would make the guild calendar match the imported events, removals first, then additions by
-- start time. Each action is { op = "add", event, place } or { op = "remove", siteId, place, slot }.
-- Also records the calendar position of every site event already on it, so a later move can be cleaned up even when
-- another officer added it. Returns nil and a reason when the calendar can't be planned against.
function Calendar.Plan()
    if not Calendar.IsAvailable() then
        return nil, "This client has no guild calendar."
    end
    if not Calendar.loaded then
        Calendar.Request()
        return nil, "Loading the calendar from the server..."
    end
    local offset = Calendar.RealmOffset()
    local cutoff = now() + 5 * 60 -- the calendar refuses events that start in the past; leave room for the click
    local maxDate = C_Calendar.GetMaxCreateDate and C_Calendar.GetMaxCreateDate()
    local maxKey = maxDate and string.format("%04d-%02d-%02d 23:59", maxDate.year, maxDate.month, maxDate.monthDay)
    local linked = links()

    local wanted = {}
    for _, evt in ipairs(SideQuest.Events.Get()) do
        if evt.id and evt.starts_at and evt.starts_at >= cutoff then
            local place = desired(evt, offset)
            if not maxKey or placeKey(place) <= maxKey then
                wanted[#wanted + 1] = { event = evt, place = place }
            end
        end
    end
    table.sort(wanted, function(a, b)
        return a.event.starts_at < b.event.starts_at
    end)

    local removes, adds = {}, {}
    local seen = {}
    for _, w in ipairs(wanted) do
        local siteId = w.event.id
        seen[siteId] = true
        local link = linked[siteId]
        local moving = false
        if link and not samePlace(link, w.place) and link.at and link.at >= cutoff then
            local slot = findAnnouncement(link)
            if slot == unreadable then
                return nil, "The calendar can't be read right now. Try again out of combat."
            elseif slot then
                removes[#removes + 1] = { op = "remove", siteId = siteId, place = link, slot = slot }
                moving = true
            end
        end
        local found = findAnnouncement(w.place)
        if found == unreadable then
            return nil, "The calendar can't be read right now. Try again out of combat."
        elseif not found then
            adds[#adds + 1] = { op = "add", event = w.event, place = w.place }
        elseif not moving then
            linked[siteId] = w.place -- keep the old position until its announcement is removed
        end
    end

    for siteId, link in pairs(linked) do
        if not seen[siteId] then
            local slot = link.at and link.at >= cutoff and findAnnouncement(link)
            if slot == unreadable then
                return nil, "The calendar can't be read right now. Try again out of combat."
            elseif slot then
                removes[#removes + 1] = { op = "remove", siteId = siteId, place = link, slot = slot }
            else
                linked[siteId] = nil -- gone already, or in the past: nothing left to clean up
            end
        end
    end

    local actions = removes
    for _, a in ipairs(adds) do
        actions[#actions + 1] = a
    end
    return actions
end

--------------------------------------------------------------------------
-- Changing the calendar (one change per click)
--------------------------------------------------------------------------

function Calendar.IsBusy()
    if Calendar.busyUntil > now() then
        return true
    end
    return C_Calendar.IsActionPending ~= nil and C_Calendar.IsActionPending()
end

local function markBusy()
    Calendar.busyUntil = now() + BUSY_TIMEOUT
    if C_Timer and C_Timer.After then
        C_Timer.After(BUSY_TIMEOUT, function()
            SideQuest.Fire("SQ_CALENDAR_CHANGED")
        end)
    end
end

-- The calendar's raid or dungeon art whose name is in the event title (the longest match wins, so "Blackwing Lair"
-- beats "Lair"), as an index for EventSetTextureID.
local function textureFor(typeValue, title)
    local textures = C_Calendar.EventGetTextures and C_Calendar.EventGetTextures(typeValue)
    local lowerTitle = title:lower()
    local best, bestLen = nil, 0
    for index, tex in ipairs(textures or {}) do
        local name = tex.title and tex.title:lower()
        if name and #name > bestLen and lowerTitle:find(name, 1, true) then
            best, bestLen = index, #name
        end
    end
    return best
end

-- Raids and dungeons show their instance art only when one is picked, as in the game's own event window; anything
-- without a matching instance goes on as "Other" rather than a raid with no picture.
local function setEventType(evt)
    local kind = KINDS[evt.kind]
    local typeName = kind and kind.type
    if typeName == "Raid" or typeName == "Dungeon" then
        local texture = textureFor(eventType(typeName), tostring(evt.title or ""))
        if texture then
            C_Calendar.EventSetType(eventType(typeName))
            C_Calendar.EventSetTextureID(texture)
            return
        end
        typeName = nil
    end
    C_Calendar.EventSetType(eventType(typeName or "Other"))
end

local function describePlace(place)
    return place.title .. " (" .. placeKey(place) .. ")"
end

local function remove(action)
    local s = action.slot
    C_Calendar.ContextMenuSelectEvent(s.monthOffset, s.day, s.index)
    -- Either way the link is done: removed, or left to the officers whose rank can remove it.
    links()[action.siteId] = nil
    if not C_Calendar.ContextMenuEventCanRemove(s.monthOffset, s.day, s.index) then
        SideQuest.Print("Your guild rank can't remove " .. describePlace(action.place) .. " from the calendar.")
        return
    end
    C_Calendar.ContextMenuEventRemove()
    markBusy()
    SideQuest.Print("Removed " .. describePlace(action.place) .. " from the guild calendar.")
end

local function add(action)
    local evt, place = action.event, action.place
    C_Calendar.CreateGuildAnnouncementEvent()
    C_Calendar.EventSetTitle(place.title)
    C_Calendar.EventSetDescription(description(evt))
    setEventType(evt)
    C_Calendar.EventSetDate(place.month, place.day, place.year)
    C_Calendar.EventSetTime(place.hour, place.minute)
    if not C_Calendar.CanAddEvent() then
        C_Calendar.CloseEvent()
        SideQuest.Print("Your guild rank can't add guild calendar events. A rank with calendar rights has to do this.")
        return
    end
    C_Calendar.AddEvent()
    links()[evt.id] = place
    markBusy()
    SideQuest.Print("Added " .. describePlace(place) .. " to the guild calendar.")
end

--- Make the next change the plan calls for. Must run inside a click or key press: the game refuses
-- C_Calendar.AddEvent otherwise.
function Calendar.Step()
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can update the guild calendar.")
        return
    end
    if not Calendar.IsAvailable() then
        SideQuest.Print("This client has no guild calendar.")
        return
    end
    if Calendar.IsBusy() then
        SideQuest.Print("The calendar is still saving the last change. Try again in a moment.")
        return
    end
    local actions, reason = Calendar.Plan()
    if not actions then
        SideQuest.Print(reason)
        return
    end
    local action = actions[1]
    if not action then
        SideQuest.Print("The guild calendar already matches the site's events.")
        return
    end
    if action.op == "remove" then
        remove(action)
    else
        add(action)
    end
    SideQuest.Fire("SQ_CALENDAR_CHANGED")
end

--- Ask the server for the calendar, at most once a minute; CALENDAR_UPDATE_EVENT_LIST answers.
function Calendar.Request()
    if not (C_Calendar and C_Calendar.OpenCalendar) then
        return
    end
    local t = now()
    if Calendar.lastRequestAt and t - Calendar.lastRequestAt < REQUEST_THROTTLE then
        return
    end
    Calendar.lastRequestAt = t
    C_Calendar.OpenCalendar()
end

SideQuest.RegisterSlash("calendar", function()
    Calendar.Step()
end, "calendar - put the next site event on the guild calendar (officers; run it again for each change)")

SideQuest.On("CALENDAR_UPDATE_EVENT_LIST", function()
    Calendar.loaded = true
    Calendar.busyUntil = 0
    SideQuest.Fire("SQ_CALENDAR_CHANGED")
end)
SideQuest.RegisterGameEvent("CALENDAR_UPDATE_EVENT_LIST")

SideQuest.On("CALENDAR_UPDATE_ERROR", function(reason)
    Calendar.busyUntil = 0
    local text = reason and _G[reason] or reason
    SideQuest.Print("The calendar refused the change: " .. tostring(text))
    SideQuest.Fire("SQ_CALENDAR_CHANGED")
end)
SideQuest.RegisterGameEvent("CALENDAR_UPDATE_ERROR")

--------------------------------------------------------------------------
-- Prompting officers (nearly automatic, not fully: AddEvent still needs a click)
--------------------------------------------------------------------------

-- Whether this login/import's prompt has already been offered or turned down. A fresh import resets both, so a
-- newly-arrived change gets its own chance even if the officer said Later to the last one.
Calendar.prompted = false
Calendar.promptSilenced = false

-- C_Calendar.CanAddEvent() only answers for the event currently being built (Blizzard's own calendar UI calls it
-- alongside C_Calendar.EventGetCalendarType() while a candidate is open -- Blizzard_Calendar/Mainline/Blizzard_
-- Calendar.lua), so there's no way to ask "can this rank add guild events" without opening one. The prompt uses
-- the same SideQuest.IsOfficer() rank gate Step() already uses instead.
StaticPopupDialogs["SIDEQUEST_CALENDAR_PENDING"] = {
    text = "%s",
    button1 = "Add next",
    button2 = "Later",
    OnAccept = function()
        Calendar.Step()
        local actions = Calendar.Plan()
        if actions and #actions > 0 then
            Calendar.ShowPrompt(#actions)
        end
    end,
    OnCancel = function()
        Calendar.promptSilenced = true
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Calendar.ShowPrompt(count)
    local text = count == 1 and "1 site event isn't on the guild calendar yet."
        or (count .. " site events aren't on the guild calendar yet.")
    StaticPopup_Show("SIDEQUEST_CALENDAR_PENDING", text)
end

--- Offer an officer who can edit the calendar a one-click way to catch it up, at most once per login or import.
-- "Later" (or Esc) silences it until the next import arrives. Members never see it.
function Calendar.CheckPrompt()
    if Calendar.prompted or Calendar.promptSilenced or not SideQuest.IsOfficer() then
        return
    end
    local actions = Calendar.Plan()
    if not actions or #actions == 0 then
        return
    end
    Calendar.prompted = true
    Calendar.ShowPrompt(#actions)
end

SideQuest.On("SQ_CALENDAR_CHANGED", Calendar.CheckPrompt) -- covers login, once the calendar list has loaded

SideQuest.On("SQ_IMPORT_APPLIED", function()
    Calendar.prompted = false
    Calendar.promptSilenced = false
    Calendar.CheckPrompt()
end)

return Calendar
