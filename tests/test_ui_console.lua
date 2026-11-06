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
end
