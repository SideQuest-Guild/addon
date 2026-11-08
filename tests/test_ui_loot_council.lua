-- tests/test_ui_loot_council.lua
-- Console > Loot: the council-award form (contract: addon council award)
-- alongside the existing ranked-bid Award flow.

return function(h)
    local function openLoot()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.isOfficer = true
        WowStub.inCombat = false
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-UILOOT1" })
        WowStub.items = {
            [2001] = { itemId = 2001, name = "Demo Trinket", quality = 4, equipLoc = "INVTYPE_TRINKET",
                icon = "Interface\\Icons\\INV_Misc_Gem_01" },
            [2002] = { itemId = 2002, name = "Demo Chest Token", quality = 4, equipLoc = nil,
                icon = "Interface\\Icons\\INV_Chest_Plate04" },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Loot")
        return SideQuest.UI.panels.Console.lootChamber
    end

    h.test("Council award: Award stays disabled until item, winner, kind and reason are all set", function()
        local chamber = openLoot()
        h.assertTrue(chamber.councilAwardBtn.__enabled == false, "disabled with nothing filled in")

        chamber.councilItemBox:SetText("2001")
        chamber.councilWinnerBox:SetText("Winner")
        chamber.councilKindButtons.chase:GetScript("OnClick")()
        h.assertTrue(chamber.councilAwardBtn.__enabled == false, "still disabled without a reason")

        chamber.councilReasonBox:SetText("Best upgrade available")
        SideQuest.UI.RefreshBidRanking()
        h.assertTrue(chamber.councilAwardBtn.__enabled == true, "enabled once everything is filled in")
        h.assertEq(chamber.councilGpText:GetText(),
            "GP " .. SideQuest.Rules.ComputeGP("INVTYPE_TRINKET", "council", { isChase = true }),
            "GP preview matches Rules.ComputeGP for the chase kind")
    end)

    h.test("Council award: an empty winner name or no item keeps Award disabled", function()
        local chamber = openLoot()
        chamber.councilReasonBox:SetText("Reason")
        chamber.councilKindButtons.chase:GetScript("OnClick")()
        SideQuest.UI.RefreshBidRanking()
        h.assertTrue(chamber.councilAwardBtn.__enabled == false, "no item, no winner: still disabled")

        chamber.councilWinnerBox:SetText("Winner")
        SideQuest.UI.RefreshBidRanking()
        h.assertTrue(chamber.councilAwardBtn.__enabled == false, "winner set but no item: still disabled")
    end)

    h.test("Council award: picking Tier shows the slot buttons and requires one before Award enables", function()
        local chamber = openLoot()
        chamber.councilItemBox:SetText("2002")
        chamber.councilWinnerBox:SetText("Winner")
        chamber.councilReasonBox:SetText("Only token drop")
        chamber.councilKindButtons.tier:GetScript("OnClick")()

        h.assertTrue(chamber.councilSlotButtons.INVTYPE_CHEST:IsShown(), "slot buttons show for the tier kind")
        h.assertTrue(chamber.councilAwardBtn.__enabled == false, "disabled until a slot is picked")

        chamber.councilSlotButtons.INVTYPE_CHEST:GetScript("OnClick")()
        h.assertTrue(chamber.councilAwardBtn.__enabled == true, "enabled once a slot is picked")
        h.assertEq(chamber.councilGpText:GetText(), "GP " .. SideQuest.Rules.active.gp.INVTYPE_CHEST,
            "GP preview uses the picked slot even though the token's own inv_type is nil")

        chamber.councilKindButtons.chase:GetScript("OnClick")()
        h.assertTrue(not chamber.councilSlotButtons.INVTYPE_CHEST:IsShown(), "slot buttons hide outside the tier kind")
    end)

    h.test("Council award: clicking Award records the loot row and clears the form", function()
        local chamber = openLoot()
        chamber.councilItemBox:SetText("2001")
        chamber.councilWinnerBox:SetText("Winner")
        chamber.councilKindButtons.legendary:GetScript("OnClick")()
        chamber.councilReasonBox:SetText("Unique legendary drop")
        SideQuest.UI.RefreshBidRanking()

        chamber.councilAwardBtn:GetScript("OnClick")()

        h.assertEq(#SideQuestDB.pending.loot, 1, "one loot row recorded")
        local row = SideQuestDB.pending.loot[1]
        h.assertEq(row.character, "Winner-Whitemane", "winner normalized with the player's realm")
        h.assertEq(row.response, "council", "response is council")
        h.assertEq(row.council_kind, "legendary", "kind stored")
        h.assertEq(row.council_reason, "Unique legendary drop", "reason stored")
        h.assertEq(row.gp, SideQuest.Rules.active.legendary_gp, "legendary GP")

        h.assertEq(chamber.councilItemBox:GetText(), "", "item box cleared")
        h.assertEq(chamber.councilWinnerBox:GetText(), "", "winner box cleared")
        h.assertEq(chamber.councilReasonBox:GetText(), "", "reason box cleared")
        h.assertTrue(chamber.councilAwardBtn.__enabled == false, "disabled again after awarding")
    end)

    h.test("Council award: clicking Award while invalid is a no-op (defense in depth under the disabled button)", function()
        local chamber = openLoot()
        chamber.councilAwardBtn:GetScript("OnClick")()
        h.assertEq(#SideQuestDB.pending.loot, 0, "nothing recorded with an empty form")
    end)

    h.test("Console Loot: an ordinary ranked-bid award is unaffected by the council form", function()
        local chamber = openLoot()
        SideQuest.Loot.OpenBid("item:2001:Demo Trinket")
        SideQuest.Loot.RecordResponse("Bidder-Whitemane", "ms")
        SideQuest.UI.RefreshBidRanking()
        h.assertTrue(#chamber.bidRows >= 1 and chamber.bidRows[1]:IsShown(), "ranked bid row shown")

        chamber.bidRows[1].awardBtn:GetScript("OnClick")()

        h.assertEq(#SideQuestDB.pending.loot, 1, "ms award recorded as before")
        h.assertTrue(SideQuestDB.pending.loot[1].council_reason == nil, "ordinary award carries no council fields")
        h.assertEq(SideQuestDB.pending.loot[1].response, "ms", "response is still ms")
    end)
end
