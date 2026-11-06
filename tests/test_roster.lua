-- tests/test_roster.lua
-- The guild roster sweeps itself: the website's inactive list and the Guild tab need it, and nobody remembers to
-- press Sweep.

return function(h)
    local function roster(n)
        local members = {}
        for i = 1, n do
            members[i] = { name = "Member" .. i, rank = "Member", rankIndex = 3, level = 60, class = "MAGE",
                classFile = "MAGE", zone = "Ironforge", online = i == 1 }
        end
        return members
    end

    h.test("roster: the game's roster update sweeps it for the Guild tab and the next export, at most every 10 minutes", function()
        h.resetAddon()
        WowStub.Advance(601)
        WowStub.guildRoster = roster(3)
        WowStub.FireEvent("GUILD_ROSTER_UPDATE")
        h.assertEq(#SideQuestDB.roster.members, 3, "swept on the update")
        h.assertEq(#SideQuestDB.pending.roster.members, 3, "queued for the next export")

        WowStub.guildRoster = roster(1)
        WowStub.FireEvent("GUILD_ROSTER_UPDATE")
        h.assertEq(#SideQuestDB.roster.members, 3, "not swept again within 10 minutes")

        WowStub.Advance(601)
        WowStub.FireEvent("GUILD_ROSTER_UPDATE")
        h.assertEq(#SideQuestDB.roster.members, 1, "swept again after 10 minutes")
    end)

    h.test("roster: an update before the client has loaded the roster keeps the last sweep", function()
        h.resetAddon()
        WowStub.Advance(601)
        WowStub.guildRoster = roster(2)
        WowStub.FireEvent("GUILD_ROSTER_UPDATE")
        WowStub.Advance(601)
        WowStub.guildRoster = {}
        WowStub.FireEvent("GUILD_ROSTER_UPDATE")
        h.assertEq(#SideQuestDB.roster.members, 2, "an empty roster doesn't replace the sweep")
    end)

    h.test("roster: an officer's logout export carries a fresh roster", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.guildRoster = roster(4)
        WowStub.FireEvent("PLAYER_LOGOUT")
        local payload = SideQuest.Codec.DecodeExport(SideQuestDB.lastExport)
        h.assertTrue(payload ~= nil and payload.roster ~= nil, "the export has a roster")
        h.assertEq(#payload.roster.members, 4, "every member swept")
        WowStub.isOfficer = false
    end)

    h.test("roster: an offline member's last_online_hours comes from GetGuildRosterLastOnline", function()
        h.resetAddon()
        WowStub.guildRoster = {
            { name = "Member1", rank = "Member", rankIndex = 3, level = 60, class = "MAGE", classFile = "MAGE",
                zone = "Ironforge", online = true },
            { name = "Member2", rank = "Member", rankIndex = 3, level = 55, class = "ROGUE", classFile = "ROGUE",
                zone = "", online = false, lastOnline = { years = 0, months = 0, days = 2, hours = 5 } },
        }
        local snapshot = SideQuest.Roster.Sweep()
        h.assertEq(snapshot.members[1].last_online_hours, 0, "an online member reads 0 hours")
        h.assertEq(snapshot.members[2].last_online_hours, 53, "an offline member's days+hours convert to hours (2*24+5)")
    end)

    h.test("roster: an offline member gets no last_online_hours when GetGuildRosterLastOnline doesn't exist", function()
        h.resetAddon()
        WowStub.guildRoster = {
            { name = "Member1", rank = "Member", rankIndex = 3, level = 40, class = "WARRIOR", classFile = "WARRIOR",
                zone = "", online = false },
        }
        local saved = GetGuildRosterLastOnline
        GetGuildRosterLastOnline = nil
        local snapshot = SideQuest.Roster.Sweep()
        GetGuildRosterLastOnline = saved
        h.assertEq(snapshot.members[1].last_online_hours, nil, "no API, no guess")
    end)
    h.test("roster: a secret member name is skipped instead of landing in SavedVariables unreadable", function()
        h.resetAddon()
        WowStub.guildRoster = {
            { name = WowStub.SECRET, rank = "Member", rankIndex = 3, level = 60, class = WowStub.SECRET,
                classFile = WowStub.SECRET, zone = "Ironforge", online = true },
            { name = "Bob-Whitemane", rank = "Member", rankIndex = 3, level = 55, class = "ROGUE",
                classFile = "ROGUE", zone = "Stormwind", online = false },
        }
        local snapshot = SideQuest.Roster.Sweep()
        h.assertTrue(snapshot ~= nil, "the sweep still completes")
        h.assertEq(#snapshot.members, 1, "the unreadable member is skipped, not stored broken")
        h.assertEq(snapshot.members[1].character, "Bob-Whitemane", "the readable member still comes through")
    end)
end
