-- tests/test_minimap.lua
-- The minimap button: shown on first login, /sq minimap hides it for good, a click opens the window.

return function(h)
    local function button()
        return SideQuest.UI.MinimapButton.button
    end

    h.test("minimap button: shown by default; /sq minimap hides it, remembers, and shows it again", function()
        h.resetAddon()
        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        h.assertTrue(button() ~= nil, "button built at load")
        h.assertTrue(button():IsShown(), "shown on a fresh save")

        SideQuest.DispatchSlash("minimap")
        h.assertTrue(not button():IsShown(), "hidden after /sq minimap")
        h.assertTrue(SideQuestDB.ui.minimap.hide, "hidden state saved")

        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        h.assertTrue(not button():IsShown(), "stays hidden after a reload")

        SideQuest.DispatchSlash("minimap")
        h.assertTrue(button():IsShown(), "shown again after a second /sq minimap")
    end)

    h.test("minimap button: a save from before the button gets it shown", function()
        SideQuestDB = SideQuest.defaultDB()
        SideQuestDB.ui = { tab = "Ledger" }
        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        h.assertEq(SideQuestDB.ui.tab, "Ledger", "existing ui settings kept")
        h.assertTrue(button():IsShown(), "older save shows the button")
    end)

    h.test("minimap button: clicking it opens the window, clicking again closes it", function()
        h.resetAddon()
        WowStub.inCombat = false
        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        if SideQuest.UI.main then SideQuest.UI.main:Hide() end

        button():GetScript("OnClick")(button(), "LeftButton")
        h.assertTrue(SideQuest.UI.main ~= nil and SideQuest.UI.main:IsShown(), "click opens the window")

        button():GetScript("OnClick")(button(), "LeftButton")
        h.assertTrue(not SideQuest.UI.main:IsShown(), "second click closes it")
    end)
end
