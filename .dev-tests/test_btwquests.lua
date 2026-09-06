bootCore()

-- Fake BtWQuests: a chain of items; item wrappers mimic DatabaseItemMetatable bound methods.
local completedQuests = {}
local function questItem(id) return {
    GetType = function() return "quest" end,
    GetID = function() return id end,
    IsCompleted = function(_, char) return completedQuests[id] == true end,
    Visible = function() return true end,
    IsValidForCharacter = function() return true end,
} end
local function embeddedChain(items) return {
    GetType = function() return "chain" end,
    IsEmbed = function() return true end,
    GetNumItems = function() return #items end,
    GetItem = function(_, i) return items[i] end,
} end
local function linkedChain() return {
    GetType = function() return "chain" end,
    IsEmbed = function() return false end,
    GetNumItems = function() return 1 end,
    GetItem = function() return questItem(9999) end,
} end
local function npcItem() return { GetType = function() return "npc" end } end

local chains = {}
local function makeChain(id, items)
    chains[id] = { GetNumItems = function() return #items end, GetItem = function(_, i) return items[i] end }
end
local loadCalls = {}
local function fakeBtW(currentChainID)
    BtWQuestsDatabase = {
        GetChainByID = function(_, id) return chains[id] end,
        LoadChain = function(_, id) loadCalls[#loadCalls + 1] = id; return chains[id] end,
    }
    BtWQuestsCharacters = { GetPlayer = function() return { name = "player" } end }
    BtWQuestsFrame = { chainID = currentChainID }
    function BtWQuestsFrame:GetChain() return self.chainID end
    function BtWQuestsFrame:GetCharacter() return { name = "player" } end
    function BtWQuestsFrame:SetChain(id) self.chainID = tonumber(id) end
    function BtWQuestsFrame:SelectChain(id) self:SetChain(id) end
end

-- Chain 10: q1 q2 [embedded: q3 q4] npc q5 [linked chain: skipped] q6
makeChain(10, { questItem(1), questItem(2), embeddedChain({ questItem(3), questItem(4) }), npcItem(), questItem(5), linkedChain(), questItem(6) })

local function keys(list)
    local t = {}
    for _, e in ipairs(list or {}) do t[#t + 1] = e.questID end
    return table.concat(t, ",")
end

test("BtWQuests is registered as a third source", function()
    local names = QuestPrism.Sources.Names()
    assertEq(names[3], "BtWQuests"); assertEq(QuestPrism.Sources.GetLabel("BtWQuests"), "BtWQuests")
end)

test("whole chain: quests in order, embedded chain flattened, linked chain and NPC skipped", function()
    fakeBtW(10); completedQuests = {}
    QuestPrism.Settings.Set("guideSource", "BtWQuests"); QuestPrism.Settings.Set("guideScope", "guide"); QuestPrism.Sources.Invalidate()
    assertEq(keys(QuestPrism.Sources.GetActiveQuestList()), "1,2,3,4,5,6")
    assertEq(QuestPrism.Sources.Get("BtWQuests").GetStepNumber(), 1)
end)

test("step scope is the first incomplete quest; lookahead counts incomplete quests only", function()
    fakeBtW(10); completedQuests = { [1] = true, [2] = true, [4] = true }
    QuestPrism.Settings.Set("guideSource", "BtWQuests"); QuestPrism.Settings.Set("guideScope", "step"); QuestPrism.Sources.Invalidate()
    assertEq(keys(QuestPrism.Sources.GetActiveQuestList()), "3", "first incomplete is 3")
    assertEq(QuestPrism.Sources.Get("BtWQuests").GetStepNumber(), 3)
    QuestPrism.Settings.Set("guideScope", "lookahead"); QuestPrism.Settings.Set("guideLookahead", 1); QuestPrism.Sources.Invalidate()
    assertEq(keys(QuestPrism.Sources.GetActiveQuestList()), "3,4,5", "3 + next incomplete (5), skipping completed 4 in between")
    QuestPrism.Settings.Set("guideLookahead", 3)
end)

test("the last viewed chain is remembered and reloaded after a /reload", function()
    fakeBtW(nil) -- frame has no chain yet (fresh session)
    QuestPrism.Settings.Set("btwChainID", nil); QuestPrism.Sources.Invalidate()
    assertFalse(QuestPrism.Sources.Get("BtWQuests").IsAvailable(), "nothing viewed, nothing remembered")
    fakeBtW(10); QuestPrism.Sources.Initialize()
    BtWQuestsFrame:SelectChain(10) -- user opens a chain -> remembered
    assertEq(QuestPrism.Settings.Get("btwChainID"), 10)
    fakeBtW(nil); loadCalls = {}; QuestPrism.Sources.Invalidate()
    assertTrue(QuestPrism.Sources.Get("BtWQuests").IsAvailable(), "remembered chain makes the source available")
    QuestPrism.Settings.Set("guideSource", "BtWQuests"); QuestPrism.Settings.Set("guideScope", "guide")
    assertEq(keys(QuestPrism.Sources.GetActiveQuestList()), "1,2,3,4,5,6")
end)

test("selecting a chain in BtWQuests schedules a QuestPrism refresh", function()
    fakeBtW(10); QuestPrism.Settings.Set("guideSource", "BtWQuests"); QuestPrism.Sources.Invalidate()
    QuestPrism.Sources.Initialize()
    MOCK.flushTimers(); MOCK.timers = {}
    makeChain(11, { questItem(21) })
    BtWQuestsFrame:SelectChain(11)
    assertEq(#MOCK.timers, 1, "one deferred refresh")
    MOCK.flushTimers()
    assertEq(keys(QuestPrism.Sources.GetActiveQuestList()), "21")
    QuestPrism.Settings.Set("guideSource", "Off")
end)

test("BtWQuests absent -> source unavailable, no errors", function()
    BtWQuestsFrame = nil; BtWQuestsDatabase = nil; BtWQuestsCharacters = nil
    QuestPrism.Settings.Set("btwChainID", nil); QuestPrism.Sources.Invalidate()
    assertFalse(QuestPrism.Sources.Get("BtWQuests").IsAvailable())
    assertTrue(pcall(QuestPrism.Sources.Get("BtWQuests").Subscribe, function() end))
end)
