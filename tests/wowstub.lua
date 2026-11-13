-- tests/wowstub.lua
-- Minimal WoW client API stub for running SideQuest's Lua under plain
-- LuaJIT (5.1 semantics) outside the game. Exposes a `WowStub` control
-- table tests use to drive roster/instance/comm state and fire events.

-- The WoW client has no `os` (or `io`) library: it exposes `date` and `time` as globals instead. Drop `os` here
-- so addon code that reaches for it fails under test exactly as it fails in game. Test harness code that really
-- needs it (exit codes, mkdir) uses `WowStub.os`.
date = os.date
time = os.time
local hostOs = os
os = nil

WowStub = {
    time = 1793490000,
    chatLog = {},
    addonMessages = {},
    addonMessagesBlocked = false,
    frames = {},
    units = {},
    raidCount = 0,
    inRaid = false,
    instance = { inInstance = false, instanceType = "none", instanceID = 0, difficultyID = 1 },
    isOfficer = false,
    inGuild = true, -- IsInGuild(); default true so GetGuildInfo's "SideQuest" default means "a member" everywhere
    rankIndex = 0, -- GetGuildInfo's own rankIndex return; 0 = Guild Master
    guildName = "SideQuest",
    realm = "Whitemane",
    lootItems = {},
    invites = {},
    whispers = {}, -- list of ChatFrameUtil.SendTell targets
    isGroupLeader = true, -- UnitIsGroupLeader("player") while in a group
    convertToRaidCalls = 0,
    mouseOverFrame = nil, -- set to a frame to make Frame:IsMouseOver() true for it and its ancestors
    -- v2
    guildRoster = {}, -- list of { name, rank, rankIndex, level, class, zone, online }
    guildRanks = nil, -- nil (API unavailable), or list of { name, officer = bool, flagsError = true } index 1 = rankOrder 1 (GM)
    professions = {}, -- array (up to 5) of { name, skillLine, skill, maxSkill }; see GetProfessions()
    openTradeSkill = nil, -- { professionID, skillLineID, professionName, skillLevel, maxSkillLevel, linked, guild, recipes, child } or nil
    guildTradeSkillsEnabled = false,
    guildTradeSkills = {}, -- list of { name, playerName, curSkill, maxSkill }
    skillLines = {}, -- list of { name, isHeader, skill, maxSkill } for the C_SkillInfo fallback
    spec = nil, -- { index, name } or nil
    quests = {}, -- questId -> true/false
    reputations = {}, -- factionId -> { reaction, currentStanding }
    spellCooldowns = {}, -- spellId -> { startTime, duration }
    spellNames = {}, -- spellId -> name
    knownSpells = {}, -- spellId -> true
    itemCooldowns = {}, -- itemId -> { startTime, duration }
    containers = {}, -- bagId -> array of { itemID, stackCount } (1-indexed slots)
    avgItemLevel = nil, avgItemLevelEquipped = nil, avgItemLevelPvp = nil,
    bankTransactions = {}, -- tabIndex -> list of { kind, name, itemLink, count, tab1, tab2, years, months, days, hours } (elapsed, not a date)
    bankMoneyTransactions = {}, -- list of { kind, name, amount, years, months, days, hours } (elapsed, not a date)
    bankLogQueries = {}, -- list of tabIndex args passed to QueryGuildBankLog, newest last
    currentGuildBankTab = 1,
    inCombat = false,
    buffs = {}, -- list of buff names on "player"
    durability = nil, -- 0-100 or nil (unknown)
    itemCounts = {}, -- itemId -> count
    raidSubgroups = {}, -- unit ("raid1"...) -> current subgroup
    subgroupCalls = {}, -- recorded SetRaidSubgroup(index, group) calls
    pvp = { scores = {}, winner = nil, myFaction = "Horde", duration = 0, scoreRequests = 0 },
        -- scores: list of PVPScoreInfo-shaped rows for GetScoreInfo; a field set to WowStub.SECRET reads as
        -- secret. winner: 0 Horde, 1 Alliance, nil unknown/draw, for GetBattlefieldWinner.
    files = {}, -- path -> true/false: whether a font file is on disk for FontString:SetFont (unlisted paths load)
    addonMetadata = { Version = "@project-version@" }, -- SideQuest.toc fields; this Version is a development checkout's
    reloads = 0, -- ReloadUI() calls
}

C_AddOns = {
    GetAddOnMetadata = function(name, field)
        return name == "SideQuest" and WowStub.addonMetadata[field] or nil
    end,
}

function ReloadUI()
    WowStub.reloads = WowStub.reloads + 1
end
WowStub.os = hostOs

--------------------------------------------------------------------------
-- Time
--------------------------------------------------------------------------

function GetServerTime()
    return WowStub.time
end

-- GetTime() is the client's uptime clock, a different number from server time.
function GetTime()
    return WowStub.time - 1700000000
end

-- Lua helpers the game client defines globally; the bundled libraries (LibStub, CallbackHandler) call them.
strmatch = string.match
function securecallfunction(fn, ...)
    return fn(...)
end

function WowStub.Advance(seconds)
    WowStub.time = WowStub.time + seconds
end

--------------------------------------------------------------------------
-- Chat output
--------------------------------------------------------------------------

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg)
        table.insert(WowStub.chatLog, msg)
    end,
}

--------------------------------------------------------------------------
-- Client identity (Forever detection, addon-identity-fix)
--------------------------------------------------------------------------

-- Real clients: WOW_PROJECT_ID == WOW_PROJECT_CAMELOT (18) on Forever,
-- some other value otherwise; RegionalUniqueNamesEnabled() true on
-- Forever (no realms, first-name/surname identity). Default to a non-
-- Forever client so every pre-existing test keeps its "Name-Realm"
-- behavior; call WowStub.SetForever(true) to model Forever.
WOW_PROJECT_CAMELOT = 18
WOW_PROJECT_ID = 1
WowStub.forever = false

function WowStub.SetForever(enabled)
    WowStub.forever = enabled and true or false
    WOW_PROJECT_ID = WowStub.forever and WOW_PROJECT_CAMELOT or 1
end

function RegionalUniqueNamesEnabled()
    return WowStub.forever
end

-- Ketho/BlizzardInterfaceResources forever branch, Resources/LuaEnum.lua.
Constants = Constants or {}
Constants.CharacterNameSeparatorConsts = {
    CHARACTERNAME_SURNAME_SEPARATOR = " ",
    CHARACTERNAME_LINK_SEPARATOR = "-",
    CHARACTERNAME_REALMNAME_SEPARATOR = "-",
}

-- Gethe/wow-ui-source forever branch, Blizzard_APIDocumentationGenerated/NameUtilDocumentation.lua.
C_NameUtil = C_NameUtil or {}
function C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(fullName)
    if not fullName then
        return fullName
    end
    return (fullName:gsub(" ", "-", 1))
end

--------------------------------------------------------------------------
-- Units / roster
--------------------------------------------------------------------------

function WowStub.SetUnit(unit, data)
    WowStub.units[unit] = data
end

function WowStub.SetRaid(unitList)
    -- unitList: array of { name, realm, class, guid }
    WowStub.raidCount = #unitList
    WowStub.inRaid = #unitList > 0
    for i, data in ipairs(unitList) do
        WowStub.units["raid" .. i] = data
    end
    for i = #unitList + 1, 40 do
        WowStub.units["raid" .. i] = nil
    end
end

function UnitName(unit)
    local u = WowStub.units[unit]
    if not u then
        return nil
    end
    return u.name, u.realm
end

function UnitGUID(unit)
    local u = WowStub.units[unit]
    return u and u.guid or nil
