-- tests/test_identity.lua
-- Forever has no realms: a character is "First Surname" (UnitName(unit)
-- returns the two parts separately; GetGuildRosterInfo, CHAT_MSG_ADDON
-- senders, GetGuildTradeSkillInfo and typed-in text all hand back one
-- joined string instead). SQ.CanonicalName folds every shape the game
-- hands the addon into the one key it stores and compares everywhere.

return function(h)
    local test, assertTrue, assertEq, resetAddon = h.test, h.assertTrue, h.assertEq, h.resetAddon

    --------------------------------------------------------------------------
    -- CanonicalName
    --------------------------------------------------------------------------

    test("CanonicalName: Forever's space form, link form, and a stray trailing realm all link the same", function()
        resetAddon()
        WowStub.SetForever(true)
        assertEq(SideQuest.CanonicalName("Legs Behindhead"), "Legs-Behindhead", "space form links")
        assertEq(SideQuest.CanonicalName("Legs-Behindhead"), "Legs-Behindhead", "already-linked form is unchanged")
        assertEq(SideQuest.CanonicalName("Legs Behindhead-ShatteredHalls"), "Legs-Behindhead",
            "a trailing realm an old call site appended is dropped")
        assertEq(SideQuest.CanonicalName("Legs-Behindhead-ShatteredHalls"), "Legs-Behindhead",
            "a trailing realm on the already-linked form is dropped")
        assertEq(SideQuest.CanonicalName("Legs", "Behindhead"), "Legs-Behindhead",
            "a true (name, surname) pair from UnitName(unit) links")
    end)

    test("CanonicalName: secret and empty names canonicalize to nil", function()
        resetAddon()
        WowStub.SetForever(true)
        assertEq(SideQuest.CanonicalName(WowStub.SECRET), nil, "a secret name canonicalizes to nil")
        assertEq(SideQuest.CanonicalName(nil), nil, "nil stays nil")
        assertEq(SideQuest.CanonicalName(""), nil, "empty stays nil")
    end)

    test("CanonicalName: non-Forever clients keep the old Name-Realm behavior", function()
        resetAddon()
        WowStub.SetForever(false)
        WowStub.realm = "Whitemane"
        assertEq(SideQuest.CanonicalName("Bob"), "Bob-Whitemane", "a bare name gets this realm appended")
        assertEq(SideQuest.CanonicalName("Bob-Other"), "Bob-Other", "an explicit realm is kept as-is")
        assertEq(SideQuest.NormalizeName("Bob"), "Bob-Whitemane", "NormalizeName is the same function as CanonicalName")
    end)

    --------------------------------------------------------------------------
    -- Roster.Sweep
    --------------------------------------------------------------------------

    test("roster: Forever's space-separated GetGuildRosterInfo names key members as First-Surname", function()
        resetAddon()
        WowStub.SetForever(true)
        WowStub.guildRoster = {
            { name = "Legs Behindhead", rank = "Member", rankIndex = 3, level = 60, class = "WARRIOR",
                classFile = "WARRIOR", zone = "Ironforge", online = true },
        }
        local snapshot = SideQuest.Roster.Sweep()
        assertEq(snapshot.members[1].character, "Legs-Behindhead",
            "the space-separated roster name links to the same key SQ.NormalizeUnit produces for the player")
    end)

    --------------------------------------------------------------------------
    -- Directory.Prune: own record + partial-sweep safety
    --------------------------------------------------------------------------

    test("directory: Prune never deletes the player's own record, even when stale or not in the roster", function()
        resetAddon()
        WowStub.SetForever(true)
        WowStub.SetUnit("player", { name = "Legs", realm = "Behindhead", class = "WARRIOR", guid = "Player-1-GROW001" })
        WowStub.guildRoster = {
            { name = "Legs Behindhead", rank = "Member", rankIndex = 3, level = 60, class = "WARRIOR",
                classFile = "WARRIOR", zone = "", online = true },
            { name = "Peer One", rank = "Member", rankIndex = 3, level = 60, class = "MAGE",
                classFile = "MAGE", zone = "", online = true },
        }
        SideQuest.Roster.Sweep()
        local me = SideQuest.NormalizeUnit("player")
        assertEq(me, "Legs-Behindhead", "the player's own canonical identity")

        SideQuestDB.directory[me] = { seen_at = 1 } -- ancient: would normally be pruned as too old
        SideQuestDB.directory["Peer-One"] = { seen_at = WowStub.time }
        SideQuestDB.directory["Gone-Away"] = { seen_at = WowStub.time }
        SideQuest.Directory.Prune()

        assertTrue(SideQuestDB.directory[me] ~= nil, "the player's own record survives even though it's ancient")
        assertTrue(SideQuestDB.directory["Peer-One"] ~= nil, "a peer still in the roster survives")
        assertTrue(SideQuestDB.directory["Gone-Away"] == nil, "a character no longer in the roster is pruned")
    end)

    test("directory: Prune skips roster-based removal when the sweep is a partial subset of the guild", function()
        resetAddon()
        WowStub.guildRoster = {
            { name = "Online1-Whitemane", rank = "Member", rankIndex = 3, level = 60, class = "MAGE",
                classFile = "MAGE", zone = "", online = true },
        }
        SideQuest.Roster.Sweep()
        -- Simulate "Show Offline" off: GetNumGuildMembers still reports the
        -- whole guild even though the sweep only indexed the one online member.
        local saved = GetNumGuildMembers
        GetNumGuildMembers = function() return 5 end
        SideQuestDB.directory["Offline-Whitemane"] = { seen_at = WowStub.time }
        SideQuest.Directory.Prune()
        GetNumGuildMembers = saved
        assertTrue(SideQuestDB.directory["Offline-Whitemane"] ~= nil,
            "an offline member missing from the partial sweep is not treated as 'left the guild'")
    end)

    --------------------------------------------------------------------------
    -- Comm: a sender's own Forever-style name must match its own `c` key
    --------------------------------------------------------------------------

    test("directory: a DIR_R from the owner's own Forever space-form sender is never flagged relayed", function()
        resetAddon()
        WowStub.SetForever(true)
        local character = "Legs-Behindhead"
        local d = { level = 60, class = "WARRIOR" }
        SideQuest.Fire("SQ_COMM_MESSAGE", "DIR_R",
            SideQuestJSON.encode({ c = character, s = "char", v = SideQuest.Directory.Hash(d), at = 100, d = d }),
            "Legs Behindhead") -- raw CHAT_MSG_ADDON sender: same identity, space form
        local sec = SideQuest.Directory.Get(character).char
        assertTrue(not sec.relayed,
            "the sender's space-form name canonicalizes to the same key as `c`, so this isn't a relay")
    end)

    --------------------------------------------------------------------------
    -- Migration: v2 -> v3 rekeys old realm-mangled Forever names
    --------------------------------------------------------------------------

    test("migration: a v2 db with old realm-mangled Forever names rekeys to First-Surname on load", function()
        SideQuestDB = SideQuest.defaultDB()
        SideQuestDB.version = 2
        WowStub.SetForever(true)

        local broken = "Legs Behindhead-ShatteredHalls"
        SideQuestDB.directory[broken] = { seen_at = 100, char = { v = "x" } }
        SideQuestDB.addonVersions[broken] = { version = "1.0.0", seenAt = 100 }
        SideQuestDB.standby = { broken }
        SideQuestDB.roster = { taken_at = 100, members = { { character = broken, class = "WARRIOR" } } }
        SideQuestDB.professions[broken .. "|Mining"] = { character = broken, profession = "Mining" }

        SideQuest.InitDB()

        assertEq(SideQuestDB.version, SideQuest.CURRENT_DB_VERSION, "db upgraded to current version")
        assertTrue(SideQuestDB.directory["Legs-Behindhead"] ~= nil, "directory entry rekeyed")
        assertTrue(SideQuestDB.directory[broken] == nil, "the old broken key is gone")
        assertTrue(SideQuestDB.addonVersions["Legs-Behindhead"] ~= nil, "addonVersions entry rekeyed")
        assertEq(SideQuestDB.standby[1], "Legs-Behindhead", "standby entry rekeyed")
        assertEq(SideQuestDB.roster.members[1].character, "Legs-Behindhead", "roster row rekeyed")
        assertTrue(SideQuestDB.professions["Legs-Behindhead|Mining"] ~= nil, "profession key rekeyed")
    end)

    test("migration: rekeying keeps the newer of two entries that collapse onto the same canonical key", function()
        SideQuestDB = SideQuest.defaultDB()
        SideQuestDB.version = 2
        WowStub.SetForever(true)
        SideQuestDB.directory["Legs Behindhead"] = { seen_at = 50, char = { v = "old" } }
        SideQuestDB.directory["Legs-Behindhead"] = { seen_at = 200, char = { v = "new" } }
        SideQuest.InitDB()
        assertEq(SideQuestDB.directory["Legs-Behindhead"].seen_at, 200, "the newer entry wins the merge")
    end)

    --------------------------------------------------------------------------
    -- UI: display and outgoing (whisper/invite) forms
    --------------------------------------------------------------------------

    test("UI: displayName shows Forever's space-separated form, not the hyphenated storage key", function()
        resetAddon()
        WowStub.SetForever(true)
        assertEq(SideQuest.UI.DisplayName("Legs-Behindhead"), "Legs Behindhead",
            "shown with a space like every other Forever UI, not the link-form hyphen")
    end)

    test("UI: Guild tab Whisper/Invite send the game's own form for the target", function()
        resetAddon()
        WowStub.inCombat = false
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-GROW001" })
        SideQuestDB.roster = { taken_at = 1000, members = {
            { character = "Alt1-Whitemane", rank = "Member", online = true, class = "MAGE", level = 30,
                zone = "Ironforge" },
        } }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Guild")
        local chamber = SideQuest.UI.panels.Guild.chamber
        SideQuest.UI.RefreshGuild()
        local row = chamber.rows[1]

        row.whisperBtn:GetScript("OnClick")()
        row.inviteBtn:GetScript("OnClick")()

        assertEq(WowStub.whispers[#WowStub.whispers], "Alt1-Whitemane", "whisper target uses SQ.GameName's form")
        assertEq(WowStub.invites[#WowStub.invites], "Alt1-Whitemane", "invite target uses SQ.GameName's form")
    end)

    test("Forever: whisper and invite get the space-separated name, like Blizzard's own SendTell", function()
        resetAddon()
        WowStub.SetForever(true)
        assertEq(SideQuest.GameName("Legs-Behindhead"), "Legs Behindhead", "First-Surname key -> First Surname")
        assertEq(SideQuest.GameName("Legs"), "Legs", "a single token passes through")
        WowStub.SetForever(false)
        assertEq(SideQuest.GameName("Alt1-Whitemane"), "Alt1-Whitemane", "Name-Realm unchanged off Forever")
    end)
end
