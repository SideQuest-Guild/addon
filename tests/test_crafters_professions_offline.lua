-- tests/test_crafters_professions_offline.lua
-- The Crafters tab's Professions view folds the site's SQI1 on-demand
-- "crafters" import (additive) into Directory.ByProfession's live results,
-- so a guildie who is offline or doesn't run the addon still shows up,
-- marked offline the same way the Search sub-tab marks it, and never
-- duplicating a character+profession the live directory already has.

return function(h)
    local test, assertEq, assertTrue, resetAddon = h.test, h.assertEq, h.assertTrue, h.resetAddon

    local function setupPlayer()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-CPRO0001" })
    end

    test("crafters Professions view: an on-demand crafter appears marked offline, deduped against a live match", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false

        local profData = { professions = { { name = "Blacksmithing", skill = 300, max_skill = 300 } } }
        SideQuestDB.directory["Live-Whitemane"] = {
            prof = { v = SideQuest.Directory.Hash(profData), at = WowStub.time, d = profData },
            seen_at = WowStub.time,
        }
        SideQuestDB.roster = { taken_at = WowStub.time, members = {
            { character = "Live-Whitemane", online = true, rank = "Member" },
        } }

        SideQuestDB.onDemand.crafters = {
            -- Same character+profession the directory already has: must not duplicate.
            { character = "Live-Whitemane", member_id = 1, profession = "Blacksmithing", skill = 299, recipes = {} },
            -- A guildie the live directory has never heard from.
            { character = "Offline-Whitemane", member_id = 2, profession = "Blacksmithing", skill = 280, recipes = {} },
        }

        SideQuest.UI.main = nil
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Crafters")
        local chamber = SideQuest.UI.panels.Crafters.professionsChamber
        chamber.profession = nil
        SideQuest.UI.RefreshCraftersProfessions()

        local liveCount, offlineRow = 0, nil
        for i = 1, #chamber.rows do
            local row = chamber.rows[i]
            if row:IsShown() then
                local name = row.nameRow.nameFS:GetText()
                if name and name:find("Live") then
                    liveCount = liveCount + 1
                elseif name and name:find("Offline") then
                    offlineRow = row
                end
            end
        end
        assertEq(liveCount, 1, "the live character appears exactly once, not duplicated by the import")
        assertTrue(offlineRow ~= nil, "the offline/imported crafter appears too")
        assertTrue(offlineRow.lastSeenText:GetText() ~= "Online", "the imported crafter is marked offline, not online")
    end)
end
