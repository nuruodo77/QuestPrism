-- Guide source: BtWQuests (quest chains).
-- The "guide" is the chain currently displayed in the BtWQuests window
-- (BtWQuestsFrame:GetChain()). BtWQuests does not save it, so the last chain seen
-- is remembered per character (QuestPrismCharDB.btwChainID) to survive a /reload,
-- and reloaded through BtWQuestsDatabase:LoadChain(id).
-- The "steps" are the chain's quests in order, embedded chains flattened; the
-- current step is the first quest not yet completed.
-- API read: BtWQuestsFrame:GetChain/GetCharacter/SetChain, BtWQuestsDatabase:
-- GetChainByID/LoadChain, chain:GetNumItems/GetItem(i, character), item:GetType/
-- GetID/IsCompleted/Visible/IsValidForCharacter/IsEmbed/GetNumItems/GetItem.

-- No ownsWaypoint: BtWQuests has no arrow of its own. It sets a waypoint only when the
-- player clicks one in its window, through BtWQuests_AddWaypoint, which already honours
-- the player's "Use TomTom waypoints" setting there.
local adapter = { label = "BtWQuests" }
local MAX_DEPTH = 4

local function frame()
    if type(BtWQuestsFrame) == "table" then return BtWQuestsFrame end
    return nil
end

local function database()
    if type(BtWQuestsDatabase) == "table" then return BtWQuestsDatabase end
    return nil
end

local function character()
    local f = frame()
    if f and type(f.GetCharacter) == "function" then
        local ok, char = pcall(f.GetCharacter, f)
        if ok and char then return char end
    end
    if type(BtWQuestsCharacters) == "table" and type(BtWQuestsCharacters.GetPlayer) == "function" then
        local ok, char = pcall(BtWQuestsCharacters.GetPlayer, BtWQuestsCharacters)
        if ok then return char end
    end
    return nil
end

local function currentChainID()
    local f = frame()
    local id
    if f and type(f.GetChain) == "function" then
        local ok, value = pcall(f.GetChain, f)
        if ok then id = tonumber(value) end
    end
    if not id then
        id = tonumber(QuestPrism.Settings.Get("btwChainID"))
    end
    return id
end

local function chainByID(id)
    local db = database()
    if not (db and id) then return nil end
    if type(db.GetChainByID) == "function" then
        local ok, chain = pcall(db.GetChainByID, db, id)
        if ok and chain then return chain end
    end
    if type(db.LoadChain) == "function" then
        local ok, chain = pcall(db.LoadChain, db, id)
        if ok and chain then return chain end
    end
    return nil
end

local function callBool(obj, method, ...)
    if type(obj[method]) ~= "function" then return nil end
    local ok, value = pcall(obj[method], obj, ...)
    if ok then return value end
    return nil
end

-- Flattens the chain (and its embedded chains) into an ordered quest list
-- { questID, completed }.
local function collect(container, char, out, depth)
    if depth > MAX_DEPTH or type(container) ~= "table" then return end
    local count = tonumber(callBool(container, "GetNumItems")) or 0
    for index = 1, count do
        local okItem, item = pcall(container.GetItem, container, index, char)
        if okItem and type(item) == "table" then
            local itemType = callBool(item, "GetType")
            if itemType == "quest" then
                local valid = callBool(item, "IsValidForCharacter", char)
                local visible = callBool(item, "Visible", char)
                if valid ~= false and visible ~= false then
                    local id = tonumber(callBool(item, "GetID"))
                    if id then
                        out[#out + 1] = { questID = id, completed = callBool(item, "IsCompleted", char) == true }
                    end
                end
            elseif itemType == "chain" and callBool(item, "IsEmbed") == true then
                collect(item, char, out, depth + 1)
            end
        end
    end
end

local function flattened()
    local chain = chainByID(currentChainID())
    if not chain then return nil end
    local out = {}
    collect(chain, character(), out, 0)
    -- Deduplicate while keeping the order
    local seen, list = {}, {}
    for _, entry in ipairs(out) do
        if not seen[entry.questID] then
            seen[entry.questID] = true
            entry.step = #list + 1
            list[#list + 1] = entry
        end
    end
    return list
end

local function currentStepIndex(list)
    for i, entry in ipairs(list) do
        if not entry.completed then return i end
    end
    return #list
end

function adapter.IsAvailable()
    return chainByID(currentChainID()) ~= nil
end

function adapter.GetStepNumber()
    local list = flattened()
    if not list or #list == 0 then return nil end
    return currentStepIndex(list)
end

function adapter.GetCacheKey()
    local id = currentChainID()
    if not id then return "none" end
    return tostring(id) .. ":" .. tostring(adapter.GetStepNumber() or 0)
end

function adapter.GetQuestList(scope, lookahead)
    local list = flattened()
    if not list then return nil end
    if #list == 0 then return {} end
    local cur = currentStepIndex(list)
    local first, last = cur, cur
    if scope == "guide" then
        first, last = 1, #list
    elseif scope == "lookahead" then
        -- The next N unfinished quests; finished ones do not count.
        local remaining = tonumber(lookahead) or 0
        last = cur
        for i = cur + 1, #list do
            if remaining <= 0 then break end
            last = i
            if not list[i].completed then remaining = remaining - 1 end
        end
    end
    local result = {}
    for i = first, last do
        local entry = list[i]
        if entry then result[#result + 1] = { questID = entry.questID, step = entry.step } end
    end
    return result
end

function adapter.Subscribe(callback)
    local f = frame()
    if f and type(f.SetChain) == "function" then
        hooksecurefunc(f, "SetChain", function(_, id)
            id = tonumber(id)
            if id then QuestPrism.Settings.Set("btwChainID", id) end
            callback()
        end)
    end
end

QuestPrism.Sources.Register("BtWQuests", adapter)
