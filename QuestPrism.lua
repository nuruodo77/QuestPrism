QuestPrism = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "QuestPrism" then
            QuestPrism.Settings.Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        QuestPrism.Sources.Initialize()
        QuestPrism.WorldMap.Initialize()
        QuestPrism.Minimap.Initialize()
        QuestPrism.ObjectiveTracker.Initialize()
        QuestPrism.WorldQuests.Initialize()
        QuestPrism.MinimapButton.Initialize()
        QuestPrism.WorldMapButton.Initialize()
        QuestPrism.Panel.Initialize()
        QuestPrism.GuideTab.Initialize()
        QuestPrism.Options.Initialize()
    end
end)

SLASH_QUESTPRISM1 = "/questprism"
SLASH_QUESTPRISM2 = "/prism"
SLASH_QUESTPRISM3 = "/lens"
SlashCmdList["QUESTPRISM"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "reset" then
        QuestPrism.Settings.Reset()
        QuestPrism.WorldMap.Refresh()
        if QuestPrism.Panel and QuestPrism.Panel.Sync then QuestPrism.Panel.Sync() end
        if QuestPrism.GuideTab and QuestPrism.GuideTab.Sync then QuestPrism.GuideTab.Sync() end
        print(QuestPrism_L.RESET_MSG)
    elseif cmd == "debug" then
        QuestPrism.Settings.ToggleDebug()
    elseif cmd == "scan" then
        QuestPrism.WorldMap.StartScan()
    elseif cmd == "inspect" then
        QuestPrism.WorldMap.InspectPins()
    elseif cmd == "tracker" then
        QuestPrism.WorldQuests.Inspect()
    elseif cmd == "options" or cmd == "config" then
        QuestPrism.Options.Open()
    elseif cmd == "help" or cmd == "?" then
        for _, line in ipairs(QuestPrism_L.HELP_LINES) do print(line) end
    else
        QuestPrism.Panel.Toggle()
    end
end
