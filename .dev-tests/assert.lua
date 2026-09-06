TEST_RESULTS = {}
function test(name, fn)
    local ok, err = pcall(fn)
    table.insert(TEST_RESULTS, { name = name, ok = ok, err = err })
end
function assertEq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "assertEq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
function assertTrue(v, msg) if not v then error((msg or "assertTrue") .. " failed", 2) end end
function assertFalse(v, msg) if v then error((msg or "assertFalse") .. " failed", 2) end end

-- Common setup: simulate ADDON_LOADED + PLAYER_LOGIN for the core modules only
function bootCore()
    QuestPrismCharDB = nil
    QuestPrismDB = nil
    QuestPrism.Settings.Initialize()
    QuestPrism.WorldMap.Initialize()
end
