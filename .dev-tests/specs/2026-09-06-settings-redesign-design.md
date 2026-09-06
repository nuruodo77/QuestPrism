# Settings redesign — design (1.0.0-beta3)

Approved on the design canvas ("QuestPrism Settings Window") and in chat, 2026-09-06
("Your suggestions seem fair" / "build the changes"). One rule drives the window: a
ticked row is visible. Everything guide-related gets one home, the map tab.

## Settings window (`UI/Panel.lua`)

Same `ButtonFrameTemplate` window, 460 wide. The content scrolls as today; the sections
are plain stacked frames (no collapsing, no saved collapse state).

Top rows:
- **Preset** — `WowStyle1DropdownTemplate` whose menu has a "Built in" title with one
  radio per built-in preset, a divider, a "Yours" title with one radio per saved preset
  (or none), a divider, and a `Delete "<name>"` button that is disabled unless a saved
  (non built-in) preset is active. Choosing a radio applies the preset. The dropdown text
  is the active preset's name, with " (edited)" appended when any filter row differs from
  it, or "No preset". A **Save as…** button reveals the inline `InputBoxTemplate` in the
  same row (Enter saves, Escape cancels; overwrite still confirms through the popup).
- **Filters** — two `UIRadioButtonTemplate` buttons: *This character* / *All characters*
  (the account-wide switch, moved up because it changes where every row below stores).

Sections:
1. **Quests to show** — header with small *All* / *None* buttons on the right. Nine rows,
   each an 18px atlas icon, the name (a button: click = solo, click again = restore; the
   soloed row shows " (solo)"), the official one-line description in
   `GameFontDisableSmall`, and a `MinimalCheckboxTemplate` on the right (right-click =
   solo, as today). Rows in order: Campaign, Important, Legendary, Meta, Repeatable,
   Local Story, Expedition, Trivial Quests, World Quests. The World Quests row reads and
   writes the existing `HideWorldQuests` key inverted (ticked = shown); it has no solo.
   *All* = `Settings.Reset()` (also lifts the world quest block); *None* unticks the eight
   type rows only.
2. **Where it applies** — *Hidden pins on the world map*: two radios *Hide* / *Dim*
   (`dimFiltered`). *Objective tracker*: checkbox (`trackerFilter`) with the description
   "Quests are hidden from the list, never untracked."
3. **Guide** — header with a *Show on map* button on the right (opens the map tab). One
   row: *Follow my guide* checkbox (`Sources.SetFollowing`) whose description is the
   sources status text followed by "Source and scope are on the QuestPrism map tab."
4. **Addon** — *Minimap button* checkbox (ticked = shown; inverts `minimap.hide`) and
   *Debug output in chat* checkbox.

Footer status line unchanged (hidden count + following state). Escape closes the window
(already in `UISpecialFrames`).

## Names and descriptions (`Locales/enUS.lua`)

Map Legend names and descriptions verbatim (Blizzard, The War Within UI post):
Campaign "Quests that continue the main story." · Important "Quests that unlock important
features and rewards or teach you about the major mechanics." · Legendary "Quests that
give legendary rewards." · Meta "Time gated quests that give valuable end game rewards." ·
Repeatable "Time gated quests." · Local Story "Quests that explore local cultures and
side adventures." Addon's own: Expedition "Timed zone events with a countdown on the
map." · Trivial Quests "Low-level quests. Uses the game's tracking filter, so it applies
to the minimap too." · World Quests "Also their tracker section, the entry banner and the
completion alerts." Descriptions live in `QuestPrism.Panel.QUEST_TYPES[i].desc` next to
the existing tooltip so every surface can reuse them.

## Built-in presets (`Core/Settings.lua`)

Four read-only presets, listed before saved ones everywhere presets appear:

| | Campaign | Important | Legendary | Meta | Repeatable | Local Story | Expedition | Trivial | World Quests |
|---|---|---|---|---|---|---|---|---|---|
| Leveling | x | x | | | | x | | | |
| Campaign only | x | x | x | | | | | | |
| Endgame | x | x | x | x | x | | x | | x |
| Weekly chores | | | | x | x | | x | | x |

- `ListBuiltInPresetNames()` (fixed order), `IsBuiltInPreset(name)`,
  `GetPresetSnapshot(name)` (built-in or saved; `nil` if unknown).
- `LoadPreset(name)` applies built-ins too and records `activePreset` in the filter store.
- `SavePreset` refuses a built-in name (case-insensitive); `DeletePreset` refuses built-ins.
- `IsActivePresetModified()` compares the active preset's snapshot with the current scoped
  values. Changing a filter no longer clears `activePreset`.
- `IsCollapsed` / `SetCollapsed` go away; `Initialize` drops the stale `collapsed` table.

## Map tab (`UI/GuideTab.lua`) — the guide's home

Header, top to bottom:
1. *Follow my guide* `MinimalCheckboxTemplate` + label on the left, gear on the right
   (opens the window anchored to the map, as today).
2. *Source* label + `WowStyle1DropdownTemplate` (radios from `Sources.AvailableNames()`),
   shown only when more than one guide addon is available.
3. *Scope*: the three existing buttons (Step / Next N / Guide, active one disabled) plus a
   stepper made of two small `UIPanelButtonTemplate` buttons around the number
   (1–10, `guideLookahead`); the stepper is disabled unless the scope is lookahead.
4. Status line (`Sources.GetStatusText()`).

The list starts below the header (height depends on whether the source row is shown).
Empty state: when not following, the text says to tick *Follow my guide* above; the
"Open QuestPrism" button is gone. When following but the scope is empty, the existing
"No quests in the current guide scope." stays.

## Quick menu (`UI/QuickMenu.lua`)

Title · *Follow my guide* checkbox · **Quest types** submenu: the eight type checkboxes
with hidden counts, then *World Quests* (ticked = shown) · **Presets** submenu: radios for
built-in then saved presets (selecting applies) · divider · Show all · Hide all ·
Open QuestPrism. The top-level "Block world quests" entry is removed.

## Escape-menu page (`UI/Options.lua`)

Open button · *Minimap button* (ticked = shown; same `QuestPrism_HideMinimap` variable,
inverted getter/setter) · *Debug output in chat* · *Share filters across all characters*.
The Dim, Tracker and Block world quests checkboxes are removed (they live in the window).

## Buttons and commands

- World map button and minimap launcher tooltips gain a line with the hidden-pin count
  on the current map when it is above zero.
- `/questprism help` lists the commands; other commands unchanged.

## Out of scope

"Next preset" keybinding, section icons, any change to filtering rules or the world quest
block, localisation beyond enUS.

## Tests (`.dev-tests`)

- Settings: built-in list and order, load applies the table above, save/delete refuse
  built-in names, modified detection, `collapsed` dropped on init.
- Smoke: window builds with 13 `MinimalCheckboxTemplate`, 4 `UIRadioButtonTemplate`,
  1 dropdown, 1 input box, no slider; World Quests checkbox inverts `HideWorldQuests`;
  minimap checkbox inverts `hide`; quick menu shape (1 top checkbox, 5 buttons, 9 type
  entries, presets submenu applies); Options registers 3 settings and the minimap one is
  inverted; map tab follow checkbox toggles following, stepper clamps 1–10, source
  dropdown exists; every referenced locale key exists (existing test).
