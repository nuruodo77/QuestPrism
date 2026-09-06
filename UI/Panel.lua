QuestPrism.Panel = {}

-- Settings window built only from Blizzard templates, to blend into the default UI:
--   * window    : ButtonFrameTemplate (portrait frame, title, close button, inset)
--   * checkboxes: MinimalCheckboxTemplate (the Options menu ones)
--   * radios    : UIRadioButtonTemplate (two-way choices)
--   * dropdown  : WowStyle1DropdownTemplate + MenuUtil (presets)
--   * buttons   : UIPanelButtonTemplate; text entry: InputBoxTemplate
--   * scrolling : ScrollFrame + MinimalScrollBar
-- One rule for every row: ticked means visible. Content, top to bottom:
--   preset row (dropdown, Save as), Filters (this character / all characters),
--   "Quests to show" (nine rows with the Map Legend's descriptions, All / None),
--   "Where it applies" (hidden pins: hide / dim; objective tracker),
--   "Guide" (Follow my guide; source and scope live on the map tab),
--   "Addon" (minimap button, debug).
-- Beside the map that is one tall column; standalone it is two columns (the quest
-- rows on the left, the three short sections on the right).

local L = QuestPrism_L
local ICON = "Interface\\AddOns\\QuestPrism\\Textures\\icon"

local QUEST_TYPES = {
    { key = "Campaign",   label = L.QUEST_CAMPAIGN,    atlas = "questlog-questtypeicon-story",      tooltip = L.TYPE_TIP_CAMPAIGN,    desc = L.TYPE_DESC_CAMPAIGN },
    { key = "Important",  label = L.QUEST_IMPORTANT,   atlas = "questlog-questtypeicon-important",  tooltip = L.TYPE_TIP_IMPORTANT,   desc = L.TYPE_DESC_IMPORTANT },
    { key = "Legendary",  label = L.QUEST_LEGENDARY,   atlas = "questlog-questtypeicon-legendary",  tooltip = L.TYPE_TIP_LEGENDARY,   desc = L.TYPE_DESC_LEGENDARY },
    { key = "Meta",       label = L.QUEST_META,        atlas = "questlog-questtypeicon-wrapper",    tooltip = L.TYPE_TIP_META,        desc = L.TYPE_DESC_META },
    { key = "Repeatable", label = L.QUEST_REPEATABLE,  atlas = "questlog-questtypeicon-recurring",  tooltip = L.TYPE_TIP_REPEATABLE,  desc = L.TYPE_DESC_REPEATABLE },
    { key = "LocalStory", label = L.QUEST_LOCAL_STORY, atlas = "questnormal",                       tooltip = L.TYPE_TIP_LOCAL_STORY, desc = L.TYPE_DESC_LOCAL_STORY },
    { key = "Expedition", label = L.QUEST_EXPEDITION,  atlas = "worldquest-tracker-questmarker",    tooltip = L.TYPE_TIP_EXPEDITION,  desc = L.TYPE_DESC_EXPEDITION },
    { key = "Trivial",    label = L.QUEST_TRIVIAL,     trackingIcon = true, fallbackTexture = "Interface\\Minimap\\Tracking\\TrivialQuests",
      tooltip = L.TYPE_TIP_TRIVIAL, desc = L.TYPE_DESC_TRIVIAL },
}
QuestPrism.Panel.QUEST_TYPES = QUEST_TYPES

-- The world quest row is not a type toggle (it drives the block in Core/Rules.lua)
-- but it sits in the same list with the same polarity: ticked = shown.
local WORLD_QUEST_ROW = { label = L.QUEST_WORLD_QUESTS, atlas = "worldquest-questmarker-questbang", tooltip = L.TOOLTIP_WORLD_QUESTS, desc = L.TYPE_DESC_WORLD_QUESTS }

local PANEL_FRAME_NAME = "QuestPrismPanelFrame"
-- Two shapes for the same content. Beside the map (map button, tab gear): one tall
-- column that fits next to the map. Standalone (minimap button, slash command,
-- keybinding): two columns of the same width, so the window uses the screen's
-- width instead of its height. Rows are built once at COLUMN_W; only the section
-- positions change between the two.
local COLUMN_W, COLUMN_GAP, CHROME_W = 396, 16, 64 -- chrome: borders, inset padding, scroll bar
local LAYOUT_BESIDE_MAP = { columns = 1, width = COLUMN_W + CHROME_W, height = 800 }
local LAYOUT_STANDALONE = { columns = 2, width = COLUMN_W * 2 + COLUMN_GAP + CHROME_W, height = 560 }
local CONTENT_W = COLUMN_W
local ICON_X, LABEL_X = 8, 32
local CONTROL_RIGHT = CONTENT_W - 8 -- right edge of the control column
local NAME_H, DESC_H = 14, 12      -- fallbacks when the mock cannot measure text
local SECTION_HEADER_H = 26
local SECTION_GAP = 10

local frame, scrollFrame, scrollBar, content, statusText
local ready = false      -- true once createWindow finished; a half-built window stays inert
local layoutMode = LAYOUT_BESIDE_MAP
local anchoredToMap = false
local sections = {}      -- ordered list of { frame, rows, column }
local widgets = { checkboxes = {}, typeRows = {} }

-- ---------------------------------------------------------------------------
-- Helpers (all on Blizzard templates)
-- ---------------------------------------------------------------------------

local function numberOr(value, default)
    if type(value) == "number" and value > 0 then return value end
    return default
end

local function showTooltip(anchorFrame, text)
    if not text then return end
    GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, nil, nil, nil, nil, true)
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

