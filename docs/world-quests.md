# World quests: every surface and how QuestPrism can touch it

Research notes against Blizzard's live UI source (Gethe/wow-ui-source, `live` branch,
read 2026-09-05). File paths are under `Interface/AddOns/`. "Hook" means what an addon
can do there; "QuestPrism" says what the addon does today.

A world quest is a *task quest* (`C_QuestLog.IsQuestTask`) that also passes
`C_QuestLog.IsWorldQuest`. Bonus objectives are tasks that are not world quests.
Bounties (emissaries, callings) are quests that other world quests count toward.

## 1. World map pins

- Source: `Blizzard_SharedMapDataProviders/WorldQuestDataProvider.lua` (base) and
  `Blizzard_WorldMap/WM_WorldQuestDataProvider.lua` (world map subclass).
- Pin template: `WorldMap_WorldQuestPinTemplate`, mixin `WorldMap_WorldQuestPinMixin`
  (extends `WorldQuestPinMixin` extends `MapCanvasPinMixin`). World Quest List replaces
  it with `WQL_WorldQuestPinTemplate`.
- Pin fields set by the provider: `questID`, `worldQuest = true`, `info`, `dataProvider`,
  `tagInfo`, `worldQuestType`, `numObjectives`, `iconWidgetSet`,
  `shouldShowObjectivesAsStatusBar`.
- Blizzard's own visibility decision, `ShouldShowQuest(info)`:
  - CVar `questPOIWQ` must be on (this is the "World Quests" checkbox in the map's
    tracking menu);
  - the quest must not be *suppressed* (`IsQuestSuppressed`, 60 s after interacting);
  - reward filters must pass (`WorldMap_DoesWorldQuestInfoPassFilters`, see section 3);
  - when a quest is *focused* (`SetFocusedQuestID` callback, bounty hover), only quests
    matching `ShouldSupertrackHighlightInfo` show;
  - the world map subclass also requires `info.mapID == current map`.
- Refresh triggers: `SUPER_TRACKING_CHANGED`, `QUEST_LOG_UPDATE`, a 0.5 s ticker while
  the map is shown, callbacks `SetFocusedQuestID` / `ClearFocusedQuestID` / `SetBounty` /
  `HighlightMapPins.WorldQuests`.
- Hooks: post-hook the provider instance's `RefreshAllData` (found in
  `WorldMapFrame.dataProviders`), enumerate `WorldMapFrame.pinPools[template]`, hide or
  dim pins. Never touch a pin from inside `AcquirePin` (see section 15).
- QuestPrism: `Hooks/WorldMap.lua` treats both templates as filterable; `Core/Filter.lua`
  types them `WorldQuest`; `Core/Rules.lua` hides them only under the world quest block.
  A world quest is typed `WorldQuest` whatever its timer: `Filter.IsExpeditionQuest`
  answers false for any world quest before it looks at the countdown. (Until beta3 the
  timer was checked first, and since every world quest has one, every world quest was
  typed `Expedition`; the Expedition checkbox governed them and the World Quests row
  governed nothing.)
- Alternative lever: set the CVar `questPOIWQ` to 0. That is Blizzard's own switch and
  taint-free, but it is account-visible in the map's tracking menu and also affects the
  flight map summary. Worth considering as the *primary* map lever for the block.

## 2. Flight map pins

- Source: `Blizzard_FlightMap/FM_WorldQuestDataProvider.lua`; template
  `FlightMap_WorldQuestPinTemplate`, mixin `FlightMap_WorldQuestPinMixin`.
- Same base filters as section 1 (`questPOIWQ`, reward filters). Watched quests draw at
  full alpha, others use the flight map's alpha limits.
- `FM_ZoneSummaryDataProvider.lua` counts world quests per zone with
  `WorldMap_DoesWorldQuestInfoPassFilters` for the zone summary tooltip.
