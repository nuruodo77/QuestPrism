bootCore()

local function fakeWorldQuestModule()
    WorldQuestObjectiveTracker = {
        laidOut = 0,
        LayoutContents = function(self) self.laidOut = self.laidOut + 1 end,
        MarkDirty = function(self) self.dirty = (self.dirty or 0) + 1 end,
    }
end

local function fakeAlertSystem()
    WorldQuestCompleteAlertSystem = {
        added = {},
        AddAlert = function(self, data) table.insert(self.added, data); return true end,
    }
end

local function fakeBanner()
    ObjectiveTrackerTopBannerFrame = {
        shown = {},
        DisplayForQuest = function(self, questID, module) table.insert(self.shown, questID); return true end,
    }
end

local function reset()
    fakeWorldQuestModule(); fakeAlertSystem(); fakeBanner()
    MOCK.cvars.questPOIWQ = "1"
    QuestPrismDB.worldQuestPinsWereShown = nil
    QuestPrism.Settings.Set("HideWorldQuests", false)
end

test("the World Quests tracker module lays out nothing while blocked and is marked dirty on refresh", function()
    reset()
    QuestPrism.WorldQuests.Initialize()
    WorldQuestObjectiveTracker:LayoutContents()
    assertEq(WorldQuestObjectiveTracker.laidOut, 1, "normal layout when not blocked")
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.WorldMap.Refresh()
    assertTrue((WorldQuestObjectiveTracker.dirty or 0) >= 1, "dirty after toggle")
    WorldQuestObjectiveTracker:LayoutContents()
    assertEq(WorldQuestObjectiveTracker.laidOut, 1, "no layout while blocked")
    QuestPrism.Settings.Set("HideWorldQuests", false)
    QuestPrism.WorldMap.Refresh()
    WorldQuestObjectiveTracker:LayoutContents()
    assertEq(WorldQuestObjectiveTracker.laidOut, 2, "layout resumes")
end)

