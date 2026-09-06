QuestPrism.WorldMap = {}

local QUEST_TEMPLATES = {
    "CampaignQuestPinTemplate",
    "ImportantQuestPinTemplate",
    "LegendaryQuestPinTemplate",
    "MetaQuestPinTemplate",
    "RepeatableQuestPinTemplate",
    "QuestNormalPinTemplate",
    "QuestTrivialPinTemplate",
    "QuestOfferPinTemplate",
    "QuestPinTemplate",
    "AreaPOIEventPinTemplate",
    -- World quest pins have no type toggle but follow the world quest block.
    "WorldMap_WorldQuestPinTemplate",
    "WQL_WorldQuestPinTemplate",
}

-- Indexed set for O(1) lookups in IsQuestPin
local FILTERABLE_TEMPLATES = {}
for _, template in ipairs(QUEST_TEMPLATES) do
    FILTERABLE_TEMPLATES[template] = true
end

local PASS_THROUGH_TEMPLATES = {
    ["BonusObjectivePinTemplate"]      = true,
    ["ThreatObjectivePinTemplate"]     = true,
    ["ScenarioBlobPinTemplate"]        = true,
}

-- Pins touched by QuestPrism itself, with the mode applied ("hide" or "dim").
-- A pin that Blizzard hid on its side (removed offers, out of range, ...) is NEVER
-- shown again: only pins recorded here are restored.
-- Weak keys let the GC reclaim recycled pins.
local DIM_ALPHA = 0.3
local touchedByQuestPrism = setmetatable({}, { __mode = "k" })

local function restorePin(pin, mode)
    if mode == "hide" then
        pin:Show()
    else
        pin:SetAlpha(1)
    end
end

-- Blizzard's pools reuse the same frame for another pin (zone change): the mark
-- must go away on release, or it survives into the frame's next life and skews the
-- decision. OnReleased is hooked once per pin.
local releaseHooked = setmetatable({}, { __mode = "k" })
local function watchRelease(pin)
    if releaseHooked[pin] then return end
    releaseHooked[pin] = true
    if type(pin.OnReleased) == "function" then
        pcall(hooksecurefunc, pin, "OnReleased", function(released)
            touchedByQuestPrism[released] = nil
        end)
    end
end

local function applyFilterToPin(pin)
    local touched = touchedByQuestPrism[pin]
    if QuestPrism.Filter.ShouldShowPin(pin) then
        if touched then
            touchedByQuestPrism[pin] = nil
            restorePin(pin, touched)
        end
        return
    end
    local mode = QuestPrism.Settings.Get("dimFiltered") == true and "dim" or "hide"
    if touched and touched ~= mode then
        restorePin(pin, touched)
        touched = nil
    end
    -- Idempotent: re-applied even when the pin was already marked, since Blizzard may
    -- have shown it again in between (recycled frame, provider refresh).
    if mode == "hide" then
        if pin:IsShown() then
            pin:Hide()
            touchedByQuestPrism[pin] = "hide"
            watchRelease(pin)
        elseif touched ~= "hide" then
            -- Hidden, and not by us: that is Blizzard's doing, leave it alone.
            touchedByQuestPrism[pin] = nil
        end
    else
        pin:SetAlpha(DIM_ALPHA)
        touchedByQuestPrism[pin] = "dim"
        watchRelease(pin)
    end
end

-- Is this pin filterable (allow-list)?
-- Only real quest pins (known template or questClassification), world quest pins
-- and expeditions (time-limited events) are touched. Other questID-only pins (POIs,
-- delves, addon pins) stay intact, so nothing is hidden by accident.
function QuestPrism.WorldMap.IsQuestPin(child)
    -- Expedition first: any pin kind, even an ignored one, can draw an expedition.
    if QuestPrism.Filter.IsExpeditionPin(child) then return true end
    local template = child.pinTemplate
    if template and PASS_THROUGH_TEMPLATES[template] then return false end
    if template and FILTERABLE_TEMPLATES[template] then return true end
    if child.questClassification ~= nil then return true end
    return false
end

-- Walks ACTIVE pins only. Blizzard's pin pools keep recycled frames as children of
-- the canvas (hidden, pinTemplate = nil, but with their old questID/classification):
-- walking them would bring ghost markers back. Pools are used when exposed,
-- otherwise canvas children are filtered on pinTemplate ~= nil.
local function forEachActivePin(fn)
    if not WorldMapFrame then return end
    local pools = WorldMapFrame.pinPools
    if type(pools) == "table" then
        for _, pool in pairs(pools) do
            if type(pool.EnumerateActive) == "function" then
                for pin in pool:EnumerateActive() do
                    fn(pin)
                end
            end
        end
        return
    end
    local canvas = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not canvas then return end
    for _, child in ipairs({ canvas:GetChildren() }) do
        if child.pinTemplate ~= nil then
            fn(child)
        end
    end
end

-- "hidden/dimmed by QuestPrism" counters from the last refresh, per type and in
-- total. Pins hidden by Blizzard are never counted.
local hiddenCounts = {}
local hiddenTotal = 0
local refreshListener = nil

function QuestPrism.WorldMap.GetHiddenCounts()
    local copy = {}
    for k, v in pairs(hiddenCounts) do copy[k] = v end
    return copy
end

function QuestPrism.WorldMap.GetHiddenTotal()
    return hiddenTotal
end

-- Single listener (the settings window): called after each refresh with
-- (total, countsByType).
function QuestPrism.WorldMap.SetRefreshListener(fn)
    refreshListener = fn
end

