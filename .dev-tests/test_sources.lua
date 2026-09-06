bootCore()

-- Fake Zygor: 5 steps, quest ids per step
local function fakeZygor(stepNum)
    local handlers = {}
    ZGV = {
        CurrentStepNum = stepNum,
        CurrentGuide = { title = "Leveling\\Test", steps = {
            { goals = { { questid = 101 }, { questid = "102" } } },
            { goals = { { questid = 201 } } },
            { goals = { { questid = 301 }, { npcid = 5 } } },
            { goals = { { questid = 401 } } },
            { goals = { { questid = 501 } } },
        } },
        handlers = handlers,
    }
    function ZGV:AddMessageHandler(event, fn) handlers[event] = fn end
end

-- Fake RestedXP, shaped like its public frame: 4 steps; step 2 has an ids list.
local function fakeRXP(stepNum)
    local steps = {
        { index = 1, elements = { { questId = 11 } } },
        { index = 2, elements = { { questId = 21 }, { ids = { 22, 23 } } } },
        { index = 3, elements = { { questId = 31 } } },
        { index = 4, elements = { { questId = 41 } } },
    }
    local pool = {}
    for i, step in ipairs(steps) do pool[i] = { step = step } end
    RXPCData = { currentStep = stepNum }
    RXPFrame = {
        activeSteps = { steps[stepNum] },
        ScrollChild = { framePool = pool },
        BottomFrame = { UpdateFrame = function() end },
        GuideName = { text = { GetText = function() return "1-10 Test" end } },
    }
    -- what RXP does on a step change: index moves, active steps re-filled, frame updated
    function RXPFrame.SetStepForTest(n)
        RXPCData.currentStep = n
        RXPFrame.activeSteps = { steps[n] }
        RXPFrame.BottomFrame.UpdateFrame()
    end
end

local function keys(set)
    local list = {}
    for k in pairs(set or {}) do list[#list + 1] = k end
    table.sort(list)
    return table.concat(list, ",")
end

test("guide settings default to Off / lookahead / 3 and are per character", function()
    assertEq(QuestPrism.Settings.Get("guideSource"), "Off")
    assertEq(QuestPrism.Settings.Get("guideScope"), "lookahead")
    assertEq(QuestPrism.Settings.Get("guideLookahead"), 3)
    QuestPrism.Settings.Solo("Campaign")
    QuestPrism.Settings.Set("guideSource", "Zygor")
    assertTrue(QuestPrism.Settings.IsSoloed("Campaign"), "guide settings must not end solo mode")
    QuestPrism.Settings.Solo("Campaign"); QuestPrism.Settings.Set("guideSource", "Off")
end)

test("no active source -> no quest set", function()
    ZGV = nil; RXPFrame = nil; RXPCData = nil
    QuestPrism.Settings.Set("guideSource", "Off")
    assertEq(QuestPrism.Sources.GetActiveQuestSet(), nil)
    QuestPrism.Settings.Set("guideSource", "Zygor")
    assertEq(QuestPrism.Sources.GetActiveQuestSet(), nil, "Zygor not loaded -> nil")
    assertTrue(QuestPrism.Sources.GetStatusText():find("Zygor", 1, true) ~= nil, "status names the source")
end)

test("Zygor scopes: step, lookahead (clamped), whole guide", function()
    fakeZygor(3); QuestPrism.Settings.Set("guideSource", "Zygor")
    QuestPrism.Settings.Set("guideScope", "step")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "301")
    QuestPrism.Settings.Set("guideScope", "lookahead"); QuestPrism.Settings.Set("guideLookahead", 5)
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "301,401,501", "clamped at guide end")
    QuestPrism.Settings.Set("guideScope", "guide")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "101,102,201,301,401,501", "string ids converted")
    QuestPrism.Settings.Set("guideLookahead", 3)
end)

test("Zygor step change invalidates the cache and refreshes the map", function()
    fakeZygor(1); QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "101,102")
    local refreshed = false
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() refreshed = true end
    QuestPrism.Sources.Initialize()
    assertTrue(ZGV.handlers.ZGV_STEP_CHANGED ~= nil, "subscribed to step change")
    ZGV.CurrentStepNum = 2
    ZGV.handlers.ZGV_STEP_CHANGED()
    assertFalse(refreshed, "refresh is deferred, not synchronous")
    MOCK.flushTimers()
    QuestPrism.WorldMap.Refresh = orig
    assertTrue(refreshed, "refresh triggered after the debounce timer")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "201", "new step's quests")
end)

test("RXP scopes and ids lists", function()
    fakeRXP(2); QuestPrism.Settings.Set("guideSource", "RXP")
    QuestPrism.Settings.Set("guideScope", "step")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "21,22,23")
    QuestPrism.Settings.Set("guideScope", "lookahead"); QuestPrism.Settings.Set("guideLookahead", 1)
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "21,22,23,31")
    QuestPrism.Settings.Set("guideScope", "guide")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "11,21,22,23,31,41")
    QuestPrism.Settings.Set("guideLookahead", 3)
end)

