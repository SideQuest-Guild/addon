-- SideQuest/Payouts.lua
-- Recruitment drive payouts (contract: "recruit_payouts" officer import / "recruit_payouts_paid" export). The
-- site works out who's owed (settled, qualified, unpaid); this module mails the gold from here, one click at
-- an open mailbox, and records a successful send for the next export so the site marks it paid.

SideQuest = SideQuest or {}
SideQuest.Payouts = {}
local Payouts = SideQuest.Payouts

local MAIL_SUBJECT = "SideQuest recruitment drive"
local PENDING_CAP = 200 -- contract: recruit_payouts_paid export caps at 200

local function now()
    return GetServerTime and GetServerTime() or 0
end

-- One payout is one (drive, inviter, recruits) set: a recruit who qualifies after an earlier mail comes back as
-- a new row for the same drive and inviter, and must not look paid.
local function paidKey(row)
    local recruits = {}
    for i, name in ipairs(row.recruits or {}) do
        recruits[i] = name
    end
    table.sort(recruits)
    return tostring(row.event_id) .. "|" .. tostring(row.inviter) .. "|" .. table.concat(recruits, ",")
end

--- True once this client has mailed this payout row (same drive, inviter and recruits).
function Payouts.IsPaid(row)
    return SideQuestDB.paidPayouts[paidKey(row)] == true
end

--- Rows owed per the last officer import, excluding anything this client
-- already marked paid locally -- which can be ahead of the site's own
-- view by up to one export/sync round-trip.
function Payouts.List()
    local out = {}
    for _, row in ipairs(SideQuestDB.officerData.recruit_payouts or {}) do
        if not Payouts.IsPaid(row) then
            table.insert(out, row)
        end
    end
    return out
end

--- Record a successful addon-mailed payout: queues it for export (so the
-- site marks it paid "via addon") and marks it paid locally so the same
-- row's button can never fire SendMail a second time, even across a
-- logout before the next export reaches the site.
local function recordPaid(row)
    local officer = SideQuest.NormalizeUnit("player")
    local entry = { event_id = row.event_id, inviter = row.inviter, copper = row.copper, at = now(), officer = officer }
    local pending = SideQuestDB.pending.recruit_payouts_paid
    table.insert(pending, entry)
    for _ = 1, #pending - PENDING_CAP do
        table.remove(pending, 1)
    end
    SideQuestDB.paidPayouts[paidKey(row)] = true
    return entry
end

local function mailBody(row)
    local recruits = row.recruits or {}
    if #recruits == 0 then
        return "Thanks for recruiting for " .. tostring(row.title or "the drive") .. "."
    end
    return "Thanks for recruiting " .. table.concat(recruits, ", ") .. ". They each stayed 7 days!"
end

--------------------------------------------------------------------------
-- Mailing the gold: SendMail/SetSendMailMoney/ClearSendMail only work at
-- an open mailbox (MAIL_SHOW..MAIL_CLOSED); only one send is ever tracked
-- at a time, since the mailbox gives no id to correlate a result with the
-- send that caused it.
--------------------------------------------------------------------------

Payouts.mailboxOpen = false
Payouts.pendingSend = nil -- the row currently being mailed, or nil

--- Fill and send a payout's mail in one click. Refuses with a clear reason
-- when the mailbox isn't open, the row is already paid, a send from this
-- button is already in flight, or the officer can't afford it -- nothing
-- is sent or recorded in any of those cases.
function Payouts.Send(row)
    if not SideQuest.IsOfficer() then
        return false, "Only officers can send recruitment payouts."
    end
    if not Payouts.mailboxOpen then
        return false, "Open a mailbox first."
    end
    if Payouts.IsPaid(row) then
        return false, "Already paid."
    end
    if Payouts.pendingSend then
        return false, "A payout mail is already sending. Wait for it to finish."
    end
    local copper = row.copper or 0
    local money = GetMoney and GetMoney() or 0
    if money < copper then
        return false, "Not enough gold on hand to send this payout."
    end
    if type(ClearSendMail) == "function" then
        ClearSendMail()
    end
    SetSendMailMoney(copper)
    Payouts.pendingSend = row
    SendMail(SideQuest.GameName(row.inviter), MAIL_SUBJECT, mailBody(row))
    return true
end

SideQuest.On("MAIL_SHOW", function()
    Payouts.mailboxOpen = true
end)
SideQuest.RegisterGameEvent("MAIL_SHOW")

SideQuest.On("MAIL_CLOSED", function()
    Payouts.mailboxOpen = false
    Payouts.pendingSend = nil
end)
SideQuest.RegisterGameEvent("MAIL_CLOSED")

SideQuest.On("MAIL_SEND_SUCCESS", function()
    local row = Payouts.pendingSend
    Payouts.pendingSend = nil
    if row then
        recordPaid(row)
        SideQuest.Print("Paid " .. tostring(row.inviter) .. ".")
        SideQuest.Fire("SQ_PAYOUT_SENT", row)
    end
end)
SideQuest.RegisterGameEvent("MAIL_SEND_SUCCESS")

SideQuest.On("MAIL_FAILED", function()
    local row = Payouts.pendingSend
    Payouts.pendingSend = nil
    if row then
        SideQuest.Print("Sending the payout mail to " .. tostring(row.inviter) .. " failed. Nothing was recorded; try again.")
        SideQuest.Fire("SQ_PAYOUT_FAILED", row)
    end
end)
SideQuest.RegisterGameEvent("MAIL_FAILED")

return Payouts
