#!/usr/bin/env luajit
-- tests/run_tests.lua
-- Loads the WoW API stub, then the addon files in TOC order, then runs the
-- test suites below. Exits non-zero on any failure.

local SCRIPT_DIR = arg and arg[0] and arg[0]:match("(.*/)") or "./"
local ROOT = SCRIPT_DIR .. "../"

dofile(SCRIPT_DIR .. "wowstub.lua")

for _, f in ipairs(dofile(SCRIPT_DIR .. "addon_files.lua")(ROOT)) do
    dofile(ROOT .. f)
end

--------------------------------------------------------------------------
-- tiny test framework
--------------------------------------------------------------------------

local tests = {}
local failures = {}
local passCount = 0

local function test(name, fn)
    table.insert(tests, { name = name, fn = fn })
end

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertEq", tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(v, msg)
    if not v then
        error(msg or "expected true", 2)
    end
end


--------------------------------------------------------------------------
-- helpers: fresh addon state per test
--------------------------------------------------------------------------

local function resetAddon()
    SideQuestDB = nil
    SideQuest.InitDB()
    SideQuest.Rules.active = nil
    -- re-run default load (Rules.lua module-level `Rules.active` was set once
    -- at file load; reset by reconstructing from DEFAULTS)
    local Rules = SideQuest.Rules
    local function cloneRules(src)
        local out = {}
        for k, v in pairs(src) do
            if type(v) == "table" then
                local inner = {}
                for ik, iv in pairs(v) do inner[ik] = iv end
                out[k] = inner
            else
                out[k] = v
            end
        end
        return out
    end
    Rules.active = cloneRules(Rules.DEFAULTS)
    SideQuest.Recorder.current = nil
    SideQuest.Recorder.killedThisSession = {}
    SideQuest.Recorder.started = false
    SideQuest.Recorder.startedAt = nil
    SideQuest.Recorder.ended = false
    SideQuest.Recorder.endedAt = nil
    SideQuest.Recorder.prepDoneAt = nil
    SideQuest.Recorder.inviteDoneAt = nil
    SideQuest.Loot.activeBid = nil
    SideQuest.Comm.ResetAnswers()
    SideQuest.Comm.ResetRateLimits()
    SideQuest.Directory.ResetState()
    SideQuest.Professions.ResetState()
    SideQuest.Sync.ResetInboxState()
    WowStub.isOfficer = false
    WowStub.officerNoteCalls = 0
    WowStub.officerKnownAfterCalls = nil
    WowStub.chatLog = {}
    WowStub.addonMessages = {}
    WowStub.pvp = { scores = {}, winner = nil, myFaction = "Horde", duration = 0, scoreRequests = 0 }
    WowStub.bankTransactions = {}
    WowStub.bankMoneyTransactions = {}
    WowStub.bankLogQueries = {}
    WowStub.currentGuildBankTab = 1
    WowStub.instance = { inInstance = false, instanceType = "none", instanceID = 0, difficultyID = 1 }
    WowStub.inRaid = false
    WowStub.raidCount = 0
    WowStub.professions = {}
    WowStub.skillLines = {}
    WowStub.openTradeSkill = nil
    WowStub.SetForever(false)
    WowStub.invites = {}
    WowStub.whispers = {}
end

--------------------------------------------------------------------------
-- 1. JSON round trip
--------------------------------------------------------------------------