local function attachTooltip(region, textOrFn)
    if not textOrFn then return end
    region:SetScript("OnEnter", function(self)
        local text = type(textOrFn) == "function" and textOrFn() or textOrFn
        showTooltip(self, text)
    end)
    region:SetScript("OnLeave", hideTooltip)
end

local function fontString(parent, fontObject, text, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObject)
    if width then fs:SetWidth(width) end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text or "")
    return fs
end

local function checkbox(parent, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
    attachTooltip(cb, tooltip)
    return cb
end

local function button(parent, text, width, onClick, tooltip)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    attachTooltip(btn, tooltip)
    return btn
end

-- Single-choice dropdown. optionsProvider() -> { { key, label }, ... }
local function optionDropdown(parent, width, optionsProvider, getValue, setValue, emptyText, tooltip)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    local function isSelected(key) return getValue() == key end
    if type(dd.SetupMenu) == "function" then
        dd:SetupMenu(function(_, rootDescription)
            for _, option in ipairs(optionsProvider()) do
                rootDescription:CreateRadio(option.label, isSelected, setValue, option.key)
            end
        end)
    end
    attachTooltip(dd, tooltip)
    dd.QLRefresh = function(self, enabled)
        local current, text = getValue(), nil
        for _, option in ipairs(optionsProvider()) do
            if option.key == current then text = option.label end
        end
        text = text or emptyText
        self.QLText = text
        if type(self.SetDefaultText) == "function" then self:SetDefaultText(text) end
        if type(self.GenerateMenu) == "function" then pcall(self.GenerateMenu, self) end
        if type(self.OverrideText) == "function" then pcall(self.OverrideText, self, text) end
        if enabled ~= nil and type(self.SetEnabled) == "function" then pcall(self.SetEnabled, self, enabled) end
    end
    return dd
end

-- [-] N [+] within min..max; Sync(enabled) greys both buttons at the ends.
local function stepperControl(parent, minValue, maxValue, getValue, setValue, tooltip)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(84, 22)
    local minus = button(holder, "-", 22, function() setValue(math.max(minValue, getValue() - 1)) end, tooltip)
    minus:SetPoint("LEFT", holder, "LEFT", 0, 0)
    local text = fontString(holder, "GameFontHighlight", "", 28, "CENTER")
    text:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = button(holder, "+", 22, function() setValue(math.min(maxValue, getValue() + 1)) end, tooltip)
    plus:SetPoint("LEFT", text, "RIGHT", 4, 0)
    holder.Sync = function(self, enabled)
        local value = getValue()
        text:SetText(tostring(value))
        minus:SetEnabled(enabled and value > minValue)
        plus:SetEnabled(enabled and value < maxValue)
    end
    return holder
end

-- Two-way choice: returns a frame holding both radios; SetValue(index) syncs them.
local function radioPair(parent, labels, getIndex, setIndex, tooltip)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(1, 20)
    holder.radios = {}
    local x = 0
    for i, labelText in ipairs(labels) do
        local radio = CreateFrame("CheckButton", nil, holder, "UIRadioButtonTemplate")
        radio:SetSize(16, 16)
        radio:SetPoint("LEFT", holder, "LEFT", x, 0)
        local label = fontString(holder, "GameFontHighlightSmall", labelText)
        label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
        radio:SetScript("OnClick", function() setIndex(i) end)
        attachTooltip(radio, tooltip)
        holder.radios[i] = radio
        x = x + 16 + 4 + numberOr(label:GetStringWidth(), 60) + 14
    end
    holder:SetWidth(x)
    holder.Sync = function(self)
        local current = getIndex()
        for i, radio in ipairs(self.radios) do radio:SetChecked(i == current) end
    end
    return holder
end

-- ---------------------------------------------------------------------------
-- Rows and sections
-- ---------------------------------------------------------------------------

-- A section: header (title, optional buttons on the right) and rows laid out
-- underneath. Heights are measured at layout time so long descriptions can wrap.
-- column: "span" (full width, above the columns), "left" or "right"; in the
-- one-column shape every section flows in order.
local function newSection(title, column)
    local section = { rows = {}, column = column or "left" }
    section.frame = CreateFrame("Frame", nil, content)
    section.frame:SetSize(CONTENT_W, SECTION_HEADER_H)
    section.header = CreateFrame("Frame", nil, section.frame)
    section.header:SetPoint("TOPLEFT", section.frame, "TOPLEFT", 0, 0)
    section.header:SetSize(CONTENT_W, SECTION_HEADER_H)
    section.header.Text = fontString(section.header, "GameFontHighlightLarge", title)
    section.header.Text:SetPoint("BOTTOMLEFT", section.header, "BOTTOMLEFT", 2, 5)
    local line = section.header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", section.header, "BOTTOMLEFT", 2, 2)
    line:SetPoint("BOTTOMRIGHT", section.header, "BOTTOMRIGHT", -2, 2)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.25)
    section.headerHeight = SECTION_HEADER_H
    section.nextButtonX = -2
    -- Buttons on the header's right, added right to left.
    section.addHeaderButton = function(self, text, width, onClick, tooltip)
        local btn = button(self.header, text, width, onClick, tooltip)
        btn:SetPoint("BOTTOMRIGHT", self.header, "BOTTOMRIGHT", self.nextButtonX, 4)
        self.nextButtonX = self.nextButtonX - width - 4
        return btn
    end
    section.body = CreateFrame("Frame", nil, section.frame)
    section.body:SetPoint("TOPLEFT", section.frame, "TOPLEFT", 0, -SECTION_HEADER_H)
    section.body:SetSize(CONTENT_W, 10)
    table.insert(sections, section)
    return section
