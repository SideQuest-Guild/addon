-- SideQuest/Roster.lua
-- Guild roster sweep (contract v2 "roster"): recorder's latest
-- GetGuildRosterInfo pass plus the guild's ranks (which are officer ranks),
-- exported as a snapshot and used locally to merge with the imported public
-- member list in the Guild tab.

SideQuest = SideQuest or {}
SideQuest.Roster = {}
local Roster = SideQuest.Roster

local function now()
    return GetServerTime and GetServerTime() or 0
end

--- Hours since a guild roster entry was last online, from GetGuildRosterLastOnline's
-- years/months/days/hours breakdown. nil when the API doesn't exist on this client or
-- returns nothing for this index (member info not loaded yet).
local function offlineHours(index)
    if type(GetGuildRosterLastOnline) ~= "function" then
        return nil
    end
    local years, months, days, hours = GetGuildRosterLastOnline(index)
    years, months, days, hours = SideQuest.Unsecret(years), SideQuest.Unsecret(months),
        SideQuest.Unsecret(days), SideQuest.Unsecret(hours)
    if years == nil and months == nil and days == nil and hours == nil then
        return nil
    end
    return (hours or 0) + (days or 0) * 24 + (months or 0) * 30 * 24 + (years or 0) * 365 * 24
end

-- addon-contract-v2.md: roster.ranks, at most 10 entries, index 0-based
-- (0 = Guild Master, matching rank_index). rankOrder (GuildControlGetRankName/
-- GuildControlGetRankFlags) is 1-based, so rankOrder = index + 1.
local MAX_RANKS = 10
local OFFICER_FLAG_INDEX = 22 -- Blizzard_GuildControlUI.xml OfficerCheckbox id="22"

--- The guild's ranks for export: name + whether each carries officer
-- privileges. nil when the client doesn't expose the rank APIs at all. The
-- Guild Master (index 0) is always an officer; every other rank's flag comes
-- from a pcall'd GuildControlGetRankFlags, so a missing/erroring call sends
-- officer=nil (unknown) instead of guessing.
local function sweepRanks()
    if type(GuildControlGetNumRanks) ~= "function" or type(GuildControlGetRankName) ~= "function" then
        return nil
    end
    local count = GuildControlGetNumRanks()
    if not count or count <= 0 then
        return nil
    end
    local ranks = {}
    for index = 0, math.min(count, MAX_RANKS) - 1 do
        local rankOrder = index + 1
        local name = SideQuest.Unsecret(GuildControlGetRankName(rankOrder))
        if name then
            local officer = nil
            if index == 0 then
                officer = true
            elseif C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
                local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rankOrder)
                if ok and type(flags) == "table" then
                    officer = flags[OFFICER_FLAG_INDEX] and true or false
                end
            end
            table.insert(ranks, { index = index, name = name, officer = officer })
        end
    end
    return ranks
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
-- Returns the snapshot, or nil if the roster API isn't available. `auto`
-- reads what the client already has without asking the server again
-- (asking fires GUILD_ROSTER_UPDATE, which would sweep again), and skips an
-- empty roster, which only means the client hasn't loaded it yet.
function Roster.Sweep(auto)
    if not Roster.IsAvailable() then
        return nil
    end
    if auto and GetNumGuildMembers() == 0 then
        return nil
    end
    if not auto and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster() -- request a fresh roster from the server; info below may be stale until it returns
    end

    local members = {}
    local total = GetNumGuildMembers()
    for i = 1, total do
        local name, rank, rankIndex, level, _, zone, _, _, online, _, classFileName =
            GetGuildRosterInfo(i)
        -- Identity return (AGENTS.md: UnitName et al. are secret whenever their
        -- restriction is on); Forever doesn't document GetGuildRosterInfo's
        -- SecretReturns either way, so guard it like every other name read in
        -- this addon rather than let an unreadable name blank the row or break
        -- the %-pattern match in UI/Main.lua's displayName.
        name = SideQuest.Unsecret(name)
        classFileName = SideQuest.Unsecret(classFileName)
        if name then
            -- GetGuildRosterInfo hands back one "First Surname"-shaped
            -- string on Forever, not UnitName's separate name/surname
            -- pair; SQ.CanonicalName splits and links it to the same
            -- "First-Surname" key the player's own SQ.NormalizeUnit
            -- produces (addon-identity-fix).
            local charName = SideQuest.NormalizeName(name)
            table.insert(members, {
                character = charName,
                rank = rank,
                rank_index = rankIndex,
                level = level,
                class = classFileName,
                zone = zone or "",
                online = online and true or false,
                last_online_hours = online and 0 or offlineHours(i),
            })
        end
    end

    local snapshot = { taken_at = now(), members = members, ranks = sweepRanks() }
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

-- The game sends GUILD_ROSTER_UPDATE at login and whenever the roster changes. Sweep then, at most every
-- AUTO_SWEEP_SECONDS, so the Guild tab and the next export carry the roster without anyone pressing Sweep.
local AUTO_SWEEP_SECONDS = 600
local lastAutoSweep = 0
SideQuest.On("GUILD_ROSTER_UPDATE", function()
    if now() - lastAutoSweep < AUTO_SWEEP_SECONDS then
        return
    end
    if Roster.Sweep(true) then
        lastAutoSweep = now()
    end
end)

return Roster
