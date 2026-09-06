-- Guide source: RestedXP Guides.
-- The addon's namespace is private; what its public frame exposes is read:
--   RXPFrame.activeSteps                    -> active steps (step objects)
--   RXPFrame.ScrollChild.framePool[n].step  -> every step of the current guide
--   RXPCData.currentStep                    -> index of the current step (SavedVariable)
--   RXPFrame.BottomFrame.UpdateFrame        -> called on every step change
-- A step has .index and .elements; an element has .questId and/or .ids (list).

-- ownsWaypoint: RestedXP draws its own arrow (RXPG_ARROW), so QuestPrism never
-- touches waypoint state while this guide is being followed.
local adapter = { label = "RestedXP", ownsWaypoint = true }

local function frame()
    if type(RXPFrame) ~= "table" then return nil end
    return RXPFrame
end

-- Ordered list of every step of the current guide (through the bottom list's
-- frame pool), or nil when unavailable.
local function allSteps()
    local f = frame()
    local pool = f and f.ScrollChild and f.ScrollChild.framePool
    if type(pool) ~= "table" then return nil end
    local steps = {}
    for _, stepFrame in ipairs(pool) do
        local step = type(stepFrame) == "table" and stepFrame.step
        if type(step) == "table" and type(step.elements) == "table" then
            steps[#steps + 1] = step
        end
    end
    table.sort(steps, function(a, b) return (tonumber(a.index) or 0) < (tonumber(b.index) or 0) end)
    if #steps == 0 then return nil end
    return steps
end

local function activeSteps()
    local f = frame()
    local active = f and f.activeSteps
    if type(active) ~= "table" then return nil end
    local steps = {}
    for _, step in ipairs(active) do
        if type(step) == "table" and type(step.elements) == "table" then
            steps[#steps + 1] = step
        end
    end
    if #steps == 0 then return nil end
    return steps
end

function adapter.IsAvailable()
    return activeSteps() ~= nil or allSteps() ~= nil
end

function adapter.GetStepNumber()
    if type(RXPCData) == "table" and tonumber(RXPCData.currentStep) then
        return tonumber(RXPCData.currentStep)
    end
    local active = activeSteps()
    return active and tonumber(active[1].index) or nil
end

function adapter.GetCacheKey()
    local f = frame()
    local name = f and f.GuideName and f.GuideName.text and f.GuideName.text.GetText and f.GuideName.text:GetText()
    local steps = allSteps()
    return tostring(name or (steps and #steps) or "?") .. ":" .. tostring(adapter.GetStepNumber())
end

local function addStepQuests(step, list, seen)
    local stepNumber = tonumber(step.index)
    local function add(raw)
        local id = tonumber(raw)
        if id and not seen[id] then
            seen[id] = true
            list[#list + 1] = { questID = id, step = stepNumber }
        end
    end
    for _, element in ipairs(step.elements or {}) do
        add(element.questId)
        if type(element.ids) == "table" then
            for _, listed in pairs(element.ids) do add(listed) end
        end
    end
end

-- Ordered list { { questID, step }, ... } for the requested scope.
function adapter.GetQuestList(scope, lookahead)
    local list, seen = {}, {}
    if scope == "step" then
        -- Active steps are the most faithful definition of "the current step".
        local active = activeSteps()
        if active then
            for _, step in ipairs(active) do addStepQuests(step, list, seen) end
            return list
        end
    end
    local steps = allSteps()
    if not steps then
        local active = activeSteps()
        if not active then return nil end
        for _, step in ipairs(active) do addStepQuests(step, list, seen) end
        return list
    end
    local cur = adapter.GetStepNumber() or 1
    local first, last = cur, cur
    if scope == "guide" then
        first, last = 1, #steps
    elseif scope == "lookahead" then
        last = math.min(#steps, cur + (tonumber(lookahead) or 0))
    end
    for _, step in ipairs(steps) do
        local index = tonumber(step.index) or 0
        if index >= first and index <= last then addStepQuests(step, list, seen) end
    end
    return list
end

function adapter.Subscribe(callback)
    local f = frame()
    if f and f.BottomFrame and type(f.BottomFrame.UpdateFrame) == "function" then
        hooksecurefunc(f.BottomFrame, "UpdateFrame", function() callback() end)
    end
end

QuestPrism.Sources.Register("RXP", adapter)
