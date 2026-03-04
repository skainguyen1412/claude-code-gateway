# E2E Claude CLI Integration Tests — Design

## Problem

Currently, every time we change the gateway (routes, adapter transforms, slot routing), we have to manually:
1. Build and run the CCGateWay app
2. Open a terminal and run `claude -p "some prompt"`
3. Eyeball-verify the response came back correctly
4. Repeat for streaming, tool use, different models

This is slow, error-prone, and blocks the feedback loop.

## Solution

Automate this by writing **Swift Testing** integration tests that:
1. Start a standalone Vapor server in-process (same routes as the app, zero UI coupling)
2. Spawn `claude -p "prompt"` as a child `Process` with `ANTHROPIC_BASE_URL` pointed at the test server
3. Capture stdout/stderr and assert the response is valid

The tests use the **real Gemini API** — they are true end-to-end tests, not mocks.

## Architecture

```
┌─────────────┐      HTTP       ┌──────────────┐     HTTP      ┌─────────────┐
│  claude CLI  │  ──────────►   │  Test Vapor   │  ─────────►  │  Gemini API │
│  (Process)   │  ◄──────────   │  Server       │  ◄─────────  │  (real)     │
│  -p "prompt" │   Anthropic    │  (in-process) │   Gemini     │             │
└─────────────┘    format       └──────────────┘    format     └─────────────┘
```

### Key Design Decisions

1. **Standalone test server, not GatewayServer** — `GatewayServer` is `@MainActor` + `ObservableObject`, tightly coupled to SwiftUI. We create a lightweight `E2ETestServer` that starts Vapor directly with the same `GatewayRoutes`, avoiding UI entanglement.

2. **Real `claude` CLI, not curl** — We want to prove the *exact same binary* the user runs works through our gateway. `claude -p "prompt"` is the non-interactive mode that prints and exits.

3. **Real Gemini API, not mocks** — The whole point is proving the transform pipeline works against the actual provider. Mocks are already covered by `GatewayTestServiceTests`.

4. **Random port per test run** — Prevents port conflicts when tests run in parallel or when the real app is running.

5. **Test-specific config** — Each test creates its own `GatewayConfig` + `ProviderConfig` with the Gemini API key from Keychain, isolating tests from user config changes.

## Test Cases

| # | Test | What it proves |
|---|------|---------------|
| 1 | Health check | Server boots, routes registered |
| 2 | Raw `/v1/messages` request | Anthropic→Gemini request transform + Gemini→Anthropic response transform |
| 3 | Claude CLI basic prompt | Full round-trip: `claude -p "Reply with OK"` → text response through gateway |
| 4 | Claude CLI with `--output-format json` | Parse structured JSON output from Claude CLI to verify response shape |
| 5 | Slot routing verification | Request with `claude-sonnet-4` model routes to `default` slot, `claude-3-haiku` routes to `background` slot |

## Prerequisites

- `claude` CLI installed at `/Users/chaileasevn/.local/bin/claude`
- Gemini API key stored in Keychain as `Gemini_api_key` (same key the app uses)
- Network access to `generativelanguage.googleapis.com`

## File Structure

```
CCGateWay/CCGateWay/Tests/
├── CCGateWayTests.swift           (existing)
├── GatewayTestServiceTests.swift  (existing)
├── E2ETestServer.swift            (NEW - lightweight Vapor test server)
├── ClaudeCliRunner.swift          (NEW - Process wrapper for claude CLI)
└── ClaudeE2ETests.swift           (NEW - the actual test cases)
```

## Non-Goals

- No mocking Gemini API (that's what unit tests are for)
- No testing the SwiftUI UI layer
- No CI integration yet (requires API key)
