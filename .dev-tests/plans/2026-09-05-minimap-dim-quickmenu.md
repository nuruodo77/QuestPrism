# Minimap sync, trivial toggle, dim mode, quick menu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, per user CLAUDE.md). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give QuestPrism a "trivial quests" toggle that drives the game's own minimap/world-map trivial filter, sync the account-completed filter with the per-type "done on an alt" toggles, add a dim-instead-of-hide mode, and a right-click quick menu on both buttons.

**Architecture:** Minimap quest blips are engine-drawn; the only levers are two tracking filters (`Enum.MinimapTrackingFilter.TrivialQuests`, `.AccountCompletedQuests`) set with `C_Minimap.SetTracking(index, enabled)` where enabled = shown. A new `Hooks/Minimap.lua` owns that sync and is called from `QuestPrism.WorldMap.Refresh()` (the single "settings changed" entry point) and at login. Dim mode extends the existing "pins QuestPrism touched" table to remember whether a pin was hidden or dimmed. The quick menu is a new `UI/QuickMenu.lua` using Blizzard's `MenuUtil.CreateContextMenu`.

**Tech Stack:** WoW Retail 12.1 Lua 5.1; tests via lupa (Lua 5.1) mock in `.dev-tests/`.

**Spec:** design approved in chat 2026-09-05 (see summary in this header).

## Global Constraints