end

-- A row: [icon] name / description on the left, a control on the right.
--   opts.icon      : atlas name (or trackingIcon + fallbackTexture)
--   opts.name      : label; opts.onNameClick makes it a button (solo mode)
--   opts.desc      : one-line description under the name (wraps if needed)
--   opts.control   : frame anchored to the row's right edge
--   opts.tooltip   : for the name
local function addRow(section, opts)
    local body = section.body
    local row = { frame = CreateFrame("Frame", nil, body), opts = opts }
    row.frame:SetSize(CONTENT_W, NAME_H)
    local textX = ICON_X
    if opts.icon or opts.trackingIcon then
        local icon = row.frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", row.frame, "TOPLEFT", ICON_X, -2)
        if opts.trackingIcon then
            local texture
            if QuestPrism.Minimap and QuestPrism.Minimap.GetTrackingTexture and Enum and Enum.MinimapTrackingFilter then
                texture = QuestPrism.Minimap.GetTrackingTexture(Enum.MinimapTrackingFilter.TrivialQuests)
            end
            pcall(icon.SetTexture, icon, texture or opts.fallbackTexture)
        else
            pcall(icon.SetAtlas, icon, opts.icon)
        end
        textX = LABEL_X
    end
    local textW = CONTROL_RIGHT - textX - (opts.controlWidth or 30) - 8

    if opts.onNameClick then
        local nameBtn = CreateFrame("Button", nil, row.frame)
        nameBtn:SetPoint("TOPLEFT", row.frame, "TOPLEFT", textX, 0)
        nameBtn:SetSize(textW, NAME_H + 4)
        nameBtn.Text = fontString(nameBtn, "GameFontNormal", opts.name)
        nameBtn.Text:SetPoint("LEFT", nameBtn, "LEFT", 0, 0)
        nameBtn.Text:SetPoint("RIGHT", nameBtn, "RIGHT", 0, 0)
        local hl = nameBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        nameBtn:SetScript("OnClick", opts.onNameClick)
        attachTooltip(nameBtn, opts.tooltip)
        row.nameButton = nameBtn
        row.name = nameBtn.Text
    else
        row.name = fontString(row.frame, "GameFontNormal", opts.name, textW)
        row.name:SetPoint("TOPLEFT", row.frame, "TOPLEFT", textX, -2)
    end
    if opts.desc then
        row.desc = fontString(row.frame, "GameFontDisableSmall", opts.desc, textW)
        row.desc:SetPoint("TOPLEFT", row.frame, "TOPLEFT", textX, -(NAME_H + 5))
    end
    if opts.control then
        opts.control:SetParent(row.frame)
        opts.control:ClearAllPoints()
        opts.control:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", -(CONTENT_W - CONTROL_RIGHT), -1)
        row.control = opts.control
    end
    table.insert(section.rows, row)
    return row
end

local function rowHeight(row)
    local h = 4 + numberOr(row.name:GetStringHeight(), NAME_H)
    if row.desc then
        h = h + 3 + numberOr(row.desc:GetStringHeight(), DESC_H)
    end
    return math.max(h + 8, row.opts.minHeight or 0)
end

