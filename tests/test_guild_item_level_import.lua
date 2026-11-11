-- tests/test_guild_item_level_import.lua
-- GameImportCharacter.item_level (SQI1, additive): the Guild tab's member
-- detail falls back to it when the live directory hasn't scanned that
-- character's gear. A live scan always wins over the import, and an import
-- from before the field existed leaves the detail panel working exactly as
-- before (no ilvl shown, no error).

return function(h)
    local test, assertTrue, resetAddon = h.test, h.assertTrue, h.resetAddon

    local function setupPlayer()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-GILV0001" })
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

    test("guild detail: item_level comes from the import when the live directory has none", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        SideQuestDB.roster = { taken_at = WowStub.time, members = {
            { character = "Imported-Whitemane", online = true, rank = "Member" },
        } }
        SideQuestDB.guild.members = {
            { member_id = 1, name = "Imported", main = "Imported-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Imported-Whitemane", class = "WARRIOR", level = 60, is_main = true,
                    item_level = 650 } } },
        }

        local block = openGuildDetail("Imported-Whitemane")
        assertTrue(block.metaText:GetText():find("ilvl 650") ~= nil, "shows the import's item level")
    end)

    test("guild detail: a live directory scan's item_level wins over the import", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        local charData = { level = 60, item_level = 700.0 }
        SideQuestDB.directory["Fresher-Whitemane"] = {
            char = { v = SideQuest.Directory.Hash(charData), at = WowStub.time, d = charData },
            seen_at = WowStub.time,
        }
        SideQuestDB.roster = { taken_at = WowStub.time, members = {
            { character = "Fresher-Whitemane", online = true, rank = "Member" },
        } }
        SideQuestDB.guild.members = {
            { member_id = 2, name = "Fresher", main = "Fresher-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Fresher-Whitemane", class = "WARRIOR", level = 60, is_main = true,
                    item_level = 500 } } }, -- stale import value
        }

        local block = openGuildDetail("Fresher-Whitemane")
        assertTrue(block.metaText:GetText():find("ilvl 700") ~= nil, "shows the fresher live scan, not the stale import")
    end)

    test("guild detail: an import from before item_level existed shows no ilvl, without erroring", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        SideQuestDB.roster = { taken_at = WowStub.time, members = {
            { character = "Old-Whitemane", online = true, rank = "Member" },
        } }
        SideQuestDB.guild.members = {
            -- Old-shaped GameImportCharacter: no item_level key at all.
            { member_id = 3, name = "Old", main = "Old-Whitemane", class = "WARRIOR", rank = "Member",
                raid_status = nil, guild_ep = 0, attendance_rate = 0, events_attended = 0, badges = {},
                characters = { { name = "Old-Whitemane", class = "WARRIOR", level = 60, is_main = true } } },
        }

        local ok, block = pcall(openGuildDetail, "Old-Whitemane")
        assertTrue(ok, "painting the detail panel for an old-shaped import doesn't error")
        assertTrue(block:IsShown(), "the detail block actually painted (sanity check)")
        assertTrue(not block.metaText:GetText():find("ilvl"), "no ilvl shown when neither source has one")
    end)
end
