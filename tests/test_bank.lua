-- tests/test_bank.lua
-- Bank.lua: the guild bank transaction log on Forever is the old globals
-- (GetNumGuildBankTransactions, GetGuildBankTransaction, ...), not
-- C_GuildBank, and it only has data once QueryGuildBankLog has been
-- answered by GUILDBANKLOG_UPDATE while the bank is open. Its year/month/
-- day/hour are elapsed time, not a date, and the same row reports a bigger
-- elapsed time every time it's re-queried, so dedup has to key on content
-- and match the row's estimated timestamp within a tolerance, remembered
-- across `/sq export clear` (SideQuestDB.bankSeen), not by hashing the
-- elapsed value itself.

return function(h)
    local DAY, HOUR = 86400, 3600
    local ITEM_LINK = "|cffffffff|Hitem:14048:0:0:0:0:0:0:0:0:0:0|h[Runecloth]|h|r"

    local function reset()
        h.resetAddon()
        WowStub.isOfficer = true
    end

    h.test("bank: the real Forever log API is available (old globals, not C_GuildBank)", function()
        reset()
        h.assertTrue(SideQuest.Bank.IsAvailable(), "item log API available")
        h.assertTrue(SideQuest.Bank.IsMoneyLogAvailable(), "money log API available")
        h.assertEq(C_GuildBank.GetNumTransactions, nil, "C_GuildBank has no GetNumTransactions on Forever")
        h.assertEq(C_GuildBank.GetTransaction, nil, "C_GuildBank has no GetTransaction on Forever")
    end)

    h.test("bank: opening the bank as officer queries both the item and money log", function()
        reset()
        SideQuest.Fire("GUILDBANKFRAME_OPENED")
        h.assertEq(#WowStub.bankLogQueries, 2, "queries the current item tab and the money tab")
        h.assertEq(WowStub.bankLogQueries[1], 1, "item log queried for the current tab (1)")
        h.assertEq(WowStub.bankLogQueries[2], 9, "money log queried at MAX_GUILDBANK_TABS(8) + 1")
    end)

    h.test("bank: a non-officer opening the bank never queries the log", function()
        reset()
        WowStub.isOfficer = false
        SideQuest.Fire("GUILDBANKFRAME_OPENED")
        h.assertEq(#WowStub.bankLogQueries, 0, "no query sent")
    end)

    h.test("bank: a row 2 days 5 hours old gets `at` as now minus that elapsed time, not the capture time", function()
        reset()
        local captureTime = WowStub.time
        WowStub.bankTransactions[1] = {
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 2, hour = 5 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")

        h.assertEq(#SideQuestDB.pending.bank, 1, "row captured")
        local dep = SideQuestDB.pending.bank[1]
        h.assertEq(dep.kind, "deposit", "kind passes through unchanged (already contract-shaped)")
        h.assertEq(dep.item_id, 14048, "item id parsed out of the item link")
        h.assertEq(dep.item_name, ITEM_LINK, "item_name holds the link")
        h.assertEq(dep.count, 5, "count captured")
        h.assertEq(dep.character, "Alice-Whitemane", "character normalized")
        h.assertEq(dep.tab, 1, "tab recorded")
        h.assertEq(dep.at, captureTime - (2 * DAY + 5 * HOUR), "at is the estimated transaction time, not capture time")
    end)

    h.test("bank: repeated GUILDBANKLOG_UPDATE in the same session never duplicates the same row", function()
        reset()
        WowStub.bankTransactions[1] = {
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 2, hour = 5 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 1, "bankSeen dedupes the identical row")
    end)

    h.test("bank: after `/sq export clear`, re-capturing the same row a day later (now reporting one more elapsed day) adds nothing", function()
        reset()
        WowStub.bankTransactions[1] = {
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 2, hour = 5 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 1, "captured once")

        SideQuest.Sync.ClearPending() -- /sq export clear
        h.assertEq(#SideQuestDB.pending.bank, 0, "export clear empties pending.bank")

        WowStub.Advance(DAY)
        WowStub.bankTransactions[1][1].day = 3 -- the server now reports one more day elapsed for the same row

        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 0, "bankSeen (which survives export clear) still recognizes the row")
    end)

    h.test("bank: a capture an hour later, before the reported elapsed hour has ticked over, still matches (tolerance)", function()
        reset()
        WowStub.bankTransactions[1] = {
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 2, hour = 5 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 1, "captured once")

        SideQuest.Sync.ClearPending()
        WowStub.Advance(HOUR) -- real time moved on, but the API's floored elapsed-hours count hasn't yet

        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 0, "the hour-wide estimate jitter is within tolerance")
    end)

    h.test("bank: two identical deposits in the same hour are recorded as two separate rows", function()
        reset()
        WowStub.bankTransactions[1] = {
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 0, hour = 1 },
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 0, hour = 1 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 2, "both deposits kept")
        h.assertTrue(SideQuestDB.pending.bank[1].id ~= SideQuestDB.pending.bank[2].id, "distinct ids")

        SideQuest.Sync.ClearPending()
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 0, "re-capturing the same two still adds nothing")
    end)

    h.test("bank: money log maps Blizzard's kinds to the contract's BankKind and drops the rest", function()
        reset()
        WowStub.bankMoneyTransactions = {
            { kind = "deposit", name = "Alice", amount = 10000, year = 0, month = 0, day = 0, hour = 1 },
            { kind = "withdraw", name = "Bob", amount = 5000, year = 0, month = 0, day = 0, hour = 2 },
            { kind = "repair", name = "Carl", amount = 300, year = 0, month = 0, day = 0, hour = 3 },
            { kind = "buyTab", name = "Dave", amount = 100000, year = 0, month = 0, day = 0, hour = 4 },
            { kind = "withdrawForTab", name = "Eve", amount = 100, year = 0, month = 0, day = 0, hour = 5 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")

        h.assertEq(#SideQuestDB.pending.bank, 4, "withdrawForTab has no contract kind and is dropped")
        local kinds = {}
        for _, row in ipairs(SideQuestDB.pending.bank) do
            kinds[row.character] = row.kind
        end
        h.assertEq(kinds["Alice-Whitemane"], "deposit_money", "deposit -> deposit_money")
        h.assertEq(kinds["Bob-Whitemane"], "withdraw_money", "withdraw -> withdraw_money")
        h.assertEq(kinds["Carl-Whitemane"], "repair", "repair stays repair")
        h.assertEq(kinds["Dave-Whitemane"], "buy_tab", "buyTab -> buy_tab")
    end)

    h.test("bank: money log rows dedupe across export clear + a day passing the same way item rows do", function()
        reset()
        local captureTime = WowStub.time
        WowStub.bankMoneyTransactions = {
            { kind = "deposit", name = "Alice", amount = 10000, year = 0, month = 0, day = 2, hour = 5 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 1, "captured once")
        local row = SideQuestDB.pending.bank[1]
        h.assertEq(row.at, captureTime - (2 * DAY + 5 * HOUR), "money row also uses the estimated transaction time")
        h.assertEq(row.money, 10000, "money amount captured")

        SideQuest.Sync.ClearPending()
        WowStub.Advance(DAY)
        WowStub.bankMoneyTransactions[1].day = 3

        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 0, "still recognized as the same row")
    end)

    h.test("bank: a non-officer's GUILDBANKLOG_UPDATE never captures", function()
        reset()
        WowStub.isOfficer = false
        WowStub.bankTransactions[1] = {
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 2, hour = 10 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE")
        h.assertEq(#SideQuestDB.pending.bank, 0, "nothing captured")
    end)

    h.test("console Bank view: never says the API is unavailable now that it exists", function()
        reset()
        SideQuest.UI.main = nil
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Bank")
        SideQuest.UI.RefreshConsoleBank()

        local chamber = SideQuest.UI.panels.Console.bankChamber
        local shown = chamber.emptyText and chamber.emptyText:GetText() or ""
        h.assertTrue(shown:find("unavailable") == nil, "never claims the API is missing: " .. shown)
        h.assertTrue(shown:find("Open the guild bank", 1, true) ~= nil, "tells the officer to open the bank: " .. shown)
    end)

    h.test("console Bank view: captured rows render once the log comes in", function()
        reset()
        SideQuest.UI.main = nil
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Bank")

        WowStub.bankTransactions[1] = {
            { kind = "deposit", name = "Alice", itemLink = ITEM_LINK, count = 5, year = 0, month = 0, day = 2, hour = 10 },
        }
        SideQuest.Fire("GUILDBANKLOG_UPDATE") -- also refreshes the open Bank sub-view via SQ_BANK_CAPTURED

        local chamber = SideQuest.UI.panels.Console.bankChamber
        h.assertEq((chamber.emptyText and chamber.emptyText:GetText()) or "", "", "empty state cleared")
        h.assertTrue(chamber.rows[1]:IsShown(), "a row is shown")
        h.assertTrue(chamber.rows[1].text:GetText():find("deposit", 1, true) ~= nil, "row text shows the kind")
    end)
end