end

function UnitExists(unit)
    return WowStub.units[unit] ~= nil
end

function UnitIsPlayer(unit)
    local u = WowStub.units[unit]
    return u ~= nil and u.isPlayer ~= false
end

function UnitClass(unit)
    local u = WowStub.units[unit]
    if not u then
        return nil, nil
    end
    return u.class, u.class
end

function UnitLevel(unit)
    local u = WowStub.units[unit]
    return u and u.level or 1
end

function UnitRace(unit)
    local u = WowStub.units[unit]
    if not u then
        return nil, nil
    end
    return u.race, u.race
end

function GetAverageItemLevel()
    return WowStub.avgItemLevel or 0, WowStub.avgItemLevelEquipped or 0, WowStub.avgItemLevelPvp or 0
end

function IsInRaid()
    return WowStub.inRaid
end

function IsInGroup()
    return WowStub.inRaid or WowStub.raidCount > 0
end

function GetNumGroupMembers()
    return WowStub.raidCount
end

function GetNormalizedRealmName()
    return WowStub.realm
end

-- Tests mark a value secret by using the WowStub.SECRET sentinel in place of
-- the real value (e.g. a score row's killingBlows); issecretvalue flags it,
-- same as the real client would flag a secret-wrapped return.
WowStub.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

function issecretvalue(v)
    return v == WowStub.SECRET
end

--------------------------------------------------------------------------
-- Guild / officer
--------------------------------------------------------------------------

C_GuildInfo = {
    CanEditOfficerNote = function()
        -- officerKnownAfterCalls simulates guild roster/officer-note perms
        -- not being known for the first few calls after login.
        WowStub.officerNoteCalls = (WowStub.officerNoteCalls or 0) + 1
        if WowStub.officerKnownAfterCalls then
            return WowStub.officerNoteCalls >= WowStub.officerKnownAfterCalls
        end
        return WowStub.isOfficer
    end,
    -- rankOrder is 1-based (index+1); flag 22 is "has officer privileges"
    -- (Blizzard_GuildControlUI.xml OfficerCheckbox id="22"). A rank with
    -- `flagsError` simulates the real call erroring/missing on some ranks.
    GuildControlGetRankFlags = function(rankOrder)
        local r = WowStub.guildRanks and WowStub.guildRanks[rankOrder]
        if not r then
            return nil
        end
        if r.flagsError then
            error("GuildControlGetRankFlags failed")
        end
        local flags = {}
        for i = 1, 32 do
            flags[i] = false
        end
        flags[22] = r.officer and true or false
        return flags
    end,
}

function IsInGuild()
    return WowStub.inGuild and true or false
end

function GetGuildInfo(unit)
    if not WowStub.inGuild then
        return nil
    end
    return WowStub.guildName, "Officer", WowStub.rankIndex or 0
end

-- A trimmed, deterministic fake call stack; SQ.ShortStack() (Core.lua) trims
-- to its first few lines regardless, so the exact content doesn't matter.
function debugstack(level, lines, linesAfter)
    return "[string \"SideQuest/Core.lua\"]:1: in function 'demo'\n"
        .. "[string \"SideQuest/Core.lua\"]:2: in function 'caller'\n"
        .. "[string \"SideQuest/Core.lua\"]:3: in main chunk"
end

-- Rank count/name: nil (API unavailable) unless a test configures WowStub.guildRanks.
function GuildControlGetNumRanks()
    return WowStub.guildRanks and #WowStub.guildRanks or nil
end

function GuildControlGetRankName(rankOrder)
    local r = WowStub.guildRanks and WowStub.guildRanks[rankOrder]
    return r and r.name or nil
end

function GetNumGuildMembers()
    return #WowStub.guildRoster
end

function GetGuildRosterInfo(index)
    local m = WowStub.guildRoster[index]
    if not m then
        return nil
    end
    return m.name, m.rank, m.rankIndex, m.level, m.class, m.zone, "", "", m.online, "", m.classFile or m.class
end

function GetGuildRosterLastOnline(index)
    local m = WowStub.guildRoster[index]
    if not m or not m.lastOnline then
        return nil
    end
    local lo = m.lastOnline
    return lo.years or 0, lo.months or 0, lo.days or 0, lo.hours or 0
end

-- WowStub.guildEvents: list of { kind, player1, player2, rank, years, months, days, hours } in
-- GetGuildEventInfo's own order (index 1 = most recent, matching the real log).
function QueryGuildEventLog()
    WowStub.queryGuildEventLogCalls = (WowStub.queryGuildEventLogCalls or 0) + 1
end

function GetNumGuildEvents()
    return #(WowStub.guildEvents or {})
end

function GetGuildEventInfo(index)
    local e = (WowStub.guildEvents or {})[index]
    if not e then
        return nil
    end
    return e.kind, e.player1, e.player2, e.rank, e.years or 0, e.months or 0, e.days or 0, e.hours or 0
end

--------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------

function IsInInstance()
    return WowStub.instance.inInstance, WowStub.instance.instanceType
end

function GetInstanceInfo()
    return WowStub.instance.name or "Test Instance", WowStub.instance.instanceType,
        WowStub.instance.difficultyID, "Normal", WowStub.raidCount, 0, false, WowStub.instance.instanceID
end

--------------------------------------------------------------------------
-- Loot
--------------------------------------------------------------------------

function GetNumLootItems()
    return #WowStub.lootItems
end

function GetLootSlotLink(slot)
    local item = WowStub.lootItems[slot]
    return item and item.link or nil
end

function GiveMasterLoot(slot, candidateIndex)
    return true
end

C_Item = {
    GetItemInfoInstant = function(itemId)
        local item = WowStub.items and WowStub.items[itemId]
        if not item then
            return nil
        end
        return item.itemId or itemId, item.itemType, item.itemSubType, item.equipLoc, item.icon, item.classID, item.subclassID
    end,
    GetItemCount = function(itemId)
        return WowStub.itemCounts[itemId] or 0
    end,
    GetItemNameByID = function(itemId)
        local item = WowStub.items and WowStub.items[itemId]
        return item and item.name or nil
    end,
    GetItemCooldown = function(itemId)
        local cd = WowStub.itemCooldowns[itemId]
        if not cd then
            return 0, 0, 1
        end
        return cd.startTime or 0, cd.duration or 0, 1
    end,
}

-- GetItemInfo/C_Item.GetItemInfo: unlike GetItemInfoInstant (id/type/equipLoc,
-- always available), name/quality/icon need the full item data; accepts
-- either an item id or an "item:<id>[:...]" link string.
function GetItemInfo(itemLinkOrId)
    local id = tonumber(itemLinkOrId)
    if not id and type(itemLinkOrId) == "string" then
        id = tonumber(itemLinkOrId:match("item:(%d+)"))
    end
    local item = id and WowStub.items and WowStub.items[id]
    if not item then
        return nil
    end
    return item.name, item.link or ("item:" .. id), item.quality or 1, item.ilvl or 1, item.minLevel or 1,
        item.itemType, item.itemSubType, item.stackCount or 1, item.equipLoc, item.icon, item.sellPrice or 0,
        item.classID, item.subclassID
end
C_Item.GetItemInfo = GetItemInfo

--------------------------------------------------------------------------
-- Professions (directory "prof" section, docs/directory.md)
--------------------------------------------------------------------------

-- GetProfessions/GetProfessionInfo: WowStub.professions is a plain array (up
-- to 5 entries) of { name, skillLine, skill, maxSkill }; its slot order maps
-- directly to GetProfessions()'s (primary1, primary2, archaeology, fishing,
-- cooking) returns.
function GetProfessions()
    local list = WowStub.professions
    local function slot(i)
        return list[i] and i or nil
    end
    return slot(1), slot(2), slot(3), slot(4), slot(5)