test("json round trip: scalars + nesting", function()
    local original = {
        v = 1,
        name = "Rage Winterchill",
        ok = true,
        bad = false,
        nothing = nil,
        list = { 1, 2, 3 },
        nested = { a = { b = { c = "deep" } } },
        empty_list = SideQuestJSON.EMPTY_ARRAY,
    }
    local json = SideQuestJSON.encode(original)
    local decoded = SideQuestJSON.decode(json)
    assertEq(decoded.v, 1, "v")
    assertEq(decoded.name, "Rage Winterchill", "name")
    assertEq(decoded.ok, true, "ok")
    assertEq(decoded.bad, false, "bad")
    assertEq(decoded.list[1], 1, "list[1]")
    assertEq(decoded.list[3], 3, "list[3]")
    assertEq(decoded.nested.a.b.c, "deep", "nested")
    assertEq(#decoded.empty_list, 0, "empty_list length")
end)

test("json round trip: special characters", function()
    local s = "quote\" backslash\\ newline\n tab\t unicode\xC3\xA9"
    local json = SideQuestJSON.encode({ s = s })
    local decoded = SideQuestJSON.decode(json)
    assertEq(decoded.s, s, "special chars")
end)

--------------------------------------------------------------------------
-- 2. base64 round trip
--------------------------------------------------------------------------

test("base64 round trip: various lengths", function()
    local cases = { "", "f", "fo", "foo", "foob", "fooba", "foobar", "SideQuest guild EPGP" }
    for _, c in ipairs(cases) do
        local encoded = SideQuestBase64.encode(c)
        local decoded = SideQuestBase64.decode(encoded)
        assertEq(decoded, c, "base64 roundtrip for " .. c)
    end
end)

test("base64: standard alphabet with padding", function()
    assertEq(SideQuestBase64.encode("Man"), "TWFu", "no padding needed")
    assertEq(SideQuestBase64.encode("Ma"), "TWE=", "one pad")
    assertEq(SideQuestBase64.encode("M"), "TQ==", "two pad")
end)

--------------------------------------------------------------------------
-- 3. Codec vs contract examples
--------------------------------------------------------------------------

test("codec: export payload encode/decode matches contract shape", function()
    local payload = {
        v = 1,
        addon_version = "1.0.0",
        exported_at = 1793500000,
        guild = "SideQuest",
        realm = "Whitemane",
        recorder = "Officername-Whitemane",
        sessions = {
            {
                id = "A1B2C3D4-1793490000-1",
                event_id = nil,
                instance_name = "Hyjal Summit",
                instance_id = 534,
                difficulty_id = 3,
                size = 20,
                started_at = 1793490000,
                ended_at = 1793500000,
                members = SideQuestJSON.EMPTY_ARRAY,
            },
        },
        encounters = SideQuestJSON.EMPTY_ARRAY,
        loot = {
            {
                id = "x1", session_id = "s1", encounter_row_id = nil, item_id = 30896,
                item_name = "Glory of the Defender", quality = 4, inv_type = "INVTYPE_CHEST",
                character = "Name-Realm", response = "ms", gp = 100, at = 1793491500,
                officer = "Officername-Whitemane", voided = false,
            },
        },
        awards = {
            {
                id = "a1", session_id = nil, kind = "ep", character = "Name-Realm", amount = 10,
                reason = "boss_kill", note = "Rage Winterchill", loot_id = nil, at = 1793491300,
                officer = "Officername-Whitemane", voided = false,
            },
        },
    }
    local str = SideQuest.Codec.EncodeExport(payload)
    assertTrue(str:sub(1, 5) == "SQX1:", "has SQX1 prefix")
    local decoded = SideQuest.Codec.DecodeExport(str)
    assertEq(decoded.v, 1, "v")
    assertEq(decoded.recorder, "Officername-Whitemane", "recorder")
    assertEq(decoded.sessions[1].instance_name, "Hyjal Summit", "instance_name")
    assertEq(decoded.loot[1].item_name, "Glory of the Defender", "item_name")
    assertEq(decoded.loot[1].gp, 100, "gp")
    assertEq(decoded.awards[1].reason, "boss_kill", "reason")
    assertEq(#decoded.encounters, 0, "encounters empty array")
end)

test("codec: import string decode matches contract shape", function()
    local importPayload = {
        v = 1,
        generated_at = 1793500000,
        rules = {
            ep = { boss_kill = 10, progress = 10, on_time = 5, full_night = 5 },
            gp = { INVTYPE_HEAD = 100 },
            chase_multiplier = 1.5, legendary_gp = 300, os_percent = 10,
            base_gp = 100, min_gp = 100, decay_percent = 15, trial_days = 14,
        },
        standings = {
            {
                member_id = 4, name = "Display name", main = "Name-Realm", class = "WARRIOR",
                characters = { "Name-Realm", "Alt-Realm" }, ep = 123.4, gp = 150.0, pr = 0.823, trial = false,
            },
        },
        killed_encounters = { 652, 653 },
        events = {
            {
                id = "uuid", title = "Hyjal Summit", kind = "raid", starts_at = 1793500000, size = 20,
                signups = {
                    { character = "Name", class = "WARRIOR", role = "tank", status = "signed", group = 1, bench = false },
                },
            },
        },
    }
    local str = SideQuest.Codec.EncodeImport(importPayload)
    assertTrue(str:sub(1, 5) == "SQI1:", "has SQI1 prefix")
    local decoded = SideQuest.Codec.DecodeImport(str)
    assertEq(decoded.standings[1].member_id, 4, "member_id")
    assertEq(decoded.standings[1].pr, 0.823, "pr")
    assertEq(decoded.killed_encounters[1], 652, "killed_encounters")
    assertEq(decoded.events[1].signups[1].character, "Name", "signup character")
end)

--------------------------------------------------------------------------
-- 4. GP calc
--------------------------------------------------------------------------

test("GP calc: slot base costs", function()
    local R = SideQuest.Rules
    assertEq(R.ComputeGP("INVTYPE_CHEST", "ms"), 100, "chest ms")
    assertEq(R.ComputeGP("INVTYPE_SHOULDER", "ms"), 75, "shoulder ms")
    assertEq(R.ComputeGP("INVTYPE_NECK", "ms"), 55, "neck ms")
    assertEq(R.ComputeGP("INVTYPE_TRINKET", "ms"), 125, "trinket ms")
    assertEq(R.ComputeGP("INVTYPE_WEAPON", "ms"), 150, "weapon ms")
    assertEq(R.ComputeGP("INVTYPE_2HWEAPON", "ms"), 200, "2h ms")
    assertEq(R.ComputeGP("INVTYPE_RANGED", "ms"), 50, "ranged ms")
end)

test("GP calc: response modifiers", function()
    local R = SideQuest.Rules
    assertEq(R.ComputeGP("INVTYPE_CHEST", "alt"), 0, "alt pays 0")
    assertEq(R.ComputeGP("INVTYPE_CHEST", "de"), 0, "de pays 0")
    assertEq(R.ComputeGP("INVTYPE_CHEST", "bank"), 0, "bank pays 0")
    -- os pays 10% rounded half up: 100 * 0.10 = 10
    assertEq(R.ComputeGP("INVTYPE_CHEST", "os"), 10, "chest os")
    -- shoulder os: 75 * 0.10 = 7.5 -> round half up -> 8
    assertEq(R.ComputeGP("INVTYPE_SHOULDER", "os"), 8, "shoulder os rounds half up")
end)

test("GP calc: tier token, chase, legendary, main caster weapon", function()
    local R = SideQuest.Rules
    assertEq(R.ComputeGP("INVTYPE_CHEST", "ms", { isTierToken = true, tierSlotInvType = "INVTYPE_LEGS" }), 100, "tier token uses chosen slot")
    assertEq(R.ComputeGP("INVTYPE_TRINKET", "ms", { isChase = true }), 188, "chase = slot*1.5 round half up (125*1.5=187.5->188)")
    assertEq(R.ComputeGP("INVTYPE_CHEST", "ms", { isLegendary = true }), 300, "legendary flat 300")
    assertEq(R.ComputeGP("INVTYPE_WEAPON", "ms", { isMainCasterWeapon = true }), 200, "1h main caster weapon uses 200")
    assertEq(R.ComputeGP("INVTYPE_WEAPONMAINHAND", "ms"), 150, "normal 1h stays 150")
end)

test("GP calc: council item still charges GP", function()
    local R = SideQuest.Rules
    assertEq(R.ComputeGP("INVTYPE_TRINKET", "council", { isChase = true }), 188, "council pays full chase cost")
end)

--------------------------------------------------------------------------
-- 5. Bid ordering
--------------------------------------------------------------------------

test("bid ordering: ms raiders > ms trials > os > alt > de, ties by EP then roll", function()
    local now = 1793500000
    local bids = {
        { character = "AltGuy-R", response = "alt", pr = 9.0, ep = 999, roll = 99 },
        { character = "DeGuy-R", response = "de", pr = 9.0, ep = 999, roll = 99 },
        { character = "OsHigh-R", response = "os", pr = 2.0, ep = 50, roll = 10 },
        { character = "MsLow-R", response = "ms", pr = 0.5, ep = 10, roll = 50 },
        { character = "MsHigh-R", response = "ms", pr = 1.5, ep = 20, roll = 1 },
        { character = "TrialHigh-R", response = "ms", pr = 5.0, ep = 100, roll = 1, trial = true, trial_started_at = now - 5 * 86400 },
        { character = "TrialExpired-R", response = "ms", pr = 5.0, ep = 100, roll = 1, trial = true, trial_started_at = now - 20 * 86400 },
        { character = "TieA-R", response = "ms", pr = 1.5, ep = 30, roll = 20 },
        { character = "TieB-R", response = "ms", pr = 1.5, ep = 30, roll = 80 },
    }
    local ranked = SideQuest.Loot.RankBids(bids, now)
    local order = {}
    for i, b in ipairs(ranked) do
        order[i] = b.character
    end
    -- ms non-trial raiders ranked by PR desc (ties: EP desc, then roll desc);
    -- TrialExpired-R is >14 days old so it counts as a regular raider (same PR
    -- group as other ms raiders, ranked by PR among them)
    assertEq(order[1], "TrialExpired-R", "expired trial ranks as raider, pr 5.0 highest")
    assertEq(order[2], "TieB-R", "tie broken by roll desc (80>20) at pr 1.5,ep 30")
    assertEq(order[3], "TieA-R", "tie loser")
    assertEq(order[4], "MsHigh-R", "pr 1.5 ep 20")
    assertEq(order[5], "MsLow-R", "pr 0.5 lowest ms raider")
    assertEq(order[6], "TrialHigh-R", "active trial sorts after all ms raiders")
    assertEq(order[7], "OsHigh-R", "os group after all ms")
    assertEq(order[8], "AltGuy-R", "alt after os")
    assertEq(order[9], "DeGuy-R", "de last")
end)

test("bid ordering: council/bank responses are excluded from auto ranking", function()
    local bids = {
        { character = "A-R", response = "ms", pr = 1, ep = 1, roll = 1 },
        { character = "B-R", response = "council", pr = 99, ep = 99, roll = 99 },
        { character = "C-R", response = "bank", pr = 99, ep = 99, roll = 99 },
    }
    local ranked = SideQuest.Loot.RankBids(bids)
    assertEq(#ranked, 1, "only the ms bid is ranked")
    assertEq(ranked[1].character, "A-R", "council/bank excluded")
end)

--------------------------------------------------------------------------
-- 6. Simulated raid night -> export matches contract
--------------------------------------------------------------------------

test("simulated raid night produces a contract-shaped export", function()
    resetAddon()
    WowStub.isOfficer = true
    WowStub.guildName = "SideQuest"
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Officername", realm = "Whitemane", class = "PRIEST", guid = "Player-1-AAAA1111" })

    -- roster: tank, healer, two dps, one trial dps
    WowStub.SetRaid({
        { name = "Tanky", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-BBBB0001" },
        { name = "Healy", realm = "Whitemane", class = "PRIEST", guid = "Player-1-BBBB0002" },
        { name = "Dps1", realm = "Whitemane", class = "MAGE", guid = "Player-1-BBBB0003" },
        { name = "Dps2", realm = "Whitemane", class = "ROGUE", guid = "Player-1-BBBB0004" },
    })
    WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 534, difficultyID = 3, name = "Hyjal Summit" }

    local session = SideQuest.Recorder.StartRecording("Hyjal Summit", 534, 3, 20)
    assertTrue(session ~= nil, "session started")

    SideQuest.Recorder.StartRaid()

    -- boss 1: wipe first (progress EP, once), then kill (boss_kill EP)
    WowStub.FireEvent("ENCOUNTER_START", 652, "Rage Winterchill", 3, 20)
    WowStub.FireEvent("ENCOUNTER_END", 652, "Rage Winterchill", 3, 20, false)
    WowStub.FireEvent("ENCOUNTER_START", 652, "Rage Winterchill", 3, 20)
    WowStub.FireEvent("ENCOUNTER_END", 652, "Rage Winterchill", 3, 20, true)

    -- roster change mid-raid: Dps2 drops, standby member joins
    WowStub.SetRaid({
        { name = "Tanky", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-BBBB0001" },
        { name = "Healy", realm = "Whitemane", class = "PRIEST", guid = "Player-1-BBBB0002" },
        { name = "Dps1", realm = "Whitemane", class = "MAGE", guid = "Player-1-BBBB0003" },
    })
    SideQuest.Recorder.AddStandby("Standby-Whitemane")
    WowStub.FireEvent("GROUP_ROSTER_UPDATE")

    -- boss 2: straight kill
    WowStub.FireEvent("ENCOUNTER_START", 653, "Anetheron", 3, 20)
    WowStub.FireEvent("ENCOUNTER_END", 653, "Anetheron", 3, 20, true)

    -- a loot award, then undo it to verify the voided flag round-trips
    local lootId = SideQuest.Loot.AwardLoot(
        { item_id = 30896, item_name = "Glory of the Defender", quality = 4, inv_type = "INVTYPE_CHEST" },
        "Tanky-Whitemane", "ms", session.id, nil, {})
    assertEq(lootId ~= nil, true, "loot id created")

    local lootId2 = SideQuest.Loot.AwardLoot(
        { item_id = 40, item_name = "Mistake Band", quality = 3, inv_type = "INVTYPE_FINGER" },
        "Dps1-Whitemane", "ms", session.id, nil, {})
    SideQuest.Loot.Undo(lootId2)

    SideQuest.Recorder.EndRaid()

    local str = SideQuest.Sync.BuildExport()
    assertTrue(str:sub(1, 5) == "SQX1:", "export has prefix")

    local decoded = SideQuest.Codec.DecodeExport(str)
    assertEq(decoded.v, 2, "v")
    assertEq(decoded.guild, "SideQuest", "guild")
    assertEq(decoded.realm, "Whitemane", "realm")
    assertEq(decoded.recorder, "Officername-Whitemane", "recorder")
    assertEq(#decoded.sessions, 1, "one session")
    assertEq(decoded.sessions[1].instance_name, "Hyjal Summit", "instance_name")
    assertEq(decoded.sessions[1].instance_id, 534, "instance_id")
    assertTrue(decoded.sessions[1].ended_at ~= nil, "session ended")

    assertEq(#decoded.encounters, 3, "three encounter rows (wipe + 2 kills)")
    local wipeRow, killRow652, killRow653
    for _, row in ipairs(decoded.encounters) do
        if row.encounter_id == 652 and row.success == false then
            wipeRow = row
        elseif row.encounter_id == 652 and row.success == true then
            killRow652 = row
        elseif row.encounter_id == 653 then
            killRow653 = row
        end
    end
    assertTrue(wipeRow ~= nil, "wipe row present")
    assertTrue(killRow652 ~= nil, "kill row present")
    assertTrue(killRow653 ~= nil, "second kill row present")

    assertEq(#decoded.loot, 2, "two loot rows")
    local voidedLoot, liveLoot
    for _, row in ipairs(decoded.loot) do
        if row.id == lootId2 then
            voidedLoot = row
        elseif row.id == lootId then
            liveLoot = row
        end
    end
    assertEq(voidedLoot.voided, true, "undone loot row is voided")
    assertEq(liveLoot.voided, false, "live loot row stays un-voided")
    assertEq(liveLoot.gp, 100, "chest ms gp")

    -- awards: on_time x4 (raid+standby), boss_kill x4 (only 652 kill +653 kill members = 3 raid at kill652 time +
    -- standby at kill653), progress x3 (wipe), full_night x4, plus 2 gp loot twins (one voided)
    local epReasons = {}
    local gpCount = 0
    local voidedAwardFound = false
    for _, row in ipairs(decoded.awards) do
        if row.kind == "ep" then
            epReasons[row.reason] = (epReasons[row.reason] or 0) + 1
        elseif row.kind == "gp" then
            gpCount = gpCount + 1
            if row.loot_id == lootId2 then
                assertEq(row.voided, true, "voided gp twin stays voided")
                voidedAwardFound = true
            end
        end
    end
    assertEq(epReasons.on_time, 4, "on_time: the four raiders at Start raid")
    assertEq(epReasons.progress, 4, "progress: once for the wipe on an unkilled boss")
    assertEq(epReasons.boss_kill, 8, "boss_kill: four at each kill")
    assertEq(epReasons.full_night, 4, "full_night: the three still in the raid plus standby")

    -- Dps2 left before Anetheron: no EP for that kill or for staying the night
    for _, row in ipairs(decoded.awards) do
        if row.character == "Dps2-Whitemane" then
            assertTrue(row.reason ~= "full_night" and row.note ~= "Anetheron", "no EP after leaving: " .. row.reason)
        end
    end
    assertEq(killRow653.standby[1], "Standby-Whitemane", "standby listed on the kill")
    local classes = {}
    for _, m in ipairs(decoded.sessions[1].members) do
        classes[m.character] = m.class
    end
    assertEq(classes["Tanky-Whitemane"], "WARRIOR", "raid member class recorded")
    assertEq(gpCount, 2, "two gp ledger twins (one per loot row)")
    assertTrue(voidedAwardFound, "the voided loot's gp twin was found and voided")

    -- persist the fixture for the site's import tests
    local fixturePath = ROOT .. "tests/fixtures/export_v1.txt"
    local fh = io.open(fixturePath, "w")
    fh:write(str)
    fh:close()
end)

test("a /reload mid-raid resumes the same session and keeps once-per-night state", function()
    resetAddon()
    WowStub.isOfficer = true
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Officername", realm = "Whitemane", class = "PRIEST", guid = "Player-1-AAAA1111" })
    WowStub.SetRaid({ { name = "Tanky", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-BBBB0001" } })
    WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 534, difficultyID = 3, name = "Hyjal Summit" }

    local session = SideQuest.Recorder.StartRecording("Hyjal Summit", 534, 3, 20)
    SideQuest.Recorder.StartRaid()
    WowStub.FireEvent("ENCOUNTER_START", 652, "Rage Winterchill", 3, 20)
    WowStub.FireEvent("ENCOUNTER_END", 652, "Rage Winterchill", 3, 20, false)

    -- /reload: in-memory state is gone, SavedVariables survive
    SideQuest.Recorder.current = nil
    SideQuest.Recorder.started = false
    SideQuest.Recorder.killedThisSession = {}
    WowStub.FireEvent("PLAYER_ENTERING_WORLD")

    assertEq(SideQuest.Recorder.current, session, "same session resumed")
    assertEq(SideQuest.Recorder.started, true, "Start raid is not awarded twice")
    WowStub.FireEvent("ENCOUNTER_START", 652, "Rage Winterchill", 3, 20)
    WowStub.FireEvent("ENCOUNTER_END", 652, "Rage Winterchill", 3, 20, false)
    local progress = 0
    for _, row in ipairs(SideQuestDB.pending.awards) do
        if row.reason == "progress" then
            progress = progress + 1
        end
    end
    assertEq(progress, 1, "progress EP still once per boss per night after the reload")
end)

--------------------------------------------------------------------------
-- 7. Comm chunking/reassembly
--------------------------------------------------------------------------

test("comm: chunk + reassemble a long message", function()
    local payload = string.rep("x", 1000)
    local chunks = SideQuest.Comm.ChunkMessage("STANDINGS", payload)
    assertTrue(#chunks > 1, "payload splits into multiple chunks")
    local result
    for i = #chunks, 1, -1 do -- deliver out of order
        local _, full = SideQuest.Comm.ReceiveChunk("Sender-Realm", chunks[i])
        if full then
            result = full
        end
    end
    assertEq(result, payload, "reassembled payload matches original")
end)

--------------------------------------------------------------------------
-- 8. v2: export sections, signup relay/ack, crafter suppression, sheet
--    answer, import public/officer split, combat deferral
--------------------------------------------------------------------------

local function deliverQueued(fromSender)
    local queued = WowStub.addonMessages
    WowStub.addonMessages = {}
    for _, m in ipairs(queued) do
        WowStub.DeliverAddonMessage(fromSender, m.message)
    end
end

test("v2 export: every v1 and v2 section has at least one row from a simulated night", function()
    resetAddon()
    WowStub.realm = "Whitemane"

    -- a member signs up before the officer does anything else, so the
    -- queued SIGNUP message is waiting when the officer identity logs in
    WowStub.isOfficer = false
    WowStub.SetUnit("player", { name = "Tanky", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-BBBB0001" })
    SideQuest.Signups.Answer("8f2c6a1e-4b7d-4c1a-9e3f-2d5b7a9c1e40", "going", nil, "tank")

    WowStub.isOfficer = true
    WowStub.SetUnit("player", { name = "Officername", realm = "Whitemane", class = "PRIEST", guid = "Player-1-AAAA1111" })
    deliverQueued("Tanky-Whitemane")
    assertEq(#SideQuestDB.pending.signups, 1, "the relayed signup is queued")
    assertEq(SideQuestDB.pending.signups[1].status, "signed", "status mapped from 'going'")
    assertEq(SideQuestDB.pending.signups[1].role, "tank", "role carried on the relayed signup")
    assertEq(SideQuestDB.pending.signups[1].class, "WARRIOR", "class token stays uppercase like the game")

    WowStub.guildRoster = {
        { name = "Tanky", rank = "Officer", rankIndex = 1, level = 30, class = "WARRIOR", classFile = "WARRIOR", zone = "Ironforge", online = true },
        { name = "Healy", rank = "Raider", rankIndex = 2, level = 30, class = "PRIEST", classFile = "PRIEST", zone = "Ironforge", online = true },
        { name = "Dps1", rank = "Member", rankIndex = 3, level = 29, class = "MAGE", classFile = "MAGE", zone = "Stormwind", online = false },
    }
    SideQuest.Roster.Sweep()

    table.insert(SideQuestDB.pending.professions, {
        character = "Tanky-Whitemane", profession = "Blacksmithing", skill = 150, max_skill = 150,
        scanned_at = WowStub.time, recipes = { { id = 2662, name = "Copper Chain Pants", item_id = 2852 } },
    })

    WowStub.SetRaid({ { name = "Tanky", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-BBBB0001" } })
    WowStub.instance = { inInstance = true, instanceType = "raid", instanceID = 534, difficultyID = 3, name = "Hyjal Summit" }
    local session = SideQuest.Recorder.StartRecording("Hyjal Summit", 534, 3, 20)
    SideQuest.Recorder.StartRaid()
    WowStub.FireEvent("ENCOUNTER_START", 652, "Rage Winterchill", 3, 20)
    WowStub.FireEvent("ENCOUNTER_END", 652, "Rage Winterchill", 3, 20, true)
    SideQuest.Loot.AwardLoot(
        { item_id = 30896, item_name = "Glory of the Defender", quality = 4, inv_type = "INVTYPE_CHEST" },
        "Tanky-Whitemane", "ms", session.id, nil, {})
    SideQuest.Recorder.EndRaid()

    table.insert(SideQuestDB.pending.bank, {
        id = "bank-sim-1", at = WowStub.time, character = "Tanky-Whitemane", kind = "deposit",
        item_id = 2589, item_name = "Linen Cloth", count = 20, money = 0, tab = 1,
    })
    table.insert(SideQuestDB.pending.announcements, { id = "ann-1", text = "Flasks please", officer = "Officername-Whitemane", at = WowStub.time })

    local recruit = SideQuest.Recruits.Save({
        character = "Trialer-Whitemane", class = "MAGE", status = "trial",
        checklist = { talked = true, gear_check = false, first_raid = false, vouched = true },
    })
    SideQuest.Recruits.Vote(recruit.id, "yes")
    SideQuest.Recruits.AddNote("Tanky-Whitemane", "Prefers tanking over DPS")

    local str = SideQuest.Sync.BuildExport()
    local decoded = SideQuest.Codec.DecodeExport(str)
    assertEq(decoded.v, 2, "export v2")
    assertEq(#decoded.sessions, 1, "session present")
    assertEq(#decoded.encounters, 1, "encounter present")
    assertEq(#decoded.loot, 1, "loot present")
    assertTrue(#decoded.awards > 0, "awards present")
    assertTrue(#decoded.roster.members >= 3, "roster has at least 3 members")
    assertEq(#decoded.professions, 1, "professions present")
    assertEq(#decoded.professions[1].recipes, 1, "profession recipe present")
    assertEq(#decoded.signups, 1, "signups present")
    assertEq(decoded.signups[1].role, "tank", "signup role present")
    assertEq(#decoded.bank, 1, "bank present")
    assertEq(#decoded.announcements, 1, "announcements present")
    assertEq(#decoded.recruits, 1, "recruits present")
    assertEq(#decoded.recruits[1].votes, 1, "recruit vote present")
    assertEq(#decoded.member_notes, 1, "member_notes present")

    local fixturePath = ROOT .. "tests/fixtures/export_v2.txt"
    local fh = io.open(fixturePath, "w")
    fh:write(str)
    fh:close()
end)

test("signup relay/ack: member sends, officer queues + acks, member sees sent then saved", function()
    resetAddon()
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Member", realm = "Whitemane", class = "HUNTER", guid = "Player-1-CCCC0001" })
    WowStub.isOfficer = false

    SideQuest.Signups.Answer("1a2b3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d", "going")
    local state = SideQuest.Signups.MyState("1a2b3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d")
    assertEq(state, "sent", "answer starts as sent")

    WowStub.isOfficer = true
    deliverQueued("Member-Whitemane")
    assertEq(#SideQuestDB.pending.signups, 1, "officer queued the sign-up")
    assertEq(SideQuestDB.pending.signups[1].status, "signed", "status mapped from 'going'")

    WowStub.isOfficer = false
    deliverQueued("Officername-Whitemane")
    state = SideQuest.Signups.MyState("1a2b3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d")
    assertEq(state, "saved", "ack flips sign-up to saved")
end)

test("crafter query: an already-seen offline answer suppresses a second officer's answer", function()
    resetAddon()
    WowStub.isOfficer = true
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Officer2", realm = "Whitemane", class = "PRIEST", guid = "Player-1-DDDD0001" })
    SideQuestDB.onDemand.crafters = { { character = "Smith-Whitemane", member_id = 1, profession = "Blacksmithing", skill = 150, recipes = { 2662 } } }
    SideQuestDB.onDemand.recipe_names = { ["2662"] = "Copper Chain Pants" }

    -- another officer's aggregate answer already arrived for this query id
    SideQuest.Comm.SuppressAnswer("CRAFT_OFFLINE:q-1")
    SideQuest.Fire("SQ_COMM_MESSAGE", "CRAFT_Q", SideQuestJSON.encode({ id = "q-1", query = "chain" }), "Someone-Whitemane")

    local sawOfflineAnswer = false
    for _, m in ipairs(WowStub.addonMessages) do
        if m.message:find("^CRAFT_A") then
            sawOfflineAnswer = true
        end
    end
    assertTrue(not sawOfflineAnswer, "suppressed officer never sends its own aggregate answer")
end)

test("sheet query/answer: member asks, officer answers from on-demand sheets", function()
    resetAddon()
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Member", realm = "Whitemane", class = "HUNTER", guid = "Player-1-EEEE0001" })
    WowStub.isOfficer = false

    SideQuest.Sheet.Request()

    WowStub.isOfficer = true
    SideQuestDB.guild.members = { { member_id = 7, name = "Membername", main = "Member-Whitemane",
        characters = { { name = "Member-Whitemane", class = "HUNTER", is_main = true } } } }
    SideQuestDB.onDemand.sheets["7"] = { ledger = { { at = WowStub.time, kind = "ep", amount = 10, reason = "boss_kill" } }, loot = {} }
    deliverQueued("Member-Whitemane")

    WowStub.isOfficer = false
    deliverQueued("Officer2-Whitemane")
    assertTrue(SideQuest.Sheet.lastAnswer ~= nil, "member received a sheet answer")
    assertEq(SideQuest.Sheet.lastAnswer.found, true, "sheet was found")
    assertEq(#SideQuest.Sheet.lastAnswer.ledger, 1, "ledger entry carried over")
end)

test("import v2: public part broadcasts on GUILD, officer part only on OFFICER, never mixed", function()
    resetAddon()
    WowStub.isOfficer = true
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Officername", realm = "Whitemane", class = "PRIEST", guid = "Player-1-FFFF0001" })

    local payload = {
        v = 2, generated_at = WowStub.time,
        rules = nil, standings = {}, killed_encounters = {}, events = {},
        members = { { member_id = 1, name = "Membername", main = "Member-Whitemane", class = "HUNTER", characters = {} } },
        news = {},
        sheets = {}, crafters = {}, recipe_names = {},
        officer = { recruits = { { id = "r1", character = "Trialer-Whitemane", class = "MAGE", status = "trial" } },
                    member_notes = {}, inactive = {} },
    }
    SideQuest.Sync.ApplyImport(payload)

    assertEq(SideQuestDB.guild.members[1].member_id, 1, "public members cached")
    assertEq(SideQuestDB.officerData.recruits[1].id, "r1", "officer recruit cached locally")

    local sawOfficerDataOnGuild = false
    local sawRosterPubOnOfficer = false
    for _, m in ipairs(WowStub.addonMessages) do
        if m.channel == "GUILD" and m.message:find("officer", 1, true) then
            sawOfficerDataOnGuild = true
        end
        if m.channel == "OFFICER" and m.message:find("^ROSTERPUB") then
            sawRosterPubOnOfficer = true
        end
    end
    assertTrue(not sawOfficerDataOnGuild, "officer-only data never appears on a GUILD-channel message")
    assertTrue(not sawRosterPubOnOfficer, "ROSTERPUB never sent on OFFICER")
end)

test("UI never opens in combat; opens once combat ends", function()
    resetAddon()
    WowStub.inCombat = true
    SideQuest.UI.main = nil
    SideQuest.UI.Show()
    assertTrue(SideQuest.UI.main == nil, "window not built while in combat")

    WowStub.inCombat = false
    WowStub.FireEvent("PLAYER_REGEN_ENABLED")
    assertTrue(SideQuest.UI.main ~= nil, "window builds once combat ends")
    assertTrue(SideQuest.UI.main:IsShown(), "window is shown once combat ends")
end)

test("bid popup: GP computed from the item's real slot (regression for the hardcoded-nil bug)", function()
    resetAddon()
    SideQuest.UI.main = nil
    SideQuest.UI.bidPopup = nil
    WowStub.inCombat = false
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Demo1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-GGGG0001" })
    WowStub.items = {
        [30896] = { itemId = 30896, name = "Glory of the Defender", quality = 4, equipLoc = "INVTYPE_CHEST",
            icon = "Interface\\Icons\\INV_Chest_Plate04" },
    }
    SideQuest.UI.ShowBidPopup("item:30896:Glory of the Defender", 30)
    local popup = SideQuest.UI.bidPopup
    assertTrue(popup ~= nil, "popup built")
    assertTrue(popup.itemText:GetText() == "Glory of the Defender", "resolved the real item name, not the raw link text")
    assertTrue(popup.slotGpText:GetText():find("100") ~= nil, "chest main-spec bid computes GP 100, not 0")
end)

test("console: switching sub-tabs shows only the chosen sub-view (regression for the SetShown stub bug)", function()
    resetAddon()
    SideQuest.UI.main = nil
    WowStub.isOfficer = true
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Officername", realm = "Whitemane", class = "PRIEST", guid = "Player-1-HHHH0001" })
    SideQuest.UI.Show()
    SideQuest.UI.ShowTab("Console")
    SideQuest.UI.ShowConsoleSub("Loot")
    local subs = SideQuest.UI.panels.Console.subPanels
    assertTrue(subs["Loot"]:IsShown(), "Loot sub-view is shown once chosen")
    assertTrue(not subs["Raid Night"]:IsShown(), "Raid Night sub-view is hidden while Loot is active")
    SideQuest.UI.ShowConsoleSub("Roster")
    assertTrue(subs["Roster"]:IsShown(), "switching shows Roster")
    assertTrue(not subs["Loot"]:IsShown(), "switching hides the previous sub-view (Loot)")
end)

--------------------------------------------------------------------------
-- 9. Staged import ("inbox") from SideQuest Companion
--------------------------------------------------------------------------

local function buildInboxPayload(generatedAt)
    return SideQuest.Codec.EncodeImport({
        v = 1,
        generated_at = generatedAt,
        rules = nil,
        standings = SideQuestJSON.EMPTY_ARRAY,
        killed_encounters = SideQuestJSON.EMPTY_ARRAY,
        events = SideQuestJSON.EMPTY_ARRAY,
    })
end

local function lastChatLine()
    return WowStub.chatLog[#WowStub.chatLog]
end

test("inbox: officer applies the staged import and it is cleared", function()
    resetAddon()
    WowStub.isOfficer = true
    SideQuestDB.standings.generated_at = 100
    SideQuestDB.inbox = { payload = buildInboxPayload(200), generated_at = 200, staged_at = 250 }
    SideQuest.Fire("PLAYER_ENTERING_WORLD")
    assertEq(SideQuestDB.inbox, nil, "inbox cleared")
    assertEq(SideQuestDB.standings.generated_at, 200, "standings updated from the staged import")
    assertTrue(lastChatLine():find("Applied the import SideQuest Companion staged") ~= nil, "prints an applied line")
end)

test("inbox: an import older than current standings is skipped and cleared", function()
    resetAddon()
    WowStub.isOfficer = true
    SideQuestDB.standings.generated_at = 500
    SideQuestDB.inbox = { payload = buildInboxPayload(200), generated_at = 200, staged_at = 250 }
    SideQuest.Fire("PLAYER_ENTERING_WORLD")
    assertEq(SideQuestDB.inbox, nil, "inbox cleared")
    assertEq(SideQuestDB.standings.generated_at, 500, "standings untouched: the staged import was older")
    assertTrue(lastChatLine():find("older than what the addon already has") ~= nil, "explains why it was skipped")
end)

test("inbox: a non-officer never applies it and leaves it for an officer alt", function()
    resetAddon()
    WowStub.isOfficer = false
    SideQuestDB.standings.generated_at = 100
    SideQuestDB.inbox = { payload = buildInboxPayload(200), generated_at = 200, staged_at = 250 }
    SideQuest.Fire("PLAYER_ENTERING_WORLD")
    assertTrue(SideQuestDB.inbox ~= nil, "inbox kept for an officer on the same account")
    assertEq(SideQuestDB.standings.generated_at, 100, "standings untouched: never applied")
    assertTrue(lastChatLine():find("Log in on an officer") ~= nil, "says an officer has to apply it")
    local lines = #WowStub.chatLog
    SideQuest.Fire("GUILD_ROSTER_UPDATE")
    assertEq(#WowStub.chatLog, lines, "doesn't repeat itself on later roster updates")
end)

test("inbox: a malformed payload is discarded with a message", function()
    resetAddon()
    WowStub.isOfficer = true
    SideQuestDB.inbox = { payload = "not an import string", generated_at = 200, staged_at = 250 }
    SideQuest.Fire("PLAYER_ENTERING_WORLD")
    assertEq(SideQuestDB.inbox, nil, "inbox cleared")
    assertTrue(lastChatLine():find("could not be read") ~= nil, "explains it could not be read")
end)

test("inbox: officer status unknown at first, then known on retry", function()
    resetAddon()
    SideQuestDB.standings.generated_at = 100
    SideQuestDB.inbox = { payload = buildInboxPayload(200), generated_at = 200, staged_at = 250 }
    -- guild roster/officer-note perms take a couple of ticks to load after login
    WowStub.officerKnownAfterCalls = 3
    SideQuest.Fire("PLAYER_ENTERING_WORLD")
    assertEq(SideQuestDB.inbox, nil, "inbox cleared once officer status resolves")
    assertEq(SideQuestDB.standings.generated_at, 200, "staged import applied once officer status was known")
    assertTrue(WowStub.officerNoteCalls >= 3, "retried until officer status was known")
end)

--------------------------------------------------------------------------
-- 10. Battleground scoreboards
--------------------------------------------------------------------------

local function simScoreRow(name, overrides)
    local row = {
        name = name, guid = "Player-1-" .. name, faction = 1, raceName = "Dwarf",
        gender = 2, className = "Warrior", classToken = "WARRIOR",
        killingBlows = 3, honorableKills = 12, deaths = 2, honorGained = 140,
        damageDone = 45000, healingDone = 1200, rating = 0, ratingChange = 0,
        prematchMMR = 0, mmrChange = 0, postmatchMMR = 0, talentSpec = "", honorLevel = 1,
        roleAssigned = 0, stats = {},
    }
    for k, v in pairs(overrides or {}) do
        row[k] = v
    end
    return row
end

test("battlegrounds: records one match after PVP_MATCH_COMPLETE + the next score update", function()
    resetAddon()
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Zach", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
    WowStub.instance = { inInstance = true, instanceType = "pvp", instanceID = 489, difficultyID = 1, name = "Warsong Gulch" }
    WowStub.pvp.myFaction = "Alliance"
    WowStub.pvp.winner = 1
    WowStub.pvp.duration = 1234
    WowStub.pvp.scores = {
        simScoreRow("Zach"),
        simScoreRow("Enemy1", { faction = 0, classToken = "MAGE", raceName = "Troll" }),
    }

    SideQuest.Fire("PVP_MATCH_COMPLETE", 1, 1234)
    assertEq(WowStub.pvp.scoreRequests, 1, "score data was requested on completion")
    assertEq(#SideQuestDB.pending.battlegrounds, 0, "nothing recorded until the score update arrives")

    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    assertEq(#SideQuestDB.pending.battlegrounds, 1, "one match recorded")
    local match = SideQuestDB.pending.battlegrounds[1]
    assertEq(match.id, "Zach-" .. tostring(WowStub.time), "id is recorder name + ended_at")
    assertEq(match.map, "Warsong Gulch", "map from GetInstanceInfo")
    assertEq(match.instance_id, 489, "instance_id from GetInstanceInfo")
    assertEq(match.winner, "alliance", "winner 1 maps to alliance")
    assertEq(match.my_faction, "alliance", "my_faction from UnitFactionGroup")
    assertEq(match.duration, 1234, "duration from C_PvP.GetActiveMatchDuration")
    assertEq(#match.players, 2, "both score rows kept")
    assertEq(match.players[1].name, "Zach", "first player name")
    assertEq(match.players[1].faction, "alliance", "faction 1 maps to alliance")
    assertEq(match.players[1].class, "WARRIOR", "classToken kept")
    assertEq(match.players[1].killing_blows, 3, "killing_blows kept")
    assertEq(match.players[2].faction, "horde", "faction 0 maps to horde")
end)

test("battlegrounds: nothing recorded while the match is still active (secret scores, no complete yet)", function()
    resetAddon()
    WowStub.SetUnit("player", { name = "Zach", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
    WowStub.pvp.scores = {
        simScoreRow("Zach", {
            killingBlows = WowStub.SECRET, honorableKills = WowStub.SECRET, deaths = WowStub.SECRET,
            honorGained = WowStub.SECRET, damageDone = WowStub.SECRET, healingDone = WowStub.SECRET,
        }),
    }

    -- UPDATE_BATTLEFIELD_SCORE fires repeatedly while the match is live; without a prior
    -- PVP_MATCH_COMPLETE, the addon never reads the (secret) scoreboard at all.
    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    assertEq(#SideQuestDB.pending.battlegrounds, 0, "nothing recorded while active")
end)

test("battlegrounds: an unreadable scoreboard skips the match entirely", function()
    resetAddon()
    WowStub.SetUnit("player", { name = "Zach", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
    WowStub.pvp.scores = {
        simScoreRow("Zach", { name = WowStub.SECRET }),
        simScoreRow("Enemy1", { name = WowStub.SECRET }),
    }

    SideQuest.Fire("PVP_MATCH_COMPLETE", nil, 0)
    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    assertEq(#SideQuestDB.pending.battlegrounds, 0, "match skipped: every row's name was secret")
end)

test("battlegrounds: repeated score updates for the same match never duplicate", function()
    resetAddon()
    WowStub.SetUnit("player", { name = "Zach", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
    WowStub.pvp.scores = { simScoreRow("Zach") }

    SideQuest.Fire("PVP_MATCH_COMPLETE", 1, 60)
    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    assertEq(#SideQuestDB.pending.battlegrounds, 1, "only recorded once despite repeated score events")
end)

test("battlegrounds: pending caps at 50, dropping the oldest", function()
    resetAddon()
    WowStub.SetUnit("player", { name = "Zach", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
    local baseTime = WowStub.time
    for _ = 1, 55 do
        WowStub.Advance(10)
        WowStub.pvp.scores = { simScoreRow("Zach") }
        SideQuest.Fire("PVP_MATCH_COMPLETE", 1, 60)
        SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")
    end
    local list = SideQuestDB.pending.battlegrounds
    assertEq(#list, 50, "capped at 50")
    assertEq(list[1].id, "Zach-" .. tostring(baseTime + 6 * 10), "oldest 5 matches dropped")
    assertEq(list[50].id, "Zach-" .. tostring(baseTime + 55 * 10), "newest match kept")
end)

test("battlegrounds: export shape matches the contract", function()
    resetAddon()
    WowStub.realm = "Whitemane"
    WowStub.SetUnit("player", { name = "Zach", realm = "Whitemane", class = "WARRIOR", guid = "Player-1-AAAA0001" })
    WowStub.instance = { inInstance = true, instanceType = "pvp", instanceID = 489, difficultyID = 1, name = "Warsong Gulch" }
    WowStub.pvp.myFaction = "Alliance"
    WowStub.pvp.winner = 1
    WowStub.pvp.duration = 1234
    WowStub.pvp.scores = { simScoreRow("Zach") }

    SideQuest.Fire("PVP_MATCH_COMPLETE", 1, 1234)
    SideQuest.Fire("UPDATE_BATTLEFIELD_SCORE")

    local str = SideQuest.Sync.BuildExport()
    local decoded = SideQuest.Codec.DecodeExport(str)
    assertEq(#decoded.battlegrounds, 1, "battlegrounds present in export")
    local match = decoded.battlegrounds[1]
    assertEq(match.map, "Warsong Gulch", "map in export")
    assertEq(match.winner, "alliance", "winner in export")
    assertEq(match.my_faction, "alliance", "my_faction in export")
    assertEq(#match.players, 1, "players present in export")
    assertEq(match.players[1].name, "Zach", "player name in export")

    local fixturePath = ROOT .. "tests/fixtures/export_v2_battlegrounds.txt"
    local fh = io.open(fixturePath, "w")
    fh:write(str)
    fh:close()
end)

--------------------------------------------------------------------------
-- more suites: every tests/test_*.lua file, called with the helpers above
--------------------------------------------------------------------------

do
    local helpers = { test = test, assertEq = assertEq, assertTrue = assertTrue, resetAddon = resetAddon }
    local listing = io.popen('ls "' .. SCRIPT_DIR .. '"')
    local suites = {}
    for name in listing:lines() do
        if name:match("^test_.+%.lua$") then
            table.insert(suites, name)
        end
    end
    listing:close()
    table.sort(suites)
    for _, name in ipairs(suites) do
        dofile(SCRIPT_DIR .. name)(helpers)
    end
end

--------------------------------------------------------------------------
-- run
--------------------------------------------------------------------------

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passCount = passCount + 1
        print("ok   - " .. t.name)
    else
        table.insert(failures, { name = t.name, err = err })
        print("FAIL - " .. t.name .. ": " .. tostring(err))
    end
end

print(string.format("\n%d passed, %d failed", passCount, #failures))
if #failures > 0 then
    WowStub.os.exit(1)
end
