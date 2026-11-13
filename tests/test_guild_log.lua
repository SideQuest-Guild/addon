-- tests/test_guild_log.lua
-- GuildLog.lua: who invited whom, from the in-game guild event log (officer-only), with its time-ago fields
-- rounded down to the hour, deduped against local history, and exported as contract v2 "guild_log".

return function(h)
    local function fixturesDir()
        local src = debug.getinfo(1, "S").source
        local here = src:match("@(.*/)") or "./"
        return here .. "fixtures/"
    end
    local HOUR = 3600

    local function setup()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-GLOG001" })
    end

    local function nowHour()
        return math.floor(WowStub.time / HOUR) * HOUR
    end

    h.test("guild log: invite/join/quit/remove are captured with time-ago rounded down to the hour", function()
        setup()
        WowStub.guildEvents = {
            { kind = "invite", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", hours = 2 },
            { kind = "join", player1 = "Newbie-Whitemane", hours = 1 },
            { kind = "quit", player1 = "Oldtimer-Whitemane", days = 1, hours = 3 },
            { kind = "remove", player1 = "Officer1-Whitemane", player2 = "Troublemaker-Whitemane", hours = 0 },
        }
        local added = SideQuest.GuildLog.Capture()
        h.assertEq(added, 4, "all four kept kinds captured")
        local rows = SideQuestDB.pending.guild_log
        h.assertEq(#rows, 4, "queued for export")

        h.assertEq(rows[1].kind, "invite", "invite kind")
        h.assertEq(rows[1].actor, "Officer1-Whitemane", "invite actor is the inviter")
        h.assertEq(rows[1].target, "Newbie-Whitemane", "invite target is the invitee")
        h.assertEq(rows[1].at, nowHour() - 2 * HOUR, "invite at: 2 hours ago, rounded to the hour")

        h.assertEq(rows[2].kind, "join", "join kind")
        h.assertEq(rows[2].actor, "Newbie-Whitemane", "join actor is the member who joined")
        h.assertEq(rows[2].target, nil, "join has no target")

        h.assertEq(rows[3].kind, "quit", "quit kind")
        h.assertEq(rows[3].actor, "Oldtimer-Whitemane", "quit actor is the member who left")
        h.assertEq(rows[3].at, nowHour() - 27 * HOUR, "quit at: 1 day 3 hours ago")

        h.assertEq(rows[4].kind, "remove", "remove kind")
        h.assertEq(rows[4].actor, "Officer1-Whitemane", "remove actor is the officer who removed")
        h.assertEq(rows[4].target, "Troublemaker-Whitemane", "remove target is the removed member")
    end)

    h.test("guild log: promote/demote are never captured (kept out of the export on purpose)", function()
        setup()
        WowStub.guildEvents = {
            { kind = "promote", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", rank = "Member" },
            { kind = "demote", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", rank = "Trial" },
        }
        local added = SideQuest.GuildLog.Capture()
        h.assertEq(added, 0, "nothing captured")
        h.assertEq(#SideQuestDB.pending.guild_log, 0, "nothing queued")
    end)

    h.test("guild log: a secret actor name is skipped instead of landing in SavedVariables unreadable", function()
        setup()
        WowStub.guildEvents = {
            { kind = "invite", player1 = WowStub.SECRET, player2 = "Newbie-Whitemane", hours = 1 },
        }
        local added = SideQuest.GuildLog.Capture()
        h.assertEq(added, 0, "secret actor row skipped")
    end)

    h.test("guild log: a repeat capture of the same log doesn't duplicate (dedupe within 2 hours)", function()
        setup()
        WowStub.guildEvents = {
            { kind = "invite", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", hours = 1 },
        }
        local first = SideQuest.GuildLog.Capture()
        h.assertEq(first, 1, "first capture adds the row")
        local second = SideQuest.GuildLog.Capture()
        h.assertEq(second, 0, "same log captured again adds nothing")
        h.assertEq(#SideQuestDB.pending.guild_log, 1, "still only one queued row")
    end)

    h.test("guild log: the same actor/target re-inviting more than 2 hours later counts as a new row", function()
        setup()
        WowStub.guildEvents = {
            { kind = "invite", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", hours = 5 },
        }
        SideQuest.GuildLog.Capture()
        WowStub.guildEvents = {
            { kind = "invite", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", hours = 0 },
        }
        local added = SideQuest.GuildLog.Capture()
        h.assertEq(added, 1, "a genuinely later invite of the same pair is a new row")
        h.assertEq(#SideQuestDB.pending.guild_log, 2, "both rows kept")
    end)

    h.test("guild log: a non-officer never captures (the log export is officer-only)", function()
        setup()
        WowStub.isOfficer = false
        WowStub.guildEvents = {
            { kind = "invite", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", hours = 1 },
        }
        local added = SideQuest.GuildLog.Capture()
        h.assertEq(added, nil, "capture refuses for a non-officer")
        h.assertEq(#SideQuestDB.pending.guild_log, 0, "nothing queued")
    end)

    h.test("guild log: history older than 60 days is pruned before the next dedupe check", function()
        setup()
        SideQuestDB.guildLogHistory = {
            { kind = "invite", actor = "Officer1-Whitemane", target = "Stale-Whitemane", at = WowStub.time - 61 * 86400 },
        }
        WowStub.guildEvents = {
            { kind = "invite", player1 = "Officer1-Whitemane", player2 = "Stale-Whitemane", hours = 0 },
        }
        local added = SideQuest.GuildLog.Capture()
        h.assertEq(added, 1, "the stale history entry no longer blocks a fresh one")
    end)

    h.test("guild log: requests the server log on login and after a roster sweep, throttled between requests", function()
        setup()
        SideQuest.GuildLog.lastRequestAt = nil
        SideQuest.Fire("PLAYER_ENTERING_WORLD")
        h.assertEq(WowStub.queryGuildEventLogCalls, 1, "login requests the log")
        SideQuest.Fire("SQ_ROSTER_UPDATED", {})
        h.assertEq(WowStub.queryGuildEventLogCalls, 1, "throttled: no second request yet")
        WowStub.Advance(301)
        SideQuest.Fire("SQ_ROSTER_UPDATED", {})
        h.assertEq(WowStub.queryGuildEventLogCalls, 2, "requests again once the throttle has passed")
    end)

    h.test("guild log: GUILD_EVENT_LOG_UPDATE captures whatever the server answered with", function()
        setup()
        WowStub.guildEvents = {
            { kind = "join", player1 = "Newbie-Whitemane", hours = 0 },
        }
        SideQuest.Fire("GUILD_EVENT_LOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.guild_log, 1, "captured on the update event")
    end)

    h.test("guild log: export shape matches the contract (kind/actor/target/at)", function()
        setup()
        WowStub.guildEvents = {
            { kind = "invite", player1 = "Officer1-Whitemane", player2 = "Newbie-Whitemane", hours = 1 },
        }
        SideQuest.GuildLog.Capture()

        local str = SideQuest.Sync.BuildExport()
        local decoded = SideQuest.Codec.DecodeExport(str)
        h.assertEq(#decoded.guild_log, 1, "guild_log present in the export")
        local row = decoded.guild_log[1]
        h.assertEq(row.kind, "invite", "export kind")
        h.assertEq(row.actor, "Officer1-Whitemane", "export actor")
        h.assertEq(row.target, "Newbie-Whitemane", "export target")
        h.assertTrue(row.at ~= nil, "export at")

        local fixturePath = fixturesDir() .. "export_v2_guild_log.txt"
        local fh = io.open(fixturePath, "w")
        fh:write(str)
        fh:close()
    end)

    h.test("guild log: /sq export clear drops queued rows", function()
        setup()
        WowStub.guildEvents = {
            { kind = "join", player1 = "Newbie-Whitemane", hours = 0 },
        }
        SideQuest.GuildLog.Capture()
        h.assertEq(#SideQuestDB.pending.guild_log, 1, "queued before clear")
        SideQuest.Sync.ClearPending()
        h.assertEq(#SideQuestDB.pending.guild_log, 0, "cleared")
    end)
end
