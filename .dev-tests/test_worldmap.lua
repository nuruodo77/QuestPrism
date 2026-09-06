bootCore()

local function offerPin(classification, questID)
    local pin = WorldMapFrame:AcquirePin("QuestOfferPinTemplate")
    pin.questClassification = classification
    pin.questID = questID
    return pin
end

test("hidden type is hidden after refresh", function()
    QuestPrism.Settings.Set("Campaign", false)
    local pin = offerPin(Enum.QuestClassification.Campaign, 100)
    QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown(), "campaign pin visible")
end)

test("pin hidden by QuestPrism is re-shown when its type is re-enabled", function()
    QuestPrism.Settings.Set("Campaign", false)
    local pin = offerPin(Enum.QuestClassification.Campaign, 101)
    QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown())
    QuestPrism.Settings.Set("Campaign", true)
    QuestPrism.WorldMap.Refresh()
    assertTrue(pin:IsShown(), "pin should be re-shown")
end)

test("pin hidden by Blizzard is never force-shown", function()
    QuestPrism.Settings.Set("Campaign", true)
    local pin = offerPin(Enum.QuestClassification.Campaign, 102)
    pin:Hide() -- Blizzard hid it (e.g. suppressed offer)
    QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown(), "QuestPrism must not resurrect Blizzard-hidden pins")
end)

test("released (pooled) pins are not touched", function()
    QuestPrism.Settings.Set("Campaign", true)
    local pin = offerPin(Enum.QuestClassification.Campaign, 103)
    WorldMapFrame:ReleasePin(pin) -- template cleared, stale fields remain, hidden
    QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown(), "released pin was resurrected")
end)

test("many AcquirePin calls schedule a single deferred refresh", function()
    MOCK.flushTimers() -- clear any refresh still pending from earlier tests
    MOCK.timers = {}
    for i = 1, 25 do WorldMapFrame:AcquirePin("QuestOfferPinTemplate") end
    assertEq(#MOCK.timers, 1, "pending timers")
end)

test("StartScan installs its hook only once", function()
    MOCK.printed = {}
    QuestPrism.WorldMap.StartScan()
    QuestPrism.WorldMap.StartScan()
    WorldMapFrame:AcquirePin("BrandNewTemplate")
    local count = 0
    for _, line in ipairs(MOCK.printed) do
        if line:find("BrandNewTemplate", 1, true) then count = count + 1 end
    end
    assertEq(count, 1, "scan lines for one template")
end)

test("dim mode dims filtered pins instead of hiding them", function()
    QuestPrism.Settings.Set("dimFiltered", true); QuestPrism.Settings.Set("Campaign", false)
    local pin = offerPin(Enum.QuestClassification.Campaign, 300)
    QuestPrism.WorldMap.Refresh()
    assertTrue(pin:IsShown(), "dimmed pin stays shown"); assertEq(pin:GetAlpha(), 0.3, "dim alpha")
    QuestPrism.Settings.Set("Campaign", true); QuestPrism.WorldMap.Refresh()
    assertEq(pin:GetAlpha(), 1, "alpha restored")
    QuestPrism.Settings.Set("dimFiltered", false)
end)

test("switching from dim to hide restores alpha and hides", function()
    QuestPrism.Settings.Set("dimFiltered", true); QuestPrism.Settings.Set("Campaign", false)
    local pin = offerPin(Enum.QuestClassification.Campaign, 301)
    QuestPrism.WorldMap.Refresh(); assertEq(pin:GetAlpha(), 0.3)
    QuestPrism.Settings.Set("dimFiltered", false); QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown(), "hidden after mode switch"); assertEq(pin:GetAlpha(), 1, "alpha restored on switch")
    QuestPrism.Settings.Set("Campaign", true); QuestPrism.WorldMap.Refresh(); assertTrue(pin:IsShown(), "re-shown")
end)

test("hidden counts are tracked per type and in total", function()
    QuestPrism.Settings.Set("dimFiltered", false)
    QuestPrism.Settings.Reset()
    QuestPrism.Settings.Set("Campaign", false); QuestPrism.Settings.Set("Meta", false)
    MOCK.resetWorldMap(); QuestPrism.WorldMap.Initialize()
    offerPin(Enum.QuestClassification.Campaign, 500); offerPin(Enum.QuestClassification.Campaign, 501)
    offerPin(Enum.QuestClassification.Meta, 502); offerPin(Enum.QuestClassification.Important, 503)
    QuestPrism.WorldMap.Refresh()
    local counts = QuestPrism.WorldMap.GetHiddenCounts()
    assertEq(counts.Campaign, 2, "campaign"); assertEq(counts.Meta, 1, "meta"); assertEq(counts.Important, nil, "important shown")
    assertEq(QuestPrism.WorldMap.GetHiddenTotal(), 3, "total")
    QuestPrism.Settings.Set("Campaign", true); QuestPrism.WorldMap.Refresh()
    assertEq(QuestPrism.WorldMap.GetHiddenTotal(), 1, "total after re-enable")
    QuestPrism.Settings.Reset()
end)

