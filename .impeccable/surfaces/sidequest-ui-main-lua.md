---
version: 1
slug: "sidequest-ui-main-lua"
primary_target: "SideQuest/UI/Main.lua"
related_targets: ["SideQuest/UI/BidPopup.lua"]
---

# SideQuest window (in-game addon)

Scope: the addon's main window and its popups (bid popup, announcement toast, record prompt). Mode: Operate.
Audience: every SideQuest member between pulls or in town; officers and GMs running raid nights and the week's guild work.
Jobs: answer who's on, who crafts this, where do I stand, am I signed, in one or two clicks; run prep, invites, recording, loot, roster, recruits, bank and announcements without leaving the game.
Constraints: Lua frames only (no HTML/CSS); nothing opens or animates in combat; class and quality colours always paired with text; every automatic step has a stated manual fallback; data freshness always shown.

## Direction contract

THESIS: The guild's character sheet. The window opens on you, the way the game's Character frame does, not on a roster table; it refuses the category's left-rail-plus-roster-grid.

OWN-WORLD: The site's citadel carried in game. Night ground (#0a0f1a to #18253d), chamber frames (stone outer line, guild-gold-deep inner line 5px in, gold corner brackets), royal ribbon headings with notched ends in tracked Libertinus Serif Display caps, Friz Quadrata body in ink #f2efe9 and mist #c4cddd, flavor gold #ffd36a only for quoted text, class colours on names, quality colours on items, the game's own atlas icons.

STORY: A member opens it, sees their standing, next raid and sign-up, and who's on; one tab finds a crafter or the ledger. An officer opens the gold-edged Console and works the night step by step.

FIRST VIEWPORT: Painted header strip with crest, wordmark and a freshness line ("synced 2h ago") at right. Left chamber YOU: name in class colour, rank and alts, PR with rank and a four-week bar history, next event with Going/Maybe/Can't, badges. Right chamber GUILD NOW: online count, then the news feed. Bottom tabs: You, Guild, Crafters, Raids, Ledger, News, and Console for officers.

FORM: Guild Sheet, my ranked list #3, dealt lead. Seed key 96b6c010. Raised by the orienteering challenger: on raid night the Console is a numbered course (Prep, Invite, Start, each boss, Loot, End) whose controls punch as they are done.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved

- Exact window size at default UI scale (target ~860x560, resizable down to ~700x480).
- Guild bank log APIs and profession recipe APIs are unverified on Forever; the build must detect and degrade.
