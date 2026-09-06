QuestPrism.Settings = {}

local DEFAULTS = {
    Campaign     = true,
    Important    = true,
    Legendary    = true,
    Meta         = true,
    Repeatable   = true,
    LocalStory   = true,
    Expedition   = true,
    -- Trivial quests (low level, hidden by the game by default): off by default, like
    -- the game's own tracking filter. Drives the engine filter (map + minimap).
    Trivial      = false,
    -- Block world quests everywhere: map pins, the World Quests section of the
    -- objective tracker, completion alerts (Core/Rules.lua, Hooks/WorldQuests.lua).
    HideWorldQuests = false,
    debug        = false,
    -- Dim filtered pins (alpha) instead of hiding them. Per character.
    dimFiltered  = false,
    -- Guide source (Core/Sources.lua): "Off" or an adapter name. Per character, never in
    -- presets or account mode: the guide being followed depends on the character.
    guideSource     = "Off",
    guideScope      = "lookahead", -- "step" | "lookahead" | "guide"
    guideLookahead  = 3,
    -- Apply the filters (types + guide) to the objective tracker too. Per character.
    trackerFilter   = true,
    -- While World Quests is unticked, never super-track a world quest, so the waypoint
    -- arrow stops pointing at one (Hooks/WorldQuests.lua). Off: a waypoint you set
    -- yourself survives the block. Per character.
    clearWorldQuestWaypoint = false,
    -- Also show the guide's source and scope in the settings window, not only on the
    -- QuestPrism map tab (UI/Panel.lua). Per character.
    guideControlsInWindow   = false,
}

-- The type toggles: what "Show all", "Hide all" and solo mode operate on.
local FILTER_KEYS = { "Campaign", "Important", "Legendary", "Meta", "Repeatable", "LocalStory", "Expedition", "Trivial" }

-- The filter keys (type toggles + the world quest block): the only ones that follow
-- the account-wide mode and get saved in presets. Everything else (debug, minimap,
-- window position) stays per character.
local SCOPED_KEYS = {}
for _, k in ipairs(FILTER_KEYS) do SCOPED_KEYS[k] = true end
SCOPED_KEYS.HideWorldQuests = true

-- Built-in presets: read-only filter setups listed before the saved ones. "shown" lists
-- the rows that are ticked; every other type is off and "WorldQuest" stands for the
-- world quest row (absent = blocked).
local L = QuestPrism_L
local BUILTIN_PRESETS = {
    { name = L.PRESET_LEVELING,      shown = { "Campaign", "Important", "LocalStory" } },
    { name = L.PRESET_CAMPAIGN_ONLY, shown = { "Campaign", "Important", "Legendary" } },
    { name = L.PRESET_ENDGAME,       shown = { "Campaign", "Important", "Legendary", "Meta", "Repeatable", "Expedition", "WorldQuest" } },
    { name = L.PRESET_WEEKLY,        shown = { "Meta", "Repeatable", "Expedition", "WorldQuest" } },
}

local function builtInSnapshot(preset)
    local shown = {}
    for _, key in ipairs(preset.shown) do shown[key] = true end
    local snapshot = {}
    for _, k in ipairs(FILTER_KEYS) do snapshot[k] = shown[k] == true end
    snapshot.HideWorldQuests = not shown.WorldQuest
    return snapshot
end

local function findBuiltIn(name)
    if type(name) ~= "string" then return nil end
    local lower = name:lower()
    for _, preset in ipairs(BUILTIN_PRESETS) do
        if preset.name:lower() == lower then return preset end
    end
    return nil
end

