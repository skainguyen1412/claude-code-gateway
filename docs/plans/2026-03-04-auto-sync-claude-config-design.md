# Auto-Sync Claude Config Design

## Overview
The goal is to simplify the user experience of CCGateWay by automatically synchronizing the local `~/.claude/settings.json` configuration file whenever the user switches the active AI provider. Currently, users must manually click an "Update Claude Code Config" button in the Settings interface to apply their selected provider to Claude Code.

## Architecture & Implementation

We will adopt **Approach A** (putting the logic directly in `GatewayConfig`):

1. **Extract Logic:** 
   Move the `updateClaudeCodeConfig()` function from `SettingsView.swift` into `GatewayConfig.swift`. We will rename it to `syncWithClaudeCode()` and make it a public function of the `GatewayConfig` class.
   This function accesses `self.port` and `self.activeProviderConfig` to correctly write the proxy and model settings to the Claude configuration file.

2. **Automate Sync on Switch:**
   Modify the existing `switchProvider(to:)` method inside `GatewayConfig.swift` so that it calls `syncWithClaudeCode()` immediately after it calls `save()`. This ensures that anytime the active provider changes (such as from the Menu Bar layout), the local `~/.claude/settings.json` is updated instantly.

3. **UI Cleanup:**
   Remove the now-redundant "Update Claude Code Config" button and its associated success message from `SettingsView.swift`, creating a cleaner and less confusing interface. The "Apply & Restart Server" button can remain for port changes.

## Rollout
1. Move `updateClaudeCodeConfig()` from `SettingsView.swift` to `GatewayConfig.swift` as `syncWithClaudeCode()`.
2. Update `GatewayConfig.switchProvider(to:)` to call `syncWithClaudeCode()`.
3. Clean up `SettingsView.swift` UI and state variables.
4. Verify that changing a provider updates `~/.claude/settings.json` automatically without user intervention.
