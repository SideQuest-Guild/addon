-- SideQuest/Codec.lua
-- Builds/encodes the "SQX1:" export string from pending SavedVariables data,
-- and decodes the "SQI1:" import string from the site.

SideQuest = SideQuest or {}
SideQuest.Codec = {}
local Codec = SideQuest.Codec

local EXPORT_PREFIX = "SQX1:"
local IMPORT_PREFIX = "SQI1:"

Codec.EXPORT_PREFIX = EXPORT_PREFIX
Codec.IMPORT_PREFIX = IMPORT_PREFIX

local function arr(t)
    -- mark a Lua array table so SideQuestJSON always encodes it as `[]`,
    -- even when empty.
    if #t == 0 then
        return SideQuestJSON.EMPTY_ARRAY
    end
    return t
end

local function copy(row)
    local out = {}
    for k, v in pairs(row) do
        out[k] = v
    end
    return out
end

-- Sessions keep members keyed by "Name-Realm" for fast roster updates; the contract wants a list.
local function exportSessions(sessions)
    local out = {}
    for _, session in ipairs(sessions) do
        local row = copy(session)
        local names = {}
        for name in pairs(session.members or {}) do
            table.insert(names, name)
        end
        table.sort(names)
        local members = {}
        for _, name in ipairs(names) do
            table.insert(members, session.members[name])
        end
        row.members = arr(members)
        table.insert(out, row)
    end
    return out
end

-- An empty Lua table would encode as `{}`; the character lists must stay arrays.
local function exportEncounters(encounters)
    local out = {}
    for _, encounter in ipairs(encounters) do
        local row = copy(encounter)
        row.characters = arr(encounter.characters or {})
        row.standby = arr(encounter.standby or {})
        table.insert(out, row)
    end
    return out
end
-- Professions keep recipes as a sub-array per entry; ensure it stays `[]` when empty.
local function exportProfessions(professions)
    local out = {}
    for _, row in ipairs(professions) do
        local copied = copy(row)
        copied.recipes = arr(row.recipes or {})
        table.insert(out, copied)
    end
    return out
end

-- Recruits keep votes as a sub-array and checklist as an object map.
local function exportRecruits(recruits)
    local out = {}
    for _, row in ipairs(recruits) do
        local copied = copy(row)
        copied.votes = arr(row.votes or {})
        copied.checklist = row.checklist or {}
        table.insert(out, copied)
    end
    return out
end

-- Battlegrounds keep their player rows as a sub-array; ensure it stays `[]`
-- when empty (shouldn't happen in practice, since Battlegrounds.lua skips a
-- match with no readable rows, but stay defensive).
local function exportBattlegrounds(battlegrounds)
    local out = {}
    for _, row in ipairs(battlegrounds) do
        local copied = copy(row)
        copied.players = arr(row.players or {})
        table.insert(out, copied)
    end
    return out
end

-- directory.md: every stored record this client holds, newest `at` wins on the site. `d` stays nil
-- (the key is simply absent, like every other optional field this codec already omits) for a section
-- the owner stopped sharing; the site treats an absent `d` the same as the contract's literal `null`.
local DIRECTORY_SECTIONS = { "prof", "char", "cd", "market", "stock" }

local function exportDirectory(directory)
    local out = {}
    for character, entry in pairs(directory or {}) do
        local sections = {}
        local any = false
        for _, section in ipairs(DIRECTORY_SECTIONS) do
            local sec = entry[section]
            if sec then
                sections[section] = { v = sec.v, at = sec.at, d = sec.d }
                any = true
            end
        end
        if any then
            table.insert(out, { character = character, sections = sections })
        end
    end
    return out
end

-- Every item ID and recipe (spell) ID the directory export mentions, so the site can be told their
-- names; item/spell names are static client data, nameable regardless of who holds the directory entry.
local function collectDirectoryIds(directory)
    local itemIds, recipeIds = {}, {}
    for _, entry in pairs(directory or {}) do
        local prof = entry.prof and entry.prof.d
        if prof then
            for _, p in ipairs(prof.professions or {}) do
                for _, recipeId in ipairs(p.recipes or {}) do
                    recipeIds[recipeId] = true
                end
            end
        end
        local market = entry.market and entry.market.d
        if market then
            for _, row in ipairs(market.sell or {}) do
                itemIds[row.item_id] = true
            end
            for _, row in ipairs(market.buy or {}) do
                itemIds[row.item_id] = true
            end
            for _, row in ipairs(market.requests or {}) do
                itemIds[row.item_id] = true
            end
        end
        local stock = entry.stock and entry.stock.d
        if stock then
            for _, row in ipairs(stock.bags or {}) do
                itemIds[row[1]] = true
            end
            for _, row in ipairs(stock.bank or {}) do
                itemIds[row[1]] = true
            end
        end
    end
    return itemIds, recipeIds
end

local function exportItemNames(itemIds)
    local out = {}
    if not (C_Item and C_Item.GetItemNameByID) then
        return out
    end
    for itemId in pairs(itemIds) do
        local ok, name = pcall(C_Item.GetItemNameByID, itemId)
        if ok and name then
            out[tostring(itemId)] = name
        end
    end
    return out
end

local function exportRecipeNames(recipeIds)
    local out = {}
    if not (C_Spell and C_Spell.GetSpellName) then
        return out
    end
    for recipeId in pairs(recipeIds) do
        local ok, name = pcall(C_Spell.GetSpellName, recipeId)
        if ok and name then
            out[tostring(recipeId)] = name
        end
    end
    return out
end

