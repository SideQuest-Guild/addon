-- tests/test_member_export.lua
-- Contract section 3: every character rebuilds SideQuestDB.lastExport on PLAYER_LOGOUT.
-- Officers build the full officer export unchanged; everyone else builds a member
-- export carrying only their own directory entry and their own sign-ups.

return function(h)
    h.test("member export: a non-officer's logout export carries only their own directory entry and sign-ups", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.isOfficer = false
        WowStub.SetUnit("player", { name = "Me", realm = "Whitemane", class = "DRUID", guid = "Player-1-MMMM0001" })

        -- someone else's directory entry, gossiped to this client; must never leak into a member export
        SideQuestDB.directory["Other-Whitemane"] = {
            char = { v = "x", at = 1, d = { itemLevel = 60 } },
            seen_at = WowStub.time,
        }
        -- this character's own shared entry
        SideQuestDB.directory["Me-Whitemane"] = {
            prof = { v = "y", at = 2, d = { professions = { { name = "Alchemy", skill = 100, max_skill = 300 } } } },
            seen_at = WowStub.time,
        }
        -- this character's own queued sign-up
        SideQuestDB.mySignups["event-1"] = {
            status = "signed",
            sentAt = WowStub.time,
            acked = false,
            payload = { id = "sq-1", event_id = "event-1", character = "Me-Whitemane", status = "signed", at = WowStub.time },
        }

        WowStub.FireEvent("PLAYER_LOGOUT")

        h.assertTrue(SideQuestDB.lastExport ~= "", "lastExport was rebuilt")
        local payload = SideQuest.Codec.DecodeExport(SideQuestDB.lastExport)
        h.assertEq(payload.v, 2, "member export is still the v2 envelope")
        h.assertEq(#payload.directory, 1, "only one directory row")
        h.assertEq(payload.directory[1].character, "Me-Whitemane", "the row is this character's own entry")
        h.assertEq(#payload.signups, 1, "only this character's sign-up")
        h.assertEq(payload.signups[1].event_id, "event-1", "the queued sign-up payload carried through")

        -- every officer-only section stays empty for a member export
        for _, section in ipairs({
            "sessions", "encounters", "loot", "awards", "professions", "bank", "announcements",
            "recruits", "member_notes", "battlegrounds", "guild_log", "recruit_payouts_paid",
        }) do
            h.assertEq(#payload[section], 0, section .. " is empty in a member export")
        end
        h.assertTrue(payload.roster == nil, "a member export never carries a roster")
    end)

    h.test("member export: with no own directory entry or sign-ups, both export arrays stay empty", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.isOfficer = false
        WowStub.SetUnit("player", { name = "Fresh", realm = "Whitemane", class = "HUNTER", guid = "Player-1-FFFF0001" })
        SideQuestDB.directory["Other-Whitemane"] = {
            char = { v = "x", at = 1, d = { itemLevel = 60 } },
            seen_at = WowStub.time,
        }

        WowStub.FireEvent("PLAYER_LOGOUT")

        local payload = SideQuest.Codec.DecodeExport(SideQuestDB.lastExport)
        h.assertEq(#payload.directory, 0, "no own directory entry to carry")
        h.assertEq(#payload.signups, 0, "no own sign-up to carry")
    end)

    h.test("member export: an officer's logout export is unaffected (still the full officer export)", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Boss", realm = "Whitemane", class = "PALADIN", guid = "Player-1-BBBB0001" })
        WowStub.guildRoster = {
            { name = "Boss", rank = "Guild Master", rankIndex = 0, level = 60, class = "PALADIN",
                classFile = "PALADIN", zone = "Ironforge", online = true },
            { name = "Other", rank = "Member", rankIndex = 3, level = 60, class = "MAGE",
                classFile = "MAGE", zone = "Ironforge", online = false },
        }
        SideQuestDB.directory["Other-Whitemane"] = {
            char = { v = "x", at = 1, d = { itemLevel = 60 } },
            seen_at = WowStub.time,
        }

        WowStub.FireEvent("PLAYER_LOGOUT")

        local payload = SideQuest.Codec.DecodeExport(SideQuestDB.lastExport)
        h.assertTrue(payload.roster ~= nil, "officer export still carries a fresh roster")
        h.assertEq(#payload.directory, 1, "officer export still carries every known directory entry")
        h.assertEq(payload.directory[1].character, "Other-Whitemane", "including entries gossiped from other members")
    end)
end
