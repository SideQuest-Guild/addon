-- SideQuest/Roster.lua
-- Guild roster sweep (contract v2 "roster"): recorder's latest
-- GetGuildRosterInfo pass, exported as a snapshot and used locally to
-- merge with the imported public member list in the Guild tab.

SideQuest = SideQuest or {}
SideQuest.Roster = {}
local Roster = SideQuest.Roster

local function now()
    return GetServerTime and GetServerTime() or 0
end

--- True when the roster APIs this module needs exist on this client. Guild
-- roster info is unverified on Forever per the researched addon facts, so
-- every caller must check this and degrade (state the manual path) rather
-- than error.
function Roster.IsAvailable()
    return type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function"
end

--- Sweep the guild roster into SideQuestDB.roster (this character's local
-- snapshot) and SideQuestDB.pending.roster (queued for the next export).
-- Returns the snapshot, or nil if the roster API isn't available.
function Roster.Sweep()
    if not Roster.IsAvailable() then
        return nil
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster() -- request a fresh roster from the server; info below may be stale until it returns
    end

    local members = {}
    local total = GetNumGuildMembers()
    for i = 1, total do
        local name, rank, rankIndex, level, _, zone, _, _, online, _, classFileName =
            GetGuildRosterInfo(i)
        if name then
            local charName = name
            if not charName:find("-") and GetNormalizedRealmName then
                charName = SideQuest.NormalizeName(name, GetNormalizedRealmName())
            end
            table.insert(members, {
                character = charName,
                rank = rank,
                rank_index = rankIndex,
                level = level,
                class = classFileName,
                zone = zone or "",
                online = online and true or false,
                last_online_hours = online and 0 or nil,
            })
        end
    end

    local snapshot = { taken_at = now(), members = members }
    SideQuestDB.roster = snapshot
    SideQuestDB.pending.roster = snapshot
    SideQuest.Fire("SQ_ROSTER_UPDATED", snapshot)
    return snapshot
end

--- Merge this character's own sweep with the imported public roster
-- (ROSTERPUB "members") for the Guild tab: online status/zone/level from
-- our local sweep (fresher) layered over member identity (main/alts,
-- raid_status, badges) from the import.
function Roster.MergedRows()
    local byChar = {}
    for _, m in ipairs((SideQuestDB.roster and SideQuestDB.roster.members) or {}) do
        byChar[m.character] = m
    end

    local rows = {}
    local seen = {}
    for _, member in ipairs((SideQuestDB.guild and SideQuestDB.guild.members) or {}) do
        for _, char in ipairs(member.characters or {}) do
            local local_ = byChar[char.name]
            table.insert(rows, {
                character = char.name,
                class = char.class or (local_ and local_.class),
                level = char.level or (local_ and local_.level),
                is_main = char.is_main,
                member_name = member.name,
                member_id = member.member_id,
                rank = member.rank,
                raid_status = member.raid_status,
                online = local_ and local_.online or false,
                zone = local_ and local_.zone or nil,
            })
            seen[char.name] = true
        end
    end
    -- characters our sweep knows about but the import hasn't linked yet (unlinked)
    for charName, m in pairs(byChar) do
        if not seen[charName] then
            table.insert(rows, {
                character = charName,
                class = m.class,
                level = m.level,
                is_main = true,
                member_name = nil,
                member_id = nil,
                rank = m.rank,
                raid_status = nil,
                online = m.online,
                zone = m.zone,
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.online ~= b.online then
            return a.online
        end
        return (a.member_name or a.character) < (b.member_name or b.character)
    end)
    return rows
end

SideQuest.RegisterSlash("roster", function()
    local snap = Roster.Sweep()
    if snap then
        SideQuest.Print("Swept " .. #snap.members .. " guild member(s).")
    else
        SideQuest.Print("Guild roster API unavailable here; roster stays as last imported.")
    end
end, "sweep the guild roster for export (officers)")

return Roster
