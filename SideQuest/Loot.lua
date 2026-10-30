-- SideQuest/Loot.lua
-- Loot bidding over RAID addon messages, GP cost calculation, officer
-- ranking and award recording.

SideQuest = SideQuest or {}
SideQuest.Loot = {}
local Loot = SideQuest.Loot

local function pending()
    return SideQuestDB.pending
end

local function now()
    return GetServerTime and GetServerTime() or 0
end

--------------------------------------------------------------------------
-- Bid ordering (contract: main spec by PR [raiders, then trials], then off
-- spec by PR, then alt, then disenchant; ties by EP then roll). Council
-- items are decided by officers and are not auto-ranked.
--------------------------------------------------------------------------

local GROUP_ORDER = {
    ms_raider = 1,
    ms_trial = 2,
    os = 3,
    alt = 4,
    de = 5,
}

local TRIAL_WINDOW_DAYS = 14

function Loot.IsTrial(bid, atTime)
    if not bid.trial then
        return false
    end
    if not bid.trial_started_at then
        return true
    end
    atTime = atTime or now()
    local days = (atTime - bid.trial_started_at) / 86400
    return days < TRIAL_WINDOW_DAYS
end

function Loot.GroupFor(bid, atTime)
    if bid.response == "ms" then
        if Loot.IsTrial(bid, atTime) then
            return GROUP_ORDER.ms_trial
        end
        return GROUP_ORDER.ms_raider
    elseif bid.response == "os" then
        return GROUP_ORDER.os
    elseif bid.response == "alt" then
        return GROUP_ORDER.alt
    elseif bid.response == "de" then
        return GROUP_ORDER.de
    end
    return nil -- council/bank: not auto-ranked
end

