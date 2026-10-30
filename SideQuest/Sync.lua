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
    SideQuestDB.pending = {
        sessions = {}, encounters = {}, loot = {}, awards = {},
        roster = nil, professions = {}, signups = {}, bank = {},
        announcements = {}, recruits = {}, member_notes = {},
    }
    SideQuestDB.lastExport = ""
end

--- Apply a decoded "SQI1:" payload (v1 or v2): updates rules, standings,
-- killed encounters, events; v2 additionally updates the public guild
-- member/news cache, the officer-held on-demand cache (sheets, crafters),
-- and (officer only) the officer-only cache. Officers then rebroadcast
-- the public part to the guild and the officer part to other officers.
function Sync.ApplyImport(payload)
    if payload.v ~= 1 and payload.v ~= 2 then
        SideQuest.Print("Unsupported import version " .. tostring(payload.v))
        return false
    end
    SideQuest.Standings.LoadFromImport(payload)
    SideQuest.Print("Imported standings generated at " .. tostring(payload.generated_at))

    local publicPart = nil
    if payload.v == 2 then
        publicPart = { members = payload.members or {}, news = payload.news or {} }
        SideQuestDB.guild.generated_at = payload.generated_at or 0
        SideQuestDB.guild.members = publicPart.members
        for _, item in ipairs(publicPart.news) do
            SideQuest.News.Add(item)
        end
        if payload.sheets or payload.crafters or payload.recipe_names then
            SideQuestDB.onDemand.sheets = payload.sheets or {}
            SideQuestDB.onDemand.crafters = payload.crafters or {}
            SideQuestDB.onDemand.recipe_names = payload.recipe_names or {}
        end
        if SideQuest.IsOfficer() and payload.officer then
            SideQuestDB.officerData.recruits = payload.officer.recruits or {}
            SideQuestDB.officerData.member_notes = payload.officer.member_notes or {}
            SideQuestDB.officerData.inactive = payload.officer.inactive or {}
        end
    end

    if SideQuest.IsOfficer() then
        SideQuest.Standings.BroadcastAfterImport()
        if publicPart then
            SideQuest.Comm.BroadcastRosterPub(publicPart)
        end
        if payload.officer then
            SideQuest.Comm.SendOfficerData(payload.officer)
        end
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

-- Members (and officers, redundantly) receive the public import part
-- straight off the wire, without ever pasting anything, per the contract.
SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, _sender)
    if msgType == "ROSTERPUB" then
        local ok, pub = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        SideQuestDB.guild.members = pub.members or {}
        for _, item in ipairs(pub.news or {}) do
            SideQuest.News.Add(item)
        end
        SideQuest.Fire("SQ_GUILD_UPDATED")
    elseif msgType == "OFFDATA" then
        if not SideQuest.IsOfficer() then
            return -- officer-only part; non-officers never process it
        end
        local ok, off = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        SideQuestDB.officerData.recruits = off.recruits or SideQuestDB.officerData.recruits
        SideQuestDB.officerData.member_notes = off.member_notes or SideQuestDB.officerData.member_notes
        SideQuestDB.officerData.inactive = off.inactive or SideQuestDB.officerData.inactive
        SideQuest.Fire("SQ_OFFICER_DATA_UPDATED")
    end
end)

return Sync
