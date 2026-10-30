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
local makeFontString = UI.MakeFontString
local FONT_DISPLAY, FONT_BODY = UI.FontDisplay, UI.FontBody
local BAR_W, BAR_H = 211, 13 -- Forever's player cast bar, native size

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
    popup:SetSize(340, 236)
    popup:SetPoint("TOP", 0, -200)
    popup:Hide()
    local ribbon = UI.CreateRibbon(popup, "Bidding")
    popup.ribbon = ribbon

    local inner = popup.inner

    -- the item's icon in a chamfered metal frame tinted to its quality colour
    -- (the name below carries the quality colour too, so it never rests on
    -- colour alone)
    local iconFrame = CreateFrame("Frame", nil, inner)
    iconFrame:SetSize(44, 44)
    iconFrame:SetPoint("TOPLEFT", 10, -28)
    local iconWell = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconWell:SetPoint("TOPLEFT", 3, -3)
    iconWell:SetPoint("BOTTOMRIGHT", -3, 3)
    iconWell:SetColorTexture(0.02, 0.03, 0.06, 1)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local iconRim = iconFrame:CreateTexture(nil, "OVERLAY")
    iconRim:SetAllPoints(iconFrame)
    iconRim:SetTexture(UI.MediaTex .. "IconFrame")

    local itemText = makeFontString(inner, FONT_DISPLAY, 14, C.ink, "LEFT")
    itemText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 10, -2)
    itemText:SetWidth(230)
    if itemText.SetWordWrap then
        itemText:SetWordWrap(true)
    end
    local slotGpText = makeFontString(inner, FONT_BODY, 12, C.mist, "LEFT")
    slotGpText:SetPoint("TOPLEFT", itemText, "BOTTOMLEFT", 0, -6)

    local prText = makeFontString(inner, FONT_BODY, 12, C.mist, "LEFT")
    prText:SetPoint("TOPLEFT", iconFrame, "BOTTOMLEFT", 0, -10)
    local rankText = makeFontString(inner, FONT_BODY, 12, C.mist, "LEFT")
    rankText:SetPoint("TOPLEFT", prText, "BOTTOMLEFT", 0, -2)

    -- countdown: Forever's player cast bar at its native size, so its frame
    -- art is never stretched; the fill shrinks as time runs out, with the
    -- seconds in words for anyone who can't read the bar at 0.64 scale.
    -- The atlases are set without useAtlasSize: these sizes are the layout.
    local barBg = inner:CreateTexture(nil, "BACKGROUND")
    barBg:SetSize(BAR_W, BAR_H)
    barBg:SetPoint("TOPLEFT", rankText, "BOTTOMLEFT", 6, -14)
    barBg:SetAtlas("UI-CastingBar-Background")
    local barFill = inner:CreateTexture(nil, "ARTWORK")
    barFill:SetSize(BAR_W, BAR_H)
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT")
    barFill:SetAtlas("UI-CastingBar-Filling-Standard")
    local barFrame = inner:CreateTexture(nil, "OVERLAY")
    barFrame:SetPoint("TOPLEFT", barBg, "TOPLEFT", -6, 6)
    barFrame:SetPoint("BOTTOMRIGHT", barBg, "BOTTOMRIGHT", 6, -6)
    barFrame:SetAtlas("UI-CastingBar-Frame")
    local timerText = makeFontString(inner, FONT_BODY, 11, C.mist2, "LEFT")
    timerText:SetPoint("TOPLEFT", barBg, "BOTTOMLEFT", 0, -4)

    local function makeChoiceButton(label, xOffset, response)
        local btn = UI.CreateButton(inner, "quiet", label, 86, 24)
        btn:SetPoint("BOTTOM", xOffset, 12)
        btn:SetScript("OnClick", function()
            SideQuest.Loot.SubmitBid(response)
            popup.chosen = response
            for _, b in ipairs(popup.choiceButtons) do
                if b == btn then
                    b:SetSelected(true)
                    b:EnableMouse(false)
                else
                    b:Disable()
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

    popup.iconRim, popup.icon, popup.itemText, popup.slotGpText = iconRim, icon, itemText, slotGpText
    popup.prText, popup.rankText = prText, rankText
    popup.barBg, popup.barFill, popup.barFrame, popup.timerText, popup.sentText =
        barBg, barFill, barFrame, timerText, sentText

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
            btn:EnableMouse(true)
            btn:SetSelected(false)
            btn:Enable()
        end

        -- resolve the real item: name/quality/icon/slot/GP via the shared
        -- UI.ResolveItemInfo, so GP is computed from the item's actual
        -- inventory slot instead of a hardcoded nil -- that hardcode is
        -- why the popup used to always show "Estimated GP: 0".
        local info = UI.ResolveItemInfo(itemLink)
        local qColor = UI.QualityColor[info.quality] or UI.QualityColor[1]

        popup.iconRim:SetVertexColor(qColor[1], qColor[2], qColor[3], 1)
        if info.icon then
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
        popup.barFill:SetWidth(BAR_W)
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
            popup.barFill:SetWidth(BAR_W * (remaining / totalSeconds))
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
