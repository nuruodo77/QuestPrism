-- Minimal WoW API mock for QuestPrism logic tests (Lua 5.1)
local M = {}
_G.MOCK = M

-- Timers: recorded, flushed manually
M.timers = {}
C_Timer = {
    After = function(delay, fn) table.insert(M.timers, { delay = delay, fn = fn }) end,
}
function M.flushTimers()
    local pending = M.timers
    M.timers = {}
    for _, t in ipairs(pending) do t.fn() end
    return #pending
end

-- Printing: captured
M.printed = {}
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(M.printed, table.concat(parts, " "))
end

function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetLocale() return "enUS" end
function tinsert(t, v) table.insert(t, v) end
SlashCmdList = {}
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end, Hide = function() end }

-- Frames
local frameMT = {}
frameMT.__index = frameMT
function frameMT:RegisterEvent(e) self.events[e] = true end
function frameMT:UnregisterAllEvents() self.events = {} end
function frameMT:SetScript(name, fn) self.scripts[name] = fn end
function frameMT:GetScript(name) return self.scripts[name] end
function frameMT:Show() self.shown = true end
function frameMT:Hide() self.shown = false end
function frameMT:IsShown() return self.shown end
function frameMT:SetShown(v) self.shown = v and true or false end
function frameMT:SetAlpha(a) self.alpha = a end
function frameMT:GetAlpha() return self.alpha == nil and 1 or self.alpha end
function frameMT:GetChildren() return unpack(self.children) end
function frameMT:SetSize() end
function frameMT:SetPoint() end
function frameMT:SetFrameStrata() end
function frameMT:SetFrameLevel() end
function frameMT:GetFrameLevel() return 1 end
function frameMT:GetParent() return self.parent end
function frameMT:CreateTexture() return setmetatable({ shown = true, children = {}, scripts = {}, events = {}, parent = self,
    SetTexture = function() end, SetAtlas = function() end, SetAllPoints = function() end, SetBlendMode = function() end }, frameMT) end
function frameMT:RegisterForDrag() end
function frameMT:RegisterForClicks() end
function frameMT:OnReleased() end
function frameMT:OnAcquired() end
function frameMT:Fire(event, ...) if self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end end

function M.newFrame(fields)
    local f = setmetatable({ shown = true, children = {}, scripts = {}, events = {} }, frameMT)
    if fields then for k, v in pairs(fields) do f[k] = v end end
    return f
end
M.createdFrames = {}
function CreateFrame(kind, name, parent, template)
    local f = M.newFrame({ parent = parent, template = template, name = name })
    table.insert(M.createdFrames, f)
    return f
end

-- hooksecurefunc: real post-hook
function hooksecurefunc(tbl, name, hook)
    if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
    local orig = tbl[name]
    if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(name) .. " is not a function") end
    tbl[name] = function(...)
        local r = { orig(...) }
        hook(...)
        return unpack(r)
    end
end

-- Enums / APIs used by Filter
Enum = {
    QuestClassification = { Important = 0, Legendary = 1, Campaign = 2, Calling = 3, Meta = 4, Recurring = 5, Questline = 6, Normal = 7, BonusObjective = 8, WorldQuest = 9, Threat = 10 },
    QuestTag = { Legendary = 83 }, -- deliberately no Meta
}
M.accountCompleted = {}
M.worldQuests = {}
M.timeLeft = {}
M.campaign = {}
M.repeatable = {}
C_QuestLog = {
    IsQuestFlaggedCompletedOnAccount = function(id) return M.accountCompleted[id] == true end,
    IsWorldQuest = function(id) return M.worldQuests[id] == true end,
    GetQuestTagInfo = function(id) return nil end,
    IsRepeatableQuest = function(id) return M.repeatable[id] == true end,
}
C_TaskQuest = { GetQuestTimeLeftSeconds = function(id) return M.timeLeft[id] end }
C_CampaignInfo = { GetCampaignID = function(id) return M.campaign[id] or 0 end }
M.cvars = { questPOIWQ = "1" }
C_CVar = {
    GetCVar = function(name) return M.cvars[name] end,
    GetCVarBool = function(name) return M.cvars[name] == "1" end,
    SetCVar = function(name, value) M.cvars[name] = tostring(value) end,
}
M.metadata = { Version = "9.9.9" }
C_AddOns = { GetAddOnMetadata = function(addon, key) return M.metadata[key] end }

