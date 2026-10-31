-- SideQuest/Professions.lua
-- Profession scan (contract v2 "professions" + directory "prof" section). Forever runs the Mainline 12.x
-- API: the Classic globals (GetTradeSkillLine, GetSkillLineInfo, ...) are gone. Passive skill/skill cap
-- reads use GetProfessions/GetProfessionInfo (falling back to C_SkillInfo); known recipes are read from
-- C_TradeSkillUI only while a profession window is open, and kept between passive scans.

SideQuest = SideQuest or {}
SideQuest.Professions = {}
local Professions = SideQuest.Professions

local function now()
    return GetServerTime and GetServerTime() or 0
end

-- Keyed by profession name: { name, skill_line, skill, max_skill, recipes (detailed, nil until a window
-- was opened once), recipes_at }.
local profState = {}

local function professionLookup()
    local out = {}
    for _, p in ipairs(SideQuest.Data.PROFESSIONS or {}) do
        out[p.name] = p
    end
    return out
end

function Professions.HasModernAPI()
    return C_TradeSkillUI ~= nil
        and type(C_TradeSkillUI.GetAllRecipeIDs) == "function"
        and type(C_TradeSkillUI.GetRecipeInfo) == "function"
end

function Professions.IsAvailable()
    return type(GetProfessions) == "function" or Professions.HasModernAPI()
        or (C_SkillInfo ~= nil and type(C_SkillInfo.GetNumSkillLines) == "function")
end

--------------------------------------------------------------------------
-- Passive scan: skill/max skill for every profession the character has,
-- primary and secondary. Never touches `recipes` for a profession it
-- already knows about.
--------------------------------------------------------------------------

local function mergeSkill(name, skillLine, skill, maxSkill)
    local existing = profState[name]
    profState[name] = {
        name = name,
        skill_line = skillLine or (existing and existing.skill_line),
        skill = skill or 0,
        max_skill = maxSkill or 0,
        recipes = existing and existing.recipes or nil,
        recipes_at = existing and existing.recipes_at or nil,
    }
end

local function scanPassiveModern()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return false
    end
    local p1, p2, arch, fish, cook = GetProfessions()
    local slots = { p1, p2, arch, fish, cook }
    local any = false
    for i = 1, 5 do
        local index = slots[i]
        if index then
            local name, _, skillLevel, maxSkillLevel, _, _, skillLine = GetProfessionInfo(index)
            if name and name ~= "" then
                any = true
                mergeSkill(name, skillLine, skillLevel, maxSkillLevel)
            end
        end
    end
    return any
end

local function scanPassiveFallback()
    if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo) then
        return false
    end
    local known = professionLookup()
    local any = false
    local ok, numLines = pcall(C_SkillInfo.GetNumSkillLines)
    if not ok or not numLines then
        return false
    end
    for i = 1, numLines do
        local ok2, name, isHeader, _, skillRank, _, skillMaxRank = pcall(C_SkillInfo.GetSkillLineInfo, i)
        if ok2 and name and not isHeader and known[name] then
            any = true
            mergeSkill(name, known[name].skill_line, skillRank, skillMaxRank)
        end
    end
    return any
end

--------------------------------------------------------------------------
-- Publish: push the full `prof` section to the directory, and keep feeding
-- the legacy per-character pending.professions export for older sites.
--------------------------------------------------------------------------

local function publish()
    local professions = {}
    for _, row in pairs(profState) do
        local entry = {
            name = row.name,
            skill_line = row.skill_line,
            skill = row.skill,
            max_skill = row.max_skill,
        }
        if row.recipes then
            local ids = {}
            for _, r in ipairs(row.recipes) do
                table.insert(ids, r.id)
            end
            entry.recipes = ids
            entry.recipes_at = row.recipes_at
        end
        table.insert(professions, entry)
    end
    table.sort(professions, function(a, b)
        return a.name < b.name
    end)
    SideQuest.Directory.SetMine("prof", { professions = professions })

    local character = SideQuest.NormalizeUnit("player")
    if not character then
        return
    end
    for _, row in pairs(profState) do
        local legacyRow = {
            character = character,
            profession = row.name,
            skill = row.skill,
            max_skill = row.max_skill,
            scanned_at = now(),
            recipes = row.recipes or {},
        }
        local key = character .. "|" .. row.name
        SideQuestDB.professions[key] = legacyRow
        local queue = SideQuestDB.pending.professions
        local replaced = false
        for i, existingRow in ipairs(queue) do
            if existingRow.character == character and existingRow.profession == row.name then
                queue[i] = legacyRow
                replaced = true
                break
            end
        end
        if not replaced then
            table.insert(queue, legacyRow)
        end
    end
end

function Professions.ScanPassive()
    local changed = scanPassiveModern()
    if not changed then
        changed = scanPassiveFallback()
    end
    if changed then
        publish()
        SideQuest.Fire("SQ_PROFESSION_SCANNED")
    end
    return changed
end

--------------------------------------------------------------------------
-- Recipe scan: only while a (non-linked, non-guild) profession window is open.
--------------------------------------------------------------------------

