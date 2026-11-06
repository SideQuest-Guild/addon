-- tests/test_options.lua
-- The options panel (UI/Options.lua): registers the "SideQuest Guild" category once under Options > AddOns,
-- its minimap and scale settings apply and save the way the matching /sq command does, and /sq options opens it.

return function(h)
    local function settingsList()
        local layout = SettingsPanel:GetLayout(SideQuest.UI.Options.category)
        return layout.initializers
    end

    local function findSetting(variable)
        for _, initializer in ipairs(settingsList()) do
            local setting = initializer.setting or (initializer.data and initializer.data.setting)
            if setting and setting:GetVariable() == variable then
                return setting
            end
        end
        return nil
    end

    -- Options.Register() caches its category forever, like the real game never re-registering a category on a
    -- later ADDON_LOADED; force a fresh registration bound to this test's own SideQuestDB.
    local function freshLoad()
        h.resetAddon()
        SideQuest.UI.Options.category = nil
        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
    end

    h.test("options: the category registers once under Options > AddOns", function()
        h.resetAddon()
        SideQuest.UI.Options.category = nil
        WowStub.registeredAddOnCategories = {}
        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        h.assertEq(#WowStub.registeredAddOnCategories, 1, "registered once on load")
        local category = SideQuest.UI.Options.category
        h.assertTrue(category ~= nil, "category stored")

        WowStub.FireEvent("ADDON_LOADED", "SideQuest")
        h.assertEq(#WowStub.registeredAddOnCategories, 1, "not registered again on a later ADDON_LOADED")
        h.assertEq(SideQuest.UI.Options.category, category, "same category kept")
    end)

    h.test("options: the minimap setting hides the button and saves it", function()
        freshLoad()
        local setting = findSetting("SIDEQUEST_MINIMAP_SHOWN")
        h.assertTrue(setting ~= nil, "minimap setting registered")
        h.assertEq(setting:GetValue(), true, "shown by default")

        setting:SetValue(false)
        h.assertTrue(SideQuestDB.ui.minimap.hide, "hidden state saved")
        h.assertTrue(not SideQuest.UI.MinimapButton.button:IsShown(), "button actually hidden")

        setting:SetValue(true)
        h.assertTrue(not SideQuestDB.ui.minimap.hide, "shown state saved")
        h.assertTrue(SideQuest.UI.MinimapButton.button:IsShown(), "button shown again")
    end)

    h.test("options: the minimap row's button opens the SideQuest window", function()
        freshLoad()
        if SideQuest.UI.main then SideQuest.UI.main:Hide() end
        local initializer = nil
        for _, candidate in ipairs(settingsList()) do
            if candidate.data and candidate.data.OnButtonClick then
                initializer = candidate
                break
            end
        end
        h.assertTrue(initializer ~= nil, "minimap row has a button")
        initializer.data.OnButtonClick()
        h.assertTrue(SideQuest.UI.main ~= nil and SideQuest.UI.main:IsShown(), "button opens the window")
    end)

    h.test("options: the scale setting applies and saves", function()
        freshLoad()
        SideQuest.UI.Toggle() -- builds the window so applying the scale has a frame to apply to
        local setting = findSetting("SIDEQUEST_WINDOW_SCALE")
        h.assertTrue(setting ~= nil, "scale setting registered")
        h.assertEq(setting:GetValue(), 1.25, "default scale matches /sq scale's own default")

        setting:SetValue(1.5)
        h.assertEq(SideQuestDB.ui.scale, 1.5, "scale saved")
        h.assertEq(SideQuest.UI.main:GetScale(), 1.5, "window scale applied")
    end)

    h.test("options: reduce motion and sharing checkboxes bind to the saved settings", function()
        freshLoad()
        local motion = findSetting("SIDEQUEST_REDUCE_MOTION")
        h.assertEq(motion:GetValue(), false, "off by default")
        motion:SetValue(true)
        h.assertTrue(SideQuestDB.settings.reduceMotion, "reduce motion saved")

        local prof = findSetting("SIDEQUEST_SHARE_PROF")
        h.assertEq(prof:GetValue(), true, "shared by default")
        prof:SetValue(false)
        h.assertTrue(not SideQuestDB.settings.share.prof, "share.prof saved")
    end)

    h.test("options: /sq options (and /sq settings) opens the registered category", function()
        freshLoad()
        WowStub.openedSettingsCategoryID = nil
        SideQuest.DispatchSlash("options")
        h.assertEq(WowStub.openedSettingsCategoryID, SideQuest.UI.Options.category:GetID(),
            "/sq options opens the category")

        WowStub.openedSettingsCategoryID = nil
        SideQuest.DispatchSlash("settings")
        h.assertEq(WowStub.openedSettingsCategoryID, SideQuest.UI.Options.category:GetID(),
            "/sq settings opens the same category")
    end)
end