- Hooks: `FlightMapFrame` is load-on-demand (`Blizzard_FlightMap`); hook its providers on
  `ADDON_LOADED` for that addon, same technique as the world map.
- QuestPrism: covered by the `questPOIWQ` lever (section 3).

## 3. Map tracking menu filters (CVars)

- Source: `Blizzard_WorldMap/Blizzard_WorldMapTemplates.lua`
  (`WorldMapTrackingOptionsButtonMixin:SetupMenu`) and
  `WorldMap_DoesWorldQuestInfoPassFilters` in
  `Blizzard_UIPanels_Game/Mainline/WorldMapFrame.lua`.
- CVars: `questPOIWQ` (master "World Quests"), `worldQuestFilterGold`,
  `worldQuestFilterResources`, `worldQuestFilterArtifactPower`,
  `worldQuestFilterProfessionMaterials`, `worldQuestFilterEquipment`,
  `worldQuestFilterReputation`, `worldQuestFilterAnima`, `showTamersWQ`,
  `dragonRidingRacesFilterWQ`, `primaryProfessionsFilter`, `secondaryProfessionsFilter`.
- A change calls `WorldMapFrame:RefreshAllDataProviders()`.
- Hooks: `C_CVar.SetCVar` from an addon is allowed for these (not protected). Toggling
  `questPOIWQ` hides world quest pins on both maps without touching any frame.
- QuestPrism: `Hooks/WorldQuests.lua` sets `questPOIWQ` to 0 while blocked, remembers in
  `QuestPrismDB.worldQuestPinsWereShown` that it was on, and restores it when the block is
  lifted; re-asserted on every refresh and at login.

## 4. Minimap

- Source: `Blizzard_Minimap/Mainline/Minimap.lua`,
  `Blizzard_APIDocumentationGenerated/MinimapConstantsDocumentation.lua`.
- `Enum.MinimapTrackingFilter` has `QuestPOIs` (65536), `TrivialQuests` (1024),
  `AccountCompletedQuests` (2097152), `POI` (8192). Blizzard's menu marks `QuestPOIs`
  and `TaxiNode` as *always on*: they are never listed and cannot be turned off from the
  menu. Whether `C_Minimap.SetTracking` on the `QuestPOIs` index is honoured by the
  engine is untested; if it is, it would also remove normal quest markers, not only
  world quests.
- Conclusion: no world-quest-specific lever on the minimap. World quest icons there are
  engine POIs.
- QuestPrism: documents the limitation in the option's tooltip.

## 5. Objective tracker: the World Quests module

- Source: `Blizzard_ObjectiveTracker/Blizzard_WorldQuestObjectiveTracker.lua`
  (`WorldQuestObjectiveTrackerMixin = CreateFromMixins(BonusObjectiveTrackerMixin,
  settings)`, `settings.showWorldQuests = true`, header `TRACKER_HEADER_WORLD_QUESTS`),
  module mechanics in `Blizzard_ObjectiveTrackerModule.lua`, container in
  `Blizzard_ObjectiveTrackerContainer.lua`, registration in
  `Blizzard_ObjectiveTrackerManager.lua` (global frame `WorldQuestObjectiveTracker`).
- `LayoutContents` adds (a) world quests in the local area
  (`GetTasksTable()` filtered by `QuestUtils_IsQuestWorldQuest` and not already
  watched) and (b) watched world quests (`C_QuestLog.GetNumWorldQuestWatches` /
  `GetQuestIDForWorldQuestWatchIndex`, sorted). A module with no blocks ends in state
  `NoObjectives`, is not displayable, and `EndLayout` hides the whole frame, header
  included.
- Events: `QUEST_TURNED_IN`, `QUEST_LOG_UPDATE`, `QUEST_WATCH_LIST_CHANGED`,
  `QUEST_ACCEPTED` (filtered to trackable world quests), `SUPER_TRACKING_CHANGED`,
  `SUPER_TRACKING_PATH_UPDATED`.
