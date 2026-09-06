QuestPrism.Sources = {}

-- Registry of guide sources (Zygor, RestedXP, BtWQuests, ...). A source provides the
-- quests of the guide the player follows, for a given scope:
--   "step"      -> the current step
--   "lookahead" -> the current step plus the next N
--   "guide"     -> the whole loaded guide
-- Adapter contract:
--   IsAvailable()                  -> bool   (addon loaded AND a guide active)
--   GetCacheKey()                  -> string (guide identity + current step)
--   GetStepNumber()                -> number|nil
--   GetQuestList(scope, lookahead) -> { { questID, step }, ... } | nil
--   Subscribe(callback)            -> called on step changes
--   label                          -> display name

local L = QuestPrism_L
local adapters = {}
local order = {}

function QuestPrism.Sources.Register(name, adapter)
    if not adapters[name] then table.insert(order, name) end
    adapters[name] = adapter
end

function QuestPrism.Sources.Get(name)
    return adapters[name]
end

function QuestPrism.Sources.Names()
    local copy = {}
    for i, name in ipairs(order) do copy[i] = name end
    return copy
end

function QuestPrism.Sources.GetLabel(name)
    local adapter = adapters[name]
    return (adapter and adapter.label) or name
end

-- Active adapter according to the settings, or nil when "Off" / unknown.
function QuestPrism.Sources.GetActive()
    local name = QuestPrism.Settings.Get("guideSource")
    if not name or name == "Off" then return nil, nil end
    local adapter = adapters[name]
    if not adapter then return nil, name end
    return adapter, name
end

-- True while the guide being followed draws its own arrow (Zygor, RestedXP). The guide
-- decides where the player is going, so QuestPrism leaves waypoint state alone.
function QuestPrism.Sources.GuideOwnsWaypoint()
    local adapter = QuestPrism.Sources.GetActive()
    return adapter ~= nil and adapter.ownsWaypoint == true
end

function QuestPrism.Sources.FirstAvailable()
    for _, name in ipairs(order) do
        local adapter = adapters[name]
        local ok, available = pcall(adapter.IsAvailable)
        if ok and available then return name end
    end
    return nil
end

-- Cache: recomputed when the source, scope, lookahead depth or the adapter's key
-- (guide/step) changes. The adapter provides an ORDERED LIST { { questID, step }, ... }
-- in guide order; the set is derived from it.
local cache = { key = nil, list = nil, set = nil }

function QuestPrism.Sources.Invalidate()
    cache.key, cache.list, cache.set = nil, nil, nil
end

local function refreshCache()
    local adapter, name = QuestPrism.Sources.GetActive()
    if not adapter then return false end
    local ok, available = pcall(adapter.IsAvailable)
    if not ok or not available then return false end
    local scope = QuestPrism.Settings.Get("guideScope") or "lookahead"
    local lookahead = tonumber(QuestPrism.Settings.Get("guideLookahead")) or 3
    local okKey, adapterKey = pcall(adapter.GetCacheKey)
    local key = table.concat({ name, scope, tostring(lookahead), okKey and tostring(adapterKey) or "?" }, "|")
    if cache.key == key then return true end
    local okList, list = pcall(adapter.GetQuestList, scope, lookahead)
    if not okList or type(list) ~= "table" then
        cache.key, cache.list, cache.set = key, nil, nil
        return true
    end
    local set = {}
    for _, item in ipairs(list) do
        local id = tonumber(item.questID)
        if id then set[id] = true end
    end
    cache.key, cache.list, cache.set = key, list, set
    return true
end

-- Ordered quest list of the guide (or nil when no source is available).
function QuestPrism.Sources.GetActiveQuestList()
    if not refreshCache() then return nil end
    return cache.list
end

-- Set { [questID] = true } (or nil when no source is available).
function QuestPrism.Sources.GetActiveQuestSet()
    if not refreshCache() then return nil end
    return cache.set
end