-- World map with pin pools
local function newPool(template)
    local pool = { active = {}, template = template }
    function pool:EnumerateActive()
        local list = {}
        for pin in pairs(self.active) do table.insert(list, pin) end
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    return pool
end
function M.resetWorldMap()
    local canvas = M.newFrame()
    WorldMapFrame = M.newFrame({
        pinPools = {},
        ScrollContainer = { Child = canvas },
    })
    WorldMapFrame.canvas = canvas
    function WorldMapFrame:AcquirePin(template, ...)
        if not self.pinPools[template] then self.pinPools[template] = newPool(template) end
        local pin = M.newFrame({ pinTemplate = template })
        self.pinPools[template].active[pin] = true
        table.insert(canvas.children, pin)
        return pin
    end
    function WorldMapFrame:ReleasePin(pin)
        local pool = self.pinPools[pin.pinTemplate]
        if pool then pool.active[pin] = nil end
        pin:Hide()
        if pin.OnReleased then pin:OnReleased() end
        pin.pinTemplate = nil
    end
    -- Blizzard pools reuse the same frame object for a new pin: template set,
    -- new data, and shown again (a zone change does this for every pin).
    function WorldMapFrame:ReacquirePin(pin, template, fields)
        if not self.pinPools[template] then self.pinPools[template] = newPool(template) end
        pin.pinTemplate = template
        if fields then for k, v in pairs(fields) do pin[k] = v end end
        self.pinPools[template].active[pin] = true
        pin:Show()
        if pin.OnAcquired then pin:OnAcquired() end
        return pin
    end
    function WorldMapFrame:EnumeratePinsByTemplate(template)
        if self.pinPools[template] then return self.pinPools[template]:EnumerateActive() end
        return function() return nil end
    end
    function WorldMapFrame:GetCanvasContainer() return self.ScrollContainer end
    -- Data providers, as Blizzard wires them: a set keyed by provider object,
    -- each refreshed synchronously inside OnMapChanged.
    WorldMapFrame.dataProviders = {}
    function WorldMapFrame:AddDataProvider(provider) self.dataProviders[provider] = true end
    function WorldMapFrame:OnMapChanged()
        for provider in pairs(self.dataProviders) do provider:RefreshAllData() end
    end
    function WorldMapFrame:RefreshOverlayFrames() end
    WorldMapFrame.overlayFrames = {}
end
M.resetWorldMap()
-- Minimap tracking filters (engine): index -> state
M.tracking = {
    { filterID = 0x400,    active = false, name = "Trivial Quests" },
    { filterID = 0x200000, active = true,  name = "Account Completed Quests" },
    { filterID = 0x2,      active = true,  name = "Banker" },
}
M.setTrackingCalls = {}
Enum.MinimapTrackingFilter = { TrivialQuests = 0x400, AccountCompletedQuests = 0x200000, Banker = 0x2 }
C_Minimap = {
    GetNumTrackingTypes = function() return #M.tracking end,
    GetTrackingFilter = function(i) return { filterID = M.tracking[i].filterID } end,
    GetTrackingInfo = function(i) local t = M.tracking[i]; return { name = t.name, active = t.active, filterID = t.filterID } end,
    SetTracking = function(i, on) M.tracking[i].active = on; table.insert(M.setTrackingCalls, { i, on }) end,
}

M.superTracked = 0
C_SuperTrack = {
    GetSuperTrackedQuestID = function() return M.superTracked end,
    SetSuperTrackedQuestID = function(id) M.superTracked = id or 0 end,
}

-- Modern three-slice button family (SharedButton*Template) is present on retail.
ThreeSliceButtonMixin = {}

QuestPinMixin = { OnAcquired = function() end }
QuestDataProviderMixin = { RefreshAllData = function() end }

return M