local function layoutAll()
    local twoColumns = layoutMode.columns == 2
    local columnX = { span = 0, left = 0, right = twoColumns and (COLUMN_W + COLUMN_GAP) or 0 }
    local columnY = { span = 4, left = 4, right = 4 }
    for _, section in ipairs(sections) do
        local bodyY = 4
        for _, row in ipairs(section.rows) do
            if row.hidden then
                row.frame:Hide()
            else
                row.frame:Show()
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT", section.body, "TOPLEFT", 0, -bodyY)
                local h = rowHeight(row)
                row.frame:SetHeight(h)
                bodyY = bodyY + h
            end
        end
        section.body:ClearAllPoints()
        section.body:SetPoint("TOPLEFT", section.frame, "TOPLEFT", 0, -section.headerHeight)
        section.body:SetHeight(bodyY + 2)
        local total = section.headerHeight + bodyY + 2
        section.frame:SetHeight(total)

        local column = twoColumns and section.column or "span"
        section.frame:ClearAllPoints()
        section.frame:SetPoint("TOPLEFT", content, "TOPLEFT", columnX[column], -columnY[column])
        columnY[column] = columnY[column] + total + SECTION_GAP
        if column == "span" then
            -- Whatever spans pushes both columns down.
            columnY.left, columnY.right = columnY.span, columnY.span
        end
    end
    content:SetWidth(twoColumns and (COLUMN_W * 2 + COLUMN_GAP) or COLUMN_W)
    content:SetHeight(math.max(columnY.span, columnY.left, columnY.right) + 8)
end

local function applyLayoutMode(mode)
    layoutMode = mode
    if frame then frame:SetSize(mode.width, mode.height) end
    if content then layoutAll() end
end

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

local function isSoloed(key)
    return QuestPrism.Settings.IsSoloed and QuestPrism.Settings.IsSoloed(key)
end

local function presetDropdownText()
    local active = QuestPrism.Settings.GetActivePresetName()
    if not active then return L.PRESET_NONE end
    if QuestPrism.Settings.IsActivePresetModified() then return active .. L.PRESET_EDITED_SUFFIX end
    return active
end

local function syncWidgets()
    for _, questType in ipairs(QUEST_TYPES) do
        local cb = widgets.checkboxes[questType.key]
        if cb then cb:SetChecked(QuestPrism.Settings.Get(questType.key) == true) end
        local row = widgets.typeRows[questType.key]
        if row then
            row.name:SetText(isSoloed(questType.key) and (questType.label .. L.SOLO_SUFFIX) or questType.label)
        end
    end
    if widgets.worldQuestsCb then widgets.worldQuestsCb:SetChecked(QuestPrism.Settings.Get("HideWorldQuests") ~= true) end
    if widgets.presetDropdown then widgets.presetDropdown:QLRefresh() end
    if widgets.scopeRadios then widgets.scopeRadios:Sync() end
    if widgets.pinRadios then widgets.pinRadios:Sync() end
    if widgets.trackerCb then widgets.trackerCb:SetChecked(QuestPrism.Settings.Get("trackerFilter") == true) end
    if widgets.waypointCb then widgets.waypointCb:SetChecked(QuestPrism.Settings.Get("clearWorldQuestWaypoint") == true) end
    if widgets.followCb then widgets.followCb:SetChecked(QuestPrism.Sources.IsFollowing()) end
    if widgets.guideInWindowCb then
        local show = QuestPrism.Settings.Get("guideControlsInWindow") == true
        local following = QuestPrism.Sources.IsFollowing()
        widgets.guideInWindowCb:SetChecked(show)
        widgets.sourceRow.hidden = not show
        widgets.scopeRow.hidden = not show
        widgets.lookaheadRow.hidden = not show
        if show then
            widgets.sourceDropdown:QLRefresh(following)
            widgets.scopeDropdown:QLRefresh(following)
            widgets.lookaheadStepper:Sync(following and (QuestPrism.Settings.Get("guideScope") or "lookahead") == "lookahead")
        end
    end
    if widgets.followRow then
        widgets.followRow.desc:SetText(QuestPrism.Sources.GetStatusText() .. " " .. L.FOLLOW_GUIDE_DESC)
    end
    if widgets.minimapCb then widgets.minimapCb:SetChecked(not QuestPrism.MinimapButton.IsHidden()) end
    if widgets.debugCb then widgets.debugCb:SetChecked(QuestPrism.Settings.Get("debug") == true) end
    layoutAll()
end

local function changed()
    syncWidgets()
    QuestPrism.WorldMap.Refresh()
    if QuestPrism.GuideTab and QuestPrism.GuideTab.Sync then QuestPrism.GuideTab.Sync() end
end

-- ---------------------------------------------------------------------------
-- Preset row + Filters row (above the sections, inside the first section frame)
-- ---------------------------------------------------------------------------