-- Called by adapters when the step changes. Guide addons fire this in bursts (Zygor:
-- once per skipped step while loading a guide, and on every update of its window):
-- a full refresh plus an objective-tracker rebuild each time multiplied the load
-- time. The cache is invalidated at once, but the refresh runs once per burst,
-- a little later.
local REFRESH_DELAY = 0.2
local refreshPending = false
local lastSeenKey = nil

-- "guide + step" key of the active source (nil when no source is available).
local function activeAdapterKey()
    local adapter, name = QuestPrism.Sources.GetActive()
    if not adapter then return nil end
    local ok, available = pcall(adapter.IsAvailable)
    if not ok or not available then return nil end
    local okKey, key = pcall(adapter.GetCacheKey)
    return name .. "|" .. (okKey and tostring(key) or "?")
end

function QuestPrism.Sources.NotifyChanged()
    -- Zygor also fires this from its window updates without the step moving: ignore
    -- any signal that changes neither the guide nor the step.
    local key = activeAdapterKey()
    if key == lastSeenKey then return end
    lastSeenKey = key
    QuestPrism.Sources.Invalidate()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        if QuestPrism.WorldMap and QuestPrism.WorldMap.Refresh then
            QuestPrism.WorldMap.Refresh()
        end
    end)
end

local function countSet(set)
    local n = 0
    for _ in pairs(set or {}) do n = n + 1 end
    return n
end

-- Status line of the settings window.
function QuestPrism.Sources.GetStatusText()
    local adapter, name = QuestPrism.Sources.GetActive()
    if not name then return L.GUIDE_STATUS_OFF end
    local label = QuestPrism.Sources.GetLabel(name)
    if not adapter then return string.format(L.GUIDE_STATUS_NOT_LOADED, label) end
    local ok, available = pcall(adapter.IsAvailable)
    if not ok or not available then return string.format(L.GUIDE_STATUS_NOT_LOADED, label) end
    local set = QuestPrism.Sources.GetActiveQuestSet()
    local okStep, step = pcall(adapter.GetStepNumber)
    return string.format(L.GUIDE_STATUS_ACTIVE, label, tonumber(okStep and step) or 0, countSet(set))
end

-- Names of the sources currently available (addon loaded + guide active).
function QuestPrism.Sources.AvailableNames()
    local names = {}
    for _, name in ipairs(order) do
        local ok, available = pcall(adapters[name].IsAvailable)
        if ok and available then names[#names + 1] = name end
    end
    return names
end

function QuestPrism.Sources.IsFollowing()
    local source = QuestPrism.Settings.Get("guideSource")
    return source ~= nil and source ~= "Off"
end

-- "Follow my guide": enables the last used source if available, otherwise the first
-- available one. Returns false (and tells the user) when none is.
function QuestPrism.Sources.SetFollowing(enabled)
    if not enabled then
        if QuestPrism.Sources.IsFollowing() then
            QuestPrism.Settings.Set("guideLastSource", QuestPrism.Settings.Get("guideSource"))
        end
        QuestPrism.Settings.Set("guideSource", "Off")
        return true
    end
    local available = QuestPrism.Sources.AvailableNames()
    local target = QuestPrism.Settings.Get("guideLastSource")
    local ok = false
    for _, name in ipairs(available) do if name == target then ok = true end end
    if not ok then target = available[1] end
    if not target then
        print(L.GUIDE_NO_SOURCE_MSG)
        return false
    end
    QuestPrism.Settings.Set("guideSource", target)
    QuestPrism.Settings.Set("guideLastSource", target)
    return true
end

-- Keybinding: toggle and refresh.
function QuestPrism.Sources.ToggleFollowing()
    QuestPrism.Sources.SetFollowing(not QuestPrism.Sources.IsFollowing())
    if QuestPrism.WorldMap and QuestPrism.WorldMap.Refresh then QuestPrism.WorldMap.Refresh() end
    if QuestPrism.Panel and QuestPrism.Panel.Sync then QuestPrism.Panel.Sync() end
end

function QuestPrism.Sources.Initialize()
    for _, name in ipairs(order) do
        local adapter = adapters[name]
        if type(adapter.Subscribe) == "function" then
            pcall(adapter.Subscribe, QuestPrism.Sources.NotifyChanged)
        end
    end
end
