-- SideQuest/UI/MinimapButton.lua
-- The crest on the minimap rim: click to open or close the window, drag it
-- round the rim. Shown by default; `/sq minimap` hides or shows it. The
-- button is a LibDataBroker launcher drawn by LibDBIcon-1.0, so minimap
-- button collectors and broker displays list it as "SideQuest". The game's
-- addon compartment (the minimap's addon list) calls the same toggle through
-- the .toc's AddonCompartmentFunc.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
SideQuest.UI.MinimapButton = SideQuest.UI.MinimapButton or {}
local MinimapButton = SideQuest.UI.MinimapButton

function SideQuest_OnAddonCompartmentClick()
    SideQuest.Fire("SQ_OPEN_MAIN_WINDOW")
end

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
if not LDB or not DBIcon then
    return MinimapButton -- headless, or a client without a minimap
end

local NAME = "SideQuest"
local CREST = "Interface\\AddOns\\SideQuest\\Media\\Skin\\CrestPortrait"

MinimapButton.launcher = LDB:NewDataObject(NAME, {
    type = "launcher",
    label = "SideQuest Guild",
    icon = CREST,
    OnClick = function()
        SideQuest.Fire("SQ_OPEN_MAIN_WINDOW")
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("SideQuest Guild")
        tooltip:AddLine("Click to open or close. Drag to move.", 1, 1, 1)
        tooltip:AddLine("/sq minimap hides this button.", 0.7, 0.7, 0.7)
    end,
})

local function settings()
    return SideQuestDB.ui.minimap
end

--- Registers the button once, then shows, hides and places it to match the saved setting. Refresh also points
--- LibDBIcon at the current save table, which changes when the save is reset.
function MinimapButton.Refresh()
    if not DBIcon:IsRegistered(NAME) then
        DBIcon:Register(NAME, MinimapButton.launcher, settings())
    end
    DBIcon:Refresh(NAME, settings())
    MinimapButton.button = DBIcon:GetMinimapButton(NAME)
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