end

function GetProfessionInfo(index)
    local p = WowStub.professions[index]
    if not p then
        return nil
    end
    return p.name, p.icon or 0, p.skill, p.maxSkill, 0, 0, p.skillLine
end

-- WowStub.openTradeSkill: { professionID, skillLineID, professionName, skillLevel, maxSkillLevel,
-- linked = bool, guild = bool, recipes = { { id, name, learned, previewItemID } }, child = nil or the
-- same shape (a specialization tab) } or nil when no profession window is open.
C_TradeSkillUI = {
    GetBaseProfessionInfo = function()
        local t = WowStub.openTradeSkill
        if not t then
            return { professionID = 0 }
        end
        return {
            professionID = t.professionID or 1,
            skillLineID = t.skillLineID,
            professionName = t.professionName,
            skillLevel = t.skillLevel,
            maxSkillLevel = t.maxSkillLevel,
        }
    end,
    GetChildProfessionInfo = function()
        local t = WowStub.openTradeSkill
        if not t or not t.child then
            return { professionID = 0 }
        end
        return {
            professionID = t.child.professionID or 2,
            skillLineID = t.child.skillLineID,
            professionName = t.child.professionName,
            skillLevel = t.child.skillLevel,
            maxSkillLevel = t.child.maxSkillLevel,
        }
    end,
    GetAllRecipeIDs = function()
        local t = WowStub.openTradeSkill
        local ids = {}
        for _, r in ipairs(t and t.recipes or {}) do
            table.insert(ids, r.id)
        end
        return ids
    end,
    GetRecipeInfo = function(id)
        local t = WowStub.openTradeSkill
        for _, r in ipairs(t and t.recipes or {}) do
            if r.id == id then
                return { learned = r.learned, name = r.name, previewItemID = r.previewItemID }
            end
        end
        return nil
    end,
    IsTradeSkillLinked = function()
        return WowStub.openTradeSkill and WowStub.openTradeSkill.linked or false
    end,
    IsTradeSkillGuild = function()
        return WowStub.openTradeSkill and WowStub.openTradeSkill.guild or false
    end,
    IsGuildTradeSkillsEnabled = function()
        return WowStub.guildTradeSkillsEnabled or false
    end,
}

-- WowStub.skillLines: array of { name, isHeader, skill, maxSkill } for the C_SkillInfo fallback path
-- Professions.lua uses when GetProfessions is unavailable.
C_SkillInfo = {
    GetNumSkillLines = function()
        return #(WowStub.skillLines or {})
    end,
    GetSkillLineInfo = function(i)
        local line = (WowStub.skillLines or {})[i]
        if not line then
            return nil
        end
        return line.name, line.isHeader or false, false, line.skill, 0, line.maxSkill
    end,
}

-- WowStub.spec: { index, name } or nil.
C_SpecializationInfo = {
    GetSpecialization = function()
        return WowStub.spec and WowStub.spec.index or nil
    end,
    GetSpecializationInfo = function(index)
        if not WowStub.spec or WowStub.spec.index ~= index then
            return nil
        end
        return index, WowStub.spec.name
    end,
}

-- WowStub.spellCooldowns: spellId -> { startTime, duration } on the GetTime() clock; WowStub.spellNames:
-- spellId -> name. GetSpellCooldown returns Mainline's SpellCooldownInfo table.
C_Spell = {
    GetSpellCooldown = function(spellId)
        local cd = WowStub.spellCooldowns[spellId] or {}
        return { startTime = cd.startTime or 0, duration = cd.duration or 0, isEnabled = true, modRate = 1 }
    end,
    GetSpellName = function(spellId)
        return WowStub.spellNames[spellId]
    end,
}

-- WowStub.knownSpells: spellId -> true.
C_SpellBook = {
    IsSpellKnown = function(spellId)
        return WowStub.knownSpells[spellId] or false
    end,
}

-- WowStub.quests: questId -> true/false.
C_QuestLog = {
    IsQuestFlaggedCompleted = function(questId)
        return WowStub.quests[questId] or false
    end,
}

-- WowStub.reputations: factionId -> { reaction, currentStanding }.
C_Reputation = {
    GetFactionDataByID = function(factionId)
        return WowStub.reputations[factionId]
    end,
}

-- WowStub.containers: bagId -> array of { itemID, stackCount } (1-indexed slots).
C_Container = {
    GetContainerNumSlots = function(bagId)
        return #(WowStub.containers[bagId] or {})
    end,
    GetContainerItemInfo = function(bagId, slot)
        local bag = WowStub.containers[bagId]
        return bag and bag[slot] or nil
    end,
}

-- WowStub.guildTradeSkills: array of { name, playerName, curSkill, maxSkill } for the native guild
-- profession seed (docs/directory.md "Members who don't run SideQuest").
function GetNumGuildTradeSkill()
    return #WowStub.guildTradeSkills
end

function GetGuildTradeSkillInfo(i)
    local r = WowStub.guildTradeSkills[i]
    if not r then
        return nil
    end
    return r.name, r.playerName, r.curSkill, r.maxSkill
end

function QueryGuildRecipes() end

--------------------------------------------------------------------------
-- Guild bank (v2)
--------------------------------------------------------------------------

-- Forever's real guild bank log API: old globals, not C_GuildBank (which
-- only has IsGuildBankEnabled). See addon/SideQuest/Bank.lua for sources.
C_GuildBank = {
    IsGuildBankEnabled = function()
        return true
    end,
}

function GetCurrentGuildBankTab()
    return WowStub.currentGuildBankTab or 1
end

function QueryGuildBankLog(tabIndex)
    table.insert(WowStub.bankLogQueries, tabIndex)
end

function GetNumGuildBankTransactions(tabIndex)
    return #(WowStub.bankTransactions[tabIndex] or {})
end

function GetGuildBankTransaction(tabIndex, i)
    local r = (WowStub.bankTransactions[tabIndex] or {})[i]
    if not r then
        return nil
    end
    return r.kind, r.name, r.itemLink, r.count, r.tab1, r.tab2, r.year, r.month, r.day, r.hour
end

function GetNumGuildBankMoneyTransactions()
    return #WowStub.bankMoneyTransactions
end

function GetGuildBankMoneyTransaction(i)
    local r = WowStub.bankMoneyTransactions[i]
    if not r then
        return nil
    end
    return r.kind, r.name, r.amount, r.year, r.month, r.day, r.hour
end

--------------------------------------------------------------------------
-- Battlegrounds (v2)
--------------------------------------------------------------------------

C_PvP = {
    GetScoreInfo = function(i)
        return WowStub.pvp.scores[i]
    end,
    GetActiveMatchDuration = function()
        return WowStub.pvp.duration
    end,
}

function GetNumBattlefieldScores()
    return #WowStub.pvp.scores
end

function GetBattlefieldWinner()
    return WowStub.pvp.winner
end

function RequestBattlefieldScoreData()
    WowStub.pvp.scoreRequests = (WowStub.pvp.scoreRequests or 0) + 1
end

function UnitFactionGroup(unit)
    return WowStub.pvp.myFaction, WowStub.pvp.myFaction
end

--------------------------------------------------------------------------
-- Combat lockdown + chat (v2)
--------------------------------------------------------------------------

function InCombatLockdown()
    return WowStub.inCombat
end

-- Forever has no SendChatMessage global: C_ChatInfo.SendChatMessage (below) replaces it.

