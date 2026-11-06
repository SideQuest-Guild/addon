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

    h.test("minimap button: LibDBIcon draws it as 'SideQuest', so button collectors list it by name", function()
        h.resetAddon()
        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        local DBIcon = LibStub("LibDBIcon-1.0")
        h.assertTrue(DBIcon:IsRegistered("SideQuest"), "registered with LibDBIcon")
        h.assertEq(button(), DBIcon:GetMinimapButton("SideQuest"), "the button is LibDBIcon's")
        h.assertEq(LibStub("LibDataBroker-1.1"):GetDataObjectByName("SideQuest").type, "launcher", "a broker launcher")
    end)

    h.test("minimap button: a save that kept its position as `angle` keeps it as LibDBIcon's `minimapPos`", function()
        SideQuestDB = SideQuest.defaultDB()
        SideQuestDB.version = 1
        SideQuestDB.ui.minimap = { hide = false, angle = 45 }
        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        h.assertEq(SideQuestDB.ui.minimap.minimapPos, 45, "position carried over")
        h.assertEq(SideQuestDB.ui.minimap.angle, nil, "old key removed")
    end)
end
