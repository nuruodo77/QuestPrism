QuestPrism.Minimap = {}

-- Minimap quest markers are drawn by the engine: an addon cannot hide a single one.
-- The only lever is the tracking filter (Enum.MinimapTrackingFilter) that Blizzard
-- also exposes in its tracking menu. It applies to the minimap AND the world map:
--   * TrivialQuests -> low-level ("hidden") quests, driven by the "Trivial" toggle
-- SetTracking(index, true) means shown, as for any other tracking type.

local function trackingIndexFor(filterID)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter) then
        return nil
    end
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local filter = C_Minimap.GetTrackingFilter(index)
        if type(filter) == "table" and filter.filterID == filterID then
            return index
        end
    end
    return nil
end

-- true/false when known, nil when the API does not say (then written unconditionally).
local function isTrackingActive(index)
    if not (C_Minimap and C_Minimap.GetTrackingInfo) then return nil end
    local info = C_Minimap.GetTrackingInfo(index)
    if type(info) == "table" then
        return info.active == true
    end
    return nil
end

local function setFilterShown(filterID, shown)
    local index = trackingIndexFor(filterID)
    if not index or not (C_Minimap and C_Minimap.SetTracking) then return end
    if isTrackingActive(index) == shown then return end
    C_Minimap.SetTracking(index, shown)
end

-- Blizzard icon of the tracking filter (for the "Trivial quests" row of the window).
function QuestPrism.Minimap.GetTrackingTexture(filterID)
    local index = trackingIndexFor(filterID)
    if not index or not (C_Minimap and C_Minimap.GetTrackingInfo) then return nil end
    local info = C_Minimap.GetTrackingInfo(index)
    if type(info) == "table" then return info.texture end
    return nil
end

function QuestPrism.Minimap.Sync()
    local filters = Enum and Enum.MinimapTrackingFilter
    if not filters then return end
    if filters.TrivialQuests then
        setFilterShown(filters.TrivialQuests, QuestPrism.Settings.Get("Trivial") == true)
    end
end

function QuestPrism.Minimap.Initialize()
    pcall(QuestPrism.Minimap.Sync)
end