test("refresh notifies a registered listener with the new total", function()
    local got
    QuestPrism.WorldMap.SetRefreshListener(function(total) got = total end)
    QuestPrism.WorldMap.Refresh()
    assertTrue(got ~= nil, "listener called")
    QuestPrism.WorldMap.SetRefreshListener(nil)
end)

test("a hidden pin reused by the pool for a new pin is hidden again (zone change)", function()
    QuestPrism.Settings.Reset(); QuestPrism.Settings.Set("dimFiltered", false)
    QuestPrism.Settings.Set("Expedition", false)
    MOCK.resetWorldMap(); QuestPrism.WorldMap.Initialize()
    local pin = WorldMapFrame:AcquirePin("AreaPOIEventPinTemplate")
    QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown(), "hidden in zone A")
    WorldMapFrame:ReleasePin(pin)
    WorldMapFrame:ReacquirePin(pin, "AreaPOIEventPinTemplate", { areaPoiID = 99 })
    assertTrue(pin:IsShown(), "Blizzard shows the reused pin")
    QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown(), "must be hidden again in zone B")
    QuestPrism.Settings.Reset()
end)

test("a reused pin that Blizzard keeps hidden is not resurrected when the type is re-enabled", function()
    QuestPrism.Settings.Reset(); QuestPrism.Settings.Set("dimFiltered", false)
    QuestPrism.Settings.Set("Expedition", false)
    MOCK.resetWorldMap(); QuestPrism.WorldMap.Initialize()
    local pin = WorldMapFrame:AcquirePin("AreaPOIEventPinTemplate")
    QuestPrism.WorldMap.Refresh()
    WorldMapFrame:ReleasePin(pin)
    WorldMapFrame:ReacquirePin(pin, "AreaPOIEventPinTemplate")
    pin:Hide() -- Blizzard hides this one (suppressed)
    QuestPrism.Settings.Set("Expedition", true)
    QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown(), "stale mark must not force-show a Blizzard-hidden pin")
    QuestPrism.Settings.Reset()
end)

test("a dimmed pin reused by the pool is dimmed again", function()
    QuestPrism.Settings.Reset(); QuestPrism.Settings.Set("dimFiltered", true)
    QuestPrism.Settings.Set("Expedition", false)
    MOCK.resetWorldMap(); QuestPrism.WorldMap.Initialize()
    local pin = WorldMapFrame:AcquirePin("AreaPOIEventPinTemplate")
    QuestPrism.WorldMap.Refresh(); assertEq(pin:GetAlpha(), 0.3)
    WorldMapFrame:ReleasePin(pin); pin:SetAlpha(1)
    WorldMapFrame:ReacquirePin(pin, "AreaPOIEventPinTemplate")
    QuestPrism.WorldMap.Refresh(); assertEq(pin:GetAlpha(), 0.3, "re-dimmed")
    QuestPrism.Settings.Set("dimFiltered", false); QuestPrism.Settings.Reset()
end)

test("pins acquired during a map change are hidden before the next frame", function()
    QuestPrism.Settings.Reset(); QuestPrism.Settings.Set("dimFiltered", false); QuestPrism.Settings.Set("Expedition", false)
    MOCK.resetWorldMap()
    local provider = { GetPinTemplate = function() return "AreaPOIEventPinTemplate" end }
    function provider:RefreshAllData() self.pin = WorldMapFrame:AcquirePin("AreaPOIEventPinTemplate") end
    WorldMapFrame:AddDataProvider(provider)
    QuestPrism.WorldMap.Initialize()
    MOCK.timers = {}
    WorldMapFrame:OnMapChanged()
    assertFalse(provider.pin:IsShown(), "hidden synchronously, no timer flush")
    QuestPrism.Settings.Reset()
end)

test("a provider refreshing on its own (later event) hides its pins synchronously", function()
    QuestPrism.Settings.Reset(); QuestPrism.Settings.Set("dimFiltered", false); QuestPrism.Settings.Set("Expedition", false)
    MOCK.resetWorldMap()
    local provider = { GetPinTemplate = function() return "AreaPOIEventPinTemplate" end }
    function provider:RefreshAllData() self.pin = WorldMapFrame:AcquirePin("AreaPOIEventPinTemplate") end
    WorldMapFrame:AddDataProvider(provider)
    QuestPrism.WorldMap.Initialize()
    MOCK.timers = {}
    provider:RefreshAllData()
    assertFalse(provider.pin:IsShown(), "hidden synchronously after provider refresh")
    QuestPrism.Settings.Reset()
end)
