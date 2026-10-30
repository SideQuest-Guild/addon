-- SideQuest/UI/BidPopup.lua
-- Popup shown to raiders when an officer opens bidding on an item: a
-- framed night chamber (DESIGN.md) showing the item icon + name in its
-- quality colour, slot and GP cost, the raider's PR and where they'd rank,
-- Main/Off/Pass buttons, a countdown bar, and the "sent" state once they
-- answer. Reuses Main.lua's chamber/ribbon/colour vocabulary -- never a
-- second copy of it.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
local UI = SideQuest.UI

if not CreateFrame then
    return UI
end

local C = UI.Colors
local setColor = UI.SetColor
local makeFontString = UI.MakeFontString
local FONT_DISPLAY, FONT_BODY = UI.FontDisplay, UI.FontBody

local function now()
    return GetServerTime and GetServerTime() or 0
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

--- Where the local player would land if they bid Main spec right now,
-- among everyone who has already answered this bid (contract bid order).
local function wouldRankAt(bid, myResponse)
    if not bid then
        return nil, nil
    end
    local me = SideQuest.NormalizeUnit("player")
    local bids = { { character = me, response = myResponse } }
    for character, response in pairs(bid.responses or {}) do
        if character ~= me then
            table.insert(bids, { character = character, response = response })
        end
    end
    local ranked = SideQuest.Loot.RankBids(bids, now())
    for i, entry in ipairs(ranked) do
        if entry.character == me then
            return i, #ranked
        end
    end
    return nil, #ranked
end

function UI.BuildBidPopup()
    if UI.bidPopup then
        return UI.bidPopup
    end

    local popup = UI.CreateChamber(UIParent, "SideQuestBidPopup")
    popup:SetSize(320, 220)
    popup:SetPoint("TOP", 0, -200)
    popup:Hide()
    local ribbon = UI.CreateRibbon(popup, "Bidding")
    popup.ribbon = ribbon

    local inner = popup.inner

    -- item icon (quality-colour swatch behind it; the real texture is a
    -- Blizzard file the preview renderer can't fetch, so the swatch alone
    -- still carries the quality colour, per DESIGN.md "always with text")
    local iconSwatch = inner:CreateTexture(nil, "BACKGROUND")
    iconSwatch:SetSize(40, 40)
    iconSwatch:SetPoint("TOPLEFT", 14, -32)
    local icon = inner:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("CENTER", iconSwatch, "CENTER")

    local itemText = makeFontString(inner, FONT_DISPLAY, 14, C.ink, "LEFT")
    itemText:SetPoint("TOPLEFT", iconSwatch, "TOPRIGHT", 10, -2)
    itemText:SetWidth(220)
    if itemText.SetWordWrap then
        itemText:SetWordWrap(true)
    end
    local slotGpText = makeFontString(inner, FONT_BODY, 12, C.mist, "LEFT")
    slotGpText:SetPoint("TOPLEFT", itemText, "BOTTOMLEFT", 0, -6)

    local prText = makeFontString(inner, FONT_BODY, 12, C.mist, "LEFT")
    prText:SetPoint("TOPLEFT", iconSwatch, "BOTTOMLEFT", 0, -10)
    local rankText = makeFontString(inner, FONT_BODY, 12, C.mist, "LEFT")
    rankText:SetPoint("TOPLEFT", prText, "BOTTOMLEFT", 0, -2)

    -- countdown bar: a stone track with a gold-deep fill that shrinks as
    -- time runs out, plus the numeric seconds for anyone who can't read
    -- the bar at 0.64 scale (never colour/length alone).
    local barTrack = inner:CreateTexture(nil, "ARTWORK")
    barTrack:SetSize(260, 8)
    barTrack:SetPoint("TOPLEFT", rankText, "BOTTOMLEFT", 0, -12)
    setColor(barTrack, C.stone2)
    local barFill = inner:CreateTexture(nil, "OVERLAY")
    barFill:SetHeight(8)
    barFill:SetPoint("TOPLEFT", barTrack, "TOPLEFT")
    setColor(barFill, C.goldDeep)
    local timerText = makeFontString(inner, FONT_BODY, 11, C.mist2, "LEFT")
    timerText:SetPoint("TOPLEFT", barTrack, "BOTTOMLEFT", 0, -4)

    local function makeChoiceButton(label, xOffset, response)
        local btn = UI.CreateButton(inner, "quiet", label, 84, 22)
        btn:SetPoint("BOTTOM", xOffset, 16)
        local selectedEdge = UI.AddBorder(btn, C.gold, 2)
        for _, line in pairs(selectedEdge) do
            line:Hide()
        end
        btn.selectedEdge = selectedEdge
        btn:SetScript("OnClick", function()
            SideQuest.Loot.SubmitBid(response)
            popup.chosen = response
            for _, b in ipairs(popup.choiceButtons) do
                b:Disable()
                for _, line in pairs(b.selectedEdge) do
                    line:SetShown(b == btn)
                end
            end
            UI.SetStateText(popup.sentText, "Sent: " .. label .. " -- waiting for the officer's award", false)
            popup.sentText:Show()
        end)
        return btn
    end

    popup.choiceButtons = {
        makeChoiceButton("Main", -90, "ms"),
        makeChoiceButton("Off", 0, "os"),
        makeChoiceButton("Pass", 90, "pass"),
    }

    local sentText = makeFontString(inner, FONT_BODY, 11, C.gold, "CENTER")
    sentText:SetPoint("BOTTOM", 0, 42)
    sentText:Hide()

    popup.iconSwatch, popup.icon, popup.itemText, popup.slotGpText = iconSwatch, icon, itemText, slotGpText
    popup.prText, popup.rankText = prText, rankText
    popup.barTrack, popup.barFill, popup.timerText, popup.sentText = barTrack, barFill, timerText, sentText

    UI.bidPopup = popup
    return popup
