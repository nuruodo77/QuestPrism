# QuestPrism improvement plan (approved via suggestion list, 2026-09-05)

Constraints: WoW Retail 12.1 (Interface 120100). No git repo. No in-game test runner;
logic tests run under Lua 5.1 (lupa) with a small WoW API mock in `scratchpad/tests/`.
Syntax-check every edited Lua file with lupa lua51 `loadstring`.

## Phase 1 — refresh path (Hooks/WorldMap.lua, Core/Filter.lua)
1. Hide-only filtering: track pins QuestPrism hid in a weak-keyed table; only Show a pin
   QuestPrism itself hid. Never Show a pin Blizzard hid.
2. Skip released pins: enumerate `WorldMapFrame.pinPools[*]:EnumerateActive()` when
   available; fallback to canvas children with `pinTemplate ~= nil`.
3. Debounce: single pending C_Timer per refresh source (AcquirePin/RefreshAllData/events).
4. StartScan: guard so the hook is installed once; repeat calls only print status.
5. Debug log: print each unknown template once per session.
6. Explicit guard for `Enum.QuestTag.Meta` / `.Legendary` being absent.

## Phase 2 — settings (Core/Settings.lua, UI/Panel.lua, locales)
7. Account-wide filters toggle (`QuestPrismDB.useAccountFilters`, `QuestPrismDB.filters`):
   Settings.Get/Set route the 13 filter keys to the account table when enabled;
   on first enable, seed account table from current character. Checkbox in panel.

## Phase 3 — UI (UI/MinimapButton.lua, new UI/Options.lua, libs, toc)
8. LibDBIcon minimap button: embed CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
   (copied from MidnightRoutine, current versions). Store position in
   `QuestPrismCharDB.minimap`; migrate `minimapAngle` -> `minimapPos`. Register compartment.
   Keep left-click = panel, right-click = show all.
9. Blizzard Settings category "QuestPrism": button to open panel, checkbox for account-wide
   filters, checkbox for debug, checkbox to hide minimap button.

## Phase 4 — misc (UI/ChangelogPopup.lua, toc)
10. Changelog version read from TOC metadata via C_AddOns.GetAddOnMetadata.
11. Bump Version to 1.6.0; update changelog text in both locales.

## Verification
- lupa lua51 syntax check of all .lua files
- tests in scratchpad/tests pass (Filter, Settings routing, WorldMap hide/show tracking, debounce)
- XML well-formedness check for toc-included XML
