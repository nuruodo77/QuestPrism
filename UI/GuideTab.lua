QuestPrism.GuideTab = {}

-- "QuestPrism" tab in the world map's side panel (beside Quests, Events, Map
-- Legend): the guide's home. Blizzard's list is left intact; ours shows the active
-- guide's quests, in guide order:
--   * "In your log" : accepted, with objectives and turn-in state
--   * "To pick up"  : not accepted yet (titles loaded on demand)
--   * list footer   : number already completed
-- Header: "Follow my guide" checkbox + gear (settings window), Source dropdown
-- (only when more than one guide addon is available), scope buttons
-- (Step / Next N / Guide) with a stepper for N, and the status line.
-- Buttons come from UI/Widgets.lua; the list sits in a bordered inset with the
-- modern thin scroll bar and collapsible plate headers, so the tab matches the
-- settings window and the quest log it sits beside.
-- Click a log quest: Blizzard's details. Right-click: track / untrack.
-- Tab switching goes through Blizzard's display mode (SetDisplayMode) with a mode
-- of our own; the tab is parented to a holder frame (the template has parentArray).

local L = QuestPrism_L
local MODE = "QuestPrism"
local ICON = "Interface\\AddOns\\QuestPrism\\Textures\\icon"
local RENDER_DELAY = 0.1
local LOOKAHEAD_MIN, LOOKAHEAD_MAX = 1, 10

local holder, tab, panel, header, scroll, scrollBar, listInset, content, emptyText
local ready = false -- true once the header and list exist; a half-built tab stays inert
local scopeButtons = {}
local hdr = {} -- header widgets: followCb, followLabel, gear, sourceLabel, sourceDropdown, minus, plus, count
local rowPool, headerPool = {}, {}
local activeRows, activeHeaders = {}, {}
local renderPending = false

-- ---------------------------------------------------------------------------
-- Data (pure, tested)
-- ---------------------------------------------------------------------------

-- Row icon for a quest known only by its ID. Goes through the filter's own lookup
-- (C_QuestInfoSystem, with the older-client fallbacks) so the tab and the map always
-- classify a quest the same way.
local function questTypeAtlas(questID)
    if not (QuestPrism.Filter and QuestPrism.Filter.GetQuestType) then return nil end
    local ok, questType = pcall(QuestPrism.Filter.GetQuestType, questID)
    if not ok or not questType then return nil end
    local types = QuestPrism.Panel and QuestPrism.Panel.QUEST_TYPES or {}
    for _, info in ipairs(types) do
        if info.key == questType then return info.atlas end
    end
    return nil
end
QuestPrism.GuideTab.GetQuestTypeAtlas = function(questID) return questTypeAtlas(questID) end

function QuestPrism.GuideTab.BuildEntries(list)
    local result = { inLog = {}, toPickUp = {}, completed = 0 }
    if type(list) ~= "table" or not C_QuestLog then return result end
    local seen = {}
    for _, item in ipairs(list) do
        local questID = tonumber(item.questID)
        if questID and not seen[questID] then
            seen[questID] = true
            local flagged = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID)
            if flagged then
                result.completed = result.completed + 1
            else
                local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
                local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
                if logIndex then
                    local objectives = (C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)) or {}
                    local isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) or false
                    local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) ~= nil
                    table.insert(result.inLog, {
                        questID = questID, step = item.step, inLog = true,
                        title = title or string.format(L.GUIDETAB_UNKNOWN_QUEST, questID),
                        objectives = objectives, isComplete = isComplete, watched = watched,
                    })
                else
                    if not title and C_QuestLog.RequestLoadQuestByID then
                        pcall(C_QuestLog.RequestLoadQuestByID, questID)
                    end
                    table.insert(result.toPickUp, {
                        questID = questID, step = item.step, inLog = false,
                        title = title or string.format(L.GUIDETAB_UNKNOWN_QUEST, questID),
                    })
                end
            end
        end
    end
    return result
