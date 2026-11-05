# The guild directory

Every member's SideQuest keeps a record of their own character and shares it with the guild over addon messages:
professions and skill levels, character basics, craft cooldowns, attunements and key reputations, what they sell and
want to buy, and the crafting materials they hold. Every client keeps the records it has heard, so offline members
still show up. Officers' syncs carry the whole directory to sidequest-guild.com.

This file is the contract between the addon's files, and between the addon and the site (the `directory` and
`item_names` fields of the `SQX1:` export). Change it here first.

## Records and sections

A record belongs to one character, keyed by the normalized `"Name-Realm"` (`SideQuest.NormalizeUnit`). It has five
sections. Each section travels and is stored on its own, so a price change never resends a recipe list.

| Section | Holds | Changes when |
|---|---|---|
| `prof` | professions, skill, max skill, known recipes | skill up, a profession window opens, a profession is learned or dropped |
| `char` | level, class, race, spec, average item level, attunements, tracked reputations | level up, gear or spec change, a quest or reputation change |
| `cd` | craft cooldowns and when each is ready | a cooldown craft is cast, or one comes off cooldown |
| `market` | what the player sells, buys and requests | the player edits their prices or requests |
| `stock` | crafting materials in bags and bank | bags change (debounced), the bank is opened |

Every stored section is `{ v = "<8 hex>", at = <server time>, d = <data or nil>, relayed = <bool> }`:

- `v` is a hash of the canonical JSON of `d` (`SideQuest.Directory.Hash`). Same data, same `v`, on every client.
- `at` is the owner's `GetServerTime()` when `d` last changed. Newer `at` wins everywhere, on clients and on the site.
- `d = nil` is a tombstone: the owner stopped sharing that section (Settings), and receivers drop what they had.
- `relayed` is local only: true when this client heard it from someone other than the owner.

### Section data

Field names are the same on the wire, in SavedVariables and in the export. Lists are JSON arrays; never send an empty
table where an array is meant (use `SideQuest.Codec` helpers so `{}` encodes as `[]`).

```lua
prof = {
    professions = {
        -- one per profession the character has, primary and secondary (Cooking, Fishing, First Aid)
        { name = "Tailoring", skill_line = 197, skill = 285, max_skill = 300,
          recipes = { 18560, 18401 },   -- learned recipe spell IDs; nil until the window was opened once
          recipes_at = 1793450000 },    -- when recipes were read; nil with recipes
    },
}

char = {
    level = 60, class = "MAGE", race = "Human",        -- class is the class file token
    spec = "Frost",                                     -- nil when the client can't say
    item_level = 61.4,                                  -- one decimal, nil when unknown
    attunements = { "onyxia" },                         -- keys from SideQuest.Data.ATTUNEMENTS that are done
    reputations = { { faction_id = 529, standing = 6, value = 4200 } },  -- only SideQuest.Data.REPUTATIONS
}

cd = {
    cooldowns = { { key = "transmute", ready_at = 1793460000 } },  -- 0 means ready now; only cooldowns the character has
}

market = {
    sell = { { item_id = 14048, price = 12000, qty = 20, crafted = false } },  -- price in copper, nil = "whisper me"
    buy = { { item_id = 12360, price = 35000 } },                             -- standing offer for a material
    requests = { { id = "Name-Realm-17", item_id = 12360, qty = 4, price = 35000, note = "for Arcanite Reaper",
                   at = 1793450000 } },
}

stock = {
    bags = { { 14048, 20 }, { 12360, 3 } },   -- { item_id, count } for trade goods and reagents only
    bank = { { 14256, 40 } },
    bank_at = 1793440000,                     -- when the bank was last read; nil if never
}
```

Limits (drop the excess, keep the newest): 2000 recipes per profession, 100 `sell`, 100 `buy`, 30 `requests`
(note at most 80 chars), 300 entries each in `bags` and `bank`, 30 reputations.

`stock` only counts items whose class is Trade Goods or Reagent (`C_Item.GetItemInfoInstant` classID 7 or 5), plus
anything in the player's `market.sell`. Never gold, gear or quest items.

