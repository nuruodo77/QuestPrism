QuestPrism.Options = {}

-- "QuestPrism" page under Escape > Options > AddOns (Settings API, 11.0+): a button
-- to open the window plus the addon-level switches (minimap button, debug, shared
-- filters). The quest filters themselves live in the window only.
-- The checkboxes are proxies: their values live in our SavedVariables and every
-- change triggers the intended side effects (map refresh, settings window sync).

local L = QuestPrism_L
local category

local function refreshPanelIfBuilt()
    if QuestPrism.Panel and QuestPrism.Panel.Sync then
        QuestPrism.Panel.Sync()
    end
end

local function addCheckbox(variable, name, tooltip, default, getter, setter)
    local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, name, default, getter, setter)
    Settings.CreateCheckbox(category, setting, tooltip)
    return setting
end

function QuestPrism.Options.Initialize()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        return
    end
    local ok, err = pcall(function()
        local layout
        category, layout = Settings.RegisterVerticalLayoutCategory("QuestPrism")
        if not layout and SettingsPanel and SettingsPanel.GetLayout then
            layout = SettingsPanel:GetLayout(category)
        end

        if layout and CreateSettingsButtonInitializer then
            local addSearchTags = true
            layout:AddInitializer(CreateSettingsButtonInitializer(
                L.OPTIONS_OPEN_PANEL, L.OPTIONS_OPEN_PANEL_BUTTON,
                function() QuestPrism.Panel.Toggle() end,
                L.OPTIONS_OPEN_PANEL_TOOLTIP, addSearchTags))
        end

        addCheckbox("QuestPrism_AccountWide", L.OPTIONS_ACCOUNT_WIDE, L.OPTIONS_ACCOUNT_WIDE_TOOLTIP, false,
            function() return QuestPrism.Settings.IsAccountWide() end,
            function(value)
                QuestPrism.Settings.SetAccountWide(value)
                QuestPrism.WorldMap.Refresh()
                refreshPanelIfBuilt()
            end)

        -- Ticked = the button is shown (same polarity as the window's Addon section).
        -- New variable name for the new meaning; the default matches a fresh install,
        -- where the button starts hidden.
        addCheckbox("QuestPrism_ShowMinimap", L.MINIMAP_BUTTON_LABEL, L.OPTIONS_HIDE_MINIMAP_TOOLTIP, false,
            function() return not QuestPrism.MinimapButton.IsHidden() end,
            function(value)
                QuestPrism.MinimapButton.SetHidden(not value)
                refreshPanelIfBuilt()
            end)

        addCheckbox("QuestPrism_Debug", L.DEBUG_LABEL, L.OPTIONS_DEBUG_TOOLTIP, false,
            function() return QuestPrism.Settings.Get("debug") == true end,
            function(value) QuestPrism.Settings.Set("debug", value and true or false) end)

        Settings.RegisterAddOnCategory(category)
    end)
    if not ok then
        category = nil
        print("|cff00ff00QuestPrism:|r options page unavailable: " .. tostring(err))
    end
end

function QuestPrism.Options.Open()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        QuestPrism.Panel.Toggle()
    end
end