local function presetMenu(dropdown, rootDescription)
    local function isSelected(name) return QuestPrism.Settings.GetActivePresetName() == name end
    local function onSelect(name)
        QuestPrism.Settings.LoadPreset(name)
        changed()
    end
    rootDescription:CreateTitle(L.PRESET_BUILTIN)
    for _, name in ipairs(QuestPrism.Settings.ListBuiltInPresetNames()) do
        rootDescription:CreateRadio(name, isSelected, onSelect, name)
    end
    local saved = QuestPrism.Settings.ListPresetNames()
    if #saved > 0 then
        rootDescription:CreateDivider()
        rootDescription:CreateTitle(L.PRESET_YOURS)
        for _, name in ipairs(saved) do
            rootDescription:CreateRadio(name, isSelected, onSelect, name)
        end
    end
    rootDescription:CreateDivider()
    local active = QuestPrism.Settings.GetActivePresetName()
    local deletable = active ~= nil and not QuestPrism.Settings.IsBuiltInPreset(active)
    local text = deletable and string.format(L.PRESET_DELETE_NAMED, active) or L.PRESET_DELETE
    local deleteButton = rootDescription:CreateButton(text, function()
        if deletable then StaticPopup_Show("QUESTPRISM_DELETE_PRESET", active, nil, active) end
    end)
    if deleteButton and type(deleteButton.SetEnabled) == "function" then
        pcall(deleteButton.SetEnabled, deleteButton, deletable)
    end
end

local function buildTopRows(section)
    local body = section.body
    -- Row 1: Preset [dropdown] [Save as...]
    local presetRow = addRow(section, { name = L.PRESET_ROW_LABEL, controlWidth = 0, minHeight = 30 })
    local dd = CreateFrame("DropdownButton", nil, presetRow.frame, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", presetRow.frame, "TOPLEFT", 64, 0)
    dd:SetWidth(176)
    if type(dd.SetupMenu) == "function" then dd:SetupMenu(presetMenu) end
    attachTooltip(dd, function()
        local active = QuestPrism.Settings.GetActivePresetName()
        if active and QuestPrism.Settings.IsBuiltInPreset(active) then return L.TOOLTIP_PRESET_BUILTIN end
        return L.TOOLTIP_PRESET_DROPDOWN
    end)
    dd.QLRefresh = function(self)
        local text = presetDropdownText()
        self.QLText = text
        if type(self.SetDefaultText) == "function" then self:SetDefaultText(text) end
        if type(self.GenerateMenu) == "function" then pcall(self.GenerateMenu, self) end
        if type(self.OverrideText) == "function" then pcall(self.OverrideText, self, text) end
    end
    widgets.presetDropdown = dd

    -- The name box takes the dropdown's place while a preset is being saved.
    local box = CreateFrame("EditBox", nil, presetRow.frame, "InputBoxTemplate")
    box:SetSize(170, 20)
    box:SetPoint("TOPLEFT", presetRow.frame, "TOPLEFT", 70, -2)
    box:SetAutoFocus(false)
    box:SetMaxLetters(32)
    local instructions = rawget(box, "Instructions")
    if type(instructions) == "table" then instructions:SetText(L.PRESET_SAVE_PROMPT) end
    local function closeBox()
        box:SetText(""); box:ClearFocus(); box:Hide(); dd:Show()
    end
    box:SetScript("OnEnterPressed", function(self)
        local name = QuestPrism.Settings.NormalizePresetName(self:GetText())
        if name and QuestPrism.Settings.IsBuiltInPreset(name) then
            -- Reserved name: say so and leave the box open for a correction.
            print(string.format(L.PRESET_NAME_RESERVED, name))
            return
        end
        if name then
            local exists = false
            for _, existing in ipairs(QuestPrism.Settings.ListPresetNames()) do if existing == name then exists = true end end
            if exists then
                StaticPopup_Show("QUESTPRISM_OVERWRITE_PRESET", name, nil, name)
            else
                QuestPrism.Settings.SavePreset(name)
                changed()
            end
        end
        closeBox()
    end)
    box:SetScript("OnEscapePressed", closeBox)
    box:Hide()
    widgets.presetNameBox = box
    widgets.closePresetBox = closeBox

    local saveBtn = button(presetRow.frame, L.PRESET_SAVE_AS, 80, function()
        if box:IsShown() then closeBox(); return end
        dd:Hide(); box:Show(); box:SetFocus()
    end, L.TOOLTIP_PRESET_SAVE)
    saveBtn:SetPoint("TOPLEFT", dd, "TOPRIGHT", 6, 0)

    -- Row 2: Filters (o) This character ( ) All characters
    widgets.scopeRadios = radioPair(body, { L.SCOPE_THIS_CHARACTER, L.SCOPE_ALL_CHARACTERS },
        function() return QuestPrism.Settings.IsAccountWide() and 2 or 1 end,
        function(index) QuestPrism.Settings.SetAccountWide(index == 2); changed() end,
        L.TOOLTIP_ACCOUNT_WIDE)
    local filtersRow = addRow(section, { name = L.FILTERS_LABEL, controlWidth = 0 })
    widgets.scopeRadios:SetParent(filtersRow.frame)
    widgets.scopeRadios:ClearAllPoints()
    widgets.scopeRadios:SetPoint("TOPLEFT", filtersRow.frame, "TOPLEFT", 64, -1)
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------

local function buildShowSection()
    local section = newSection(L.SECTION_SHOW, "left")
    section:addHeaderButton(L.HIDE_ALL, 50, function() QuestPrism.Settings.HideAll(); changed() end, L.TOOLTIP_HIDE_ALL)
    section:addHeaderButton(L.SHOW_ALL, 44, function() QuestPrism.Settings.Reset(); changed() end, L.TOOLTIP_SHOW_ALL)

    widgets.typeRows = {}
    for _, questType in ipairs(QUEST_TYPES) do
        local cb = checkbox(section.body, questType.tooltip or L.TOOLTIP_SHOW_TYPE)
        cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cb:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                self:SetChecked(not self:GetChecked())
                QuestPrism.Settings.Solo(questType.key)
            else
                QuestPrism.Settings.Set(questType.key, self:GetChecked() and true or false)
            end
            changed()
        end)
        widgets.checkboxes[questType.key] = cb
        widgets.typeRows[questType.key] = addRow(section, {
            icon = questType.atlas, trackingIcon = questType.trackingIcon, fallbackTexture = questType.fallbackTexture,
            name = questType.label, desc = questType.desc, control = cb,
            tooltip = function() return (questType.tooltip or "") .. "\n\n" .. L.SOLO_CAPTION end,
            onNameClick = function() QuestPrism.Settings.Solo(questType.key); changed() end,
        })
    end

    local wqCb = checkbox(section.body, WORLD_QUEST_ROW.tooltip)
    wqCb:SetScript("OnClick", function(self)
        QuestPrism.Settings.Set("HideWorldQuests", not self:GetChecked())
        changed()
    end)
    widgets.worldQuestsCb = wqCb
    addRow(section, { icon = WORLD_QUEST_ROW.atlas, name = WORLD_QUEST_ROW.label, desc = WORLD_QUEST_ROW.desc, control = wqCb, tooltip = WORLD_QUEST_ROW.tooltip })
