-- Guide source: Zygor Guides Viewer.
-- Public structures read: ZGV.CurrentGuide.steps[i].goals[j].questid,
-- ZGV.CurrentStepNum, ZGV.CurrentGuide.title; message "ZGV_STEP_CHANGED".

-- ownsWaypoint: Zygor draws its own arrow (its Arrows module), so QuestPrism never
-- touches waypoint state while this guide is being followed.
local adapter = { label = "Zygor", ownsWaypoint = true }

local function guide()
    if type(ZGV) ~= "table" then return nil end
    local current = ZGV.CurrentGuide
    if type(current) ~= "table" or type(current.steps) ~= "table" then return nil end
    return current
end

function adapter.IsAvailable()
    return guide() ~= nil
end

function adapter.GetStepNumber()
    if not guide() then return nil end
    return tonumber(ZGV.CurrentStepNum) or 1
end

function adapter.GetCacheKey()
    local current = guide()
    if not current then return "none" end
    return tostring(current.title) .. ":" .. tostring(adapter.GetStepNumber())
end

local function addStepQuests(step, stepNumber, list, seen)
    for _, goal in ipairs((type(step) == "table" and step.goals) or {}) do
        local id = tonumber(goal.questid)
        if id and not seen[id] then
            seen[id] = true
            list[#list + 1] = { questID = id, step = stepNumber }
        end
    end
end

-- Ordered list { { questID, step }, ... } for the requested scope.
function adapter.GetQuestList(scope, lookahead)
    local current = guide()
    if not current then return nil end
    local steps = current.steps
    local cur = adapter.GetStepNumber() or 1
    local first, last = cur, cur
    if scope == "guide" then
        first, last = 1, #steps
    elseif scope == "lookahead" then
        last = math.min(#steps, cur + (tonumber(lookahead) or 0))
    end
    local list, seen = {}, {}
    for i = first, last do
        addStepQuests(steps[i], i, list, seen)
    end
    return list
end

function adapter.Subscribe(callback)
    if type(ZGV) == "table" and type(ZGV.AddMessageHandler) == "function" then
        ZGV:AddMessageHandler("ZGV_STEP_CHANGED", function() callback() end)
        ZGV:AddMessageHandler("ZGV_GUIDE_LOADED", function() callback() end)
    end
end

QuestPrism.Sources.Register("Zygor", adapter)
