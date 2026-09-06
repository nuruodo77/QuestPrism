# Guide sources — Implementation Plan (v1.9.0)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, per user CLAUDE.md).

**Goal:** Filter map quest pins to the quests of the player's active Zygor or RestedXP guide, with scope step / lookahead / whole guide.
**Spec:** `.dev-tests/specs/2026-09-05-guide-sources-design.md`
**Tests:** `.dev-tests/run_tests.py` (lupa Lua 5.1 + mock).

## Tasks
1. **Settings** (`Core/Settings.lua`): DEFAULTS `guideSource="Off"`, `guideScope="lookahead"`, `guideLookahead=3`, `guideLastSource=nil`. Not scoped. Tests: defaults; setting them does not end solo mode.
2. **Sources registry** (`Core/Sources.lua`) per spec. Tests: inactive → nil set; active but unavailable → nil; caching by key; NotifyChanged calls WorldMap.Refresh; FirstAvailable; GetStatusText variants.
3. **Adapters** (`Sources/Zygor.lua`, `Sources/RXP.lua`). Tests with fake `ZGV` / `RXPGuides` + `RXPCData`: step / lookahead (clamped at guide end) / guide sets; RXP `ids` lists; tonumber on ids; Subscribe wires ZGV message handler and RXP SetStep post-hook.
4. **Rules** (`Core/Rules.lua`) + `Filter.ShouldShowPin` delegating. Tests: no type → true; guide gate hides non-guide quest, keeps guide quest; pin w/o ID passes the gate; type toggle and done-on-another-character still apply; Expedition gated by guide but not by warband.
5. **UI**: Panel "Guide" section; QuickMenu "Guide only" checkbox (smoke test: 9 checkboxes, toggle sets source Off ↔ last); locales en/fr; TOC (files + 1.9.0); `QuestPrism.lua` → `QuestPrism.Sources.Initialize()`; changelog text.
6. **Verify**: full suite, XML, TOC.
