-- SideQuest/UI/MinimapButton.lua
-- The crest on the minimap rim: click to open or close the window, drag it
-- round the rim. Shown by default; `/sq minimap` hides or shows it. The
-- game's addon compartment (the minimap's addon list) calls the same toggle
-- through the .toc's AddonCompartmentFunc.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
SideQuest.UI.MinimapButton = SideQuest.UI.MinimapButton or {}
local MinimapButton = SideQuest.UI.MinimapButton

function SideQuest_OnAddonCompartmentClick()
    SideQuest.Fire("SQ_OPEN_MAIN_WINDOW")
end

if not CreateFrame or not Minimap then
    return MinimapButton -- headless, or a client without a minimap
end

-- Same art and sizes as the minimap's own round buttons: the tracking border
-- ring over a dark disc, with the crest inside.
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local DISC = "Interface\\Minimap\\UI-Minimap-Background"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local CREST = "Interface\\AddOns\\SideQuest\\Media\\Skin\\CrestPortrait"
local RIM_OFFSET = 5 -- how far outside the minimap's edge the button's centre sits

local function settings()
    return SideQuestDB.ui.minimap
end

--- Puts the button on the rim at `settings().angle` degrees (0 = right, counter-clockwise).
local function place(button)
    local angle = math.rad(settings().angle)
    local rx = Minimap:GetWidth() / 2 + RIM_OFFSET
    local ry = Minimap:GetHeight() / 2 + RIM_OFFSET
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * rx, math.sin(angle) * ry)
end

local function followCursor(button)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    settings().angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
    place(button)
end

local function build()
    local button = CreateFrame("Button", "SideQuestMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(HIGHLIGHT)

    local disc = button:CreateTexture(nil, "BACKGROUND")
    disc:SetSize(24, 24)
    disc:SetPoint("CENTER")
    disc:SetTexture(DISC)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(CREST)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture(BORDER)

    button:SetScript("OnClick", function()
        SideQuest.Fire("SQ_OPEN_MAIN_WINDOW")
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", followCursor)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("SideQuest Guild")
        GameTooltip:AddLine("Click to open or close. Drag to move.", 1, 1, 1)
        GameTooltip:AddLine("/sq minimap hides this button.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return button
end

--- Builds the button once and shows or hides it to match the saved setting.
function MinimapButton.Refresh()
    if not MinimapButton.button then
        MinimapButton.button = build()
    end
    place(MinimapButton.button)
    MinimapButton.button:SetShown(not settings().hide)
end

SideQuest.On("SQ_READY", MinimapButton.Refresh)

SideQuest.RegisterSlash("minimap", function()
    local s = settings()
    s.hide = not s.hide
    MinimapButton.Refresh()
    SideQuest.Print(s.hide and "Minimap button hidden. Type /sq minimap to show it again."
        or "Minimap button shown.")
end, "minimap - show or hide the minimap button")

return MinimapButton
