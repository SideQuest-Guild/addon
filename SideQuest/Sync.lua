-- SideQuest/Sync.lua
-- Ties Codec + Standings together for the `/sq export`, `/sq export clear`
-- and `/sq import` commands, and the Sync tab UI.

SideQuest = SideQuest or {}
SideQuest.Sync = {}
local Sync = SideQuest.Sync

function Sync.BuildExport()
    local recorder = SideQuest.NormalizeUnit("player") or "Unknown-Unknown"
    local guildName = GetGuildInfo and select(1, GetGuildInfo("player")) or ""
    local realmName = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    local payload = SideQuest.Codec.BuildExportPayload(recorder, guildName, realmName)
    local str = SideQuest.Codec.EncodeExport(payload)
    SideQuestDB.lastExport = str
    return str, payload
end

function Sync.ClearPending()
    SideQuestDB.pending = { sessions = {}, encounters = {}, loot = {}, awards = {} }
    SideQuestDB.lastExport = ""
end

--- Apply a decoded "SQI1:" payload: updates rules, standings, killed
-- encounters, events, and (if officer) rebroadcasts standings to the guild.
function Sync.ApplyImport(payload)
    if payload.v ~= 1 then
        SideQuest.Print("Unsupported import version " .. tostring(payload.v))
        return false
    end
    SideQuest.Standings.LoadFromImport(payload)
    SideQuest.Print("Imported standings generated at " .. tostring(payload.generated_at))
    if SideQuest.IsOfficer() then
        SideQuest.Standings.BroadcastAfterImport()
    end
    SideQuest.Fire("SQ_IMPORT_APPLIED", payload)
    return true
end

function Sync.ImportString(str)
    local ok, payload = pcall(SideQuest.Codec.DecodeImport, str)
    if not ok then
        SideQuest.Print("Import failed: " .. tostring(payload))
        return false
    end
    return Sync.ApplyImport(payload)
end

SideQuest.RegisterSlash("export", function(rest)
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can export.")
        return
    end
    if rest == "clear" then
        Sync.ClearPending()
        SideQuest.Print("Cleared pending data and the last export.")
        return
    end
    local str = Sync.BuildExport()
    SideQuest.Fire("SQ_SHOW_EXPORT", str)
    SideQuest.Print("Export ready (" .. #str .. " chars). Opening the Sync window.")
end, "build/show the export string, or 'clear' to drop pending data")

SideQuest.RegisterSlash("import", function(rest)
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can import.")
        return
    end
    if rest and rest ~= "" then
        Sync.ImportString(rest)
    else
        SideQuest.Fire("SQ_SHOW_IMPORT")
    end
end, "paste an SQI1: import string, or open the import window")

return Sync
