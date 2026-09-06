# UX redesign — Implementation Plan (v2.2.0)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, per user CLAUDE.md).

**Goal:** Make QuestPrism's controls discoverable and its window compact, per the UX review approved in chat 2026-09-05 ("proceed").

## Tasks
1. **Keybindings** — `Bindings.xml` (toggle window, toggle guide-only), header/name globals in locales, TOC entry.
2. **Sources helper** — `QuestPrism.Sources.SetFollowing(enabled) -> bool`, `IsFollowing()`, `AvailableNames()`.
3. **Settings** — `DEFAULTS.collapsed = {}` (per section), new installs default the minimap button hidden (only when no saved data existed).
4. **Quick menu** — quest types moved into a "Quest types" submenu; top level: Guide only, Show all, Hide all, Open.
5. **Guide tab** — header bar: scope buttons (Step / Next N / Guide) + gear (opens window anchored to map); right-click a row to track/untrack; `ShowOnMap()` opens map + side panel + selects the tab.
6. **Settings window** (`UI/Panel.lua`) — sections as collapsible frames (state saved); Quest types gets a toolbar (preset dropdown, Load/Save/Delete, All/None), presets section removed; column header "Skip if done"; clickable type names for solo + caption; "Also on the minimap" group for Trivial; Guide section led by "Follow my guide" checkbox, source dropdown only when 2+ sources available, slider only in lookahead scope, "Show on map" button; Options gains hide-minimap + debug; status bar appends guide state.
7. **Locales** en/fr; version 2.2.0; changelog.
8. **Tests** — smoke: template counts, collapsible state, follow checkbox; quick menu submenu; guide tab scope buttons + track toggle; Sources.SetFollowing.
