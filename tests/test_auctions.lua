-- tests/test_auctions.lua
-- Game import "prices" (SQI1), the item tooltip's Auction house line, and the
-- AH price shown next to a member's price on the Market tab's Browse and
-- Mine rows. See the shared auctions contract's "Game import" section.

return function(h)
    local test, assertEq, assertTrue, resetAddon = h.test, h.assertEq, h.assertTrue, h.resetAddon

    local function setupPlayer()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-AUCT0001" })
    end

    --------------------------------------------------------------------------
    -- Import: Sync.ApplyImport stores/replaces/clears SideQuestDB.prices
    --------------------------------------------------------------------------

    test("import: payload.prices stores, replaces wholesale, clears on empty, and keeps on absent", function()
        resetAddon()
        setupPlayer()

        local base = { v = 1, generated_at = WowStub.time, rules = nil, standings = {}, killed_encounters = {}, events = {} }

        local withPrices = {}
        for k, v in pairs(base) do withPrices[k] = v end
        withPrices.prices = {
            { item_id = 14048, unit_price = 12000, quantity = 35, at = WowStub.time - 7200 },
            { item_id = 12360, unit_price = 500, quantity = 10, at = WowStub.time },
        }
        SideQuest.Sync.ApplyImport(withPrices)
        assertEq(SideQuestDB.prices[14048].p, 12000, "first import: unit_price stored as p")
        assertEq(SideQuestDB.prices[14048].q, 35, "first import: quantity stored as q")
        assertEq(SideQuestDB.prices[14048].at, WowStub.time - 7200, "first import: at stored")
        assertEq(SideQuestDB.prices[12360].p, 500, "first import: second item stored")

        local replaced = {}
        for k, v in pairs(base) do replaced[k] = v end
        replaced.prices = { { item_id = 14048, unit_price = 9000, quantity = 5, at = WowStub.time } }
        SideQuest.Sync.ApplyImport(replaced)
        assertEq(SideQuestDB.prices[14048].p, 9000, "second import: price replaced")
        assertEq(SideQuestDB.prices[12360], nil, "second import: item missing from the new payload is gone (wholesale replace)")

        local noPricesField = {}
        for k, v in pairs(base) do noPricesField[k] = v end
        SideQuest.Sync.ApplyImport(noPricesField)
        assertEq(SideQuestDB.prices[14048].p, 9000, "import predating the field: existing prices untouched")

        local cleared = {}
        for k, v in pairs(base) do cleared[k] = v end
        cleared.prices = {}
        SideQuest.Sync.ApplyImport(cleared)
        assertEq(next(SideQuestDB.prices), nil, "import with an empty prices list clears it")
    end)

    --------------------------------------------------------------------------
    -- Tooltip: "Auction house: ..." line for a priced item, none otherwise
    --------------------------------------------------------------------------

    test("tooltip: a priced item gets an Auction house line; an unpriced item gets none", function()
        resetAddon()
        setupPlayer()
        WowStub.inCombat = false

        local callback = TooltipDataProcessor.callbacks[Enum.TooltipDataType.Item][1]
        assertTrue(callback ~= nil, "SideQuest registered a tooltip post-call for items")

        SideQuestDB.prices[14048] = { p = 12000, q = 35, at = WowStub.time - 7200 }
        local tooltip = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip, { id = 14048 })
        local sawPriceLine = false
        for _, line in ipairs(tooltip.lines) do
            if line == "Auction house: 1g 20s (35 listed, 2h ago)" then
                sawPriceLine = true
            end
        end
        assertTrue(sawPriceLine, "priced item shows the AH line with price, listing count and age")

        local tooltip2 = CreateFrame("GameTooltip", nil, UIParent)
        callback(tooltip2, { id = 99999 })
        for _, line in ipairs(tooltip2.lines) do
            assertTrue(not line:find("^Auction house:"), "unpriced item shows no Auction house line")
        end
    end)

    --------------------------------------------------------------------------
    -- Market tab: Browse and Mine rows show the AH price next to the
    -- member's own price.
    --------------------------------------------------------------------------

    test("market Browse: Sellers and Standing buy offers rows show the AH price", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.prices[14048] = { p = 15000, q = 10, at = WowStub.time }
        SideQuestDB.directory = {
            ["Alt1-Whitemane"] = { seen_at = 1000, market = { v = "x", at = 1000, d = {
                sell = { { item_id = 14048, price = 12000, qty = 5 } },
            } } },
            ["Alt2-Whitemane"] = { seen_at = 1000, market = { v = "y", at = 1000, d = {
                buy = { { item_id = 14048, price = 9000 } },
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Market")
        SideQuest.UI.ShowMarketSub("Browse")
        local chamber = SideQuest.UI.panels.Market.browseChamber
        chamber.lookupItemId = 14048
        SideQuest.UI.RefreshMarketBrowse()
        assertTrue(chamber.sellRows[1].detailText:GetText():find("AH 1g 50s", 1, true) ~= nil,
            "seller row shows the AH price alongside the member's price")
        assertTrue(chamber.buyRows[1].detailText:GetText():find("AH 1g 50s", 1, true) ~= nil,
            "buyer row shows the AH price alongside the member's price")
    end)

    test("market Mine: sell and buy rows show the AH price", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.prices[14048] = { p = 15000, q = 10, at = WowStub.time }
        SideQuestDB.prices[12360] = { p = 800, q = 3, at = WowStub.time }
        SideQuestDB.directory = {
            ["Demo1-Whitemane"] = { seen_at = 1000, market = { v = "x", at = 1000, d = {
                sell = { { item_id = 14048, price = 12000, qty = 5 } },
                buy = { { item_id = 12360, price = 500 } },
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Market")
        SideQuest.UI.ShowMarketSub("Mine")
        local chamber = SideQuest.UI.panels.Market.mineChamber
        SideQuest.UI.RefreshMarketMine()
        assertTrue(chamber.sellListRows[1].text:GetText():find("AH 1g 50s", 1, true) ~= nil,
            "the player's own sell row shows the AH price")
        assertTrue(chamber.buyListRows[1].text:GetText():find("AH 8s", 1, true) ~= nil,
            "the player's own buy row shows the AH price")
    end)
end
