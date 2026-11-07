-- tests/test_updates.lua
-- Updates.lua: the in-game notice that SideQuest Companion has installed a newer SideQuest while the game runs.

return function(h)
    local Updates = SideQuest.Updates
    local MARKER = "Interface\\AddOns\\SideQuest\\Media\\Updates\\v0.10.1.ttf"

    local function reset()
        h.resetAddon()
        Updates.ready = false
        Updates.ticker = nil
        WowStub.files = { [MARKER] = false }
        WowStub.addonMetadata = { Version = "v0.10.1" }
        WowStub.activePopup = nil
        WowStub.reloads = 0
    end

    h.test("updates: nothing shows until Companion leaves the marker for the running version", function()
        reset()
        h.assertTrue(not Updates.Check(), "no marker, no notice")
        h.assertEq(WowStub.activePopup, nil, "no popup")

        WowStub.files[MARKER] = true -- Companion installed v0.10.2 over the running v0.10.1
        h.assertTrue(Updates.Check(), "marker found")
        h.assertTrue(WowStub.activePopup ~= nil, "popup shown")
        h.assertTrue(WowStub.activePopup.text:find("/reload", 1, true) ~= nil, "popup says to /reload")
        WowStub.ClickPopupButton(1)
        h.assertEq(WowStub.reloads, 1, "Reload now reloads the UI")
    end)

    h.test("updates: the version that's now running ignores the marker it was installed over", function()
        reset()
        WowStub.files[MARKER] = true
        WowStub.addonMetadata = { Version = "v0.10.2" } -- after /reload, the new version runs
        WowStub.files["Interface\\AddOns\\SideQuest\\Media\\Updates\\v0.10.2.ttf"] = false
        h.assertTrue(not Updates.Check(), "no notice for an update that's already loaded")
    end)

    h.test("updates: a development checkout never looks", function()
        reset()
        WowStub.addonMetadata = { Version = "@project-version@" }
        h.assertEq(Updates.InstalledVersion(), nil, "unpackaged toc has no version")
        h.assertTrue(not Updates.Check(), "nothing to compare against")
    end)

    h.test("updates: marker names match Companion's for any version string", function()
        h.assertEq(Updates.MarkerPath("v1.2.3-beta 1"), "Interface\\AddOns\\SideQuest\\Media\\Updates\\v1.2.3-beta_1.ttf",
            "spaces and other characters become underscores")
    end)
end
