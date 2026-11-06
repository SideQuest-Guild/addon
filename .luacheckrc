-- .luacheckrc
std = "lua51"
max_line_length = false
self = false
unused_args = false -- WoW event handler signatures are fixed; many args are unused by design

-- The addon files are a mix of real Blizzard API globals (read-only) and a
-- few globals the addon itself defines and mutates across files.
globals = {
    "SideQuestDB", "SideQuest", "SideQuestJSON", "SideQuestBase64",
    "SLASH_SIDEQUEST1", "SlashCmdList", "SideQuest_OnAddonCompartmentClick",
}

read_globals = {
    -- WoW client API used by the addon
    "CreateFrame", "UIParent", "GetServerTime", "GetTime", "GetNormalizedRealmName", "date",
    "UnitName", "UnitGUID", "UnitClass", "UnitLevel", "UnitRace", "IsInRaid", "IsInGroup",
    "GetNumGroupMembers", "IsInInstance", "GetInstanceInfo",
    "GetNumLootItems", "GetLootSlotLink", "GiveMasterLoot",
    "ConvertToRaid", "InviteUnit", "GetGuildInfo",
    "C_GuildInfo", "C_ChatInfo", "C_Item", "C_Timer", "Enum",
    "issecretvalue", "DEFAULT_CHAT_FRAME",
    "StaticPopup_Show", "StaticPopupDialogs",
    -- v2: roster, professions, bank, prep, group placement
    "GetNumGuildMembers", "GetGuildRosterInfo",
    "C_TradeSkillUI", "GetProfessions", "GetProfessionInfo",
    "GetNumGuildTradeSkill", "GetGuildTradeSkillInfo", "QueryGuildRecipes",
    "C_GuildBank",
    "C_PvP", "GetNumBattlefieldScores", "GetBattlefieldWinner", "RequestBattlefieldScoreData", "UnitFactionGroup",
    "InCombatLockdown", "SendChatMessage", "ChatFrame_SendTell",
    "C_UnitAuras", "UnitBuff", "GetInventoryItemDurability", "C_DurabilityInfo",
    "SetRaidSubgroup", "SwapRaidSubgroup", "GetItemInfo", "IsRaidLeader", "IsPartyLeader", "GameTooltip",
    "C_Texture", "NineSliceUtil", "CreateColor", "ColorMixin",
    "C_Reputation", "TooltipDataProcessor", "hooksecurefunc", "ChatEdit_InsertLink",
    -- directory: professions/character/cooldowns/stock
    "C_SkillInfo", "C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_QuestLog",
    "C_Container", "GetAverageItemLevel",
    -- minimap button
    "Minimap", "GetCursorPosition",
    -- optional third-party price hints (Market.SuggestPrice), never required
    "Auctionator", "TSM_API",
}

-- The WoW client has no `os` or `io` library (only the `date`/`time` globals): using them errors in game.
files["SideQuest/"] = { not_globals = { "os", "io" } }

-- Test files additionally define/read the WoW API stub and its control table.
files["tests/wowstub.lua"] = {
    globals = {
        "WowStub", "GetServerTime", "GetTime", "UnitName", "UnitGUID", "UnitClass", "UnitLevel", "UnitRace",
        "os", "date", "time",
        "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNormalizedRealmName",
        "issecretvalue", "C_GuildInfo", "GetGuildInfo", "IsInInstance",
        "GetInstanceInfo", "GetNumLootItems", "GetLootSlotLink", "GiveMasterLoot",
        "C_Item", "ConvertToRaid", "InviteUnit", "Enum", "C_ChatInfo",
        "C_Timer", "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME",
        "GetNumGuildMembers", "GetGuildRosterInfo", "C_TradeSkillUI",
        "GetProfessions", "GetProfessionInfo", "GetNumGuildTradeSkill", "GetGuildTradeSkillInfo",
        "QueryGuildRecipes", "GetAverageItemLevel",
        "C_SkillInfo", "C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_QuestLog", "C_Reputation",
        "C_Container", "Minimap", "GetCursorPosition",
        "C_GuildBank", "InCombatLockdown", "SendChatMessage",
        "C_PvP", "GetNumBattlefieldScores", "GetBattlefieldWinner", "RequestBattlefieldScoreData", "UnitFactionGroup",
        "C_UnitAuras", "UnitBuff", "GetInventoryItemDurability", "C_DurabilityInfo",
        "SetRaidSubgroup", "SwapRaidSubgroup", "GetItemInfo",
        "C_Texture", "NineSliceUtil", "CreateColor", "ColorMixin",
    },
}


files["tests/run_tests.lua"] = {
    globals = { "WowStub", "SideQuestDB", "ROOT" },
}

files["tests/preview/record.lua"] = {
    globals = { "WowStub" },
}

files["tests/test_directory.lua"] = {
    globals = { "WowStub" },
}

files["tests/test_ui_directory.lua"] = {
    globals = { "WowStub" },
}

files["tests/test_minimap.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}
