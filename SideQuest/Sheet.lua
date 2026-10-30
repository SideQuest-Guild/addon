-- SideQuest/Sheet.lua
-- Character sheet query (contract v2 SHEET_Q/SHEET_A): a member asks for
-- their own ledger + loot history; one online officer answers from the
-- imported on-demand "sheets" data.

SideQuest = SideQuest or {}
SideQuest.Sheet = {}
local Sheet = SideQuest.Sheet

local function now()
    return GetServerTime and GetServerTime() or 0
end

Sheet.lastAnswer = nil -- { ledger = {}, loot = {}, member_id = n } for the local player

--- Member action: ask the guild for my sheet.
function Sheet.Request()
    local payload = { id = SideQuest.NextId(), character = SideQuest.NormalizeUnit("player"), at = now() }
    SideQuest.Comm.SendSheetQuery(payload)
    SideQuest.Fire("SQ_SHEET_REQUESTED")
end

local function findMemberIdFor(character)
    for _, member in ipairs((SideQuestDB.guild and SideQuestDB.guild.members) or {}) do
        for _, char in ipairs(member.characters or {}) do
            if char.name == character then
                return member.member_id
            end
        end
    end
    return nil
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, sender)
    if msgType == "SHEET_Q" then
        local ok, req = pcall(SideQuestJSON.decode, payload)
        if not ok or not SideQuest.IsOfficer() then
            return
        end
        local requestKey = "SHEET:" .. req.id
        SideQuest.Comm.ScheduleAnswer(requestKey, function()
            local memberId = findMemberIdFor(req.character)
            local sheet = memberId and SideQuestDB.onDemand.sheets[tostring(memberId)]
            SideQuest.Comm.SendSheetAnswer({
                id = req.id,
                character = req.character,
                member_id = memberId,
                ledger = (sheet and sheet.ledger) or SideQuestJSON.EMPTY_ARRAY,
                loot = (sheet and sheet.loot) or SideQuestJSON.EMPTY_ARRAY,
                found = sheet ~= nil,
            })
        end)
    elseif msgType == "SHEET_A" then
        local ok, ans = pcall(SideQuestJSON.decode, payload)
        if not ok then
            return
        end
        SideQuest.Comm.SuppressAnswer("SHEET:" .. ans.id)
        if ans.character == SideQuest.NormalizeUnit("player") then
            Sheet.lastAnswer = ans
            SideQuest.Fire("SQ_SHEET_ANSWERED", ans)
        end
    end
end)

return Sheet
