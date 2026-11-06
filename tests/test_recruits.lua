-- tests/test_recruits.lua
-- Console > Recruits: the add-recruit form (Recruits.AddCandidate and its
-- UI), status cycling, and the empty-state copy that explains where
-- recruits come from.

return function(h)
    local function openRecruits(setup)
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.inCombat = false
        if setup then
            setup()
        end
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Recruits")
        return SideQuest.UI.panels.Console.recruitsChamber
    end

    h.test("Recruits.AddCandidate: a valid name queues an applicant recruit, exported correctly", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT1" })

        local recruit, err = SideQuest.Recruits.AddCandidate("Newbie", "MAGE", "Found in trade chat")
        h.assertTrue(recruit ~= nil, "recruit created: " .. tostring(err))
        h.assertEq(recruit.character, "Newbie-Whitemane", "realm appended")
        h.assertEq(recruit.status, "applicant", "defaults to applicant")
        h.assertEq(recruit.class, "MAGE", "class carried over")
        h.assertEq(recruit.note, "Found in trade chat", "note carried over")
        h.assertTrue(recruit.id ~= nil and recruit.id ~= "", "id assigned")
        h.assertTrue(recruit.at ~= nil, "at assigned")
        h.assertEq(#SideQuestDB.pending.recruits, 1, "queued for export")

        local exported = SideQuest.Codec.DecodeExport(SideQuest.Sync.BuildExport()).recruits[1]
        h.assertEq(exported.character, "Newbie-Whitemane", "export has character")
        h.assertEq(exported.status, "applicant", "export has status")
        h.assertEq(exported.id, recruit.id, "export has id")
    end)

    h.test("Recruits.AddCandidate: a duplicate character is ignored, not duplicated", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT2" })

        local first = SideQuest.Recruits.AddCandidate("Newbie-Whitemane")
        h.assertTrue(first ~= nil, "first add succeeds")
        local second, err = SideQuest.Recruits.AddCandidate("Newbie-Whitemane")
        h.assertTrue(second == nil, "duplicate refused")
        h.assertTrue(err ~= nil and err:find("already a recruit", 1, true) ~= nil,
            "reason names the duplicate: " .. tostring(err))
        h.assertEq(#SideQuest.Recruits.List(), 1, "still only one recruit")
    end)

    h.test("Recruits.AddCandidate: a non-officer can't add a recruit", function()
        h.resetAddon()
        WowStub.isOfficer = false
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Member", realm = "Whitemane", class = "HUNTER", guid = "Player-1-RECRUIT3" })

        local recruit, err = SideQuest.Recruits.AddCandidate("Newbie-Whitemane")
        h.assertTrue(recruit == nil, "refused")
        h.assertTrue(err ~= nil, "a reason is given")
        h.assertEq(#SideQuest.Recruits.List(), 0, "nothing added")
    end)

    h.test("Recruits.AddCandidate: an empty or malformed name is rejected", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT4" })

        local recruit, err = SideQuest.Recruits.AddCandidate("   ")
        h.assertTrue(recruit == nil, "blank name refused")
        h.assertTrue(err ~= nil, "a reason is given: " .. tostring(err))
    end)

    h.test("Console > Recruits: the add-recruit form queues a recruit and clears itself", function()
        local chamber = openRecruits(function()
            WowStub.isOfficer = true
            WowStub.realm = "Whitemane"
            WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT5" })
        end)

        chamber.nameBox:SetText("Freshface-Whitemane")
        chamber.noteBox:SetText("Met in LFG")
        chamber.addBtn:GetScript("OnClick")()

        h.assertEq(#SideQuest.Recruits.List(), 1, "one recruit added")
        h.assertEq(SideQuest.Recruits.List()[1].character, "Freshface-Whitemane", "character matches the form")
        h.assertEq(SideQuest.Recruits.List()[1].note, "Met in LFG", "note matches the form")
        h.assertEq(chamber.nameBox:GetText(), "", "name box clears after adding")
        h.assertEq(chamber.noteBox:GetText(), "", "note box clears after adding")
    end)

    h.test("Console > Recruits: adding the same character twice from the form only adds it once", function()
        local chamber = openRecruits(function()
            WowStub.isOfficer = true
            WowStub.realm = "Whitemane"
            WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT6" })
        end)

        chamber.nameBox:SetText("Freshface-Whitemane")
        chamber.addBtn:GetScript("OnClick")()
        chamber.nameBox:SetText("Freshface-Whitemane")
        chamber.addBtn:GetScript("OnClick")()

        h.assertEq(#SideQuest.Recruits.List(), 1, "second add is ignored as a duplicate")
    end)

    h.test("Console > Recruits: a non-officer can't use the add-recruit button", function()
        local chamber = openRecruits(function()
            WowStub.isOfficer = false
            WowStub.realm = "Whitemane"
            WowStub.SetUnit("player", { name = "Member", realm = "Whitemane", class = "HUNTER", guid = "Player-1-RECRUIT7" })
        end)

        h.assertTrue(not chamber.addBtn.__enabled, "add button disabled for a non-officer")
        h.assertTrue(chamber.addBtn.__disabledReason ~= nil, "disabled reason given")
    end)

    h.test("Console > Recruits: prefills the add-recruit name from a target not already in the guild", function()
        local chamber = openRecruits(function()
            WowStub.isOfficer = true
            WowStub.realm = "Whitemane"
            WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT8" })
            WowStub.SetUnit("target", { name = "Looky", realm = "Whitemane", class = "ROGUE", isPlayer = true })
        end)

        h.assertEq(chamber.nameBox:GetText(), "Looky-Whitemane", "name box prefilled from target")

        chamber.addBtn:GetScript("OnClick")()
        h.assertEq(SideQuest.Recruits.List()[1].class, "ROGUE", "prefilled class carried into the new recruit")
    end)

    h.test("Console > Recruits: never prefills a target already on the guild roster", function()
        local chamber = openRecruits(function()
            WowStub.isOfficer = true
            WowStub.realm = "Whitemane"
            WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT9" })
            WowStub.SetUnit("target", { name = "Already", realm = "Whitemane", class = "ROGUE", isPlayer = true })
            SideQuestDB.roster = { taken_at = 0, members = { { character = "Already-Whitemane" } } }
        end)

        h.assertEq(chamber.nameBox:GetText(), "", "no prefill for a guildmate")
    end)

    h.test("Console > Recruits: status cycles through the pipeline and the empty state explains where recruits come from",
        function()
            local chamber = openRecruits(function()
                WowStub.isOfficer = true
                WowStub.realm = "Whitemane"
                WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RECRUIT10" })
            end)
            local emptyText = chamber.emptyText:GetText()
            h.assertTrue(emptyText:find("No recruits yet", 1, true) ~= nil, "empty state names the state: " .. emptyText)
            h.assertTrue(emptyText:find("Officers page", 1, true) ~= nil, "empty state points at the site: " .. emptyText)

            SideQuest.Recruits.AddCandidate("Cycler-Whitemane")
            SideQuest.UI.RefreshConsoleRecruits()
            local row = chamber.rows[1]
            h.assertEq(row.statusBtn:GetText(), "(applicant)", "starts as applicant")

            row.statusBtn:GetScript("OnClick")()
            h.assertEq(SideQuest.Recruits.List()[1].status, "trial", "advances to trial")

            chamber.rows[1].statusBtn:GetScript("OnClick")()
            h.assertEq(SideQuest.Recruits.List()[1].status, "accepted", "advances to accepted")
        end)
end
