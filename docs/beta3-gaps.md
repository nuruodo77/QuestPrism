# 1.0.0-beta3 gap list

Everything still open after the settings redesign, the two-column window, the popup
removal and the code review. Ticked items are closed; each says how it was closed or
what it is waiting on.

## Needs the game (cannot be checked from the repo)

- [ ] **World Quests row icon.** `worldquest-questmarker-questbang` in `UI/Panel.lua` is
  the only atlas added this session and is unverified; no other installed addon uses it.
  If the row shows no icon, that is the cause. The other eight atlases shipped in beta1
  and beta2, so they are verified by use.
- [x] **Expedition name.** Resolved from Blizzard's own Map Legend source: the pins the
  addon filed under "Expedition" are the legend's **Event** entry (`MAP_LEGEND_EVENT`,
  "Limited Time Activities"). The row now takes its name, description and horn icon from
  that entry at runtime, in the client's language. The saved key stays `Expedition`.
- [ ] **One-column window.** 460 x 800 beside the map. Check that the Map Legend
  descriptions wrap the way the mock predicted and that the scroll bar is not permanently
  needed.
- [ ] **Two-column window.** 872 x 560 standalone. Check the left column clears the
  scroll bar and the window fits at your UI scale.
- [ ] **Control smoke test.** Radios, the preset dropdown and its menu, the Save as box,
  the map tab stepper, and Escape closing the window.

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
- [ ] **Upload.** After the in-game checks pass: rebuild the zip if anything changed,
  tag the commit, and upload to CurseForge project 1683615 as a beta file, pasting the
  beta3 changelog section as the release notes.
