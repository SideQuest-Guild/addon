-- tests/test_recorder.lua
-- The Raid Night recording control: who may start, the course's Start
-- raid/End raid gating on real recording state, persistence across a
-- simulated reload, and the "who can record" double-record warning.

return function(h)
    h.test("CanRecord: only an officer inside a raid instance may start", function()
        h.resetAddon()
        WowStub.isOfficer = false
        WowStub.instance = { inInstance = false, instanceType = "none", instanceID = 0, difficultyID = 1 }
        local ok, reason = SideQuest.Recorder.CanRecord()
        h.assertEq(ok, false, "not an officer")
        h.assertEq(reason, "Only officers record raids", "reason names the officer requirement")

        WowStub.isOfficer = true
        ok, reason = SideQuest.Recorder.CanRecord()
        h.assertEq(ok, false, "officer but not in a raid instance")
        h.assertEq(reason, "Zone into the raid to record", "reason names the instance requirement")

        WowStub.instance = { inInstance = true, instanceType = "party", instanceID = 5, difficultyID = 1 }
        ok = SideQuest.Recorder.CanRecord()
        h.assertEq(ok, false, "a party instance is not a raid")

        WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 409, difficultyID = 3 }
        ok, reason = SideQuest.Recorder.CanRecord()
        h.assertEq(ok, true, "officer inside a raid instance may record")
        h.assertEq(reason, nil, "no reason when allowed")
    end)

    h.test("starting a recording creates a session and unlocks Start raid; Start raid before recording does nothing", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-REC0001" })

        -- Start raid before any recording session exists: no-op, not marked done.
        SideQuest.Recorder.StartRaid()
        h.assertEq(SideQuest.Recorder.started, false, "Start raid does nothing without a session")
        h.assertEq(SideQuest.Recorder.startedAt, nil, "no start time recorded")

        WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 409, difficultyID = 3, name = "Molten Core" }
        local session = SideQuest.Recorder.StartRecording("Molten Core", 409, 3, 20)
        h.assertTrue(session ~= nil, "recording session created")
        h.assertEq(SideQuest.Recorder.current, session, "Recorder.current points at the new session")

        SideQuest.Recorder.StartRaid()
        h.assertEq(SideQuest.Recorder.started, true, "Start raid now available once recording")
        h.assertTrue(SideQuest.Recorder.startedAt ~= nil, "a start time was recorded")
    end)

    h.test("recording state (prep/invite/start/end) survives a simulated reload", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-REC0002" })
        WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 409, difficultyID = 3, name = "Molten Core" }

        local session = SideQuest.Recorder.StartRecording("Molten Core", 409, 3, 20)
        SideQuest.Recorder.MarkPrepDone()
        SideQuest.Recorder.MarkInviteDone()
        SideQuest.Recorder.StartRaid()
        local prepAt, inviteAt, startedAt = SideQuest.Recorder.prepDoneAt, SideQuest.Recorder.inviteDoneAt, SideQuest.Recorder.startedAt

        -- /reload: in-memory state is gone, SavedVariables survive.
        SideQuest.Recorder.current = nil
        SideQuest.Recorder.started = false
        SideQuest.Recorder.startedAt = nil
        SideQuest.Recorder.prepDoneAt = nil
        SideQuest.Recorder.inviteDoneAt = nil
        WowStub.FireEvent("PLAYER_ENTERING_WORLD")

        h.assertEq(SideQuest.Recorder.current, session, "same session resumed")
        h.assertEq(SideQuest.Recorder.started, true, "Start raid stays marked done")
        h.assertEq(SideQuest.Recorder.startedAt, startedAt, "Start raid's time survives")
        h.assertEq(SideQuest.Recorder.prepDoneAt, prepAt, "Prep's done time survives")
        h.assertEq(SideQuest.Recorder.inviteDoneAt, inviteAt, "Invite's done time survives")
    end)

    h.test("a HELLO from another officer recording the same instance shows them as recording and blocks a plain Start", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-REC0003" })
        WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 409, difficultyID = 3, name = "Molten Core" }

        local hello = SideQuestJSON.encode({
            character = "Officer2-Whitemane", version = "0.5.0", at = WowStub.time, officer = true,
            recording = { instance = "Molten Core", instance_id = 409, since = WowStub.time - 600 },
        })
        SideQuest.Fire("SQ_COMM_MESSAGE", "HELLO", hello, "Officer2-Whitemane")

        local known = SideQuest.Prep.KnownOfficers(600)
        h.assertEq(#known, 1, "one officer known")
        h.assertEq(known[1].character, "Officer2-Whitemane", "the right officer")
        h.assertTrue(known[1].recording ~= nil, "shown as recording")
        h.assertEq(known[1].recording.instance, "Molten Core", "recording instance carried through")

        local other = SideQuest.Recorder.OtherRecorder(409)
        h.assertTrue(other ~= nil, "OtherRecorder finds the conflict")
        h.assertEq(other.character, "Officer2-Whitemane", "conflicting officer identified")

        -- a plain Start (no confirm) is blocked, with the warning returned alongside nil
        local session, conflict = SideQuest.Recorder.StartRecording("Molten Core", 409, 3, 20)
        h.assertEq(session, nil, "first click does not start a session")
        h.assertTrue(conflict ~= nil, "the conflicting officer is returned for the confirm prompt")
        h.assertEq(SideQuest.Recorder.current, nil, "still not recording")

        -- a forced Start (the confirming second click) does start it
        session = SideQuest.Recorder.StartRecording("Molten Core", 409, 3, 20, true)
        h.assertTrue(session ~= nil, "forced start succeeds")
        h.assertEq(SideQuest.Recorder.current, session, "now recording")
    end)

    h.test("an old-format HELLO (no officer/recording fields) still parses and reads as unknown", function()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-REC0004" })

        local oldHello = SideQuestJSON.encode({ character = "Oldie-Whitemane", version = "0.1.0", at = WowStub.time })
        SideQuest.Fire("SQ_COMM_MESSAGE", "HELLO", oldHello, "Oldie-Whitemane")

        local seen = SideQuestDB.addonVersions["Oldie-Whitemane"]
        h.assertTrue(seen ~= nil, "the old-format HELLO was recorded")
        h.assertEq(seen.version, "0.1.0", "version still read")
        h.assertEq(seen.officer, nil, "officer status unknown, not false")
        h.assertEq(seen.recording, nil, "no recording info on an old HELLO")

        local known = SideQuest.Prep.KnownOfficers(600)
        h.assertEq(#known, 1, "an unknown-officer sender still appears (never excluded outright)")
        h.assertEq(known[1].officer, nil, "still flagged unknown")
    end)

    h.test("EncounterCountThisSession counts only this session's rows, zero with no session", function()
        h.resetAddon()
        h.assertEq(SideQuest.Recorder.EncounterCountThisSession(), 0, "zero with no session")

        WowStub.isOfficer = true
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-REC0005" })
        WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 409, difficultyID = 3, name = "Molten Core" }
        SideQuest.Recorder.StartRecording("Molten Core", 409, 3, 20)
        WowStub.FireEvent("ENCOUNTER_START", 1, "Lucifron", 3, 20)
        WowStub.FireEvent("ENCOUNTER_END", 1, "Lucifron", 3, 20, false)
        WowStub.FireEvent("ENCOUNTER_START", 1, "Lucifron", 3, 20)
        WowStub.FireEvent("ENCOUNTER_END", 1, "Lucifron", 3, 20, true)
        h.assertEq(SideQuest.Recorder.EncounterCountThisSession(), 2, "wipe + kill both counted")
    end)
end
