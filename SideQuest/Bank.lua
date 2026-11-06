-- SideQuest/Bank.lua
-- Guild bank ledger capture (contract v2 "bank"). Forever exposes the guild
-- bank transaction *log* through the old globals -- GetNumGuildBankTransactions,
-- GetGuildBankTransaction, GetNumGuildBankMoneyTransactions,
-- GetGuildBankMoneyTransaction, QueryGuildBankLog -- not a C_GuildBank
-- namespace; on Forever C_GuildBank only has IsGuildBankEnabled
-- (Ketho/BlizzardInterfaceResources forever branch, Resources/GlobalAPI.lua,
-- and Gethe/wow-ui-source forever branch,
-- Interface/AddOns/Blizzard_GuildBankUI/Mainline/Blizzard_GuildBankUI.lua
-- GuildBankFrame_UpdateLog/GuildBankFrame_UpdateMoneyLog). Bank addons like
-- Bagnon read bank *contents* (GetGuildBankItemInfo), a separate API that's
-- always queryable; it says nothing about the log.
--
-- The log itself is only populated once QueryGuildBankLog(tab) has been
-- answered by GUILDBANKLOG_UPDATE, which the server only sends while the
-- bank frame is open (interacting with the banker), same as classic. So we
-- query both the item log (tab 1) and the money log (the slot after the
-- last item tab) whenever the bank opens, and capture whatever the next
-- GUILDBANKLOG_UPDATE delivers.
--
-- GetGuildBankTransaction/GetGuildBankMoneyTransaction's year/month/day/hour
-- are time *elapsed* since the transaction, not a date (per
-- GuildBankFrame_UpdateLog/UpdateMoneyLog formatting them through
-- TimeUtil.GetRecentTimeDate) -- the same row reports a bigger elapsed time
-- every time it's re-queried. So rows can't be deduped by hashing that
-- value directly (it changes) or by just checking pending.bank (cleared by
-- `/sq export clear`): SideQuestDB.bankSeen remembers every row's estimated
-- timestamp across exports, keyed by its unchanging content, and a repeat
-- capture matches against it within a tolerance that absorbs both the
-- elapsed-hour rounding and the hour that passes between two captures.

SideQuest = SideQuest or {}
SideQuest.Bank = {}
local Bank = SideQuest.Bank

local MONEY_LOG_TAB = (MAX_GUILDBANK_TABS or 8) + 1
local SEEN_TOLERANCE = 2 * 3600 -- absorbs floored elapsed-hours + time between captures
local SEEN_PRUNE_AGE = 120 * 24 * 3600

local function now()
    return GetServerTime and GetServerTime() or 0
end

function Bank.IsAvailable()
    return type(GetNumGuildBankTransactions) == "function"
        and type(GetGuildBankTransaction) == "function"
end

function Bank.IsMoneyLogAvailable()
    return type(GetNumGuildBankMoneyTransactions) == "function"
        and type(GetGuildBankMoneyTransaction) == "function"
end

-- The row's unchanging identity: everything but when it happened.
local function contentKey(tab, kind, character, itemKey, count, money)
    return table.concat({ tab, kind, character or "", itemKey or "", count or 0, money or 0 }, "|")
end

-- Deterministic id from the content key and its estimated time.
local function hashId(key, at, ordinal)
    local raw = key .. "|" .. tostring(at) .. "|" .. tostring(ordinal)
    local hash = 0
    for i = 1, #raw do
        hash = (hash * 31 + raw:byte(i)) % 2147483647
    end
    return "bank-" .. tostring(hash)
end

-- GetGuildBankTransaction only returns an item link, not an item id; the id
-- is embedded in the link string ("|Hitem:12345:...").
local function itemIdFromLink(link)
    local id = link and link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function normalized(name)
    return name and SideQuest.NormalizeName(name) or ""
end

-- year/month/day/hour from the API are elapsed time, not a date.
local function estimateAt(years, months, days, hours)
    local elapsed = (years or 0) * 365 * 86400 + (months or 0) * 30 * 86400 + (days or 0) * 86400 + (hours or 0) * 3600
    return now() - elapsed
end

local function pruneSeen()
    local seen = SideQuestDB.bankSeen
    local cutoff = now() - SEEN_PRUNE_AGE
    for key, entries in pairs(seen) do
        local kept = {}
        for _, e in ipairs(entries) do
            if e.at >= cutoff then
                table.insert(kept, e)
            end
        end
        if #kept == 0 then
            seen[key] = nil
        else
            seen[key] = kept
        end
    end
end

