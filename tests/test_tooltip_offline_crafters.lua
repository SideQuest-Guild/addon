-- tests/test_tooltip_offline_crafters.lua
-- The item tooltip's "Crafted by" line folds in the site's SQI1 on-demand
-- "crafters" + "recipe_names" import (additive), so a guildie who is offline
-- or doesn't run the addon still shows up, deduplicated against live
-- WhoCrafts hits and matched by exact recipe name the same way.

return function(h)
    local test, assertTrue, resetAddon = h.test, h.assertTrue, h.resetAddon

    local function setupPlayer()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-OFFL0001" })
    end

    local function tooltipLines(tooltip)
        local out = {}
        for _, line in ipairs(tooltip.lines) do
            table.insert(out, line)
        end
        return out
    end

    test("tooltip crafted-by: an offline/imported crafter with no addon shows up alongside a live one", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        WowStub.items = { [30001] = { name = "Runed Adamantite Rod" } }

        -- A live crafter the directory already knows about.
        local profData = { professions = { { name = "Enchanting", skill = 300, max_skill = 300, recipes = { 7421 } } } }
        SideQuestDB.directory["Live-Whitemane"] = {
            prof = { v = SideQuest.Directory.Hash(profData), at = WowStub.time, d = profData },
            seen_at = WowStub.time,
        }
        -- WhoCrafts matches on recipe/profession name; its recipe name comes from C_Spell.GetSpellName.
        WowStub.spellNames = { [7421] = "Runed Adamantite Rod" }

        -- An offline guildie who never ran the addon, known only from the site's SQI1 import.
        SideQuestDB.onDemand.recipe_names = { ["7422"] = "Runed Adamantite Rod" }
        SideQuestDB.onDemand.crafters = {
            { character = "Offline-Whitemane", member_id = 5, profession = "Enchanting", skill = 285,
                recipes = { 7422 } },
        }

        local callback = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Item][1]
        local tooltip = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip, { id = 30001 })

        local line
        for _, l in ipairs(tooltipLines(tooltip)) do
            if l:find("^Crafted by") then
                line = l
            end
        end
        assertTrue(line ~= nil, "a Crafted by line appears")
        assertTrue(line:find("Live") ~= nil, "the live crafter is listed")
        assertTrue(line:find("Offline") ~= nil, "the offline/imported crafter is listed too")
    end)

    test("tooltip crafted-by: the same character known both live and offline is listed once", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        WowStub.items = { [30002] = { name = "Glowing Brightwood Staff" } }
        WowStub.spellNames = { [7777] = "Glowing Brightwood Staff" }

        local profData = { professions = { { name = "Enchanting", skill = 300, max_skill = 300, recipes = { 7777 } } } }
        SideQuestDB.directory["Both-Whitemane"] = {
            prof = { v = SideQuest.Directory.Hash(profData), at = WowStub.time, d = profData },
            seen_at = WowStub.time,
        }
        SideQuestDB.onDemand.recipe_names = { ["7777"] = "Glowing Brightwood Staff" }
        SideQuestDB.onDemand.crafters = {
            { character = "Both-Whitemane", member_id = 9, profession = "Enchanting", skill = 300, recipes = { 7777 } },
        }

        local callback = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Item][1]
        local tooltip = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip, { id = 30002 })

        local count = 0
        for _, l in ipairs(tooltipLines(tooltip)) do
            if l:find("^Crafted by") then
                count = count + 1
            end
        end
        h.assertEq(count, 1, "exactly one Crafted by line, not one per source")
    end)

    test("tooltip crafted-by: an on-demand recipe for a different item never matches", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false
        WowStub.items = { [30003] = { name = "Formula: Enchant Weapon - Fiery Weapon" } }
        SideQuestDB.onDemand.recipe_names = { ["8001"] = "Enchant Weapon - Fiery Weapon" } -- the taught recipe, not the formula item
        SideQuestDB.onDemand.crafters = {
            { character = "Nobody-Whitemane", member_id = 1, profession = "Enchanting", skill = 200, recipes = { 8001 } },
        }

        local callback = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Item][1]
        local tooltip = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip, { id = 30003 })
        for _, l in ipairs(tooltipLines(tooltip)) do
            assertTrue(not l:find("^Crafted by"), "a same-prefix recipe name is not an exact match")
        end
    end)
end
