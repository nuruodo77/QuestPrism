bootCore()

-- Fake quest log state for BuildEntries
local logIndex, flagged, titles, objectives, complete = {}, {}, {}, {}, {}
C_QuestLog.GetLogIndexForQuestID = function(id) return logIndex[id] end
C_QuestLog.IsQuestFlaggedCompleted = function(id) return flagged[id] == true end
C_QuestLog.GetTitleForQuestID = function(id) return titles[id] end
C_QuestLog.GetQuestObjectives = function(id) return objectives[id] end
C_QuestLog.IsComplete = function(id) return complete[id] == true end
local requested = {}
C_QuestLog.RequestLoadQuestByID = function(id) requested[id] = true end
C_QuestLog.GetQuestClassification = function(id) return Enum.QuestClassification.Normal end

LOAD_ADDON_FILE("UI/Widgets.lua")
LOAD_ADDON_FILE("UI/GuideTab.lua")

test("BuildEntries splits guide quests into in-log, to-pick-up, and completed, keeping guide order", function()
    logIndex = { [20] = 3, [40] = 1 }; flagged = { [10] = true }
    titles = { [20] = "Twenty", [30] = "Thirty", [40] = "Forty" }
    objectives = { [20] = { { text = "Kill 5", finished = false }, { text = "Talk", finished = true } } }
    complete = { [40] = true }
    local entries = QuestPrism.GuideTab.BuildEntries({
        { questID = 10, step = 1 }, { questID = 20, step = 2 }, { questID = 30, step = 2 }, { questID = 40, step = 3 },
        { questID = 20, step = 5 }, -- duplicate: ignored
    })
    assertEq(entries.completed, 1)
    assertEq(#entries.inLog, 2); assertEq(entries.inLog[1].questID, 20); assertEq(entries.inLog[2].questID, 40)
    assertEq(entries.inLog[1].title, "Twenty"); assertEq(#entries.inLog[1].objectives, 2)
    assertEq(entries.inLog[2].isComplete, true, "ready to turn in")
    assertEq(#entries.toPickUp, 1); assertEq(entries.toPickUp[1].questID, 30); assertEq(entries.toPickUp[1].step, 2)
end)

test("BuildEntries requests unknown titles and falls back to a placeholder", function()
    logIndex = {}; flagged = {}; titles = {}; requested = {}
    local entries = QuestPrism.GuideTab.BuildEntries({ { questID = 77, step = 4 } })
    assertEq(#entries.toPickUp, 1)
    assertTrue(entries.toPickUp[1].title:find("77", 1, true) ~= nil, "placeholder contains the id")
    assertTrue(requested[77], "title load requested")
end)

test("BuildEntries tolerates nil list", function()
    local entries = QuestPrism.GuideTab.BuildEntries(nil)
    assertEq(#entries.inLog, 0); assertEq(#entries.toPickUp, 0); assertEq(entries.completed, 0)
end)

-- Ordered list from the sources
test("Sources.GetActiveQuestList keeps guide order and step numbers; set is derived", function()
    ZGV = { CurrentStepNum = 2, CurrentGuide = { title = "o", steps = {
        { goals = { { questid = 1 } } }, { goals = { { questid = 5 }, { questid = 3 } } }, { goals = { { questid = 9 }, { questid = 5 } } },
    } }, AddMessageHandler = function() end }
    QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "lookahead"); QuestPrism.Settings.Set("guideLookahead", 1)
    QuestPrism.Sources.Invalidate()
    local list = QuestPrism.Sources.GetActiveQuestList()
    assertEq(#list, 3, "5, 3, 9 (duplicate 5 dropped)")
    assertEq(list[1].questID, 5); assertEq(list[1].step, 2)
    assertEq(list[2].questID, 3); assertEq(list[3].questID, 9); assertEq(list[3].step, 3)
    local set = QuestPrism.Sources.GetActiveQuestSet()
    assertTrue(set[5] and set[3] and set[9] and not set[1])
    QuestPrism.Settings.Set("guideSource", "Off"); ZGV = nil
end)