--- Rank a list of bids: { character, response, pr, ep, roll, trial,
-- trial_started_at }. Returns a new sorted array (does not mutate input).
-- Entries whose response has no ranking group (council/bank) are dropped;
-- those are resolved manually by an officer.
function Loot.RankBids(bids, atTime)
    local ranked = {}
    for _, b in ipairs(bids) do
        local group = Loot.GroupFor(b, atTime)
        if group then
            ranked[#ranked + 1] = b
            b._group = group
        end
    end
    table.sort(ranked, function(a, b)
        if a._group ~= b._group then
            return a._group < b._group
        end
        local aPr, bPr = a.pr or 0, b.pr or 0
        if aPr ~= bPr then
            return aPr > bPr
        end
        local aEp, bEp = a.ep or 0, b.ep or 0
        if aEp ~= bEp then
            return aEp > bEp
        end
        return (a.roll or 0) > (b.roll or 0)
    end)
    for _, b in ipairs(ranked) do
        b._group = nil
    end
    return ranked
end

--------------------------------------------------------------------------
-- GP + award recording
--------------------------------------------------------------------------

--- Record a loot award: writes the loot row plus its GP ledger twin, per
-- the contract (amount may be 0 for alt/de/bank but the row is still written).
-- @param item table { item_id, item_name, quality, inv_type }
-- @param character string normalized "Name-Realm"
-- @param response string ms|os|alt|council|de|bank
-- @param sessionId string|nil
-- @param encounterRowId string|nil
-- @param gpOpts table forwarded to Rules.ComputeGP, plus optional `gpOverride`
function Loot.AwardLoot(item, character, response, sessionId, encounterRowId, gpOpts)
    gpOpts = gpOpts or {}
    local gp
    if gpOpts.gpOverride ~= nil then
        gp = gpOpts.gpOverride
    else
        gp = SideQuest.Rules.ComputeGP(item.inv_type, response, gpOpts)
    end

    local lootRow = {
        id = SideQuest.NextId(),
        session_id = sessionId,
        encounter_row_id = encounterRowId,
        item_id = item.item_id,
        item_name = item.item_name,
        quality = item.quality,
        inv_type = item.inv_type,
        character = character,
        response = response,
        gp = gp,
        at = now(),
        officer = SideQuest.NormalizeUnit("player"),
        voided = false,
    }
    table.insert(pending().loot, lootRow)

    local awardRow = {
        id = SideQuest.NextId(),
        session_id = sessionId,
        kind = "gp",
        character = character,
        amount = gp,
        reason = "loot",
        note = item.item_name,
        loot_id = lootRow.id,
        at = lootRow.at,
        officer = lootRow.officer,
        voided = false,
    }
    table.insert(pending().awards, awardRow)

    SideQuest.Print(character .. " won " .. tostring(item.item_name) .. " for " .. tostring(gp) .. " GP"
        .. "  [Undo: /sq undo " .. lootRow.id .. "]")

    return lootRow.id, awardRow.id
end

--- Undo a loot award: voids the loot row and its linked GP award row.
function Loot.Undo(lootId)
    local voidedAny = false
    for _, row in ipairs(pending().loot) do
        if row.id == lootId then
            row.voided = true
            voidedAny = true
        end
    end
    for _, row in ipairs(pending().awards) do
        if row.loot_id == lootId then
            row.voided = true
        end
    end
    if voidedAny then
        SideQuest.Print("Undid loot award " .. lootId)
    end
    return voidedAny
end

--------------------------------------------------------------------------
-- Master-loot window items
--------------------------------------------------------------------------

function Loot.GetLootWindowItems()
    local items = {}
    if not GetNumLootItems then
        return items
    end
    local n = GetNumLootItems()
    for slot = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        if link then
            items[#items + 1] = { slot = slot, link = link }
        end
    end
    return items
end

function Loot.GiveMasterLoot(slot, candidateIndex)
    if GiveMasterLoot then
        local ok, result = pcall(GiveMasterLoot, slot, candidateIndex)
        return ok and result ~= false
    end
    return false
end

--------------------------------------------------------------------------
-- Bidding session (officer opens, raiders respond over RAID)
--------------------------------------------------------------------------

Loot.activeBid = nil -- { itemLink, startedAt, timeout, responses = { [char]=response } }

function Loot.OpenBid(itemLink, timeoutSeconds)
    timeoutSeconds = timeoutSeconds or 30
    Loot.activeBid = {
        itemLink = itemLink,
        startedAt = now(),
        timeout = timeoutSeconds,
        responses = {},
    }
    local sent = select(1, SideQuest.Comm.SendRaw("BID_OPEN|" .. itemLink .. "|" .. tostring(timeoutSeconds), "RAID"))
    if not sent then
        SideQuest.Print("Could not broadcast the bid (addon messages likely blocked here, e.g. inside an instance)."
            .. " Use the officer window to award manually.")
    end
    SideQuest.Fire("SQ_BID_OPENED", Loot.activeBid)
    return Loot.activeBid
end

function Loot.SubmitBid(response)
    SideQuest.Comm.SendBidResponse(response)
end

function Loot.RecordResponse(character, response)
    if not Loot.activeBid then
        return
    end
    Loot.activeBid.responses[character] = response
end

function Loot.CloseBid()
    local bid = Loot.activeBid
    Loot.activeBid = nil
    return bid
end

SideQuest.On("SQ_COMM_MESSAGE", function(msgType, payload, sender)
    if msgType == "BID_OPEN" then
        local link, timeout = payload:match("^(.-)|(%d+)$")
        SideQuest.Fire("SQ_BID_POPUP", link, tonumber(timeout), sender)
    elseif msgType == "BID_RESP" then
        Loot.RecordResponse(sender, payload)
    end
end)

SideQuest.RegisterSlash("bid", function(rest)
    if rest == "" then
        SideQuest.Print("Usage: /sq bid <itemlink>")
        return
    end
    if SideQuest.IsOfficer() then
        Loot.OpenBid(rest)
    else
        -- a raider pasting a link they want to bid on outside the loot
        -- window: just submit a main-spec bid intent for officers to see
        SideQuest.Fire("SQ_RAIDER_BID_REQUEST", rest, SideQuest.NormalizeUnit("player"))
    end
end, "officers: open bidding on an item link (e.g. one traded after pickup)")

SideQuest.RegisterSlash("undo", function(rest)
    local id = rest:match("^%S+")
    if not id then
        SideQuest.Print("Usage: /sq undo <id>")
        return
    end
    if not (Loot.Undo(id) or SideQuest.Recorder.Undo(id)) then
        SideQuest.Print("No matching row for " .. id)
    end
end, "undo an EP/GP award by id")

return Loot