--------------------------------------------------------------------------
-- Auras + durability (v2, raid prep)
--------------------------------------------------------------------------

function UnitBuff(unit, index)
    if unit ~= "player" then
        return nil
    end
    return WowStub.buffs[index]
end

function GetInventoryItemDurability(slot)
    if not WowStub.durability then
        return nil
    end
    return WowStub.durability, 100
end

--------------------------------------------------------------------------
-- Group management
--------------------------------------------------------------------------

-- Forever has none of the InviteUnit, ConvertToRaid, ChatFrame_SendTell, IsRaidLeader or IsPartyLeader globals; the
-- stub leaves them undefined so a call to one fails a test instead of silently doing nothing in game.
C_PartyInfo = {
    InviteUnit = function(name)
        table.insert(WowStub.invites, name)
    end,
    ConvertToRaid = function()
        WowStub.convertToRaidCalls = WowStub.convertToRaidCalls + 1
        WowStub.inRaid = true
    end,
}

function UnitIsGroupLeader(unit)
    return unit == "player" and WowStub.isGroupLeader
end

ChatFrameUtil = {
    SendTell = function(target)
        table.insert(WowStub.whispers, target)
    end,
    InsertLink = function(link)
        return false
    end,
}

function SetRaidSubgroup(raidIndex, group)
    table.insert(WowStub.subgroupCalls, { index = raidIndex, group = group })
    WowStub.raidSubgroups["raid" .. raidIndex] = group
    return true
end

function SwapRaidSubgroup(raidIndex, raidIndex2)
    local a, b = WowStub.raidSubgroups["raid" .. raidIndex], WowStub.raidSubgroups["raid" .. raidIndex2]
    WowStub.raidSubgroups["raid" .. raidIndex] = b
    WowStub.raidSubgroups["raid" .. raidIndex2] = a
    return true
end

C_UnitAuras = {
    GetBuffDataByIndex = function(unit, index, _filter)
        if unit ~= "player" then
            return nil
        end
        local name = WowStub.buffs[index]
        if not name then
            return nil
        end
        return { name = name }
    end,
}

C_DurabilityInfo = nil -- Forever's modern durability API is unverified; left absent so the legacy path is exercised

--------------------------------------------------------------------------
-- Addon comm
--------------------------------------------------------------------------

Enum = {
    SendAddonMessageResult = {
        Success = 0,
        AddonMessageThrottle = 1,
        NotInGroup = 2,
        ChannelThrottle = 3,
        Generic = 4,
    },
    CalendarEventType = { Raid = 0, Dungeon = 1, PvP = 2, Meeting = 3, Other = 4, HeroicDeprecated = 5 },
    TooltipDataType = { Item = 1 },
}

-- TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn): the
-- game calls `fn(tooltip, data)` after building an item tooltip. Tests fire
-- the registered callback directly with a fake tooltip and `{ id = itemId }`.
TooltipDataProcessor = {
    callbacks = {},
}

function TooltipDataProcessor.AddTooltipPostCall(dataType, fn)
    TooltipDataProcessor.callbacks[dataType] = TooltipDataProcessor.callbacks[dataType] or {}
    table.insert(TooltipDataProcessor.callbacks[dataType], fn)
end

--------------------------------------------------------------------------
-- Calendar: an in-memory guild calendar in realm time (WowStub.time + realmOffset)
--------------------------------------------------------------------------

function WowStub.ResetCalendar()
    WowStub.calendar = {
        realmOffset = 0, -- seconds the realm clock runs ahead of UTC
        events = {}, -- list of { calendarType, title, description, eventType, textureIndex, isLocked, year, month, day,
        -- hour, minute }
        textures = {}, -- eventType -> list of { title }
        canAdd = true,
        canRemove = true,
        candidate = nil,
        selected = nil,
        addCalls = 0,
        openCalendarCalls = 0,
        refuseWith = nil, -- list of CALENDAR_ERROR_* names AddEvent raises (as CALENDAR_UPDATE_ERROR) instead of adding
    }
end
WowStub.ResetCalendar()

local function realmNow()
    return hostOs.date("!*t", WowStub.time + WowStub.calendar.realmOffset)
end

-- The calendar's month offsets count from the realm's current month.
local function monthAt(offset)
    local t = realmNow()
    local index = t.year * 12 + (t.month - 1) + offset
    return math.floor(index / 12), index % 12 + 1
end

local function dayEvents(offset, day)
    local year, month = monthAt(offset)
    local list = {}
    for _, e in ipairs(WowStub.calendar.events) do
        if e.year == year and e.month == month and e.day == day then
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        return a.hour * 60 + a.minute < b.hour * 60 + b.minute
    end)
    return list
end

C_DateAndTime = {
    GetCurrentCalendarTime = function()
        local t = realmNow()
        return { year = t.year, month = t.month, monthDay = t.day, weekday = t.wday, hour = t.hour, minute = t.min }
    end,
}

C_Calendar = {
    OpenCalendar = function()
        WowStub.calendar.openCalendarCalls = WowStub.calendar.openCalendarCalls + 1
    end,
    SetAbsMonth = function(month, year)
        WowStub.calendar.absMonth = { month = month, year = year }
    end,
    GetMonthInfo = function(offset)
        local year, month = monthAt(offset or 0)
        return { year = year, month = month }
    end,
    GetMaxCreateDate = function()
        local t = hostOs.date("!*t", WowStub.time + WowStub.calendar.realmOffset + 365 * 86400)
        return { year = t.year, month = t.month, monthDay = t.day, hour = 23, minute = 59 }
    end,
    GetNumDayEvents = function(offset, day)
        return #dayEvents(offset, day)
    end,
    GetDayEvent = function(offset, day, index)
        local e = dayEvents(offset, day)[index]
        if not e then
            return nil
        end
        return {
            title = e.title, calendarType = e.calendarType, eventType = e.eventType, isLocked = e.isLocked == true,
            startTime = { year = e.year, month = e.month, monthDay = e.day, hour = e.hour, minute = e.minute },
        }
    end,
    -- WoW: Forever has no guild announcements: the call exists but creates nothing, so the setters after it have
    -- no event to fill (measured on 1.60.1)
    CreateGuildAnnouncementEvent = function()
        WowStub.calendar.candidate = nil
    end,
    CreateGuildSignUpEvent = function()
        WowStub.calendar.candidate = { calendarType = "GUILD_EVENT" }
    end,
    EventSetTitle = function(title) WowStub.calendar.candidate.title = title end,
    EventSetDescription = function(text) WowStub.calendar.candidate.description = text end,
    EventSetType = function(eventType) WowStub.calendar.candidate.eventType = eventType end,
    EventSetTextureID = function(index) WowStub.calendar.candidate.textureIndex = index end,
    EventSetLocked = function() WowStub.calendar.candidate.isLocked = true end,
    EventSetDate = function(month, day, year)
        local c = WowStub.calendar.candidate
        c.year, c.month, c.day = year, month, day
    end,
    EventSetTime = function(hour, minute)
        local c = WowStub.calendar.candidate
        c.hour, c.minute = hour, minute
    end,
    EventGetTextures = function(eventType)
        return WowStub.calendar.textures[eventType] or {}
    end,
    CanAddEvent = function()
        return WowStub.calendar.canAdd
    end,
    AddEvent = function()
        WowStub.calendar.addCalls = WowStub.calendar.addCalls + 1
        if WowStub.calendar.refuseWith then
            for _, reason in ipairs(WowStub.calendar.refuseWith) do
                SideQuest.Fire("CALENDAR_UPDATE_ERROR", reason)
            end
            return
        end
        table.insert(WowStub.calendar.events, WowStub.calendar.candidate)
        WowStub.calendar.candidate = nil
    end,
    CloseEvent = function()
        WowStub.calendar.candidate = nil
    end,
    IsActionPending = function()
        return false
    end,
    ContextMenuSelectEvent = function(offset, day, index)
        WowStub.calendar.selected = dayEvents(offset, day)[index]
    end,
    ContextMenuEventCanRemove = function()
        return WowStub.calendar.canRemove
    end,
    ContextMenuEventRemove = function()
        for i, e in ipairs(WowStub.calendar.events) do
            if e == WowStub.calendar.selected then
                table.remove(WowStub.calendar.events, i)
                break
            end
        end
        WowStub.calendar.selected = nil
    end,
}

