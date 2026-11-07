-- tests/test_events_sharing.lua
-- Site events reach every member: officers get them (upcoming and recent past) from the import and share them with
-- the standings broadcast, so nobody else needs an import string.

return function(h)
    local HOUR = 3600

    local function deliverQueued(fromSender)
        local queued = WowStub.addonMessages
        WowStub.addonMessages = {}
        for _, m in ipairs(queued) do
            WowStub.DeliverAddonMessage(fromSender, m.message)
        end
    end

    local function importPayload(generatedAt)
        return {
            v = 1, generated_at = generatedAt, rules = nil, standings = {}, killed_encounters = {},
            events = {
                { id = "evt-next", title = "Molten Core", kind = "raid", starts_at = WowStub.time + 24 * HOUR, size = 40,
                    signups = { { character = "Tanky", class = "WARRIOR", role = "tank", status = "signed",
                        group = 1, bench = false } } },
            },
            past_events = {
                { id = "evt-movie", title = "Movie Night", kind = "social", starts_at = WowStub.time - 48 * HOUR,
                    signups = {
                        { character = "A", status = "signed", bench = false },
                        { character = "B", status = "signed", bench = false },
                        { character = "C", status = "absent", bench = false },
                    } },
            },
        }
    end

    h.test("events: an import keeps past events as answer counts, newest first, with since-started ones merged in",
        function()
            h.resetAddon()
            local payload = importPayload(WowStub.time)
            table.insert(payload.events, 1, { id = "evt-earlier", title = "Hangout", kind = "other",
                starts_at = WowStub.time - 7 * HOUR, signups = { { character = "D", status = "tentative" } } })
            SideQuest.Sync.ApplyImport(payload)

            local upcoming = SideQuest.Events.Upcoming()
            h.assertEq(#upcoming, 1, "only the event still ahead is upcoming")
            h.assertEq(upcoming[1].id, "evt-next", "upcoming event")

            local past = SideQuest.Events.Past()
            h.assertEq(#past, 2, "the site's past event plus the one that started 7h ago")
            h.assertEq(past[1].id, "evt-earlier", "newest first")
            h.assertEq(past[1].maybe, 1, "counts from its sign-ups")
            h.assertEq(past[2].going, 2, "Movie Night: 2 going")
            h.assertEq(past[2].cant, 1, "Movie Night: 1 can't")
            h.assertEq(SideQuestDB.pastEvents[1].signups, nil, "stored past events carry no names")
        end)

    h.test("events: a member gets an officer's events with the standings broadcast", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officername", realm = "Whitemane", class = "PRIEST", guid = "Player-1-EVT00001" })
        SideQuest.Sync.ApplyImport(importPayload(WowStub.time))
        local officerMessages = WowStub.addonMessages

        h.resetAddon()
        WowStub.isOfficer = false
        WowStub.SetUnit("player", { name = "Membername", realm = "Whitemane", class = "HUNTER", guid = "Player-1-EVT00002" })
        WowStub.addonMessages = officerMessages
        deliverQueued("Officername-Whitemane")

        h.assertEq(#SideQuest.Events.Upcoming(), 1, "member has the upcoming event")
        h.assertEq(SideQuest.Events.Upcoming()[1].signups[1].character, "Tanky", "with its sign-ups")
        h.assertEq(SideQuest.Events.Past()[1].going, 2, "and the past event's counts")
        h.assertTrue(SideQuest.Events.EverReceived(), "events count as received")
    end)

    h.test("events: standings from an officer that didn't share events don't block events from a newer one", function()
        h.resetAddon()
        WowStub.isOfficer = false
        local at = WowStub.time
        -- an older officer addon: same import, no events in the broadcast
        WowStub.DeliverAddonMessage("Oldofficer-Whitemane", SideQuest.Comm.ChunkMessage("STANDINGS",
            SideQuestJSON.encode({ generated_at = at, rows = {} }))[1])
        h.assertEq(SideQuestDB.standings.generated_at, at, "standings taken")
        h.assertTrue(not SideQuest.Events.EverReceived(), "no events from that broadcast")
        h.assertEq(SideQuest.Standings.HeldGeneratedAt(), 0, "so the login request still asks for everything")

        local chunks = SideQuest.Comm.ChunkMessage("STANDINGS", SideQuestJSON.encode({
            generated_at = at, rows = {}, events = importPayload(at).events,
        }))
        for _, chunk in ipairs(chunks) do
            WowStub.DeliverAddonMessage("Newofficer-Whitemane", chunk)
        end
        h.assertEq(#SideQuest.Events.Upcoming(), 1, "same standings, but the events arrive")
        h.assertEq(SideQuest.Standings.HeldGeneratedAt(), at, "and the request is satisfied")
    end)

    h.test("events tab: a member with no events is told they come from an officer; past events get their own list",
        function()
            h.resetAddon()
            SideQuest.UI.main = nil
            WowStub.isOfficer = false
            WowStub.SetUnit("player", { name = "Membername", realm = "Whitemane", class = "HUNTER", guid = "Player-1-EVT00003" })
            SideQuest.UI.Show()
            SideQuest.UI.ShowTab("Raids")
            local chamber = SideQuest.UI.panels.Raids.chamber
            h.assertTrue(chamber.emptyText:GetText():find("officer's SideQuest", 1, true) ~= nil,
                "member empty text: " .. chamber.emptyText:GetText())

            local payload = importPayload(WowStub.time)
            payload.events = {}
            SideQuest.Events.Load(payload.events, payload.past_events, payload.generated_at)
            h.assertEq(chamber.emptyText:GetText(), "No events scheduled right now.", "nothing ahead")
            h.assertTrue(chamber.pastHeading:IsShown(), "past events heading")
            h.assertTrue(chamber.pastRows[1].title:GetText() == "Movie Night", "past event row")
            h.assertTrue(chamber.pastRows[1].meta:GetText():find("Going 2, Maybe 0, Can't 1", 1, true) ~= nil,
                "past event counts: " .. chamber.pastRows[1].meta:GetText())
        end)
end
