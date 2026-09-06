-- Load-order / wiring smoke test for the UI files that the core harness skips.
-- Uses the real LibStub, CallbackHandler, LibDataBroker and LibDBIcon; stubs the
-- Blizzard Settings API and the pieces of the Minimap LibDBIcon touches.
bootCore()

-- Minimap + globals LibDBIcon needs
Minimap = MOCK.newFrame({ GetWidth = function() return 140 end, GetHeight = function() return 140 end })
Minimap.GetZoom = function() return 0 end
MinimapCluster = MOCK.newFrame()
UIParent = MOCK.newFrame()
GameTooltip = MOCK.newFrame({ SetOwner = function() end, AddLine = function() end, ClearLines = function() end })
AddonCompartmentFrame = nil
GetCursorPosition = function() return 0, 0 end
GetMinimapShape = nil
strsplit = function(sep, s) local t = {} for part in string.gmatch(s, "[^" .. sep .. "]+") do t[#t + 1] = part end return unpack(t) end
CreateFramePool = nil
C_Timer.NewTicker = function() return { Cancel = function() end } end
Mixin = function(t, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do t[k] = v end end return t end
SetCVar, GetCVar = function() end, function() return "0" end

-- Permissive frame stub for this file only: LibDBIcon's internals call many
-- widget methods that are irrelevant here, so any unknown method is a no-op that
-- returns another stub frame. Known fields (parent, shown, ...) still behave.
local frameMT = getmetatable(MOCK.newFrame())
setmetatable(frameMT, { __index = function(_, key)
    if type(key) == "string" and key:match("^[A-Z]") then
        return function() return MOCK.newFrame() end
    end
    return nil
end })
frameMT.GetVertexColor = function() return 1, 1, 1, 1 end
frameMT.GetEffectiveScale = function() return 1 end
frameMT.GetCenter = function() return 0, 0 end
frameMT.GetName = function(self) return self.name end
frameMT.SetParent = function(self, p) self.parent = p end
frameMT.IsDragging = function() return false end
frameMT.IsMouseOver = function() return false end
frameMT.HookScript = function(self, name, fn) local old = self.scripts[name]; self.scripts[name] = function(...) if old then old(...) end fn(...) end end
frameMT.SetChecked = function(self, v) self.checked = v and true or false end
frameMT.GetChecked = function(self) return self.checked == true end
frameMT.SetText = function(self, t) self.text = t end
frameMT.GetText = function(self) return self.text end
frameMT.SetEnabled = function(self, v) self.enabled = v and true or false end
frameMT.IsEnabled = function(self) return self.enabled ~= false end

LOAD_ADDON_FILE("libs/LibStub.lua")
LOAD_ADDON_FILE("libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
LOAD_ADDON_FILE("libs/LibDataBroker-1.1/LibDataBroker-1.1.lua")

test("LibDBIcon loads under the mock", function()
    LOAD_ADDON_FILE("libs/LibDBIcon-1.0/LibDBIcon-1.0.lua")
    assertTrue(LibStub("LibDBIcon-1.0") ~= nil)
end)

test("MinimapButton.lua loads and registers a launcher", function()
    LOAD_ADDON_FILE("UI/MinimapButton.lua")
    assertTrue(LibStub("LibDataBroker-1.1"):GetDataObjectByName("QuestPrism") ~= nil)
end)

test("MinimapButton.Initialize registers with LibDBIcon using the migrated table", function()
    QuestPrismCharDB.minimap = { hide = false, minimapPos = 200 }
    local ok, err = pcall(QuestPrism.MinimapButton.Initialize)
    assertTrue(ok, tostring(err))
    assertTrue(LibStub("LibDBIcon-1.0"):IsRegistered("QuestPrism"))
    QuestPrism.MinimapButton.SetHidden(true)
    assertEq(QuestPrismCharDB.minimap.hide, true)
    QuestPrism.MinimapButton.SetHidden(false)
    assertEq(QuestPrismCharDB.minimap.hide, false)
end)

-- Blizzard Settings API stub: records what Options.lua registers
local registered = { settings = {}, initializers = 0, categoryRegistered = false }
Settings = {
    VarType = { Boolean = "boolean" },
    RegisterVerticalLayoutCategory = function(name)
        local category = { name = name, GetID = function() return 42 end }
        local layout = { AddInitializer = function() registered.initializers = registered.initializers + 1 end }
        return category, layout
    end,
    RegisterProxySetting = function(category, variable, varType, name, default, getter, setter)
        local s = { variable = variable, getter = getter, setter = setter }
        registered.settings[variable] = s
        return s
    end,
    CreateCheckbox = function() end,
    RegisterAddOnCategory = function() registered.categoryRegistered = true end,
    OpenToCategory = function(id) registered.openedTo = id end,
}
CreateSettingsButtonInitializer = function(name, buttonText, click, tooltip, addSearchTags)
    assertTrue(addSearchTags ~= nil, "addSearchTags must not be nil (Blizzard asserts)")
    return { click = click }
end

test("Options.lua loads and registers the category, button, and three checkboxes", function()
    LOAD_ADDON_FILE("UI/Options.lua")
    MOCK.printed = {}
    QuestPrism.Options.Initialize()
    assertEq(#MOCK.printed, 0, "no error printed: " .. table.concat(MOCK.printed, " | "))
    assertTrue(registered.categoryRegistered, "category registered")
    assertEq(registered.initializers, 1, "button initializer")
    assertTrue(registered.settings.QuestPrism_AccountWide ~= nil)
    assertTrue(registered.settings.QuestPrism_ShowMinimap ~= nil)
    assertTrue(registered.settings.QuestPrism_Debug ~= nil)
    local n = 0
    for _ in pairs(registered.settings) do n = n + 1 end
    assertEq(n, 3, "the filter switches are no longer duplicated on the Escape page")
end)

test("Escape page minimap checkbox means 'shown' (inverted hide flag)", function()
    QuestPrismCharDB.minimap.hide = false
    assertEq(registered.settings.QuestPrism_ShowMinimap.getter(), true, "shown -> ticked")
    registered.settings.QuestPrism_ShowMinimap.setter(false)
    assertEq(QuestPrismCharDB.minimap.hide, true, "unticked -> hidden")
    registered.settings.QuestPrism_ShowMinimap.setter(true)
    assertEq(QuestPrismCharDB.minimap.hide, false)
end)

test("account-wide proxy setter routes through Settings and refreshes", function()
    QuestPrism.Panel = QuestPrism.Panel or {}
    local synced = false
    QuestPrism.Panel.Sync = function() synced = true end
    registered.settings.QuestPrism_AccountWide.setter(true)
    assertTrue(QuestPrism.Settings.IsAccountWide())
    assertTrue(synced, "panel synced")
    assertEq(registered.settings.QuestPrism_AccountWide.getter(), true)
    registered.settings.QuestPrism_AccountWide.setter(false)
end)

test("Options.Open opens the registered category", function()
    QuestPrism.Options.Open()
    assertEq(registered.openedTo, 42)
end)

test("locales define every key the code references", function()
    local missing = {}
    for _, rel in ipairs({ "QuestPrism.lua", "Core/Settings.lua", "Core/Filter.lua", "Hooks/WorldMap.lua", "UI/MinimapButton.lua", "UI/Options.lua", "UI/Panel.lua", "UI/QuickMenu.lua", "Hooks/Minimap.lua", "Hooks/ObjectiveTracker.lua", "Hooks/WorldQuests.lua", "UI/GuideTab.lua", "Core/Sources.lua", "Core/Rules.lua", "Sources/Zygor.lua", "Sources/RXP.lua", "Sources/BtWQuests.lua" }) do
        local f = io.open(ADDON_PATH .. rel, "r")
        local src = f:read("*a"); f:close()
        for key in src:gmatch("QuestPrism_L%.([A-Z_]+)") do
            if QuestPrism_L[key] == nil then missing[key] = true end
        end
        if src:find("local L = QuestPrism_L", 1, true) then
            for key in src:gmatch("[^%w_]L%.([A-Z_]+)") do
                if QuestPrism_L[key] == nil then missing[key] = true end
            end
        end
    end
    local list = {}
    for k in pairs(missing) do list[#list + 1] = k end
    assertEq(#list, 0, "missing locale keys: " .. table.concat(list, ", "))
end)


-- Quick menu: Blizzard MenuUtil stub that records what the generator builds
local menu = {}
MenuUtil = {
    CreateContextMenu = function(owner, generator)
        menu = { owner = owner, checkboxes = {}, buttons = {}, subs = {}, radios = {}, dividers = 0, titles = 0 }
        local root = {
            CreateTitle = function(_, text) menu.titles = menu.titles + 1 end,
            CreateCheckbox = function(_, text, isSelected, setSelected, data)
                table.insert(menu.checkboxes, { text = text, isSelected = isSelected, setSelected = setSelected, data = data })
            end,
            CreateDivider = function() menu.dividers = menu.dividers + 1 end,
            CreateRadio = function(_, text, isSelected, setSelected, data)
                table.insert(menu.radios, { text = text, isSelected = isSelected, setSelected = setSelected, data = data })
            end,
            CreateButton = function(_, text, fn)
                local sub = { text = text, fn = fn, checkboxes = {}, radios = {}, dividers = 0 }
                sub.CreateCheckbox = function(_, t, isSelected, setSelected, data)
                    table.insert(sub.checkboxes, { text = t, isSelected = isSelected, setSelected = setSelected, data = data })
                end
                sub.CreateRadio = function(_, t, isSelected, setSelected, data)
                    table.insert(sub.radios, { text = t, isSelected = isSelected, setSelected = setSelected, data = data })
                end
                sub.CreateDivider = function() sub.dividers = sub.dividers + 1 end
                table.insert(menu.buttons, sub)
                if not fn then menu.subs[text] = sub end
                return sub
            end,
        }
        generator(owner, root)
    end,
}
QuestPrism.Panel.QUEST_TYPES = {
    { key = "Campaign" }, { key = "Important" }, { key = "Legendary" }, { key = "Meta" },
    { key = "Repeatable" }, { key = "LocalStory" }, { key = "Expedition" }, { key = "Trivial" },
}
for _, qt in ipairs(QuestPrism.Panel.QUEST_TYPES) do qt.label = qt.key end
QuestPrism.Panel.Toggle = function() menu.panelToggled = true end

test("QuickMenu: follow checkbox, types and presets submenus, three actions", function()
    LOAD_ADDON_FILE("UI/QuickMenu.lua")
    QuestPrism.QuickMenu.Open("owner")
    assertEq(#menu.checkboxes, 1, "top level: Follow my guide only"); assertEq(#menu.buttons, 5, "2 submenus + 3 actions")
    local types = menu.subs[QuestPrism_L.MENU_TYPES]
    assertEq(#types.checkboxes, 9, "8 types + World Quests in the submenu")
    assertEq(types.checkboxes[9].text, QuestPrism_L.QUEST_WORLD_QUESTS)
    local presets = menu.subs[QuestPrism_L.MENU_PRESETS]
    assertEq(#presets.radios, 4, "built-in presets as radios")
    assertEq(menu.dividers, 1); assertEq(menu.titles, 1)
end)

test("QuickMenu World Quests entry is ticked when shown and flips the block", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    QuestPrism.Settings.Set("HideWorldQuests", false)
    local wq = menu.subs[QuestPrism_L.MENU_TYPES].checkboxes[9]
    assertEq(wq.isSelected(), true, "shown -> ticked")
    wq.setSelected()
    assertEq(QuestPrism.Settings.Get("HideWorldQuests"), true)
    assertEq(wq.isSelected(), false)
    wq.setSelected()
    assertEq(QuestPrism.Settings.Get("HideWorldQuests"), false)
    QuestPrism.WorldMap.Refresh = orig
end)

test("QuickMenu presets submenu applies a preset and lists saved ones after a divider", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    QuestPrism.Settings.Reset()
    QuestPrism.Settings.SavePreset("Mine"); QuestPrism.Settings.Reset()
    QuestPrism.QuickMenu.Open("owner")
    local presets = menu.subs[QuestPrism_L.MENU_PRESETS]
    assertEq(#presets.radios, 5, "4 built-in + 1 saved"); assertEq(presets.dividers, 1)
    assertEq(presets.radios[1].isSelected(presets.radios[1].data), false)
    presets.radios[1].setSelected(presets.radios[1].data) -- Leveling
    assertEq(QuestPrism.Settings.GetActivePresetName(), "Leveling")
    assertEq(QuestPrism.Settings.Get("Meta"), false)
    assertEq(presets.radios[1].isSelected(presets.radios[1].data), true)
    QuestPrism.Settings.DeletePreset("Mine"); QuestPrism.Settings.Reset()
    QuestPrism.WorldMap.Refresh = orig
end)

test("QuickMenu 'Guide only' toggles the source and remembers the last one", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    QuestPrism.Settings.Set("guideSource", "Off"); QuestPrism.Settings.Set("guideLastSource", nil)
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "t", steps = { { goals = {} } } }, AddMessageHandler = function() end }
    local guideCb = menu.checkboxes[1]
    assertEq(guideCb.isSelected(), false)
    guideCb.setSelected(); assertEq(QuestPrism.Settings.Get("guideSource"), "Zygor", "first available source")
    guideCb.setSelected(); assertEq(QuestPrism.Settings.Get("guideSource"), "Off")
    assertEq(QuestPrism.Settings.Get("guideLastSource"), "Zygor", "remembered")
    ZGV = nil; MOCK.printed = {}
    QuestPrism.Settings.Set("guideLastSource", nil)
    guideCb.setSelected()
    assertEq(QuestPrism.Settings.Get("guideSource"), "Off", "no source available -> stays off")
    assertEq(#MOCK.printed, 1, "message printed")
    QuestPrism.WorldMap.Refresh = orig
end)

test("QuickMenu checkbox reflects and flips the setting, refreshing the map", function()
    local refreshed = false
    local orig = QuestPrism.WorldMap.Refresh
    QuestPrism.WorldMap.Refresh = function() refreshed = true end
    QuestPrism.Settings.Set("Campaign", true)
    local cb = menu.subs[QuestPrism_L.MENU_TYPES].checkboxes[1]
    assertEq(cb.isSelected(cb.data), true)
    cb.setSelected(cb.data)
    assertEq(QuestPrism.Settings.Get("Campaign"), false)
    assertTrue(refreshed, "Refresh called")
    QuestPrism.WorldMap.Refresh = orig
    QuestPrism.Settings.Set("Campaign", true)
end)

test("QuickMenu Hide all clears every type including Trivial; Show all resets", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    menu.buttons[4].fn() -- Hide all
    for _, qt in ipairs(QuestPrism.Panel.QUEST_TYPES) do assertEq(QuestPrism.Settings.Get(qt.key), false, qt.key) end
    menu.buttons[3].fn() -- Show all
    for _, qt in ipairs(QuestPrism.Panel.QUEST_TYPES) do assertEq(QuestPrism.Settings.Get(qt.key), true, qt.key) end
    menu.panelToggled = false; menu.buttons[5].fn(); assertTrue(menu.panelToggled)
    QuestPrism.WorldMap.Refresh = orig
end)

test("right-click on the minimap launcher opens the quick menu", function()
    local opened
    local origOpen = QuestPrism.QuickMenu.Open
    QuestPrism.QuickMenu.Open = function(owner) opened = owner end
    local obj = LibStub("LibDataBroker-1.1"):GetDataObjectByName("QuestPrism")
    obj.OnClick("theButton", "RightButton")
    assertEq(opened, "theButton")
    menu.panelToggled = false; obj.OnClick("theButton", "LeftButton"); assertTrue(menu.panelToggled)
    QuestPrism.QuickMenu.Open = origOpen
end)

test("world map button right-click opens the quick menu", function()
    local opened
    local origOpen = QuestPrism.QuickMenu.Open
    QuestPrism.QuickMenu.Open = function(owner) opened = owner end
    QuestPrismWorldMapButtonMixin.OnClick("wmButton", "RightButton")
    assertEq(opened, "wmButton")
    QuestPrism.QuickMenu.Open = origOpen
end)


test("QuickMenu labels carry hidden counts when present", function()
    local orig = QuestPrism.WorldMap.GetHiddenCounts
    QuestPrism.WorldMap.GetHiddenCounts = function() return { Campaign = 3 } end
    QuestPrism.QuickMenu.Open("owner")
    QuestPrism.WorldMap.GetHiddenCounts = orig
    local types = menu.subs[QuestPrism_L.MENU_TYPES]
    assertEq(types.checkboxes[1].text, "Campaign (3)")
    assertEq(types.checkboxes[2].text, "Important")
end)

-- Guide tab: fake QuestMapFrame with Blizzard's display-mode mechanics
test("GuideTab creates its tab and panel and switches modes with Blizzard's mechanism", function()
    local modeEvents = {}
    EventRegistry = { RegisterCallback = function(_, name, fn, owner) modeEvents.name = name; modeEvents.fn = fn end }
    QuestMapFrame = MOCK.newFrame({ displayMode = "Quests" })
    QuestMapFrame.ContentsAnchor = MOCK.newFrame()
    QuestMapFrame.MapLegendTab = MOCK.newFrame()
    QuestMapFrame.QuestsTab = MOCK.newFrame({ displayMode = "Quests" })
    QuestMapFrame.TabButtons = { QuestMapFrame.QuestsTab }
    QuestMapFrame.QuestsFrame = MOCK.newFrame({ displayMode = "Quests" })
    QuestMapFrame.ContentFrames = { QuestMapFrame.QuestsFrame }
    function QuestMapFrame:SetDisplayMode(mode)
        if mode == self.displayMode then return end
        self.displayMode = mode
        for _, f in ipairs(self.TabButtons) do f.checked = (f.displayMode == mode) end
        for _, f in ipairs(self.ContentFrames) do if f.displayMode == mode then f:Show() else f:Hide() end end
        if modeEvents.fn then modeEvents.fn(nil, mode) end
    end
    QuestMapFrame_OpenToQuestDetails = function(id) modeEvents.opened = id end

    LOAD_ADDON_FILE("UI/Widgets.lua")
    local tabBefore = #MOCK.createdFrames
    LOAD_ADDON_FILE("UI/GuideTab.lua")
    QuestPrism.GuideTab.Initialize()
    assertTrue(QuestPrism.GuideTab.IsCreated(), "panel created: " .. tostring(QuestPrism.GuideTab.lastError))
    assertEq(modeEvents.name, "QuestLog.SetDisplayMode", "listens to Blizzard's mode event")
    -- The list uses the modern thin bar, like the settings window, not the legacy frame.
    local tabTemplates = {}
    for i = tabBefore + 1, #MOCK.createdFrames do
        local f = MOCK.createdFrames[i]
        if f.template then tabTemplates[f.template] = (tabTemplates[f.template] or 0) + 1 end
    end
    assertEq(tabTemplates["MinimalScrollBar"], 1, "modern scroll bar")
    assertEq(tabTemplates["UIPanelScrollFrameTemplate"], nil, "no legacy scroll frame")
    local tab = QuestPrism.GuideTab.GetTab()
    assertTrue(tab ~= nil and tab.parent ~= QuestMapFrame, "tab is parented to QuestPrism's holder, not QuestMapFrame")
    assertEq(tab.template, "LargeSideTabButtonTemplate")
    assertTrue(#QuestMapFrame.TabButtons == 1, "Blizzard's tab list untouched")

    QuestPrism.GuideTab.Select()
    assertEq(QuestMapFrame.displayMode, QuestPrism.GuideTab.MODE)
    assertTrue(QuestPrism.GuideTab.GetPanel():IsShown(), "our panel shown")
    assertFalse(QuestMapFrame.QuestsFrame:IsShown(), "Blizzard's list hidden by its own switch")

    QuestMapFrame:SetDisplayMode("Quests")
    assertFalse(QuestPrism.GuideTab.GetPanel():IsShown(), "our panel hides when Blizzard switches back")
    assertTrue(QuestMapFrame.QuestsFrame:IsShown())
end)

test("GuideTab renders without error for the no-source and with-source cases", function()
    QuestPrism.Settings.Set("guideSource", "Off")
    QuestPrism.GuideTab.Select()
    MOCK.flushTimers() -- render
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "r", steps = { { goals = { { questid = 501 } } } } }, AddMessageHandler = function() end }
    QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    QuestPrism.Sources.Invalidate()
    C_QuestLog.GetLogIndexForQuestID = function() return nil end
    C_QuestLog.IsQuestFlaggedCompleted = function() return false end
    C_QuestLog.GetTitleForQuestID = function() return "Five-oh-one" end
    QuestPrism.GuideTab.Refresh()
    local ok, err = pcall(MOCK.flushTimers)
    assertTrue(ok, tostring(err))
    QuestPrism.Settings.Set("guideSource", "Off"); ZGV = nil
end)


-- Native settings window (Blizzard templates) under the permissive frame stub
test("Panel.lua (native) loads, builds the window, syncs, and toggles", function()
    UISpecialFrames = {}
    StaticPopupDialogs = StaticPopupDialogs or {}
    StaticPopup_Show = function() end
    YES, NO = "Yes", "No"
    MinimalSliderWithSteppersMixin = { Label = { Right = 2 }, Event = { OnValueChanged = "OnValueChanged" } }
    ScrollUtil = { InitScrollFrameWithScrollBar = function() end }
    WorldMapFrame = WorldMapFrame or MOCK.newFrame()
    LOAD_ADDON_FILE("UI/Widgets.lua")
    local before = #MOCK.createdFrames
    LOAD_ADDON_FILE("UI/Panel.lua")
    QuestPrism.Panel.Initialize()
    assertTrue(QuestPrism.Panel.lastError == nil, "window built: " .. tostring(QuestPrism.Panel.lastError))
    assertTrue(QuestPrism.Panel.frame ~= nil, "frame exposed")
    assertEq(UISpecialFrames[1], "QuestPrismPanelFrame", "Escape closes")
    local templates = {}
    for i = before + 1, #MOCK.createdFrames do
        local f = MOCK.createdFrames[i]
        if f.template then templates[f.template] = (templates[f.template] or 0) + 1 end
    end
    assertTrue(templates["ButtonFrameTemplate"] == 1, "one Blizzard portrait window")
    assertEq(templates["MinimalCheckboxTemplate"], 15, "8 types + World Quests + tracker + waypoint + follow + guide-here + minimap + debug")
    assertEq(templates["UIRadioButtonTemplate"], 4, "This/All characters + Hide/Dim")
    assertEq(templates["WowStyle1DropdownTemplate"], 3, "presets + the optional source and scope")
    assertEq(templates["MinimalSliderWithSteppersTemplate"], nil, "no slider in the window any more")
    assertTrue(templates["MinimalScrollBar"] == 1, "native scroll bar")
    assertEq(templates["SharedButtonSmallTemplate"], 6, "modern three-slice buttons: Save as, All, None, Show on map, stepper -/+")
    assertEq(templates["UIPanelButtonTemplate"], nil, "no legacy panel buttons left in the window")
    assertTrue(templates["InputBoxTemplate"] == 1, "inline preset name box")
    QuestPrism.Panel.Sync()
    QuestPrism.Panel.Toggle(); assertTrue(QuestPrism.Panel.IsShown(), "shown after toggle")
    QuestPrism.Panel.Toggle(); assertFalse(QuestPrism.Panel.IsShown(), "hidden after second toggle")
    QuestPrism.Panel.UpdateStatus(3)
    assertEq(QuestPrism.Panel.SetSectionCollapsed, nil, "no collapsible sections")
end)

test("Panel is one column beside the map and two columns standalone", function()
    WorldMapFrame.IsShown = function() return true end
    QuestPrism.Panel.Toggle(true) -- from the map button / tab gear
    assertEq(QuestPrism.Panel.GetLayoutColumns(), 1, "beside the map")
    QuestPrism.Panel.Toggle()
    QuestPrism.Panel.Toggle() -- minimap button, slash command, keybinding
    assertEq(QuestPrism.Panel.GetLayoutColumns(), 2, "standalone")
    QuestPrism.Panel.Toggle()
    assertFalse(QuestPrism.Panel.IsShown())
end)

test("Panel rows use one polarity: ticked means visible", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    local w = QuestPrism.Panel.GetWidgets()
    -- World Quests row inverts the stored block
    QuestPrism.Settings.Set("HideWorldQuests", false); QuestPrism.Panel.Sync()
    assertEq(w.worldQuestsCb:GetChecked(), true, "shown -> ticked")
    w.worldQuestsCb:SetChecked(false); w.worldQuestsCb:GetScript("OnClick")(w.worldQuestsCb)
    assertEq(QuestPrism.Settings.Get("HideWorldQuests"), true, "unticked -> blocked")
    w.worldQuestsCb:SetChecked(true); w.worldQuestsCb:GetScript("OnClick")(w.worldQuestsCb)
    assertEq(QuestPrism.Settings.Get("HideWorldQuests"), false)
    -- Minimap button row inverts the hide flag
    QuestPrismCharDB.minimap.hide = false; QuestPrism.Panel.Sync()
    assertEq(w.minimapCb:GetChecked(), true, "button shown -> ticked")
    w.minimapCb:SetChecked(false); w.minimapCb:GetScript("OnClick")(w.minimapCb)
    assertEq(QuestPrismCharDB.minimap.hide, true)
    w.minimapCb:SetChecked(true); w.minimapCb:GetScript("OnClick")(w.minimapCb)
    assertEq(QuestPrismCharDB.minimap.hide, false)
    -- Radios: account scope and hidden-pin behaviour
    w.scopeRadios.radios[2]:GetScript("OnClick")(w.scopeRadios.radios[2])
    assertTrue(QuestPrism.Settings.IsAccountWide(), "All characters selected")
    assertEq(w.scopeRadios.radios[2]:GetChecked(), true); assertEq(w.scopeRadios.radios[1]:GetChecked(), false)
    w.scopeRadios.radios[1]:GetScript("OnClick")(w.scopeRadios.radios[1])
    assertFalse(QuestPrism.Settings.IsAccountWide())
    w.pinRadios.radios[2]:GetScript("OnClick")(w.pinRadios.radios[2])
    assertEq(QuestPrism.Settings.Get("dimFiltered"), true, "Dim selected")
    w.pinRadios.radios[1]:GetScript("OnClick")(w.pinRadios.radios[1])
    assertEq(QuestPrism.Settings.Get("dimFiltered"), false)
    QuestPrism.WorldMap.Refresh = orig
end)

test("Panel preset dropdown shows the active preset and flags edits", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    local w = QuestPrism.Panel.GetWidgets()
    QuestPrism.Settings.Reset(); QuestPrism.Panel.Sync()
    assertEq(w.presetDropdown.QLText, QuestPrism_L.PRESET_NONE)
    QuestPrism.Settings.LoadPreset("Leveling"); QuestPrism.Panel.Sync()
    assertEq(w.presetDropdown.QLText, "Leveling")
    w.checkboxes.Meta:SetChecked(true); w.checkboxes.Meta:GetScript("OnClick")(w.checkboxes.Meta, "LeftButton")
    assertEq(w.presetDropdown.QLText, "Leveling (edited)")
    -- Save as: the name box replaces the dropdown; Enter saves and selects the new preset
    w.presetNameBox:SetText("Alts")
    w.presetNameBox:GetScript("OnEnterPressed")(w.presetNameBox)
    assertEq(QuestPrism.Settings.GetActivePresetName(), "Alts")
    assertEq(w.presetDropdown.QLText, "Alts")
    assertFalse(w.presetNameBox:IsShown(), "box closed"); assertTrue(w.presetDropdown:IsShown(), "dropdown back")
    QuestPrism.Settings.DeletePreset("Alts"); QuestPrism.Settings.Reset()
    QuestPrism.WorldMap.Refresh = orig
end)

test("Sources.SetFollowing picks the last or first available source and reports failure", function()
    ZGV = nil; RXPFrame = nil; RXPCData = nil
    QuestPrism.Settings.Set("guideSource", "Off"); QuestPrism.Settings.Set("guideLastSource", nil)
    MOCK.printed = {}
    assertFalse(QuestPrism.Sources.SetFollowing(true), "no source available")
    assertEq(#MOCK.printed, 1, "user told")
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "f", steps = { { goals = {} } } }, AddMessageHandler = function() end }
    assertTrue(QuestPrism.Sources.SetFollowing(true))
    assertEq(QuestPrism.Settings.Get("guideSource"), "Zygor"); assertTrue(QuestPrism.Sources.IsFollowing())
    assertTrue(QuestPrism.Sources.SetFollowing(false))
    assertEq(QuestPrism.Settings.Get("guideSource"), "Off"); assertEq(QuestPrism.Settings.Get("guideLastSource"), "Zygor")
    QuestPrism.Sources.ToggleFollowing(); assertTrue(QuestPrism.Sources.IsFollowing(), "keybinding toggle")
    QuestPrism.Sources.ToggleFollowing(); assertFalse(QuestPrism.Sources.IsFollowing())
    ZGV = nil
end)

test("the gear menu carries scope and the lookahead count, and right-click toggles tracking", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    QuestPrism.Settings.Set("guideScope", "lookahead")
    QuestPrism.GuideTab.OpenMenu("gear")
    assertEq(#menu.checkboxes, 1, "the follow toggle leads the menu")
    assertEq(menu.checkboxes[1].text, QuestPrism_L.FOLLOW_GUIDE_LABEL)
    assertEq(#menu.radios, 3, "three scope choices at the top level")
    local guideRadio
    for _, r in ipairs(menu.radios) do if r.data == "guide" then guideRadio = r end end
    assertTrue(guideRadio ~= nil, "whole guide offered")
    assertEq(guideRadio.isSelected(guideRadio.data), false)
    guideRadio.setSelected(guideRadio.data)
    assertEq(QuestPrism.Settings.Get("guideScope"), "guide", "menu sets the scope")
    assertEq(guideRadio.isSelected(guideRadio.data), true)

    local counts = menu.subs[QuestPrism_L.GUIDE_LOOKAHEAD_LABEL]
    assertTrue(counts ~= nil, "lookahead submenu"); assertEq(#counts.radios, 10, "1 through 10")
    counts.radios[7].setSelected(counts.radios[7].data)
    assertEq(QuestPrism.Settings.Get("guideLookahead"), 7)
    assertEq(counts.radios[7].isSelected(counts.radios[7].data), true)
    QuestPrism.Settings.Set("guideLookahead", 3); QuestPrism.Settings.Set("guideScope", "lookahead")

    local watched = {}
    C_QuestLog.GetQuestWatchType = function(id) return watched[id] end
    C_QuestLog.AddQuestWatch = function(id) watched[id] = 1 end
    C_QuestLog.RemoveQuestWatch = function(id) watched[id] = nil end
    QuestPrism.GuideTab.ToggleWatch(900); assertEq(watched[900], 1, "tracked")
    QuestPrism.GuideTab.ToggleWatch(900); assertEq(watched[900], nil, "untracked")
    QuestPrism.WorldMap.Refresh = orig
end)


test("Bindings.xml exists, is referenced by the TOC, and its header/name globals are localized", function()
    local f = io.open(ADDON_PATH .. "Bindings.xml", "r")
    assertTrue(f ~= nil, "Bindings.xml present"); local xml = f:read("*a"); f:close()
    assertTrue(xml:find('name="QUESTPRISM_TOGGLE"', 1, true) ~= nil)
    assertTrue(xml:find('name="QUESTPRISM_GUIDEONLY"', 1, true) ~= nil)
    assertTrue(type(BINDING_HEADER_QUESTPRISM) == "string" and type(BINDING_NAME_QUESTPRISM_TOGGLE) == "string" and type(BINDING_NAME_QUESTPRISM_GUIDEONLY) == "string")
    local t = io.open(ADDON_PATH .. "QuestPrism.toc", "r")
    local toc = t:read("*a"); t:close()
    -- WoW loads Bindings.xml from the addon root by itself; listing it in the TOC makes
    -- the frame-XML loader parse it and warn "Unrecognized XML: Binding".
    assertTrue(toc:find("Bindings.xml", 1, true) == nil, "TOC must NOT list Bindings.xml")
end)


test("world map button is placed on the map without the Krowi library", function()
    WorldMapFrame = WorldMapFrame or MOCK.newFrame()
    WorldMapFrame.GetCanvasContainer = function(self) return self end
    MOCK.createdFrames = {}
    QuestPrism.WorldMapButton.Initialize()
    local created
    for _, f in ipairs(MOCK.createdFrames) do if f.template == "QuestPrismWorldMapButtonTemplate" then created = f end end
    assertTrue(created ~= nil and created.parent == WorldMapFrame, "own button on WorldMapFrame")
    assertTrue(QuestPrism.WorldMapButton.frame == created)
end)


-- Map tab header: the guide's home
test("the map tab has no header row: the cog is the only chrome", function()
    local h = QuestPrism.GuideTab.GetHeaderWidgets()
    assertTrue(h.gear ~= nil, "the settings cog")
    assertEq(h.followCb, nil, "no follow row taking a row of its own")
    assertEq(h.followLabel, nil)
    assertEq(h.sourceDropdown, nil, "no source row")
    assertEq(h.minus, nil, "no stepper row")
end)

test("the gear opens the settings window when the menu system is missing", function()
    local savedMenuUtil = MenuUtil
    MenuUtil = nil
    local opened = false
    local savedToggle = QuestPrism.Panel.Toggle
    QuestPrism.Panel.Toggle = function() opened = true end
    QuestPrism.GuideTab.OpenMenu("gear")
    assertTrue(opened, "falls back to the window")
    QuestPrism.Panel.Toggle = savedToggle
    MenuUtil = savedMenuUtil
end)

test("the gear menu offers a source only when more than one guide addon is available", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "z", steps = { { goals = {} } } }, AddMessageHandler = function() end }
    RXPFrame = nil; RXPCData = nil
    QuestPrism.GuideTab.OpenMenu("gear")
    assertEq(menu.subs[QuestPrism_L.GUIDE_SOURCE_LABEL], nil, "one source: no source entry")
    RXPFrame = { activeSteps = { { index = 1, elements = {} } }, BottomFrame = { UpdateFrame = function() end } }
    RXPCData = { currentStep = 1 }
    QuestPrism.GuideTab.OpenMenu("gear")
    local sources = menu.subs[QuestPrism_L.GUIDE_SOURCE_LABEL]
    assertTrue(sources ~= nil, "two sources: a source entry appears")
    assertEq(#sources.radios, 2)
    ZGV = nil; RXPFrame = nil; RXPCData = nil; QuestPrism.WorldMap.Refresh = orig
end)

test("button tooltips add the hidden count when pins are hidden", function()
    local lines = {}
    local tip = { AddLine = function(_, text) table.insert(lines, text) end }
    local orig = QuestPrism.WorldMap.GetHiddenTotal
    QuestPrism.WorldMap.GetHiddenTotal = function() return 0 end
    QuestPrism.MinimapButton.FillTooltip(tip)
    assertEq(#lines, 3, "no count line at zero")
    lines = {}
    QuestPrism.WorldMap.GetHiddenTotal = function() return 12 end
    WorldMapFrame.IsShown = function() return true end
    QuestPrism.MinimapButton.FillTooltip(tip)
    assertEq(#lines, 4); assertTrue(lines[4]:find("12", 1, true) ~= nil)
    lines = {}
    WorldMapFrame.IsShown = function() return false end
    QuestPrism.MinimapButton.FillTooltip(tip)
    assertEq(#lines, 3, "no count while the map is closed: it would be stale")
    WorldMapFrame.IsShown = function() return true end
    QuestPrism.WorldMap.GetHiddenTotal = orig
end)

test("Save as refuses a built-in name with a message and keeps the box open", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    local w = QuestPrism.Panel.GetWidgets()
    QuestPrism.Panel.Toggle()
    w.presetNameBox:Show(); w.presetDropdown:Hide()
    MOCK.printed = {}
    w.presetNameBox:SetText("leveling")
    w.presetNameBox:GetScript("OnEnterPressed")(w.presetNameBox)
    assertEq(#MOCK.printed, 1, "told why")
    assertTrue(w.presetNameBox:IsShown(), "box stays open for a correction")
    assertEq(QuestPrism.Settings.GetActivePresetName(), nil, "nothing saved")
    -- Closing the window mid Save as restores the dropdown
    QuestPrism.Panel.Toggle()
    QuestPrism.Panel.frame.frame:GetScript("OnHide")(QuestPrism.Panel.frame.frame)
    assertFalse(w.presetNameBox:IsShown()); assertTrue(w.presetDropdown:IsShown())
    QuestPrism.WorldMap.Refresh = orig
end)

test("/questprism reset re-syncs the window and the map tab", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    local w = QuestPrism.Panel.GetWidgets()
    QuestPrism.Settings.LoadPreset("Leveling"); QuestPrism.Panel.Sync()
    assertEq(w.presetDropdown.QLText, "Leveling")
    SlashCmdList["QUESTPRISM"]("reset")
    assertEq(w.presetDropdown.QLText, QuestPrism_L.PRESET_NONE, "window follows the reset")
    assertEq(w.checkboxes.Meta:GetChecked(), true)
    QuestPrism.WorldMap.Refresh = orig
end)

test("None in the window and Hide all in the quick menu untick World Quests too", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    QuestPrism.Settings.Reset()
    QuestPrism.QuickMenu.Open("owner")
    menu.buttons[4].fn() -- Hide all
    assertEq(QuestPrism.Settings.Get("HideWorldQuests"), true)
    QuestPrism.Settings.Reset()
    QuestPrism.WorldMap.Refresh = orig
end)

test("/questprism help prints the command list", function()
    MOCK.printed = {}
    SlashCmdList["QUESTPRISM"]("help")
    assertEq(#MOCK.printed, #QuestPrism_L.HELP_LINES)
end)


test("guide controls in the window are opt-in and always present once enabled", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    local w = QuestPrism.Panel.GetWidgets()
    ZGV = nil
    QuestPrism.Settings.Set("guideControlsInWindow", false); QuestPrism.Panel.Sync()
    assertEq(w.guideInWindowCb:GetChecked(), false)
    assertTrue(w.sourceRow.hidden and w.scopeRow.hidden and w.lookaheadRow.hidden, "hidden while off")

    w.guideInWindowCb:SetChecked(true); w.guideInWindowCb:GetScript("OnClick")(w.guideInWindowCb)
    assertEq(QuestPrism.Settings.Get("guideControlsInWindow"), true)
    assertFalse(w.sourceRow.hidden, "source row shown")
    assertFalse(w.scopeRow.hidden); assertFalse(w.lookaheadRow.hidden)
    -- Not following: the rows stay put and grey out rather than disappearing.
    assertEq(w.sourceDropdown.enabled, false, "greyed while not following")
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "g", steps = { { goals = {} } } }, AddMessageHandler = function() end }
    QuestPrism.Sources.SetFollowing(true); QuestPrism.Panel.Sync()
    assertEq(w.sourceDropdown.enabled, true, "live while following")
    assertFalse(w.sourceRow.hidden, "still the same rows")
    -- The scope dropdown drives the stepper's availability, not its presence.
    QuestPrism.Settings.Set("guideScope", "guide"); QuestPrism.Panel.Sync()
    assertFalse(w.lookaheadRow.hidden, "row stays")
    QuestPrism.Settings.Set("guideScope", "lookahead"); QuestPrism.Panel.Sync()
    assertEq(w.scopeDropdown.QLText, QuestPrism_L.GUIDE_SCOPE_LOOKAHEAD)
    QuestPrism.Sources.SetFollowing(false); ZGV = nil
    QuestPrism.Settings.Set("guideControlsInWindow", false); QuestPrism.Panel.Sync()
    QuestPrism.WorldMap.Refresh = orig
end)

test("the waypoint option is off by default and writes the setting", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    local w = QuestPrism.Panel.GetWidgets()
    QuestPrism.Panel.Sync()
    assertEq(w.waypointCb:GetChecked(), false, "off by default")
    w.waypointCb:SetChecked(true); w.waypointCb:GetScript("OnClick")(w.waypointCb)
    assertEq(QuestPrism.Settings.Get("clearWorldQuestWaypoint"), true)
    w.waypointCb:SetChecked(false); w.waypointCb:GetScript("OnClick")(w.waypointCb)
    assertEq(QuestPrism.Settings.Get("clearWorldQuestWaypoint"), false)
    QuestPrism.WorldMap.Refresh = orig
end)


test("buttons fall back to the legacy template on a client without the modern one", function()
    -- Same window code, on a client where the three-slice family is absent.
    local saved = ThreeSliceButtonMixin
    ThreeSliceButtonMixin = nil
    QuestPrism.Panel = {}
    -- Reloading Widgets clears its memo, so the template is decided afresh.
    LOAD_ADDON_FILE("UI/Widgets.lua")
    local before = #MOCK.createdFrames
    LOAD_ADDON_FILE("UI/Panel.lua")
    QuestPrism.Panel.Initialize()
    assertTrue(QuestPrism.Panel.lastError == nil, "window still builds: " .. tostring(QuestPrism.Panel.lastError))
    local templates = {}
    for i = before + 1, #MOCK.createdFrames do
        local f = MOCK.createdFrames[i]
        if f.template then templates[f.template] = (templates[f.template] or 0) + 1 end
    end
    assertEq(templates["UIPanelButtonTemplate"], 6, "legacy buttons used instead")
    assertEq(templates["SharedButtonSmallTemplate"], nil, "none of the modern ones")
    ThreeSliceButtonMixin = saved
    LOAD_ADDON_FILE("UI/Widgets.lua") -- back to the modern template for later tests
end)


test("the window's buttons come from the shared factory", function()
    assertEq(QuestPrism.Widgets.ButtonTemplate(), "SharedButtonSmallTemplate")
end)


test("the guide list has plate headers in a bordered inset, and they collapse", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "c", steps = { { goals = { { questid = 501 }, { questid = 502 } } } } }, AddMessageHandler = function() end }
    QuestPrism.Settings.Set("guideSource", "Zygor"); QuestPrism.Settings.Set("guideScope", "step")
    QuestPrism.Settings.Set("guideCollapsedToPickUp", false)
    QuestPrism.Sources.Invalidate()
    C_QuestLog.GetLogIndexForQuestID = function() return nil end
    C_QuestLog.IsQuestFlaggedCompleted = function() return false end
    C_QuestLog.GetTitleForQuestID = function(id) return "Quest " .. id end
    QuestPrism.GuideTab.Select(); MOCK.flushTimers()

    local inset = QuestPrism.GuideTab.GetListInset()
    assertTrue(inset ~= nil, "container created")
    assertEq(inset.Border.atlas, "questlog-frame", "the quest log's own border art")
    assertEq(inset.ScrollLine.atlas, "questlog_line_scrollbar", "divider before the scroll bar")
    local headers = QuestPrism.GuideTab.GetActiveHeaders()
    assertEq(#headers, 1, "one section: to pick up")
    assertEq(headers[1].sectionKey, "guideCollapsedToPickUp")
    assertEq(#QuestPrism.GuideTab.GetActiveRows(), 2, "both quests listed")

    headers[1]:GetScript("OnClick")(headers[1])
    assertEq(QuestPrism.Settings.Get("guideCollapsedToPickUp"), true, "clicking collapses")
    MOCK.flushTimers()
    assertEq(#QuestPrism.GuideTab.GetActiveRows(), 0, "rows hidden while collapsed")
    assertEq(#QuestPrism.GuideTab.GetActiveHeaders(), 1, "header stays so it can be reopened")

    headers = QuestPrism.GuideTab.GetActiveHeaders()
    headers[1]:GetScript("OnClick")(headers[1])
    MOCK.flushTimers()
    assertEq(#QuestPrism.GuideTab.GetActiveRows(), 2, "reopened")
    QuestPrism.Settings.Set("guideSource", "Off"); ZGV = nil
    QuestPrism.WorldMap.Refresh = orig
end)


test("the settings menu toggles following, like the row does", function()
    local orig = QuestPrism.WorldMap.Refresh; QuestPrism.WorldMap.Refresh = function() end
    ZGV = { CurrentStepNum = 1, CurrentGuide = { title = "m", steps = { { goals = {} } } }, AddMessageHandler = function() end }
    QuestPrism.Settings.Set("guideSource", "Off")
    QuestPrism.GuideTab.OpenMenu("gear")
    local follow = menu.checkboxes[1]
    assertEq(follow.isSelected(), false)
    follow.setSelected()
    assertTrue(QuestPrism.Sources.IsFollowing(), "menu starts following")
    follow.setSelected()
    assertFalse(QuestPrism.Sources.IsFollowing())
    ZGV = nil; QuestPrism.WorldMap.Refresh = orig
end)


test("/questprism tab reports where the tab's frames are", function()
    MOCK.printed = {}
    SlashCmdList["QUESTPRISM"]("tab")
    assertTrue(#MOCK.printed >= 6, "one line per frame: " .. #MOCK.printed)
    local joined = table.concat(MOCK.printed, "\n")
    for _, want in ipairs({ "panel", "container", "ourBar", "cog", "theirList", "theirBar" }) do
        assertTrue(joined:find(want, 1, true) ~= nil, "reports " .. want)
    end
    -- It names both display modes, so a mismatch between them is visible at a glance.
    assertTrue(joined:find("ours=", 1, true) ~= nil, "names our display mode")
    MOCK.printed = {}
    MOCK.flushTimers()
    assertTrue(#MOCK.printed >= 6, "reports again once the map has been opened")
end)
