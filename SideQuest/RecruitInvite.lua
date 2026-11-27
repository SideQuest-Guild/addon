-- SideQuest/RecruitInvite.lua
-- After you post a recruiting message in a public channel (Say, Yell, or a numbered channel like General or
-- Trade), whispers from people outside the guild queue up in a popup with an Invite button for each. Nothing is
-- invited until you click: C_GuildInfo.Invite runs only from that button.
--
-- A post counts when it's yours and names the guild or says "recruit". The window stays open for WINDOW seconds
-- after the latest such post. Anyone who can invite to the guild (CanGuildInvite) gets it, not only officers,
-- since recruitment drives pay members for their invites. Someone you Skip is never offered again, on any of your
-- characters: `SideQuestDB.recruitSkipped[key] = serverTime` (local only; the export never carries it).

SideQuest = SideQuest or {}
SideQuest.RecruitInvite = {}
local RecruitInvite = SideQuest.RecruitInvite

RecruitInvite.WINDOW = 15 * 60
RecruitInvite.MAX_QUEUE = 20
RecruitInvite.TEXT_BYTES = 120

-- Chat events whose sender can be you posting to people outside the guild.
local POST_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }
-- specialFlags on a whisper from Blizzard staff; never offered an invite.
local STAFF_FLAGS = { GM = true, DEV = true }

local function now()
    return GetServerTime and GetServerTime() or 0
end

function RecruitInvite.ResetState()
    RecruitInvite.openUntil = nil
    RecruitInvite.queue = {} -- { key, name, text, at }, oldest first
    RecruitInvite.invited = {} -- key -> true: invited this session, never offered again
end
RecruitInvite.ResetState()

--- True when this character may send guild invites at all.
function RecruitInvite.CanInvite()
    return SideQuest.IsGuildMember() == true and type(CanGuildInvite) == "function" and CanGuildInvite() == true
end

--- True when `text` reads like a recruiting post: it names the guild or says "recruit".
function RecruitInvite.IsRecruitmentPost(text)
    text = SideQuest.Unsecret(text)
    if type(text) ~= "string" or text == "" then
        return false
    end
    local lower = text:lower()
    local guild = (GetGuildInfo and SideQuest.Unsecret(GetGuildInfo("player"))) or SideQuest.GUILD_NAME
    return lower:find("recruit", 1, true) ~= nil or lower:find(guild:lower(), 1, true) ~= nil
end

function RecruitInvite.IsOpen()
    return RecruitInvite.openUntil ~= nil and now() < RecruitInvite.openUntil
end

function RecruitInvite.Queue()
    return RecruitInvite.queue
end

local function isMe(sender, guid)
    local myGuid = SideQuest.SafeUnitGUID("player")
    guid = SideQuest.Unsecret(guid)
    if myGuid and guid and guid ~= "" then
        return guid == myGuid
    end
    local key = SideQuest.CanonicalName(sender)
    return key ~= nil and key == SideQuest.NormalizeUnit("player")
end

local function inGuild(key)
    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return false
    end
    for i = 1, GetNumGuildMembers() do
        local name = GetGuildRosterInfo(i) -- only the name: the second return is the rank, not a surname
        if SideQuest.CanonicalName(name) == key then
            return true
        end
    end
    return false
end

local function indexOf(key)
    for i, row in ipairs(RecruitInvite.queue) do
        if row.key == key then
            return i
        end
    end
    return nil
end

--- Whisperers you skipped (key -> server time), kept in the save file so they stay skipped after a relog.
local function skipped()
    if type(SideQuestDB) ~= "table" then
        return {}
    end
    SideQuestDB.recruitSkipped = SideQuestDB.recruitSkipped or {}
    return SideQuestDB.recruitSkipped
end

--- One of your own public chat lines: a recruiting post (re)opens the whisper window.
function RecruitInvite.OnPost(text, sender, guid)
    if not isMe(sender, guid) or not RecruitInvite.IsRecruitmentPost(text) or not RecruitInvite.CanInvite() then
        return
    end
    local wasOpen = RecruitInvite.IsOpen()
    RecruitInvite.openUntil = now() + RecruitInvite.WINDOW
    if not wasOpen then
        SideQuest.Print(string.format("Recruiting post seen. For %d minutes, whispers from people outside the guild "
            .. "get an Invite button.", RecruitInvite.WINDOW / 60))
    end
end

--- A whisper to you: while the window is open, a non-member's whisper joins the popup's queue.
function RecruitInvite.OnWhisper(text, sender, flags)
    if not RecruitInvite.IsOpen() or STAFF_FLAGS[SideQuest.Unsecret(flags) or ""] then
        return
    end
    local key = SideQuest.CanonicalName(sender)
    if not key or key == SideQuest.NormalizeUnit("player") or RecruitInvite.invited[key] or skipped()[key]
        or inGuild(key) then
        return
    end
    local row = {
        key = key,
        name = SideQuest.GameName(key),
        text = SideQuest.Utf8Cut(SideQuest.Unsecret(text) or "", RecruitInvite.TEXT_BYTES),
        at = now(),
    }
    local existing = indexOf(key)
    if existing then
        RecruitInvite.queue[existing] = row
    else
        table.insert(RecruitInvite.queue, row)
        if #RecruitInvite.queue > RecruitInvite.MAX_QUEUE then
            table.remove(RecruitInvite.queue, 1)
        end
    end
    SideQuest.Fire("SQ_RECRUIT_INVITES_UPDATED")
end

--- Send the guild invite for a queued whisperer. Only the popup's Invite button calls this.
function RecruitInvite.Invite(key)
    local i = indexOf(key)
    if not i then
        return false
    end
    if not (C_GuildInfo and C_GuildInfo.Invite) then
        SideQuest.Print("This client has no guild invite call (C_GuildInfo.Invite).")
        return false
    end
    local row = table.remove(RecruitInvite.queue, i)
    C_GuildInfo.Invite(row.name)
    RecruitInvite.invited[key] = true
    SideQuest.Print("Guild invite sent to " .. row.name .. ".")
    SideQuest.Fire("SQ_RECRUIT_INVITES_UPDATED")
    return true
end

--- Drop a whisperer from the queue without inviting, for good: their later whispers never come back.
function RecruitInvite.Skip(key)
    if key then
        skipped()[key] = now()
    end
    local i = indexOf(key)
    if i then
        table.remove(RecruitInvite.queue, i)
        SideQuest.Fire("SQ_RECRUIT_INVITES_UPDATED")
    end
end

--- Empty the queue (the popup was closed). Unlike Skip, someone who whispers again shows up again.
function RecruitInvite.Clear()
    if #RecruitInvite.queue > 0 then
        RecruitInvite.queue = {}
        SideQuest.Fire("SQ_RECRUIT_INVITES_UPDATED")
    end
end

for _, event in ipairs(POST_EVENTS) do
    SideQuest.On(event, function(text, sender, _, _, _, _, _, _, _, _, _, guid)
        RecruitInvite.OnPost(text, sender, guid)
    end)
    SideQuest.RegisterGameEvent(event)
end

SideQuest.On("CHAT_MSG_WHISPER", function(text, sender, _, _, _, flags)
    RecruitInvite.OnWhisper(text, sender, flags)
end)
SideQuest.RegisterGameEvent("CHAT_MSG_WHISPER")

return RecruitInvite
