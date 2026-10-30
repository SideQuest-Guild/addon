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

--- Build the export payload table (contract-shaped) from the addon's pending
--- data. Does not mutate SideQuestDB; callers decide when to clear `pending`.
-- @param recorderName string normalized "Name-Realm" of the recorder
-- @param guildName string
-- @param realmName string
function Codec.BuildExportPayload(recorderName, guildName, realmName)
    local db = SideQuestDB
    local pending = db.pending or { sessions = {}, encounters = {}, loot = {}, awards = {} }

    return {
        v = 1,
        addon_version = SideQuest.ADDON_VERSION,
        exported_at = GetServerTime and GetServerTime() or 0,
        guild = guildName or "",
        realm = realmName or "",
        recorder = recorderName or "",
        sessions = arr(exportSessions(pending.sessions)),
        encounters = arr(exportEncounters(pending.encounters)),
        loot = arr(pending.loot),
        awards = arr(pending.awards),
    }
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