end

local function buildAppliesSection()
    local section = newSection(L.SECTION_APPLIES, "right")
    widgets.pinRadios = radioPair(section.body, { L.PINS_HIDE, L.PINS_DIM },
        function() return QuestPrism.Settings.Get("dimFiltered") == true and 2 or 1 end,
        function(index) QuestPrism.Settings.Set("dimFiltered", index == 2); changed() end,
        L.TOOLTIP_PINS)
    addRow(section, { name = L.PINS_LABEL, control = widgets.pinRadios, controlWidth = 130 })

    widgets.trackerCb = checkbox(section.body, L.TOOLTIP_TRACKER)
    widgets.trackerCb:SetScript("OnClick", function(self)
        QuestPrism.Settings.Set("trackerFilter", self:GetChecked() and true or false)
        changed()
    end)
    addRow(section, { name = L.TRACKER_LABEL, desc = L.TRACKER_DESC, control = widgets.trackerCb, tooltip = L.TOOLTIP_TRACKER })

    -- Opt-in: the world quest block also stops the waypoint arrow pointing at one.
    widgets.waypointCb = checkbox(section.body, L.TOOLTIP_WAYPOINT)
    widgets.waypointCb:SetScript("OnClick", function(self)
        QuestPrism.Settings.Set("clearWorldQuestWaypoint", self:GetChecked() and true or false)
        if QuestPrism.WorldQuests and QuestPrism.WorldQuests.EnforceWaypoint then
            pcall(QuestPrism.WorldQuests.EnforceWaypoint)
        end
        changed()
    end)
    addRow(section, { name = L.WAYPOINT_LABEL, desc = L.WAYPOINT_DESC, control = widgets.waypointCb, tooltip = L.TOOLTIP_WAYPOINT })
end

local SCOPE_OPTIONS = {
    { key = "step",      label = L.GUIDE_SCOPE_STEP },
    { key = "lookahead", label = L.GUIDE_SCOPE_LOOKAHEAD },
    { key = "guide",     label = L.GUIDE_SCOPE_GUIDE },
}