## Where it lives

```lua
SideQuestDB.directory = {
    ["Name-Realm"] = { prof = {v, at, d, relayed}, char = {...}, cd = {...}, market = {...}, stock = {...},
                       seen_at = <last time anything was heard from or about them> },
}
SideQuestDB.settings.share = { prof = true, char = true, cd = true, market = true, stock = true }
```

The table is account-wide (SavedVariables are per account), so an alt's own record and everyone else's survive
switching characters. Entries are pruned when the guild roster is known and the character is not in it, or when
`seen_at` is over 90 days old.

## API (SideQuest.Directory)

- `Directory.SetMine(section, d)`: collectors call this with fresh data. It hashes `d`; if `v` changed it stores the
  section with `at = now` and schedules an announce (debounced 3 s). A section whose share setting is off is stored
  as a tombstone instead.
- `Directory.Get(character)`, `Directory.Section(character, section)` return stored data (`d`), or nil.
- `Directory.All()` iterates `character, entry`.
- `Directory.Hash(d)` returns the 8-hex version.
- Fires `SQ_DIRECTORY_UPDATED(character, section)` after any stored change, mine or received.

Lookups that the UI and the tooltip share live in `SideQuest.Directory` too, so the UI never walks the raw tables:

- `Directory.WhoCrafts(query)` → `{ { character, profession, skill, recipe_id, recipe_name, online } }` (recipe name
  or profession substring)
- `Directory.ByProfession(name)` → members with that profession, best skill first; every member's every
  profession (each entry names its `profession`) when `name` is nil
- `Directory.WhoHas(itemId)` → `{ { character, bags, bank, online } }`
- `Directory.WhoSells(itemId)`, `Directory.WhoBuys(itemId)`, `Directory.Requests()`
- `Directory.Cooldowns(key)` → who has it and when it's ready

`online` comes from the guild roster when available, otherwise from having heard the character in the last 10
minutes.

## Messages

All are `Comm.SendJSON` on `GUILD`, chunked and throttled to about one chunk a second. Addon messages fail inside
instances; the directory just catches up later.

| Type | Body | Sent by | When |
|---|---|---|---|
| `DIR_V` | `{ c, v = { prof = "h", char = "h", ... } }` | owner | 3 s after a change (debounced), and 10-25 s after login |
| `DIR_Q` | `{ c, s = { "prof", "market" } }` | anyone holding an older or missing section | after a random 0-3 s wait, unless someone else's `DIR_Q` for the same `c` and sections was seen first |
| `DIR_R` | `{ c, s = "prof", v, at, d }` | the owner, or a relayer when the owner is offline | in answer to `DIR_Q` |
| `DIR_LQ` | `{ id }` | a client that just logged in | once, 30-60 s after login |
| `DIR_L` | `{ id, e = { ["Name-Realm"] = { prof = "h", ... } } }` | one member (suppressed like other answers) | in answer to `DIR_LQ` |

Rules:

- A receiver stores a `DIR_R` only if its `at` is newer than what it holds, or it holds nothing. It checks that `v`
  matches `Hash(d)` and drops the section if not.
- The owner answers a `DIR_Q` for itself at once. A relayer waits 2-5 s and stays quiet if the owner or another
  relayer answered (`Comm.ScheduleAnswer`/`SuppressAnswer`, keyed `DIR:<c>:<s>:<v>`).
- At most one `DIR_Q` per character and section every 30 s, and at most one answer per character and section every
  30 s, from any one client.
- A client that gets a `DIR_L` asks (`DIR_Q`) for what it is missing or holds older, at most 10 characters at a time,
  the next batch after those arrive or after 60 s.
- Old clients ignore every `DIR_*` type. `CRAFT_Q`/`CRAFT_A` stay and are answered from the directory as well.

## Collectors

All run out of combat only (`SideQuest.WhenOutOfCombat`), and degrade silently when an API is missing. Forever runs
the Mainline 12.x API (interface 16001): the Classic globals (`GetTradeSkillLine`, `GetSkillLineInfo`,
`GetTalentTabInfo`, `GetSpellCooldown`, `GetContainerItemInfo`, `GetItemInfoInstant`) are gone.

