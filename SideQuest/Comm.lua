-- SideQuest/Comm.lua
-- Addon-message transport: chunking, throttling and failure detection for
-- SendAddonMessage (which likely fails inside instances on Forever per the
-- researched addon facts). Used for standings broadcast (GUILD), standby
-- requests from outside instances (GUILD) and loot bidding (RAID).

SideQuest = SideQuest or {}
SideQuest.Comm = {}
local Comm = SideQuest.Comm

Comm.PREFIX = "SideQuest1"
Comm.MAX_CHUNK = 240 -- stay comfortably under the ~255 byte addon message limit

local sendQueue = {}
local ticker = nil

--- Low-level send. Returns success(bool), resultEnum(any). Never throws.
function Comm.SendRaw(message, channel, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return false, nil
    end
    local result = C_ChatInfo.SendAddonMessage(Comm.PREFIX, message, channel, target)
    local success = result == nil or result == (Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success)
    if Enum and Enum.SendAddonMessageResult then
        success = result == Enum.SendAddonMessageResult.Success
    end
    return success, result
end

--- Queue a message for throttled delivery. Drains at
-- SideQuestDB.settings.standingsBroadcastThrottle seconds per message.
function Comm.Queue(message, channel, target)
    table.insert(sendQueue, { message = message, channel = channel, target = target })
    Comm.StartDrain()
end

local function drainOne()
    local item = table.remove(sendQueue, 1)
    if not item then
        if ticker and ticker.Cancel then
            ticker:Cancel()
        end
        ticker = nil
        return
    end
    Comm.SendRaw(item.message, item.channel, item.target)
end

function Comm.StartDrain()
    if ticker then
        return
    end
    local interval = (SideQuestDB and SideQuestDB.settings and SideQuestDB.settings.standingsBroadcastThrottle) or 2
    if C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(interval, drainOne)
    else
        -- test/headless environment: drain synchronously
        while #sendQueue > 0 do
            drainOne()
        end
    end
end

--- Split a long string into Comm.MAX_CHUNK-sized pieces, each prefixed with
-- "<msgType>|<index>|<total>|" so the receiver can reassemble out of order
-- chunks (addon messages are not guaranteed in order across chat throttling).
function Comm.ChunkMessage(msgType, payload)
    local total = math.max(1, math.ceil(#payload / Comm.MAX_CHUNK))
    local chunks = {}
    for i = 1, total do
        local startIdx = (i - 1) * Comm.MAX_CHUNK + 1
        local piece = payload:sub(startIdx, startIdx + Comm.MAX_CHUNK - 1)
        chunks[i] = msgType .. "|" .. i .. "|" .. total .. "|" .. piece
    end
    return chunks
end

local reassembly = {} -- key (sender..msgType) -> { total=n, got={}, [i]=piece }

--- Feed one received chunk; returns the fully reassembled payload string
-- once every piece has arrived, otherwise nil.
function Comm.ReceiveChunk(sender, rawMessage)
    local msgType, idxStr, totalStr, piece = rawMessage:match("^(%a+)|(%d+)|(%d+)|(.*)$")
    if not msgType then
        return nil, nil
    end
    local idx = tonumber(idxStr)
    local total = tonumber(totalStr)
    local key = sender .. "|" .. msgType

    reassembly[key] = reassembly[key] or { total = total, got = 0, pieces = {} }
    local entry = reassembly[key]
    if not entry.pieces[idx] then
        entry.got = entry.got + 1
    end
    entry.pieces[idx] = piece

    if entry.got >= entry.total then
        local parts = {}
        for i = 1, entry.total do
            parts[i] = entry.pieces[i] or ""
        end
        reassembly[key] = nil
        return msgType, table.concat(parts)
    end

    return nil, nil
end

--- Broadcast standings to the guild as chunked, throttled GUILD messages.
function Comm.BroadcastStandings(payloadString)
    for _, chunk in ipairs(Comm.ChunkMessage("STANDINGS", payloadString)) do
        Comm.Queue(chunk, "GUILD")
    end
end

function Comm.AnnounceRecorder(recorderName)
    Comm.SendRaw("RECORDER|" .. recorderName, "RAID")
end

function Comm.RequestStandby(characterName)
    return Comm.SendRaw("STANDBY_REQ|" .. characterName, "GUILD")
end

function Comm.SendBidOpen(itemLink, timeoutSeconds)
    Comm.SendRaw("BID_OPEN|" .. itemLink .. "|" .. tostring(timeoutSeconds), "RAID")
end

function Comm.SendBidResponse(response)
    Comm.SendRaw("BID_RESP|" .. response, "RAID")
end

if CreateFrame then
    local frame = CreateFrame("Frame", "SideQuestCommFrame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, event, prefix, message, _channel, sender)
        if prefix ~= Comm.PREFIX then
            return
        end
        local msgType, full = Comm.ReceiveChunk(sender, message)
        if msgType then
            SideQuest.Fire("SQ_COMM_MESSAGE", msgType, full, sender)
        else
            -- unchunked single-piece control messages (RECORDER|, STANDBY_REQ|, BID_*)
            local kind, rest = message:match("^(%a+)|(.*)$")
            if kind then
                SideQuest.Fire("SQ_COMM_MESSAGE", kind, rest, sender)
            end
        end
    end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
    end
end

return Comm
