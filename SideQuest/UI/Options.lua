-- SideQuest/UI/Options.lua
-- Registers "SideQuest Guild" under the game menu's Options > AddOns tab (Settings.RegisterAddOnCategory), so
-- every setting /sq already understands is reachable without typing a command. Each row binds straight to the
-- saved-variable field its matching /sq command reads and writes, so the panel, the slash commands and the
-- window's own Sharing checklist (UI/Main.lua) always agree. `/sq options` (and `/sq settings`) opens it with
-- Settings.OpenToCategory.

SideQuest = SideQuest or {}
SideQuest.UI = SideQuest.UI or {}
SideQuest.UI.Options = SideQuest.UI.Options or {}
local Options = SideQuest.UI.Options

if not Settings then
    return Options -- no modern Settings API (headless, or a client that predates it)
end

local CATEGORY_NAME = "SideQuest Guild"
-- Same range and default /sq scale uses (UI/Main.lua WINDOW_SCALE_MIN/MAX/DEFAULT_SCALE).
local SCALE_MIN, SCALE_MAX, SCALE_DEFAULT = 0.75, 2, 1.25

-- The five directory sections settings.share toggles, in docs/directory.md's table order. The sentences match
-- UI/Main.lua's SHARE_SECTIONS (the window's own Sharing checklist) word for word.
local SHARE_SECTIONS = {
    { key = "prof", label = "Share my professions", sentence = "Shares your professions, skill levels and known recipes." },
    { key = "char", label = "Share my character sheet", sentence = "Shares your level, spec, item level, attunements and tracked reputations." },
    { key = "cd", label = "Share my craft cooldowns", sentence = "Shares your craft cooldowns and when each is ready." },
    { key = "market", label = "Share my market listings", sentence = "Shares what you sell, your standing buy offers and your requests." },
    { key = "stock", label = "Share my crafting stock", sentence = "Shares the crafting materials you hold in bags and bank." },
}

local function openWindow()
    SideQuest.Fire("SQ_OPEN_MAIN_WINDOW")
end

-- UI/MinimapButton.lua only defines Refresh when LibDataBroker/LibDBIcon are present.
local function refreshMinimapButton()
    local MinimapButton = SideQuest.UI.MinimapButton
    if MinimapButton and MinimapButton.Refresh then
        MinimapButton.Refresh()
    end
end

-- UI/Main.lua only defines ApplyWindowScale when CreateFrame exists (headless tests skip it).
local function applyWindowScale()
    if SideQuest.UI.ApplyWindowScale then
        SideQuest.UI.ApplyWindowScale()
    end
end

--- Registers the category once, the first time SQ_READY fires (after SavedVariables load, so every setting
-- binds to a real value instead of nil). Safe to call again; later calls just return the same category.
function Options.Register()
    if Options.category then
        return Options.category
    end

    local category = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
    Settings.RegisterAddOnCategory(category)
    Options.category = category
    local layout = SettingsPanel:GetLayout(category)

    -- Minimap button, inverted from the saved hide flag, paired with a button that opens the window right
    -- from the panel -- the "can I open SideQuest from here" the options tab was missing.
    local minimapSetting = Settings.RegisterProxySetting(category, "SIDEQUEST_MINIMAP_SHOWN", Settings.VarType.Boolean,
        "Show minimap button", true,
        function() return not SideQuestDB.ui.minimap.hide end,
        function(shown)
            SideQuestDB.ui.minimap.hide = not shown
            refreshMinimapButton()
        end)
    local minimapData = Settings.CreateSettingInitializerData(minimapSetting, nil,
        "Shows the SideQuest crest on the minimap rim. Click it to open or close the window. Same as /sq minimap.")
    minimapData.buttonText = "Open SideQuest"
    minimapData.OnButtonClick = openWindow
    layout:AddInitializer(Settings.CreateSettingInitializer("SettingsCheckboxWithButtonControlTemplate", minimapData))

    -- Window scale, applied and saved the way /sq scale does.
    local scaleSetting = Settings.RegisterAddOnSetting(category, "SIDEQUEST_WINDOW_SCALE", "scale", SideQuestDB.ui,
        Settings.VarType.Number, "Window scale", SCALE_DEFAULT)
    local scaleOptions = Settings.CreateSliderOptions(SCALE_MIN, SCALE_MAX, 0.05)
    if MinimalSliderWithSteppersMixin and scaleOptions.SetLabelFormatter then
        scaleOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%.2f", value)
        end)
    end
    Settings.CreateSlider(category, scaleSetting, scaleOptions,
        string.format("Makes the SideQuest window bigger or smaller, from %.2f to %.2f. Same as /sq scale.",
            SCALE_MIN, SCALE_MAX))
    Settings.SetOnValueChangedCallback("SIDEQUEST_WINDOW_SCALE", applyWindowScale)

    -- Reduce motion.
    local motionSetting = Settings.RegisterAddOnSetting(category, "SIDEQUEST_REDUCE_MOTION", "reduceMotion",
        SideQuestDB.settings, Settings.VarType.Boolean, "Reduce motion", false)
    Settings.CreateCheckbox(category, motionSetting,
        "Skips the window-open, tab-crossfade, wax seal and toast animations.")

    -- Guild directory sharing: what this character publishes, same five switches as the You tab's Sharing
    -- checklist and /sq share.
    layout:AddInitializer(Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", {
        name = "Guild directory sharing",
        tooltip = "What this character publishes to the guild directory. See /sq dir.",
    }))
    for _, section in ipairs(SHARE_SECTIONS) do
        local shareSetting = Settings.RegisterAddOnSetting(category, "SIDEQUEST_SHARE_" .. section.key:upper(),
            section.key, SideQuestDB.settings.share, Settings.VarType.Boolean, section.label, true)
        Settings.CreateCheckbox(category, shareSetting, section.sentence)
    end

    return category
end

SideQuest.On("SQ_READY", Options.Register)

local function openOptions()
    local category = Options.Register()
    Settings.OpenToCategory(category:GetID())
end

SideQuest.RegisterSlash("options", openOptions, "options - open the SideQuest settings panel")
SideQuest.RegisterSlash("settings", openOptions, "settings - same as /sq options")

return Options
