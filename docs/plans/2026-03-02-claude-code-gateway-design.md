# Claude Code Gateway — Design Document (v2)

**Date:** 2026-03-02
**Status:** Approved

## Overview

Claude Code Gateway is a native macOS application with two UI components:

1. **Main Dashboard Window** — a control panel for configuration, live monitoring, and usage tracking
2. **Menu Bar Widget** — compact dropdown for cost display and one-click provider switching

Both share an embedded Vapor HTTP proxy server that intercepts Claude Code API requests and routes them to alternative LLM providers.

## Architecture

### Single Process, Two UI Surfaces

One Swift binary runs as both a standard macOS window app AND a menu bar widget. The Vapor HTTP server runs on a background thread inside the same process.

- **No external dependencies** — no Node.js, no bundled binaries
- **Single lifecycle** — server starts/stops with the app
- **Built with Tuist** — existing `CCGateWay` project structure
- **Framework**: Vapor (embedded HTTP server)

## Main Dashboard Window

A macOS window with **sidebar navigation** and a **content area** (control panel style).

### Sidebar Sections

| Section | Purpose |
|---------|---------|
| **Overview** | Gateway status (Running/Stopped), active provider, today's cost, request count, start/stop button |
| **Providers** | Add/edit/delete providers. Per provider: name, type, API key, base URL, slot mappings. Test connection button. |
| **Request Log** | Live scrolling one-liner log: `[timestamp] slot → model \| tokens \| cost \| latency` |
| **Usage & Cost** | Daily/monthly cost tables. Breakdown by provider. Bar chart (last 7/30 days). |
| **Settings** | Port, auto-start on login, Claude Code config path, "Configure Claude Code" button |

### First-Time Experience

1. On first launch, check for `~/.claude-code-router/config.json`
2. If found: auto-import providers and slot mappings, show toast notification
3. Also check env vars (`GEMINI_API_KEY`, `OPENROUTER_API_KEY`, etc.)
4. If nothing found: empty Providers section with "Add Your First Provider" button

## Menu Bar Widget

**Title:** `$1.23 • Gemini` (daily cost + active provider)

**Compact dropdown popover:**
- Top: Today cost | Month cost
- Middle: Provider radio buttons (one-click switch, instant, no confirmation)
- Bottom: "Open Dashboard..." link, Quit button

## Gateway Server

### Core Endpoint

```
POST /v1/messages   (Anthropic-compatible)
GET  /health        (status check)
```

Claude Code configured once: `ANTHROPIC_BASE_URL=http://127.0.0.1:3456`

### Slot-Based Model Routing

Claude Code internally uses different models for different phases:

| Slot | Claude Code Uses For | Example Request Model |
|------|---------------------|----------------------|
| `default` | General coding, tool calls | `claude-3-5-sonnet` |
| `background` | Quick/cheap background tasks | `claude-3-5-haiku` |
| `think` | Planning, reasoning | `claude-3-7-sonnet:thinking` |
| `longContext` | Large codebases (>60k tokens) | `claude-3-5-sonnet` |

The gateway maps incoming model names → slots → active provider's models.

Example Gemini mapping:

| Slot | Gemini Model |
|------|-------------|
| `default` | `gemini-2.5-pro` |
| `background` | `gemini-2.5-flash` |
| `think` | `gemini-2.5-pro` |
| `longContext` | `gemini-2.5-pro` |

### Provider Adapters

Bidirectional format conversion:

```
Anthropic Request → [Gateway] → Provider Request → Provider API
Provider Response → [Gateway] → Anthropic Response → Claude Code
```

MVP: Gemini adapter (request/response/streaming/tool mapping)
Reference: claude-code-router transformer pattern

### Storage

- **API keys**: macOS Keychain
- **Config**: `~/Library/Application Support/CCGateWay/config.json`
- **Request logs & usage**: SQLite in Application Support directory

## Configuration Format

```json
{
  "activeProvider": "gemini",
  "port": 3456,
  "providers": {
    "gemini": {
      "name": "Gemini",
      "type": "gemini",
      "baseUrl": "https://generativelanguage.googleapis.com/v1beta/models/",
      "slots": {
        "default": "gemini-2.5-pro",
        "background": "gemini-2.5-flash",
        "think": "gemini-2.5-pro",
        "longContext": "gemini-2.5-pro"
      }
    }
  }
}
```

## Key Design Decisions

1. **Language**: 100% Native Swift (Vapor embedded)
2. **UI**: SwiftUI — Dashboard window + MenuBarExtra
3. **Build system**: Tuist
4. **Model routing**: Slot-based (inspired by claude-code-router)
5. **Secret storage**: macOS Keychain
6. **Usage storage**: SQLite
7. **First-time UX**: Auto-import from claude-code-router config
