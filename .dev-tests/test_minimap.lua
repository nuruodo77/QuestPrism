bootCore()

test("Sync shows trivial quests iff the Trivial toggle is on", function()
    QuestPrism.Settings.Set("Trivial", true); QuestPrism.Minimap.Sync(); assertEq(MOCK.tracking[1].active, true)
    QuestPrism.Settings.Set("Trivial", false); QuestPrism.Minimap.Sync(); assertEq(MOCK.tracking[1].active, false)
end)

test("Sync leaves the account-completed filter to the game", function()
    MOCK.setTrackingCalls = {}; QuestPrism.Minimap.Sync()
    for _, c in ipairs(MOCK.setTrackingCalls) do assertTrue(c[1] ~= 2, "account-completed filter touched") end
end)

test("Sync does not call SetTracking when already in the wanted state", function()
    QuestPrism.Minimap.Sync(); MOCK.setTrackingCalls = {}; QuestPrism.Minimap.Sync()
    assertEq(#MOCK.setTrackingCalls, 0)
end)

test("Sync never touches unrelated trackers", function()
    MOCK.setTrackingCalls = {}; QuestPrism.Settings.Set("Trivial", true); QuestPrism.Minimap.Sync()
    for _, c in ipairs(MOCK.setTrackingCalls) do assertTrue(c[1] ~= 3, "banker touched") end
end)

test("WorldMap.Refresh triggers a minimap sync", function()
    local called = false; local orig = QuestPrism.Minimap.Sync
    QuestPrism.Minimap.Sync = function() called = true end
    QuestPrism.WorldMap.Refresh(); QuestPrism.Minimap.Sync = orig
    assertTrue(called)
end)

test("Sync is a no-op without the API", function()
    local saved = C_Minimap; C_Minimap = nil
    local ok = pcall(QuestPrism.Minimap.Sync); C_Minimap = saved
    assertTrue(ok)
end)
