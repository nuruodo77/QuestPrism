QuestPrism.Rules = {}

-- "Show it?" decision for a quest, independent of any pin. The world-map hook and
-- the objective-tracker hook call it with the type and the quest ID.
-- Rule order:
--   1. world quest block on -> hide anything that is a world quest (by type or by ID)
--   2. no type, or the WorldQuest type -> not filterable -> show (world quests,
--      scenarios, addon pins)
--   3. guide source active and quest ID known -> hide unless the quest is part of it
--   4. the type's checkbox

-- Guide gate alone: true when no source is active, or when the quest is part of it.
function QuestPrism.Rules.InGuide(questID)
    local guideSet = QuestPrism.Sources and QuestPrism.Sources.GetActiveQuestSet and QuestPrism.Sources.GetActiveQuestSet()
    if not guideSet or not questID then return true end
    return guideSet[questID] == true
end

local function isWorldQuest(questType, questID)
    if questType == "WorldQuest" then return true end
    return QuestPrism.Filter.IsWorldQuest(questID)
end

function QuestPrism.Rules.ShouldShow(questType, questID)
    if QuestPrism.Settings.Get("HideWorldQuests") == true and isWorldQuest(questType, questID) then
        return false
    end
    if not questType or questType == "WorldQuest" then return true end

    local guideSet = QuestPrism.Sources and QuestPrism.Sources.GetActiveQuestSet and QuestPrism.Sources.GetActiveQuestSet()
    if guideSet and questID and not guideSet[questID] then
        return false
    end

    return QuestPrism.Settings.Get(questType) == true
end
