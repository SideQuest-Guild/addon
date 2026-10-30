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

OWN-WORLD (Hybrid, built): Forever's own Camelot chrome outside: the gilded chamfered portrait frame, the crest in its portrait ring, the native close button, native tabs hanging below the window and native top tabs on the Console. Inside, the site's citadel cut in the same chamfered shape language, with no square boxes: night ground (#0a0f1a to #18253d), chambers with a gilded rim, inner hairline and riveted diamonds, royal swallowtail ribbons in tracked Libertinus Serif Display caps, EB Garamond body in ink #f2efe9 and mist #c4cddd, flavor gold #ffd36a only for quoted text, class colours on names, quality colours on items, the game's own atlases for icons, checkboxes, quest marks, expand arrows and the cast bar, and the addon's own SVG-drawn art (tools/skin-art/render.mjs) for everything else.

STORY: A member opens it, sees their standing, next raid and sign-up, and who's on; one tab finds a crafter or the ledger. An officer opens the gold-edged Console and works the night step by step.

FIRST VIEWPORT: Native frame with the crest in the portrait ring and SIDEQUEST in the title band; the Great Hall painting under it with a freshness line ("Synced 2h ago") at lower right. Left chamber YOU: name in class colour, rank and alts, PR with rank, a four-week EP/GP table, next event with Going/Maybe/Can't, badges. Right chamber GUILD NOW: online count, then the news feed. Native tabs below: You, Guild, Crafters, Raids, Ledger, News, and Console for officers.

FORM: Guild Sheet, my ranked list #3, dealt lead. Seed key 96b6c010. Raised by the orienteering challenger: on raid night the Console is a numbered course (Prep, Invite, Start, each boss, Loot, End) whose controls punch as they are done.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved

- Exact window size at default UI scale (target ~860x560, resizable down to ~700x480).
- Guild bank log APIs and profession recipe APIs are unverified on Forever; the build must detect and degrade.