local function openProfessionInfo()
    if not Professions.HasModernAPI() then
        return nil
    end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
        return nil
    end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then
        return nil
    end

    local info = nil
    if C_TradeSkillUI.GetChildProfessionInfo then
        local ok, childInfo = pcall(C_TradeSkillUI.GetChildProfessionInfo)
        if ok and childInfo and childInfo.professionID and childInfo.professionID ~= 0 then
            info = childInfo
        end
    end
    if not info and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo and baseInfo.professionID and baseInfo.professionID ~= 0 then
            info = baseInfo
        end
    end
    return info
end

--- Scan the currently open profession window. Returns the stored row, or nil if no window is open, it's
--- a linked/guild view, or the API is unavailable.
function Professions.ScanOpenWindow()
    local info = openProfessionInfo()
    if not info then
        return nil
    end
    local profName = info.professionName or info.skillName
    if not profName or profName == "" then
        return nil
    end

    local recipes = {}
    if C_TradeSkillUI.GetAllRecipeIDs then
        local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if ok and ids then
            for _, recipeId in ipairs(ids) do
                local ok2, recipeInfo = pcall(C_TradeSkillUI.GetRecipeInfo, recipeId)
                if ok2 and recipeInfo and recipeInfo.learned then
                    table.insert(recipes, {
                        id = recipeId,
                        name = recipeInfo.name,
                        item_id = recipeInfo.previewItemID or nil,
                    })
                end
            end
        end
    end

    local existing = profState[profName]
    profState[profName] = {
        name = profName,
        skill_line = info.skillLineID or (existing and existing.skill_line),
        skill = info.skillLevel or (existing and existing.skill) or 0,
        max_skill = info.maxSkillLevel or (existing and existing.max_skill) or 0,
        recipes = recipes,
        recipes_at = now(),
    }
    publish()
    SideQuest.Fire("SQ_PROFESSION_SCANNED", profState[profName])
    return profState[profName]
end

--------------------------------------------------------------------------
-- Optional: seed a `prof` section (skills only, no recipes) for guild
-- members who don't run SideQuest, from the game's own guild profession
-- list. Officer-only, at most once an hour, never overwrites a section
-- its owner already sent.
--------------------------------------------------------------------------

local GUILD_SEED_THROTTLE = 3600
local lastGuildSeed = 0

function Professions.SeedFromGuild()
    if not SideQuest.IsOfficer() then
        return
    end
    if not (C_TradeSkillUI and C_TradeSkillUI.IsGuildTradeSkillsEnabled and C_TradeSkillUI.IsGuildTradeSkillsEnabled()) then
        return
    end
    local nowTs = now()
    if (nowTs - lastGuildSeed) < GUILD_SEED_THROTTLE then
        return
    end
    lastGuildSeed = nowTs
    if type(QueryGuildRecipes) == "function" then
        QueryGuildRecipes()
    end
    if type(GetNumGuildTradeSkill) ~= "function" or type(GetGuildTradeSkillInfo) ~= "function" then
        return
    end
    local ok, total = pcall(GetNumGuildTradeSkill)
    if not ok or not total then
        return
    end
    for i = 1, total do
        local name, playerName, curSkill, maxSkill = GetGuildTradeSkillInfo(i)
        if name and playerName then
            local character = SideQuest.NormalizeName(playerName, GetNormalizedRealmName and GetNormalizedRealmName() or "")
            if character then
                local entry = SideQuestDB.directory[character]
                if not (entry and entry.prof) then
                    entry = entry or {}
                    SideQuestDB.directory[character] = entry
                    local section = { professions = { { name = name, skill = curSkill or 0, max_skill = maxSkill or 0 } } }
                    entry.prof = { v = SideQuest.Directory.Hash(section), at = now(), d = section, relayed = true }
                    entry.seen_at = now()
                    SideQuest.Fire("SQ_DIRECTORY_UPDATED", character, "prof")
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- Triggers
--------------------------------------------------------------------------

SideQuest.On("TRADE_SKILL_SHOW", function()
    SideQuest.WhenOutOfCombat(Professions.ScanOpenWindow)
end)
SideQuest.RegisterGameEvent("TRADE_SKILL_SHOW")

SideQuest.On("TRADE_SKILL_LIST_UPDATE", function()
    SideQuest.WhenOutOfCombat(Professions.ScanOpenWindow)
end)
SideQuest.RegisterGameEvent("TRADE_SKILL_LIST_UPDATE")

SideQuest.On("SKILL_LINES_CHANGED", function()
    SideQuest.WhenOutOfCombat(Professions.ScanPassive)
end)
SideQuest.RegisterGameEvent("SKILL_LINES_CHANGED")

SideQuest.On("PLAYER_ENTERING_WORLD", function()
    SideQuest.WhenOutOfCombat(Professions.ScanPassive)
end)

SideQuest.On("GUILD_ROSTER_UPDATE", function()
    SideQuest.WhenOutOfCombat(Professions.SeedFromGuild)
end)

return Professions