C_ChatInfo = {
    SendAddonMessage = function(prefix, message, channel, target)
        table.insert(WowStub.addonMessages, { prefix = prefix, message = message, channel = channel, target = target })
        if WowStub.addonMessagesBlocked then
            return Enum.SendAddonMessageResult.Generic
        end
        return Enum.SendAddonMessageResult.Success
    end,
    RegisterAddonMessagePrefix = function(prefix) end,
    SendChatMessage = function(msg, channel, _language, target)
        table.insert(WowStub.chatLog, { msg = msg, channel = channel, target = target })
    end,
}

--------------------------------------------------------------------------
-- Timers: resolved synchronously for deterministic tests
--------------------------------------------------------------------------

C_Timer = {
    After = function(seconds, fn)
        fn()
    end,
}

--------------------------------------------------------------------------
-- Mailbox + gold: GetMoney reads WowStub.money; SendMail/SetSendMailMoney/
-- ClearSendMail just record their calls in WowStub.mail -- MAIL_SEND_SUCCESS
-- or MAIL_FAILED never fires on its own (the real server confirms it);
-- tests fire one or the other directly, as the client receiving it would.
--------------------------------------------------------------------------

WowStub.money = 0

function GetMoney()
    return WowStub.money or 0
end

function WowStub.ResetMail()
    WowStub.mail = { sent = {}, pendingMoney = 0, clearCalls = 0 }
end
WowStub.ResetMail()

function ClearSendMail()
    WowStub.mail.clearCalls = WowStub.mail.clearCalls + 1
    WowStub.mail.pendingMoney = 0
end

function SetSendMailMoney(copper)
    WowStub.mail.pendingMoney = copper or 0
end

function GetSendMailMoney()
    return WowStub.mail.pendingMoney or 0
end

function SendMail(target, subject, body)
    table.insert(WowStub.mail.sent, { target = target, subject = subject, body = body, money = WowStub.mail.pendingMoney })
end

