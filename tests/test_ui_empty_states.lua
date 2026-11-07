-- tests/test_ui_empty_states.lua
-- With nothing imported yet, the Guild and Events tabs say so and how to get the data, instead of blaming filters.

return function(h)
    local function open(tab)
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.inCombat = false
        WowStub.guildRoster = {}
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-EMPTY001" })
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab(tab)
        return SideQuest.UI.panels[tab].chamber
    end

    h.test("guild tab: no guild data says how to get it, not 'no members match these filters'", function()
        local chamber = open("Guild")
        SideQuest.UI.RefreshGuild()
        local text = chamber.noResultText:GetText()
        h.assertTrue(text:find("No guild data yet", 1, true) ~= nil, "says there's no data yet: " .. text)
        h.assertTrue(text:find("filters", 1, true) == nil, "doesn't blame filters")
    end)

    h.test("guild tab: a search that hides every member still says so", function()
        local chamber = open("Guild")
        SideQuestDB.guild.members = { { member_id = 1, name = "Demo", raid_status = "raider",
            characters = { { name = "Demo-Whitemane", class = "PRIEST", is_main = true } } } }
        chamber.searchBox:SetText("nobody")
        SideQuest.UI.RefreshGuild()
        h.assertEq(chamber.noResultText:GetText(), "No one matches 'nobody'.", "filtered-out message")
    end)

    h.test("events tab: before any events arrive it says how to get them; after, that none are scheduled", function()
        WowStub.isOfficer = true
        local chamber = open("Raids")
        SideQuest.UI.RefreshRaids()
        h.assertTrue(chamber.emptyText:GetText():find("No event data yet", 1, true) ~= nil, "nothing received yet")

        SideQuestDB.eventsAt = 1793500000
        SideQuest.UI.RefreshRaids()
        h.assertEq(chamber.emptyText:GetText(), "No events scheduled right now.", "received, nothing scheduled")
    end)
end
