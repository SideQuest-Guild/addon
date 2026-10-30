-- SideQuest/Bank.lua
-- Guild bank ledger capture (contract v2 "bank"): guild bank log APIs are
-- unverified on Forever per the researched addon facts; this module
-- detects C_GuildBank, captures the visible log when the bank frame opens,
-- and degrades (no rows, UI says so) when the API is missing.

SideQuest = SideQuest or {}
SideQuest.Bank = {}
local Bank = SideQuest.Bank

local function now()
    return GetServerTime and GetServerTime() or 0
end

function Bank.IsAvailable()
    return C_GuildBank ~= nil
        and type(C_GuildBank.GetNumTransactions) == "function"
        and type(C_GuildBank.GetTransaction) == "function"
end

-- Deterministic id: the game's bank log has none, so hash the fields that
-- make a row unique (tab, type, time-bucket, character, item/money/count).
local function deterministicId(tab, kind, character, itemId, count, money, atBucket)
    local raw = table.concat({ tab, kind, character or "", itemId or 0, count or 0, money or 0, atBucket }, "|")
    local hash = 0
    for i = 1, #raw do
        hash = (hash * 31 + raw:byte(i)) % 2147483647
    end
    return "bank-" .. tostring(hash)
end

local KIND_MAP = {
    [1] = "deposit", [2] = "withdraw", [3] = "move", [4] = "repair",
    [5] = "buy_tab", [6] = "deposit_money", [7] = "withdraw_money",
}

--- Capture the currently-open guild bank tab's transaction log into
-- pending.bank (insert-only by deterministic id). Returns the number of
-- new rows captured, or nil if the API is unavailable.
function Bank.CaptureOpenTab(tabIndex)
    if not Bank.IsAvailable() then
        return nil
    end
    tabIndex = tabIndex or 1
    local seen = {}
    for _, row in ipairs(SideQuestDB.pending.bank) do
        seen[row.id] = true
    end

    local added = 0
    local total = C_GuildBank.GetNumTransactions(tabIndex) or 0
    for i = 1, total do
        local info = C_GuildBank.GetTransaction(tabIndex, i)
        if info then
            local kind = KIND_MAP[info.type] or "deposit"
            local atBucket = info.year and (info.year * 100000 + (info.month or 0) * 1000 + (info.day or 0))
                or now()
            local id = deterministicId(tabIndex, kind, info.name, info.itemID, info.count, info.money, atBucket)
            if not seen[id] then
                seen[id] = true
                table.insert(SideQuestDB.pending.bank, {
                    id = id,
                    at = now(),
                    character = info.name and SideQuest.NormalizeName(info.name, GetNormalizedRealmName and GetNormalizedRealmName() or "") or "",
                    kind = kind,
                    item_id = info.itemID,
                    item_name = info.itemLink,
                    count = info.count or 0,
                    money = info.money or 0,
                    tab = tabIndex,
                })
                added = added + 1
            end
        end
    end
    SideQuest.Fire("SQ_BANK_CAPTURED", added)
    return added
end

SideQuest.On("GUILDBANKFRAME_OPENED", function()
    if SideQuest.IsOfficer() then
        Bank.CaptureOpenTab(1)
    end
end)
SideQuest.RegisterGameEvent("GUILDBANKFRAME_OPENED")

return Bank