- Hooks: replace `LayoutContents` on the instance; `MarkDirty()` to re-layout.
- QuestPrism: `Hooks/WorldQuests.lua` does exactly that. `/questprism tracker` confirms
  the module is hidden while blocked.

## 6. Objective tracker: the "World Quest" top banner (open issue candidate)

- Source: `Blizzard_ObjectiveTracker/Blizzard_BonusObjectiveTracker.lua`,
  `ObjectiveTrackerTopBannerMixin`, frame `ObjectiveTrackerTopBannerFrame`, driven by
  `Blizzard_FrameXML/TopBannerManager.lua`.
- When a world quest is auto-accepted (walking into its area), the World Quests module's
  `OnEvent(QUEST_ACCEPTED)` calls `OnQuestAccepted(questID)` (inherited from the bonus
  mixin), which calls `ObjectiveTrackerTopBannerFrame:DisplayForQuest(questID, module)`.
  The banner shows the quest title with the subtitle `WORLD_QUEST_BANNER` ("World
  Quest"), plays `SOUNDKIT.UI_WORLDQUEST_START`, then slides into the tracker.
  Bonus objectives use the same banner with `BONUS_OBJECTIVE_BANNER`.
- This is independent of `LayoutContents`, so the current block does not stop it. It is
  the most likely explanation for a "World Quests" title that stays visible while the
  module itself is hidden.
- Hooks: wrap `ObjectiveTrackerTopBannerFrame.DisplayForQuest` and return `false` when
  `module.showWorldQuests` and the block is on (the caller then just marks the module
  dirty). `TopBannerManager` has no filtering API of its own; wrapping `DisplayForQuest`
  is the cleanest point. No protected calls are involved.
- QuestPrism: `Hooks/WorldQuests.lua` wraps `DisplayForQuest` and refuses world quest
  banners while blocked (module `showWorldQuests`, or quest ID is a world quest).

## 7. Objective tracker: rewards toast

- Source: `BonusObjectiveTrackerMixin:OnQuestTurnedIn` / `ShowRewardsToast`,
  `ObjectiveTrackerManager:ShowRewardsToast` (pool of
  `ObjectiveTrackerRewardsToastTemplate` frames parented to `UIParent`).
- For the World Quests module (`showWorldQuests = true`) turn-in plays the block's
  `RemoveAnim` instead of the toast; the toast is used by the Bonus Objectives module.
  So world quests do not produce this toast; their completion goes through the alert
  system (section 8).
- Hooks: wrap `ObjectiveTrackerManager.ShowRewardsToast` if bonus objectives are ever
  in scope.
- QuestPrism: out of scope (bonus objectives are not world quests).

## 8. Alerts (top-of-screen toasts)

- Source: `Blizzard_FrameXML/Mainline/AlertFrameSystems.lua`, `AlertFrames.lua`.
- `WorldQuestCompleteAlertSystem = AlertFrame:AddQueuedAlertFrameSubSystem(
  "WorldQuestCompleteAlertFrameTemplate", WorldQuestCompleteAlertFrame_SetUp,
  WorldQuestCompleteAlertFrame_Coalesce)`; fed from `QUEST_TURNED_IN` for world quests
  and `WORLD_QUEST_COMPLETED_BY_SPELL`.
- Related: `InvasionAlertSystem` (Legion invasions, "ScenarioLegionInvasionAlertFrameTemplate").
- Suppression API: `AlertFrameQueueMixin:SetCanShowMoreConditionFunc(fn)` stores the
  function in `self.canShowMoreConditionFunc`; `CanShowMore` returns false when it
  answers false, and `AddAlert` then queues instead of showing (the queue drains when
  the condition allows again). There is no API to disable or remove a sub system.
- QuestPrism: `Hooks/WorldQuests.lua` wraps the system's `AddAlert` to return true
  without showing or queueing while blocked, so no backlog builds up.

## 9. Quest log side panel (world map)

- Source: `Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua`.
- The quest log has campaign, covenant-callings, zone and story headers. It has no world
  quest section and does not list tracked world quests.
- QuestPrism: nothing to do here. The QuestPrism guide tab lists guide quests only.

## 10. Tooltips

- Source: `TaskPOI_OnEnter` / `TaskPOI_OnLeave` in
  `Blizzard_UIPanels_Game/Mainline/WorldMapFrame.lua`, using `GameTooltip` with
  `GameTooltip_AddQuest`, `GameTooltip_AddQuestRewardsToTooltip`,
  `GameTooltip_AddQuestTimeToTooltip`. Pins call it from `WorldQuestPinMixin:OnEnter`.
- Hooks: hidden pins never receive mouse events, so hiding the pin removes the tooltip.
  To annotate tooltips instead, post-hook `TaskPOI_OnEnter`.
- QuestPrism: covered by pin hiding.

## 11. Super tracking and the waypoint arrow

- Source: `Blizzard_FrameXMLUtil/Mainline/Blizzard_QuestSuperTracking.lua`,
  `QuestUtil.CheckAutoSuperTrackQuest` / `AllowAutoSuperTrackQuest` in `QuestUtils.lua`.
- Auto super-tracking on accept skips world quests and bonus objectives unless forced,
  so a world quest only gets the waypoint arrow when the player clicks it (map pin,
  tracker block) or when `SUPER_TRACKING_CHANGED` comes from elsewhere.
- APIs: `C_SuperTrack.SetSuperTrackedQuestID`, `GetSuperTrackedQuestID`,
  `IsSuperTrackingAnything`, `IsSuperTrackingQuest`. Not protected.
- Hooks: on `SUPER_TRACKING_CHANGED`, if the block is on and the super-tracked quest is a
  world quest, clear it (`C_SuperTrack.ClearAllSuperTracked` or set to 0).
- QuestPrism: optional since beta3. `Hooks/WorldQuests.lua` enforces one rule -- while
  blocked AND `clearWorldQuestWaypoint` is on, a world quest is never super-tracked --
  from `SUPER_TRACKING_CHANGED` and from `Refresh`. Off by default, so a waypoint the
  player set survives the block.
- A followed guide outranks the rule. Adapters carry `ownsWaypoint`; Zygor (its Arrows
  module) and RestedXP (`RXPG_ARROW`) set it, so while one of them is followed
  `Sources.GuideOwnsWaypoint()` is true and QuestPrism does not touch waypoint state at
  all. BtWQuests does not set it: it has no arrow, and sets a waypoint only when the
  player clicks one in its own window, through the global `BtWQuests_AddWaypoint`, which
  already honours that addon's "Use TomTom waypoints" setting. There is nothing for
  QuestPrism to add there; delegating to that global is the way in if the guide tab ever
  offers a "show me the way" action.

## 12. Watch list APIs and events

- `C_QuestLog.AddWorldQuestWatch(questID, watchType)` (Automatic or Manual),
  `RemoveWorldQuestWatch(questID)`, `GetNumWorldQuestWatches()`,
  `GetQuestIDForWorldQuestWatchIndex(i)`, `GetQuestWatchType(questID)`. None are
  protected (documentation marks them "Secure", meaning callable, not restricted).
- Events: `QUEST_WATCH_LIST_CHANGED(questID, added)`, `QUEST_WATCH_UPDATE(questID)`,
  `TASK_PROGRESS_UPDATE`, `WORLD_QUEST_COMPLETED_BY_SPELL(questID)`, `QUEST_ACCEPTED`
  (fires for auto-accepted world quests when entering their area), `QUEST_TURNED_IN`.
- Hooks: the client auto-adds an *Automatic* watch when the player enters a world quest
  area; an addon can remove it on `QUEST_WATCH_LIST_CHANGED`. Not needed while the
  module is emptied, and it would fight the user's manual tracking.
- QuestPrism: not used.

## 13. Detection and classification

- `C_QuestLog.IsWorldQuest(questID)`, `C_QuestLog.IsQuestTask(questID)`,
  `C_QuestLog.IsQuestBounty(questID)`, `QuestUtil.IsQuestTrackableTask(questID)`
  (task and not bounty), `QuestUtils_IsQuestBonusObjective` (task and not world quest).
- `Enum.QuestClassification.WorldQuest` on quest-offer pins and tracker entries.
- `C_TaskQuest` (documentation file not located in the mirror; names from memory,
  verify in game): `GetQuestsOnMap(uiMapID)`, `GetQuestInfoByQuestID`,
  `GetQuestTimeLeftSeconds/Minutes`, `IsActive`, `GetQuestLocation`, `GetQuestZoneID`,
  `DoesMapShowTaskQuestObjectives`, `GetThreatQuests`, `RequestPreloadRewardData`.
- Tag info: `C_QuestLog.GetQuestTagInfo(questID)` returns `worldQuestType`, `quality`
  (`Enum.WorldQuestQuality.Common/Rare/Epic`), `isElite`, `tradeskillLineID`; atlas via
  `QuestUtils_GetQuestTagAtlas`.
- QuestPrism: `Filter.IsWorldQuest` (by ID) and the `WorldQuest` classification/type.

## 14. Bounties, emissaries, callings

- `C_QuestLog.GetBountiesForMapID(uiMapID)`, `GetBountySetInfoForMapID`,
  `IsQuestCriteriaForBounty(questID, bountyQuestID)`. The map's bounty board
  (`WorldMapBountyBoardMixin`, `Blizzard_WorldMap`) sets the provider's bounty and the
  focused quest, which changes which world quest pins highlight or show.
- Covenant callings live in `Blizzard_CovenantCallings` and the quest log's callings
  header.
- QuestPrism: out of scope for the block; bounty quests themselves are regular quests.

## 15. Taint rules learned the hard way

- `Button:SetPassThroughButtons()` is protected and is called by
  `MapCanvasMixin:AcquirePin` right after `pin:OnAcquired(...)`. Hiding or otherwise
  touching a pin from an `OnAcquired` hook gets the addon blocked
  (`ADDON_ACTION_BLOCKED`). Filter after the provider's `RefreshAllData` instead.
- Replacing methods on Blizzard frames (`LayoutContents`, `ShouldDisplayQuest`,
  `DisplayForQuest`) is fine as long as no protected call follows in the same secure
  execution. The tracker layout and banners make none.
- `Frame:Hide()` from insecure code taints the frame's shown state; secure code that
  later reads `IsShown()` on that frame runs tainted from there on. Prefer CVars or
  Blizzard's own switches where they exist (`questPOIWQ` for map pins).

## Status (1.0.0-beta3)

Sections 1 to 3, 5, 6 and 8 are implemented in `Hooks/WorldQuests.lua` and
`Hooks/WorldMap.lua`. The blocking mechanism is unchanged since beta2; what changed in
beta3 is the control in front of it.

- The setting is still `HideWorldQuests` and still means "blocked", but no surface
  presents it that way any more. The settings window shows a **World Quests** row as the
  ninth entry of "Quests to show", read and written inverted, so a ticked row means the
  pins and the tracker section are visible, like every other row in that list. The quick
  menu carries the same row as the last entry of its Quest types submenu.
- "All" / "Show all" lifts the block (`Settings.Reset`), and since beta3 "None" /
  "Hide all" (`Settings.HideAll`) and solo mode set it, so the list's bulk actions cover
  all nine rows symmetrically. Solo snapshots and restores it with the type toggles.
- The row's description and the option tooltip carry the minimap limitation from
  section 4.

Section 11 (the waypoint arrow) is implemented as an opt-in rule; see that section. With
its option off, which is the default, a world quest that is already super-tracked when the
block goes on keeps its waypoint arrow.
