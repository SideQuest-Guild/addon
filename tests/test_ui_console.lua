-- tests/test_ui_console.lua
-- The officers' Console tab.

return function(h)
    h.test("console roster: an inactive member with no login on record says so instead of a 1969 date", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.inCombat = false
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-CONSOLE1" })
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuestDB.officerData.inactive = {
            { member_id = 1, name = "Never Seen" },
            { member_id = 2, name = "Seen Once", level = 58, last_seen_at = 1762300800, last_raid_at = 1762300800 },
            { member_id = 3, name = "No Raids", level = 42, last_seen_at = 1762300800 },
        }
        SideQuestDB.officerData.unseen = {
            { member_id = 4, name = "Fresh Recruit" },
        }
        SideQuest.UI.RefreshConsoleRoster()

        local chamber = SideQuest.UI.panels.Console.rosterChamber
        local rows = chamber.rows
        local never, seen, noRaids = rows[1].text:GetText(), rows[2].text:GetText(), rows[3].text:GetText()
        h.assertTrue(never:find("no login on record", 1, true) ~= nil, "missing last-seen reads as no login: " .. never)
        h.assertTrue(never:find("1969", 1, true) == nil and never:find("1970", 1, true) == nil, "no epoch date")
        h.assertTrue(seen:find("last seen " .. date("%Y-%m-%d", 1762300800), 1, true) ~= nil, "a real date still shows")
        h.assertTrue(seen:find("level 58", 1, true) ~= nil, "a known level shows: " .. seen)
        h.assertTrue(seen:find("last raid", 1, true) ~= nil, "a known raid date shows: " .. seen)
        h.assertTrue(noRaids:find("never raided", 1, true) == nil, "no fake 'never raided' when the raid date is unknown: " .. noRaids)
        h.assertTrue(chamber.unseenText:GetText():find("1 member has no login on record yet", 1, true) ~= nil,
            "unseen count line: " .. chamber.unseenText:GetText())

        SideQuestDB.officerData.inactive = {}
        SideQuestDB.officerData.unseen = {}
        SideQuest.UI.RefreshConsoleRoster()
        h.assertTrue(chamber.inactiveEmpty:GetText():find("No one has been away more than 14 days", 1, true) ~= nil,
            "plain empty state: " .. chamber.inactiveEmpty:GetText())
        h.assertEq(chamber.unseenText:GetText(), "", "no unseen line once everyone has a record")
    end)

    h.test("console roster: the sweep button reads clearly and explains itself", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-CONSOLE4" })
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")

        local chamber = SideQuest.UI.panels.Console.rosterChamber
        h.assertEq(chamber.sweepBtn:GetText(), "Read roster now", "button names the action, not 'sweep'")
        h.assertTrue(chamber.sweepHint:GetText():find("removes no one", 1, true) ~= nil
            or chamber.sweepHint:GetText():find("Removes no one", 1, true) ~= nil,
            "hint says it's non-destructive: " .. chamber.sweepHint:GetText())
    end)

    h.test("console sync: Import applies the pasted text instead of clearing it", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-CONSOLE6" })
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Sync")
        local chamber = SideQuest.UI.panels.Console.syncChamber

        local payload = { v = 1, generated_at = 1793500000, rules = nil, standings = {}, killed_encounters = {},
            events = {} }
        chamber.editBox:SetText(" " .. SideQuest.Codec.EncodeImport(payload) .. " ")
        chamber.importBtn:GetScript("OnClick")()
        h.assertEq(SideQuestDB.standings.generated_at, 1793500000, "the pasted import was applied")
        h.assertEq(chamber.importResult:GetText(), "Imported.", "says so next to the button")

        chamber.editBox:SetText("not an import")
        chamber.importBtn:GetScript("OnClick")()
        h.assertTrue(chamber.importResult:GetText():find("isn't a SideQuest import", 1, true) ~= nil,
            "a bad paste says so: " .. chamber.importResult:GetText())
    end)

    h.test("console sync calendar: no site events says whether the site has none or nothing was imported yet", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-CONSOLE5" })
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Sync")
        SideQuest.Calendar.loaded = true

        local chamber = SideQuest.UI.panels.Console.syncChamber
        SideQuest.UI.RefreshConsoleCalendar()
        h.assertTrue(chamber.calendarText:GetText():find("No site data yet", 1, true) ~= nil,
            "nothing imported: " .. chamber.calendarText:GetText())

        SideQuestDB.eventsAt = 1793500000
        SideQuest.UI.RefreshConsoleCalendar()
        h.assertTrue(chamber.calendarText:GetText():find("no events in the next 14 days", 1, true) ~= nil,
            "imported, the site has nothing upcoming: " .. chamber.calendarText:GetText())
    end)

    h.test("Raid Night recording control: disabled outside a raid, enabled and toggling inside one", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-CONSOLE2" })
        WowStub.instance = { inInstance = false, instanceType = "none", instanceID = 0, difficultyID = 1 }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Raid Night")

        local chamber = SideQuest.UI.panels.Console.raidNightChamber
        h.assertTrue(not chamber.recordBtn.__enabled, "Start recording is disabled outside a raid instance")
        h.assertTrue(chamber.recordStatusText:GetText():find("Zone into the raid", 1, true) ~= nil,
            "status explains why: " .. chamber.recordStatusText:GetText())

        WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 409, difficultyID = 3, name = "Molten Core" }
        SideQuest.UI.RefreshConsoleRaidNight()
        h.assertTrue(chamber.recordBtn.__enabled, "Start recording enables once in a raid instance")
        h.assertEq(chamber.recordStatusText:GetText(), "Not recording.", "not recording yet")

        SideQuest.UI.OnClickRecordButton()
        h.assertTrue(SideQuest.Recorder.current ~= nil, "clicking Start recording starts a session")
        h.assertEq(chamber.recordBtn:GetText(), "Stop recording", "button now offers to stop")

        -- Start raid unlocks now that we're recording
        local startRow = chamber.stepRows[3]
        h.assertTrue(startRow.btn.__enabled, "Start raid step is enabled once recording")

        SideQuest.UI.OnClickRecordButton()
        h.assertTrue(SideQuest.Recorder.current == nil, "clicking Stop recording ends the session")
        h.assertEq(chamber.recordBtn:GetText(), "Start recording", "button offers to start again")
    end)

    h.test("Raid Night: a conflicting recorder requires a second click to confirm", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-CONSOLE3" })
        WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 409, difficultyID = 3, name = "Molten Core" }
        SideQuestDB.addonVersions["Officer2-Whitemane"] = {
            version = "0.5.0", seenAt = WowStub.time, officer = true,
            recording = { instance = "Molten Core", instance_id = 409, since = WowStub.time - 300 },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Raid Night")

        local chamber = SideQuest.UI.panels.Console.raidNightChamber
        h.assertTrue(chamber.recordBtn:GetText():find("already recording", 1, true) ~= nil,
            "button names the other officer: " .. chamber.recordBtn:GetText())

        SideQuest.UI.OnClickRecordButton()
        h.assertEq(SideQuest.Recorder.current, nil, "first click only arms the confirm, doesn't start")

        SideQuest.UI.OnClickRecordButton()
        h.assertTrue(SideQuest.Recorder.current ~= nil, "second click starts recording anyway")
    end)
end