local function sourceOptions()
    local options = {}
    for _, name in ipairs(QuestPrism.Sources.AvailableNames()) do
        options[#options + 1] = { key = name, label = QuestPrism.Sources.GetLabel(name) }
    end
    return options
end

local function buildGuideSection()
    local section = newSection(L.SECTION_GUIDE, "right")
    section:addHeaderButton(L.GUIDE_SHOW_ON_MAP, 100, function()
        if QuestPrism.GuideTab and QuestPrism.GuideTab.ShowOnMap then QuestPrism.GuideTab.ShowOnMap() end
    end, L.TOOLTIP_GUIDE_SHOW_ON_MAP)
    widgets.followCb = checkbox(section.body, L.TOOLTIP_FOLLOW_GUIDE)
    widgets.followCb:SetScript("OnClick", function(self)
        if not QuestPrism.Sources.SetFollowing(self:GetChecked() and true or false) then
            self:SetChecked(false)
        end
        changed()
    end)
    widgets.followRow = addRow(section, { name = L.FOLLOW_GUIDE_LABEL, desc = L.FOLLOW_GUIDE_DESC, control = widgets.followCb, tooltip = L.TOOLTIP_FOLLOW_GUIDE })

    -- Opt-in duplicates of the map tab's source and scope. The rows are always present
    -- while the option is on and grey out when no guide is being followed, so nothing
    -- appears or disappears as you tick things.
    widgets.guideInWindowCb = checkbox(section.body, L.TOOLTIP_GUIDE_IN_WINDOW)
    widgets.guideInWindowCb:SetScript("OnClick", function(self)
        QuestPrism.Settings.Set("guideControlsInWindow", self:GetChecked() and true or false)
        syncWidgets()
    end)
    addRow(section, { name = L.GUIDE_IN_WINDOW_LABEL, desc = L.GUIDE_IN_WINDOW_DESC, control = widgets.guideInWindowCb, tooltip = L.TOOLTIP_GUIDE_IN_WINDOW })

    widgets.sourceDropdown = optionDropdown(section.body, 150, sourceOptions,
        function() return QuestPrism.Settings.Get("guideSource") or "Off" end,
        function(key)
            QuestPrism.Settings.Set("guideSource", key)
            QuestPrism.Settings.Set("guideLastSource", key)
            changed()
        end, L.GUIDE_SOURCE_OFF, L.TOOLTIP_GUIDE_SOURCE)
    widgets.sourceRow = addRow(section, { name = L.GUIDE_SOURCE_LABEL, control = widgets.sourceDropdown, controlWidth = 150 })

    widgets.scopeDropdown = optionDropdown(section.body, 150, function() return SCOPE_OPTIONS end,
        function() return QuestPrism.Settings.Get("guideScope") or "lookahead" end,
        function(key) QuestPrism.Settings.Set("guideScope", key); changed() end,
        L.GUIDE_SCOPE_LOOKAHEAD, L.TOOLTIP_GUIDE_SCOPE)
    widgets.scopeRow = addRow(section, { name = L.GUIDE_SCOPE_LABEL, control = widgets.scopeDropdown, controlWidth = 150 })

    widgets.lookaheadStepper = stepperControl(section.body, 1, 10,
        function() return tonumber(QuestPrism.Settings.Get("guideLookahead")) or 3 end,
        function(value) QuestPrism.Settings.Set("guideLookahead", value); changed() end,
        L.TOOLTIP_GUIDE_LOOKAHEAD)
    widgets.lookaheadRow = addRow(section, { name = L.GUIDE_LOOKAHEAD_LABEL, control = widgets.lookaheadStepper, controlWidth = 90 })
end

local function buildAddonSection()
    local section = newSection(L.SECTION_ADDON, "right")
    widgets.minimapCb = checkbox(section.body, L.OPTIONS_HIDE_MINIMAP_TOOLTIP)
    widgets.minimapCb:SetScript("OnClick", function(self)
        QuestPrism.MinimapButton.SetHidden(not self:GetChecked())
        syncWidgets()
    end)
    addRow(section, { name = L.MINIMAP_BUTTON_LABEL, control = widgets.minimapCb, tooltip = L.OPTIONS_HIDE_MINIMAP_TOOLTIP })
    widgets.debugCb = checkbox(section.body, L.OPTIONS_DEBUG_TOOLTIP)
    widgets.debugCb:SetScript("OnClick", function(self)
        QuestPrism.Settings.Set("debug", self:GetChecked() and true or false)
    end)
    addRow(section, { name = L.DEBUG_LABEL, control = widgets.debugCb, tooltip = L.OPTIONS_DEBUG_TOOLTIP })
end

-- ---------------------------------------------------------------------------
-- Confirmation popups
-- ---------------------------------------------------------------------------

StaticPopupDialogs["QUESTPRISM_OVERWRITE_PRESET"] = {
    text = L.PRESET_OVERWRITE_CONFIRM, button1 = YES, button2 = NO,
    OnAccept = function(self, name) QuestPrism.Settings.SavePreset(name); QuestPrism.Panel.Sync() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["QUESTPRISM_DELETE_PRESET"] = {
    text = L.PRESET_DELETE_CONFIRM, button1 = YES, button2 = NO,
    OnAccept = function(self, name)
        QuestPrism.Settings.DeletePreset(name)
        QuestPrism.Panel.Sync(); QuestPrism.WorldMap.Refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function savePosition()
    -- Only the standalone position is remembered: beside the map the anchors are
    -- relative to the map frame, not the screen.
    if not frame or anchoredToMap then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then QuestPrismCharDB.panelPos = { point = point, relPoint = relPoint, x = x, y = y } end
end

local function restorePosition()
    local pos = QuestPrismCharDB.panelPos
    frame:ClearAllPoints()
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function createWindow()
    frame = CreateFrame("Frame", PANEL_FRAME_NAME, UIParent, "ButtonFrameTemplate")
    frame:SetSize(layoutMode.width, layoutMode.height)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
    frame:Hide()

    local function field(name)
        local v = rawget(frame, name)
        if type(v) == "table" or type(v) == "function" then return v end
        return nil
    end
    local setTitle = field("SetTitle")
    local titleContainer, titleText = field("TitleContainer"), field("TitleText")
    if type(setTitle) == "function" then
        pcall(setTitle, frame, "QuestPrism")
    elseif type(titleContainer) == "table" and type(rawget(titleContainer, "TitleText")) == "table" then
        titleContainer.TitleText:SetText("QuestPrism")
    elseif type(titleText) == "table" then
        titleText:SetText("QuestPrism")
    end
    local setPortrait = field("SetPortraitToAsset")
    local portraitContainer, portrait = field("PortraitContainer"), field("portrait")
    if type(setPortrait) == "function" then
        pcall(setPortrait, frame, ICON)
    elseif type(portraitContainer) == "table" and type(rawget(portraitContainer, "portrait")) == "table" then
        portraitContainer.portrait:SetTexture(ICON)
    elseif type(portrait) == "table" then
        portrait:SetTexture(ICON)
    end

    -- Escape closes the window like any other panel.
    if UISpecialFrames then tinsert(UISpecialFrames, PANEL_FRAME_NAME) end

    local inset = field("Inset")
    if type(inset) ~= "table" then inset = frame end
    scrollFrame = CreateFrame("ScrollFrame", nil, inset)
    scrollFrame:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -24, 24)
    scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 0)
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        pcall(ScrollUtil.InitScrollFrameWithScrollBar, scrollFrame, scrollBar)
    end
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(CONTENT_W, 10)
    scrollFrame:SetScrollChild(content)

    statusText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 10, 6)
    statusText:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -10, 6)
    statusText:SetJustifyH("LEFT")
    statusText:SetText(L.STATUS_HINT)

    -- The preset and Filters rows share the first section frame, with no header text.
    local top = newSection("", "span")
    top.header:Hide()
    top.headerHeight = 0
    buildTopRows(top)
    buildShowSection()
    buildAppliesSection()
    buildGuideSection()
    buildAddonSection()
    restorePosition()
    -- Closing the window mid "Save as..." must not leave the dropdown hidden.
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnHide", function() widgets.closePresetBox() end)
    end
    ready = true
    syncWidgets()
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function QuestPrism.Panel.UpdateStatus(total)
    if not ready then return end
    total = total or (QuestPrism.WorldMap.GetHiddenTotal and QuestPrism.WorldMap.GetHiddenTotal()) or 0
    local parts = {}
    if total > 0 then parts[#parts + 1] = string.format(L.STATUS_HIDDEN_COUNT, total) end
    if QuestPrism.Sources.IsFollowing() then
        local adapter, name = QuestPrism.Sources.GetActive()
        local okStep, step = pcall(function() return adapter and adapter.GetStepNumber() end)
        parts[#parts + 1] = string.format(L.STATUS_FOLLOWING, QuestPrism.Sources.GetLabel(name), tonumber(okStep and step) or 0)
    end
    statusText:SetText(#parts > 0 and table.concat(parts, " ") or L.STATUS_HINT)
    if widgets.followRow then
        widgets.followRow.desc:SetText(QuestPrism.Sources.GetStatusText() .. " " .. L.FOLLOW_GUIDE_DESC)
        -- The description may have gained or lost a line; Toggle re-lays out a hidden window anyway.
        if frame:IsShown() then layoutAll() end
    end
end

function QuestPrism.Panel.Initialize()
    local ok, err = pcall(createWindow)
    if not ok then
        QuestPrism.Panel.lastError = tostring(err)
        return
    end
    QuestPrism.Panel.frame = { frame = frame }
    if QuestPrism.WorldMap.SetRefreshListener then
        QuestPrism.WorldMap.SetRefreshListener(function(total) QuestPrism.Panel.UpdateStatus(total) end)
    end
end

function QuestPrism.Panel.Sync()
    if not ready then return end
    syncWidgets()
    QuestPrism.Panel.UpdateStatus()
end

local function anchorToWorldMap()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    frame:ClearAllPoints()
    local maximized = WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
    if maximized then
        frame:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -40, -90)
    else
        frame:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 8, 0)
    end
end

-- anchorToMap: opened from the map button or the tab's gear -> one tall column
-- beside the map. Otherwise the standalone two-column shape at its saved position.
function QuestPrism.Panel.Toggle(anchorToMap)
    if not ready then return end
    if frame:IsShown() then frame:Hide(); return end
    anchoredToMap = anchorToMap and true or false
    applyLayoutMode(anchoredToMap and LAYOUT_BESIDE_MAP or LAYOUT_STANDALONE)
    QuestPrism.Panel.Sync()
    if anchoredToMap then
        pcall(anchorToWorldMap)
    else
        restorePosition()
    end
    frame:Show()
end

function QuestPrism.Panel.IsShown()
    return ready and frame:IsShown()
end

-- Exposed for tests.
function QuestPrism.Panel.GetWidgets()
    return widgets
end

function QuestPrism.Panel.GetLayoutColumns()
    return layoutMode.columns
end
