-- SideQuest/UI/RecruitPopup.lua
-- The whispers that came in after your recruiting post (RecruitInvite.lua), one row each with Invite and Skip
-- buttons. Invite is the only path to C_GuildInfo.Invite: nobody is invited without a click. Closing the popup
-- (Close or Escape) skips everyone still listed.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
local UI = SideQuest.UI

if not CreateFrame then
    return UI
end

local C = UI.Colors
local makeFontString = UI.MakeFontString
local FONT_BODY = UI.FontBody

local WIDTH = 380
local SHOWN_ROWS = 5
local ROW_H = 46
local TOP_PAD, BOTTOM_PAD = 52, 50

local function buildRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 32, ROW_H)
    row:SetPoint("TOPLEFT", 8, -(TOP_PAD + (index - 1) * ROW_H))

    row.inviteBtn = UI.CreateButton(row, "primary", "Invite", 64, 22)
    row.inviteBtn:SetPoint("RIGHT", row, "RIGHT", -58, 0)
    row.skipBtn = UI.CreateButton(row, "quiet", "Skip", 52, 22)
    row.skipBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.nameText = makeFontString(row, FONT_BODY, 13, C.ink, "LEFT")
    row.nameText:SetPoint("TOPLEFT", 0, -6)
    row.nameText:SetPoint("RIGHT", row.inviteBtn, "LEFT", -8, 0)
    row.msgText = makeFontString(row, FONT_BODY, 11, C.mist, "LEFT")
    row.msgText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -1)
    row.msgText:SetPoint("RIGHT", row.inviteBtn, "LEFT", -8, 0)
    if row.msgText.SetWordWrap then
        row.msgText:SetWordWrap(false)
    end

    row.inviteBtn:SetScript("OnClick", function()
        SideQuest.RecruitInvite.Invite(row.key)
    end)
    row.skipBtn:SetScript("OnClick", function()
        SideQuest.RecruitInvite.Skip(row.key)
    end)
    return row
end

function UI.BuildRecruitPopup()
    if UI.recruitPopup then
        return UI.recruitPopup
    end
    local popup = UI.CreateChamber(UIParent, "SideQuestRecruitPopup")
    popup:SetSize(WIDTH, TOP_PAD + ROW_H + BOTTOM_PAD)
    -- over the main window (HIGH)
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:SetPoint("TOP", 0, -160)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:Hide()
    -- Escape closes it; OnHide skips whoever is left, so it never reopens with stale rows.
    if UISpecialFrames then
        table.insert(UISpecialFrames, "SideQuestRecruitPopup")
    end
    popup:SetScript("OnHide", function()
        SideQuest.RecruitInvite.Clear()
    end)
    UI.CreateRibbon(popup, "Recruiting")

    local inner = popup.inner
    local intro = makeFontString(inner, FONT_BODY, 12, C.mist, "LEFT")
    intro:SetPoint("TOPLEFT", 8, -28)
    intro:SetText("Whispers after your recruiting post")

    popup.rows = {}
    for i = 1, SHOWN_ROWS do
        popup.rows[i] = buildRow(inner, i)
    end

    local moreText = makeFontString(inner, FONT_BODY, 11, C.mist2, "LEFT")
    moreText:SetPoint("BOTTOMLEFT", 8, 14)
    local closeBtn = UI.CreateButton(inner, "quiet", "Close", 70, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -8, 10)
    closeBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    popup.intro, popup.moreText, popup.closeBtn = intro, moreText, closeBtn
    UI.recruitPopup = popup
    return popup
end

--- Redraw from RecruitInvite's queue: shows the popup while anyone waits, hides it once the queue is empty.
function UI.RefreshRecruitPopup()
    local queue = SideQuest.RecruitInvite.Queue()
    if #queue == 0 then
        if UI.recruitPopup and UI.recruitPopup:IsShown() then
            UI.recruitPopup:Hide()
        end
        return
    end
    local popup = UI.BuildRecruitPopup()
    local shown = math.min(#queue, SHOWN_ROWS)
    for i, row in ipairs(popup.rows) do
        local entry = queue[i]
        if i <= shown then
            row.key = entry.key
            row.nameText:SetText(entry.name)
            row.msgText:SetText(entry.text ~= "" and ('"' .. entry.text .. '"') or "")
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    if #queue > SHOWN_ROWS then
        popup.moreText:SetText(string.format("+%d more waiting", #queue - SHOWN_ROWS))
    else
        popup.moreText:SetText("")
    end
    popup:SetHeight(TOP_PAD + shown * ROW_H + BOTTOM_PAD)
    popup:Show()
end

-- Never opens in combat: a whisper mid-fight waits until it ends.
SideQuest.On("SQ_RECRUIT_INVITES_UPDATED", function()
    SideQuest.WhenOutOfCombat(UI.RefreshRecruitPopup)
end)

return UI
