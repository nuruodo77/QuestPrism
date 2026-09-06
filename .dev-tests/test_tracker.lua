bootCore()

local function quest(id, classification, isTask)
    return {
        GetID = function() return id end,
        GetQuestClassification = function() return classification end,
        isTask = isTask,
    }
end

local function fakeModules()
    QuestObjectiveTracker = {
        ShouldDisplayQuest = function(self, q) return not q.isTask end, -- Blizzard's own rule
        MarkDirty = function(self) self.dirty = (self.dirty or 0) + 1 end,
    }
    CampaignQuestObjectiveTracker = {
        ShouldDisplayQuest = function(self, q) return true end,
        MarkDirty = function(self) self.dirty = (self.dirty or 0) + 1 end,
    }
end

test("trackerFilter defaults on and is per character", function()
    assertEq(QuestPrism.Settings.Get("trackerFilter"), true)
end)

test("type toggles filter tracked quests; Blizzard's own 'no' always wins", function()
    fakeModules(); QuestPrism.ObjectiveTracker.Initialize()
    QuestPrism.Settings.Reset()
    local q = quest(10, Enum.QuestClassification.Normal)
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(q), true)
    QuestPrism.Settings.Set("LocalStory", false)
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(q), false, "Local Story off hides it")
    QuestPrism.Settings.Set("LocalStory", true)
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(quest(11, Enum.QuestClassification.Normal, true)), false, "task: Blizzard says no")
end)

test("campaign module quests are treated as Campaign", function()
    fakeModules(); QuestPrism.ObjectiveTracker.Initialize()
    QuestPrism.Settings.Reset()
    local q = quest(20, Enum.QuestClassification.Campaign)
    assertEq(CampaignQuestObjectiveTracker:ShouldDisplayQuest(q), true)
    QuestPrism.Settings.Set("Campaign", false)
    assertEq(CampaignQuestObjectiveTracker:ShouldDisplayQuest(q), false)
    QuestPrism.Settings.Set("Campaign", true)
end)

test("world-quest classified entries ignore the type toggles but follow the block", function()
    fakeModules(); QuestPrism.ObjectiveTracker.Initialize()
    QuestPrism.Settings.Reset()
    QuestPrism.Settings.Set("LocalStory", false)
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(quest(30, Enum.QuestClassification.WorldQuest)), true)
    QuestPrism.Settings.Set("HideWorldQuests", true)
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(quest(30, Enum.QuestClassification.WorldQuest)), false)
    QuestPrism.Settings.Set("HideWorldQuests", false); QuestPrism.Settings.Set("LocalStory", true)
end)

test("guide filter applies to the tracker", function()
    fakeModules(); QuestPrism.ObjectiveTracker.Initialize()
    QuestPrism.Settings.Reset()
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "g", steps = { { goals = { { questid = 40 } } } } }, AddMessageHandler = function() end }
    QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(quest(40, Enum.QuestClassification.Normal)), true)
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(quest(41, Enum.QuestClassification.Normal)), false)
    QuestPrism.Settings.Set("guideSource", "Off"); ZGV = nil
end)

test("turning the tracker filter off restores Blizzard behaviour", function()
    fakeModules(); QuestPrism.ObjectiveTracker.Initialize()
    QuestPrism.Settings.Reset(); QuestPrism.Settings.Set("LocalStory", false)
    QuestPrism.Settings.Set("trackerFilter", false)
    assertEq(QuestObjectiveTracker:ShouldDisplayQuest(quest(50, Enum.QuestClassification.Normal)), true)
    QuestPrism.Settings.Set("trackerFilter", true); QuestPrism.Settings.Set("LocalStory", true)
end)

test("a QuestPrism refresh marks both modules dirty", function()
    fakeModules(); QuestPrism.ObjectiveTracker.Initialize()
    QuestPrism.WorldMap.Refresh()
    assertTrue((QuestObjectiveTracker.dirty or 0) >= 1, "quest module dirty")
    assertTrue((CampaignQuestObjectiveTracker.dirty or 0) >= 1, "campaign module dirty")
end)

test("Initialize is safe without the tracker and wraps only once", function()
    QuestObjectiveTracker = nil; CampaignQuestObjectiveTracker = nil
    local ok = pcall(QuestPrism.ObjectiveTracker.Initialize); assertTrue(ok)
    fakeModules()
    QuestPrism.ObjectiveTracker.Initialize(); local first = QuestObjectiveTracker.ShouldDisplayQuest
    QuestPrism.ObjectiveTracker.Initialize()
    assertEq(QuestObjectiveTracker.ShouldDisplayQuest, first, "not re-wrapped")
end)