end

function UI.ShowBidPopup(itemLink, timeoutSeconds)
    -- never opens or flashes in combat
    SideQuest.WhenOutOfCombat(function()
        local popup = UI.BuildBidPopup()
        popup.chosen = nil
        popup.sentText:Hide()
        for _, btn in ipairs(popup.choiceButtons) do
            btn:Enable()
            for _, line in pairs(btn.selectedEdge) do
                line:Hide()
            end
        end

        -- resolve the real item: name/quality/icon/slot/GP via the shared
        -- UI.ResolveItemInfo, so GP is computed from the item's actual
        -- inventory slot instead of a hardcoded nil -- that hardcode is
        -- why the popup used to always show "Estimated GP: 0".
        local info = UI.ResolveItemInfo(itemLink)
        local qColor = UI.QualityColor[info.quality] or UI.QualityColor[1]

        setColor(popup.iconSwatch, qColor)
        if info.icon and popup.icon.SetTexture then
            popup.icon:SetTexture(info.icon)
        end
        popup.itemText:SetTextColor(qColor[1], qColor[2], qColor[3], 1)
        popup.itemText:SetText(info.name)

        if info.slotWord and info.gp then
            popup.slotGpText:SetText(info.slotWord .. "  --  Main-spec GP " .. info.gp)
        elseif info.gp then
            popup.slotGpText:SetText("Main-spec GP " .. info.gp)
        else
            UI.SetStateText(popup.slotGpText, "GP unknown until the item is identified", true)
        end

        popup.prText:SetText(string.format("Your PR: %.3f", myPR()))
        local bid = SideQuest.Loot.activeBid
        local rankAt, totalBids = wouldRankAt(bid, "ms")
        if rankAt then
            popup.rankText:SetText(string.format("Would rank %d of %d bidding Main spec", rankAt, totalBids))
        else
            UI.SetStateText(popup.rankText, "Rank unknown until more bids come in", true)
        end

        local startedAt = now()
        local totalSeconds = timeoutSeconds or 30
        local deadline = startedAt + totalSeconds
        popup.deadline = deadline
        popup.barFill:SetWidth(260)
        if popup.ticker and popup.ticker.Cancel then
            popup.ticker:Cancel()
        end
        local function tick()
            local remaining = deadline - (GetServerTime and GetServerTime() or 0)
            if remaining <= 0 then
                popup.barFill:SetWidth(0)
                popup.timerText:SetText("Bidding closed")
                popup:Hide()
                if popup.ticker and popup.ticker.Cancel then
                    popup.ticker:Cancel()
                end
                return
            end
            popup.barFill:SetWidth(260 * (remaining / totalSeconds))
            popup.timerText:SetText(remaining .. "s remaining")
        end
        tick()
        if C_Timer and C_Timer.NewTicker then
            popup.ticker = C_Timer.NewTicker(1, tick)
        end

        popup:Show()
    end)
end

SideQuest.On("SQ_BID_POPUP", function(itemLink, timeoutSeconds)
    UI.ShowBidPopup(itemLink, timeoutSeconds)
end)

return UI
