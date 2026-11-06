-- tests/test_ui_guild_rows.lua
-- Two Guild tab row bugs: hovering Whisper/Invite used to flicker, and an unreadable
-- character name must say so instead of going blank.

return function(h)
    local test, assertTrue, assertEq, resetAddon = h.test, h.assertTrue, h.assertEq, h.resetAddon

    local function open()
        resetAddon()
        SideQuest.UI.main = nil
        WowStub.inCombat = false
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-GROW001" })
        SideQuestDB.roster = { taken_at = 1000, members = {
            { character = "Alt1-Whitemane", rank = "Member", online = true, class = "MAGE", level = 30,
                zone = "Ironforge" },
        } }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Guild")
        return SideQuest.UI.panels.Guild.chamber
    end

    test("guild: hovering onto Whisper/Invite doesn't flicker the buttons", function()
        local chamber = open()
        SideQuest.UI.RefreshGuild()
        local row = chamber.rows[1]

        WowStub.mouseOverFrame = row
        row:GetScript("OnEnter")()
        assertTrue(row.whisperBtn:IsShown(), "hovering the row shows Whisper")
        assertTrue(row.inviteBtn:IsShown(), "hovering the row shows Invite")

        -- The pointer moves onto the child Whisper button: the row's own
        -- OnLeave fires (the child takes mouse focus) even though the
        -- pointer never left the row's rect.
        WowStub.mouseOverFrame = row.whisperBtn
        row:GetScript("OnLeave")()
        assertTrue(row.whisperBtn:IsShown(), "moving onto Whisper doesn't hide it")
        assertTrue(row.inviteBtn:IsShown(), "moving onto Whisper doesn't hide Invite either")

        -- Leaving Whisper for Invite (still inside the row) fires Whisper's
        -- own OnLeave (its hover-paint reset) too.
        WowStub.mouseOverFrame = row.inviteBtn
        row.whisperBtn:GetScript("OnLeave")()
        assertTrue(row.whisperBtn:IsShown(), "crossing from Whisper to Invite doesn't hide either button")
        assertTrue(row.inviteBtn:IsShown(), "crossing from Whisper to Invite doesn't hide either button")

        -- The pointer finally leaves the row for good.
        WowStub.mouseOverFrame = nil
        row.inviteBtn:GetScript("OnLeave")()
        assertTrue(not row.whisperBtn:IsShown(), "leaving the row for good hides Whisper")
        assertTrue(not row.inviteBtn:IsShown(), "leaving the row for good hides Invite")
    end)

    test("guild: a selected row keeps Whisper/Invite shown even once the pointer leaves", function()
        local chamber = open()
        chamber.selectedCharacter = "Alt1-Whitemane"
        SideQuest.UI.RefreshGuild()
        local row = chamber.rows[1]

        WowStub.mouseOverFrame = row
        row:GetScript("OnEnter")()
        WowStub.mouseOverFrame = nil
        row:GetScript("OnLeave")()
        assertTrue(row.whisperBtn:IsShown(), "a selected row's Whisper button stays shown after the pointer leaves")
        assertTrue(row.inviteBtn:IsShown(), "a selected row's Invite button stays shown after the pointer leaves")
    end)

    test("guild: an unreadable character name shows as Unknown instead of going blank", function()
        resetAddon()
        local ok, result = pcall(SideQuest.UI.DisplayName, WowStub.SECRET)
        assertTrue(ok, "doesn't error on an unreadable name: " .. tostring(result))
        assertEq(result, "Unknown", "shows something instead of going blank")
    end)

    test("guild: a nil character still shows nothing (not Unknown -- there's simply no name)", function()
        resetAddon()
        assertEq(SideQuest.UI.DisplayName(nil), "", "no character at all stays blank, unlike an unreadable one")
    end)
end
