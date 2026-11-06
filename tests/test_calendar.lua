-- tests/test_calendar.lua
-- Calendar.lua: putting the site's events on the in-game guild calendar as guild announcements, in realm time, one
-- change per Step, and taking moved or cancelled events back off.

return function(h)
    local Calendar = SideQuest.Calendar
    local HOUR, DAY = 3600, 86400

    local function reset()
        h.resetAddon()
        WowStub.ResetCalendar()
        Calendar.busyUntil = 0
        Calendar.lastRequestAt = nil
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

    h.test("calendar: a site event goes on as a guild announcement at the realm's local time", function()
        reset()
        WowStub.calendar.realmOffset = -6 * HOUR -- realm six hours behind UTC
        local startsAt = utcAt(3, 1, 30) -- 01:30 UTC is 19:30 the evening before on the realm
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = startsAt } }

        step()

        h.assertEq(#WowStub.calendar.events, 1, "one announcement added")
        local e = WowStub.calendar.events[1]
        local want = realmDate(startsAt)
        h.assertEq(e.calendarType, "GUILD_ANNOUNCEMENT", "a guild announcement, not a sign-up event")
        h.assertEq(e.title, "Molten Core", "title")
        h.assertEq(e.year * 10000 + e.month * 100 + e.day, want.year * 10000 + want.month * 100 + want.day,
            "dated on the realm's calendar day, the day before the UTC date")
        h.assertEq(e.hour, 19, "realm hour")
        h.assertEq(e.minute, 30, "realm minute")
        h.assertTrue(e.description:find("events/detail/?id=evt-1", 1, true) ~= nil, "description links the sign-up page")
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

    h.test("calendar: a moved event's old announcement comes off and the new one goes on", function()
        reset()
        local evt = { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) }
        SideQuestDB.events = { evt }
        step()
        evt.starts_at = utcAt(3, 20)

        local plan = Calendar.Plan()
        h.assertEq(#plan, 2, "remove then add")
        h.assertEq(plan[1].op, "remove", "removal first")
        step()
        step()
        h.assertEq(#WowStub.calendar.events, 1, "only the moved announcement is left")
        h.assertEq(WowStub.calendar.events[1].hour, 20, "at the new time")
        h.assertEq(#Calendar.Plan(), 0, "in sync")
    end)

    h.test("calendar: a cancelled event comes off; a past one stays as history", function()
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
        h.assertEq(#WowStub.calendar.events, 1, "one removed")
        h.assertEq(WowStub.calendar.events[1].title, "Zul'Gurub", "the past event stays on the calendar")
        h.assertEq(next(SideQuestDB.calendarLinks), nil, "no links left")
        step()
        h.assertTrue(lastLine():find("already matches") ~= nil, "nothing more to do")
    end)

    h.test("calendar: adopts another officer's announcement, then still cleans it up when the event moves", function()
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

    h.test("calendar: leaves other guild announcements and same-titled events at other times alone", function()
        reset()
        local p = realmDate(utcAt(2, 19))
        WowStub.calendar.events[1] = { calendarType = "GUILD_ANNOUNCEMENT", title = "Bank day",
            year = p.year, month = p.month, day = p.day, hour = 19, minute = 0 }
        WowStub.calendar.events[2] = { calendarType = "GUILD_EVENT", title = "Molten Core",
            year = p.year, month = p.month, day = p.day, hour = 19, minute = 0 }
        SideQuestDB.events = { { id = "evt-1", title = "Molten Core", kind = "raid", starts_at = utcAt(2, 19) } }
        local plan = Calendar.Plan()
        h.assertEq(#plan, 1, "a sign-up event with the same title doesn't count as ours")
        h.assertEq(plan[1].op, "add", "adds its own announcement")
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
end
