-- tests/test_payouts.lua
-- Payouts.lua: mailing recruitment drive gold to inviters from an open mailbox, one click, never twice for the
-- same row, and only ever recorded on MAIL_SEND_SUCCESS for the attempt it started.

return function(h)
    local function setup()
        h.resetAddon()
        WowStub.isOfficer = true
        WowStub.realm = "Whitemane"
        WowStub.SetUnit("player", { name = "Officer1", realm = "Whitemane", class = "PRIEST", guid = "Player-1-PAY0001" })
    end

    local function sampleRow()
        return { event_id = "evt-1", title = "Spring drive", inviter = "Newbie-Whitemane", copper = 10000,
            recruits = { "Recruit1-Whitemane" }, settles_at = WowStub.time }
    end

    h.test("payouts: List() surfaces the officer import's owed rows", function()
        setup()
        SideQuestDB.officerData.recruit_payouts = { sampleRow() }
        local list = SideQuest.Payouts.List()
        h.assertEq(#list, 1, "one row owed")
        h.assertEq(list[1].inviter, "Newbie-Whitemane", "inviter carried over")
    end)

    h.test("payouts: Send refuses when the mailbox isn't open, and sends nothing", function()
        setup()
        local ok, err = SideQuest.Payouts.Send(sampleRow())
        h.assertTrue(not ok, "refused")
        h.assertTrue(err:find("mailbox", 1, true) ~= nil, "reason: " .. tostring(err))
        h.assertEq(#WowStub.mail.sent, 0, "nothing sent")
    end)

    h.test("payouts: Send refuses for a non-officer", function()
        setup()
        WowStub.isOfficer = false
        SideQuest.Fire("MAIL_SHOW")
        local ok, err = SideQuest.Payouts.Send(sampleRow())
        h.assertTrue(not ok, "refused")
        h.assertTrue(err:find("officers", 1, true) ~= nil, "reason: " .. tostring(err))
    end)

    h.test("payouts: Send refuses without enough gold on hand", function()
        setup()
        SideQuest.Fire("MAIL_SHOW")
        WowStub.money = 5000
        local ok, err = SideQuest.Payouts.Send(sampleRow())
        h.assertTrue(not ok, "refused")
        h.assertTrue(err:find("gold", 1, true) ~= nil, "reason: " .. tostring(err))
        h.assertEq(#WowStub.mail.sent, 0, "nothing sent")
    end)

    h.test("payouts: a successful send fills the mail, then MAIL_SEND_SUCCESS records it paid", function()
        setup()
        SideQuest.Fire("MAIL_SHOW")
        WowStub.money = 50000
        SideQuestDB.officerData.recruit_payouts = { sampleRow() }

        local ok = SideQuest.Payouts.Send(sampleRow())
        h.assertTrue(ok, "send accepted")
        h.assertEq(#WowStub.mail.sent, 1, "one mail sent")
        local sent = WowStub.mail.sent[1]
        h.assertEq(sent.target, "Newbie-Whitemane", "recipient is the inviter")
        h.assertEq(sent.subject, "SideQuest recruitment drive", "subject")
        h.assertTrue(sent.body:find("Recruit1-Whitemane", 1, true) ~= nil, "body names the recruit")
        h.assertEq(WowStub.mail.pendingMoney, 10000, "money set before sending")
        h.assertTrue(not SideQuest.Payouts.IsPaid(sampleRow()), "not paid until success confirms")

        SideQuest.Fire("MAIL_SEND_SUCCESS")
        h.assertTrue(SideQuest.Payouts.IsPaid(sampleRow()), "paid now")
        h.assertEq(#SideQuestDB.pending.recruit_payouts_paid, 1, "queued for export")
        local paid = SideQuestDB.pending.recruit_payouts_paid[1]
        h.assertEq(paid.event_id, "evt-1", "export event_id")
        h.assertEq(paid.inviter, "Newbie-Whitemane", "export inviter")
        h.assertEq(paid.copper, 10000, "export copper")
        h.assertEq(paid.officer, "Officer1-Whitemane", "export officer")
        h.assertEq(#SideQuest.Payouts.List(), 0, "paid row no longer listed as owed")

        local late = sampleRow()
        late.recruits = { "Recruit2-Whitemane" }
        SideQuestDB.officerData.recruit_payouts = { late }
        h.assertEq(#SideQuest.Payouts.List(), 1, "a recruit who qualified later is owed again for the same drive")
    end)

    h.test("payouts: MAIL_FAILED records nothing and leaves the row unpaid", function()
        setup()
        SideQuest.Fire("MAIL_SHOW")
        WowStub.money = 50000
        SideQuest.Payouts.Send(sampleRow())
        SideQuest.Fire("MAIL_FAILED")
        h.assertTrue(not SideQuest.Payouts.IsPaid(sampleRow()), "still unpaid")
        h.assertEq(#SideQuestDB.pending.recruit_payouts_paid, 0, "nothing queued")
    end)

    h.test("payouts: never sends twice for the same row", function()
        setup()
        SideQuest.Fire("MAIL_SHOW")
        WowStub.money = 50000
        SideQuest.Payouts.Send(sampleRow())
        local ok, err = SideQuest.Payouts.Send(sampleRow())
        h.assertTrue(not ok, "second send while the first is still in flight is refused")
        h.assertTrue(err:find("already sending", 1, true) ~= nil, "reason: " .. tostring(err))
        h.assertEq(#WowStub.mail.sent, 1, "only the first mail actually went out")

        SideQuest.Fire("MAIL_SEND_SUCCESS")
        local ok2, err2 = SideQuest.Payouts.Send(sampleRow())
        h.assertTrue(not ok2, "once paid, sending again is refused")
        h.assertTrue(err2:find("Already paid", 1, true) ~= nil, "reason: " .. tostring(err2))
        h.assertEq(#WowStub.mail.sent, 1, "still only one mail ever sent")
    end)

    h.test("payouts: closing the mailbox clears the pending send", function()
        setup()
        SideQuest.Fire("MAIL_SHOW")
        WowStub.money = 50000
        SideQuest.Payouts.Send(sampleRow())
        h.assertTrue(SideQuest.Payouts.pendingSend ~= nil, "a send is in flight")
        SideQuest.Fire("MAIL_CLOSED")
        h.assertTrue(SideQuest.Payouts.pendingSend == nil, "cleared on close")
        h.assertTrue(not SideQuest.Payouts.mailboxOpen, "mailbox marked closed")
    end)

    h.test("payouts: an officer import's recruit_payouts lands in officerData, replaced wholesale", function()
        setup()
        SideQuest.Sync.ApplyImport({
            v = 2, generated_at = WowStub.time, rules = nil, standings = {}, killed_encounters = {},
            members = {}, news = {},
            officer = { recruits = {}, member_notes = {}, inactive = {}, unseen = {},
                recruit_payouts = { sampleRow() } },
        })
        h.assertEq(#SideQuestDB.officerData.recruit_payouts, 1, "stored from the import")
        h.assertEq(SideQuestDB.officerData.recruit_payouts[1].inviter, "Newbie-Whitemane", "row carried over")
    end)

    h.test("Console > Payouts: lists owed rows, disables Mail until a mailbox is open, and sends on click", function()
        setup()
        SideQuest.UI.main = nil
        SideQuestDB.officerData.recruit_payouts = { sampleRow() }
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Payouts")
        local chamber = SideQuest.UI.panels.Console.payoutsChamber
        local row = chamber.rows[1]
        h.assertTrue(row.titleText:GetText():find("Newbie", 1, true) ~= nil, "shows the inviter")
        h.assertTrue(row.mailBtn:GetText():find("Mail", 1, true) ~= nil, "Mail button labeled")
        h.assertTrue(not row.mailBtn.__enabled, "disabled: no mailbox open")

        SideQuest.Fire("MAIL_SHOW")
        WowStub.money = 50000
        SideQuest.UI.RefreshConsolePayouts()
        row = chamber.rows[1]
        h.assertTrue(row.mailBtn.__enabled, "enabled once a mailbox is open")

        row.mailBtn:GetScript("OnClick")()
        h.assertEq(#WowStub.mail.sent, 1, "clicking Mail sends it")
        SideQuest.Fire("MAIL_SEND_SUCCESS")
        h.assertEq(#chamber.rows, 1, "row pool kept")
        SideQuest.UI.RefreshConsolePayouts()
        h.assertTrue(not chamber.rows[1]:IsShown(), "the paid row is gone from the list")
    end)

    h.test("Console > Payouts: the empty state explains there's nothing owed", function()
        setup()
        SideQuest.UI.main = nil
        SideQuest.UI.Show()
        SideQuest.UI.ShowTab("Console")
        SideQuest.UI.ShowConsoleSub("Payouts")
        local chamber = SideQuest.UI.panels.Console.payoutsChamber
        h.assertTrue(chamber.emptyText:GetText():find("No recruitment payouts owed", 1, true) ~= nil,
            "empty state: " .. chamber.emptyText:GetText())
    end)
end
