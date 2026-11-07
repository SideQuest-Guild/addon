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
    "StaticPopupDialogs",
}

read_globals = {
    -- WoW client API used by the addon
    "CreateFrame", "UIParent", "GetServerTime", "GetTime", "GetNormalizedRealmName", "date",
    "UnitName", "UnitGUID", "UnitClass", "UnitLevel", "UnitRace", "UnitExists", "UnitIsPlayer", "IsInRaid", "IsInGroup",
    "GetNumGroupMembers", "IsInInstance", "GetInstanceInfo",
    "GetNumLootItems", "GetLootSlotLink", "GiveMasterLoot",
    "ConvertToRaid", "InviteUnit", "GetGuildInfo",
    "C_GuildInfo", "C_ChatInfo", "C_Item", "C_Timer", "Enum", "C_Calendar", "C_DateAndTime",
    -- Forever's chat/party calls (it has no InviteUnit/ChatFrame_SendTell/ConvertToRaid/IsRaidLeader globals)
    "C_PartyInfo", "ChatFrameUtil", "UnitIsGroupLeader",
    -- Forever client identity (no realms, First-Surname)
    "RegionalUniqueNamesEnabled", "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "C_NameUtil", "Constants",
    "issecretvalue", "DEFAULT_CHAT_FRAME",
    "StaticPopup_Show", "StaticPopup_Hide",
    -- v2: roster, professions, bank, prep, group placement
    "GetNumGuildMembers", "GetGuildRosterInfo", "GetGuildRosterLastOnline",
    "C_TradeSkillUI", "GetProfessions", "GetProfessionInfo",
    "GetNumGuildTradeSkill", "GetGuildTradeSkillInfo", "QueryGuildRecipes",
    "C_GuildBank", "GetCurrentGuildBankTab", "QueryGuildBankLog",
    "GetNumGuildBankTransactions", "GetGuildBankTransaction",
    "GetNumGuildBankMoneyTransactions", "GetGuildBankMoneyTransaction", "MAX_GUILDBANK_TABS",
    "C_PvP", "GetNumBattlefieldScores", "GetBattlefieldWinner", "RequestBattlefieldScoreData", "UnitFactionGroup",
    "InCombatLockdown", "SendChatMessage", "ChatFrame_SendTell",
    "C_UnitAuras", "UnitBuff", "GetInventoryItemDurability", "C_DurabilityInfo",
    "SetRaidSubgroup", "SwapRaidSubgroup", "GetItemInfo", "IsRaidLeader", "IsPartyLeader", "GameTooltip",
    "C_Texture", "NineSliceUtil", "CreateColor", "ColorMixin",
    "C_Reputation", "TooltipDataProcessor", "hooksecurefunc", "ChatEdit_InsertLink",
    -- directory: professions/character/cooldowns/stock
    "C_SkillInfo", "C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_QuestLog",
    "C_Container", "GetAverageItemLevel",
    -- minimap button (LibDBIcon-1.0 through LibStub)
    "LibStub",
    -- options panel (Settings API)
    "Settings", "SettingsPanel", "MinimalSliderWithSteppersMixin",
    -- optional third-party price hints (Market.SuggestPrice), never required
    "Auctionator", "TSM_API",
}

-- The WoW client has no `os` or `io` library (only the `date`/`time` globals): using them errors in game.
files["SideQuest/"] = { not_globals = { "os", "io" } }

-- Third-party libraries, kept exactly as their authors ship them.
exclude_files = {
    "SideQuest/Libs/LibStub/",
    "SideQuest/Libs/CallbackHandler-1.0/",
    "SideQuest/Libs/LibDataBroker-1.1/",
    "SideQuest/Libs/LibDBIcon-1.0/",
}

-- Test files additionally define/read the WoW API stub and its control table.
files["tests/wowstub.lua"] = {
    globals = {
        "WowStub", "GetServerTime", "GetTime", "UnitName", "UnitGUID", "UnitClass", "UnitLevel", "UnitRace",
        "UnitExists", "UnitIsPlayer",
        "os", "date", "time",
        "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNormalizedRealmName",
        "issecretvalue", "C_GuildInfo", "GetGuildInfo", "IsInInstance",
        "GetInstanceInfo", "GetNumLootItems", "GetLootSlotLink", "GiveMasterLoot",
        "C_Item", "ConvertToRaid", "InviteUnit", "Enum", "C_ChatInfo",
        "C_Timer", "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME",
        "GetNumGuildMembers", "GetGuildRosterInfo", "GetGuildRosterLastOnline", "C_TradeSkillUI",
        "GetProfessions", "GetProfessionInfo", "GetNumGuildTradeSkill", "GetGuildTradeSkillInfo",
        "QueryGuildRecipes", "GetAverageItemLevel",
        "C_SkillInfo", "C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_QuestLog", "C_Reputation",
        "C_Container", "Minimap", "GetCursorPosition", "C_Calendar", "C_DateAndTime",
        "C_GuildBank", "GetCurrentGuildBankTab", "QueryGuildBankLog",
        "GetNumGuildBankTransactions", "GetGuildBankTransaction",
        "GetNumGuildBankMoneyTransactions", "GetGuildBankMoneyTransaction",
        "InCombatLockdown", "SendChatMessage",
        "C_PvP", "GetNumBattlefieldScores", "GetBattlefieldWinner", "RequestBattlefieldScoreData", "UnitFactionGroup",
        "C_UnitAuras", "UnitBuff", "GetInventoryItemDurability", "C_DurabilityInfo",
        "SetRaidSubgroup", "SwapRaidSubgroup", "GetItemInfo",
        "C_Texture", "NineSliceUtil", "CreateColor", "ColorMixin",
        "strmatch", "securecallfunction", "Settings", "SettingsPanel",
        "StaticPopupDialogs", "StaticPopup_Show", "StaticPopup_Hide",
        "ChatFrame_SendTell", "WOW_PROJECT_CAMELOT", "WOW_PROJECT_ID", "RegionalUniqueNamesEnabled",
        "Constants", "C_NameUtil", "C_PartyInfo", "ChatFrameUtil", "UnitIsGroupLeader",
        "TooltipDataProcessor",
    },
}


files["tests/run_tests.lua"] = {
    globals = { "WowStub", "SideQuestDB", "ROOT" },
}

files["tests/preview/record.lua"] = {
    globals = { "WowStub" },
}

files["tests/test_directory.lua"] = {
    globals = { "WowStub", "GetProfessions" },
}

files["tests/test_ui_directory.lua"] = {
    globals = { "WowStub" },
}

files["tests/test_auctions.lua"] = {
    globals = { "WowStub", "SideQuestDB", "TooltipDataProcessor", "Enum", "UIParent" },
}

files["tests/test_minimap.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_calendar.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_roster.lua"] = {
    globals = { "WowStub", "SideQuestDB", "GetGuildRosterLastOnline" },
}

files["tests/test_recorder.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_ui_console.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_ui_empty_states.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_bank.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_options.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_ui_events.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_recruits.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_ui_guild_rows.lua"] = {
    globals = { "WowStub", "SideQuestDB" },
}

files["tests/test_identity.lua"] = {
    globals = { "WowStub", "SideQuestDB", "GetNumGuildMembers" },
}
