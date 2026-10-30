-- SideQuest/Announce.lua
-- Announcements (contract v2 "announcements"): an officer writes once; it
-- shows in every online member's SideQuest window (news feed + toast), in
-- guild chat, and is queued for Discord after the next sync.

SideQuest = SideQuest or {}
SideQuest.Announce = {}
local Announce = SideQuest.Announce

local function now()
    return GetServerTime and GetServerTime() or 0
end

--- Officer action: post an announcement. Queues it for export, broadcasts
-- it to the guild over addon messages, drops it in guild chat, and is
-- never sent during combat (queued until PLAYER_REGEN_ENABLED).
function Announce.Post(text, toDiscord)
    if not SideQuest.IsOfficer() then
        SideQuest.Print("Only officers can post announcements.")
        return
    end
    local officer = SideQuest.NormalizeUnit("player")
    local item = {
        id = SideQuest.NextId(),
        text = text,
        officer = officer,
        at = now(),
        discord = toDiscord and true or nil,
    }
    table.insert(SideQuestDB.pending.announcements, item)

    SideQuest.WhenOutOfCombat(function()
        SideQuest.Comm.BroadcastAnnounce(item)
        if SendChatMessage then
            SendChatMessage("[SideQuest] " .. text, "GUILD")
        end
    end)

    -- feed the news feed locally for the officer who posted it (members
    -- feed theirs from the received ANN message below)
    SideQuest.News.Add({ id = item.id, kind = "announcement", text = text, character = officer, at = item.at })
    SideQuest.Fire("SQ_ANNOUNCEMENT_POSTED", item)
    return item
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, _sender)
    if msgType ~= "ANN" then
        return
    end
    local ok, item = pcall(SideQuestJSON.decode, payload)
    if not ok then
        return
    end
    SideQuest.News.Add({ id = item.id, kind = "announcement", text = item.text, character = item.officer, at = item.at })
    SideQuest.Fire("SQ_ANNOUNCEMENT_RECEIVED", item) -- UI: toast, never during combat
end)

return Announce
