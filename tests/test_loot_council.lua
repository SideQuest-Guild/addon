-- tests/test_loot_council.lua
-- Council loot awards (contract: addon council award): Loot.AwardLoot's
-- kind/reason validation and GP-by-kind, and the SQX1 export carrying
-- council_reason/council_kind only on council rows.

return function(h)
    local function setupOfficer()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.realm = "Whitemane"
        WowStub.inCombat = false
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-COUNCIL1" })
    end

    h.test("Loot.AwardLoot council: GP follows the chase kind via Rules.ComputeGP", function()
        setupOfficer()
        local lootId = SideQuest.Loot.AwardLoot(
            { item_id = 1001, item_name = "Chase Trinket", quality = 4, inv_type = "INVTYPE_TRINKET" },
            "Winner-Whitemane", "council", nil, nil,
            { councilKind = "chase", councilReason = "Best in slot for the tank", isChase = true })
        h.assertTrue(lootId ~= nil, "award recorded")
        local row = SideQuestDB.pending.loot[1]
        h.assertEq(row.gp, SideQuest.Rules.ComputeGP("INVTYPE_TRINKET", "council", { isChase = true }),
            "chase GP matches Rules.ComputeGP")
        h.assertEq(row.response, "council", "response stored as council")
        h.assertEq(row.council_kind, "chase", "kind stored")
        h.assertEq(row.council_reason, "Best in slot for the tank", "reason stored")
    end)

    h.test("Loot.AwardLoot council: legendary kind charges the flat legendary GP regardless of slot", function()
        setupOfficer()
        SideQuest.Loot.AwardLoot(
            { item_id = 1002, item_name = "Legendary Cloak", quality = 5, inv_type = "INVTYPE_CLOAK" },
            "Winner-Whitemane", "council", nil, nil,
            { councilKind = "legendary", councilReason = "Only drop this tier", isLegendary = true })
        local row = SideQuestDB.pending.loot[1]
        h.assertEq(row.gp, SideQuest.Rules.active.legendary_gp, "legendary GP is the flat legendary_gp")
        h.assertEq(row.council_kind, "legendary", "kind stored")
    end)

    h.test("Loot.AwardLoot council: tier kind prices off the picked slot, not the token's own inv_type", function()
        setupOfficer()
        SideQuest.Loot.AwardLoot(
            { item_id = 1003, item_name = "Tier Token", quality = 4, inv_type = nil },
            "Winner-Whitemane", "council", nil, nil,
            { councilKind = "tier", councilReason = "Last token this tier", isTierToken = true, tierSlotInvType = "INVTYPE_CHEST" })
        local row = SideQuestDB.pending.loot[1]
        h.assertEq(row.gp, SideQuest.Rules.active.gp.INVTYPE_CHEST,
            "tier GP uses the chosen slot even though the token's own inv_type is nil")
        h.assertEq(row.council_kind, "tier", "kind stored")
    end)

    h.test("Loot.AwardLoot council: a missing or invalid kind is rejected", function()
        setupOfficer()
        local lootId = SideQuest.Loot.AwardLoot(
            { item_id = 1004, item_name = "X", quality = 1, inv_type = "INVTYPE_HEAD" },
            "Winner-Whitemane", "council", nil, nil, { councilReason = "reason here" })
        h.assertTrue(lootId == nil, "rejected without a kind")
        h.assertEq(#SideQuestDB.pending.loot, 0, "nothing recorded")

        local lootId2 = SideQuest.Loot.AwardLoot(
            { item_id = 1004, item_name = "X", quality = 1, inv_type = "INVTYPE_HEAD" },
            "Winner-Whitemane", "council", nil, nil, { councilKind = "bogus", councilReason = "reason here" })
        h.assertTrue(lootId2 == nil, "rejected with an unknown kind")
        h.assertEq(#SideQuestDB.pending.loot, 0, "still nothing recorded")
    end)

    h.test("Loot.AwardLoot council: an empty, whitespace-only or too-long reason is rejected", function()
        setupOfficer()
        local lootId1 = SideQuest.Loot.AwardLoot(
            { item_id = 1005, item_name = "X", quality = 1, inv_type = "INVTYPE_HEAD" },
            "Winner-Whitemane", "council", nil, nil, { councilKind = "chase", isChase = true })
        h.assertTrue(lootId1 == nil, "no reason rejected")

        local lootId2 = SideQuest.Loot.AwardLoot(
            { item_id = 1005, item_name = "X", quality = 1, inv_type = "INVTYPE_HEAD" },
            "Winner-Whitemane", "council", nil, nil, { councilKind = "chase", isChase = true, councilReason = "   " })
        h.assertTrue(lootId2 == nil, "whitespace-only reason rejected")

        local lootId3 = SideQuest.Loot.AwardLoot(
            { item_id = 1005, item_name = "X", quality = 1, inv_type = "INVTYPE_HEAD" },
            "Winner-Whitemane", "council", nil, nil,
            { councilKind = "chase", isChase = true, councilReason = string.rep("x", 201) })
        h.assertTrue(lootId3 == nil, "over-200-char reason rejected")

        h.assertEq(#SideQuestDB.pending.loot, 0, "nothing recorded across all three rejections")
    end)

    h.test("Loot.AwardLoot council: the reason is trimmed before storing", function()
        setupOfficer()
        SideQuest.Loot.AwardLoot(
            { item_id = 1006, item_name = "X", quality = 1, inv_type = "INVTYPE_HEAD" },
            "Winner-Whitemane", "council", nil, nil,
            { councilKind = "chase", isChase = true, councilReason = "  padded reason  " })
        h.assertEq(SideQuestDB.pending.loot[1].council_reason, "padded reason", "leading/trailing space trimmed")
    end)

    h.test("Codec export: council_reason/council_kind ship only on council rows, surviving encode/decode", function()
        setupOfficer()
        SideQuest.Loot.AwardLoot(
            { item_id = 1007, item_name = "Council Item", quality = 4, inv_type = "INVTYPE_TRINKET" },
            "Winner-Whitemane", "council", nil, nil,
            { councilKind = "chase", isChase = true, councilReason = "Needed for progression" })
        SideQuest.Loot.AwardLoot(
            { item_id = 1008, item_name = "Normal Item", quality = 3, inv_type = "INVTYPE_HEAD" },
            "Someone-Whitemane", "ms", nil, nil, {})

        local payload = SideQuest.Codec.BuildExportPayload("Officer1-Whitemane", "Guild", "Whitemane")
        local councilRow, msRow
        for _, row in ipairs(payload.loot) do
            if row.response == "council" then
                councilRow = row
            elseif row.response == "ms" then
                msRow = row
            end
        end
        h.assertTrue(councilRow ~= nil, "council row present")
        h.assertEq(councilRow.council_kind, "chase", "council row carries kind")
        h.assertEq(councilRow.council_reason, "Needed for progression", "council row carries reason")
        h.assertTrue(msRow ~= nil, "ms row present")
        h.assertTrue(msRow.council_reason == nil, "non-council row has no council_reason")
        h.assertTrue(msRow.council_kind == nil, "non-council row has no council_kind")

        -- round-trip through the actual SQX1: wire format, not just the Lua table
        local decoded = SideQuest.Codec.DecodeExport(SideQuest.Codec.EncodeExport(payload))
        local decodedCouncil, decodedMs
        for _, row in ipairs(decoded.loot) do
            if row.response == "council" then
                decodedCouncil = row
            elseif row.response == "ms" then
                decodedMs = row
            end
        end
        h.assertEq(decodedCouncil.council_reason, "Needed for progression", "survives encode/decode")
        h.assertTrue(decodedMs.council_reason == nil, "still absent on the ms row after encode/decode")
    end)

    h.test("Loot.Undo: voiding a council award works like any other void", function()
        setupOfficer()
        local lootId, awardId = SideQuest.Loot.AwardLoot(
            { item_id = 1009, item_name = "Council Item", quality = 4, inv_type = "INVTYPE_TRINKET" },
            "Winner-Whitemane", "council", nil, nil,
            { councilKind = "chase", isChase = true, councilReason = "Needed for progression" })
        h.assertTrue(SideQuest.Loot.Undo(lootId), "undo reports voided")
        h.assertTrue(SideQuestDB.pending.loot[1].voided, "loot row voided")
        for _, award in ipairs(SideQuestDB.pending.awards) do
            if award.id == awardId then
                h.assertTrue(award.voided, "linked GP award voided too")
            end
        end
    end)
end