end

-- Track / untrack a log quest in the objective tracker.
function QuestPrism.GuideTab.ToggleWatch(questID)
    if not (C_QuestLog and C_QuestLog.AddQuestWatch and C_QuestLog.RemoveQuestWatch) then return end
    local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) ~= nil
    if watched then
        pcall(C_QuestLog.RemoveQuestWatch, questID)
    else
        pcall(C_QuestLog.AddQuestWatch, questID)
    end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local ROW_PADDING = 6
local ROW_INDENT = 26

local function numberOr(value, default)
    if type(value) == "number" and value > 0 then return value end
    return default
end

-- Section headers are the game's list-header plate: a three-slice bar with a
-- collapse arrow, the same art the quest log's own category headers use.
local HEADER_H = 22

local function toggleSection(header)
    if not header.sectionKey then return end
    QuestPrism.Settings.Set(header.sectionKey, not (QuestPrism.Settings.Get(header.sectionKey) == true))
    QuestPrism.GuideTab.Refresh()
end

local function acquireHeader()
    local header = table.remove(headerPool)
    if not header then
        header = CreateFrame("Button", nil, content)
        header:SetHeight(HEADER_H)
        header.Left = header:CreateTexture(nil, "BACKGROUND")
        header.Left:SetPoint("TOPLEFT")
        header.Left:SetPoint("BOTTOMLEFT")
        pcall(header.Left.SetAtlas, header.Left, "Options_ListExpand_Left", true)
        header.Right = header:CreateTexture(nil, "BACKGROUND")
        header.Right:SetPoint("TOPRIGHT")
        header.Right:SetPoint("BOTTOMRIGHT")
        pcall(header.Right.SetAtlas, header.Right, "Options_ListExpand_Right", true)
        header.Middle = header:CreateTexture(nil, "BACKGROUND")
        header.Middle:SetPoint("TOPLEFT", header.Left, "TOPRIGHT")
        header.Middle:SetPoint("BOTTOMRIGHT", header.Right, "BOTTOMLEFT")
        pcall(header.Middle.SetAtlas, header.Middle, "_Options_ListExpand_Middle")
        header.Expander = header:CreateTexture(nil, "ARTWORK")
        header.Expander:SetSize(16, 16)
        header.Expander:SetPoint("LEFT", header, "LEFT", 6, 0)
        pcall(header.Expander.SetAtlas, header.Expander, "common-button-list-collapseExpand")
        header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header.Text:SetPoint("LEFT", header.Expander, "RIGHT", 4, 0)
        header.Text:SetPoint("RIGHT", header, "RIGHT", -6, 0)
        header.Text:SetJustifyH("LEFT")
        local highlight = header:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.07)
        header:SetScript("OnClick", toggleSection)
    end
    header:Show()
    table.insert(activeHeaders, header)
    return header
end

local function onRowClick(row, button)
    local entry = row.entry
    if not entry then return end
    if button == "RightButton" then
        if entry.inLog then
            QuestPrism.GuideTab.ToggleWatch(entry.questID)
            QuestPrism.GuideTab.Refresh()
        end
        return
    end
    if entry.inLog and type(QuestMapFrame_OpenToQuestDetails) == "function" then
        pcall(QuestMapFrame_OpenToQuestDetails, entry.questID)
    end
end

