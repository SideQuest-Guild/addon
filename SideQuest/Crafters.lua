-- SideQuest/Crafters.lua
-- Crafter directory (contract v2 "professions"/"crafters"): find who can
-- craft a recipe. Online crafters answer a CRAFT_Q from their own scan;
-- one officer answers once more for offline crafters from the imported
-- on-demand "crafters" list, so an answer never fires twice for the same
-- offline set.

SideQuest = SideQuest or {}
SideQuest.Crafters = {}
local Crafters = SideQuest.Crafters

local function now()
    return GetServerTime and GetServerTime() or 0
end

local function matches(haystack, needle)
    if not haystack then
        return false
    end
    return haystack:lower():find(needle:lower(), 1, true) ~= nil
end

--- Member action: search for a recipe or profession by substring.
function Crafters.Query(text)
    local payload = { id = SideQuest.NextId(), query = text, at = now() }
    SideQuest.Comm.SendCraftQuery(payload)
    Crafters.results = {}
    SideQuest.Fire("SQ_CRAFT_QUERY_SENT", payload.id)
    return payload.id
end

--- My own live scans that match a query string (used to answer CRAFT_Q).
local function myMatches(query)
    local character = SideQuest.NormalizeUnit("player")
    local matchedRecipes = {}
    local profession, skill
    for key, row in pairs(SideQuestDB.professions) do
        if row.character == character then
            if matches(row.profession, query) then
                profession = row.profession
                skill = row.skill
            end
            for _, recipe in ipairs(row.recipes or {}) do
                if matches(recipe.name, query) then
                    table.insert(matchedRecipes, recipe)
                    profession = profession or row.profession
                    skill = skill or row.skill
                end
            end
        end
    end
    if not profession then
        return nil
    end
    return { profession = profession, skill = skill, recipes = matchedRecipes }
end

--- Offline/imported crafters matching a query, from the on-demand import.
local function offlineMatches(query)
    local out = {}
    for _, row in ipairs(SideQuestDB.onDemand.crafters) do
        local hitRecipes = {}
        for _, recipeId in ipairs(row.recipes or {}) do
            local name = SideQuestDB.onDemand.recipe_names[tostring(recipeId)]
            if name and matches(name, query) then
                table.insert(hitRecipes, { id = recipeId, name = name })
            end
        end
        if matches(row.profession, query) or #hitRecipes > 0 then
            table.insert(out, {
                character = row.character,
                member_id = row.member_id,
                profession = row.profession,
                skill = row.skill,
                recipes = hitRecipes,
            })
        end
    end
    return out
end

Crafters.results = {} -- current answers for the in-flight query, by character

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, sender)
    if msgType == "CRAFT_Q" then
        local ok, req = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        local mine = myMatches(req.query)
        if mine then
            SideQuest.Comm.ScheduleAnswer("CRAFT:" .. req.id .. ":" .. SideQuest.NormalizeUnit("player"), function()
                SideQuest.Comm.SendCraftAnswer({
                    id = req.id,
                    character = SideQuest.NormalizeUnit("player"),
                    profession = mine.profession,
                    skill = mine.skill,
                    recipes = mine.recipes,
                    online = true,
                })
            end)
        end
        if SideQuest.IsOfficer() then
            SideQuest.Comm.ScheduleAnswer("CRAFT_OFFLINE:" .. req.id, function()
                SideQuest.Comm.SendCraftAnswer({
                    id = req.id,
                    offline = true,
                    results = offlineMatches(req.query),
                })
            end)
        end
    elseif msgType == "CRAFT_A" then
        local ok, ans = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        if ans.offline then
            -- one officer's aggregate offline answer suppresses any other officer's
            SideQuest.Comm.SuppressAnswer("CRAFT_OFFLINE:" .. ans.id)
            for _, row in ipairs(ans.results or {}) do
                Crafters.results[row.character] = row
            end
        else
            SideQuest.Comm.SuppressAnswer("CRAFT:" .. ans.id .. ":" .. (ans.character or ""))
            Crafters.results[ans.character] = ans
        end
        SideQuest.Fire("SQ_CRAFT_ANSWER", ans)
    end
end)

return Crafters