-- Matches `at` against bankSeen[key] within SEEN_TOLERANCE, skipping entries
-- already matched earlier in this same capture pass (so two identical
-- transactions in the same hour stay two separate rows, not one). Returns
-- true and records a new entry if this is a new row; false if it's already
-- recorded.
local function recordIfNew(key, at, matchedThisPass)
    SideQuestDB.bankSeen[key] = SideQuestDB.bankSeen[key] or {}
    local entries = SideQuestDB.bankSeen[key]
    matchedThisPass[key] = matchedThisPass[key] or {}
    local used = matchedThisPass[key]
    for i, e in ipairs(entries) do
        if not used[i] and math.abs(e.at - at) <= SEEN_TOLERANCE then
            used[i] = true
            return false, e.id
        end
    end
    local id = hashId(key, at, #entries)
    table.insert(entries, { at = at, id = id })
    used[#entries] = true
    return true, id
end

--- Capture a guild bank tab's item transaction log into pending.bank.
-- Reads whatever QueryGuildBankLog(tab) has already delivered; call once
-- GUILDBANKLOG_UPDATE has fired. Returns the number of new rows, or nil if
-- the API is unavailable.
function Bank.CaptureItemLog(tabIndex)
    if not Bank.IsAvailable() then
        return nil
    end
    tabIndex = tabIndex or 1
    pruneSeen()
    local matchedThisPass = {}
    local added = 0
    local total = GetNumGuildBankTransactions(tabIndex) or 0
    for i = 1, total do
        local kind, name, itemLink, count, _, _, years, months, days, hours = GetGuildBankTransaction(tabIndex, i)
        if kind == "deposit" or kind == "withdraw" or kind == "move" then
            local itemId = itemIdFromLink(itemLink)
            local key = contentKey(tabIndex, kind, name, itemId or itemLink, count, 0)
            local at = estimateAt(years, months, days, hours)
            local isNew, id = recordIfNew(key, at, matchedThisPass)
            if isNew then
                table.insert(SideQuestDB.pending.bank, {
                    id = id,
                    at = at,
                    character = normalized(name),
                    kind = kind,
                    item_id = itemId,
                    item_name = itemLink,
                    count = count or 0,
                    money = 0,
                    tab = tabIndex,
                })
                added = added + 1
            end
        end
    end
    if added > 0 then
        SideQuest.Fire("SQ_BANK_CAPTURED", added)
    end
    return added
end

-- Blizzard's money-log kind strings don't all match the contract's BankKind
-- enum (deposit/withdraw/move/repair/buy_tab/deposit_money/withdraw_money);
-- translate the ones we record and drop the rest (tab purchases' sibling
-- events, guild renames) as not worth a ledger row.
local MONEY_KIND_MAP = {
    deposit = "deposit_money",
    withdraw = "withdraw_money",
    repair = "repair",
    buyTab = "buy_tab",
}

--- Capture the guild bank's money transaction log into pending.bank. Reads
-- whatever QueryGuildBankLog(MONEY_LOG_TAB) has already delivered; call once
-- GUILDBANKLOG_UPDATE has fired. Returns the number of new rows, or nil if
-- the API is unavailable.
function Bank.CaptureMoneyLog()
    if not Bank.IsMoneyLogAvailable() then
        return nil
    end
    pruneSeen()
    local matchedThisPass = {}
    local added = 0
    local total = GetNumGuildBankMoneyTransactions() or 0
    for i = 1, total do
        local rawKind, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
        local kind = MONEY_KIND_MAP[rawKind]
        if kind then
            local key = contentKey(MONEY_LOG_TAB, kind, name, nil, 0, amount)
            local at = estimateAt(years, months, days, hours)
            local isNew, id = recordIfNew(key, at, matchedThisPass)
            if isNew then
                table.insert(SideQuestDB.pending.bank, {
                    id = id,
                    at = at,
                    character = normalized(name),
                    kind = kind,
                    item_id = nil,
                    item_name = nil,
                    count = 0,
                    money = amount or 0,
                    tab = nil,
                })
                added = added + 1
            end
        end
    end
    if added > 0 then
        SideQuest.Fire("SQ_BANK_CAPTURED", added)
    end
    return added
end

--- Ask the server for the item and money logs; results land asynchronously
-- via GUILDBANKLOG_UPDATE, captured below. Safe to call with the bank
-- closed (QueryGuildBankLog is simply a no-op then); does nothing if the
-- client has no QueryGuildBankLog at all.
function Bank.RequestCapture(tabIndex)
    if type(QueryGuildBankLog) ~= "function" then
        return
    end
    QueryGuildBankLog(tabIndex or (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1)
    QueryGuildBankLog(MONEY_LOG_TAB)
end

SideQuest.On("GUILDBANKFRAME_OPENED", function()
    if SideQuest.IsOfficer() then
        Bank.RequestCapture()
    end
end)
SideQuest.RegisterGameEvent("GUILDBANKFRAME_OPENED")

SideQuest.On("GUILDBANKLOG_UPDATE", function()
    if not SideQuest.IsOfficer() then
        return
    end
    Bank.CaptureItemLog(GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 1)
    Bank.CaptureMoneyLog()
end)
SideQuest.RegisterGameEvent("GUILDBANKLOG_UPDATE")

return Bank
