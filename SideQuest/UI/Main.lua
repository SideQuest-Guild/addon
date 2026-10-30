-- SideQuest/UI/Main.lua
-- One movable main window with tabs: Standings, Raid, Loot, Events, Sync.
-- Uses only stock templates available on modern Mainline: BackdropTemplate,
-- UIPanelButtonTemplate, InputBoxTemplate, UIPanelScrollFrameTemplate.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
local UI = SideQuest.UI

if not CreateFrame then
    return UI -- headless (no Blizzard UI environment); nothing to build
end

local TABS = { "Standings", "Raid", "Loot", "Events", "Sync" }
local PANEL_WIDTH, PANEL_HEIGHT = 520, 420

local function makeBackdropFrame(name, parent, template)
    local f = CreateFrame("Frame", name, parent, template or "BackdropTemplate")
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    return f
end

local function makeFontString(parent, text, point)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if point then
        fs:SetPoint(unpack(point))
    end
    if text then
        fs:SetText(text)
    end
    return fs
end

local function buildScrollList(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_WIDTH - 60, PANEL_HEIGHT - 60)
    scroll:SetScrollChild(content)
    return scroll, content
end

--------------------------------------------------------------------------
-- Main frame + tabs
--------------------------------------------------------------------------

function UI.BuildMainFrame()
    if UI.main then
        return UI.main
    end

    local main = makeBackdropFrame("SideQuestMainFrame", UIParent)
    main:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    main:SetPoint("CENTER")
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", main.StopMovingOrSizing)
    main:Hide()

    makeFontString(main, "SideQuest", { "TOP", 0, -16 })

    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        main:Hide()
    end)

    UI.panels = {}
    UI.tabButtons = {}
    local lastButton
    for i, tabName in ipairs(TABS) do
        local btn = CreateFrame("Button", "SideQuestTab" .. i, main, "UIPanelButtonTemplate")
        btn:SetSize(90, 22)
        if lastButton then
            btn:SetPoint("LEFT", lastButton, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", 16, -40)
        end
        btn:SetText(tabName)
        btn:SetScript("OnClick", function()
            UI.ShowTab(tabName)
        end)
        UI.tabButtons[tabName] = btn
        lastButton = btn

        local panel = CreateFrame("Frame", nil, main)
        panel:SetPoint("TOPLEFT", 10, -70)
        panel:SetPoint("BOTTOMRIGHT", -10, 10)
        panel:Hide()
        UI.panels[tabName] = panel
    end

    UI.main = main
    UI.BuildStandingsPanel(UI.panels.Standings)
    UI.BuildRaidPanel(UI.panels.Raid)
    UI.BuildLootPanel(UI.panels.Loot)
    UI.BuildEventsPanel(UI.panels.Events)
    UI.BuildSyncPanel(UI.panels.Sync)

    return main
end

function UI.ShowTab(tabName)
    for name, panel in pairs(UI.panels) do
        if name == tabName then
            panel:Show()
        else
            panel:Hide()
        end
    end
    UI.activeTab = tabName
    if tabName == "Standings" then
        UI.RefreshStandings()
    elseif tabName == "Events" then
        UI.RefreshEvents()
    end
end

function UI.Toggle()
    local main = UI.BuildMainFrame()
    if main:IsShown() then
        main:Hide()
    else
        main:Show()
        UI.ShowTab(UI.activeTab or "Standings")
    end
end

--------------------------------------------------------------------------
-- Standings panel
--------------------------------------------------------------------------

function UI.BuildStandingsPanel(panel)
    local scroll, content = buildScrollList(panel)
    panel.scroll = scroll
    panel.content = content
    panel.rowFontStrings = {}
    makeFontString(content, "Name / EP / GP / PR", { "TOPLEFT", 0, 0 })
end

function UI.RefreshStandings()
    local panel = UI.panels and UI.panels.Standings
    if not panel then
        return
    end
    local rows = SideQuest.Standings.GetDisplayRows()
    local me = SideQuest.NormalizeUnit("player")
    for i, row in ipairs(rows) do
        local fs = panel.rowFontStrings[i]
        if not fs then
            fs = makeFontString(panel.content)
            fs:SetPoint("TOPLEFT", 0, -16 * i)
            panel.rowFontStrings[i] = fs
        end
        local isMe = false
        for _, c in ipairs(row.characters or {}) do
            if c == me then
                isMe = true
            end
        end
        local color = isMe and "|cffffd100" or "|cffffffff"
        fs:SetText(string.format("%s%s|r  EP %.1f  GP %.1f  PR %.3f%s",
            color, row.name or row.main or "?", row.ep or 0, row.gp or 0, row.pr or 0,
            row.provisional and " |cff33ff33(provisional)|r" or ""))
    end
end

--------------------------------------------------------------------------
-- Raid panel (officer recorder controls + standby)
--------------------------------------------------------------------------

function UI.BuildRaidPanel(panel)
    local recordBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    recordBtn:SetSize(140, 22)
    recordBtn:SetPoint("TOPLEFT", 0, 0)
    recordBtn:SetText("Record this raid")
    recordBtn:SetScript("OnClick", function()
        local info = { GetInstanceInfo and GetInstanceInfo() }
        local name, difficultyID, instanceID = info[1], info[3], info[8]
        SideQuest.Recorder.StartRecording(name, instanceID, difficultyID, GetNumGroupMembers and GetNumGroupMembers())
    end)

    local startBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    startBtn:SetSize(140, 22)
    startBtn:SetPoint("TOPLEFT", recordBtn, "BOTTOMLEFT", 0, -8)
    startBtn:SetText("Start raid (on time)")
    startBtn:SetScript("OnClick", function()
        SideQuest.Recorder.StartRaid()
    end)

    local endBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    endBtn:SetSize(140, 22)
    endBtn:SetPoint("TOPLEFT", startBtn, "BOTTOMLEFT", 0, -8)
    endBtn:SetText("End raid (full night)")
    endBtn:SetScript("OnClick", function()
        SideQuest.Recorder.EndRaid()
    end)

    makeFontString(panel, "Standby:", { "TOPLEFT", 0, -110 })
    local scroll, content = buildScrollList(panel)
    scroll:SetPoint("TOPLEFT", 0, -130)
    panel.standbyContent = content
end

SideQuest.On("SQ_PROMPT_RECORD", function()
    SideQuest.Print("You're in a raid instance. Use /sq or the Raid tab to 'Record this raid' if you're officer of the night.")
end)

--------------------------------------------------------------------------
-- Loot panel (officer bid ranking + award)
--------------------------------------------------------------------------

function UI.BuildLootPanel(panel)
    local openLootBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openLootBtn:SetSize(160, 22)
    openLootBtn:SetPoint("TOPLEFT", 0, 0)
    openLootBtn:SetText("Open bidding (loot window)")
    openLootBtn:SetScript("OnClick", function()
        for _, item in ipairs(SideQuest.Loot.GetLootWindowItems()) do
            SideQuest.Loot.OpenBid(item.link)
        end
    end)

    local scroll, content = buildScrollList(panel)
    scroll:SetPoint("TOPLEFT", 0, -30)
    panel.bidContent = content
    panel.bidRows = {}
end

function UI.RefreshBidRanking(bid)
    local panel = UI.panels and UI.panels.Loot
    if not panel then
        return
    end
    local bids = {}
    for charName, response in pairs(bid.responses or {}) do
        local standingsRow
        for _, row in ipairs(SideQuest.Standings.GetDisplayRows()) do
            for _, c in ipairs(row.characters or {}) do
                if c == charName then
                    standingsRow = row
                end
            end
        end
        bids[#bids + 1] = {
            character = charName,
            response = response,
            pr = standingsRow and standingsRow.pr or 0,
            ep = standingsRow and standingsRow.ep or 0,
            roll = math.random(1, 100),
            trial = standingsRow and standingsRow.trial,
        }
    end
    local ranked = SideQuest.Loot.RankBids(bids)
    for i, b in ipairs(ranked) do
        local fs = panel.bidRows[i]
        if not fs then
            fs = makeFontString(panel.bidContent)
            fs:SetPoint("TOPLEFT", 0, -16 * i)
            panel.bidRows[i] = fs
        end
        fs:SetText(i .. ". " .. b.character .. " (" .. b.response .. ") PR " .. string.format("%.3f", b.pr))
    end
end

--------------------------------------------------------------------------
-- Events panel
--------------------------------------------------------------------------

function UI.BuildEventsPanel(panel)
    local scroll, content = buildScrollList(panel)
    panel.scroll = scroll
    panel.content = content
    panel.rows = {}
end

function UI.RefreshEvents()
    local panel = UI.panels and UI.panels.Events
    if not panel then
        return
    end
    for i, evt in ipairs(SideQuest.Events.Get()) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, panel.content)
            row:SetSize(PANEL_WIDTH - 70, 20)
            row:SetPoint("TOPLEFT", 0, -22 * i)
            row.label = makeFontString(row, nil, { "LEFT", 0, 0 })
            row.inviteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.inviteBtn:SetSize(100, 20)
            row.inviteBtn:SetPoint("RIGHT", 0, 0)
            row.inviteBtn:SetText("Invite signed")
            panel.rows[i] = row
        end
        row.label:SetText(evt.title .. " (" .. tostring(evt.kind) .. ")")
        row.inviteBtn:SetScript("OnClick", function()
            SideQuest.Events.InviteSigned(evt.id)
        end)
        row:Show()
    end
