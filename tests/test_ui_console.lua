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
            { member_id = 2, name = "Seen Once", last_seen_at = 1762300800, last_raid_at = 1762300800 },
        }
        SideQuest.UI.RefreshConsoleRoster()

        local rows = SideQuest.UI.panels.Console.rosterChamber.rows
        local never, seen = rows[1].text:GetText(), rows[2].text:GetText()
        h.assertTrue(never:find("no login on record", 1, true) ~= nil, "missing last-seen reads as no login: " .. never)
        h.assertTrue(never:find("1969", 1, true) == nil and never:find("1970", 1, true) == nil, "no epoch date")
        h.assertTrue(seen:find("last seen " .. date("%Y-%m-%d", 1762300800), 1, true) ~= nil, "a real date still shows")
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
