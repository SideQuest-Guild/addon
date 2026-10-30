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
        return item.itemId, item.itemType, item.itemSubType, item.equipLoc, item.icon, item.classID, item.subclassID
    end,
}

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

    local shown = false
    self.Show = function() shown = true end
    self.Hide = function() shown = false end
    self.IsShown = function() return shown end

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

FrameMeta.__index = function(t, k)
    return function(self, ...)
        -- generic chainable no-op; returns the object itself for method chains
        return t
    end
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

return WowStub
