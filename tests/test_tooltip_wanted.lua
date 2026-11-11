-- tests/test_tooltip_wanted.lua
-- GameImportPrice.wanted (SQI1, additive): the number of distinct guild
-- members with an item on their wishlist. Sync.ApplyImport stores it
-- alongside the price as `w`, defaulting to 0 when the import omits it, and
-- the item tooltip shows a "Wanted by N guildies" line under the Auction
-- house line when it's above zero.

return function(h)
    local test, assertEq, assertTrue, resetAddon = h.test, h.assertEq, h.assertTrue, h.resetAddon

    local function setupPlayer()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-WANT0001" })
    end

    local function sawLine(tooltip, text)
        for _, line in ipairs(tooltip.lines) do
            if line == text then
                return true
            end
        end
        return false
    end

    test("import: GameImportPrice.wanted is stored as w, defaulting to 0 when the import omits it", function()
        resetAddon()
        setupPlayer()
        local base = { v = 1, generated_at = WowStub.time, rules = nil, standings = {}, killed_encounters = {}, events = {} }

        local withWanted = {}
        for k, v in pairs(base) do withWanted[k] = v end
        withWanted.prices = {
            { item_id = 111, unit_price = 100, quantity = 1, at = WowStub.time, wanted = 4 },
            { item_id = 222, unit_price = 200, quantity = 1, at = WowStub.time }, -- old-shaped entry, no wanted
        }
        SideQuest.Sync.ApplyImport(withWanted)
        assertEq(SideQuestDB.prices[111].w, 4, "wanted carried through as w")
        assertEq(SideQuestDB.prices[222].w, 0, "a price entry without wanted defaults to 0")
    end)

    test("tooltip wanted line: shown under the Auction house line, singular for one, plural otherwise, absent at zero", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false

        SideQuestDB.prices[14048] = { p = 12000, q = 35, at = WowStub.time - 3600, w = 1 }
        local callback = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Item][1]
        local tooltip = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip, { id = 14048 })
        assertTrue(sawLine(tooltip, "Wanted by 1 guildie"), "singular wording for exactly one wisher")

        SideQuestDB.prices[14049] = { p = 500, q = 2, at = WowStub.time, w = 3 }
        local tooltip2 = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip2, { id = 14049 })
        assertTrue(sawLine(tooltip2, "Wanted by 3 guildies"), "plural wording for more than one wisher")

        SideQuestDB.prices[14050] = { p = 100, q = 1, at = WowStub.time, w = 0 }
        local tooltip3 = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip3, { id = 14050 })
        for _, l in ipairs(tooltip3.lines) do
            assertTrue(not l:find("^Wanted by"), "no wanted line when nobody wants it")
        end
    end)

    test("tooltip wanted line: an import from before the `wanted` field existed shows no wanted line", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false

        -- An old import stores prices without `w` at all (Sync.ApplyImport before this field existed).
        SideQuestDB.prices[14048] = { p = 12000, q = 35, at = WowStub.time - 3600 }
        local callback = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Item][1]
        local tooltip = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip, { id = 14048 })
        assertTrue(sawLine(tooltip, "Auction house: 1g 20s (35 listed, 1h ago)"), "the price line still shows")
        for _, l in ipairs(tooltip.lines) do
            assertTrue(not l:find("^Wanted by"), "no wanted line when the field was never imported")
        end
    end)
end
