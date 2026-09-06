QuestPrism.WorldQuests = {}

-- "Block world quests": everything world-quest related goes away while the option
-- is on. See docs/world-quests.md for the full survey. Four surfaces are handled here;
-- the world map pins are handled by Rules/Filter like any other pin.
--   * Map pins, Blizzard's way: the CVar questPOIWQ is the "World Quests" checkbox of
--     the map's tracking menu and governs the world map AND the flight map. It is set
--     to 0 while blocked and put back when the block is lifted, but only if it was on
--     when the block started (a player who had it off keeps it off). The pin path in
--     Hooks/WorldMap.lua stays as a fallback, notably for World Quest List's pins.
--   * The World Quests section of the objective tracker: the module's LayoutContents is
--     wrapped to lay out nothing. Blizzard's module Update then finds no contents and
--     hides the module, header included, exactly as when no world quest is tracked.
--   * The "World Quest" top banner that slides into the tracker when a world quest is
--     auto-accepted: ObjectiveTrackerTopBannerFrame.DisplayForQuest is wrapped to
--     answer false for world quests (the caller then simply marks its module dirty).
--   * The "World Quest Complete" alert: the alert queue's AddAlert is wrapped to swallow
--     world quest alerts while blocked, so nothing piles up in Blizzard's queue and
--     nothing is released later.
-- Minimap icons are drawn by the engine and have no filter for world quests.
--
-- Blizzard objects are found by global name, and the tracker module also by header
-- text among the modules registered on the tracker frame; the lookup is repeated on
-- every refresh so an object created after login is still caught. Wrapping happens
-- once per object; every wrapper checks the setting when it runs, so toggling never
-- needs to unwrap anything.

local TRACKER_MODULE_NAMES = { "WorldQuestObjectiveTracker" }
local ALERT_SYSTEM_NAMES = { "WorldQuestCompleteAlertSystem" }
local BANNER_FRAME_NAMES = { "ObjectiveTrackerTopBannerFrame" }
local MAP_CVAR = "questPOIWQ"

local wrappedModules = {} -- module -> original LayoutContents
local wrappedAlerts = {}  -- alert system -> original AddAlert
local wrappedBanners = {} -- banner frame -> original DisplayForQuest
local eventFrame          -- SUPER_TRACKING_CHANGED, for the waypoint rule

function QuestPrism.WorldQuests.IsBlocked()
    return QuestPrism.Settings.Get("HideWorldQuests") == true
end
local isBlocked = QuestPrism.WorldQuests.IsBlocked

-- ---------------------------------------------------------------------------
-- Objective tracker module
-- ---------------------------------------------------------------------------

local function wrapModule(module)
    if type(module) ~= "table" or wrappedModules[module] then return end
    local original = module.LayoutContents
    if type(original) ~= "function" then return end
    wrappedModules[module] = original
    module.LayoutContents = function(self, ...)
        if isBlocked() then return end
        return original(self, ...)
    end
end

local function worldQuestHeaderText()
    local text = _G.TRACKER_HEADER_WORLD_QUESTS
    return type(text) == "string" and text or nil
end

local function isWorldQuestModule(module, name)
    for _, wanted in ipairs(TRACKER_MODULE_NAMES) do
        if name == wanted then return true end
    end
    local header = worldQuestHeaderText()
    return header ~= nil and type(module) == "table" and module.headerText == header
end

-- Modules registered on the tracker frame, when Blizzard exposes the list.
local function trackerModules()
    local frame = _G.ObjectiveTrackerFrame
    local list = type(frame) == "table" and frame.modules
    if type(list) ~= "table" then return {} end
    return list
end

local function findAndWrapModules()
    for _, name in ipairs(TRACKER_MODULE_NAMES) do
        pcall(wrapModule, _G[name])
    end
    for _, module in ipairs(trackerModules()) do
        local ok, name = pcall(function() return module.GetName and module:GetName() end)
        if isWorldQuestModule(module, ok and name or nil) then
            pcall(wrapModule, module)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Top banner ("World Quest" title sliding into the tracker)
-- ---------------------------------------------------------------------------

-- The banner is shared with bonus objectives: only world quest banners are refused.
-- The module that asks carries showWorldQuests; the quest ID is the fallback.
local function isWorldQuestBanner(questID, module)
    if type(module) == "table" and module.showWorldQuests == true then return true end
    return QuestPrism.Filter.IsWorldQuest(questID)
end