- Interface 120100; no new libraries.
- Engine filters are all-or-nothing and also affect the world map. Therefore: account-completed tracking is turned OFF (hidden) only when ALL six `HideWarbandCompleted_*` toggles are true; otherwise it stays ON so per-type world-map filtering keeps working.
- `Trivial` is a scoped (account-wide capable) filter key, default `false` (= hide trivial quests, matching Blizzard's default). It is included in presets, Show all (→ true) and Hide all (→ false).
- `dimFiltered` is per-character, default `false`; dim alpha is `0.3`.
- Right-click on the minimap button now opens the quick menu (was: reset). "Show all" lives in the menu.
- All new user-facing strings exist in enUS and frFR.
- Verification: `python .dev-tests/run_tests.py` → syntax OK, all tests pass.

---

### Task 1: Settings — `Trivial` key, `dimFiltered`, `AllWarbandHidden()`

**Files:**
- Modify: `Core/Settings.lua`
- Test: `.dev-tests/test_settings.lua`

**Produces:** `QuestPrism.Settings.AllWarbandHidden() -> boolean`; `QuestPrism.Settings.WARBAND_TYPE_KEYS` (array); `Trivial` in `FILTER_KEYS`/`SCOPED_KEYS` with default false; `DEFAULTS.dimFiltered = false`.

- [ ] Step 1: add tests
```lua
test("Trivial is a scoped filter key defaulting to hidden", function()
    QuestPrismCharDB = nil; QuestPrismDB = nil; QuestPrism.Settings.Initialize()
    assertEq(QuestPrism.Settings.Get("Trivial"), false)
    QuestPrism.Settings.SetAccountWide(true)
    QuestPrism.Settings.Set("Trivial", true)
    assertEq(QuestPrismDB.filters.Trivial, true)
    QuestPrism.Settings.SetAccountWide(false)
end)
test("Reset shows trivial quests too, and dimFiltered defaults off", function()
    QuestPrism.Settings.Set("Trivial", false)
    QuestPrism.Settings.Reset()
    assertEq(QuestPrism.Settings.Get("Trivial"), true)
    assertEq(QuestPrism.Settings.Get("dimFiltered"), false)
end)
test("AllWarbandHidden is true only when all six toggles are on", function()
    for _, t in ipairs(QuestPrism.Settings.WARBAND_TYPE_KEYS) do QuestPrism.Settings.Set("HideWarbandCompleted_" .. t, true) end
    assertTrue(QuestPrism.Settings.AllWarbandHidden())
    QuestPrism.Settings.Set("HideWarbandCompleted_Meta", false)
    assertFalse(QuestPrism.Settings.AllWarbandHidden())
end)
```
- [ ] Step 2: run → FAIL (Trivial default nil, AllWarbandHidden nil)
- [ ] Step 3: implement: add `Trivial = false`, `dimFiltered = false` to DEFAULTS; add `"Trivial"` to FILTER_KEYS; export `QuestPrism.Settings.WARBAND_TYPE_KEYS = WARBAND_TYPE_KEYS`; add
```lua
function QuestPrism.Settings.AllWarbandHidden()
    for _, t in ipairs(WARBAND_TYPE_KEYS) do
        if QuestPrism.Settings.Get("HideWarbandCompleted_" .. t) ~= true then return false end
    end
    return true
end
```
- [ ] Step 4: run → PASS

### Task 2: `Hooks/Minimap.lua` — engine filter sync

**Files:**
- Create: `Hooks/Minimap.lua`
- Modify: `QuestPrism.toc` (add after `Hooks/WorldMap.lua`), `QuestPrism.lua` (call `QuestPrism.Minimap.Initialize()` at PLAYER_LOGIN), `Hooks/WorldMap.lua` (`Refresh()` calls `QuestPrism.Minimap.Sync()` when present)
- Test: `.dev-tests/test_minimap.lua`, `.dev-tests/mock.lua` (add C_Minimap mock), `.dev-tests/run_tests.py` (add file to CORE_FILES)

**Produces:** `QuestPrism.Minimap.Sync()`, `QuestPrism.Minimap.Initialize()`.

- [ ] Step 1: mock — in `mock.lua`:
```lua
M.tracking = { -- index -> {filterID=, active=}
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
```
- [ ] Step 2: tests
```lua
bootCore()
test("Sync shows trivial quests iff the Trivial toggle is on", function()
    QuestPrism.Settings.Set("Trivial", true); QuestPrism.Minimap.Sync(); assertEq(MOCK.tracking[1].active, true)
    QuestPrism.Settings.Set("Trivial", false); QuestPrism.Minimap.Sync(); assertEq(MOCK.tracking[1].active, false)
end)
test("account-completed quests hidden only when all six warband toggles are on", function()
    for _, t in ipairs(QuestPrism.Settings.WARBAND_TYPE_KEYS) do QuestPrism.Settings.Set("HideWarbandCompleted_" .. t, true) end
    QuestPrism.Minimap.Sync(); assertEq(MOCK.tracking[2].active, false)
    QuestPrism.Settings.Set("HideWarbandCompleted_Meta", false)
    QuestPrism.Minimap.Sync(); assertEq(MOCK.tracking[2].active, true)
end)
test("Sync does not call SetTracking when already in the wanted state", function()
    QuestPrism.Minimap.Sync(); MOCK.setTrackingCalls = {}; QuestPrism.Minimap.Sync()
    assertEq(#MOCK.setTrackingCalls, 0)
end)
test("Sync never touches unrelated trackers", function()
    MOCK.setTrackingCalls = {}; QuestPrism.Settings.Set("Trivial", true); QuestPrism.Minimap.Sync()
    for _, c in ipairs(MOCK.setTrackingCalls) do assertTrue(c[1] ~= 3, "banker touched") end
end)
test("WorldMap.Refresh triggers a minimap sync", function()
    local called = false; local orig = QuestPrism.Minimap.Sync
    QuestPrism.Minimap.Sync = function() called = true end
    QuestPrism.WorldMap.Refresh(); QuestPrism.Minimap.Sync = orig
    assertTrue(called)
end)
test("Sync is a no-op without the API", function()
    local saved = C_Minimap; C_Minimap = nil
    local ok = pcall(QuestPrism.Minimap.Sync); C_Minimap = saved
    assertTrue(ok)
end)
```
- [ ] Step 3: run → FAIL (QuestPrism.Minimap nil)
- [ ] Step 4: implement `Hooks/Minimap.lua`:
```lua
QuestPrism.Minimap = {}
local function trackingIndexFor(filterID)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter) then return nil end
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local filter = C_Minimap.GetTrackingFilter(index)
        if type(filter) == "table" and filter.filterID == filterID then return index end
    end
    return nil
end
local function isTrackingActive(index)
    if not (C_Minimap and C_Minimap.GetTrackingInfo) then return nil end
    local info = C_Minimap.GetTrackingInfo(index)
    if type(info) == "table" then return info.active == true end
    return nil
end
local function setFilterShown(filterID, shown)
    local index = trackingIndexFor(filterID)
    if not index or not (C_Minimap and C_Minimap.SetTracking) then return end
    if isTrackingActive(index) == shown then return end
    C_Minimap.SetTracking(index, shown)
end
function QuestPrism.Minimap.Sync()
    local filters = Enum and Enum.MinimapTrackingFilter
    if not filters then return end
    if filters.TrivialQuests then setFilterShown(filters.TrivialQuests, QuestPrism.Settings.Get("Trivial") == true) end
    if filters.AccountCompletedQuests then setFilterShown(filters.AccountCompletedQuests, not QuestPrism.Settings.AllWarbandHidden()) end
end
function QuestPrism.Minimap.Initialize()
    pcall(QuestPrism.Minimap.Sync)
end
```
In `Hooks/WorldMap.lua`: `function QuestPrism.WorldMap.Refresh() refreshAllPins(); if QuestPrism.Minimap and QuestPrism.Minimap.Sync then pcall(QuestPrism.Minimap.Sync) end end`. Add `QuestPrism.Minimap.Initialize()` after `QuestPrism.WorldMap.Initialize()` in `QuestPrism.lua`. TOC + runner CORE_FILES.
- [ ] Step 5: run → PASS

### Task 3: Dim mode in `Hooks/WorldMap.lua`

**Files:**
- Modify: `Hooks/WorldMap.lua` (replace `hiddenByQuestPrism` with `touchedByQuestPrism` storing `"hide"`/`"dim"`)
- Test: `.dev-tests/test_worldmap.lua`; `mock.lua` frames get `SetAlpha/GetAlpha` (default 1)

- [ ] Step 1: tests
```lua
test("dim mode dims filtered pins instead of hiding them", function()
    QuestPrism.Settings.Set("dimFiltered", true); QuestPrism.Settings.Set("Campaign", false)
    local pin = offerPin(Enum.QuestClassification.Campaign, 300)
    QuestPrism.WorldMap.Refresh()
    assertTrue(pin:IsShown()); assertEq(pin:GetAlpha(), 0.3)
    QuestPrism.Settings.Set("Campaign", true); QuestPrism.WorldMap.Refresh()
    assertEq(pin:GetAlpha(), 1)
    QuestPrism.Settings.Set("dimFiltered", false)
end)
test("switching from dim to hide restores alpha and hides", function()
    QuestPrism.Settings.Set("dimFiltered", true); QuestPrism.Settings.Set("Campaign", false)
    local pin = offerPin(Enum.QuestClassification.Campaign, 301)
    QuestPrism.WorldMap.Refresh(); assertEq(pin:GetAlpha(), 0.3)
    QuestPrism.Settings.Set("dimFiltered", false); QuestPrism.WorldMap.Refresh()
    assertFalse(pin:IsShown()); assertEq(pin:GetAlpha(), 1)
    QuestPrism.Settings.Set("Campaign", true); QuestPrism.WorldMap.Refresh(); assertTrue(pin:IsShown())
end)
```
- [ ] Step 2: run → FAIL
- [ ] Step 3: implement
```lua
local DIM_ALPHA = 0.3
local touchedByQuestPrism = setmetatable({}, { __mode = "k" }) -- pin -> "hide" | "dim"
local function restorePin(pin, mode)
    if mode == "hide" then pin:Show() else pin:SetAlpha(1) end
end
local function applyFilterToPin(pin)
    local touched = touchedByQuestPrism[pin]
    if QuestPrism.Filter.ShouldShowPin(pin) then
        if touched then touchedByQuestPrism[pin] = nil; restorePin(pin, touched) end
        return
    end
    local mode = QuestPrism.Settings.Get("dimFiltered") == true and "dim" or "hide"
    if touched == mode then return end
    if touched then restorePin(pin, touched) end
    if mode == "hide" then
        if not pin:IsShown() then touchedByQuestPrism[pin] = nil; return end -- Blizzard hid it
        pin:Hide()
    else
        pin:SetAlpha(DIM_ALPHA)
    end
    touchedByQuestPrism[pin] = mode
end
```
Rename all `hiddenByQuestPrism` uses to `touchedByQuestPrism`.
- [ ] Step 4: run → PASS (existing hide tests must still pass)

### Task 4: Panel, options page, locales

**Files:**
- Modify: `UI/Panel.lua` (Trivial row via QUEST_TYPES entry `{ key="Trivial", label=L.QUEST_TRIVIAL, atlas="questnormal", hasWarband=false }`; export `QuestPrism.Panel.QUEST_TYPES`; dim checkbox in scope row; Hide all sets Trivial false via loop already), `UI/Options.lua` (dim checkbox), `Locales/enUS.lua`, `Locales/frFR.lua`
- Keys: `QUEST_TRIVIAL`, `TOOLTIP_TRIVIAL`, `DIM_LABEL`, `TOOLTIP_DIM`, `OPTIONS_DIM`, `OPTIONS_DIM_TOOLTIP`, `MENU_SHOW_ALL`, `MENU_HIDE_ALL`, `MENU_OPEN_PANEL`, `TOOLTIP_RIGHT_CLICK` (→ quick menu), `CHANGELOG_BODY` (1.7.0)
- Test: locale-coverage test already scans these files; extend the scan list with `UI/QuickMenu.lua`.

### Task 5: `UI/QuickMenu.lua` + button wiring

**Files:**
- Create: `UI/QuickMenu.lua` (after `UI/Panel.lua` in TOC, before `UI/Options.lua`)
- Modify: `UI/MinimapButton.lua` (right-click → `QuestPrism.QuickMenu.Open(button)`; world-map mixin `OnClick(self, button)`), `UI/WorldMapButton.xml` (`registerForClicks="LeftButtonUp, RightButtonUp"`)
- Test: `.dev-tests/test_ui_smoke.lua` — mock `MenuUtil.CreateContextMenu(owner, generator)` that runs generator with a recording `rootDescription` (`CreateTitle`, `CreateCheckbox(text, isSelected, setSelected, data)`, `CreateDivider`, `CreateButton(text, fn)`); assert 8 checkboxes, 3 buttons; toggling a checkbox flips the setting and calls Refresh.

```lua
QuestPrism.QuickMenu = {}
local function questTypes() return QuestPrism.Panel and QuestPrism.Panel.QUEST_TYPES or {} end
local function isShown(key) return QuestPrism.Settings.Get(key) == true end
local function setShown(key) QuestPrism.Settings.Set(key, not isShown(key)); QuestPrism.WorldMap.Refresh(); QuestPrism.Panel.Sync() end
local function build(_, root)
    root:CreateTitle("QuestPrism")
    for _, qt in ipairs(questTypes()) do root:CreateCheckbox(qt.label, isShown, setShown, qt.key) end
    root:CreateDivider()
    root:CreateButton(QuestPrism_L.MENU_SHOW_ALL, function() QuestPrism.Settings.Reset(); QuestPrism.WorldMap.Refresh(); QuestPrism.Panel.Sync() end)
    root:CreateButton(QuestPrism_L.MENU_HIDE_ALL, function() for _, qt in ipairs(questTypes()) do QuestPrism.Settings.Set(qt.key, false) end; QuestPrism.WorldMap.Refresh(); QuestPrism.Panel.Sync() end)
    root:CreateButton(QuestPrism_L.MENU_OPEN_PANEL, function() QuestPrism.Panel.Toggle() end)
end
function QuestPrism.QuickMenu.Open(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(owner, build) else QuestPrism.Panel.Toggle() end
end
```

### Task 6: Version bump + final verification

- `QuestPrism.toc` Version 1.7.0; changelog text both locales.
- Run `python .dev-tests/run_tests.py` → all pass; XML well-formed; every TOC file exists.
