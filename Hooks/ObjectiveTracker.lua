QuestPrism.ObjectiveTracker = {}

-- Blizzard's objective tracker: each quest module decides quest by quest through
-- ShouldDisplayQuest(quest) and rebuilds itself when marked dirty. That method is
-- wrapped on both quest modules (global instances): Blizzard's answer wins; when it
-- is "yes", our rules apply (types + guide).
-- Bonus objectives, scenarios, achievements: modules left untouched. The World
-- Quests module is handled by Hooks/WorldQuests.lua.

local MODULES = {
    { name = "QuestObjectiveTracker",         forcedType = nil },
    { name = "CampaignQuestObjectiveTracker", forcedType = "Campaign" },
}

local wrapped = {} -- module -> original Blizzard function

local function questTypeOf(quest, forcedType)
    if forcedType then return forcedType end
    if type(quest.GetQuestClassification) == "function" then
        local ok, classification = pcall(quest.GetQuestClassification, quest)
        if ok and classification ~= nil then
            return QuestPrism.Filter.GetTypeFromClassification(classification) or "LocalStory"
        end
    end
    return "LocalStory"
end

local function questIDOf(quest)
    if type(quest.GetID) == "function" then
        local ok, id = pcall(quest.GetID, quest)
        if ok then return tonumber(id) end
    end
    return tonumber(quest.questID)
end

local function wrapModule(module, forcedType)
    if wrapped[module] then return end
    local original = module.ShouldDisplayQuest
    if type(original) ~= "function" then return end
    wrapped[module] = original
    module.ShouldDisplayQuest = function(self, quest, ...)
        local shown = original(self, quest, ...)
        if not shown or type(quest) ~= "table" then return shown end
        if QuestPrism.Settings.Get("trackerFilter") ~= true then return shown end
        return QuestPrism.Rules.ShouldShow(questTypeOf(quest, forcedType), questIDOf(quest))
    end
end

function QuestPrism.ObjectiveTracker.Initialize()
    for _, info in ipairs(MODULES) do
        local module = _G[info.name]
        if type(module) == "table" then
            pcall(wrapModule, module, info.forcedType)
        end
    end
end

-- Asks Blizzard to rebuild the wrapped modules (called by QuestPrism.WorldMap.Refresh,
-- the "settings changed" entry point).
function QuestPrism.ObjectiveTracker.Refresh()
    for module in pairs(wrapped) do
        if type(module.MarkDirty) == "function" then
            pcall(module.MarkDirty, module)
        end
    end
end
