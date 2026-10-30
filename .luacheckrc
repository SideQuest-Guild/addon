-- .luacheckrc
std = "lua51"
max_line_length = false
self = false
unused_args = false -- WoW event handler signatures are fixed; many args are unused by design

-- The addon files are a mix of real Blizzard API globals (read-only) and a
-- few globals the addon itself defines and mutates across files.
globals = {
    "SideQuestDB", "SideQuest", "SideQuestJSON", "SideQuestBase64",
    "SLASH_SIDEQUEST1", "SlashCmdList",
}

read_globals = {
    -- WoW client API used by the addon
    "CreateFrame", "UIParent", "GetServerTime", "GetNormalizedRealmName",
    "UnitName", "UnitGUID", "UnitClass", "IsInRaid", "IsInGroup",
    "GetNumGroupMembers", "IsInInstance", "GetInstanceInfo",
    "GetNumLootItems", "GetLootSlotLink", "GiveMasterLoot",
    "ConvertToRaid", "InviteUnit", "GetGuildInfo",
    "C_GuildInfo", "C_ChatInfo", "C_Item", "C_Timer", "Enum",
    "issecretvalue", "DEFAULT_CHAT_FRAME",
    "StaticPopup_Show", "StaticPopupDialogs",
}

-- Test files additionally define/read the WoW API stub and its control table.
files["tests/wowstub.lua"] = {
    globals = {
        "WowStub", "GetServerTime", "UnitName", "UnitGUID", "UnitClass",
        "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNormalizedRealmName",
        "issecretvalue", "C_GuildInfo", "GetGuildInfo", "IsInInstance",
        "GetInstanceInfo", "GetNumLootItems", "GetLootSlotLink", "GiveMasterLoot",
        "C_Item", "ConvertToRaid", "InviteUnit", "Enum", "C_ChatInfo",
        "C_Timer", "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME",
    },
}

files["tests/run_tests.lua"] = {
    globals = { "WowStub", "SideQuestDB", "ROOT" },
}
