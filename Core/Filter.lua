QuestPrism.Filter = {}
local Filter = QuestPrism.Filter

-- Pin classification.
--
-- Every world-map pin is reduced to two facts: the filter type it belongs to
-- (a Settings key: Campaign, Important, Legendary, Meta, Repeatable, LocalStory,
-- Expedition; or WorldQuest, which has no toggle but can be blocked) and the quest
-- it stands for. Whether such a pin is shown is decided in Core/Rules.lua; this
-- file only answers "what is it?".
--
-- Sources of truth, in the order they are consulted:
--   1. time-limited events (expeditions), by dedicated template or quest timer
--   2. world quest pins, by template (Blizzard's and World Quest List's)
--   3. an ignore list of pin kinds that are never filtered
--   4. the pin's own QuestClassification (modern quest-offer pins carry it)
--   5. the pin template, for the few dedicated legacy templates
--   6. the quest ID, resolved through the quest APIs
-- A pin that fits none of these has no type and is left alone.

-- World quest pins: Blizzard's own and World Quest List's replacement.
local WORLD_QUEST_TEMPLATES = {
    WorldMap_WorldQuestPinTemplate = true,
    WQL_WorldQuestPinTemplate = true,
}

-- Pin kinds that stay untouched whatever the settings: bonus objectives, threats
-- and area blobs.
local IGNORED_TEMPLATES = {
    BonusObjectivePinTemplate = true,
    ThreatObjectivePinTemplate = true,
    ScenarioBlobPinTemplate = true,
    QuestBlobPinTemplate = true,
}

-- Dedicated templates that predate QuestOfferPinTemplate and still show up.
local TEMPLATE_TYPES = {
    CampaignQuestPinTemplate = "Campaign",
    ImportantQuestPinTemplate = "Important",
    LegendaryQuestPinTemplate = "Legendary",
    MetaQuestPinTemplate = "Meta",
    RepeatableQuestPinTemplate = "Repeatable",
    QuestNormalPinTemplate = "LocalStory",
    QuestTrivialPinTemplate = "LocalStory",
}

-- Templates that always represent a time-limited event, even without a quest ID.
local EVENT_TEMPLATES = {
    AreaPOIEventPinTemplate = true,
}

-- Enum.QuestClassification values that get their own filter type. Everything
-- else (Normal, Questline, Calling, BonusObjective, ...) counts as Local Story.
-- Built on first use: the Enum table only exists in the game client.
local classificationTypes

local function classificationTable()
    if classificationTypes then return classificationTypes end
    local E = Enum and Enum.QuestClassification
    if not E then return nil end
    classificationTypes = {}
    local function map(member, questType)
        if E[member] ~= nil then classificationTypes[E[member]] = questType end
    end
    map("Campaign", "Campaign")
    map("Important", "Important")
    map("Legendary", "Legendary")
    map("Meta", "Meta")
    map("Recurring", "Repeatable")
    map("WorldQuest", "WorldQuest")
    return classificationTypes
end

function Filter.GetTypeFromClassification(classification)
    local types = classificationTable()
    if not types then return nil end
    return types[classification] or "LocalStory"
end

-- Debug helper: an unknown template is reported once per session, not on every scan.
local reportedTemplates = {}

local function reportUnknownTemplate(template)
    if reportedTemplates[template] or not QuestPrism.Settings.Get("debug") then return end
    reportedTemplates[template] = true
    print("|cff00ff00QuestPrism Debug:|r " .. QuestPrism_L.UNKNOWN_TEMPLATE .. tostring(template))
end

-- Quest ID of a pin. Pins store it under a few different names, and some only
-- expose a method. A zero ID means "no real quest" (blob pins) and becomes nil.
local ID_FIELDS = { "questID", "questId" }

