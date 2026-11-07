-- tests/test_debug.lua
-- The Guild Master's Console "Debug" sub-view: blocked-action/error log
-- (Core.lua SQ.LogDebug) and the "view as" UI preview override
-- (Core.lua SQ.SetViewAs/ViewAs, consulted only by UI/Main.lua's
-- Display* checks -- never by the real SQ.IsOfficer/IsGuildMember used
-- for exports, comms, HELLO and recorder rights).

return function(h)
    h.test("debug log: ADDON_ACTION_BLOCKED/FORBIDDEN record only SideQuest's own events", function()
        h.resetAddon()
        WowStub.FireEvent("ADDON_ACTION_BLOCKED", "SideQuest", "SomeForbiddenFunc")
        WowStub.FireEvent("ADDON_ACTION_FORBIDDEN", "OtherAddon", "SomeFunc")
        local log = SideQuestDB.debug.log
        h.assertEq(#log, 1, "only the SideQuest-addon event was recorded")
        h.assertEq(log[1].kind, "blocked", "entry is kind=blocked")
        h.assertEq(log[1].func, "SomeForbiddenFunc", "function name captured")
        h.assertEq(log[1].event, "ADDON_ACTION_BLOCKED", "event name captured")
        h.assertTrue(log[1].stack ~= nil, "a stack is captured when debugstack() is available")
    end)

    h.test("debug log: a missing debugstack() sends stack=nil instead of erroring", function()
        h.resetAddon()
        local saved = debugstack
        debugstack = nil
        WowStub.FireEvent("ADDON_ACTION_FORBIDDEN", "SideQuest", "AnotherFunc")
        debugstack = saved
        local log = SideQuestDB.debug.log
        h.assertEq(log[1].stack, nil, "no debugstack -> stack is nil, not an error")
    end)

    h.test("debug log: a swallowed SQ.Fire handler error is recorded", function()
        h.resetAddon()
        SideQuest.On("SQ_TEST_EVENT_FOR_DEBUG_LOG", function()
            error("boom")
        end)
        SideQuest.Fire("SQ_TEST_EVENT_FOR_DEBUG_LOG")
        local log = SideQuestDB.debug.log
        h.assertEq(log[1].kind, "error", "entry is kind=error")
        h.assertEq(log[1].event, "SQ_TEST_EVENT_FOR_DEBUG_LOG", "event name captured")
        h.assertTrue(log[1].message:find("boom", 1, true) ~= nil, "error message captured: " .. tostring(log[1].message))
    end)

    h.test("debug log: capped at 50 entries, newest first", function()
        h.resetAddon()
        for i = 1, 55 do
            WowStub.FireEvent("ADDON_ACTION_BLOCKED", "SideQuest", "Func" .. i)
        end
        local log = SideQuestDB.debug.log
        h.assertEq(#log, 50, "capped at 50")
        h.assertEq(log[1].func, "Func55", "newest first")
        h.assertEq(log[50].func, "Func6", "oldest trimmed")
    end)

    h.test("debug log: Clear empties it", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.FireEvent("ADDON_ACTION_BLOCKED", "SideQuest", "F")
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Debug")
        local chamber = SideQuest.UI.panels.Console.debugChamber
        chamber.clearBtn:GetScript("OnClick")()
        h.assertEq(#SideQuestDB.debug.log, 0, "cleared")
    end)

    h.test("debug view: hidden for a non-GM officer, visible for the Guild Master", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.isOfficer = true
        WowStub.rankIndex = 1 -- officer, not GM
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        local panel = SideQuest.UI.panels.Console
        h.assertTrue(not panel.subButtons["Debug"]:IsShown(), "Debug hidden for a non-GM officer")

        SideQuest.UI.main = nil
        WowStub.rankIndex = 0 -- Guild Master
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        panel = SideQuest.UI.panels.Console
        h.assertTrue(panel.subButtons["Debug"]:IsShown(), "Debug visible for the Guild Master")
    end)

    h.test("view as: only the Guild Master can turn the override on", function()
        h.resetAddon()
        WowStub.rankIndex = 1 -- officer, not GM
        local ok = SideQuest.SetViewAs("member")
        h.assertTrue(not ok, "a non-GM can't turn the override on")
        h.assertEq(SideQuest.ViewAs(), nil, "override stays off")
    end)

    h.test("view as: member preview hides officer-only parts without touching real rights", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        WowStub.isOfficer = true -- real officer (and GM, default rankIndex 0)
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        h.assertTrue(SideQuest.UI.tabButtons["Console"]:IsShown(), "Console tab visible for the real officer")

        local ok = SideQuest.SetViewAs("member")
        h.assertTrue(ok, "the GM can turn the override on")
        h.assertEq(SideQuest.ViewAs(), "member", "override reports member")
        h.assertTrue(not SideQuest.UI.tabButtons["Console"]:IsShown(), "Console tab hidden while viewing as member")
        h.assertEq(SideQuest.IsOfficer(), true, "the real officer check is unaffected by the override")
        h.assertEq(SideQuest.IsGuildMember(), true, "the real membership check is unaffected")

        SideQuest.SetViewAs(nil)
        h.assertTrue(SideQuest.UI.tabButtons["Console"]:IsShown(), "Exit restores the real view")
    end)

    h.test("view as: officer preview hides the GM-only Debug view", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        h.assertTrue(SideQuest.UI.panels.Console.subButtons["Debug"]:IsShown(), "Debug visible as the real GM")

        SideQuest.SetViewAs("officer")
        h.assertTrue(not SideQuest.UI.panels.Console.subButtons["Debug"]:IsShown(),
            "Debug hidden while viewing as a plain officer")
        h.assertTrue(SideQuest.UI.tabButtons["Console"]:IsShown(), "Console tab itself still shows for an officer preview")
        SideQuest.SetViewAs(nil)
    end)

    h.test("view as: nonmember preview rebuilds into the join pane with an Exit banner", function()
        h.resetAddon()
        SideQuest.UI.main = nil
        SideQuest.UI.joinFrame = nil
        SideQuest.UI.Show() -- real GM/member, full tabbed UI
        h.assertTrue(SideQuest.UI.main:IsShown())

        SideQuest.SetViewAs("nonmember")
        h.assertTrue(SideQuest.UI.joinFrame ~= nil and SideQuest.UI.joinFrame:IsShown(), "rebuilt into the join pane")
        h.assertTrue(not SideQuest.UI.main:IsShown(), "tabbed window hidden")
        h.assertTrue(SideQuest.UI.joinFrame.viewAsBanner:IsShown(), "join pane shows the exit banner")
        h.assertTrue(SideQuest.UI.joinFrame.viewAsBanner.label:GetText():find("Exit", 1, true) ~= nil,
            "banner names Exit: " .. SideQuest.UI.joinFrame.viewAsBanner.label:GetText())

        local onClick = SideQuest.UI.joinFrame.viewAsBanner:GetScript("OnClick")
        onClick()
        h.assertEq(SideQuest.ViewAs(), nil, "banner click clears the override")
        h.assertTrue(SideQuest.UI.main ~= nil and SideQuest.UI.main:IsShown(), "back to the real tabbed window")
    end)

    h.test("view as: /sq viewas is a GM-only fallback that always allows exit", function()
        h.resetAddon()
        WowStub.rankIndex = 1 -- not GM
        SideQuest.DispatchSlash("viewas member")
        h.assertEq(SideQuest.ViewAs(), nil, "a non-GM can't turn it on via slash either")

        WowStub.rankIndex = 0 -- GM
        SideQuest.DispatchSlash("viewas member")
        h.assertEq(SideQuest.ViewAs(), "member", "the GM can turn it on via slash")
        SideQuest.DispatchSlash("viewas off")
        h.assertEq(SideQuest.ViewAs(), nil, "off always works")
    end)

    h.test("view as: never affects what's exported, synced, or recorder rights", function()
        h.resetAddon()
        WowStub.isOfficer = true
        SideQuest.SetViewAs("nonmember")
        h.assertEq(SideQuest.IsOfficer(), true, "real officer check unaffected by the override")
        h.assertEq(SideQuest.IsGuildMember(), true, "real membership check unaffected by the override")
        local _, reason = SideQuest.Recorder.CanRecord()
        h.assertTrue(reason ~= "Only officers record raids",
            "recorder gate uses the real officer check, not the view-as override: " .. tostring(reason))
        SideQuest.SetViewAs(nil)
    end)
end
