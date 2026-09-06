# Guide sources — design (v1.9.0)

Approved in chat 2026-09-05. Show only the quests that belong to the guide the player is
following in Zygor or RestedXP (BTWQuests later), with a selectable scope.

## Behaviour
- Setting **guide source**: `Off` | `Zygor` | `RXP` (per character, not in presets/account-wide).
- Setting **scope**: `step` (current step only) | `lookahead` (current + next N) | `guide` (whole loaded guide). Default `lookahead`, N default 3 (1–10).
- When a source is active and its addon is loaded with a guide: quest-type pins whose quest ID is **not** in the source's set are hidden. Pins that are not quest-type pins (world quests, scenarios, addon pins, no type) are untouched. Type toggles and "done on another character" still apply on top.
- When the source's addon is not loaded / has no guide: nothing is hidden by the guide filter; the panel status line says so.
- Filter updates immediately on the guide's step change (Zygor message `ZGV_STEP_CHANGED`; RestedXP post-hook on `RXPGuides.SetStep`), via the same synchronous refresh path as a zone change.
- Quick menu: "Guide only" checkbox toggles the source between `Off` and the last used source (`guideLastSource`, default first available adapter). If no adapter is available, prints a chat message.

## Structure
- `Core/Sources.lua` — registry + cache: `Register(name, adapter)`, `GetActive()`, `GetActiveQuestSet()` (cached by source/scope/lookahead/adapter cache key), `NotifyChanged()` (invalidate + `QuestPrism.WorldMap.Refresh()`), `GetStatusText()`, `Initialize()` (subscribe adapters), `FirstAvailable()`.
- Adapter contract: `IsAvailable() -> bool`, `GetCacheKey() -> string`, `GetQuestSet(scope, lookahead) -> set|nil`, `GetStepNumber() -> number|nil`, `Subscribe(callback)`.
- `Sources/Zygor.lua`, `Sources/RXP.lua` — adapters.
- `Core/Rules.lua` — `QuestPrism.Rules.ShouldShow(questType, questID)`: no type → true; guide gate; type toggle; done-on-another-character. `Filter.ShouldShowPin` delegates to it.
- Panel section "Guide": source dropdown, scope dropdown, lookahead slider (disabled unless scope = lookahead), status label. Status refreshes on Sync and after each map refresh.

## Data shapes relied upon
- Zygor: `ZGV.CurrentGuide.steps[i].goals[j].questid`, `ZGV.CurrentStepNum`, `ZGV.CurrentGuide.title`, `ZGV:AddMessageHandler(event, fn)`.
- RestedXP: `RXPGuides.currentGuide.steps[i].elements[j].questId` and optional `.ids` list, `RXPCData.currentStep`, `RXPGuides.currentGuide.name`, `RXPGuides.SetStep(n, ...)`.
