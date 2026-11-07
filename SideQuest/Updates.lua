-- SideQuest/Updates.lua
-- Tells the player when SideQuest Companion has installed a newer SideQuest while the game is running. The game only
-- reads addon files at login and /reload, so the old version keeps running until then.
--
-- The addon can't read files, but it can try to load a font: SetFont answers whether the file loaded. After an
-- install, Companion leaves a font at Media\Updates\<version that was installed before>.ttf. This version looks for
-- the file named after itself; once the new version is running, it looks for its own name, which isn't there.

SideQuest = SideQuest or {}
SideQuest.Updates = {}
local Updates = SideQuest.Updates

local PROBE_SECONDS = 15
local MARKER_DIR = "Interface\\AddOns\\SideQuest\\Media\\Updates\\"

Updates.ready = false

--- The version in SideQuest.toc as packaged (e.g. "v0.10.1"), or nil in a development checkout.
function Updates.InstalledVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMetadata and getMetadata(SideQuest.ADDON_NAME, "Version")
    if type(version) ~= "string" or version == "" or version:find("@", 1, true) then
        return nil
    end
    return version
end

--- The marker file name for a version, made the same way Companion makes it: anything but letters, digits, dots,
-- dashes and underscores becomes an underscore.
function Updates.MarkerPath(version)
    return MARKER_DIR .. version:gsub("[^%w%.%-_]", "_") .. ".ttf"
end

local probe
local function markerPresent(path)
    if not probe then
        local frame = CreateFrame("Frame")
        frame:Hide()
        probe = frame:CreateFontString(nil, "ARTWORK")
    end
    local ok, loaded = pcall(probe.SetFont, probe, path, 12, "")
    return ok and loaded == true
end

StaticPopupDialogs["SIDEQUEST_UPDATE_READY"] = {
    text = "A SideQuest update is installed. Type /reload to apply it.",
    button1 = "Reload now",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--- Look for Companion's marker once; on finding it, say so (popup and chat) and stop looking.
function Updates.Check()
    if Updates.ready then
        return true
    end
    local version = Updates.InstalledVersion()
    if not version or not markerPresent(Updates.MarkerPath(version)) then
        return false
    end
    Updates.ready = true
    if Updates.ticker then
        Updates.ticker:Cancel()
        Updates.ticker = nil
    end
    SideQuest.Print("A SideQuest update is installed. Type /reload to apply it.")
    StaticPopup_Show("SIDEQUEST_UPDATE_READY")
    return true
end

SideQuest.On("PLAYER_LOGIN", function()
    if Updates.InstalledVersion() and C_Timer and C_Timer.NewTicker then
        Updates.ticker = C_Timer.NewTicker(PROBE_SECONDS, Updates.Check)
    end
end)
SideQuest.RegisterGameEvent("PLAYER_LOGIN")

return Updates
