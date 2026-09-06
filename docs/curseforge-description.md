**QuestPrism gives you a clear view of your quests.** It filters the world map, the minimap and the objective tracker by quest type, and can narrow everything down to the quests of the guide you are following in Zygor, RestedXP or BtWQuests.

## Filter by quest type

Turn quest pins on or off per type: Campaign, Important, Legendary, Meta, Repeatable, Local Story and Events, named as the Map Legend names them.

Every row works the same way: ticked means visible. Untick **World Quests** and their pins disappear from the world map and the flight map, the World Quests section leaves the objective tracker, the "World Quest" banner no longer plays when you walk into one, and the "World Quest Complete" alerts stop. (Minimap icons are drawn by the game itself and cannot be filtered by addons.)

Trivial quests use the game's own tracking filter, so that toggle cleans up the minimap as well.

Click a quest type's name to see only that type, click it again to restore. Four presets are built in (Leveling, Campaign only, Endgame, Weekly chores) and you can save your own; presets are shared by all your characters, and the filters themselves can be shared too.

## Follow your guide

Tick **Follow my guide** and QuestPrism shows only the quests from the guide you are running:

- your active **Zygor** or **RestedXP** guide, or
- the **BtWQuests** chain you last opened.

Pick the scope on the QuestPrism map tab: the current step, the current step plus the next few, or the whole guide. The map updates the moment your guide advances.

## The objective tracker follows

Your type filters and the guide filter also apply to the quest list in the objective tracker. Quests are only hidden from the list, never untracked.

## A QuestPrism tab on the world map

Next to Quests, Events and Map Legend you get a QuestPrism tab: the guide's controls at the top (Follow my guide, the source when more than one guide addon is loaded, and the Step / Next / Guide scope buttons), then the guide's quests in guide order: **in your log** (with objectives and turn-in state), **to pick up**, and how many are already done. Click a quest to open its details, right-click to track it. Blizzard's own quest list is left untouched.

## Everything else

- **Dim instead of hide** if you prefer to keep filtered pins faintly visible.
- A hidden-pin counter, so you always know the filter is doing something.
- Right-click the map or minimap button for a **quick menu**.
- Two **keybindings**: toggle the window, toggle "Follow my guide".
- Native look: the settings window and all controls use Blizzard's own UI templates.

## How to open it

Left-click the QuestPrism button at the top right of the world map, or the minimap button, or type `/questprism` (also `/lens`). Right-click either button for the quick menu.

## Good to know

QuestPrism reads three parts of Blizzard's interface that aren't public API: the world map's pin pools, the objective tracker's quest modules, and the quest-log side panel. Each is guarded so that a Blizzard change disables the feature rather than breaking your UI, but those are the places most likely to need an update after a major patch. If something looks off after a patch, a BugSack report in the comments is the fastest way to get it fixed.

Guide integration reads the running guide addon's data in memory only. Nothing from Zygor, RestedXP or BtWQuests is stored or redistributed.