test("the World Quest Complete alert is swallowed while blocked, never queued, and flows again afterwards", function()
    reset()
    QuestPrism.WorldQuests.Refresh()
    assertEq(WorldQuestCompleteAlertSystem:AddAlert("a"), true)
    assertEq(#WorldQuestCompleteAlertSystem.added, 1, "passes through when not blocked")
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.WorldQuests.Refresh()
    assertEq(WorldQuestCompleteAlertSystem:AddAlert("b"), true, "reports handled")
    assertEq(#WorldQuestCompleteAlertSystem.added, 1, "nothing shown or queued while blocked")
    QuestPrism.Settings.Set("HideWorldQuests", false)
    QuestPrism.WorldQuests.Refresh()
    WorldQuestCompleteAlertSystem:AddAlert("c")
    assertEq(#WorldQuestCompleteAlertSystem.added, 2, "no backlog released, new alerts shown")
    assertEq(WorldQuestCompleteAlertSystem.added[2], "c")
end)

test("the World Quest top banner is refused while blocked; bonus objective banners still play", function()
    reset()
    QuestPrism.WorldQuests.Refresh()
    local worldQuestModule = { showWorldQuests = true }
    local bonusModule = { showWorldQuests = false }
    assertEq(ObjectiveTrackerTopBannerFrame:DisplayForQuest(1, worldQuestModule), true, "plays when not blocked")
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.WorldQuests.Refresh()
    assertEq(ObjectiveTrackerTopBannerFrame:DisplayForQuest(2, worldQuestModule), false, "refused: world quest module")
    MOCK.worldQuests[3] = true
    assertEq(ObjectiveTrackerTopBannerFrame:DisplayForQuest(3, bonusModule), false, "refused: world quest by id")
    MOCK.worldQuests[3] = nil
    assertEq(ObjectiveTrackerTopBannerFrame:DisplayForQuest(4, bonusModule), true, "bonus objective banner untouched")
    assertEq(#ObjectiveTrackerTopBannerFrame.shown, 2, "only 1 and 4 reached Blizzard")
    QuestPrism.Settings.Set("HideWorldQuests", false)
end)

test("the map's own World Quests switch (questPOIWQ) is turned off while blocked and restored afterwards", function()
    reset()
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.WorldQuests.Refresh()
    assertEq(MOCK.cvars.questPOIWQ, "0", "cvar off while blocked")
    assertEq(QuestPrismDB.worldQuestPinsWereShown, true, "remembered that it was on")
    QuestPrism.WorldQuests.Refresh()
    assertEq(MOCK.cvars.questPOIWQ, "0", "stays off on repeated refresh")
    QuestPrism.Settings.Set("HideWorldQuests", false)
    QuestPrism.WorldQuests.Refresh()
    assertEq(MOCK.cvars.questPOIWQ, "1", "restored")
    assertEq(QuestPrismDB.worldQuestPinsWereShown, nil, "nothing left to restore")
end)

test("a player who had world quests off on the map keeps them off when the block is lifted", function()
    reset()
    MOCK.cvars.questPOIWQ = "0"
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.WorldQuests.Refresh()
    assertEq(QuestPrismDB.worldQuestPinsWereShown, nil, "not remembered: was already off")
    QuestPrism.Settings.Set("HideWorldQuests", false)
    QuestPrism.WorldQuests.Refresh()
    assertEq(MOCK.cvars.questPOIWQ, "0", "left as the player had it")
end)

test("Initialize and Refresh are safe without the module, the banner, the alert system or C_CVar", function()
    reset()
    WorldQuestObjectiveTracker = nil; WorldQuestCompleteAlertSystem = nil; ObjectiveTrackerTopBannerFrame = nil
    local saved = C_CVar; C_CVar = nil
    assertTrue(pcall(QuestPrism.WorldQuests.Initialize))
    QuestPrism.Settings.Set("HideWorldQuests", true)
    assertTrue(pcall(QuestPrism.WorldQuests.Refresh))
    QuestPrism.Settings.Set("HideWorldQuests", false)
    C_CVar = saved
end)

test("objects are wrapped only once", function()
    reset()
    QuestPrism.WorldQuests.Initialize()
    local m, a, b = WorldQuestObjectiveTracker.LayoutContents, WorldQuestCompleteAlertSystem.AddAlert, ObjectiveTrackerTopBannerFrame.DisplayForQuest
    QuestPrism.WorldQuests.Refresh()
    assertEq(WorldQuestObjectiveTracker.LayoutContents, m)
    assertEq(WorldQuestCompleteAlertSystem.AddAlert, a)
    assertEq(ObjectiveTrackerTopBannerFrame.DisplayForQuest, b)
end)

test("a module registered on the tracker frame is wrapped by its header text, even under another name", function()
    reset()
    WorldQuestObjectiveTracker = nil
    TRACKER_HEADER_WORLD_QUESTS = "World Quests"
    local renamed = {
        headerText = "World Quests", laidOut = 0,
        GetName = function() return "SomeOtherTracker" end,
        LayoutContents = function(self) self.laidOut = self.laidOut + 1 end,
        MarkDirty = function(self) self.dirty = (self.dirty or 0) + 1 end,
    }
    local other = { headerText = "Quests", GetName = function() return "QuestObjectiveTracker" end, LayoutContents = function() end }
    ObjectiveTrackerFrame = { modules = { other, renamed } }
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.WorldQuests.Refresh()
    renamed:LayoutContents()
    assertEq(renamed.laidOut, 0, "blocked through the header-text match")
    assertTrue((renamed.dirty or 0) >= 1, "marked dirty")
    QuestPrism.Settings.Set("HideWorldQuests", false)
    QuestPrism.WorldQuests.Refresh()
    renamed:LayoutContents()
    assertEq(renamed.laidOut, 1, "block lifted")
    assertTrue(pcall(QuestPrism.WorldQuests.Inspect), "Inspect runs")
    ObjectiveTrackerFrame = nil
end)

test("Inspect is safe without the tracker frame", function()
    reset()
    ObjectiveTrackerFrame = nil; WorldQuestObjectiveTracker = nil
    assertTrue(pcall(QuestPrism.WorldQuests.Inspect))
end)

-- Waypoint arrow: opt-in, one rule -- while blocked AND the option is on, a world
-- quest is never super-tracked.
test("waypoint rule is off by default: a super-tracked world quest survives the block", function()
    MOCK.worldQuests = { [700] = true }
    MOCK.superTracked = 700
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", false)
    assertFalse(QuestPrism.WorldQuests.ShouldClearWaypoint(700))
    QuestPrism.WorldQuests.EnforceWaypoint()
    assertEq(MOCK.superTracked, 700, "left alone")
end)

test("with the option on, a super-tracked world quest is cleared while blocked", function()
    MOCK.worldQuests = { [700] = true }
    MOCK.superTracked = 700
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", true)
    assertTrue(QuestPrism.WorldQuests.ShouldClearWaypoint(700))
    QuestPrism.WorldQuests.EnforceWaypoint()
    assertEq(MOCK.superTracked, 0, "waypoint cleared")
end)

test("the rule never touches a normal quest, and never applies while unblocked", function()
    MOCK.worldQuests = { [700] = true }
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", true)
    QuestPrism.Settings.Set("HideWorldQuests", true)
    MOCK.superTracked = 42 -- a normal quest
    assertFalse(QuestPrism.WorldQuests.ShouldClearWaypoint(42))
    QuestPrism.WorldQuests.EnforceWaypoint()
    assertEq(MOCK.superTracked, 42, "normal quest kept")
    QuestPrism.Settings.Set("HideWorldQuests", false)
    MOCK.superTracked = 700
    assertFalse(QuestPrism.WorldQuests.ShouldClearWaypoint(700), "not blocked, not our business")
    QuestPrism.WorldQuests.EnforceWaypoint()
    assertEq(MOCK.superTracked, 700)
    assertFalse(QuestPrism.WorldQuests.ShouldClearWaypoint(nil), "nothing tracked")
    assertFalse(QuestPrism.WorldQuests.ShouldClearWaypoint(0))
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", false)
end)

test("Refresh applies the rule, so turning the block on clears an existing waypoint", function()
    MOCK.worldQuests = { [700] = true }
    MOCK.superTracked = 700
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", true)
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.WorldQuests.Refresh()
    assertEq(MOCK.superTracked, 0)
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", false)
    QuestPrism.Settings.Set("HideWorldQuests", false)
end)

test("a guide that draws its own arrow outranks the waypoint rule", function()
    MOCK.worldQuests = { [700] = true }
    QuestPrism.Settings.Set("HideWorldQuests", true)
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", true)
    -- Zygor followed: its arrow is the guide's business, so we keep our hands off.
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "z", steps = { { goals = {} } } }, AddMessageHandler = function() end }
    QuestPrism.Settings.Set("guideSource", "Zygor")
    assertTrue(QuestPrism.Sources.GuideOwnsWaypoint())
    assertFalse(QuestPrism.WorldQuests.ShouldClearWaypoint(700), "guide takes precedence")
    MOCK.superTracked = 700
    QuestPrism.WorldQuests.EnforceWaypoint()
    assertEq(MOCK.superTracked, 700, "left to the guide")
    -- BtWQuests has no arrow of its own, so the rule applies again.
    QuestPrism.Settings.Set("guideSource", "BtWQuests")
    assertFalse(QuestPrism.Sources.GuideOwnsWaypoint())
    assertTrue(QuestPrism.WorldQuests.ShouldClearWaypoint(700))
    QuestPrism.Settings.Set("guideSource", "Off")
    assertFalse(QuestPrism.Sources.GuideOwnsWaypoint(), "not following: nothing owns it")
    assertTrue(QuestPrism.WorldQuests.ShouldClearWaypoint(700))
    ZGV = nil
    QuestPrism.Settings.Set("clearWorldQuestWaypoint", false)
    QuestPrism.Settings.Set("HideWorldQuests", false)
end)
