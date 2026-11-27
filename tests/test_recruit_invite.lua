-- tests/test_recruit_invite.lua
-- After your own recruiting post, whispers from non-members show in a popup with an Invite button
-- (RecruitInvite.lua, UI/RecruitPopup.lua). Nobody is invited without a click.

return function(h)
    local MY_GUID = "Player-1-RINV0001"

    local function setup()
        h.resetAddon()
        WowStub.inCombat = false
        WowStub.SetForever(true)
        WowStub.SetUnit("player", { name = "Legs", realm = "Behindhead", class = "PALADIN", guid = MY_GUID })
        WowStub.guildRoster = {
            { name = "Legs Behindhead", rank = "Member", rankIndex = 3, level = 60, class = "PALADIN",
                classFile = "PALADIN", zone = "", online = true },
            { name = "Guildie Mcguild", rank = "Member", rankIndex = 3, level = 60, class = "MAGE",
                classFile = "MAGE", zone = "", online = true },
        }
        if SideQuest.UI.recruitPopup then
            SideQuest.UI.recruitPopup:Hide()
        end
    end

    local function post(text, sender, guid)
        WowStub.FireEvent("CHAT_MSG_CHANNEL", text, sender or "Legs-Behindhead", "", "2. Trade - City", "", "", 2, 2,
            "Trade - City", 0, 1, guid or MY_GUID)
    end

    local function whisper(text, sender, flags)
        WowStub.FireEvent("CHAT_MSG_WHISPER", text, sender, "", "", "", flags or "", 0, 0, "", 0, 2, "Player-1-OTHER")
    end

    local function popupShown()
        return SideQuest.UI.recruitPopup ~= nil and SideQuest.UI.recruitPopup:IsShown()
    end

    h.test("recruit invite: a whisper after your post shows an Invite button and invites only on click", function()
        setup()
        post("<SideQuest> is recruiting all levels, /w me for an invite!")
        whisper("inv pls", "Newbie-Fresh")

        h.assertTrue(popupShown(), "popup shown for the whisper")
        h.assertEq(#WowStub.guildInvites, 0, "nobody invited before the click")
        local row = SideQuest.UI.recruitPopup.rows[1]
        h.assertEq(row.nameText:GetText(), "Newbie-Fresh", "row names the whisperer")
        h.assertTrue(row.msgText:GetText():find("inv pls", 1, true) ~= nil, "row shows what they said")

        row.inviteBtn:GetScript("OnClick")(row.inviteBtn)
        h.assertEq(#WowStub.guildInvites, 1, "one invite sent")
        h.assertEq(WowStub.guildInvites[1], "Newbie-Fresh", "invited the whisperer")
        h.assertTrue(not popupShown(), "popup closes once nobody is left")

        whisper("thanks!", "Newbie-Fresh")
        h.assertTrue(not popupShown(), "someone already invited isn't offered again")
    end)

    h.test("recruit invite: whispers without your recruiting post, or after the window, are ignored", function()
        setup()
        whisper("hi", "Stranger-One")
        h.assertTrue(not popupShown(), "no post yet: no popup")

        post("<SideQuest> recruiting", "Someone-Else", "Player-1-SOMEONE")
        whisper("hi", "Stranger-One")
        h.assertTrue(not popupShown(), "someone else's post doesn't open the window")

        post("anyone selling copper ore?")
        whisper("hi", "Stranger-One")
        h.assertTrue(not popupShown(), "a post that isn't recruiting doesn't open the window")

        post("Recruiting for <SideQuest>!")
        WowStub.Advance(SideQuest.RecruitInvite.WINDOW + 1)
        whisper("hi", "Stranger-One")
        h.assertTrue(not popupShown(), "window closed after its time")

        post("Recruiting for <SideQuest>!")
        whisper("hi", "Stranger-One")
        h.assertTrue(popupShown(), "posting again reopens it")
    end)

    h.test("recruit invite: guildmates, Blizzard staff and characters who can't invite get no popup", function()
        setup()
        post("SideQuest recruiting")
        whisper("hey legs", "Guildie-Mcguild")
        h.assertTrue(not popupShown(), "a guildmate's whisper is skipped")
        whisper("hello", "Blizz-Staff", "GM")
        h.assertTrue(not popupShown(), "a GM whisper is skipped")

        setup()
        WowStub.canGuildInvite = false
        post("SideQuest recruiting")
        whisper("inv", "Newbie-Fresh")
        h.assertTrue(not popupShown(), "no invite rights: no popup")
    end)

    h.test("recruit invite: Skip and Close drop rows without inviting; one row per whisperer", function()
        setup()
        post("SideQuest recruiting")
        whisper("inv", "Newbie-One")
        whisper("inv me too", "Newbie-Two")
        whisper("hello?", "Newbie-One")
        h.assertEq(#SideQuest.RecruitInvite.Queue(), 2, "a second whisper updates the row, not a new one")
        h.assertEq(SideQuest.RecruitInvite.Queue()[1].text, "hello?", "row shows their latest whisper")

        local first = SideQuest.UI.recruitPopup.rows[1]
        first.skipBtn:GetScript("OnClick")(first.skipBtn)
        h.assertEq(#SideQuest.RecruitInvite.Queue(), 1, "skip drops the row")
        h.assertTrue(popupShown(), "popup stays while someone is left")

        SideQuest.UI.recruitPopup.closeBtn:GetScript("OnClick")(SideQuest.UI.recruitPopup.closeBtn)
        h.assertEq(#SideQuest.RecruitInvite.Queue(), 0, "close drops everyone left")
        h.assertEq(#WowStub.guildInvites, 0, "nobody invited")

        -- A relog and a new recruiting post later: the skipped whisperer stays gone, the closed one comes back.
        SideQuest.RecruitInvite.ResetState()
        post("SideQuest recruiting again")
        whisper("inv??", "Newbie-One")
        h.assertTrue(not popupShown(), "someone you skipped never pops up again")
        h.assertEq(#SideQuest.RecruitInvite.Queue(), 0)
        whisper("still want in", "Newbie-Two")
        h.assertEq(#SideQuest.RecruitInvite.Queue(), 1, "closing the popup isn't a skip: they can whisper again")
        h.assertEq(SideQuest.RecruitInvite.Queue()[1].name, "Newbie-Two")
    end)

    h.test("recruit invite: a whisper in combat waits for combat to end", function()
        setup()
        post("SideQuest recruiting")
        WowStub.inCombat = true
        whisper("inv", "Newbie-Fresh")
        h.assertTrue(not popupShown(), "no popup mid-fight")
        WowStub.inCombat = false
        WowStub.FireEvent("PLAYER_REGEN_ENABLED")
        h.assertTrue(popupShown(), "popup once combat ends")
    end)
end
