-- tests/test_guild_battlenet_fallback.lua
-- GameImportCharacter.spec/professions/reputations (SQI1, additive): the Guild
-- tab's member detail falls back to each one, independently, only when the live
-- directory has no data for that section. A live scan always wins per section,
-- imported reputations are filtered to SideQuest.Data.REPUTATIONS (ordered by
-- that list), and an import predating these fields leaves the detail panel
-- working exactly as before (no error, same empty texts).

return function(h)
    local test, assertTrue, assertEq, resetAddon = h.test, h.assertTrue, h.assertEq, h.resetAddon
    local TrackedCaps = SideQuest.UI.TrackedCaps

    local function setupPlayer()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-GBF0001" })
    end

    local function openGuildDetail(character)
        SideQuest.UI.main = nil
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Guild")
        local chamber = SideQuest.UI.panels.Guild.chamber
        chamber.selectedCharacter = character
        SideQuest.UI.RefreshGuild()
        return chamber.detailBlock
    end

    local function setRoster(character)
        SideQuestDB.roster = { taken_at = WowStub.time, members = {
            { character = character, online = true, rank = "Member" },
        } }
    end

    test("guild detail: spec, professions and reputations come from the import when the live directory has none", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        setRoster("Imported-Whitemane")
        SideQuestDB.guild.members = {
            { member_id = 1, name = "Imported", main = "Imported-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Imported-Whitemane", class = "WARRIOR", level = 60, is_main = true,
                    spec = "Arms",
                    professions = { { name = "Tailoring", skill = 300, max_skill = 300 } },
                    reputations = { { faction_id = 529, standing = 7, value = 4000, max = 21000 } },
                } } },
        }

        local block = openGuildDetail("Imported-Whitemane")
        assertTrue(block.metaText:GetText():find("Arms %(from Battle.net%)") ~= nil, "spec shows, marked as imported")
        assertEq(block.profHeading.label:GetText(), TrackedCaps("Professions (from Battle.net)"), "professions heading marked")
        assertEq(block.profRows[1]:GetText(), "Tailoring: 300 / 300", "imported profession row formatted like a live one")
        assertEq(block.repHeading.label:GetText(), TrackedCaps("Reputations (from Battle.net)"), "reputations heading marked")
        assertEq(block.repRows[1]:GetText(), "Argent Dawn: Revered (4000/21000)", "imported reputation row shows value/max")
    end)

    test("guild detail: a live section wins over the import, independently per section", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        local charData = { level = 60 } -- no spec, no reputations live
        local profData = { professions = { { name = "Mining", skill = 250, max_skill = 300 } } }
        SideQuestDB.directory["Fresher-Whitemane"] = {
            char = { v = SideQuest.Directory.Hash(charData), at = WowStub.time, d = charData },
            prof = { v = SideQuest.Directory.Hash(profData), at = WowStub.time, d = profData },
            seen_at = WowStub.time,
        }
        setRoster("Fresher-Whitemane")
        SideQuestDB.guild.members = {
            { member_id = 2, name = "Fresher", main = "Fresher-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Fresher-Whitemane", class = "WARRIOR", level = 60, is_main = true,
                    spec = "Stale Spec",
                    professions = { { name = "Stale Prof", skill = 1, max_skill = 1 } },
                    reputations = { { faction_id = 529, standing = 5, value = 100, max = 6000 } },
                } } },
        }

        local block = openGuildDetail("Fresher-Whitemane")
        -- spec: live has none, so the import's wins
        assertTrue(block.metaText:GetText():find("Stale Spec %(from Battle.net%)") ~= nil, "spec falls back to import")
        -- professions: live has data, so the import is ignored and unmarked
        assertEq(block.profHeading.label:GetText(), TrackedCaps("Professions"), "professions heading unmarked when live wins")
        assertEq(block.profRows[1]:GetText(), "Mining: 250 / 300", "live profession wins over import")
        -- reputations: live has none, so the import's wins
        assertEq(block.repHeading.label:GetText(), TrackedCaps("Reputations (from Battle.net)"), "reputations heading marked")
        assertEq(block.repRows[1]:GetText(), "Argent Dawn: Friendly (100/6000)", "imported reputation wins when live has none")
    end)

    test("guild detail: imported reputations are filtered to the tracked list and ordered by it", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        local originalReputations = SideQuest.Data.REPUTATIONS
        SideQuest.Data.REPUTATIONS = {
            { faction_id = 529, label = "Argent Dawn" },
            { faction_id = 909, label = "Thorium Brotherhood" },
        }
        setRoster("Tracked-Whitemane")
        SideQuestDB.guild.members = {
            { member_id = 4, name = "Tracked", main = "Tracked-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Tracked-Whitemane", class = "WARRIOR", level = 60, is_main = true,
                    reputations = {
                        -- import lists them reversed, plus one faction that isn't tracked at all
                        { faction_id = 909, standing = 4, value = 1000, max = 6000 },
                        { faction_id = 1, standing = 2, value = 0, max = 3000 },
                        { faction_id = 529, standing = 6, value = 2000, max = 12000 },
                    },
                } } },
        }

        local ok, err = pcall(function()
            local block = openGuildDetail("Tracked-Whitemane")
            assertEq(#block.repRows, 2, "only the two tracked factions show")
            assertEq(block.repRows[1]:GetText(), "Argent Dawn: Honored (2000/12000)", "tracked list order, not import order")
            assertEq(block.repRows[2]:GetText(), "Thorium Brotherhood: Neutral (1000/6000)", "second tracked faction follows")
        end)
        SideQuest.Data.REPUTATIONS = originalReputations
        assertTrue(ok, err)
    end)

    test("guild detail: imported reputation standing words", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        setRoster("Standing-Whitemane")
        SideQuestDB.guild.members = {
            { member_id = 5, name = "Standing", main = "Standing-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Standing-Whitemane", class = "WARRIOR", level = 60, is_main = true,
                    reputations = { { faction_id = 529, standing = 8, value = 21000, max = 21000 } },
                } } },
        }

        local block = openGuildDetail("Standing-Whitemane")
        assertEq(block.repRows[1]:GetText(), "Argent Dawn: Exalted", "Exalted shows just the standing word")
    end)

    test("guild detail: an imported reputation with no max shows just the standing word", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        setRoster("Nomax-Whitemane")
        SideQuestDB.guild.members = {
            { member_id = 6, name = "Nomax", main = "Nomax-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Nomax-Whitemane", class = "WARRIOR", level = 60, is_main = true,
                    reputations = { { faction_id = 529, standing = 5, value = 100, max = 0 } },
                } } },
        }

        local block = openGuildDetail("Nomax-Whitemane")
        assertEq(block.repRows[1]:GetText(), "Argent Dawn: Friendly", "max 0 shows just the standing word")
    end)

    test("guild detail: an import from before spec/professions/reputations existed shows the old empty texts, without erroring", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        setRoster("Old-Whitemane")
        SideQuestDB.guild.members = {
            -- Old-shaped GameImportCharacter: no spec/professions/reputations keys at all.
            { member_id = 7, name = "Old", main = "Old-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Old-Whitemane", class = "WARRIOR", level = 60, is_main = true } } },
        }

        local ok, block = pcall(openGuildDetail, "Old-Whitemane")
        assertTrue(ok, "painting the detail panel for an old-shaped import doesn't error")
        assertTrue(block:IsShown(), "the detail block actually painted (sanity check)")
        assertTrue(not block.metaText:GetText():find("from Battle.net"), "no spec marker when neither source has one")
        assertEq(block.profHeading.label:GetText(), TrackedCaps("Professions"), "professions heading stays unmarked")
        assertEq(block.profEmptyText:GetText(), "No professions on record.", "same empty text as before this change")
        assertEq(block.repHeading.label:GetText(), TrackedCaps("Reputations"), "reputations heading stays unmarked")
        assertEq(block.repEmptyText:GetText(), "No tracked reputations on record.", "same empty text as before this change")
    end)
end
