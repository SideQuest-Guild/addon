-- SideQuest/News.lua
-- Guild news feed (contract v2 "news"): imported history plus live NEWS
-- items the recorder broadcasts as they happen (boss kills, loot, etc).

SideQuest = SideQuest or {}
SideQuest.News = {}
local News = SideQuest.News

local MAX_ITEMS = 60
local MAX_AGE_SECONDS = 14 * 24 * 60 * 60

local function now()
    return GetServerTime and GetServerTime() or 0
end

local function pruneAndSort()
    local items = SideQuestDB.guild.news
    local cutoff = now() - MAX_AGE_SECONDS
    local kept = {}
    for _, item in ipairs(items) do
        if (item.at or 0) >= cutoff then
            table.insert(kept, item)
        end
    end
    table.sort(kept, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)
    while #kept > MAX_ITEMS do
        table.remove(kept)
    end
    SideQuestDB.guild.news = kept
end

local function addItem(item)
    -- de-dupe by id
    for _, existing in ipairs(SideQuestDB.guild.news) do
        if existing.id == item.id then
            return
        end
    end
    table.insert(SideQuestDB.guild.news, item)
    pruneAndSort()
end

function News.Get()
    return SideQuestDB.guild.news
end

--- Insert a news item locally without broadcasting it (used for items that
-- already have their own broadcast, like ANN, and for echoing them into
-- the news feed on the sender's and receivers' sides alike).
function News.Add(item)
    item.id = item.id or SideQuest.NextId()
    item.at = item.at or now()
    addItem(item)
    SideQuest.Fire("SQ_NEWS_UPDATED")
end

--- Officer action: broadcast one live news item the recorder just saw
-- (a boss kill, a loot award, etc). Also stores it locally.
function News.Broadcast(item)
    item.id = item.id or SideQuest.NextId()
    item.at = item.at or now()
    addItem(item)
    SideQuest.Comm.BroadcastNews(item)
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, _sender)
    if msgType ~= "NEWS" then
        return
    end
    local ok, item = pcall(SideQuestJSON.decode, payload)
    if not ok then
        return
    end
    addItem(item)
    SideQuest.Fire("SQ_NEWS_UPDATED")
end)

-- Fed automatically from the recorder's own boss kills, matching the kind
-- the contract uses for "boss_kill"/"first_kill".
SideQuest.On("SQ_ENCOUNTER_RECORDED", function(encounterRow, wasFirstKill)
    if not (encounterRow.success and SideQuest.IsOfficer()) then
        return
    end
    News.Broadcast({
        kind = wasFirstKill and "first_kill" or "boss_kill",
        text = encounterRow.name .. " defeated",
        character = nil,
        item_id = nil,
        quality = nil,
    })
end)

return News