local function refreshAllPins()
    if not WorldMapFrame then return end
    local active = {}
    local counts, total = {}, 0
    forEachActivePin(function(pin)
        active[pin] = true
        if QuestPrism.WorldMap.IsQuestPin(pin) then
            applyFilterToPin(pin)
            if touchedByQuestPrism[pin] then
                total = total + 1
                local questType = QuestPrism.Filter.GetPinType(pin)
                if questType then
                    counts[questType] = (counts[questType] or 0) + 1
                end
            end
        end
    end)
    -- A pin recycled by Blizzard is no longer "ours": forget its mark so it is not
    -- wrongly shown again in its next life.
    for pin in pairs(touchedByQuestPrism) do
        if not active[pin] then
            touchedByQuestPrism[pin] = nil
        end
    end
    hiddenCounts, hiddenTotal = counts, total
    if refreshListener then
        pcall(refreshListener, total, counts)
    end
end

-- One deferred refresh at a time: opening a busy map calls AcquirePin dozens of
-- times in the same frame, no need to rescan everything each time.
local refreshPending = false
local function scheduleRefresh(delay)
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(delay or 0, function()
        refreshPending = false
        refreshAllPins()
    end)
end

-- Targeted synchronous pass over the pins of one template: called right after a
-- data provider refreshed, before the frame is drawn, so nothing flickers. Counters
-- and the listener are updated by the deferred full pass.
local function refreshPinsByTemplate(template)
    if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
    for pin in WorldMapFrame:EnumeratePinsByTemplate(template) do
        if QuestPrism.WorldMap.IsQuestPin(pin) then
            applyFilterToPin(pin)
        end
    end
end

-- Blizzard's data providers are instances created before addons load: hooking
-- their mixin does not affect them. Each instance present on the map is hooked:
-- after its RefreshAllData, its pins are filtered within the same frame.
local function hookDataProvider(provider)
    if type(provider) ~= "table" or type(provider.RefreshAllData) ~= "function" then return end
    local template
    if type(provider.GetPinTemplate) == "function" then
        local ok, value = pcall(provider.GetPinTemplate, provider)
        if ok and type(value) == "string" then template = value end
    end
    hooksecurefunc(provider, "RefreshAllData", function()
        if template then
            refreshPinsByTemplate(template)
        end
        scheduleRefresh(0)
    end)
end

-- Pins are never touched from inside Blizzard's AcquirePin (for instance through a
-- QuestPinMixin.OnAcquired hook): AcquirePin goes on to call the protected
-- SetPassThroughButtons on the very pin, and hiding it just before that call gets
-- the addon blocked. Filtering happens after each data provider's refresh instead,
-- still before the frame is drawn, plus a deferred full pass.
function QuestPrism.WorldMap.Initialize()
    pcall(function()
        hooksecurefunc(WorldMapFrame, "AcquirePin", function()
            scheduleRefresh(0)
        end)
    end)

    -- Zone change: Blizzard refreshes every provider inside OnMapChanged; this
    -- post-hook filters right away, before the frame is drawn.
    pcall(function()
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            refreshAllPins()
        end)
    end)

    pcall(function()
        for provider in pairs(WorldMapFrame.dataProviders) do
            pcall(hookDataProvider, provider)
        end
    end)

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:SetScript("OnEvent", function()
        scheduleRefresh(0.1)
    end)
end

-- Single "settings changed" entry point: world map plus the minimap's engine
-- filters.
function QuestPrism.WorldMap.Refresh()
    refreshAllPins()
    if QuestPrism.Minimap and QuestPrism.Minimap.Sync then
        pcall(QuestPrism.Minimap.Sync)
    end
    if QuestPrism.ObjectiveTracker and QuestPrism.ObjectiveTracker.Refresh then
        pcall(QuestPrism.ObjectiveTracker.Refresh)
    end
    if QuestPrism.WorldQuests and QuestPrism.WorldQuests.Refresh then
        pcall(QuestPrism.WorldQuests.Refresh)
    end
    if QuestPrism.GuideTab and QuestPrism.GuideTab.Refresh then
        pcall(QuestPrism.GuideTab.Refresh)
    end
end

-- Diagnostic tool: lists EVERY active template on the map with the detection
-- verdict, and the API details for those carrying a quest ID.
function QuestPrism.WorldMap.InspectPins()
    local seen = {}
    forEachActivePin(function(child)
        local template = tostring(child.pinTemplate)
        local questID  = QuestPrism.Filter.GetQuestID(child)
        if not seen[template] then
            seen[template] = true
            local filtered = QuestPrism.WorldMap.IsQuestPin(child)
            print(string.format("|cff00ff00QuestPrism Inspect:|r template=%s filtered=%s",
                template, tostring(filtered)))
        end
        if questID and questID ~= 0 then
            local timeLeft   = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds and C_TaskQuest.GetQuestTimeLeftSeconds(questID)
            local campaignID = C_CampaignInfo and C_CampaignInfo.GetCampaignID and C_CampaignInfo.GetCampaignID(questID)
            local tagInfo    = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
            print(string.format(
                "|cffffff00  -> questID=%s timeLeft=%s campaignID=%s worldQuestType=%s classification=%s|r",
                tostring(questID),
                tostring(timeLeft),
                tostring(campaignID),
                tostring(tagInfo and tagInfo.worldQuestType),
                tostring(child.questClassification)
            ))
        end
    end)
end

-- The hook set by StartScan cannot be removed (hooksecurefunc): it is installed
-- once; later calls only print the state again.
local scanHooked = false
function QuestPrism.WorldMap.StartScan()
    if not scanHooked then
        local seen = {}
        scanHooked = pcall(hooksecurefunc, WorldMapFrame, "AcquirePin", function(_, templateName)
            if templateName and not seen[templateName] then
                seen[templateName] = true
                print("|cff00ff00QuestPrism Scan:|r template = " .. templateName)
            end
        end)
    end
    print(QuestPrism_L.SCAN_ACTIVE_MSG)
end
