-- tests/test_calendar.lua
-- Calendar.lua: putting the site's events on the in-game guild calendar as guild events (WoW: Forever has no guild
-- announcements), in realm time, one change per Step, and taking moved or cancelled events back off.

return function(h)
    local Calendar = SideQuest.Calendar
    local HOUR, DAY = 3600, 86400

    local function reset()
        h.resetAddon()
        WowStub.ResetCalendar()
        Calendar.busyUntil = 0
        Calendar.lastRequestAt = nil
        Calendar.firstRequestAt = nil
        Calendar.prompted = false
        Calendar.promptSilenced = false
        WowStub.activePopup = nil
        WowStub.isOfficer = true
        SideQuest.Fire("CALENDAR_UPDATE_EVENT_LIST") -- the server has sent the calendar
    end

    -- The server confirming the last change, as CALENDAR_UPDATE_EVENT_LIST does in game.
    local function step()
        Calendar.Step()
        SideQuest.Fire("CALENDAR_UPDATE_EVENT_LIST")
    end

    local function lastLine()
        return WowStub.chatLog[#WowStub.chatLog] or ""
    end

    -- A UTC time `days` from now at hh:mm UTC.
    local function utcAt(days, hh, mm)
        local base = WowStub.time - WowStub.time % DAY
        return base + days * DAY + hh * HOUR + (mm or 0) * 60
    end

    local function realmDate(ts)
        return date("!*t", ts + WowStub.calendar.realmOffset)
    end

    h.test("calendar: nothing is added before the server has sent the calendar", function()
        reset()
        Calendar.loaded = false
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 0, "an unloaded calendar reads as empty; adding now would duplicate")
        h.assertEq(WowStub.calendar.openCalendarCalls, 1, "asked the server for the calendar")
        h.assertTrue(lastLine():find("Loading the calendar") ~= nil, "says it's loading")
        SideQuest.Fire("CALENDAR_UPDATE_EVENT_LIST")
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 1, "adds once the calendar is in")
    end)

    h.test("calendar: with no word from the server, it plans once the request has had time to land", function()
        reset()
        Calendar.loaded = false
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 0, "nothing added straight after asking")
        h.assertTrue(WowStub.calendar.absMonth ~= nil, "opened the calendar on this month, as Blizzard's does")
        WowStub.Advance(11) -- CALENDAR_UPDATE_EVENT_LIST never comes (as after a /reload)
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 1, "adds once the client's calendar has had time to fill")
    end)

    h.test("calendar: entries already in this month mean the calendar is in", function()
        reset()
        Calendar.loaded = false
        local today = date("!*t", WowStub.time + WowStub.calendar.realmOffset)
        table.insert(WowStub.calendar.events, { title = "Fishing Extravaganza", calendarType = "HOLIDAY",
            year = today.year, month = today.month, day = today.day, hour = 14, minute = 0 })
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        Calendar.Step() -- asks; the holiday shows the month is filled
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 2, "the site event goes on without waiting")
    end)

    h.test("calendar: a site event goes on as a guild event at the realm's local time", function()
        reset()
        WowStub.calendar.realmOffset = -6 * HOUR -- realm six hours behind UTC
        local startsAt = utcAt(3, 1, 30) -- 01:30 UTC is 19:30 the evening before on the realm
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = startsAt } }

        step()

        h.assertEq(#WowStub.calendar.events, 1, "one announcement added")
        local e = WowStub.calendar.events[1]
        local want = realmDate(startsAt)
        h.assertEq(e.calendarType, "GUILD_EVENT", "a guild event: Forever has no guild announcements")
        h.assertEq(e.title, "Molten Core", "title")
        h.assertEq(e.year * 10000 + e.month * 100 + e.day, want.year * 10000 + want.month * 100 + want.day,
            "dated on the realm's calendar day, the day before the UTC date")
        h.assertEq(e.hour, 19, "realm hour")
        h.assertEq(e.minute, 30, "realm minute")
        h.assertTrue(e.description:find("events/detail/?id=evt-1", 1, true) ~= nil, "description links the sign-up page")
        h.assertTrue(#e.description <= 255, "fits the calendar's 255-letter description box")
    end)

    h.test("calendar: once on the calendar, the next step changes nothing", function()
        reset()
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        step()
        h.assertEq(#Calendar.Plan(), 0, "plan is empty after the add")
        step()
        h.assertEq(WowStub.calendar.addCalls, 1, "no second add")
        h.assertTrue(lastLine():find("already matches") ~= nil, "says the calendar already matches")
    end)

    h.test("calendar: one change per step, in start order", function()
        reset()
        SideQuestDB.events = {
            { id = "late", title = "Onyxia", kind = "raid", starts_at = utcAt(5, 19) },
            { id = "early", title = "Scholomance", kind = "dungeon", starts_at = utcAt(1, 19) },
        }
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 1, "only one event per step: the game allows one add per click")
        h.assertEq(WowStub.calendar.events[1].title, "Scholomance", "earliest first")
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 1, "refuses while the server hasn't confirmed the last change")
        SideQuest.Fire("CALENDAR_UPDATE_EVENT_LIST")
        Calendar.Step()
        h.assertEq(#WowStub.calendar.events, 2, "next step adds the second")
    end)

    h.test("calendar: a raid named after an instance gets that instance's art; others go on as Other", function()
        reset()
        local RAID, OTHER = Enum.CalendarEventType.Raid, Enum.CalendarEventType.Other
        WowStub.calendar.textures[RAID] = { { title = "Lair" }, { title = "Blackwing Lair" }, { title = "Molten Core" } }
        SideQuestDB.events = {
            { id = "bwl", title = "Blackwing Lair - week 2", kind = "raid", starts_at = utcAt(1, 19) },
            { id = "wb", title = "Azuregos hunt", kind = "world_boss", starts_at = utcAt(2, 19) },
        }
        step()
        step()
        local byTitle = {}
        for _, e in ipairs(WowStub.calendar.events) do
            byTitle[e.title] = e
        end
        h.assertEq(byTitle["Blackwing Lair - week 2"].eventType, RAID, "raid type")
        h.assertEq(byTitle["Blackwing Lair - week 2"].textureIndex, 2, "the longest instance name in the title wins")
        h.assertEq(byTitle["Azuregos hunt"].eventType, OTHER, "no instance art to show: Other")
        h.assertEq(byTitle["Azuregos hunt"].textureIndex, nil, "no texture set")
    end)

    h.test("calendar: a moved event is edited in place over two clicks, not deleted and added", function()
        reset()
        local evt = { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) }
        SideQuestDB.events = { evt }
        step()
        evt.starts_at = utcAt(3, 20)

        local plan = Calendar.Plan()
        h.assertEq(#plan, 1, "one change")
        h.assertEq(plan[1].op, "edit", "an edit")
        step()
        h.assertTrue(lastLine():find("Opened Molten Core", 1, true) ~= nil, "the first click opens it")
        h.assertEq(WowStub.calendar.events[1].hour, 19, "nothing saved yet")
        step()
        h.assertEq(#WowStub.calendar.events, 1, "still one event")
        h.assertEq(WowStub.calendar.events[1].hour, 20, "at the new time")
        h.assertTrue(lastLine():find("Updated Molten Core", 1, true) ~= nil, "the second click saves it")
        h.assertEq(#Calendar.Plan(), 0, "in sync")
    end)

    h.test("calendar: an edit whose open event was swapped out opens it again instead of saving onto the wrong one", function()
        reset()
        local evt = { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) }
        SideQuestDB.events = { evt }
        step()
        evt.starts_at = utcAt(3, 20)
        step() -- opens Molten Core
        WowStub.calendar.candidate = { title = "Someone's alt run", year = 2000, month = 1, day = 1, hour = 1,
            minute = 0 } -- an officer opened another event in the game's window
        step()
        h.assertEq(WowStub.calendar.events[1].hour, 19, "nothing saved onto the other event or this one")
        h.assertTrue(lastLine():find("Opened Molten Core", 1, true) ~= nil, "opened again")
        step()
        h.assertEq(WowStub.calendar.events[1].hour, 20, "then saved")
    end)

    h.test("calendar: a cancelled event is left for an officer to delete by hand; a past one stays as history", function()
        reset()
        SideQuestDB.events = {
            { id = "cancelled", title = "Onyxia", kind = "raid", starts_at = utcAt(2, 19) },
            { id = "past", title = "Zul'Gurub", kind = "raid", starts_at = WowStub.time + HOUR },
        }
        step()
        step()
        h.assertEq(#WowStub.calendar.events, 2, "both added")

        WowStub.Advance(2 * HOUR) -- Zul'Gurub has started; the next import drops it, and Onyxia was cancelled
        SideQuestDB.events = {}
        step()
        h.assertTrue(lastLine():find("Delete Onyxia", 1, true) ~= nil, "says to delete it by hand: " .. lastLine())
        h.assertEq(next(SideQuestDB.calendarLinks), nil, "no links left")
        step()
        h.assertTrue(lastLine():find("already matches") ~= nil, "said once, then nothing more to do")
    end)

    h.test("calendar: a cancelled event comes off where the client lets an addon delete it", function()
        reset()
        WowStub.calendar.canRemove = true
        SideQuestDB.events = { { id = "cancelled", title = "Onyxia", kind = "raid", starts_at = utcAt(2, 19) } }
        step()
        SideQuestDB.events = {}
        step()
        h.assertEq(#WowStub.calendar.events, 0, "removed")
    end)

    h.test("calendar: adopts another officer's announcement, then still moves it when the event moves", function()
        reset()
        local startsAt = utcAt(2, 19)
        local p = realmDate(startsAt)
        WowStub.calendar.events[1] = { calendarType = "GUILD_ANNOUNCEMENT", title = "Molten Core",
            year = p.year, month = p.month, day = p.day, hour = p.hour, minute = p.min }
        local evt = { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = startsAt }
        SideQuestDB.events = { evt }

        h.assertEq(#Calendar.Plan(), 0, "already on the calendar: nothing to add")
        evt.starts_at = utcAt(2, 21)
        step()
        step()
        h.assertEq(#WowStub.calendar.events, 1, "the other officer's copy was replaced, not duplicated")
        h.assertEq(WowStub.calendar.events[1].hour, 21, "at the new time")
    end)

    h.test("calendar: a guild event someone already made for it is adopted; other entries are left alone", function()
        reset()
        local p = realmDate(utcAt(2, 19))
        WowStub.calendar.events[1] = { calendarType = "GUILD_EVENT", title = "Bank day",
            year = p.year, month = p.month, day = p.day, hour = 19, minute = 0 }
        WowStub.calendar.events[2] = { calendarType = "GUILD_EVENT", title = "Molten Core",
            year = p.year, month = p.month, day = p.day, hour = 20, minute = 0 }
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        local plan = Calendar.Plan()
        h.assertEq(#plan, 1, "a same-titled event at another time isn't ours")
        h.assertEq(plan[1].op, "add", "adds its own")

        WowStub.calendar.events[2].hour = 19 -- an officer made it by hand at the right time
        h.assertEq(#Calendar.Plan(), 0, "adopted: no duplicate")
        h.assertEq(#WowStub.calendar.events, 2, "nothing removed")
    end)

    h.test("calendar: a rank without calendar rights gets told, and nothing is half-made", function()
        reset()
        WowStub.calendar.canAdd = false
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        step()
        h.assertEq(#WowStub.calendar.events, 0, "nothing added")
        h.assertEq(WowStub.calendar.candidate, nil, "the draft event was closed")
        h.assertEq(next(SideQuestDB.calendarLinks), nil, "nothing recorded as on the calendar")
        h.assertTrue(lastLine():find("can't add guild calendar events") ~= nil, "explains the rank")
    end)

    h.test("calendar: members can't run it", function()
        reset()
        WowStub.isOfficer = false
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        step()
        h.assertEq(#WowStub.calendar.events, 0, "nothing added")
        h.assertTrue(lastLine():find("Only officers") ~= nil, "says officers only")
    end)

    h.test("calendar: long titles are cut to 31 bytes without splitting a character", function()
        h.assertEq(Calendar.Title("Short"), "Short", "short titles unchanged")
        local ascii = string.rep("a", 40)
        h.assertEq(#Calendar.Title(ascii), 31, "cut to 31 bytes")
        -- 30 ASCII bytes then a 2-byte character: byte 31 is its lead byte, so the whole character goes
        local cut = Calendar.Title(string.rep("a", 30) .. "\195\169" .. "zz")
        h.assertEq(cut, string.rep("a", 30), "the split character is dropped whole")
    end)

    h.test("calendar: a pending plan prompts the officer once per login or import", function()
        reset()
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        SideQuest.Fire("SQ_IMPORT_APPLIED")
        h.assertTrue(WowStub.activePopup ~= nil, "shows a popup")
        h.assertTrue(WowStub.activePopup.text:find("1 site event") ~= nil, "says how many")
        h.assertTrue(Calendar.prompted, "marked as shown")
        local shown = WowStub.activePopup
        SideQuest.Fire("SQ_CALENDAR_CHANGED")
        h.assertEq(WowStub.activePopup, shown, "does not prompt twice for the same login or import")
    end)

    h.test("calendar: Later silences the prompt until the next import", function()
        reset()
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        SideQuest.Fire("SQ_IMPORT_APPLIED")
        h.assertTrue(WowStub.activePopup ~= nil, "shows a popup")
        WowStub.ClickPopupButton(2) -- Later
        h.assertTrue(Calendar.promptSilenced, "silenced")
        h.assertEq(WowStub.activePopup, nil, "popup closed")
        SideQuest.Fire("CALENDAR_UPDATE_EVENT_LIST")
        h.assertEq(WowStub.activePopup, nil, "stays quiet without a new import")
        SideQuest.Fire("SQ_IMPORT_APPLIED")
        h.assertTrue(WowStub.activePopup ~= nil, "a new import gets its own chance")
    end)

    h.test("calendar: members never see the calendar prompt", function()
        reset()
        WowStub.isOfficer = false
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        SideQuest.Fire("SQ_IMPORT_APPLIED")
        h.assertEq(WowStub.activePopup, nil, "no popup for members")
    end)

    h.test("calendar: the prompt's Add next steps one change, then offers the next", function()
        reset()
        SideQuestDB.events = {
            { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) },
            { id = "evt-2", title = "Onyxia's Lair", kind = "raid", starts_at = utcAt(3, 20) },
        }
        SideQuest.Fire("SQ_IMPORT_APPLIED")
        h.assertTrue(WowStub.activePopup ~= nil, "shows a popup")
        WowStub.ClickPopupButton(1) -- Add next
        h.assertEq(#WowStub.calendar.events, 1, "one change made")
        h.assertTrue(WowStub.activePopup ~= nil, "re-shows while changes remain")
        h.assertTrue(WowStub.activePopup.text:find("1 site event") ~= nil, "one change left")
    end)

    h.test("calendar: a recruitment drive gets two locked Other events: its title at starts_at, 'Ends: <title>' at ends_at", function()
        reset()
        SideQuestDB.events = {
            { id = "drive-1", title = "Spring Recruitment", kind = "recruitment",
                starts_at = utcAt(1, 19), ends_at = utcAt(15, 19) },
        }
        step()
        step()
        h.assertEq(#WowStub.calendar.events, 2, "both events added")
        local byTitle = {}
        for _, e in ipairs(WowStub.calendar.events) do
            byTitle[e.title] = e
        end
        h.assertTrue(byTitle["Spring Recruitment"] ~= nil, "start event present")
        h.assertTrue(byTitle["Ends: Spring Recruitment"] ~= nil, "end event present")
        for title, e in pairs(byTitle) do
            h.assertEq(e.eventType, Enum.CalendarEventType.Other, title .. ": a drive shows as Other")
            h.assertTrue(e.isLocked, title .. ": locked, since a drive takes no sign-ups")
        end
        h.assertEq(SideQuestDB.calendarLinks["drive-1"].at, utcAt(1, 19), "start linked under the plain id")
        h.assertEq(SideQuestDB.calendarLinks["drive-1:end"].at, utcAt(15, 19), "end linked under its own key")
        h.assertEq(#Calendar.Plan(), 0, "both in sync; nothing left to do")
    end)

    h.test("calendar: a drive's end announcement is still planned even once its start has already passed", function()
        reset()
        SideQuestDB.events = {
            { id = "drive-1", title = "Spring Recruitment", kind = "recruitment",
                starts_at = WowStub.time - 10 * DAY, ends_at = utcAt(4, 19) },
        }
        step()
        h.assertEq(#WowStub.calendar.events, 1, "only the end announcement is plannable")
        h.assertEq(WowStub.calendar.events[1].title, "Ends: Spring Recruitment", "the end announcement")
        h.assertEq(next(SideQuestDB.calendarLinks), "drive-1:end", "linked under the end key only")
    end)

    h.test("calendar: a drive event put on as Meeting and unlocked is edited in place to a locked Other event", function()
        reset()
        local endsAt = utcAt(4, 19)
        local p = realmDate(endsAt)
        -- what v0.17.2 left: right title and time, wrong type, open to sign-ups
        WowStub.calendar.events[1] = { calendarType = "GUILD_EVENT", title = "Ends: Spring Recruitment",
            eventType = Enum.CalendarEventType.Meeting, year = p.year, month = p.month, day = p.day, hour = 19, minute = 0 }
        SideQuestDB.events = { { id = "drive-1", title = "Spring Recruitment", kind = "recruitment",
            starts_at = WowStub.time - DAY, ends_at = endsAt } }

        step()
        h.assertTrue(lastLine():find("Opened Ends: Spring Recruitment", 1, true) ~= nil, "opened to fix it")
        step()
        h.assertEq(#WowStub.calendar.events, 1, "the same event, not a second one")
        h.assertEq(WowStub.calendar.events[1].eventType, Enum.CalendarEventType.Other, "as Other")
        h.assertTrue(WowStub.calendar.events[1].isLocked, "locked")
        h.assertEq(#Calendar.Plan(), 0, "nothing left to do")
    end)

    h.test("calendar: a raid someone made by hand as another type or unlocked is left alone", function()
        reset()
        local p = realmDate(utcAt(2, 19))
        WowStub.calendar.events[1] = { calendarType = "GUILD_EVENT", title = "Molten Core",
            eventType = Enum.CalendarEventType.Meeting, year = p.year, month = p.month, day = p.day, hour = 19, minute = 0 }
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        h.assertEq(#Calendar.Plan(), 0, "only drives are redone")
    end)

    h.test("calendar: moving a drive's end time only touches its own announcement, not the start one", function()
        reset()
        local evt = { id = "drive-1", title = "Spring Recruitment", kind = "recruitment",
            starts_at = utcAt(1, 19), ends_at = utcAt(15, 19) }
        SideQuestDB.events = { evt }
        step()
        step()
        evt.ends_at = utcAt(16, 20)

        local plan = Calendar.Plan()
        h.assertEq(#plan, 1, "one edit, for the end event only")
        h.assertEq(plan[1].linkKey, "drive-1:end", "only the end link is touched")
        step()
        step()
        local byTitle = {}
        for _, e in ipairs(WowStub.calendar.events) do
            byTitle[e.title] = e
        end
        h.assertEq(byTitle["Spring Recruitment"].hour, 19, "start announcement untouched")
        h.assertEq(byTitle["Ends: Spring Recruitment"].hour, 20, "end announcement moved")
    end)

    h.test("calendar: a refused add says so once, names it, and doesn't claim it was added", function()
        reset()
        SideQuestDB.events = { { id = "drive-1", title = "Spring Recruitment", kind = "recruitment",
            starts_at = WowStub.time - DAY, ends_at = utcAt(4, 19) } }
        -- as the game did: three refusals raised while AddEvent runs
        WowStub.calendar.refuseWith = {
            "CALENDAR_ERROR_INVALID_DATE", "CALENDAR_ERROR_INVALID_TIME", "CALENDAR_ERROR_NEEDS_TITLE",
        }
        local before = #WowStub.chatLog
        Calendar.Step()
        h.assertEq(#WowStub.chatLog - before, 1, "one line for the whole refusal")
        local line = lastLine()
        h.assertTrue(line:find("refused Ends: Spring Recruitment", 1, true) ~= nil, "names what was refused: " .. line)
        h.assertTrue(line:find("Added", 1, true) == nil, "doesn't claim success")
        h.assertEq(next(SideQuestDB.calendarLinks), nil, "nothing linked")
        h.assertEq(SideQuestDB.debug.log[1].kind, "calendar", "what was sent is in the debug log")
        h.assertEq(#Calendar.Plan(), 1, "still to do on the next click")
    end)

    h.test("calendar: an add is reported once the game confirms it", function()
        reset()
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        Calendar.Step()
        h.assertTrue(lastLine():find("Added", 1, true) == nil, "not claimed before the game answers")
        SideQuest.Fire("CALENDAR_NEW_EVENT", false)
        h.assertTrue(lastLine():find("Added Molten Core", 1, true) ~= nil, "added once confirmed")
        h.assertTrue(SideQuestDB.calendarLinks["evt-1"] ~= nil, "linked once confirmed")
    end)
end