function Filter.GetQuestID(pin)
    if not pin then return nil end
    local questID
    for _, field in ipairs(ID_FIELDS) do
        questID = pin[field]
        if questID ~= nil then break end
    end
    if questID == nil and type(pin.questInfo) == "table" then
        for _, field in ipairs(ID_FIELDS) do
            questID = pin.questInfo[field]
            if questID ~= nil then break end
        end
    end
    if questID == nil and type(pin.GetQuestID) == "function" then
        local ok, value = pcall(pin.GetQuestID, pin)
        if ok then questID = value end
    end
    if type(questID) ~= "number" or questID == 0 then return nil end
    return questID
end

-- World quest by ID, whatever pin or tracker entry shows it. Unknown means no, so
-- a missing API never hides anything by accident.
function Filter.IsWorldQuest(questID)
    if not questID then return false end
    local api = C_QuestLog and C_QuestLog.IsWorldQuest
    return api ~= nil and api(questID) == true
end

-- Expeditions are zone events with a countdown. The timer identifies them no
-- matter which pin kind (area POI, world quest, addon pin) happens to draw them.
function Filter.IsExpeditionQuest(questID)
    if not questID then return false end
    local api = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds
    if not api then return false end
    local secondsLeft = api(questID)
    return type(secondsLeft) == "number" and secondsLeft > 0
end

function Filter.IsExpeditionPin(pin)
    if not pin then return false end
    if pin.pinTemplate and EVENT_TEMPLATES[pin.pinTemplate] then return true end
    return Filter.IsExpeditionQuest(Filter.GetQuestID(pin))
end

-- Type of a quest known only by ID. The modern client answers directly through
-- C_QuestInfoSystem; older clients are reconstructed from campaign membership,
-- quest tags and repeatability. Importance is not exposed there and falls back
-- to Local Story.
local function typeFromQuestID(questID)
    local classify = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification
    if classify then
        local ok, classification = pcall(classify, questID)
        if ok and classification ~= nil then
            local questType = Filter.GetTypeFromClassification(classification)
            if questType then return questType end
        end
    end

    -- GetCampaignID returns 0, not nil, for quests outside any campaign.
    local campaignID = C_CampaignInfo and C_CampaignInfo.GetCampaignID and C_CampaignInfo.GetCampaignID(questID)
    if type(campaignID) == "number" and campaignID > 0 then return "Campaign" end

    local tags = Enum and Enum.QuestTag
    local tagInfo = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
    local tagID = type(tagInfo) == "table" and tagInfo.tagID or nil
    if tags and tagID ~= nil then
        -- Members are checked one by one: not every client exposes Legendary and Meta.
        if tags.Legendary ~= nil and tagID == tags.Legendary then return "Legendary" end
        if tags.Meta ~= nil and tagID == tags.Meta then return "Meta" end
    end

    if C_QuestLog and C_QuestLog.IsRepeatableQuest and C_QuestLog.IsRepeatableQuest(questID) then
        return "Repeatable"
    end
    return "LocalStory"
end

-- Filter type of a pin, or nil when the pin is not something QuestPrism filters.
-- Same lookup for callers that only have a quest ID (the map tab's row icons).
Filter.GetQuestType = typeFromQuestID

function Filter.GetPinType(pin)
    if not pin then return nil end

    -- Events first: an expedition may be drawn by a pin kind that is otherwise ignored.
    if Filter.IsExpeditionPin(pin) then return "Expedition" end

    local template = pin.pinTemplate
    if template and WORLD_QUEST_TEMPLATES[template] then return "WorldQuest" end
    if template and IGNORED_TEMPLATES[template] then return nil end

    local classification = pin.questClassification
    if classification == nil and type(pin.questInfo) == "table" then
        classification = pin.questInfo.questClassification
    end
    if classification ~= nil then
        return Filter.GetTypeFromClassification(classification)
    end

    if template then
        local questType = TEMPLATE_TYPES[template]
        if questType then return questType end
        reportUnknownTemplate(template)
    end

    local questID = Filter.GetQuestID(pin)
    if questID then return typeFromQuestID(questID) end
    return nil
end

-- Convenience for the world-map hook: classify, then ask the rules.
function Filter.ShouldShowPin(pin)
    if not pin then return true end
    return QuestPrism.Rules.ShouldShow(Filter.GetPinType(pin), Filter.GetQuestID(pin))
end