local function onRowEnter(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(entry.title)
    if entry.step then GameTooltip:AddLine(string.format(L.GUIDETAB_STEP, entry.step), 0.7, 0.7, 0.7) end
    if entry.inLog then
        GameTooltip:AddLine(entry.isComplete and L.GUIDETAB_READY or L.GUIDETAB_CLICK_DETAILS, 1, 1, 1)
        GameTooltip:AddLine(entry.watched and L.GUIDETAB_UNTRACK_HINT or L.GUIDETAB_TRACK_HINT, 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(L.GUIDETAB_NOT_ACCEPTED, 1, 0.82, 0)
    end
    GameTooltip:Show()
end

local function acquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, content)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(16, 16)
        row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
        row.Title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
        row.Title:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_INDENT, -2)
        row.Title:SetPoint("RIGHT", row, "RIGHT", -20, 0)
        row.Title:SetJustifyH("LEFT")
        row.Title:SetWordWrap(true)
        row.Objectives = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Objectives:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -2)
        row.Objectives:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.Objectives:SetJustifyH("LEFT")
        row.Objectives:SetWordWrap(true)
        -- Discreet check mark on the right: quest tracked in the objective tracker.
        row.Watch = row:CreateTexture(nil, "OVERLAY")
        row.Watch:SetSize(12, 12)
        row.Watch:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
        pcall(row.Watch.SetAtlas, row.Watch, "common-icon-checkmark")
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnClick", onRowClick)
        row:SetScript("OnEnter", onRowEnter)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row:Show()
    table.insert(activeRows, row)
    return row
end

local function releaseAll()
    for _, row in ipairs(activeRows) do row:Hide(); row.entry = nil; table.insert(rowPool, row) end
    for _, h in ipairs(activeHeaders) do h:Hide(); h.sectionKey = nil; table.insert(headerPool, h) end
    activeRows, activeHeaders = {}, {}
end

local function objectivesText(entry)
    if entry.isComplete then
        return "|cff20ff20" .. L.GUIDETAB_READY .. "|r"
    end
    local lines = {}
    for _, objective in ipairs(entry.objectives or {}) do
        if objective.text and objective.text ~= "" then
            if objective.finished then
                table.insert(lines, "|cff808080- " .. objective.text .. "|r")
            else
                table.insert(lines, "- " .. objective.text)
            end
        end
    end
    return table.concat(lines, "\n")
end

local function layoutRow(row, entry, width, y)
    row.entry = entry
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    local atlas = questTypeAtlas(entry.questID)
    if atlas then
        row.Icon:Show()
        pcall(row.Icon.SetAtlas, row.Icon, atlas)
    else
        row.Icon:Hide()
    end
    row.Icon:SetDesaturated(not entry.inLog)
    row.Title:SetText(entry.title)
    if entry.inLog then
        row.Title:SetTextColor(1, 0.82, 0)
        row.Objectives:SetText(objectivesText(entry))
        row.Watch:SetShown(entry.watched == true)
    else
        row.Title:SetTextColor(0.6, 0.6, 0.6)
        row.Objectives:SetText("")
        row.Watch:Hide()
    end
    local height = numberOr(row.Title:GetStringHeight(), 14) + 4
    local objHeight = numberOr(row.Objectives:GetStringHeight(), 0)
    if objHeight > 0 then height = height + objHeight + 2 end
    height = height + ROW_PADDING
    row:SetHeight(height)
    return height
end

-- sectionKey nil means a plain caption (the completed footer): no arrow, no click.
local function layoutHeader(text, width, y, sectionKey)
    local header = acquireHeader()
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
    header:SetWidth(math.max(40, width - 8))
    header:SetHeight(HEADER_H)
    header.Text:SetText(text)
    header.sectionKey = sectionKey
    header:SetEnabled(sectionKey ~= nil)
    header.Expander:SetShown(sectionKey ~= nil)
    if sectionKey then
        -- One arrow atlas, turned to point down when the section is open.
        local collapsed = QuestPrism.Settings.Get(sectionKey) == true
        pcall(header.Expander.SetRotation, header.Expander, collapsed and 0 or -math.pi / 2)
        header.Text:SetPoint("LEFT", header.Expander, "RIGHT", 4, 0)
    else
        header.Text:SetPoint("LEFT", header, "LEFT", 8, 0)
    end
    return HEADER_H + 4
end