--------------------------------------------------------------------------
-- StaticPopup: enough of Blizzard_StaticPopup (DefaultState: enabled, so it's always loaded) for addon code that
-- shows a one-button-per-action confirmation. WowStub.activePopup holds the one dialog currently shown;
-- WowStub.ClickPopupButton(n) fires its OnAccept (n == 1, the default) or OnCancel (n == 2), as a player click
-- would.
--------------------------------------------------------------------------

StaticPopupDialogs = {}
-- Blizzard defines these before any addon loads; the addon only adds keys (see run_tests.lua's guard).
SlashCmdList = {}
UISpecialFrames = {}

function StaticPopup_Show(which, text_arg1, text_arg2, data)
    local info = StaticPopupDialogs[which]
    if not info then
        return nil
    end
    local text = info.text
    if text_arg1 then
        text = (text:gsub("%%s", tostring(text_arg1), 1))
    end
    WowStub.activePopup = { which = which, info = info, text = text, data = data }
    return WowStub.activePopup
end

function StaticPopup_Hide(which)
    if WowStub.activePopup and (not which or WowStub.activePopup.which == which) then
        WowStub.activePopup = nil
    end
end

function WowStub.ClickPopupButton(buttonNum)
    local popup = WowStub.activePopup
    if not popup then
        return
    end
    WowStub.activePopup = nil
    local callback = (buttonNum == 2) and popup.info.OnCancel or popup.info.OnAccept
    if callback then
        callback(popup.data)
    end
end

--------------------------------------------------------------------------
-- Settings: a trimmed mirror of Blizzard_Settings_Shared's addon-facing
-- Settings table (confirmed against Gethe/wow-ui-source, branch forever,
-- Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua):
-- RegisterVerticalLayoutCategory, RegisterAddOnCategory, RegisterAddOnSetting,
-- RegisterProxySetting, CreateCheckbox, CreateSlider, CreateSliderOptions,
-- CreateElementInitializer, CreateSettingInitializer(Data), SetOnValueChangedCallback
-- and OpenToCategory -- enough shape for UI/Options.lua's register/apply/save
-- behaviour to run the same way it does in game.
--------------------------------------------------------------------------

Settings = {
    VarType = { Boolean = "boolean", String = "string", Number = "number" },
}

local settingsCallbacks = {} -- variable -> list of callback(setting, value)
local categoryLayouts = {} -- category -> layout
local categoryIdCounter = 0

local function newSetting(name, variable, variableType, getValue, setValue)
    local setting = { name = name, variable = variable, variableType = variableType }
    function setting:GetName() return name end
    function setting:GetVariable() return variable end
    function setting:GetValue() return getValue() end
    function setting:SetValue(value)
        setValue(value)
        for _, callback in ipairs(settingsCallbacks[variable] or {}) do
            callback(self, value)
        end
    end
    return setting
end

function Settings.RegisterVerticalLayoutCategory(name)
    categoryIdCounter = categoryIdCounter + 1
    local id = categoryIdCounter
    local category = { name = name }
    function category:GetID() return id end
    local layout = { initializers = {} }
    function layout:AddInitializer(initializer)
        table.insert(self.initializers, initializer)
    end
    categoryLayouts[category] = layout
    return category, layout
end

function Settings.RegisterAddOnCategory(category)
    WowStub.registeredAddOnCategories = WowStub.registeredAddOnCategories or {}
    table.insert(WowStub.registeredAddOnCategories, category)
end

function Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
    if variableTbl[variableKey] == nil then
        variableTbl[variableKey] = defaultValue
    end
    return newSetting(name, variable, variableType,
        function() return variableTbl[variableKey] end,
        function(value) variableTbl[variableKey] = value end)
end

function Settings.RegisterProxySetting(category, variable, variableType, name, defaultValue, getValue, setValue)
    return newSetting(name, variable, variableType, getValue, setValue)
end

function Settings.CreateSliderOptions(minValue, maxValue, rate)
    return { minValue = minValue, maxValue = maxValue, steps = rate and (maxValue - minValue) / rate or 100 }
end

function Settings.CreateCheckbox(category, setting, tooltip)
    local initializer = { setting = setting, tooltip = tooltip, kind = "checkbox" }
    categoryLayouts[category]:AddInitializer(initializer)
    return initializer
end

function Settings.CreateSlider(category, setting, options, tooltip)
    local initializer = { setting = setting, options = options, tooltip = tooltip, kind = "slider" }
    categoryLayouts[category]:AddInitializer(initializer)
    return initializer
end

function Settings.CreateSettingInitializerData(setting, options, tooltip)
    return { setting = setting, name = setting:GetName(), options = options or {}, tooltip = tooltip }
end

function Settings.CreateSettingInitializer(frameTemplate, data)
    return { data = data, frameTemplate = frameTemplate, kind = "control" }
end

function Settings.CreateElementInitializer(frameTemplate, data)
    return { data = data, frameTemplate = frameTemplate, kind = "element" }
end

function Settings.SetOnValueChangedCallback(variable, callback)
    settingsCallbacks[variable] = settingsCallbacks[variable] or {}
    table.insert(settingsCallbacks[variable], callback)
end

function Settings.OpenToCategory(categoryID, scrollToElementName)
    WowStub.openedSettingsCategoryID = categoryID
    WowStub.openedSettingsScrollTo = scrollToElementName
end

SettingsPanel = {
    GetLayout = function(self, category)
        return categoryLayouts[category]
    end,
}

math.randomseed(1)

--------------------------------------------------------------------------
-- Frames: enough of the widget API for Core/Comm/UI code to run headless.
-- Any method not explicitly implemented is a chainable no-op that returns
-- the frame itself, so UI construction code never errors.
--------------------------------------------------------------------------

local FrameMeta = {}

local function newMockRegion(kind, name, parent, template)
    local self = { __kind = kind, __name = name, __parent = parent, __template = template }
    local events = {}
    local scripts = {}

    self.RegisterEvent = function(_, e) events[e] = true end
    self.UnregisterEvent = function(_, e) events[e] = nil end
    self.IsEventRegistered = function(_, e) return events[e] or false end
    self.SetScript = function(_, handler, fn) scripts[handler] = fn end
    self.GetScript = function(_, handler) return scripts[handler] end
    -- HookScript runs after whatever's already on that handler, same as the
    -- real client, rather than replacing it (Skin.lua/LibDBIcon rely on this).
    self.HookScript = function(_, handler, fn)
        local existing = scripts[handler]
        scripts[handler] = function(...)
            if existing then
                existing(...)
            end
            return fn(...)
        end
    end
    self.GetParent = function() return self.__parent end
    -- True while the pointer is over this frame or any frame nested inside
    -- it (child buttons sit within their parent row's hit rect in game, so
    -- a hover there still counts as hovering the row). Tests point
    -- WowStub.mouseOverFrame at whichever frame the pointer is "on".
    self.IsMouseOver = function()
        local f = WowStub.mouseOverFrame
        while f do
            if f == self then
                return true
            end
            f = f.GetParent and f:GetParent()
        end
        return false
    end
    -- SetFont answers whether the font file loaded, as the real client does. Every path loads unless a test lists
    -- it in WowStub.files (path -> true/false) to say whether it's on disk. The call is still logged for the preview.
    self.SetFont = function(_, path, ...)
        self.__geo = self.__geo or {}
        self.__geo[#self.__geo + 1] = { method = "SetFont", args = { path, ... } }
        local present = WowStub.files[path]
        return present == nil or present
    end

    -- Regions remember their draw layer (and sublevel) so the preview can
    -- stack them the way the client does; SetDrawLayer changes it later.
    local function region(regionKind, rName, layer, tmpl, subLevel)
        local r = newMockRegion(regionKind, rName, self, tmpl)
        r.__layer, r.__subLevel = layer, subLevel
        return r
    end
    self.CreateFontString = function(_, fsName, layer, tmpl)
        return region("FontString", fsName, layer or "ARTWORK", tmpl)
    end
    self.CreateTexture = function(_, texName, layer, tmpl, subLevel)
        return region("Texture", texName, layer or "ARTWORK", tmpl, subLevel)
    end
    self.CreateMaskTexture = function(_, texName, layer, tmpl, subLevel)
        return region("MaskTexture", texName, layer or "ARTWORK", tmpl, subLevel)
    end
    self.SetDrawLayer = function(_, layer, subLevel)
        self.__layer, self.__subLevel = layer, subLevel
        return self
    end

    -- Animations: only the end state matters for a static preview render,
    -- so Play/Stop/IsPlaying just flip a flag; every Set* on the group or
    -- its animations (SetFromAlpha, SetScale, SetOffset, SetDegrees, ...)
    -- is captured generically like any other PascalCase call and read
    -- back by the renderer for the finished-animation position/alpha.
    self.CreateAnimationGroup = function(_, agName, tmpl)
        local ag = newMockRegion("AnimationGroup", agName, self, tmpl)
        local playing = false
        ag.Play = function() playing = true end
        ag.Stop = function() playing = false end
        ag.IsPlaying = function() return playing end
        ag.CreateAnimation = function(_, animType, animName)
            return newMockRegion(animType or "Animation", animName, ag, nil)
        end
        return ag
    end

    -- SetAtlas is explicit (not the generic chainable no-op) because real
    -- WoW's useAtlasSize=true argument actually resizes the region from
    -- the atlas's real pixel dimensions (C_Texture.GetAtlasInfo), which
    -- NineSliceUtil.ApplyLayout and the real UIPanelCloseButton icon both
    -- rely on for correct sizing without an explicit SetSize call.
    self.SetAtlas = function(_, atlasName, useAtlasSize, filterMode)
        self.__geo = self.__geo or {}
        self.__geo[#self.__geo + 1] = { method = "SetAtlas", args = { atlasName, useAtlasSize, filterMode } }
        if useAtlasSize and atlasName then
            local info = C_Texture.GetAtlasInfo(atlasName)
            if info then
                self:SetSize(info.width, info.height)
            end
        end
        return self
    end

    -- real WoW Frame/Texture/FontString default to shown; Hide() is explicit. Like the client, a change of shown
    -- state runs OnShow/OnHide (the stub doesn't model hidden parents, so it fires on the frame's own flag).
    local shown = true
    local function setShown(want)
        if want == shown then
            return
        end
        shown = want
        local handler = scripts[want and "OnShow" or "OnHide"]
        if handler then
            handler(self)
        end
    end
    self.Show = function() setShown(true) end
    self.Hide = function() setShown(false) end
    self.IsShown = function() return shown end
    self.SetShown = function(_, cond) setShown(cond and true or false) end

    self.SetScrollChild = function(_, child) self.__scrollChild = child end
    self.GetScrollChild = function() return self.__scrollChild end

    local text = ""
    self.SetText = function(_, t) text = t or "" end
    self.GetText = function() return text end

    local scale = 1 -- real Frame/Texture/FontString default to parent-relative scale 1
    self.SetScale = function(_, s) scale = s end
    self.GetScale = function() return scale end

    setmetatable(self, FrameMeta)
    table.insert(WowStub.frames, { frame = self, events = events, scripts = scripts, name = name })
    self.__events = events
    self.__scripts = scripts
    return self
end

-- Getters that real WoW answers with numbers. Sizes come from the region's
-- last explicit SetSize/SetWidth/SetHeight when the preview recorder logged
-- them (`__geo`), else 0; string width uses the same codepoint estimate as
-- the preview renderer, so text-sized widgets (tabs, ribbons) lay out alike.
local function lastSize(t, axis)
    local geo = rawget(t, "__geo")
    if not geo then
        return 0
    end
    for i = #geo, 1, -1 do
        local c = geo[i]
        if c.method == "SetSize" then
            return (axis == "w" and c.args[1] or c.args[2]) or 0
        elseif axis == "w" and c.method == "SetWidth" or axis == "h" and c.method == "SetHeight" then
            return c.args[1] or 0
        end
    end
    return 0
end

local function stringWidth(t)
    local text = t.GetText and t:GetText() or ""
    local _, codepoints = text:gsub("[^\128-\191]", "")
    local size = 13
    for _, c in ipairs(rawget(t, "__geo") or {}) do
        if c.method == "SetFont" and c.args[2] then
            size = c.args[2]
        end
    end
    return codepoints * size * 0.56
end

local NUMERIC_GETTERS = {
    GetWidth = function(t) return lastSize(t, "w") end,
    GetHeight = function(t) return lastSize(t, "h") end,
    GetStringWidth = stringWidth,
    -- A frame sits one level above its parent unless SetFrameLevel moved it;
    -- a region (texture, font string) draws at its frame's level.
    GetFrameLevel = function(t)
        local level = rawget(t, "__level")
        if level then
            return level
        end
        local parent = rawget(t, "__parent")
        return parent and parent:GetFrameLevel() or 0
    end,
}

-- Only PascalCase keys (the WoW API convention: SetPoint, CreateTexture,
-- IsShown, ...) fall back to a chainable no-op; addon code also stores its
-- own lowerCamelCase data fields directly on these tables (panel.rows,
-- chamber.emptyText, ...) and those must read back as real nil when unset,
-- exactly like a real Frame, or "if not x.field then" guards never fire.
FrameMeta.__index = function(t, k)
    if NUMERIC_GETTERS[k] then
        return NUMERIC_GETTERS[k]
    end
    if type(k) == "string" and k:match("^%u") then
        return function(self, ...)
            -- generic chainable no-op; returns the object itself for method chains
            return t
        end
    end
    return nil
end

function CreateFrame(kind, name, parent, template)
    local self = newMockRegion(kind, name, parent, template)
    self.__level = parent and parent:GetFrameLevel() + 1 or 0
    -- where the addon created it, so the layout preview can name an
    -- invalid-rect frame's source line
    local caller = debug.getinfo(2, "Sl")
    self.__src = caller and (caller.short_src .. ":" .. caller.currentline) or "?"
    self.SetFrameLevel = function(_, level) self.__level = level end
    if template == "UIPanelCloseButton" then
        -- Real template: a 32x32 button whose Normal texture is the
        -- red-lacquer Camelot exit button; Pushed/Disabled/Highlight
        -- states exist in-game but only the resting state matters for a
        -- static preview render.
        self:SetSize(32, 32)
        local icon = self:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints(self)
        icon:SetAtlas("RedButton-Exit", true)
        self.Icon = icon
    elseif template == "UIPanelScrollFrameTemplate" then
        -- Real template: a Slider (UIPanelScrollBarTemplate) beside the
        -- frame with up/down arrow buttons and a thumb texture. The engine
        -- places the thumb by scroll value; a static render shows it at the
        -- top of the slider.
        local bar = CreateFrame("Slider", nil, self)
        bar:SetPoint("TOPLEFT", self, "TOPRIGHT", 6, -16)
        bar:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", 6, 16)
        bar.ScrollUpButton = CreateFrame("Button", nil, bar)
        bar.ScrollDownButton = CreateFrame("Button", nil, bar)
        local thumb = bar:CreateTexture(nil, "OVERLAY")
        thumb:SetPoint("TOP", bar, "TOP", 0, 0)
        bar.ThumbTexture = thumb
        self.ScrollBar = bar
    end
    if kind == "GameTooltip" then
        -- Real GameTooltip:AddLine(text, r, g, b, wrap) appends a line; tests
        -- read them back off self.lines.
        self.lines = {}
        self.AddLine = function(_, text, r, g, b, wrap)
            table.insert(self.lines, text)
            return self
        end
    end
    return self
end

UIParent = newMockRegion("Frame", "UIParent", nil, nil)
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)

function GetCursorPosition()
    return 0, 0
end

--------------------------------------------------------------------------
-- Atlases: real Forever ("Camelot") chrome art, fetched out-of-band by
-- tests/preview/fetch_atlases.py into tests/preview/.atlas-cache/ (never
-- committed -- see tests/preview/README.md). When that cache is missing
-- (fresh checkout, no network) or doesn't have a given name yet,
-- GetAtlasInfo still returns a plausible non-nil table, so addon/
-- NineSlice logic that branches on "if info then" never has to
-- special-case headless tests.
--------------------------------------------------------------------------

local function atlasCacheDir()
    local src = debug.getinfo(1, "S").source
    local here = src:match("@(.*/)") or "./"
    return here .. "preview/.atlas-cache/"
end

-- Minimal JSON decoder: only needs to handle the shape fetch_atlases.py
-- writes (a flat object of objects: strings, numbers, booleans).
local function decodeJson(s)
    local pos = 1
    local function skipWs()
        local _, e = s:find("^%s*", pos)
        pos = e + 1
    end
    local parseValue
    local function parseString()
        pos = pos + 1 -- opening quote
        local startPos = pos
        local out = {}
        while true do
            local c = s:sub(pos, pos)
            if c == "" then
                error("unterminated string in atlas cache JSON")
            elseif c == '"' then
                out[#out + 1] = s:sub(startPos, pos - 1)
                pos = pos + 1
                return table.concat(out)
            elseif c == "\\" then
                out[#out + 1] = s:sub(startPos, pos - 1)
                out[#out + 1] = s:sub(pos + 1, pos + 1)
                pos = pos + 2
                startPos = pos
            else
                pos = pos + 1
            end
        end
    end
    local function parseObject()
        pos = pos + 1
        local t = {}
        skipWs()
        if s:sub(pos, pos) == "}" then
            pos = pos + 1
            return t
        end
        while true do
            skipWs()
            local key = parseString()
            skipWs()
            pos = pos + 1 -- ':'
            skipWs()
            t[key] = parseValue()
            skipWs()
            local c = s:sub(pos, pos)
            if c == "," then
                pos = pos + 1
            elseif c == "}" then
                pos = pos + 1
                return t
            else
                error("malformed object in atlas cache JSON at " .. pos)
            end
        end
    end
    local function parseArray()
        pos = pos + 1
        local t = {}
        skipWs()
        if s:sub(pos, pos) == "]" then
            pos = pos + 1
            return t
        end
        while true do
            skipWs()
            t[#t + 1] = parseValue()
            skipWs()
            local c = s:sub(pos, pos)
            if c == "," then
                pos = pos + 1
            elseif c == "]" then
                pos = pos + 1
                return t
            else
                error("malformed array in atlas cache JSON at " .. pos)
            end
        end
    end
    parseValue = function()
        skipWs()
        local c = s:sub(pos, pos)
        if c == '"' then
            return parseString()
        elseif c == "{" then
            return parseObject()
        elseif c == "[" then
            return parseArray()
        elseif s:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif s:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif s:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local _, e, num = s:find("^(-?%d+%.?%d*[eE]?[%+%-]?%d*)", pos)
            if not num then
                error("malformed value in atlas cache JSON at " .. pos)
            end
            pos = e + 1
            return tonumber(num)
        end
    end
    skipWs()
    return parseValue()
end

local atlasCache -- memoized; false = already tried and the file is missing
local function loadAtlasCache()
    if atlasCache ~= nil then
        return atlasCache or nil
    end
    local f = io.open(atlasCacheDir() .. "index.json", "r")
    if not f then
        atlasCache = false
        return nil
    end
    local text = f:read("*a")
    f:close()
    local ok, decoded = pcall(decodeJson, text)
    atlasCache = ok and decoded or false
    return atlasCache or nil
end
WowStub.LoadAtlasCache = loadAtlasCache -- exposed so tests/preview/record.lua validates against the same cache

C_Texture = {}

function C_Texture.GetAtlasInfo(name)
    if not name then
        return nil
    end
    local cache = loadAtlasCache()
    local e = cache and cache.elements and cache.elements[name]
    if e then
        return {
            width = e.width,
            height = e.height,
            leftTexCoord = e.left / e.imageWidth,
            rightTexCoord = e.right / e.imageWidth,
            topTexCoord = e.top / e.imageHeight,
            bottomTexCoord = e.bottom / e.imageHeight,
            tilesHorizontally = e.tilesHorizontally,
            tilesVertically = e.tilesVertically,
            file = e.png,
        }
    end
    -- Cache missing, or this name hasn't been fetched yet: a plausible
    -- fallback so NineSliceUtil / addon code that branches on the return
    -- (width/height, "if info then") still works with zero network.
    return {
        width = 32,
        height = 32,
        leftTexCoord = 0,
        rightTexCoord = 1,
        topTexCoord = 0,
        bottomTexCoord = 1,
        tilesHorizontally = name:sub(1, 1) == "_",
        tilesVertically = name:sub(1, 1) == "!",
        file = nil,
    }
end

--------------------------------------------------------------------------
-- NineSliceUtil: a faithful (trimmed -- no textureKit/threeSlice/named-
-- layout support, unused by this addon) port of Blizzard's
-- Interface/AddOns/Blizzard_SharedXML/NineSlice.lua ApplyLayout, so the
-- addon's own layout tables (TopLeftCorner/TopRightCorner/.../Center,
-- each {atlas=, layer=, x=, y=, mirrorLayout=}) produce the exact same
-- piece anchors a real client would: corners pinned to the container,
-- edges stretched between their two adjacent corners (tiling along the
-- stretch axis via the atlas's own tilesHorizontally/tilesVertically),
-- Center spanning TopLeftCorner.BOTTOMRIGHT to BottomRightCorner.TOPLEFT.
--------------------------------------------------------------------------

NineSliceUtil = {}

-- rawget, not container[pieceName]: an unset Pascal-case key like
-- "TopLeftCorner" would otherwise hit FrameMeta's generic no-op fallback
-- (which returns a callable, not nil, for any capitalized key) and look
-- like the piece already existed.
local function getNineSlicePiece(container, pieceName)
    local piece = rawget(container, pieceName)
    if piece then
        return piece, true
    end
    piece = container:CreateTexture()
    container[pieceName] = piece
    return piece, false
end

local function setupTextureCoordinates(piece, setupInfo, pieceLayout, userLayout)
    local left, right, top, bottom = 0, 1, 0, 1
    local mirrored = pieceLayout.mirrorLayout
    if mirrored == nil then
        mirrored = userLayout and userLayout.mirrorLayout
    end
    if mirrored then
        if setupInfo.mirrorVertical then
            top, bottom = bottom, top
        end
        if setupInfo.mirrorHorizontal then
            left, right = right, left
        end
    end
    piece:SetTexCoord(left, right, top, bottom)
end

local function setupPieceVisuals(piece, setupInfo, pieceLayout, textureKit, userLayout)
    setupTextureCoordinates(piece, setupInfo, pieceLayout, userLayout)
    local atlasName = pieceLayout.atlas
    if textureKit and atlasName then
        atlasName = atlasName:gsub("%%s", textureKit)
    end
    local info = atlasName and C_Texture.GetAtlasInfo(atlasName)
    piece:SetHorizTile(info and info.tilesHorizontally or false)
    piece:SetVertTile(info and info.tilesVertically or false)
    if info and atlasName then
        piece:SetAtlas(atlasName, true)
    end
end

local function setupCorner(container, piece, setupInfo, pieceLayout)
    piece:ClearAllPoints()
    piece:SetPoint(pieceLayout.point or setupInfo.point, container, pieceLayout.relativePoint or setupInfo.point,
        pieceLayout.x, pieceLayout.y)
end

local function setupEdge(container, piece, setupInfo, pieceLayout)
    piece:ClearAllPoints()
    piece:SetPoint(setupInfo.point, getNineSlicePiece(container, setupInfo.relativePieces[1]), setupInfo.relativePoint,
        pieceLayout.x, pieceLayout.y)
    piece:SetPoint(setupInfo.relativePoint, getNineSlicePiece(container, setupInfo.relativePieces[2]), setupInfo.point,
        pieceLayout.x1, pieceLayout.y1)
end

local function setupCenter(container, piece, setupInfo, pieceLayout)
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", getNineSlicePiece(container, "TopLeftCorner"), "BOTTOMRIGHT", pieceLayout.x, pieceLayout.y)
    piece:SetPoint("BOTTOMRIGHT", getNineSlicePiece(container, "BottomRightCorner"), "TOPLEFT", pieceLayout.x1, pieceLayout.y1)
end

local nineSliceSetup = {
    { pieceName = "TopLeftCorner", point = "TOPLEFT", fn = setupCorner },
    { pieceName = "TopRightCorner", point = "TOPRIGHT", mirrorHorizontal = true, fn = setupCorner },
    { pieceName = "BottomLeftCorner", point = "BOTTOMLEFT", mirrorVertical = true, fn = setupCorner },
    { pieceName = "BottomRightCorner", point = "BOTTOMRIGHT", mirrorHorizontal = true, mirrorVertical = true, fn = setupCorner },
    { pieceName = "TopEdge", point = "TOPLEFT", relativePoint = "TOPRIGHT",
        relativePieces = { "TopLeftCorner", "TopRightCorner" }, fn = setupEdge },
    { pieceName = "BottomEdge", point = "BOTTOMLEFT", relativePoint = "BOTTOMRIGHT",
        relativePieces = { "BottomLeftCorner", "BottomRightCorner" }, mirrorVertical = true, fn = setupEdge },
    { pieceName = "LeftEdge", point = "TOPLEFT", relativePoint = "BOTTOMLEFT",
        relativePieces = { "TopLeftCorner", "BottomLeftCorner" }, fn = setupEdge },
    { pieceName = "RightEdge", point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT",
        relativePieces = { "TopRightCorner", "BottomRightCorner" }, mirrorHorizontal = true, fn = setupEdge },
    { pieceName = "Center", fn = setupCenter },
}

function NineSliceUtil.ApplyLayout(container, userLayout, textureKit)
    for _, setup in ipairs(nineSliceSetup) do
        local pieceLayout = userLayout[setup.pieceName]
        if pieceLayout then
            local piece, alreadyExisted = getNineSlicePiece(container, setup.pieceName)
            if not alreadyExisted then
                container[setup.pieceName] = piece
                piece:SetDrawLayer(container.layoutTextureLayer or pieceLayout.layer or "BORDER",
                    container.layoutTextureSubLevel or pieceLayout.subLevel)
            end
            setup.fn(container, piece, setup, pieceLayout)
            setupPieceVisuals(piece, setup, pieceLayout, textureKit, userLayout)
        end
    end
end

--------------------------------------------------------------------------
-- ColorMixin / CreateColor: real clients always have ColorMixin defined;
-- addon code uses its presence as a "is the real SetGradient API
-- available" feature check before calling CreateColor. GetRGBA is the
-- one ColorMixin method addon code reads a color object back through.
--------------------------------------------------------------------------

ColorMixin = {}

function CreateColor(r, g, b, a)
    a = a or 1
    return { r = r, g = g, b = b, a = a, GetRGBA = function() return r, g, b, a end }
end

function WowStub.FireEvent(eventName, ...)
    for _, entry in ipairs(WowStub.frames) do
        if entry.events[eventName] and entry.scripts.OnEvent then
            entry.scripts.OnEvent(entry.frame, eventName, ...)
        end
    end
end

function WowStub.DeliverAddonMessage(sender, message)
    WowStub.FireEvent("CHAT_MSG_ADDON", "SideQuest1", message, "RAID", sender)
end
WowStub.FrameMeta = FrameMeta -- exposed so tests/preview can wrap method dispatch to record geometry

return WowStub