--- Build the export payload table (contract-shaped) from the addon's pending
--- data. Does not mutate SideQuestDB; callers decide when to clear `pending`.
-- @param recorderName string normalized "Name-Realm" of the recorder
-- @param guildName string
-- @param realmName string
function Codec.BuildExportPayload(recorderName, guildName, realmName)
    local db = SideQuestDB
    local pending = db.pending or { sessions = {}, encounters = {}, loot = {}, awards = {} }

    local payload = {
        v = 2,
        addon_version = SideQuest.ADDON_VERSION,
        exported_at = GetServerTime and GetServerTime() or 0,
        guild = guildName or "",
        realm = realmName or "",
        recorder = recorderName or "",
        sessions = arr(exportSessions(pending.sessions)),
        encounters = arr(exportEncounters(pending.encounters)),
        loot = arr(pending.loot),
        awards = arr(pending.awards),
        -- v2 sections: every one is optional per the site, but the addon
        -- always sends the arrays it has (even empty) for a stable shape.
        professions = arr(exportProfessions(pending.professions or {})),
        signups = arr(pending.signups or {}),
        bank = arr(pending.bank or {}),
        announcements = arr(pending.announcements or {}),
        recruits = arr(exportRecruits(pending.recruits or {})),
        member_notes = arr(pending.member_notes or {}),
        battlegrounds = arr(exportBattlegrounds(pending.battlegrounds or {})),
        guild_log = arr(pending.guild_log or {}),
        recruit_payouts_paid = arr(pending.recruit_payouts_paid or {}),
        directory = arr(exportDirectory(db.directory or {})),
    }
    if pending.roster then
        payload.roster = { taken_at = pending.roster.taken_at, members = arr(pending.roster.members or {}) }
        if pending.roster.ranks then
            payload.roster.ranks = arr(pending.roster.ranks)
        end
    end
    do
        local itemIds, recipeIds = collectDirectoryIds(db.directory or {})
        payload.item_names = exportItemNames(itemIds)
        payload.recipe_names = exportRecipeNames(recipeIds)
    end
    return payload
end

--- Build a non-officer's export payload: same v2 envelope shape as
-- Codec.BuildExportPayload, with every officer section forced empty and
-- only the current character's own directory entry and own queued
-- sign-ups included.
-- @param recorderName string normalized "Name-Realm" of the recorder
-- @param guildName string
-- @param realmName string
function Codec.BuildMemberExportPayload(recorderName, guildName, realmName)
    local db = SideQuestDB
    local ownSignups = {}
    for _, row in pairs(db.mySignups or {}) do
        if row.payload then
            table.insert(ownSignups, row.payload)
        end
    end
    local ownDirectory = {}
    if recorderName and db.directory and db.directory[recorderName] then
        ownDirectory[recorderName] = db.directory[recorderName]
    end
    local payload = {
        v = 2,
        addon_version = SideQuest.ADDON_VERSION,
        exported_at = GetServerTime and GetServerTime() or 0,
        guild = guildName or "",
        realm = realmName or "",
        recorder = recorderName or "",
        sessions = arr({}),
        encounters = arr({}),
        loot = arr({}),
        awards = arr({}),
        professions = arr({}),
        signups = arr(ownSignups),
        bank = arr({}),
        announcements = arr({}),
        recruits = arr({}),
        member_notes = arr({}),
        battlegrounds = arr({}),
        guild_log = arr({}),
        recruit_payouts_paid = arr({}),
        directory = arr(exportDirectory(ownDirectory)),
    }
    do
        local itemIds, recipeIds = collectDirectoryIds(ownDirectory)
        payload.item_names = exportItemNames(itemIds)
        payload.recipe_names = exportRecipeNames(recipeIds)
    end
    return payload
end

function Codec.EncodeExport(payload)
    local json = SideQuestJSON.encode(payload)
    return EXPORT_PREFIX .. SideQuestBase64.encode(json)
end

--- Decode any "SQX1:...." string into its JSON payload table. Errors on a
--- malformed prefix/base64/json.
function Codec.DecodeExport(str)
    if type(str) ~= "string" then
        error("Codec.DecodeExport: expected string")
    end
    local b64 = str:match("^" .. EXPORT_PREFIX .. "([A-Za-z0-9+/=]+)$")
    if not b64 then
        error("Codec.DecodeExport: missing/invalid SQX1: prefix")
    end
    local json = SideQuestBase64.decode(b64)
    return SideQuestJSON.decode(json)
end

--- Extract the first SQX1:... token from arbitrary pasted text (e.g. the
--- SavedVariables file body) and decode it.
function Codec.ExtractExport(text)
    local token = text:match(EXPORT_PREFIX .. "[A-Za-z0-9+/=]+")
    if not token then
        return nil
    end
    return Codec.DecodeExport(token)
end

function Codec.EncodeImport(payload)
    local json = SideQuestJSON.encode(payload)
    return IMPORT_PREFIX .. SideQuestBase64.encode(json)
end

function Codec.DecodeImport(str)
    if type(str) ~= "string" then
        error("Codec.DecodeImport: expected string")
    end
    local b64 = str:match("^" .. IMPORT_PREFIX .. "([A-Za-z0-9+/=]+)$")
    if not b64 then
        error("Codec.DecodeImport: missing/invalid SQI1: prefix")
    end
    local json = SideQuestBase64.decode(b64)
    return SideQuestJSON.decode(json)
end

function Codec.ExtractImport(text)
    local token = text:match(IMPORT_PREFIX .. "[A-Za-z0-9+/=]+")
    if not token then
        return nil
    end
    return Codec.DecodeImport(token)
end

return Codec
