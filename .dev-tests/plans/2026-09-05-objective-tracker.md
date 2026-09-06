# Objective tracker filter — Implementation Plan (v1.10.0)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, per user CLAUDE.md).

**Goal:** Apply QuestPrism's type and guide filters to the quest entries of Blizzard's objective tracker.
**Design (approved in chat 2026-09-05):** wrap `ShouldDisplayQuest(quest)` on the two quest module frames (`QuestObjectiveTracker`, `CampaignQuestObjectiveTracker`). Blizzard's answer first; if true, apply `QuestPrism.Rules.ShouldShow(type, id, { ignoreWarband = true })`. Type from `quest:GetQuestClassification()` (campaign module → "Campaign"). Mark both modules dirty on every QuestPrism refresh. Per-character toggle `trackerFilter` (default true). World quests, bonus objectives, scenarios etc. untouched. "Done on another character" is NOT applied in the tracker.

## Tasks
1. `Core/Rules.lua`: `ShouldShow(questType, questID, options)`; `options.ignoreWarband` skips rule 4. `Core/Filter.lua`: export `QuestPrism.Filter.GetTypeFromClassification`.
2. `Core/Settings.lua`: DEFAULTS `trackerFilter = true`.
3. `Hooks/ObjectiveTracker.lua`: `Initialize()` wraps modules present in `_G`; `Refresh()` marks hooked modules dirty. `Hooks/WorldMap.lua` `Refresh()` calls it. `QuestPrism.lua` calls Initialize at PLAYER_LOGIN. TOC entry.
4. UI: checkbox in panel Options section + options page; locales en/fr; changelog; version 1.10.0.
5. Tests `.dev-tests/test_tracker.lua` (fake modules + quests) and smoke locale scan.
