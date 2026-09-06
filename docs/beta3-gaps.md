# 1.0.0-beta3 gap list

Everything still open after the settings redesign, the two-column window, the popup
removal and the code review. Ticked items are closed; each says how it was closed or
what it is waiting on.

## Needs the game (cannot be checked from the repo)

- [x] **World Quests row icon.** Verified in game: the row draws its marker. The Event
  row's horn icon, taken from the Map Legend, verified the same way.
- [x] **Expedition name.** Resolved from Blizzard's own Map Legend source: the pins the
  addon filed under "Expedition" are the legend's **Event** entry (`MAP_LEGEND_EVENT`,
  "Limited Time Activities"). The row now takes its name, description and horn icon from
  that entry at runtime, in the client's language. The saved key stays `Expedition`.
- [x] **One-column window.** Seen in game beside the map; descriptions wrap cleanly and
  every row is readable.
- [ ] **Two-column window.** 872 x 560 standalone. Not yet looked at in game; open it
  from the minimap button or `/questprism` and check the left column clears the bar.
- [x] **Control smoke test.** The map tab, its menu, headers, bar and heading were
  worked through in game during the beta3 session; the window's radios and preset
  dropdown were seen working. Escape closing the window was not separately reported.

## Closable from here

- [x] **Stale research notes.** `docs/world-quests.md` ended with a beta2 status section
  that predated the row rename and the polarity change. Rewritten for beta3.
- [x] **Locale hygiene.** No key defined in `Locales/enUS.lua` is unread by code, and no
  key read by code is missing (the second half is enforced by a test).
- [x] **Doc consistency.** README, the CurseForge description and the changelog all
  describe the World Quests row rather than the old block switch.

## Open decisions

Both were settled the same way: make the behaviour a rule you can state in one sentence,
and put it behind an option that is off by default.

- [x] **Super-tracked world quest while blocked.** New option, *Waypoint arrow* under
  "Where it applies": while World Quests is unticked and the option is on, a world quest
  is never super-tracked. Off by default, so a waypoint you set yourself survives the
  block. Enforced on `SUPER_TRACKING_CHANGED` and on every refresh, so it holds whether
  the block, the option or the tracked quest changed last. A followed guide outranks it:
  Zygor and RestedXP draw their own arrow (adapter flag `ownsWaypoint`), so QuestPrism
  touches no waypoint state while one of them is followed. BtWQuests needs nothing from
  us: it already has its own TomTom setting and waypoint call.
- [x] **No fallback for guide source and scope.** New option, *Source and scope here too*
  in the Guide section: the window shows the same source, scope and next-steps controls
  as the map tab. Off by default. When on, the three rows are always present and grey out
  while no guide is followed, so nothing appears or disappears as you tick things, and
  the controls stay reachable if the map tab is ever unavailable.

## Accepted limitations

- [x] **Minimap world quest icons.** Drawn by the engine as points of interest, with no
  world-quest-specific filter. Stated in the row description and the tooltip.
- [x] **English only.** `Locales/enUS.lua` is the only locale, as in beta2.

## Release

Everything below the in-game checks is ready; the package is reproducible with
`python .dev-tests/build_release.py`.

- [x] **Version.** TOC reads `1.0.0-beta3`, interface `120100`.
- [x] **Release notes.** The beta3 changelog entry is grouped by area and reads as
  release notes rather than a commit log.
- [x] **Store description.** `docs/curseforge-description.md` matches the beta3 UI.
- [x] **Package.** 30 files, ~195 KB, one `QuestPrism/` folder, no dev files, every TOC
  entry present.
- [x] **Upload.** Done 2026-09-06 by pushing tag `v1.0.0-beta3`: the release workflow
  packaged it, uploaded it to CurseForge project 1683615 as a beta file for 12.1.0, and
  cut a GitHub prerelease with the zip attached. Tags follow the existing `v` prefix.
  The two older tags on this machine point at the pre-reset history and must never be
  pushed; push tags by name, never `--tags`.
