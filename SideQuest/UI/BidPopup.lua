-- SideQuest/UI/BidPopup.lua
-- Popup shown to raiders when an officer opens bidding on an item: shows
-- the item, its GP cost estimate, the raider's current PR, and
-- Main/Off/Pass buttons that reply over the RAID channel.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
local UI = SideQuest.UI

if not CreateFrame then
    return UI
end

local function myPR()
    local me = SideQuest.NormalizeUnit("player")
    for _, row in ipairs(SideQuest.Standings.GetDisplayRows()) do
        for _, c in ipairs(row.characters or {}) do
            if c == me then
                return row.pr or 0
            end
        end
    end
    return 0
end

function UI.BuildBidPopup()
    if UI.bidPopup then
        return UI.bidPopup
    end

    local popup = CreateFrame("Frame", "SideQuestBidPopup", UIParent, "BackdropTemplate")
    popup:SetSize(300, 150)
    popup:SetPoint("TOP", 0, -200)
    if popup.SetBackdrop then
        popup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    popup:Hide()

    popup.itemText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup.itemText:SetPoint("TOP", 0, -16)

    popup.prText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.prText:SetPoint("TOP", popup.itemText, "BOTTOM", 0, -8)

    popup.timerText = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.timerText:SetPoint("TOP", popup.prText, "BOTTOM", 0, -4)

    local function makeChoiceButton(label, xOffset, response)
        local btn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        btn:SetSize(80, 22)
        btn:SetPoint("BOTTOM", xOffset, 16)
        btn:SetText(label)
        btn:SetScript("OnClick", function()
            SideQuest.Loot.SubmitBid(response)
            popup:Hide()
        end)
        return btn
    end

    makeChoiceButton("Main", -90, "ms")
    makeChoiceButton("Off", 0, "os")
    makeChoiceButton("Pass", 90, "pass")

    UI.bidPopup = popup
    return popup
end

function UI.ShowBidPopup(itemLink, timeoutSeconds)
    local popup = UI.BuildBidPopup()
    popup.itemText:SetText(itemLink)
    popup.prText:SetText(string.format("Your PR: %.3f", myPR()))

    local deadline = (GetServerTime and GetServerTime() or 0) + (timeoutSeconds or 30)
    popup.deadline = deadline
    if popup.ticker and popup.ticker.Cancel then
        popup.ticker:Cancel()
    end
    if C_Timer and C_Timer.NewTicker then
        popup.ticker = C_Timer.NewTicker(1, function()
            local remaining = deadline - (GetServerTime and GetServerTime() or 0)
            if remaining <= 0 then
                popup:Hide()
                if popup.ticker.Cancel then
                    popup.ticker:Cancel()
                end
                return
            end
            popup.timerText:SetText(remaining .. "s remaining")
        end)
    end

    popup:Show()
end

SideQuest.On("SQ_BID_POPUP", function(itemLink, timeoutSeconds)
    UI.ShowBidPopup(itemLink, timeoutSeconds)
end)

return UI