-- A saved preset that shares a built-in's name (saved before the built-ins existed)
-- would be shadowed: renamed with a suffix so it stays reachable and deletable.
local function renameShadowedPresets()
    local presets = QuestPrismDB and QuestPrismDB.presets
    if type(presets) ~= "table" then return end
    local shadowed = {}
    for name in pairs(presets) do
        if findBuiltIn(name) then shadowed[#shadowed + 1] = name end
    end
    for _, name in ipairs(shadowed) do
        local renamed = name .. L.PRESET_RENAMED_SUFFIX
        while presets[renamed] do renamed = renamed .. L.PRESET_RENAMED_SUFFIX end
        presets[renamed] = presets[name]
        presets[name] = nil
        for _, store in ipairs({ QuestPrismCharDB, QuestPrismDB.filters }) do
            if type(store) == "table" and store.activePreset == name then store.activePreset = renamed end
        end
    end
end

-- Keys of a removed option, dropped from every store they may still sit in.
local RETIRED_KEY_PATTERN = "^HideWarbandCompleted"

local function dropRetiredKeys(store)
    if type(store) ~= "table" then return end
    for k in pairs(store) do
        if type(k) == "string" and k:find(RETIRED_KEY_PATTERN) then store[k] = nil end
    end
end

local function ensureAccountDB()
    if not QuestPrismDB then
        QuestPrismDB = {}
    end
    return QuestPrismDB
end

-- Table holding the active filters: QuestPrismDB.filters in account mode,
-- QuestPrismCharDB otherwise.
local function filterStore()
    if QuestPrismDB and QuestPrismDB.useAccountFilters and QuestPrismDB.filters then
        return QuestPrismDB.filters
    end
    return QuestPrismCharDB
end

function QuestPrism.Settings.Initialize()
    local freshInstall = (QuestPrismCharDB == nil)
    if not QuestPrismCharDB then
        QuestPrismCharDB = {}
    end
    ensureAccountDB()
    dropRetiredKeys(QuestPrismCharDB)
    dropRetiredKeys(QuestPrismDB.filters)
    if type(QuestPrismDB.presets) == "table" then
        for _, preset in pairs(QuestPrismDB.presets) do dropRetiredKeys(preset) end
    end
    for k, v in pairs(DEFAULTS) do
        if QuestPrismCharDB[k] == nil then
            QuestPrismCharDB[k] = v
        end
    end
    -- LibDBIcon state table (hide, minimapPos, showInCompartment).
    QuestPrismCharDB.minimap = QuestPrismCharDB.minimap or { hide = false }
    if QuestPrismCharDB.minimap.hide == nil then
        -- Fresh install: the world map button is the main entry point; the minimap
        -- button stays available from Options.
        QuestPrismCharDB.minimap.hide = freshInstall
    end
    -- The window's sections no longer collapse and the first-run popup is gone
    -- (beta3); drop their saved state.
    QuestPrismCharDB.collapsed = nil
    QuestPrismDB.lastSeenVersion = nil
    renameShadowedPresets()
end

function QuestPrism.Settings.Get(key)
    if SCOPED_KEYS[key] then
        local value = filterStore()[key]
        if value == nil then value = DEFAULTS[key] end
        return value
    end
    return QuestPrismCharDB[key]
end

-- Solo mode (click a type's name or right-click its checkbox): show a single type
-- and nothing else, world quests included, remembering the previous filters so a
-- second solo restores them. In-memory snapshot only (not saved). Any manual
-- filter change ends solo mode without restoring.
local soloState = nil -- { key = "Campaign", snapshot = { scopedKey -> boolean } }

local function writeFilter(key, value)
    if SCOPED_KEYS[key] then
        filterStore()[key] = value
    else
        QuestPrismCharDB[key] = value
    end
end

function QuestPrism.Settings.Set(key, value)
    if SCOPED_KEYS[key] then
        soloState = nil
    end
    writeFilter(key, value)
end

function QuestPrism.Settings.IsSoloed(key)
    return soloState ~= nil and soloState.key == key
end

-- Returns true if the type is now soloed, false if the previous filters were just restored.
function QuestPrism.Settings.Solo(key)
    if soloState and soloState.key == key then
        local snapshot = soloState.snapshot
        soloState = nil
        for k, v in pairs(snapshot) do
            writeFilter(k, v)
        end
        return false
    end
    local snapshot = soloState and soloState.snapshot
    if not snapshot then
        snapshot = {}
        for k in pairs(SCOPED_KEYS) do
            snapshot[k] = QuestPrism.Settings.Get(k)
        end
    end
    for _, k in ipairs(FILTER_KEYS) do
        writeFilter(k, k == key)
    end
    writeFilter("HideWorldQuests", true)
    soloState = { key = key, snapshot = snapshot }
    return true
end

-- Account-wide mode: the filters are shared by every character.
function QuestPrism.Settings.IsAccountWide()
    return (QuestPrismDB and QuestPrismDB.useAccountFilters == true) or false
end

function QuestPrism.Settings.SetAccountWide(enabled)
    local db = ensureAccountDB()
    enabled = enabled and true or false
    if enabled and not db.filters then
        -- First activation: start from the current character's settings.
        db.filters = {}
        for k in pairs(SCOPED_KEYS) do
            local v = QuestPrismCharDB[k]
            if v == nil then v = DEFAULTS[k] end
            db.filters[k] = v
        end
        db.filters.activePreset = QuestPrismCharDB.activePreset
    end
    db.useAccountFilters = enabled
end

function QuestPrism.Settings.Reset()
    for _, k in ipairs(FILTER_KEYS) do
        QuestPrism.Settings.Set(k, true)
    end
    -- "Show all" also lifts the world quest block and leaves no preset active.
    QuestPrism.Settings.Set("HideWorldQuests", false)
    local store = filterStore()
    if store then store.activePreset = nil end
end

-- "Hide all" / "None": every row in the list, world quests included.
function QuestPrism.Settings.HideAll()
    for _, k in ipairs(FILTER_KEYS) do
        QuestPrism.Settings.Set(k, false)
    end
    QuestPrism.Settings.Set("HideWorldQuests", true)
end

function QuestPrism.Settings.ToggleDebug()
    QuestPrismCharDB.debug = not QuestPrismCharDB.debug
    local state = QuestPrismCharDB.debug and QuestPrism_L.DEBUG_ON or QuestPrism_L.DEBUG_OFF
    print("|cff00ff00QuestPrism:|r Debug " .. state)
end

-- Named presets: filter configurations saved at the account level (QuestPrismDB)
-- so they can be recalled on any character.

local function normalizePresetName(name)
    if type(name) ~= "string" then return nil end
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed == "" then return nil end
    return trimmed
end
QuestPrism.Settings.NormalizePresetName = normalizePresetName

local function ensurePresetsTable()
    local db = ensureAccountDB()
    if not db.presets then
        db.presets = {}
    end
    return db.presets
end

function QuestPrism.Settings.ListBuiltInPresetNames()
    local names = {}
    for i, preset in ipairs(BUILTIN_PRESETS) do names[i] = preset.name end
    return names
end

function QuestPrism.Settings.IsBuiltInPreset(name)
    return findBuiltIn(name) ~= nil
end

-- Copy of a preset's filter values: built-in first, then saved. nil if unknown.
function QuestPrism.Settings.GetPresetSnapshot(name)
    local builtIn = findBuiltIn(name)
    if builtIn then return builtInSnapshot(builtIn) end
    local saved = QuestPrismDB and QuestPrismDB.presets and QuestPrismDB.presets[name]
    if not saved then return nil end
    local copy = {}
    for k, v in pairs(saved) do copy[k] = v end
    return copy
end

-- Captures only the filter keys (never window/minimap/debug). Returns true when
-- saved; false for an empty or built-in name.
function QuestPrism.Settings.SavePreset(name)
    name = normalizePresetName(name)
    if not name or findBuiltIn(name) then return false end
    local presets = ensurePresetsTable()
    local snapshot = {}
    for k in pairs(SCOPED_KEYS) do
        snapshot[k] = QuestPrism.Settings.Get(k)
    end
    presets[name] = snapshot
    filterStore().activePreset = name
    return true
end

function QuestPrism.Settings.LoadPreset(name)
    local snapshot = QuestPrism.Settings.GetPresetSnapshot(name)
    if not snapshot then return end
    -- A preset is a complete setup: keys it predates fall back to their defaults.
    for k in pairs(SCOPED_KEYS) do
        local v = snapshot[k]
        if v == nil then v = DEFAULTS[k] end
        QuestPrism.Settings.Set(k, v)
    end
    local builtIn = findBuiltIn(name)
    filterStore().activePreset = builtIn and builtIn.name or name
end

function QuestPrism.Settings.DeletePreset(name)
    if findBuiltIn(name) then return end
    if not (QuestPrismDB and QuestPrismDB.presets) then return end
    QuestPrismDB.presets[name] = nil
    local store = filterStore()
    if store and store.activePreset == name then store.activePreset = nil end
end

-- True when any filter row differs from the active preset. A saved preset that
-- predates a key compares against that key's default.
function QuestPrism.Settings.IsActivePresetModified()
    local name = QuestPrism.Settings.GetActivePresetName()
    if not name then return false end
    local snapshot = QuestPrism.Settings.GetPresetSnapshot(name)
    if not snapshot then return false end
    for k in pairs(SCOPED_KEYS) do
        local expected = snapshot[k]
        if expected == nil then expected = DEFAULTS[k] end
        if QuestPrism.Settings.Get(k) ~= expected then return true end
    end
    return false
end

function QuestPrism.Settings.ListPresetNames()
    local names = {}
    if QuestPrismDB and QuestPrismDB.presets then
        for presetName in pairs(QuestPrismDB.presets) do
            table.insert(names, presetName)
        end
    end
    table.sort(names)
    return names
end

-- Returns the active preset only if it still exists (a saved one may have been
-- deleted from another character): the check lives here so the UI does not have
-- to duplicate it.
function QuestPrism.Settings.GetActivePresetName()
    local store = filterStore()
    local name = store and store.activePreset
    if not name then return nil end
    if findBuiltIn(name) then return name end
    if QuestPrismDB and QuestPrismDB.presets and QuestPrismDB.presets[name] then
        return name
    end
    return nil
end