test("RXP SetStep post-hook refreshes and the set follows the step", function()
    fakeRXP(1); QuestPrism.Settings.Set("guideSource", "RXP"); QuestPrism.Settings.Set("guideScope", "step")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "11")
    local refreshed = false
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() refreshed = true end
    QuestPrism.Sources.Initialize()
    RXPFrame.SetStepForTest(3)
    MOCK.flushTimers()
    QuestPrism.WorldMap.Refresh = orig
    assertTrue(refreshed); assertEq(keys(QuestPrism.Sources.GetActiveQuestSet()), "31")
end)

test("status text reports step and quest count when active", function()
    fakeZygor(2); QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    local text = QuestPrism.Sources.GetStatusText()
    assertTrue(text:find("2", 1, true) ~= nil and text:find("1", 1, true) ~= nil, "step 2, 1 quest: " .. text)
end)

test("FirstAvailable prefers a loaded adapter", function()
    ZGV = nil; fakeRXP(1)
    assertEq(QuestPrism.Sources.FirstAvailable(), "RXP")
    RXPFrame = nil; RXPCData = nil
    assertEq(QuestPrism.Sources.FirstAvailable(), nil)
end)

-- Rules ordering
test("Rules: guide gate hides non-guide quests and keeps guide quests; typeless pins pass", function()
    fakeZygor(1); QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    QuestPrism.Settings.Reset()
    assertEq(QuestPrism.Rules.ShouldShow("Campaign", 101), true, "in guide")
    assertEq(QuestPrism.Rules.ShouldShow("Campaign", 999), false, "not in guide")
    assertEq(QuestPrism.Rules.ShouldShow("Campaign", nil), true, "no id passes the gate")
    assertEq(QuestPrism.Rules.ShouldShow(nil, 999), true, "typeless passes")
    assertEq(QuestPrism.Rules.ShouldShow("Expedition", 999), false, "expedition gated by guide")
end)

test("Rules: the type toggle still applies on top of the guide; world quests pass the guide gate", function()
    fakeZygor(1); QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    QuestPrism.Settings.Reset()
    QuestPrism.Settings.Set("Campaign", false)
    assertEq(QuestPrism.Rules.ShouldShow("Campaign", 101), false, "type off")
    QuestPrism.Settings.Set("Campaign", true)
    assertEq(QuestPrism.Rules.ShouldShow("Campaign", 101), true, "type on, in guide")
    assertEq(QuestPrism.Rules.ShouldShow("WorldQuest", 555), true, "world quest outside the guide still shown")
    QuestPrism.Settings.Set("guideSource", "Off")
end)

test("ShouldShowPin on a real pin honours the guide filter", function()
    fakeZygor(1); QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    QuestPrism.Settings.Reset()
    local inGuide  = { pinTemplate = "QuestOfferPinTemplate", questClassification = Enum.QuestClassification.Campaign, questID = 101 }
    local outGuide = { pinTemplate = "QuestOfferPinTemplate", questClassification = Enum.QuestClassification.Campaign, questID = 777 }
    local worldQuest = { pinTemplate = "WorldMap_WorldQuestPinTemplate", questID = 888 }
    assertTrue(QuestPrism.Filter.ShouldShowPin(inGuide)); assertFalse(QuestPrism.Filter.ShouldShowPin(outGuide))
    assertTrue(QuestPrism.Filter.ShouldShowPin(worldQuest), "pass-through untouched")
    QuestPrism.Settings.Set("guideSource", "Off")
end)


test("a burst of step-change messages (guide load) causes a single deferred refresh", function()
    fakeZygor(1); QuestPrism.Settings.Set("guideSource", "Zygor")
    QuestPrism.Sources.Initialize()
    MOCK.flushTimers(); MOCK.timers = {}
    local count = 0
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() count = count + 1 end
    for i = 1, 300 do ZGV.CurrentStepNum = i % 5 + 1; ZGV.handlers.ZGV_STEP_CHANGED() end
    assertEq(#MOCK.timers, 1, "one pending timer for the whole burst")
    MOCK.flushTimers()
    QuestPrism.WorldMap.Refresh = orig
    assertEq(count, 1, "one refresh")
    QuestPrism.Settings.Set("guideSource", "Off")
end)

test("step-change signals without an actual change do not schedule a refresh", function()
    fakeZygor(2); QuestPrism.Settings.Set("guideSource", "Zygor")
    QuestPrism.Sources.Initialize()
    ZGV.handlers.ZGV_STEP_CHANGED(); MOCK.flushTimers(); MOCK.timers = {}
    for i = 1, 50 do ZGV.handlers.ZGV_STEP_CHANGED() end -- same guide, same step
    assertEq(#MOCK.timers, 0, "no refresh scheduled for no-op signals")
    ZGV.CurrentStepNum = 3
    ZGV.handlers.ZGV_STEP_CHANGED()
    assertEq(#MOCK.timers, 1, "real step change schedules one refresh")
    MOCK.flushTimers()
    QuestPrism.Settings.Set("guideSource", "Off")
end)