end

--------------------------------------------------------------------------
-- Sync panel: export/import dialogs
--------------------------------------------------------------------------

function UI.BuildSyncPanel(panel)
    local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    exportBtn:SetSize(120, 22)
    exportBtn:SetPoint("TOPLEFT", 0, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local str = SideQuest.Sync.BuildExport()
        UI.ShowExportBox(str)
    end)

    local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearBtn:SetSize(120, 22)
    clearBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)
    clearBtn:SetText("Export: Clear")
    clearBtn:SetScript("OnClick", function()
        SideQuest.Sync.ClearPending()
    end)

    local importBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importBtn:SetSize(120, 22)
    importBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        UI.ShowImportBox()
    end)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -34)
    scroll:SetPoint("BOTTOMRIGHT", -20, 0)
    local editBox = CreateFrame("EditBox", nil, scroll, "InputBoxTemplate")
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetSize(PANEL_WIDTH - 90, PANEL_HEIGHT - 150)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scroll:SetScrollChild(editBox)
    panel.editBox = editBox
end

function UI.ShowExportBox(str)
    local panel = UI.panels.Sync
    panel.editBox:SetText(str)
    panel.editBox:HighlightText()
    panel.editBox:SetFocus()
end

function UI.ShowImportBox()
    local panel = UI.panels.Sync
    panel.editBox:SetText("")
    panel.editBox:SetFocus()
    panel.importMode = true
    panel.editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text:match("^SQI1:") and panel.importMode then
            panel.importMode = false
            SideQuest.Sync.ImportString(text)
        end
    end)
end

SideQuest.On("SQ_SHOW_EXPORT", function(str)
    UI.BuildMainFrame():Show()
    UI.ShowTab("Sync")
    UI.ShowExportBox(str)
end)

SideQuest.On("SQ_SHOW_IMPORT", function()
    UI.BuildMainFrame():Show()
    UI.ShowTab("Sync")
    UI.ShowImportBox()
end)

SideQuest.On("SQ_OPEN_MAIN_WINDOW", function()
    UI.Toggle()
end)

SideQuest.On("SQ_STANDINGS_UPDATED", function()
    UI.RefreshStandings()
end)

SideQuest.On("SQ_BID_OPENED", function(bid)
    UI.ShowTab("Loot")
    UI.RefreshBidRanking(bid)
end)

return UI
