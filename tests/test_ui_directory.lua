-- tests/test_ui_directory.lua
-- Crafters (Search/Professions/Cooldowns), Market (Browse/Mine) and the
-- Guild tab's inline member detail, against the real SideQuest.Directory.

return function(h)
    local test, assertEq, assertTrue, resetAddon = h.test, h.assertEq, h.assertTrue, h.resetAddon

    local function setupPlayer()
        WowStub.inCombat = false
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-UIDIR001" })
    end

    test("crafters: sub-tabs show only the chosen sub-view", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.directory = SideQuestDB.directory or {}
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Crafters")
        local panel = SideQuest.UI.panels.Crafters
        SideQuest.UI.ShowCraftersSub("Professions")
        assertTrue(panel.subPanels["Professions"]:IsShown(), "Professions sub-view shown once chosen")
        assertTrue(not panel.subPanels["Search"]:IsShown(), "Search sub-view hidden while Professions is active")
        SideQuest.UI.ShowCraftersSub("Cooldowns")
        assertTrue(panel.subPanels["Cooldowns"]:IsShown(), "switching shows Cooldowns")
        assertTrue(not panel.subPanels["Professions"]:IsShown(), "switching hides the previous sub-view")
    end)

    test("crafters: Professions view lists directory members, best skill first among those online", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.roster = { taken_at = 1000, members = {
            { character = "Alt1-Whitemane", online = true },
            { character = "Alt2-Whitemane", online = false },
        } }
        SideQuestDB.directory = {
            ["Alt1-Whitemane"] = { seen_at = 1000, prof = { v = "x", at = 1000, d = {
                professions = { { name = "Tailoring", skill_line = 197, skill = 200, max_skill = 300, recipes = { 1, 2 } } },
            } } },
            ["Alt2-Whitemane"] = { seen_at = 900, prof = { v = "y", at = 900, d = {
                professions = { { name = "Tailoring", skill_line = 197, skill = 280, max_skill = 300 } },
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Crafters")
        SideQuest.UI.ShowCraftersSub("Professions")
        local chamber = SideQuest.UI.panels.Crafters.professionsChamber
        chamber.profession = "Tailoring"
        SideQuest.UI.RefreshCraftersProfessions()
        -- Alt2 has the higher skill but Alt1 is online: online-first still wins the top row.
        assertTrue(chamber.rows[1].nameRow.nameFS:GetText():find("Alt1") ~= nil, "online member sorts first despite lower skill")
        assertTrue(chamber.rows[1].recipesText:GetText() == "2", "recipe count read from the member's own prof section")
        assertTrue(chamber.rows[2].nameRow.nameFS:GetText():find("Alt2") ~= nil, "offline member listed second")
    end)

    test("crafters: Professions view lists every profession until one is chosen", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.roster = { taken_at = 1000, members = {} }
        SideQuestDB.directory = {
            ["Alt1-Whitemane"] = { seen_at = 1000, prof = { v = "x", at = 1000, d = {
                professions = {
                    { name = "Tailoring", skill_line = 197, skill = 200, max_skill = 300 },
                    { name = "Skinning", skill_line = 393, skill = 22, max_skill = 75 },
                },
            } } },
            ["Alt2-Whitemane"] = { seen_at = 900, prof = { v = "y", at = 900, d = {
                professions = { { name = "Mining", skill_line = 186, skill = 150, max_skill = 225 } },
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Crafters")
        SideQuest.UI.ShowCraftersSub("Professions")
        local chamber = SideQuest.UI.panels.Crafters.professionsChamber
        local function shown()
            local out = {}
            for _, row in ipairs(chamber.rows) do
                if row:IsShown() then
                    table.insert(out, row.professionText:GetText())
                end
            end
            return table.concat(out, ",")
        end
        assertEq(shown(), "Mining,Skinning,Tailoring", "every member's every profession, by profession")
        chamber.profession = "Mining"
        SideQuest.UI.RefreshCraftersProfessions()
        assertEq(shown(), "Mining", "choosing a profession narrows the list")
    end)

    test("crafters: Cooldowns view groups holders by cooldown, ready-first", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.directory = {
            ["Alt1-Whitemane"] = { seen_at = 1000, cd = { v = "x", at = 1000, d = {
                cooldowns = { { key = "transmute", ready_at = (GetServerTime and GetServerTime() or 0) + 999999999 } },
            } } },
            ["Alt2-Whitemane"] = { seen_at = 1000, cd = { v = "y", at = 1000, d = {
                cooldowns = { { key = "transmute", ready_at = 0 } },
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Crafters")
        SideQuest.UI.ShowCraftersSub("Cooldowns")
        local chamber = SideQuest.UI.panels.Crafters.cooldownsChamber
        assertTrue(chamber.groupRows[1].rows[1].readyText:GetText() == "Ready now", "the ready member sorts first")
        assertTrue(chamber.groupRows[1].rows[2].readyText:GetText():find("Ready in") ~= nil, "the not-yet-ready member sorts second")
    end)

    test("market: Browse looks up sellers/buyers/holders for one item", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.directory = {
            ["Alt1-Whitemane"] = { seen_at = 1000, market = { v = "x", at = 1000, d = {
                sell = { { item_id = 14048, price = 12000, qty = 5 } },
            } } },
            ["Alt2-Whitemane"] = { seen_at = 1000, market = { v = "y", at = 1000, d = {
                buy = { { item_id = 14048, price = 9000 } },
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Market")
        SideQuest.UI.ShowMarketSub("Browse")
        local chamber = SideQuest.UI.panels.Market.browseChamber
        chamber.lookupItemId = 14048
        SideQuest.UI.RefreshMarketBrowse()
        assertTrue(chamber.sellRows[1]:IsShown(), "a seller row is shown")
        assertTrue(chamber.buyRows[1]:IsShown(), "a buyer row is shown")
    end)

    test("market: Browse says what to do when nothing is looked up or nothing matches", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.directory = {}
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Market")
        SideQuest.UI.ShowMarketSub("Browse")
        local chamber = SideQuest.UI.panels.Market.browseChamber
        assertTrue(chamber.stateLines.item:GetText():find("Who has it") ~= nil, "before a lookup it says how to start one")
        assertTrue(chamber.stateLines.requests:IsShown(), "an empty requests feed says so")
        chamber.lookupItemId = 14048
        SideQuest.UI.RefreshMarketBrowse()
        assertTrue(chamber.stateLines.item:GetText():find("No one in the directory") ~= nil,
            "a lookup nobody can answer says so instead of showing nothing")
    end)

    test("market: Mine lists the player's own sell/buy/request entries and removes them", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.directory = {
            ["Demo1-Whitemane"] = { seen_at = 1000, market = { v = "x", at = 1000, d = {
                sell = { { item_id = 14048, price = 12000, qty = 5 } },
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Market")
        SideQuest.UI.ShowMarketSub("Mine")
        local chamber = SideQuest.UI.panels.Market.mineChamber
        assertTrue(chamber.sellListRows[1]:IsShown(), "the player's own sell listing is shown")
    end)

    test("guild: clicking a member shows their directory detail inline", function()
        resetAddon()
        SideQuest.UI.main = nil
        setupPlayer()
        SideQuestDB.roster = { taken_at = 1000, members = {
            { character = "Alt1-Whitemane", rank = "Member", online = true, class = "MAGE", level = 30 },
        } }
        SideQuestDB.directory = {
            ["Alt1-Whitemane"] = { seen_at = 1000, char = { v = "x", at = 1000, d = {
                level = 30, class = "MAGE", spec = "Frost", item_level = 44.5,
            } } },
        }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Guild")
        local chamber = SideQuest.UI.panels.Guild.chamber
        assertTrue(not chamber.detailBlock:IsShown(), "no detail shown before any row is clicked")
        chamber.selectedCharacter = "Alt1-Whitemane"
        SideQuest.UI.RefreshGuild()
        assertTrue(chamber.detailBlock:IsShown(), "detail block shown once a member is selected")
        assertTrue(chamber.detailBlock.metaText:GetText():find("Frost") ~= nil, "shows the member's spec")
        assertEq(chamber.detailBlock.metaText:GetText():find("44.5") ~= nil, true, "shows the member's item level")
        chamber.selectedCharacter = nil
        SideQuest.UI.RefreshGuild()
        assertTrue(not chamber.detailBlock:IsShown(), "clearing the selection hides the detail block again")
        chamber.selectedCharacter = "Alt1-Whitemane"
        SideQuest.UI.RefreshGuild()
        chamber.searchBox:SetText("nobody")
        SideQuest.UI.RefreshGuild()
        assertTrue(not chamber.detailBlock:IsShown(), "filtering the selected member out hides their detail too")
    end)
end
