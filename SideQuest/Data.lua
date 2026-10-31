-- SideQuest/Data.lua
-- Static tables the directory collectors read: professions, craft cooldowns, attunements and tracked
-- reputations. See docs/directory.md. Skill line/faction/quest IDs are the stable values used across
-- every WoW version since Classic; entries specific to Forever's own content (its raids, its reputation
-- gates) are marked unconfirmed below because Forever launches after this was written.

SideQuest = SideQuest or {}
SideQuest.Data = SideQuest.Data or {}
local Data = SideQuest.Data

-- name: English profession name (also the directory wire value). skill_line: the skill line ID used by
-- C_SkillInfo/GetProfessionInfo. primary: true for the two-slot crafting/gathering professions, false for
-- the "secondary" skills everyone can have alongside them.
Data.PROFESSIONS = {
    { name = "Alchemy", skill_line = 171, primary = true },
    { name = "Blacksmithing", skill_line = 164, primary = true },
    { name = "Enchanting", skill_line = 333, primary = true },
    { name = "Engineering", skill_line = 202, primary = true },
    { name = "Herbalism", skill_line = 182, primary = true },
    { name = "Leatherworking", skill_line = 165, primary = true },
    { name = "Mining", skill_line = 186, primary = true },
    { name = "Tailoring", skill_line = 197, primary = true },
    { name = "Skinning", skill_line = 393, primary = true },
    { name = "Cooking", skill_line = 185, primary = false },
    { name = "First Aid", skill_line = 129, primary = false },
    { name = "Fishing", skill_line = 356, primary = false },
}

-- key: the directory's `cd.cooldowns[].key`. profession: which prof section it is read for context only.
-- spell_ids/item_id: how `Character.lua` checks the character knows it and reads its cooldown.
-- length_seconds: documentation only (the real cooldown comes from the API at read time).
-- [UNCONFIRMED] Forever's own tuning of these classic cooldowns (length, whether they survived at all)
-- has not been checked; a wrong spell ID just means this cooldown never shows for anyone.
Data.COOLDOWNS = {
    transmute = {
        label = "Transmute Arcanite",
        profession = "Alchemy",
        spell_ids = { 17187 }, -- Transmute: Arcanite (classic value)
        length_seconds = 172800, -- 2 days (classic value)
    },
}

-- key: `char.attunements[]` entry. raid: display label. quest_ids: any one being flagged completed counts.
-- Forever's Barrow Deeps and Hyjal Summit have no attunement chain (per the contract); only Onyxia does.
Data.ATTUNEMENTS = {
    onyxia = {
        label = "Drakefire Amulet",
        raid = "Onyxia's Lair",
        -- [UNCONFIRMED] classic quest ID for the Alliance chain's final quest ("Drakefire Amulet");
        -- Forever may use a different ID for the same quest. A wrong ID just leaves this step empty.
        quest_ids = { 6502 },
    },
}

-- faction_id: tracked in `char.reputations[]`. [UNCONFIRMED] Forever's own key reputations (whatever
-- gates Barrow Deeps/Hyjal Summit recipes or attunements) are not yet known; Argent Dawn is the one
-- classic reputation the contract's own example uses (faction_id 529) and is kept as a placeholder.
Data.REPUTATIONS = {
    { faction_id = 529, label = "Argent Dawn" },
}

return Data
