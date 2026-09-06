QuestPrism.QuickMenu = {}

-- Context menu (right-click on the minimap button or the world map button):
-- Follow my guide, a Quest types submenu (one checkbox per type plus World Quests,
-- ticked = shown), a Presets submenu (built-in then saved), then Show all /
-- Hide all / Open the window.
-- Relies on Blizzard's menu system (MenuUtil, 11.0+); without it, falls back to
-- opening the window.

local L = QuestPrism_L

local function questTypes()
    return (QuestPrism.Panel and QuestPrism.Panel.QUEST_TYPES) or {}
end

local function afterChange()
    QuestPrism.WorldMap.Refresh()
    if QuestPrism.Panel and QuestPrism.Panel.Sync then
        QuestPrism.Panel.Sync()
    end
    if QuestPrism.GuideTab and QuestPrism.GuideTab.Sync then
        QuestPrism.GuideTab.Sync()
    end
end

local function isShown(key)
    return QuestPrism.Settings.Get(key) == true
end

local function toggleShown(key)
    QuestPrism.Settings.Set(key, not isShown(key))
    afterChange()
end

-- "Follow my guide": toggles the guide source between Off and the last used one (or
-- the first available). Without an active guide addon, a chat message.
local function isFollowing()
    return QuestPrism.Sources.IsFollowing()
end

local function toggleFollowing()
    if QuestPrism.Sources.SetFollowing(not isFollowing()) then
        afterChange()
    end
end

local function isWorldQuestsShown()
    return QuestPrism.Settings.Get("HideWorldQuests") ~= true
end

local function toggleWorldQuests()
    QuestPrism.Settings.Set("HideWorldQuests", isWorldQuestsShown())
    afterChange()
end

local function isActivePreset(name)
    return QuestPrism.Settings.GetActivePresetName() == name
end

local function applyPreset(name)
    QuestPrism.Settings.LoadPreset(name)
    afterChange()
end

-- "Campaign (3)" when QuestPrism hides 3 pins of that type on the current map.
local function labelWithCount(questType, counts)
    local n = counts and counts[questType.key]
    if n and n > 0 then
        return string.format("%s (%d)", questType.label, n)
    end
    return questType.label
end

local function buildMenu(_, rootDescription)
    rootDescription:CreateTitle("QuestPrism")
    rootDescription:CreateCheckbox(L.FOLLOW_GUIDE_LABEL, isFollowing, toggleFollowing)
    -- The nine rows in a submenu: the common actions stay one click away.
    local counts = QuestPrism.WorldMap.GetHiddenCounts and QuestPrism.WorldMap.GetHiddenCounts() or nil
    local types = rootDescription:CreateButton(L.MENU_TYPES)
    if types and type(types.CreateCheckbox) == "function" then
        for _, questType in ipairs(questTypes()) do
            types:CreateCheckbox(labelWithCount(questType, counts), isShown, toggleShown, questType.key)
        end
        types:CreateCheckbox(L.QUEST_WORLD_QUESTS, isWorldQuestsShown, toggleWorldQuests)
    end
    local presets = rootDescription:CreateButton(L.MENU_PRESETS)
    if presets and type(presets.CreateRadio) == "function" then
        for _, name in ipairs(QuestPrism.Settings.ListBuiltInPresetNames()) do
            presets:CreateRadio(name, isActivePreset, applyPreset, name)
        end
        local saved = QuestPrism.Settings.ListPresetNames()
        if #saved > 0 then
            if type(presets.CreateDivider) == "function" then presets:CreateDivider() end
            for _, name in ipairs(saved) do
                presets:CreateRadio(name, isActivePreset, applyPreset, name)
            end
        end
    end
    rootDescription:CreateDivider()
    rootDescription:CreateButton(L.MENU_SHOW_ALL, function()
        QuestPrism.Settings.Reset()
        afterChange()
    end)
    rootDescription:CreateButton(L.MENU_HIDE_ALL, function()
        QuestPrism.Settings.HideAll()
        afterChange()
    end)
    rootDescription:CreateButton(L.MENU_OPEN_PANEL, function()
        QuestPrism.Panel.Toggle()
    end)
end

function QuestPrism.QuickMenu.Open(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, buildMenu)
    else
        QuestPrism.Panel.Toggle()
    end
end
