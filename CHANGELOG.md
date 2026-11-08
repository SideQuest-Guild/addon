# Changelog

## v0.13.4 (2026-11-08)

### Fixed

- SideQuest no longer gets other addons' /tm macros blocked

## v0.13.3 (2026-11-08)

### Fixed

- Market request notes are cut on a whole character, so the save file stays readable for SideQuest Companion

## v0.13.2 (2026-11-07)

### Fixed

- Import imports what you pasted, Last seen shows Online in green and offline muted, and Debug entries read cleanly

## v0.13.1 (2026-11-07)

### Fixed

- Whisper buttons no longer get other addons' target buttons blocked, and View as has a Back to my view button

## v0.13.0 (2026-11-07)

### New

- Every member gets the site's events from an officer's addon, and the Events tab lists the last 30 days' past events

## v0.12.1 (2026-11-07)

### Fixed

- The Sync tab's calendar says when the site has no upcoming events, instead of waiting for an import that already came

## v0.12.0 (2026-11-07)

### New

- Players outside the guild get a join window, the roster sync reports which ranks are officers, and the guild master gets a Console Debug view with View as

## v0.11.0 (2026-11-07)

### New

- When SideQuest Companion updates the addon while you play, SideQuest says so in game with a Reload now button

### Fixed

- The guild calendar sync stops waiting forever on "Loading the calendar from the server"

## v0.10.1 (2026-11-07)

### Fixed

- Guild member names show again, and Whisper/Invite sit beside Last seen instead of on top of it

## v0.10.0 (2026-11-07)

### New

- Item tooltips and the Market show the auction house price from the guild site, with how many are listed and how fresh it is

## v0.9.1 (2026-11-07)

### Fixed

- On WoW: Forever, Whisper and Invite buttons, Invite signed, turning the party into a raid, guild announcements and shift-clicking items into SideQuest's boxes work again, and a raid leader is recognised as one

## v0.9.0 (2026-11-06)

### New

- Officers can add recruits from the Console's Recruits tab (it fills in your target) and move them through applicant, trial, accepted and declined, and the game offers to put the site's new events on the guild calendar one click at a time

### Fixed

- On WoW: Forever, SideQuest knows each guildmate by first name and surname everywhere, so your professions stay shared, roster rows match the site and whispers reach the right player; plus every guild event shows in the Events tab, Whisper and Invite stop flickering, Market's first fields aren't cut off, and the Roster tab explains Read roster now and stops calling everyone inactive

## v0.8.0 (2026-11-06)

### New

- SideQuest has its own page under Options > AddOns for the minimap button, window scale, reduced motion and what you share with the guild directory, and /sq options opens it

### Fixed

- Officers can start and stop recording from the Console's Raid Night tab or /sq record, see which officers with SideQuest are online and who is already recording, and the course shows what really happened

## v0.7.1 (2026-11-06)

### Fixed

- The Console's Bank tab records the guild bank's item and money log on WoW: Forever when an officer opens the bank, with each entry's real time and no repeats when the bank is opened again
- The minimap button is a standard LibDBIcon button named SideQuest, so minimap button collectors and broker bars list it, and it keeps its place on the rim
- The addon reads the guild roster by itself at login and on changes, so the Guild tab and the website's inactive list fill in without pressing Sweep, and a member with no login on record no longer shows as last seen 1969-12-31
- With no site data yet, the Guild and Events tabs say how to get it instead of 'No members match these filters', the header says how old the site data is, and the Sync tab and /sq export explain that SideQuest Companion uploads the export and loads the site's data by itself

## v0.7.0 (2026-11-06)

### New

- Officers can put the site's upcoming events on the in-game guild calendar with Update calendar on the Console's Sync tab or /sq calendar, and moved or cancelled events come off again

## v0.6.0 (2026-11-06)

### New

- SideQuest records each battleground's final scoreboard and sends it to the website with your next sync

## v0.5.2 (2026-11-05)

### Fixed

- The guild crest in the window's corner shows whole again instead of half hidden under the header painting

## v0.5.1 (2026-11-05)

### Fixed

- Dates show again and the Sync window opens: the addon no longer errors on login, roster updates or export, and a staged import is applied once instead of on every login

## v0.5.0 (2026-11-05)

### New

- The Raids tab is now Events, and each event shows its kind as the website names it (World Boss, PvP, Social, ...)

## v0.4.0 (2026-11-05)

### New

- The window opens 25% bigger, about the size of the game's own windows, and /sq scale makes it bigger or smaller
- Crafters > Professions lists every guildmate's professions by default, with a Profession column; the button narrows it to one and steps back to All

### Fixed

- The window's headings, tabs and title read properly in game instead of as "XE2X80X89" codes, it draws above quest arrows, and the You tab no longer leaves gaps or empty buttons
- Empty Guild, Ledger and Market views say what to do instead of overlapping text or a blank panel, and Enter runs a search

## v0.3.0 (2026-11-05)

### New

- A crest button on the minimap opens the window (drag it to move, /sq minimap to hide it), and the addon list shows the guild crest

## v0.2.0 (2026-10-31)

### New

- The window wears WoW: Forever's own frame, tabs and close button, with the guild site's chambers, ribbons and buttons inside, and a wax seal stamps each finished raid-night step
- The addon applies the import SideQuest Companion stages, at an officer's next login
- The addon keeps a guild directory of every member's professions and skill, character, craft cooldowns, market listings and materials, with Crafters and Market tabs to search it

### Fixed

- Sidequest-sync creates its token file as 0600, so the token is never readable by other users
- The Raid Night tab lists each standby player once

## v0.1.0 (2026-10-30)

### New

- SideQuest guild addon for WoW: Forever (raid recorder, EPGP loot, standings, events, site sync) and the sidequest-sync uploader
- The SideQuest window as a guild sheet for members and a console for officers; roster, crafters, sign-ups, news, raid prep, bank, recruits and announcements; v2 sync; layout-preview renderer