local function wrapBanner(frame)
    if type(frame) ~= "table" or wrappedBanners[frame] then return end
    local original = frame.DisplayForQuest
    if type(original) ~= "function" then return end
    wrappedBanners[frame] = original
    frame.DisplayForQuest = function(self, questID, module, ...)
        if isBlocked() and isWorldQuestBanner(questID, module) then return false end
        return original(self, questID, module, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Completion alert
-- ---------------------------------------------------------------------------

local function wrapAlert(system)
    if type(system) ~= "table" or wrappedAlerts[system] then return end
    local original = system.AddAlert
    if type(original) ~= "function" then return end
    wrappedAlerts[system] = original
    system.AddAlert = function(self, ...)
        -- "true" tells the caller the alert was handled, so it is neither shown nor queued.
        if isBlocked() then return true end
        return original(self, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Map pins: Blizzard's own switch
-- ---------------------------------------------------------------------------

-- QuestPrismDB.worldQuestPinsWereShown remembers that the CVar was on when the block
-- started, so lifting the block puts it back. Nil means "nothing to restore".
local function syncMapCVar()
    if not (C_CVar and C_CVar.GetCVarBool and C_CVar.SetCVar) then return end
    if type(QuestPrismDB) ~= "table" then return end
    local ok, shown = pcall(C_CVar.GetCVarBool, MAP_CVAR)
    if not ok then return end
    if isBlocked() then
        if shown then
            QuestPrismDB.worldQuestPinsWereShown = true
            pcall(C_CVar.SetCVar, MAP_CVAR, "0")
        end
    elseif QuestPrismDB.worldQuestPinsWereShown then
        QuestPrismDB.worldQuestPinsWereShown = nil
        if not shown then
            pcall(C_CVar.SetCVar, MAP_CVAR, "1")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Waypoint arrow (optional, off by default)
-- ---------------------------------------------------------------------------

-- One rule, stated in the option's tooltip: while world quests are blocked AND the
-- option is on, a world quest is never super-tracked. Nothing else is ever cleared,
-- and with the option off a waypoint the player set survives the block.
-- A followed guide outranks the rule: Zygor and RestedXP drive their own arrow, so
-- while one of them is being followed QuestPrism does not touch waypoint state at all.
function QuestPrism.WorldQuests.ShouldClearWaypoint(questID)
    if not isBlocked() then return false end
    if QuestPrism.Settings.Get("clearWorldQuestWaypoint") ~= true then return false end
    if QuestPrism.Sources.GuideOwnsWaypoint() then return false end
    questID = tonumber(questID)
    if not questID or questID == 0 then return false end
    return QuestPrism.Filter.IsWorldQuest(questID)
end

local function enforceWaypoint()
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID) then return end
    local ok, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if not ok then return end
    if not QuestPrism.WorldQuests.ShouldClearWaypoint(questID) then return end
    pcall(C_SuperTrack.SetSuperTrackedQuestID, 0)
end
QuestPrism.WorldQuests.EnforceWaypoint = enforceWaypoint

-- The rule has to hold when the game starts super-tracking as well as when the block
-- or the option changes, so the event and the refresh path share it.
local function ensureEventFrame()
    if eventFrame or type(CreateFrame) ~= "function" then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")
    eventFrame:SetScript("OnEvent", function() pcall(enforceWaypoint) end)
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- Applies the current setting everywhere (called by QuestPrism.WorldMap.Refresh, the
-- "settings changed" entry point, and at login).
function QuestPrism.WorldQuests.Refresh()
    findAndWrapModules()
    for _, name in ipairs(BANNER_FRAME_NAMES) do pcall(wrapBanner, _G[name]) end
    for _, name in ipairs(ALERT_SYSTEM_NAMES) do pcall(wrapAlert, _G[name]) end
    for module in pairs(wrappedModules) do
        if type(module.MarkDirty) == "function" then
            pcall(module.MarkDirty, module)
        end
    end
    pcall(syncMapCVar)
    pcall(enforceWaypoint)
end

function QuestPrism.WorldQuests.Initialize()
    ensureEventFrame()
    QuestPrism.WorldQuests.Refresh()
end

-- Diagnostic (/questprism tracker): one line per tracker module with what QuestPrism
-- knows about it, plus the state of the other three surfaces.
function QuestPrism.WorldQuests.Inspect()
    local function field(t, k)
        local ok, v = pcall(function() return t[k] end)
        return ok and v or nil
    end
    local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
    local okCVar, cvar = pcall(function() return C_CVar.GetCVarBool(MAP_CVAR) end)
    print(string.format("|cff00ff00QuestPrism tracker:|r block=%s modulesWrapped=%d bannersWrapped=%d alertsWrapped=%d %s=%s restoreLater=%s",
        tostring(isBlocked()), count(wrappedModules), count(wrappedBanners), count(wrappedAlerts),
        MAP_CVAR, okCVar and tostring(cvar) or "?", tostring(QuestPrismDB and QuestPrismDB.worldQuestPinsWereShown)))
    local modules = trackerModules()
    if #modules == 0 then
        print("  no ObjectiveTrackerFrame.modules list; global WorldQuestObjectiveTracker=" .. tostring(_G.WorldQuestObjectiveTracker ~= nil))
    end
    for _, module in ipairs(modules) do
        local okName, name = pcall(function() return module:GetName() end)
        local okShown, shown = pcall(function() return module:IsShown() end)
        local header = field(module, "Header")
        local okText, headerShownText = pcall(function() return header.Text:GetText() end)
        local okHeaderShown, headerShown = pcall(function() return header:IsShown() end)
        print(string.format("  %s header=%q headerShown=%s shown=%s state=%s hasContents=%s wrapped=%s headerText=%s",
            tostring(okName and name or "?"), tostring(okText and headerShownText or "?"), okHeaderShown and tostring(headerShown) or "?",
            okShown and tostring(shown) or "?", tostring(field(module, "state")), tostring(field(module, "hasContents")),
            tostring(wrappedModules[module] ~= nil), tostring(field(module, "headerText"))))
    end
end
