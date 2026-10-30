-- SideQuest/Professions.lua
-- Profession scan (contract v2 "professions"): runs when the player opens a
-- profession/trade-skill window. Profession recipe APIs are unverified on
-- Forever per the researched addon facts; this module detects the modern
-- C_TradeSkillUI surface, falls back to the legacy global API, and degrades
-- silently (no export row, UI says so) when neither exists.

SideQuest = SideQuest or {}
SideQuest.Professions = {}
local Professions = SideQuest.Professions

local function now()
    return GetServerTime and GetServerTime() or 0
end

function Professions.HasModernAPI()
    return C_TradeSkillUI ~= nil
        and type(C_TradeSkillUI.GetTradeSkillLine) == "function"
        and type(C_TradeSkillUI.GetAllRecipeIDs) == "function"
        and type(C_TradeSkillUI.GetRecipeInfo) == "function"
end

function Professions.HasLegacyAPI()
    return type(GetTradeSkillLine) == "function"
        and type(GetNumTradeSkills) == "function"
        and type(GetTradeSkillInfo) == "function"
end

function Professions.IsAvailable()
    return Professions.HasModernAPI() or Professions.HasLegacyAPI()
end

local function scanModern()
    local name, skill, maxSkill = C_TradeSkillUI.GetTradeSkillLine()
    if not name or name == "" then
        return nil
    end
    local recipes = {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and info.learned then
            table.insert(recipes, {
                id = recipeID,
                name = info.name,
                item_id = info.previewItemID or nil,
            })
        end
    end
    return name, skill or 0, maxSkill or 0, recipes
end

local function scanLegacy()
    local name, skill, maxSkill = GetTradeSkillLine()
    if not name or name == "" then
        return nil
    end
    local recipes = {}
    for i = 1, GetNumTradeSkills() do
        local recipeName, recipeType, _, _, _, skillID = GetTradeSkillInfo(i)
        if recipeType ~= "header" and recipeName then
            table.insert(recipes, { id = skillID or i, name = recipeName })
        end
    end
    return name, skill or 0, maxSkill or 0, recipes
end

--- Scan the currently open profession window. Returns the stored row, or
-- nil if no profession window is open or the API is unavailable.
function Professions.ScanOpenWindow()
    if not Professions.IsAvailable() then
        return nil
    end
    local profName, skill, maxSkill, recipes
    if Professions.HasModernAPI() then
        profName, skill, maxSkill, recipes = scanModern()
    else
        profName, skill, maxSkill, recipes = scanLegacy()
    end
    if not profName then
        return nil
    end

    local character = SideQuest.NormalizeUnit("player")
    local row = {
        character = character,
        profession = profName,
        skill = skill,
        max_skill = maxSkill,
        scanned_at = now(),
        recipes = recipes,
    }

    local key = character .. "|" .. profName
    SideQuestDB.professions[key] = row

    -- queue for export: replace any existing queued row for this pair
    local queue = SideQuestDB.pending.professions
    local replaced = false
    for i, existing in ipairs(queue) do
        if existing.character == character and existing.profession == profName then
            queue[i] = row
            replaced = true
            break
        end
    end
    if not replaced then
        table.insert(queue, row)
    end

    SideQuest.Fire("SQ_PROFESSION_SCANNED", row)
    return row
end

SideQuest.On("TRADE_SKILL_SHOW", function()
    Professions.ScanOpenWindow()
end)
SideQuest.RegisterGameEvent("TRADE_SKILL_SHOW")

return Professions
