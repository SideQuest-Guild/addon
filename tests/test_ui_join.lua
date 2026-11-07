-- tests/test_ui_join.lua
-- A player who installs the addon but isn't in the SideQuest guild gets
-- the single-pane join window instead of the tabbed one (Main.lua
-- UI.Show/UI.Toggle, Core.lua SideQuest.IsGuildMember).

return function(h)
    h.test("join pane: a member gets the full tabbed window", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        SideQuest.UI.joinFrame = nil
        SideQuest.UI.Show()
        h.assertTrue(SideQuest.UI.main ~= nil and SideQuest.UI.main:IsShown(), "tabbed window shown")
        h.assertTrue(SideQuest.UI.joinFrame == nil, "join pane never built for a member")
    end)

    h.test("join pane: a non-member gets the single-pane window instead of tabs", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        SideQuest.UI.joinFrame = nil
        WowStub.inGuild = false
        WowStub.FireEvent("PLAYER_GUILD_UPDATE") -- resolves membership: confirmed not in the guild
        h.assertEq(SideQuest.IsGuildMember(), false, "membership resolves to false")

        SideQuest.UI.Show()
        h.assertTrue(SideQuest.UI.joinFrame ~= nil and SideQuest.UI.joinFrame:IsShown(), "join pane shown")
        h.assertTrue(SideQuest.UI.main == nil, "tabbed window never built for a non-member")
    end)

    h.test("join pane: guild info not loaded yet doesn't flash the join pane to someone who turns out to be a member", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        SideQuest.UI.joinFrame = nil
        WowStub.inGuild = false -- not loaded yet; membership still unknown
        h.assertEq(SideQuest.IsGuildMember(), nil, "membership unknown before anything resolves it")

        SideQuest.UI.Show()
        h.assertTrue(SideQuest.UI.joinFrame == nil, "join pane not shown while membership is unknown")
        h.assertTrue(SideQuest.UI.main ~= nil and SideQuest.UI.main:IsShown(), "full UI shown instead, assuming member")

        -- guild info resolves: this character really is a member
        WowStub.inGuild = true
        WowStub.FireEvent("PLAYER_GUILD_UPDATE")
        h.assertEq(SideQuest.IsGuildMember(), true, "membership resolves true once guild info loads")
    end)

    h.test("join pane: toggling (minimap/compartment/slash all route through UI.Toggle) opens and closes it", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        SideQuest.UI.joinFrame = nil
        WowStub.inGuild = false
        WowStub.FireEvent("PLAYER_GUILD_UPDATE")

        SideQuest.UI.Toggle()
        h.assertTrue(SideQuest.UI.joinFrame:IsShown(), "first toggle opens the join pane")
        SideQuest.UI.Toggle()
        h.assertTrue(not SideQuest.UI.joinFrame:IsShown(), "second toggle closes it")
    end)

    h.test("join pane: website and Discord links are read-only with the contract URLs", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        SideQuest.UI.joinFrame = nil
        WowStub.inGuild = false
        WowStub.FireEvent("PLAYER_GUILD_UPDATE")
        SideQuest.UI.Show()

        local frame = SideQuest.UI.joinFrame
        h.assertEq(frame.websiteBox:GetText(), "https://sidequest-guild.com/", "website URL shown")
        h.assertEq(frame.discordBox:GetText(), "https://discord.gg/nwncP7H9Hh", "discord URL shown")
        h.assertTrue(frame.websiteHint:GetText():find("Ctrl+C", 1, true) ~= nil, "website hint mentions Ctrl+C")
        h.assertTrue(frame.discordHint:GetText():find("Ctrl+C", 1, true) ~= nil, "discord hint mentions Ctrl+C")

        -- an attempted edit reverts: the box is read-only
        frame.websiteBox:SetText("hacked")
        local onTextChanged = frame.websiteBox:GetScript("OnTextChanged")
        if onTextChanged then
            onTextChanged(frame.websiteBox)
        end
        h.assertEq(frame.websiteBox:GetText(), "https://sidequest-guild.com/", "edit reverted, read-only")
    end)
end
