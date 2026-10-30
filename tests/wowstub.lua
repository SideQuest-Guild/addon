-- tests/wowstub.lua
-- Minimal WoW client API stub for running SideQuest's Lua under plain
-- LuaJIT (5.1 semantics) outside the game. Exposes a `WowStub` control
-- table tests use to drive roster/instance/comm state and fire events.

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
    guildName = "SideQuest",
    realm = "Whitemane",
    lootItems = {},
    invites = {},
    convertToRaidCalls = 0,
    -- v2
    guildRoster = {}, -- list of { name, rank, rankIndex, level, class, zone, online }
    tradeSkill = nil, -- { name, skill, maxSkill, recipes = { { id, name, type } } } or nil (window closed)
    bankTransactions = {}, -- tabIndex -> list of { type, name, itemID, itemLink, count, money, year, month, day }
    inCombat = false,
    buffs = {}, -- list of buff names on "player"
    durability = nil, -- 0-100 or nil (unknown)
    itemCounts = {}, -- itemId -> count
    raidSubgroups = {}, -- unit ("raid1"...) -> current subgroup
    subgroupCalls = {}, -- recorded SetRaidSubgroup(index, group) calls
}

--------------------------------------------------------------------------
-- Time
--------------------------------------------------------------------------

function GetServerTime()
    return WowStub.time
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

function UnitClass(unit)
    local u = WowStub.units[unit]
    if not u then
        return nil, nil
    end
    return u.class, u.class
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

function issecretvalue(v)
    return false
end

--------------------------------------------------------------------------
-- Guild / officer
--------------------------------------------------------------------------

C_GuildInfo = {
    CanEditOfficerNote = function()
        return WowStub.isOfficer
    end,
}

function GetGuildInfo(unit)
    return WowStub.guildName, "Officer", 0
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
-- Professions (v2)
--------------------------------------------------------------------------

function GetTradeSkillLine()
    if not WowStub.tradeSkill then
        return nil
    end
    return WowStub.tradeSkill.name, WowStub.tradeSkill.skill, WowStub.tradeSkill.maxSkill
end

function GetNumTradeSkills()
    return WowStub.tradeSkill and #WowStub.tradeSkill.recipes or 0
end

function GetTradeSkillInfo(i)
    local r = WowStub.tradeSkill and WowStub.tradeSkill.recipes[i]
    if not r then
        return nil
    end
    return r.name, r.type or "trade", nil, nil, nil, r.id
end

--------------------------------------------------------------------------
-- Guild bank (v2)
--------------------------------------------------------------------------

C_GuildBank = {
    GetNumTransactions = function(tabIndex)
        return #(WowStub.bankTransactions[tabIndex] or {})
    end,
    GetTransaction = function(tabIndex, i)
        local list = WowStub.bankTransactions[tabIndex] or {}
        return list[i]
    end,
}

--------------------------------------------------------------------------
-- Combat lockdown + chat (v2)
--------------------------------------------------------------------------

function InCombatLockdown()
    return WowStub.inCombat
end

function SendChatMessage(msg, channel)
    table.insert(WowStub.chatLog, { msg = msg, channel = channel })
end

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

function ConvertToRaid()
    WowStub.convertToRaidCalls = WowStub.convertToRaidCalls + 1
    WowStub.inRaid = true
end

function InviteUnit(name)
    table.insert(WowStub.invites, name)
end

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
}

--------------------------------------------------------------------------
-- Timers: resolved synchronously for deterministic tests
--------------------------------------------------------------------------

C_Timer = {
    After = function(seconds, fn)
        fn()
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

    self.CreateFontString = function(_, fsName, layer, tmpl)
        return newMockRegion("FontString", fsName, self, tmpl)
    end
    self.CreateTexture = function(_, texName, layer, tmpl)
        return newMockRegion("Texture", texName, self, tmpl)
    end

    local shown = true -- real WoW Frame/Texture/FontString default to shown; Hide() is explicit
    self.Show = function() shown = true end
    self.Hide = function() shown = false end
    self.IsShown = function() return shown end
    self.SetShown = function(_, cond) shown = cond and true or false end

    self.SetScrollChild = function(_, child) self.__scrollChild = child end
    self.GetScrollChild = function() return self.__scrollChild end

    local text = ""
    self.SetText = function(_, t) text = t or "" end
    self.GetText = function() return text end

    setmetatable(self, FrameMeta)
    table.insert(WowStub.frames, { frame = self, events = events, scripts = scripts, name = name })
    self.__events = events
    self.__scripts = scripts
    return self
end

-- Only PascalCase keys (the WoW API convention: SetPoint, CreateTexture,
-- IsShown, ...) fall back to a chainable no-op; addon code also stores its
-- own lowerCamelCase data fields directly on these tables (panel.rows,
-- chamber.emptyText, ...) and those must read back as real nil when unset,
-- exactly like a real Frame, or "if not x.field then" guards never fire.
FrameMeta.__index = function(t, k)
    if type(k) == "string" and k:match("^%u") then
        return function(self, ...)
            -- generic chainable no-op; returns the object itself for method chains
            return t
        end
    end
    return nil
end

function CreateFrame(kind, name, parent, template)
    return newMockRegion(kind, name, parent, template)
end

UIParent = newMockRegion("Frame", "UIParent", nil, nil)

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
