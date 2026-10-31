-- tests/test_directory.lua
-- The guild directory: hashing, store/receive rules, DIR_* messaging, pruning, lookups, the prof/char/
-- market/stock collectors, and the export's directory/item_names/recipe_names fields. See docs/directory.md.

return function(h)
    local function fixturesDir()
        local src = debug.getinfo(1, "S").source
        local here = src:match("@(.*/)") or "./"
        return here .. "fixtures/"
    end

    local function sawMessageType(prefix)
        for _, m in ipairs(WowStub.addonMessages) do
            if m.message:find("^" .. prefix) then
                return true
            end
        end
        return false
    end

    local function countMessageType(prefix)
        local n = 0
        for _, m in ipairs(WowStub.addonMessages) do
            if m.message:find("^" .. prefix) then
                n = n + 1
            end
        end
        return n
    end

    --------------------------------------------------------------------------
    -- Hashing
    --------------------------------------------------------------------------

    h.test("directory: Hash is deterministic regardless of key order", function()
        h.resetAddon()
        local a = { b = 1, a = 2 }
        local b = { a = 2, b = 1 }
        h.assertEq(SideQuest.Directory.Hash(a), SideQuest.Directory.Hash(b), "same data, same hash")
        h.assertTrue(SideQuest.Directory.Hash(a) ~= SideQuest.Directory.Hash({ a = 2, b = 3 }), "different data, different hash")
        h.assertEq(#SideQuest.Directory.Hash(nil), 8, "hash is 8 hex chars, even for a tombstone (nil)")
    end)

    --------------------------------------------------------------------------
    -- SetMine + tombstones
    --------------------------------------------------------------------------

    h.test("directory: SetMine stores a section and announces DIR_V; off settings tombstone it", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Smith", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
        local character = "Smith-Whitemane"

        local d = { professions = { { name = "Blacksmithing", skill_line = 164, skill = 150, max_skill = 300 } } }
        SideQuest.Directory.SetMine("prof", d)
        local stored = SideQuest.Directory.Section(character, "prof")
        h.assertTrue(stored ~= nil, "section stored")
        h.assertEq(stored.professions[1].name, "Blacksmithing", "profession name stored")
        h.assertTrue(sawMessageType("DIR_V"), "a DIR_V announce was sent")

        WowStub.addonMessages = {}
        local before = SideQuest.Directory.Get(character).prof.v
        SideQuest.Directory.SetMine("prof", d)
        h.assertEq(SideQuest.Directory.Get(character).prof.v, before, "identical data keeps the same hash")
        h.assertEq(#WowStub.addonMessages, 0, "no new announce when the hash didn't change")

        SideQuestDB.settings.share.prof = false
        SideQuest.Directory.SetMine("prof", d)
        h.assertEq(SideQuest.Directory.Section(character, "prof"), nil, "tombstoned (d=nil) once sharing is off")
        h.assertTrue(SideQuest.Directory.Get(character).prof ~= nil, "the section row still exists as a tombstone")
    end)

    --------------------------------------------------------------------------
    -- Receiving: newest `at` wins, hash must match, relayed is local-only
    --------------------------------------------------------------------------

    h.test("directory: DIR_R keeps the newest `at`, drops hash mismatches, flags relayed", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        local character = "Other-Whitemane"

        local d1 = { level = 60, class = "MAGE" }
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_R",
            SideQuestJSON.encode({ c = character, s = "char", v = SideQuest.Directory.Hash(d1), at = 100, d = d1 }),
            "Relay-Whitemane")
        local sec = SideQuest.Directory.Get(character).char
        h.assertEq(sec.at, 100, "first receive stored")
        h.assertTrue(sec.relayed, "relayed is true when the sender isn't the owner")

        local d0 = { level = 59, class = "MAGE" }
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_R",
            SideQuestJSON.encode({ c = character, s = "char", v = SideQuest.Directory.Hash(d0), at = 50, d = d0 }),
            "Relay-Whitemane")
        h.assertEq(SideQuest.Directory.Section(character, "char").level, 60, "an older `at` is ignored")

        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_R",
            SideQuestJSON.encode({ c = character, s = "char", v = "deadbeef", at = 200, d = { level = 61 } }),
            "Relay-Whitemane")
        h.assertEq(SideQuest.Directory.Section(character, "char").level, 60, "a hash mismatch is dropped")

        local d2 = { level = 61, class = "MAGE" }
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_R",
            SideQuestJSON.encode({ c = character, s = "char", v = SideQuest.Directory.Hash(d2), at = 300, d = d2 }),
            character)
        local sec2 = SideQuest.Directory.Get(character).char
        h.assertEq(sec2.at, 300, "a newer `at` is stored")
        h.assertTrue(not sec2.relayed, "relayed is false when the sender is the owner")
    end)

    --------------------------------------------------------------------------
    -- DIR_Q / DIR_R: self-answer, rate limit, relayer suppression
    --------------------------------------------------------------------------

    h.test("directory: a DIR_Q for my own section is answered at once, then rate-limited for 30s", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Smith", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
        SideQuest.Directory.SetMine("prof", { professions = { { name = "Blacksmithing", skill = 150, max_skill = 300 } } })
        WowStub.addonMessages = {}

        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_Q", SideQuestJSON.encode({ c = "Smith-Whitemane", s = { "prof" } }), "Asker-Whitemane")
        h.assertTrue(sawMessageType("DIR_R"), "the owner answers its own DIR_Q at once")

        WowStub.addonMessages = {}
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_Q", SideQuestJSON.encode({ c = "Smith-Whitemane", s = { "prof" } }), "Asker2-Whitemane")
        h.assertTrue(not sawMessageType("DIR_R"), "a second DIR_Q within 30s is not answered again")

        WowStub.Advance(31)
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_Q", SideQuestJSON.encode({ c = "Smith-Whitemane", s = { "prof" } }), "Asker3-Whitemane")
        h.assertTrue(sawMessageType("DIR_R"), "answers again once the 30s rate limit has passed")
    end)

    h.test("directory: a relayer stays quiet once an answer for that character+section was already seen", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Relay", realm = "Whitemane", class = "PRIEST", guid = "Player-1-RRRR0001" })
        local character = "Smith-Whitemane"
        local d = { professions = { { name = "Blacksmithing", skill = 150, max_skill = 300 } } }
        local v = SideQuest.Directory.Hash(d)

        -- this client holds a relayed copy of Smith's prof section...
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_R", SideQuestJSON.encode({ c = character, s = "prof", v = v, at = 100, d = d }), "SomeoneElse-Whitemane")
        -- ...but the owner's own answer already went out first.
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_R", SideQuestJSON.encode({ c = character, s = "prof", v = v, at = 100, d = d }), character)
        WowStub.addonMessages = {}

        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_Q", SideQuestJSON.encode({ c = character, s = { "prof" } }), "Asker-Whitemane")
        h.assertTrue(not sawMessageType("DIR_R"), "the relayer never answers once the owner's answer was already seen")
    end)

    --------------------------------------------------------------------------
    -- DIR_LQ / DIR_L: login catch-up, batched at 10 characters
    --------------------------------------------------------------------------

    h.test("directory: DIR_LQ is answered with a DIR_L of this client's known hashes", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Smith", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
        SideQuest.Directory.SetMine("prof", { professions = { { name = "Mining", skill = 100, max_skill = 300 } } })
        WowStub.addonMessages = {}

        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_LQ", SideQuestJSON.encode({ id = "lq-1" }), "NewLogin-Whitemane")
        h.assertTrue(sawMessageType("DIR_L"), "answered the catch-up request")
    end)

    h.test("directory: DIR_L queries every stale/missing character, rate-limited per character+section after", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Me", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
        local e = {}
        for i = 1, 12 do
            e["Char" .. i .. "-Whitemane"] = { prof = "aaaaaaaa" }
        end
        WowStub.addonMessages = {}
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_L", SideQuestJSON.encode({ id = "l-1", e = e }), "Someone-Whitemane")
        -- the catch-up queue processes in batches of 10, the next batch firing once the first's
        -- answers arrive or after 60s; under the test harness's synchronous timer both batches run
        -- immediately, so every stale character ends up queried.
        h.assertEq(countMessageType("DIR_Q"), 12, "every stale character is queried across the batches")

        WowStub.addonMessages = {}
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_L", SideQuestJSON.encode({ id = "l-2", e = e }), "Someone-Whitemane")
        h.assertEq(countMessageType("DIR_Q"), 0, "re-asking the same character+section within 30s is rate-limited")
    end)

    --------------------------------------------------------------------------
    -- Pruning
    --------------------------------------------------------------------------

    h.test("directory: Prune drops characters outside a known roster and anything stale for 90+ days", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        SideQuestDB.directory["Gone-Whitemane"] = { char = { v = "x", at = 1, d = {} }, seen_at = WowStub.time }
        SideQuestDB.directory["Stale-Whitemane"] = { char = { v = "x", at = 1, d = {} }, seen_at = WowStub.time - (91 * 24 * 3600) }
        SideQuestDB.directory["Current-Whitemane"] = { char = { v = "x", at = 1, d = {} }, seen_at = WowStub.time }
        WowStub.guildRoster = {
            { name = "Current", rank = "Member", rankIndex = 3, level = 60, class = "MAGE", classFile = "MAGE", zone = "IF", online = true },
        }
        SideQuest.Roster.Sweep()
        h.assertEq(SideQuestDB.directory["Gone-Whitemane"], nil, "pruned: not in the known roster")
        h.assertEq(SideQuestDB.directory["Stale-Whitemane"], nil, "pruned: stale for 90+ days")
        h.assertTrue(SideQuestDB.directory["Current-Whitemane"] ~= nil, "kept: in the roster and recent")
    end)

    --------------------------------------------------------------------------
    -- Lookups
    --------------------------------------------------------------------------

    h.test("directory lookups: WhoCrafts, ByProfession, WhoHas, WhoSells, WhoBuys, Requests, Cooldowns", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.spellNames = { [18560] = "Mooncloth" }
        SideQuestDB.directory["A-Whitemane"] = {
            prof = { v = "x", at = 1, d = { professions = { { name = "Tailoring", skill = 285, max_skill = 300, recipes = { 18560 } } } } },
            stock = { v = "x", at = 1, d = { bags = { { 14048, 20 } }, bank = {} } },
            market = { v = "x", at = 1, d = {
                sell = { { item_id = 14048, price = 12000, qty = 20 } },
                buy = { { item_id = 12360, price = 35000 } },
                requests = { { id = "A-Whitemane-1", item_id = 12360, qty = 4, price = 35000, note = "test", at = 100 } },
            } },
            cd = { v = "x", at = 1, d = { cooldowns = { { key = "transmute", ready_at = 0 } } } },
            seen_at = WowStub.time,
        }
        SideQuestDB.directory["B-Whitemane"] = {
            prof = { v = "x", at = 1, d = { professions = { { name = "Tailoring", skill = 150, max_skill = 300 } } } },
            seen_at = WowStub.time,
        }

        local crafts = SideQuest.Directory.WhoCrafts("mooncloth")
        h.assertEq(#crafts, 1, "finds the recipe by name")
        h.assertEq(crafts[1].character, "A-Whitemane", "correct crafter")

        local byProf = SideQuest.Directory.ByProfession("Tailoring")
        h.assertEq(#byProf, 2, "both tailors found")
        h.assertEq(byProf[1].character, "A-Whitemane", "higher skill first")

        local whoHas = SideQuest.Directory.WhoHas(14048)
        h.assertEq(#whoHas, 1, "stock lookup finds the item")
        h.assertEq(whoHas[1].bags, 20, "bag count correct")

        local sellers = SideQuest.Directory.WhoSells(14048)
        h.assertEq(#sellers, 1, "sell lookup")
        h.assertEq(sellers[1].price, 12000, "sell price correct")

        local buyers = SideQuest.Directory.WhoBuys(12360)
        h.assertEq(#buyers, 1, "buy lookup")

        local requests = SideQuest.Directory.Requests()
        h.assertEq(#requests, 1, "requests lookup")
        h.assertEq(requests[1].note, "test", "request note correct")

        local cds = SideQuest.Directory.Cooldowns("transmute")
        h.assertEq(#cds, 1, "cooldown lookup")
        h.assertEq(cds[1].ready_at, 0, "ready now")
    end)

    --------------------------------------------------------------------------
    -- Market: price parsing/formatting
    --------------------------------------------------------------------------

    h.test("market: price parsing handles g/s/c tokens and plain gold decimals", function()
        h.resetAddon()
        h.assertEq(SideQuest.Market.ParsePrice("1g20s"), 12000, "1g20s")
        h.assertEq(SideQuest.Market.ParsePrice("35s"), 3500, "35s")
        h.assertEq(SideQuest.Market.ParsePrice("80c"), 80, "80c")
        h.assertEq(SideQuest.Market.ParsePrice("1.5"), 15000, "1.5 (gold, decimal)")
        h.assertEq(SideQuest.Market.ParsePrice(nil), nil, "nil input")
        h.assertEq(SideQuest.Market.ParsePrice(""), nil, "empty input")
        h.assertEq(SideQuest.Market.FormatPrice(nil), "whisper me", "nil price displays as whisper me")
        h.assertEq(SideQuest.Market.FormatPrice(12000), "1g 20s", "format back to gsc")
        h.assertEq(SideQuest.Market.FormatPrice(0), "0c", "zero still shows a value")
    end)

    h.test("market: commands take a shift-clicked link (which has spaces), a quoted name or an ID", function()
        h.resetAddon()
        local M = SideQuest.Market
        local item, rest = M.SplitItem("|cff1eff00|Hitem:14048::::::::60:::::|h[Bolt of Runecloth]|h|r 1g20s 20")
        h.assertEq(M.ParseItemArg(item), 14048, "the item ID comes out of the link")
        h.assertEq(rest, "1g20s 20", "price and quantity after the link are left for the command")
        item, rest = M.SplitItem('"Arcanite Bar" 3g 2')
        h.assertEq(item, "Arcanite Bar", "a quoted name is one argument")
        h.assertEq(rest, "3g 2", "the rest after a quoted name")
        item, rest = M.SplitItem("12360 35s")
        h.assertEq(M.ParseItemArg(item), 12360, "a bare ID")
        h.assertEq(rest, "35s", "the rest after an ID")
    end)

    h.test("market: sell/buy/request editing publishes to the directory and respects settings.share", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Trader", realm = "Whitemane", class = "GNOME", guid = "Player-1-TTTT0001" })

        SideQuest.Market.SetSell(14048, 12000, 20, false)
        SideQuest.Market.SetBuy(12360, 35000)
        local id = SideQuest.Market.AddRequest(12360, 4, 35000, "for Arcanite Reaper")

        local market = SideQuest.Directory.Section("Trader-Whitemane", "market")
        h.assertEq(#market.sell, 1, "sell listing published")
        h.assertEq(#market.buy, 1, "buy offer published")
        h.assertEq(#market.requests, 1, "request published")
        h.assertEq(market.requests[1].id, id, "request id matches what AddRequest returned")

        SideQuest.Market.RemoveRequest(id)
        market = SideQuest.Directory.Section("Trader-Whitemane", "market")
        h.assertEq(#market.requests, 0, "request removed")

        SideQuestDB.settings.share.market = false
        SideQuest.Market.SetSell(14048, 11000)
        h.assertEq(SideQuest.Directory.Section("Trader-Whitemane", "market"), nil, "tombstoned once market sharing is off")
        h.assertEq(#SideQuestDB.market.sell, 1, "the player's own local copy is unaffected by the tombstone")
    end)

    --------------------------------------------------------------------------
    -- Character collector: char + cd
    --------------------------------------------------------------------------

    h.test("character collector: char + cd sections read from game state", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Hero", realm = "Whitemane", class = "WARRIOR", race = "Human", guid = "Player-1-HHHH0001", level = 60 })
        WowStub.avgItemLevelEquipped = 61.44
        WowStub.spec = { index = 1, name = "Arms" }
        WowStub.quests[6502] = true
        WowStub.reputations[529] = { reaction = 6, currentStanding = 4200 }
        WowStub.knownSpells[17187] = true
        -- cast an hour ago on the client's uptime clock, two-day cooldown
        WowStub.spellCooldowns[17187] = { startTime = GetTime() - 3600, duration = 172800 }

        local char = SideQuest.Character.CollectChar()
        h.assertEq(char.level, 60, "level")
        h.assertEq(char.class, "WARRIOR", "class")
        h.assertEq(char.race, "Human", "race")
        h.assertEq(char.spec, "Arms", "spec")
        h.assertEq(char.item_level, 61.4, "item level rounds to one decimal")
        h.assertEq(#char.attunements, 1, "onyxia attunement detected from the quest flag")
        h.assertEq(char.attunements[1], "onyxia", "onyxia key")
        h.assertEq(#char.reputations, 1, "tracked reputation present")
        h.assertEq(char.reputations[1].faction_id, 529, "faction id")
        h.assertEq(char.reputations[1].value, 4200, "reputation value")

        local cd = SideQuest.Character.CollectCooldowns()
        h.assertEq(#cd.cooldowns, 1, "the known transmute cooldown is reported")
        h.assertEq(cd.cooldowns[1].key, "transmute", "cooldown key")
        local expected = math.ceil((WowStub.time + 172800 - 3600) / 60) * 60
        h.assertEq(cd.cooldowns[1].ready_at, expected, "ready_at is server time, rounded up to the minute")
        WowStub.Advance(5)
        h.assertEq(SideQuest.Character.CollectCooldowns().cooldowns[1].ready_at, expected,
            "a rescan seconds later gives the same ready_at, so the section hash doesn't churn")
        WowStub.spellCooldowns[17187] = { startTime = GetTime(), duration = 1.5 }
        h.assertEq(SideQuest.Character.CollectCooldowns().cooldowns[1].ready_at, 0, "the global cooldown is not a craft cooldown")
        WowStub.spellCooldowns[17187] = { startTime = GetTime() - 172801, duration = 172800 }
        h.assertEq(SideQuest.Character.CollectCooldowns().cooldowns[1].ready_at, 0, "an expired cooldown is ready")
    end)

    --------------------------------------------------------------------------
    -- Professions collector: passive scan, recipe scan, merge, guild seed
    --------------------------------------------------------------------------

    h.test("professions: passive scan + recipe scan on window open, recipes kept across passive rescans", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Smith", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-SSSS0001" })
        WowStub.professions = {
            { name = "Blacksmithing", skillLine = 164, skill = 150, maxSkill = 300 },
            { name = "Mining", skillLine = 186, skill = 200, maxSkill = 300 },
        }
        SideQuest.Professions.ScanPassive()
        local prof = SideQuest.Directory.Section("Smith-Whitemane", "prof")
        h.assertEq(#prof.professions, 2, "both professions scanned")

        WowStub.openTradeSkill = {
            professionID = 1, skillLineID = 164, professionName = "Blacksmithing",
            skillLevel = 150, maxSkillLevel = 300,
            recipes = {
                { id = 2662, name = "Copper Chain Pants", learned = true, previewItemID = 2852 },
                { id = 9999, name = "Unlearned Thing", learned = false },
            },
        }
        SideQuest.Professions.ScanOpenWindow()
        prof = SideQuest.Directory.Section("Smith-Whitemane", "prof")
        local function findProf(name)
            for _, p in ipairs(prof.professions) do
                if p.name == name then
                    return p
                end
            end
        end
        local bs = findProf("Blacksmithing")
        h.assertEq(#bs.recipes, 1, "only the learned recipe is kept")
        h.assertEq(bs.recipes[1], 2662, "recipe stored as a plain spell id")

        WowStub.professions[1].skill = 151
        SideQuest.Professions.ScanPassive()
        prof = SideQuest.Directory.Section("Smith-Whitemane", "prof")
        bs = findProf("Blacksmithing")
        h.assertEq(bs.skill, 151, "skill updated by the passive rescan")
        h.assertEq(#bs.recipes, 1, "recipes preserved across a passive-only rescan")

        h.assertTrue(SideQuestDB.professions["Smith-Whitemane|Blacksmithing"] ~= nil, "legacy per-character row kept")
        local foundLegacy = false
        for _, row in ipairs(SideQuestDB.pending.professions) do
            if row.profession == "Blacksmithing" then
                foundLegacy = true
            end
        end
        h.assertTrue(foundLegacy, "legacy pending.professions still queued for older sites")
    end)

    h.test("professions: a linked or guild trade skill window is never scanned", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Smith", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-SSSS0001" })
        WowStub.openTradeSkill = {
            professionID = 1, skillLineID = 164, professionName = "Blacksmithing",
            skillLevel = 150, maxSkillLevel = 300, linked = true,
            recipes = { { id = 2662, name = "Copper Chain Pants", learned = true } },
        }
        local row = SideQuest.Professions.ScanOpenWindow()
        h.assertEq(row, nil, "a linked trade skill window is skipped")
    end)

    h.test("professions: native guild profession seed for non-SideQuest members, officer-only, hourly, never overwrites the owner", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer", realm = "Whitemane", class = "PRIEST", guid = "Player-1-OOOO0001" })
        WowStub.guildTradeSkillsEnabled = true
        WowStub.guildTradeSkills = { { name = "Tailoring", playerName = "Weaver", curSkill = 200, maxSkill = 300 } }

        SideQuest.Professions.SeedFromGuild()
        local entry = SideQuest.Directory.Get("Weaver-Whitemane")
        h.assertTrue(entry ~= nil and entry.prof ~= nil, "seeded a prof section for the non-addon member")
        h.assertTrue(entry.prof.relayed, "the seeded section is marked relayed")
        h.assertEq(entry.prof.d.professions[1].skill, 200, "skill taken from the guild profession list")

        WowStub.guildTradeSkills[1].curSkill = 250
        SideQuest.Professions.SeedFromGuild()
        entry = SideQuest.Directory.Get("Weaver-Whitemane")
        h.assertEq(entry.prof.d.professions[1].skill, 200, "throttled: no reseed within the hour")

        WowStub.Advance(3601)
        SideQuestDB.directory["Weaver-Whitemane"].prof.relayed = false -- simulate the owner's own section arriving
        SideQuest.Professions.SeedFromGuild()
        h.assertTrue(not SideQuestDB.directory["Weaver-Whitemane"].prof.relayed, "never overwrites a section its owner sent")
    end)

    --------------------------------------------------------------------------
    -- Stock collector
    --------------------------------------------------------------------------

    h.test("stock: counts trade goods/reagents plus anything in market.sell, bags and bank publish separately", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Packrat", realm = "Whitemane", class = "ROGUE", guid = "Player-1-PPPP0001" })
        WowStub.items = {
            [14048] = { classID = 7, name = "Runecloth" }, -- Trade Goods: always tracked
            [6948] = { classID = 15, name = "Hearthstone" }, -- not tracked, unless being sold
        }
        SideQuestDB.market = { sell = { { item_id = 6948, price = 100 } }, buy = {}, requests = {} }
        WowStub.containers = {
            [0] = { { itemID = 14048, stackCount = 20 }, { itemID = 6948, stackCount = 1 } },
        }

        local bags = SideQuest.Stock.CollectBags()
        h.assertEq(#bags, 2, "trade goods and the sold hearthstone are both counted")

        SideQuest.Stock.ScanBags()
        local stock = SideQuest.Directory.Section("Packrat-Whitemane", "stock")
        h.assertEq(#stock.bags, 2, "bags published to the directory")

        WowStub.containers[-1] = { { itemID = 14048, stackCount = 40 } }
        SideQuest.Stock.ScanBank()
        stock = SideQuest.Directory.Section("Packrat-Whitemane", "stock")
        h.assertEq(#stock.bank, 1, "bank published")
        h.assertEq(stock.bank_at, WowStub.time, "bank_at recorded at scan time")
    end)

    --------------------------------------------------------------------------
    -- Export shape: directory + item_names + recipe_names
    --------------------------------------------------------------------------

    h.test("export v2: directory + item_names + recipe_names match the contract shape", function()
        h.resetAddon()
        WowStub.realm = "Whitemane"
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer", realm = "Whitemane", class = "PRIEST", guid = "Player-1-OOOO0002" })
        WowStub.items = { [14048] = { name = "Runecloth", classID = 7 } }
        WowStub.spellNames = { [18560] = "Mooncloth" }

        local profData = { professions = { { name = "Tailoring", skill = 285, max_skill = 300, recipes = { 18560 } } } }
        local stockData = { bags = { { 14048, 5 } }, bank = {} }
        SideQuestDB.directory["Tailor-Whitemane"] = {
            prof = { v = SideQuest.Directory.Hash(profData), at = 1793450000, d = profData },
            stock = { v = SideQuest.Directory.Hash(stockData), at = 1793450050, d = stockData },
            seen_at = WowStub.time,
        }
        SideQuestDB.directory["Other-Whitemane"] = {
            market = { v = SideQuest.Directory.Hash(nil), at = 1793450100, d = nil }, -- a tombstone
            seen_at = WowStub.time,
        }

        local str = SideQuest.Sync.BuildExport()
        local decoded = SideQuest.Codec.DecodeExport(str)
        h.assertEq(decoded.v, 2, "export v2")
        h.assertEq(#decoded.directory, 2, "both characters present")

        local function findChar(character)
            for _, row in ipairs(decoded.directory) do
                if row.character == character then
                    return row
                end
            end
        end
        local tailor = findChar("Tailor-Whitemane")
        local other = findChar("Other-Whitemane")
        h.assertTrue(tailor ~= nil, "tailor row present")
        h.assertEq(tailor.sections.prof.d.professions[1].name, "Tailoring", "prof section carried through")
        h.assertTrue(other ~= nil, "other row present")
        h.assertTrue(other.sections.market.d == nil, "a tombstoned section has no d")
        h.assertEq(decoded.item_names["14048"], "Runecloth", "item name resolved from stock")
        h.assertEq(decoded.recipe_names["18560"], "Mooncloth", "recipe name resolved from prof")

        local fixturePath = fixturesDir() .. "export_v2_directory.txt"
        local fh = io.open(fixturePath, "w")
        fh:write(str)
        fh:close()
    end)
end
