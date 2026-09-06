# Settings redesign — Implementation Plan (1.0.0-beta3)

> **For agentic workers:** execute inline, all tasks to completion, one review at the end
> (per user CLAUDE.md). TDD for Settings/QuickMenu/Options/GuideTab logic; the Panel
> layout is covered by the smoke test's template counts and setter behaviour.

**Spec:** `.dev-tests/specs/2026-09-06-settings-redesign-design.md`
**Goal:** one polarity (ticked = visible), official names with descriptions, built-in
presets, the guide's controls on the map tab, no duplicated switches on the Escape page.

## Tasks

1. **Locale** (`Locales/enUS.lua`) — add: `TYPE_DESC_*` for the nine rows,
   `QUEST_WORLD_QUESTS` ("World Quests"), `QUEST_TRIVIAL` → "Trivial Quests",
   section titles (`SECTION_SHOW`, `SECTION_APPLIES`, `SECTION_GUIDE`, `SECTION_ADDON`),
   `FILTERS_LABEL`, `SCOPE_THIS_CHARACTER`, `SCOPE_ALL_CHARACTERS`, `PINS_LABEL`,
   `PINS_HIDE`, `PINS_DIM`, `TRACKER_LABEL` ("Objective tracker"), `TRACKER_DESC`,
   `FOLLOW_GUIDE_DESC`, `MINIMAP_BUTTON_LABEL`, `DEBUG_LABEL`, `PRESET_SAVE_AS`,
   `PRESET_BUILTIN`, `PRESET_YOURS`, `PRESET_DELETE_NAMED`, `PRESET_EDITED_SUFFIX`,
   `PRESET_LEVELING`, `PRESET_CAMPAIGN_ONLY`, `PRESET_ENDGAME`, `PRESET_WEEKLY`,
   `MENU_PRESETS`, `GUIDETAB_SOURCE`, `GUIDETAB_NO_SOURCE` reworded (tick above),
   `TOOLTIP_HIDDEN_ON_MAP`, `HELP_*` lines for `/questprism help`. Remove keys that no
   longer have a reader after tasks 2–7 (checked by grep at the end).

2. **Settings** (`Core/Settings.lua`, `test_settings.lua`) — `BUILTIN_PRESETS` (ordered,
   names from locale), `ListBuiltInPresetNames`, `IsBuiltInPreset`, `GetPresetSnapshot`,
   `LoadPreset` for built-ins, `SavePreset`/`DeletePreset` refusals,
   `IsActivePresetModified`, `GetActivePresetName` returning built-ins; drop
   `IsCollapsed`/`SetCollapsed` and clear `QuestPrismCharDB.collapsed` in `Initialize`.
   Tests first: list/order, load table, refusals, modified detection, collapsed dropped.

3. **Quest types table + Panel** (`UI/Panel.lua`, smoke test) — `QUEST_TYPES` gains
   `desc` per entry and a `WorldQuest` pseudo-entry is NOT added (World Quests row is
   built separately, it is not a type toggle). Rebuild the window body per spec: preset
   row (dropdown + Save as + input box), Filters radios, four sections. Remove the
   collapsible section machinery. Keep `Sync`, `UpdateStatus`, `Toggle`, `IsShown`,
   `SetSectionCollapsed` gone. Smoke test updated: template counts, World Quests
   checkbox inversion, minimap checkbox inversion, radio setters, preset dropdown
   `QLRefresh` text with " (edited)".

4. **Quick menu** (`UI/QuickMenu.lua`, smoke test) — remove top-level Block world quests;
   append *World Quests* to the types submenu (inverted); add *Presets* submenu with
   radios (`CreateRadio`); mock gains `CreateRadio` on submenus. Tests: shape, applying a
   preset from the menu, World Quests entry flips `HideWorldQuests`.

5. **Escape page** (`UI/Options.lua`, smoke test) — remove Dim/Tracker/HideWorldQuests
   proxies; `QuestPrism_HideMinimap` label "Minimap button", getter `not IsHidden()`,
   setter `SetHidden(not value)`. Test the inversion.

6. **Map tab** (`UI/GuideTab.lua`, smoke + guidetab tests) — header: follow checkbox +
   gear; source row (dropdown, shown only when >1 available); scope buttons + stepper;
   status. Dynamic header height → scroll anchored below it. Empty state text without the
   Open button. Expose `GetFollowCheckbox`, `GetStepper` for tests. Tests: checkbox
   toggles following (Zygor stub), stepper clamps 1–10 and refreshes, source dropdown
   created, `Sync` from the window updates the tab header.

7. **Buttons, slash, docs** — hidden-count tooltip line on both buttons;
   `/questprism help`; README, curseforge blurb, CHANGELOG (beta3), TOC version.

8. **Verification** — `python .dev-tests/run_tests.py` green; grep for unused locale
   keys; `git diff --stat`; single review at the end.
