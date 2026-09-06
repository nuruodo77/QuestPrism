# QuestPrism

A clear view of your quests. QuestPrism filters the world map, the minimap and the
objective tracker by quest type, and can narrow everything down to the quests of
the guide you are following in Zygor, RestedXP or BtWQuests.

World of Warcraft Retail (12.1). English only.

## What it does

- **Quest types.** Show or hide Campaign, Important, Legendary, Meta, Repeatable,
  Local Story and Expedition pins on the world map. Trivial quests use the game's
  own tracking filter, so that one applies to the minimap too.
- **World Quests.** Untick the World Quests row and everything world quest related
  goes: the pins on the world map and the flight map, the World Quests section of
  the objective tracker, the "World Quest" entry banner and the "World Quest
  Complete" alerts. (Minimap icons are drawn by the game and cannot be filtered
  by addons.)
- **Follow my guide.** Show only the quests from your active Zygor or RestedXP
  guide, or from the BtWQuests chain you last opened. Choose the scope: the
  current step, the current step plus the next few, or the whole guide.
- **Objective tracker.** The same type and guide filters apply to the tracker's
  quest list. Quests are only hidden from the list, never untracked.
- **QuestPrism tab on the world map.** Beside Quests, Events and Map Legend: the
  guide's controls (follow, source, scope) and its quests in guide order, split
  into "in your log", "to pick up" and completed. Click to open a quest,
  right-click to track it.
- **Presets.** Four built in (Leveling, Campaign only, Endgame, Weekly chores) plus
  your own, shared across characters; the filters themselves can be shared too.
- **Dim instead of hide**, a hidden-pin counter, a right-click quick menu on the
  map and minimap buttons, and two keybindings.
- Two opt-in extras: stop the waypoint arrow pointing at a hidden world quest, and
  show the guide's source and scope in the window as well as on the map tab.

## Using it

- Left-click the QuestPrism button on the world map (or the minimap button, or
  `/questprism`, `/lens`) to open the settings window. Right-click for the quick
  menu. `/questprism help` lists the commands. From the map the window is one tall
  column beside the map; opened any other way it is two columns wide.
- Every row in the window works the same way: ticked means visible. Click a quest
  type's name to see only that type; click again to restore.
- Pick a preset from the dropdown to apply it. Leveling, Campaign only, Endgame and
  Weekly chores are built in; "Save as..." stores your own.
- Tick **Follow my guide** in the window or on the QuestPrism map tab. The tab holds
  the source dropdown (when more than one guide addon is loaded) and the scope
  buttons (Step / Next N / Guide).
- Keybindings: **Toggle the QuestPrism window** and **Toggle "Follow my guide"**,
  under QuestPrism in the game's Keybindings screen.

## Compatibility notes

QuestPrism reads three parts of Blizzard's UI that are not public API: the world
map's pin pools, the objective tracker's quest modules, and the quest-log side
panel's display modes. Each is guarded so that a change on Blizzard's side
disables the feature rather than breaking the game UI, but these are the places
to look first after a major patch.

Guide integration reads the running guide addon's in-memory data only; nothing
is stored or redistributed.

## Development

Logic tests run outside the game under Lua 5.1 with a small WoW API mock:

    pip install lupa
    python .dev-tests/run_tests.py

See `.dev-tests/README.md`. The `.dev-tests` folder is excluded from release
packages by `.pkgmeta`.

## License

MIT for QuestPrism's own code (see LICENSE). Embedded libraries keep their own
licenses.
