# Changelog

## 1.0.0-beta3

A full pass over the settings: what the controls are called, what they mean, and where
they live. Your saved filters and presets carry over.

**The window**

- One rule everywhere: a ticked row is visible. "Block world quests" is now a **World
  Quests** row in the same list as the quest types, and the minimap switch reads
  "Minimap button" (ticked = shown) in the window and on the Escape-menu page.
- Two shapes for the same rows. Opened from the map it stays one tall column beside the
  map; opened from the minimap button, `/questprism` or the keybinding it is two columns,
  using the screen's width instead of its height. The standalone position is remembered.
- Every quest row carries the Map Legend's own name and description (Campaign,
  Important, Legendary, Meta, Repeatable, Local Story). Trivial Quests, Expedition and
  World Quests have descriptions of their own.
- "This character / All characters" sits at the top, above the rows it affects.
  "Hide / Dim" for filtered pins and the objective tracker switch are together under
  "Where it applies". Sections no longer collapse.

**Presets**

- Four built in: Leveling, Campaign only, Endgame, Weekly chores. They share one
  dropdown with your own, built-in first.
- Choosing a preset applies it; the name shows "(edited)" once you change a row.
  "Save as..." replaces the old Load / Save / Delete buttons, and Delete moved into the
  dropdown where it only offers your own presets.
- A saved preset that shares a built-in's name is renamed with " (yours)" on load, so it
  stays reachable.

**The guide**

- Its controls live on the QuestPrism map tab: Follow my guide, the source dropdown
  (only when more than one guide addon is loaded), the Step / Next / Guide buttons and a
  stepper for "Next N". The window keeps a Follow my guide switch with the guide's status
  and a "Show on map" button.
- New option, *Source and scope here too*, off by default: the window shows the same
  guide controls as the map tab. They grey out rather than disappear when no guide is
  followed.

**World quests**

- New option, *Waypoint arrow*, off by default: while World Quests is unticked, a world
  quest is never super-tracked, so the arrow stops pointing at one. A followed guide takes
  precedence, so while you follow Zygor or RestedXP, which draw their own arrow,
  QuestPrism leaves waypoints alone whatever the option says.
- "None", "Hide all" and solo now cover the World Quests row, so All and None are
  symmetric.

**Elsewhere**

- Quick menu: Follow my guide, a Quest types submenu that now includes World Quests, a
  new Presets submenu, then Show all, Hide all and Open.
- The Escape-menu page is trimmed to Open, Minimap button, Debug and Share filters; the
  filter switches are no longer duplicated there.
- The world map and minimap button tooltips show how many pins are hidden, while the map
  is open. `/questprism help` lists the commands.
- The first-run "What's new" popup is gone.
- The window's buttons use the game's modern three-slice button art instead of the
  legacy panel-button textures. A client without that template keeps the old one.

## 1.0.0-beta2

- Block world quests now also stops the "World Quest" banner that slides into the tracker
  when you walk into one. This was the title that stayed visible in beta1.
- The block drives the map's own "World Quests" switch (CVar `questPOIWQ`), which covers the
  world map and the flight map without touching any pin; the pin filter stays as a fallback
  for World Quest List. The switch is put back when the block is lifted, if it was on before.
- Completion alerts are swallowed while blocked instead of queued, so nothing is released
  when the block is lifted.
- `/questprism tracker` reports all four surfaces.

## 1.0.0-beta1

First public beta. Everything below is in; feedback welcome through the CurseForge comments
with a BugSack report when something breaks.

Known issue (fixed in beta2): with "Block world quests" on, the "World Quest" entry banner
still played.

## 1.0.0 (in progress)

Initial release.

- Filter world map quest pins by type: Campaign, Important, Legendary, Meta, Repeatable,
  Local Story and Expedition. Trivial quests use the game's own tracking filter, which
  also covers the minimap.
- Block world quests: one switch hides their map pins, the World Quests section of the
  objective tracker and the "World Quest Complete" alerts.
- Follow my guide: show only the quests of your Zygor or RestedXP guide, or of the
  BtWQuests chain you last opened, with a scope of the current step, the next few steps,
  or the whole guide.
- The objective tracker follows the same type and guide filters (quests are hidden from
  the list, never untracked).
- QuestPrism tab on the world map's side panel listing the guide's quests in guide order,
  with scope buttons and right-click tracking.
- Settings window built on Blizzard's UI templates: named presets, account-wide filters,
  solo mode, dim instead of hide, hidden-pin counter, quick menu on the map and minimap
  buttons, two keybindings, Escape-menu options page.