-- Header state: follow checkbox, source row (shown only with a choice), scope
-- buttons (active one pressed, all greyed when not following), stepper, status.
-- Positions depend on whether the source row is shown, so the list is re-anchored.
local function syncHeader()
    if not ready then return end
    local following = QuestPrism.Sources.IsFollowing()
    local available = QuestPrism.Sources.AvailableNames()
    local scope = QuestPrism.Settings.Get("guideScope") or "lookahead"
    local lookahead = tonumber(QuestPrism.Settings.Get("guideLookahead")) or 3

    hdr.followCb:SetChecked(following)
    local y = 34
    local showSource = following and #available > 1
    hdr.sourceLabel:SetShown(showSource)
    hdr.sourceDropdown:SetShown(showSource)
    if showSource then
        hdr.sourceDropdown:QLRefresh()
        y = y + 28
    end
    local x = 6
    for _, key in ipairs({ "step", "lookahead", "guide" }) do
        local button = scopeButtons[key]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
        if key == "lookahead" then button:SetText(string.format(L.GUIDETAB_SCOPE_NEXT, lookahead)) end
        -- The active scope's button is "pressed" (disabled): readable at a glance.
        button:SetEnabled(following and key ~= scope)
        x = x + numberOr(button:GetWidth(), 50) + 4
    end
    hdr.minus:ClearAllPoints(); hdr.minus:SetPoint("TOPLEFT", panel, "TOPLEFT", x + 6, -y)
    hdr.count:SetText(tostring(lookahead))
    local stepperOn = following and scope == "lookahead"
    hdr.minus:SetEnabled(stepperOn and lookahead > LOOKAHEAD_MIN)
    hdr.plus:SetEnabled(stepperOn and lookahead < LOOKAHEAD_MAX)
    y = y + 34 -- the scope buttons are 28 tall

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -y)
    header:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    header:SetText(QuestPrism.Sources.GetStatusText())
    y = y + numberOr(header:GetStringHeight(), 12) + 8

    listInset:ClearAllPoints()
    listInset:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -(y - 2))
    listInset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", listInset, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", listInset, "BOTTOMRIGHT", -22, 4)
    emptyText:ClearAllPoints()
    emptyText:SetPoint("TOP", listInset, "TOP", 0, -30)
end

