bootCore()

test("unknown template is logged once per session when debug is on", function()
    QuestPrismCharDB.debug = true
    MOCK.printed = {}
    local pin = { pinTemplate = "MysteryPinTemplate" }
    QuestPrism.Filter.ShouldShowPin(pin)
    QuestPrism.Filter.ShouldShowPin(pin)
    QuestPrism.Filter.ShouldShowPin({ pinTemplate = "MysteryPinTemplate" })
    local count = 0
    for _, line in ipairs(MOCK.printed) do
        if line:find("MysteryPinTemplate", 1, true) then count = count + 1 end
    end
    assertEq(count, 1, "debug lines")
    QuestPrismCharDB.debug = false
end)

test("quest-tag fallback tolerates a missing Enum.QuestTag.Meta", function()
    C_QuestLog.GetQuestTagInfo = function() return { tagID = 83 } end
    local ok, result = pcall(QuestPrism.Filter.ShouldShowPin, { pinTemplate = "QuestPinTemplate", questID = 5 })
    C_QuestLog.GetQuestTagInfo = function() return nil end
    assertTrue(ok, "ShouldShowPin errored: " .. tostring(result))
end)

test("world quest pins are typed WorldQuest, shown by default and hidden by the block", function()
    QuestPrism.Settings.Set("HideWorldQuests", false)
    local wq = { pinTemplate = "WorldMap_WorldQuestPinTemplate", questID = 200 }
    assertEq(QuestPrism.Filter.GetPinType(wq), "WorldQuest")
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "WQL_WorldQuestPinTemplate", questID = 201 }), "WorldQuest", "World Quest List pin")
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "QuestOfferPinTemplate", questClassification = Enum.QuestClassification.WorldQuest, questID = 202 }), "WorldQuest", "by classification")
    assertTrue(QuestPrism.Filter.ShouldShowPin(wq), "shown by default")
    QuestPrism.Settings.Set("LocalStory", false)
    assertTrue(QuestPrism.Filter.ShouldShowPin(wq), "type toggles do not apply to world quests")
    QuestPrism.Settings.Set("LocalStory", true)
    QuestPrism.Settings.Set("HideWorldQuests", true)
    assertFalse(QuestPrism.Filter.ShouldShowPin(wq), "blocked")
    QuestPrism.Settings.Set("HideWorldQuests", false)
end)

test("a world quest is a world quest whatever its timer: its own row governs it, not Expedition", function()
    -- Every world quest has a countdown. Until beta3 the timer was tested first, so all of
    -- them were typed Expedition and the World Quests row governed nothing.
    MOCK.timeLeft[210] = 600; MOCK.worldQuests[210] = true
    local timed = { pinTemplate = "WorldMap_WorldQuestPinTemplate", questID = 210 }
    assertEq(QuestPrism.Filter.GetPinType(timed), "WorldQuest", "the timer does not make it an expedition")
    QuestPrism.Settings.Set("Expedition", false)
    assertTrue(QuestPrism.Filter.ShouldShowPin(timed), "the Expedition row does not touch it")
    QuestPrism.Settings.Set("Expedition", true)
    QuestPrism.Settings.Set("HideWorldQuests", true)
    assertFalse(QuestPrism.Filter.ShouldShowPin(timed), "the World Quests row does")
    assertFalse(QuestPrism.Rules.ShouldShow("LocalStory", 210), "any type, world quest id -> hidden")
    assertTrue(QuestPrism.Rules.ShouldShow("LocalStory", 211), "non world quest unaffected")
    QuestPrism.Settings.Set("HideWorldQuests", false)
    -- A timed quest that is not a world quest is still an expedition.
    MOCK.timeLeft[212] = 600
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "QuestOfferPinTemplate", questID = 212 }), "Expedition", "timed, not a world quest")
    MOCK.timeLeft[210] = nil; MOCK.worldQuests[210] = nil; MOCK.timeLeft[212] = nil
end)

test("GetPinType classifies offer, template, and expedition pins", function()
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "QuestOfferPinTemplate", questClassification = Enum.QuestClassification.Campaign, questID = 400 }), "Campaign")
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "LegendaryQuestPinTemplate", questID = 401 }), "Legendary")
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "AreaPOIEventPinTemplate" }), "Expedition")
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "BonusObjectivePinTemplate", questID = 402 }), nil, "pass-through has no type")
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "SomethingElse" }), nil)
end)

test("questID-only pins ask C_QuestInfoSystem.GetQuestClassification when the client has it", function()
    C_QuestInfoSystem = { GetQuestClassification = function(id) if id == 7 then return Enum.QuestClassification.Meta end end }
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "QuestPinTemplate", questID = 7 }), "Meta")
    MOCK.campaign[8] = 12
    assertEq(QuestPrism.Filter.GetPinType({ pinTemplate = "QuestPinTemplate", questID = 8 }), "Campaign", "nil classification falls back to the older checks")
    MOCK.campaign[8] = nil
    C_QuestInfoSystem = nil
end)

test("GetQuestID reads direct, nested and method-provided ids and drops zero", function()
    assertEq(QuestPrism.Filter.GetQuestID({ questId = 11 }), 11)
    assertEq(QuestPrism.Filter.GetQuestID({ questInfo = { questID = 12 } }), 12)
    assertEq(QuestPrism.Filter.GetQuestID({ GetQuestID = function() return 13 end }), 13)
    assertEq(QuestPrism.Filter.GetQuestID({ questID = 0 }), nil)
    assertEq(QuestPrism.Filter.GetQuestID(nil), nil)
end)