| Section | Source |
|---|---|
| `prof` skills | `GetProfessions()` + `GetProfessionInfo(i)` at login and on `SKILL_LINES_CHANGED`; else `C_SkillInfo.GetNumSkillLines`/`GetSkillLineInfo` |
| `prof` recipes | on `TRADE_SKILL_SHOW`/`TRADE_SKILL_LIST_UPDATE`: `C_TradeSkillUI.GetBaseProfessionInfo()` (or `GetChildProfessionInfo()`), `GetAllRecipeIDs()`, `GetRecipeInfo(id).learned`; skip linked/guild views (`IsTradeSkillLinked`, `IsTradeSkillGuild`) |
| `char` | `UnitLevel`, `UnitClass`, `UnitRace`, `C_SpecializationInfo.GetSpecialization`/`GetSpecializationInfo`, `GetAverageItemLevel`; attunements via `C_QuestLog.IsQuestFlaggedCompleted`; reputations via `C_Reputation.GetFactionDataByID` |
| `cd` | `C_Spell.GetSpellCooldown` for spell cooldowns, `C_Item.GetItemCooldown` for item ones, for entries in `SideQuest.Data.COOLDOWNS` the character knows (`C_SpellBook.IsSpellKnown` / `C_Item.GetItemCount`) |
| `market` | the player's own edits (`/sq sell`, `/sq buy`, `/sq request`, the Market tab) |
| `stock` | `C_Container.GetContainerNumSlots`/`GetContainerItemInfo` on `BAG_UPDATE_DELAYED` (debounced 5 s) and on `BANKFRAME_OPENED` |

`SideQuest.Data` (`Data.lua`) holds the tables these read: `PROFESSIONS` (English name, skill line ID, primary or
secondary), `COOLDOWNS` (key, label, profession, spell IDs or item ID, cooldown length), `ATTUNEMENTS` (key, label,
raid, quest IDs, any one of which counts) and `REPUTATIONS` (faction IDs to track). Entries not yet confirmed on the
Forever client say so in a comment; a wrong ID only means that line stays empty.

Members who don't run SideQuest: when `C_TradeSkillUI.IsGuildTradeSkillsEnabled()` is true, an officer's client reads
the game's own guild profession list (`GetNumGuildTradeSkill`/`GetGuildTradeSkillInfo`, after `QueryGuildRecipes`)
at most once an hour and stores a `prof` section (skills only, `recipes = nil`, `relayed = true`) for characters
that have no `prof` section yet. It never overwrites a section its owner sent.

Price hints for the Market tab, when installed: Auctionator (`Auctionator.API.v1.GetAuctionPriceByItemID("SideQuest",
id)`), then TSM (`TSM_API.GetCustomPriceValue("dbmarket", "i:" .. id)`). Never required.

## Export to the site

The `SQX1:` payload stays `v = 2` and gains three optional fields that older sites ignore:

```json
"directory": [
  { "character": "Name-Realm",
    "sections": { "prof": { "v": "1a2b3c4d", "at": 1793450000, "d": { ... } },
                  "market": { "v": "...", "at": 1793450100, "d": null } } }
],
"item_names": { "14048": "Runecloth", "12360": "Arcanite Bar" },
"recipe_names": { "18560": "Mooncloth" }
```

- `directory` is every record the exporting client holds (not only pending changes), so any officer's sync brings the
  site up to date. `d: null` sections tell the site to delete that character's data for the section.
- `item_names` names every item ID the export mentions that the client can name (`C_Item.GetItemNameByID`), and
  `recipe_names` every recipe spell ID (`C_Spell.GetSpellName`); the site keeps names it already has for the rest.
- The legacy `professions` array keeps being sent from `pending.professions` for older sites.
- Officers rebuild `lastExport` on `PLAYER_LOGOUT`, so SideQuest Companion always uploads a current export.

The site upserts per character and section, newest `at` wins, and treats each section's lists as the full set for
that character (replace, not merge).