local function render()
    if not ready or not panel:IsShown() then return end
    releaseAll()
    syncHeader()
    local list = QuestPrism.Sources.GetActiveQuestList and QuestPrism.Sources.GetActiveQuestList() or nil
    local width = math.max(50, numberOr(scroll:GetWidth(), 280))
    content:SetWidth(width)

    if not list then
        emptyText:SetText(L.GUIDETAB_NO_SOURCE)
        emptyText:Show()
        content:SetHeight(1)
        return
    end

    local entries = QuestPrism.GuideTab.BuildEntries(list)
    local y = 4
    local function section(key, text, list)
        if #list == 0 then return end
        y = y + layoutHeader(text, width, y, key)
        if QuestPrism.Settings.Get(key) ~= true then
            for _, entry in ipairs(list) do
                y = y + layoutRow(acquireRow(), entry, width, y)
            end
        end
        y = y + 6
    end
    section("guideCollapsedInLog", string.format(L.GUIDETAB_IN_LOG, #entries.inLog), entries.inLog)
    section("guideCollapsedToPickUp", string.format(L.GUIDETAB_TO_PICK_UP, #entries.toPickUp), entries.toPickUp)
    if entries.completed > 0 then
        y = y + layoutHeader("|cff808080" .. string.format(L.GUIDETAB_COMPLETED, entries.completed) .. "|r", width, y)
    end
    if #entries.inLog == 0 and #entries.toPickUp == 0 then
        emptyText:SetText(L.GUIDETAB_EMPTY)
        emptyText:Show()
    else
        emptyText:Hide()
    end
    content:SetHeight(math.max(y, 1))
end

local function scheduleRender()
    if renderPending then return end
    renderPending = true
    C_Timer.After(RENDER_DELAY, function()
        renderPending = false
        pcall(render)
    end)
end

-- ---------------------------------------------------------------------------
-- Tab + panel
-- ---------------------------------------------------------------------------

local function setTabChecked(checked)
    if not tab then return end
    if type(tab.SetChecked) == "function" then pcall(tab.SetChecked, tab, checked) end
    local icon = rawget(tab, "Icon")
    if type(icon) == "table" then
        icon:SetTexture(ICON)
        icon:SetSize(26, 26)
        icon:SetAlpha(checked and 1 or 0.65)
        if icon.SetDesaturated then icon:SetDesaturated(not checked) end
    end
    local selected = rawget(tab, "SelectedTexture")
    if type(selected) == "table" then selected:SetShown(checked) end
end

local function isActive()
    return type(QuestMapFrame) == "table" and QuestMapFrame.displayMode == MODE
end

function QuestPrism.GuideTab.OnDisplayModeChanged(mode)
    local active = (mode == MODE)
    if panel then panel:SetShown(active) end
    setTabChecked(active)
    if active then scheduleRender() end
end

function QuestPrism.GuideTab.Select()
    if not (type(QuestMapFrame) == "table" and type(QuestMapFrame.SetDisplayMode) == "function") then return end
    pcall(QuestMapFrame.SetDisplayMode, QuestMapFrame, MODE)
    if not (EventRegistry and EventRegistry.RegisterCallback) then
        QuestPrism.GuideTab.OnDisplayModeChanged(MODE)
    end
end

-- Opens the world map (and its side panel) on our tab.
function QuestPrism.GuideTab.ShowOnMap()
    if type(WorldMapFrame) == "table" and not WorldMapFrame:IsShown() then
        if type(OpenWorldMap) == "function" then
            pcall(OpenWorldMap)
        elseif type(ShowUIPanel) == "function" then
            pcall(ShowUIPanel, WorldMapFrame)
        end
    end
    if type(QuestMapFrame) == "table" and QuestMapFrame.IsShown and not QuestMapFrame:IsShown()
        and type(QuestMapFrame_Show) == "function" then
        pcall(QuestMapFrame_Show)
    end
    QuestPrism.GuideTab.Select()
end

-- After any guide setting changes here: map, settings window, this header + list.
local function guideChanged()
    QuestPrism.WorldMap.Refresh()
    if QuestPrism.Panel and QuestPrism.Panel.Sync then QuestPrism.Panel.Sync() end
    syncHeader()
    scheduleRender()
end

local function setScope(scope)
    QuestPrism.Settings.Set("guideScope", scope)
    guideChanged()
end

local function stepLookahead(delta)
    local value = (tonumber(QuestPrism.Settings.Get("guideLookahead")) or 3) + delta
    value = math.max(LOOKAHEAD_MIN, math.min(LOOKAHEAD_MAX, value))
    if value ~= tonumber(QuestPrism.Settings.Get("guideLookahead")) then
        QuestPrism.Settings.Set("guideLookahead", value)
        guideChanged()
    end
end

local function tooltip(region, text, anchor)
    region:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
        GameTooltip:SetText(text, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    region:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function sourceOptions()
    local options = {}
    for _, name in ipairs(QuestPrism.Sources.AvailableNames()) do
        options[#options + 1] = { key = name, label = QuestPrism.Sources.GetLabel(name) }
    end
    return options
end

local function createHeader()
    -- Row 1: [x] Follow my guide .......... [gear]
    hdr.followCb = CreateFrame("CheckButton", nil, panel, "MinimalCheckboxTemplate")
    hdr.followCb:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    hdr.followCb:SetScript("OnClick", function(self)
        if not QuestPrism.Sources.SetFollowing(self:GetChecked() and true or false) then
            self:SetChecked(false)
        end
        guideChanged()
    end)
    tooltip(hdr.followCb, L.TOOLTIP_FOLLOW_GUIDE, "ANCHOR_RIGHT")
    hdr.followLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr.followLabel:SetPoint("LEFT", hdr.followCb, "RIGHT", 2, 0)
    hdr.followLabel:SetText(L.FOLLOW_GUIDE_LABEL)

    hdr.gear = CreateFrame("Button", nil, panel)
    hdr.gear:SetSize(20, 20)
    hdr.gear:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -8)
    hdr.gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    hdr.gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    hdr.gear:SetScript("OnClick", function() QuestPrism.Panel.Toggle(true) end)
    tooltip(hdr.gear, L.GUIDETAB_SETTINGS_TOOLTIP, "ANCHOR_LEFT")

    -- Row 2 (optional): Source [dropdown]
    hdr.sourceLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr.sourceLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -40)
    hdr.sourceLabel:SetText(L.GUIDETAB_SOURCE)
    local dd = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", panel, "TOPLEFT", 60, -34)
    dd:SetWidth(170)
    local function isSelected(key) return QuestPrism.Settings.Get("guideSource") == key end
    local function onSelect(key)
        QuestPrism.Settings.Set("guideSource", key)
        QuestPrism.Settings.Set("guideLastSource", key)
        guideChanged()
    end
    if type(dd.SetupMenu) == "function" then
        dd:SetupMenu(function(_, rootDescription)
            for _, option in ipairs(sourceOptions()) do
                rootDescription:CreateRadio(option.label, isSelected, onSelect, option.key)
            end
        end)
    end
    dd.QLRefresh = function(self)
        local text = QuestPrism.Sources.GetLabel(QuestPrism.Settings.Get("guideSource") or "Off")
        self.QLText = text
        if type(self.SetDefaultText) == "function" then self:SetDefaultText(text) end
        if type(self.GenerateMenu) == "function" then pcall(self.GenerateMenu, self) end
        if type(self.OverrideText) == "function" then pcall(self.OverrideText, self, text) end
    end
    tooltip(dd, L.TOOLTIP_GUIDE_SOURCE, "ANCHOR_RIGHT")
    hdr.sourceDropdown = dd

    -- Row 3: [Step] [Next N] [Guide]  [-] N [+]
    local defs = {
        { key = "step",      text = L.GUIDETAB_SCOPE_STEP,  width = 48 },
        { key = "lookahead", text = string.format(L.GUIDETAB_SCOPE_NEXT, 3), width = 60 },
        { key = "guide",     text = L.GUIDETAB_SCOPE_GUIDE, width = 50 },
    }
    for _, def in ipairs(defs) do
        local btn = QuestPrism.Widgets.Button(panel, def.text, def.width, function() setScope(def.key) end)
        tooltip(btn, L.TOOLTIP_GUIDE_SCOPE)
        scopeButtons[def.key] = btn
    end
    -- 26 wide, not square: the three-slice caps need room either side of the glyph.
    hdr.minus = QuestPrism.Widgets.Button(panel, "-", 26, function() stepLookahead(-1) end)
    tooltip(hdr.minus, L.TOOLTIP_GUIDE_LOOKAHEAD)
    hdr.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hdr.count:SetPoint("LEFT", hdr.minus, "RIGHT", 0, 0)
    hdr.count:SetWidth(24)
    hdr.count:SetJustifyH("CENTER")
    hdr.plus = QuestPrism.Widgets.Button(panel, "+", 26, function() stepLookahead(1) end)
    hdr.plus:SetPoint("LEFT", hdr.count, "RIGHT", 0, 0)
    tooltip(hdr.plus, L.TOOLTIP_GUIDE_LOOKAHEAD)
end

local function createUI()
    if panel then return end
    if not (type(QuestMapFrame) == "table" and QuestMapFrame.ContentsAnchor and QuestMapFrame.MapLegendTab) then return end

    holder = CreateFrame("Frame", nil, QuestMapFrame)
    holder:SetSize(1, 1)
    holder:SetPoint("TOPLEFT", QuestMapFrame, "TOPLEFT", 0, 0)

    tab = CreateFrame("Frame", nil, holder, "LargeSideTabButtonTemplate")
    tab:SetPoint("TOP", QuestMapFrame.MapLegendTab, "BOTTOM", 0, -3)
    tab.tooltipText = L.GUIDETAB_TOOLTIP
    tab.activeAtlas = "questlog-tab-icon-quest"
    tab.inactiveAtlas = "questlog-tab-icon-quest-inactive"
    tab.displayMode = MODE
    if type(tab.SetCustomOnMouseUpHandler) == "function" then
        tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
            if button == "LeftButton" and upInside ~= false then QuestPrism.GuideTab.Select() end
        end)
    else
        tab:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then QuestPrism.GuideTab.Select() end
        end)
    end
    setTabChecked(false)

    panel = CreateFrame("Frame", nil, QuestMapFrame)
    panel:SetPoint("TOPLEFT", QuestMapFrame.ContentsAnchor, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", QuestMapFrame.ContentsAnchor, "BOTTOMRIGHT", -22, 0)
    panel:Hide()
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    pcall(bg.SetAtlas, bg, "QuestLog-main-background")

    createHeader()

    header = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header:SetJustifyH("LEFT")
    header:SetWordWrap(true)

    -- The list sits in a bordered inset, like Blizzard's own quest list, rather than
    -- floating on the panel background.
    listInset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")

    -- Plain scroll frame plus the modern thin scroll bar, the same pairing the
    -- settings window uses, instead of UIPanelScrollFrameTemplate's chunky legacy bar.
    scroll = CreateFrame("ScrollFrame", nil, panel)
    scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        pcall(ScrollUtil.InitScrollFrameWithScrollBar, scroll, scrollBar)
    end
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function() if panel:IsShown() then scheduleRender() end end)

    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetWidth(240)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetWordWrap(true)
    emptyText:Hide()
    ready = true
    syncHeader()

    panel:RegisterEvent("QUEST_LOG_UPDATE")
    panel:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    panel:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    panel:RegisterEvent("SUPER_TRACKING_CHANGED")
    panel:SetScript("OnEvent", function() if panel:IsShown() then scheduleRender() end end)
    panel:SetScript("OnShow", function() scheduleRender() end)

    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", function(_, mode)
            QuestPrism.GuideTab.OnDisplayModeChanged(mode)
        end, QuestPrism.GuideTab)
    end
    if QuestMapFrame.HookScript then
        QuestMapFrame:HookScript("OnShow", function()
            if isActive() then QuestPrism.GuideTab.OnDisplayModeChanged(MODE) end
        end)
    end
end

function QuestPrism.GuideTab.Initialize()
    local ok, err = pcall(createUI)
    if not ok then QuestPrism.GuideTab.lastError = tostring(err) end
end

function QuestPrism.GuideTab.Refresh()
    if ready and panel:IsShown() then scheduleRender() end
end

-- Called by the settings window and the quick menu after a guide change.
function QuestPrism.GuideTab.Sync()
    if not ready then return end
    syncHeader()
    if panel:IsShown() then scheduleRender() end
end

-- Exposed for tests.
QuestPrism.GuideTab.IsCreated = function() return ready end
QuestPrism.GuideTab.GetTab = function() return tab end
QuestPrism.GuideTab.GetPanel = function() return panel end
QuestPrism.GuideTab.GetScopeButtons = function() return scopeButtons end
QuestPrism.GuideTab.GetHeaderWidgets = function() return hdr end
QuestPrism.GuideTab.GetActiveHeaders = function() return activeHeaders end
QuestPrism.GuideTab.GetActiveRows = function() return activeRows end
QuestPrism.GuideTab.GetListInset = function() return listInset end
QuestPrism.GuideTab.MODE = MODE
