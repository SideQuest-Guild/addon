-- SideQuest/Character.lua
-- Collects this character's "char" and "cd" directory sections. See docs/directory.md.

SideQuest = SideQuest or {}
SideQuest.Character = SideQuest.Character or {}
local Character = SideQuest.Character

--------------------------------------------------------------------------
-- char
--------------------------------------------------------------------------

local function questDone(questIds)
    if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then
        return false
    end
    for _, id in ipairs(questIds or {}) do
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        if ok and done then
            return true
        end
    end
    return false
end

local function collectAttunements()
    local out = {}
    for key, def in pairs(SideQuest.Data.ATTUNEMENTS or {}) do
        if questDone(def.quest_ids) then
            table.insert(out, key)
        end
    end
    table.sort(out)
    return out
end

local function collectReputations()
    local out = {}
    if not (C_Reputation and C_Reputation.GetFactionDataByID) then
        return out
    end
    for _, def in ipairs(SideQuest.Data.REPUTATIONS or {}) do
        local ok, info = pcall(C_Reputation.GetFactionDataByID, def.faction_id)
        if ok and info then
            table.insert(out, {
                faction_id = def.faction_id,
                standing = info.reaction,
                value = info.currentStanding,
            })
        end
    end
    return out
end

local function spec()
    if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then
        return nil
    end
    local ok, index = pcall(C_SpecializationInfo.GetSpecialization)
    if not ok or not index then
        return nil
    end
    local ok2, _, name = pcall(C_SpecializationInfo.GetSpecializationInfo, index)
    if ok2 then
        return name
    end
    return nil
end

local function itemLevel()
    if not GetAverageItemLevel then
        return nil
    end
    local ok, _, equipped = pcall(GetAverageItemLevel)
    if ok and equipped and equipped > 0 then
        return math.floor(equipped * 10 + 0.5) / 10
    end
    return nil
end

--- Build the `char` section's `d` from the current game state. Pure (no store writes).
function Character.CollectChar()
    local level = UnitLevel and UnitLevel("player") or nil
    local classFile = UnitClass and select(2, UnitClass("player")) or nil
    local race = UnitRace and select(2, UnitRace("player")) or nil
    return {
        level = level,
        class = classFile,
        race = race,
        spec = spec(),
        item_level = itemLevel(),
        attunements = collectAttunements(),
        reputations = collectReputations(),
    }
end

function Character.ScanChar()
    SideQuest.WhenOutOfCombat(function()
        SideQuest.Directory.SetMine("char", Character.CollectChar())
    end)
end

--------------------------------------------------------------------------
-- cd: craft cooldowns for entries in SideQuest.Data.COOLDOWNS the character knows.
--------------------------------------------------------------------------

local function knowsCooldown(def)
    for _, spellId in ipairs(def.spell_ids or {}) do
        if C_SpellBook and C_SpellBook.IsSpellKnown then
            local ok, known = pcall(C_SpellBook.IsSpellKnown, spellId)
            if ok and known then
                return true
            end
        end
    end
    if def.item_id and C_Item and C_Item.GetItemCount then
        local ok, count = pcall(C_Item.GetItemCount, def.item_id)
        if ok and count and count > 0 then
            return true
        end
    end
    return false
end

-- Cooldown starts are on the GetTime() clock (seconds since the client
-- started), not server time. Turn the time left into a server time, rounded
-- up to the minute so a rescan a second later hashes the same.
local function readyAtFromCooldown(startTime, duration)
    if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
        return nil
    end
    -- a duration of 2 s or less is the global cooldown, not a craft cooldown
    if type(startTime) ~= "number" or type(duration) ~= "number" or duration <= 2 or not GetTime then
        return nil
    end
    local left = startTime + duration - GetTime()
    if left <= 0 then
        return nil
    end
    local readyAt = (GetServerTime and GetServerTime() or 0) + left
    return math.ceil(readyAt / 60) * 60
end

local function cooldownReadyAt(def)
    for _, spellId in ipairs(def.spell_ids or {}) do
        if C_Spell and C_Spell.GetSpellCooldown then
            -- Mainline returns a SpellCooldownInfo table; older clients a tuple.
            local ok, first, second = pcall(C_Spell.GetSpellCooldown, spellId)
            if ok and type(first) == "table" then
                first, second = first.startTime, first.duration
            end
            local readyAt = ok and readyAtFromCooldown(first, second)
            if readyAt then
                return readyAt
            end
        end
    end
    if def.item_id and C_Item and C_Item.GetItemCooldown then
        local ok, startTime, duration = pcall(C_Item.GetItemCooldown, def.item_id)
        local readyAt = ok and readyAtFromCooldown(startTime, duration)
        if readyAt then
            return readyAt
        end
    end
    return 0
end

--- Build the `cd` section's `d` from the current game state. Pure (no store writes).
function Character.CollectCooldowns()
    local out = {}
    for key, def in pairs(SideQuest.Data.COOLDOWNS or {}) do
        if knowsCooldown(def) then
            table.insert(out, { key = key, ready_at = cooldownReadyAt(def) })
        end
    end
    table.sort(out, function(a, b)
        return a.key < b.key
    end)
    return { cooldowns = out }
end

function Character.ScanCooldowns()
    SideQuest.WhenOutOfCombat(function()
        SideQuest.Directory.SetMine("cd", Character.CollectCooldowns())
    end)
end

--------------------------------------------------------------------------
-- Triggers
--------------------------------------------------------------------------

SideQuest.On("PLAYER_ENTERING_WORLD", function()
    Character.ScanChar()
    Character.ScanCooldowns()
end)
SideQuest.On("PLAYER_LEVEL_UP", Character.ScanChar)
SideQuest.RegisterGameEvent("PLAYER_LEVEL_UP")
SideQuest.On("PLAYER_EQUIPMENT_CHANGED", Character.ScanChar)
SideQuest.RegisterGameEvent("PLAYER_EQUIPMENT_CHANGED")
SideQuest.On("QUEST_TURNED_IN", Character.ScanChar)
SideQuest.RegisterGameEvent("QUEST_TURNED_IN")
SideQuest.On("UPDATE_FACTION", Character.ScanChar)
SideQuest.RegisterGameEvent("UPDATE_FACTION")
SideQuest.On("PLAYER_SPECIALIZATION_CHANGED", Character.ScanChar)
SideQuest.RegisterGameEvent("PLAYER_SPECIALIZATION_CHANGED")
SideQuest.On("SPELL_UPDATE_COOLDOWN", Character.ScanCooldowns)
SideQuest.RegisterGameEvent("SPELL_UPDATE_COOLDOWN")
SideQuest.On("BAG_UPDATE_COOLDOWN", Character.ScanCooldowns)
SideQuest.RegisterGameEvent("BAG_UPDATE_COOLDOWN")

return Character
