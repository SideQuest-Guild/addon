-- SideQuest/Prep.lua
-- Raid prep (contract v2 PREP_Q/PREP_A): consumable buffs, durability,
-- reagent counts and required-addon checks; plus HELLO (addon version, for
-- the "missing addon" check) and invite-from-chart with group placement.
-- Aura/durability/reagent APIs are read through SQ.Unsecret-guarded calls
-- since unit auras and item counts can be secret values on Midnight.

SideQuest = SideQuest or {}
SideQuest.Prep = {}
local Prep = SideQuest.Prep

local function now()
    return GetServerTime and GetServerTime() or 0
end

-- Best-effort name match for the two consumable families the contract asks
-- about; a real spell-id database is out of scope, so this degrades to
-- "unknown, check manually" rather than guessing wrong.
local FLASK_ELIXIR_PATTERN = "[Ff]lask"
local FOOD_PATTERN = "[Ww]ell [Ff]ed"

local function scanOwnBuffs()
    local result = { flask = false, food = false, known = false }
    local getAura = (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) or nil
    if not getAura and not UnitBuff then
        return result -- no aura API available at all; UI must say "unknown"
    end
    result.known = true
    local i = 1
    while true do
        local name
        if getAura then
            local aura = getAura("player", i, "HELPFUL")
            if not aura then break end
            name = SideQuest.Unsecret(aura.name)
        else
            name = SideQuest.Unsecret((UnitBuff("player", i)))
            if not name then break end
        end
        if name then
            if name:find(FLASK_ELIXIR_PATTERN) then
                result.flask = true
            elseif name:find(FOOD_PATTERN) then
                result.food = true
            end
        end
        i = i + 1
        if i > 40 then break end -- safety cap
    end
    return result
end

local function scanDurability()
    local getDurability = GetInventoryItemDurability
    if not getDurability and not (C_DurabilityInfo and C_DurabilityInfo.GetSlotDurability) then
        return nil -- unknown; UI shows "check manually"
    end
    local totalCur, totalMax = 0, 0
    for slot = 1, 19 do
        local cur, max
        if C_DurabilityInfo and C_DurabilityInfo.GetSlotDurability then
            cur, max = C_DurabilityInfo.GetSlotDurability(slot)
        else
            cur, max = getDurability(slot)
        end
        if cur and max and max > 0 then
            totalCur = totalCur + cur
            totalMax = totalMax + max
        end
    end
    if totalMax == 0 then
        return nil
    end
    return math.floor((totalCur / totalMax) * 100 + 0.5)
end

local function scanReagents(itemIds)
    local counts = {}
    if not (C_Item and C_Item.GetItemCount) then
        return counts -- empty: unknown, UI says so
    end
    for _, itemId in ipairs(itemIds or {}) do
        local count = SideQuest.Unsecret(C_Item.GetItemCount(itemId))
        counts[tostring(itemId)] = count or 0
    end
    return counts
end

--------------------------------------------------------------------------
-- HELLO: addon version broadcast, for the "missing addon" check
--------------------------------------------------------------------------

function Prep.SayHello()
    SideQuest.Comm.SendHello({ character = SideQuest.NormalizeUnit("player"), version = SideQuest.ADDON_VERSION, at = now() })
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, _sender)
    if msgType ~= "HELLO" then
        return
    end
    local ok, hello = pcall(SideQuestJSON.decode, payload)
    if ok then
        SideQuestDB.addonVersions[hello.character] = { version = hello.version, seenAt = now() }
    end
end)

SideQuest.On("SQ_READY", function()
    Prep.SayHello()
end)

--- Which raid members have not been seen saying HELLO recently (addon
-- missing or out of date); `raidCharacters` is a list of normalized names.
function Prep.MissingAddon(raidCharacters, maxAgeSeconds)
    maxAgeSeconds = maxAgeSeconds or 3600
    local missing = {}
    for _, char in ipairs(raidCharacters) do
        local seen = SideQuestDB.addonVersions[char]
        if not seen or (now() - seen.seenAt) > maxAgeSeconds then
            table.insert(missing, char)
        end
    end
    return missing
end

--------------------------------------------------------------------------
-- PREP_Q / PREP_A
--------------------------------------------------------------------------

--- Officer action: ask the raid to report readiness. `reagentItemIds` is
-- an optional list of item ids the raid leader wants counts for.
function Prep.RequestCheck(reagentItemIds)
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can request a prep check.")
        return nil
    end
    SideQuestDB.prepAnswers = {} -- a new check replaces the old answers
    local id = SideQuest.NextId()
    SideQuest.Comm.SendPrepQuery({ id = id, reagents = reagentItemIds or {}, at = now() })
    SideQuest.Fire("SQ_PREP_REQUESTED", id)
    return id
end

function Prep.Answers()
    return SideQuestDB.prepAnswers
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, sender)
    if msgType == "PREP_Q" then
        local ok, req = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        local buffs = scanOwnBuffs()
        local durability = scanDurability()
        local reagents = scanReagents(req.reagents)
        SideQuest.Comm.SendPrepAnswer({
            id = req.id,
            character = SideQuest.NormalizeUnit("player"),
            flask = buffs.known and buffs.flask or nil,
            food = buffs.known and buffs.food or nil,
            buffs_known = buffs.known,
            durability = durability,
            reagents = reagents,
            addon_version = SideQuest.ADDON_VERSION,
            at = now(),
        })
    elseif msgType == "PREP_A" then
        local ok, ans = pcall(SideQuestJSON.decode, payload)
        if ok and SideQuest.IsOfficer() then
            SideQuestDB.prepAnswers[ans.character] = ans
            SideQuest.Fire("SQ_PREP_ANSWER", ans)
        end
    end
end)

--------------------------------------------------------------------------
-- Invite-from-chart with group placement (out of combat only)
--------------------------------------------------------------------------

--- Place every signed, non-benched sign-up from the event into its
-- assigned raid subgroup (contract: SetRaidSubgroup/SwapRaidSubgroup, out
-- of combat only). Must run after Events.InviteSigned has gotten everyone
-- into the raid; placement itself is deferred to out-of-combat too, since
-- it can run moments after an invite flurry during a pull.
function Prep.PlaceGroups(eventId)
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can place the raid into groups.")
        return
    end
    local evt = SideQuest.Events.Find(eventId)
    if not evt then
        SideQuest.Print("Unknown event " .. tostring(eventId))
        return
    end
    if not (SetRaidSubgroup and GetNumGroupMembers) then
        SideQuest.Print("Group placement API unavailable; place groups manually from the raid frame.")
        return
    end

    SideQuest.WhenOutOfCombat(function()
        local roster = SideQuest.Events.SignedRoster(evt)
        local wanted = {} -- normalized name -> desired subgroup
        for _, signup in ipairs(roster) do
            if signup.group then
                wanted[signup.character] = signup.group
            end
        end
        local placed = 0
        local total = GetNumGroupMembers()
        for i = 1, total do
            local unit = "raid" .. i
            local name = SideQuest.NormalizeUnit(unit)
            local targetGroup = name and wanted[name]
            if targetGroup then
                if SetRaidSubgroup(i, targetGroup) then
                    placed = placed + 1
                end
            end
        end
        SideQuest.Print("Placed " .. placed .. " raider(s) into their chart groups.")
        SideQuest.Fire("SQ_GROUPS_PLACED", eventId, placed)
    end)
end

return Prep
