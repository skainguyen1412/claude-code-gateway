# GitHub README Design

**Date:** 2026-03-05
**Status:** Approved

## Goal

Create a GitHub-ready `README.md` that clearly explains what CCGateWay is, why it exists, and how to run it from source.

Success criteria:
- A developer can understand the value in <60 seconds.
- A developer can build and run it on macOS without guessing.
- Claims match the current codebase (SwiftUI + embedded Vapor gateway + provider adapters + usage/cost tracking).

## Target Audience

- Claude Code users who want multi-provider routing and quick switching.
- macOS developers who want a native, local-first gateway (no Node runtime).

## Messaging Pillars

- Native macOS app (menu bar + dashboard).
- Local Anthropic-compatible gateway (`POST /v1/messages`) with streaming support.
- Slot-based routing (`default`, `background`, `think`, `longContext`) so Claude Code behavior stays consistent.
- One-click provider switching.
- Local-first: keys in Keychain; usage/cost stored locally.

## README Outline

- Title + tagline
- What it is / why it exists
- How it works (small diagram)
- Features
- Requirements
- Build & Run (from source)
- Configure providers (templates + API keys + model slots + test connection)
- Claude Code integration (auto-sync of `~/.claude/settings.json` + reset)
- Test with curl (`/health`, `/v1/messages`, streaming)
- Config/data locations
- Security & privacy notes
- Status/roadmap + contributing + disclaimer
