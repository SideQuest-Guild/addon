-- SideQuest/Sync.lua
-- Ties Codec + Standings together for the `/sq export`, `/sq export clear`
-- and `/sq import` commands, and the Sync tab UI.

SideQuest = SideQuest or {}
SideQuest.Sync = {}
local Sync = SideQuest.Sync

-- WoW has no `os` library; `date` is the client's global copy of os.date.
local function formatStagedTime(ts)
    ts = tonumber(ts)
    if not ts then
        return "at an unknown time"
    end
    return date("%Y-%m-%d %H:%M", ts)
end

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
        announcements = {}, recruits = {}, member_notes = {}, battlegrounds = {},
        guild_log = {}, recruit_payouts_paid = {},
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
    SideQuest.Print("Imported standings generated " .. formatStagedTime(payload.generated_at) .. ".")

    -- Game import "prices" (contract "Game import"): replaced wholesale when the
    -- field is present (even an empty list, which clears it); a payload from
    -- before this field existed omits it, and existing prices are left alone.
    if payload.prices ~= nil then
        local prices = {}
        for _, entry in ipairs(payload.prices) do
            prices[entry.item_id] = { p = entry.unit_price, q = entry.quantity, at = entry.at, w = entry.wanted or 0 }
        end
        SideQuestDB.prices = prices
    end

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
            SideQuestDB.officerData.unseen = payload.officer.unseen or {}
            SideQuestDB.officerData.recruit_payouts = payload.officer.recruit_payouts or {}
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
    SideQuest.Print("Export ready (" .. #str .. " chars). SideQuest Companion uploads it on its own after "
        .. "/reload or logout -- otherwise paste it on sidequest-guild.com/officers/sync/. Opening the Sync window.")
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
        SideQuestDB.officerData.unseen = off.unseen or SideQuestDB.officerData.unseen
        SideQuestDB.officerData.recruit_payouts = off.recruit_payouts or SideQuestDB.officerData.recruit_payouts
        SideQuest.Fire("SQ_OFFICER_DATA_UPDATED")
    end
end)

--------------------------------------------------------------------------
-- Staged import ("inbox"): SideQuest Companion, the desktop tray app, can
-- write SideQuestDB.inbox while WoW is closed so officers pick up the
-- website's newest points at their next login without pasting anything.
-- See the companion's "staged import" contract.
--------------------------------------------------------------------------

local INBOX_MAX_ATTEMPTS = 20
local INBOX_RETRY_DELAY = 1 -- seconds; officer-note perms/guild roster can lag a few seconds after login

local inboxAttempts = 0

function Sync.ResetInboxState()
    inboxAttempts = 0
end

local function applyInbox(inbox)
    SideQuest.WhenOutOfCombat(function()
        if Sync.ImportString(inbox.payload) then
            SideQuest.Print("Applied the import SideQuest Companion staged (generated "
                .. formatStagedTime(inbox.generated_at) .. ").")
        end
    end)
end

--- Runs at PLAYER_ENTERING_WORLD and GUILD_ROSTER_UPDATE, retrying briefly
-- off a timer, until officer status is known; then applies or discards the
-- staged inbox exactly once. Safe to call repeatedly: it is a no-op once
-- SideQuestDB.inbox has been cleared. SavedVariables are per account, so a
-- non-officer character leaves the inbox in place for an officer alt.
function Sync.ProcessInbox()
    local inbox = SideQuestDB and SideQuestDB.inbox
    if type(inbox) ~= "table" then
        return
    end
    if type(inbox.payload) ~= "string" or inbox.payload:sub(1, 5) ~= "SQI1:" then
        SideQuest.Print("SideQuest Companion staged an import, but it could not be read. It has been discarded.")
        SideQuestDB.inbox = nil
        return
    end

    if SideQuest.IsOfficer() then
        -- Clear the inbox before applying it: if anything in the import fails, it must not be re-applied on every
        -- later login and roster update.
        SideQuestDB.inbox = nil
        local stagedAt = tonumber(inbox.generated_at) or 0
        local haveAt = (SideQuestDB.standings and SideQuestDB.standings.generated_at) or 0
        if stagedAt < haveAt then
            SideQuest.Print("SideQuest Companion's staged import was older than what the addon already has; it has"
                .. " been discarded.")
        else
            applyInbox(inbox)
        end
        return
    end

    -- Guild info (and so officer status) may not be known yet right after
    -- login; retry briefly before concluding the character really isn't an
    -- officer. A non-officer leaves the inbox for an officer on this account.
    if inboxAttempts >= INBOX_MAX_ATTEMPTS then
        return -- already told the player; GUILD_ROSTER_UPDATE keeps calling in
    end
    inboxAttempts = inboxAttempts + 1
    if inboxAttempts == INBOX_MAX_ATTEMPTS then
        SideQuest.Print("SideQuest Companion staged an import. Log in on an officer to apply it.")
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(INBOX_RETRY_DELAY, Sync.ProcessInbox)
    end
end

SideQuest.On("PLAYER_ENTERING_WORLD", function()
    Sync.ProcessInbox()
end)

SideQuest.On("GUILD_ROSTER_UPDATE", function()
    Sync.ProcessInbox()
end)
SideQuest.RegisterGameEvent("GUILD_ROSTER_UPDATE")

-- Officers sweep the roster and rebuild lastExport on logout, so SideQuest Companion always finds a current
-- export in the save file to upload, including the roster and the directory's latest hashes, even if nobody ran
-- /sq export that session.
SideQuest.On("PLAYER_LOGOUT", function()
    if SideQuest.IsOfficer() then
        SideQuest.Roster.Sweep(true)
        Sync.BuildExport()
    end
end)
SideQuest.RegisterGameEvent("PLAYER_LOGOUT")

return Sync
