<p align="center">
  <img src="asset/banner.png" alt="CCGateWay" width="360">
</p>

<h1 align="center">Claude Code Gateway</h1>

<p align="center">
  <strong>Route Claude Code to any LLM provider from your Mac menu bar.</strong><br>
  One-click switching &bull; Slot-based model mapping &bull; Local cost tracking
</p>

<p align="center">
  <a href="#requirements"><img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6"></a>
  <a href="#build--run"><img src="https://img.shields.io/badge/build-Tuist-blue?style=flat-square" alt="Tuist"></a>
</p>

---

CCGateWay is a native macOS menu bar app with an embedded local gateway server. Point Claude Code at it once, then switch between Gemini, OpenAI, OpenRouter, DeepSeek, Groq -- or any OpenAI-compatible API -- without touching your workflow.

## Why

| Problem | CCGateWay |
|---------|-----------|
| Switching providers means editing env vars and restarting | One click in the menu bar |
| Claude Code assumes Anthropic models | Slot-based routing maps `default` / `background` / `think` / `longContext` to any provider's models |
| No visibility into what you're spending | Token + cost tracking, persisted locally |
| Existing proxies need Node / Python / Docker | Pure Swift -- SwiftUI UI + embedded Vapor server, nothing else to install |

## How It Works

```
Claude Code  ──(Anthropic Messages API)──►  CCGateWay (127.0.0.1)
                                                │
                                      ┌─────────┼─────────┐
                                      ▼         ▼         ▼
                                   Gemini    OpenAI    OpenRouter
                                             DeepSeek  Groq
                                             (any OpenAI-compatible)
```

The app exposes two endpoints on `127.0.0.1`:

| Endpoint | Purpose |
|----------|---------|
| `POST /v1/messages` | Anthropic-compatible messages (streaming + non-streaming) |
| `GET  /health` | Health check |

Claude Code sends requests as usual. CCGateWay translates them to the active provider's format and returns Anthropic-shaped responses.

### Slot-Based Routing

Claude Code uses different model names for different tasks (e.g. "haiku" for background work, "opus" for deeper reasoning). CCGateWay intercepts the model string, maps it to a **slot**, and routes to whatever model you configured for that slot on the active provider.

| Slot | When Claude Code uses it |
|------|--------------------------|
| `default` | Standard completions |
| `background` | Background / lightweight tasks |
| `think` | Deep reasoning / chain-of-thought |
| `longContext` | Large context windows |

## Features

- **Menu bar quick switch** -- change providers without leaving your editor
- **Dashboard** -- configure providers, assign models to slots, view usage
- **Anthropic-compatible gateway** -- drop-in replacement, streaming + non-streaming
- **Provider adapters** -- Gemini native + OpenAI-compatible (OpenAI, OpenRouter, DeepSeek, Groq, custom)
- **Tool / function calling** -- passthrough for OpenAI-compatible providers
- **Model catalog** -- curated list with per-token pricing for cost estimation
- **Keychain storage** -- API keys never leave macOS Keychain
- **Local cost tracking** -- usage + cost history persisted on disk

## Requirements

| Dependency | Version |
|------------|---------|
| macOS | 14+ |
| Xcode | Swift 6 toolchain |
| [Tuist](https://tuist.io) | Latest |

## Build & Run

```bash
git clone https://github.com/skainguyen1412/claude-code-gateway.git
cd claude-code-gateway/CCGateWay

# Generate the Xcode workspace
tuist generate

# Open in Xcode and run the CCGateWay scheme
open CCGateWay.xcworkspace
```

The app installs in the menu bar. Open the dashboard from the dropdown.

## Setup

### 1. Add a Provider

1. Open **Dashboard** > **Providers**
2. Pick a template (Gemini, OpenAI, OpenRouter, DeepSeek, Groq) or enter a custom endpoint
3. Paste your API key (stored in Keychain)
4. Assign models to each slot (`default` / `background` / `think` / `longContext`)
5. **Test Connection**, then **Save**

### 2. Activate

Use the menu bar quick switch or click **Make Active Provider** in the dashboard.

### 3. Claude Code Auto-Sync

CCGateWay automatically writes to `~/.claude/settings.json` when you switch providers, setting:

- `ANTHROPIC_BASE_URL` to `http://127.0.0.1:<port>`
- `ANTHROPIC_MODEL` and slot env vars to your configured models

To revert: **Settings** > **Reset Claude Code Settings** (removes CCGateWay-injected env vars).

## Test the Gateway

```bash
# Health check
curl -sS http://127.0.0.1:3456/health
```

```bash
# Non-streaming
curl -sS http://127.0.0.1:3456/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 256,
    "messages": [{"role": "user", "content": "Hello from CCGateWay"}]
  }'
```

```bash
# Streaming (SSE)
curl -N http://127.0.0.1:3456/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 256,
    "stream": true,
    "messages": [{"role": "user", "content": "Stream a short response"}]
  }'
```

## Data & Security

| What | Where |
|------|-------|
| App config | `~/Library/Application Support/CCGateWay/config.json` |
| Usage history | `~/.ccgateway/usage_history.json` |
| API keys | macOS Keychain (`dev.tuist.CCGateWay`) |

**Privacy:**
- Gateway binds to `127.0.0.1` only -- not exposed on your network
- API keys stored in Keychain, never written to disk as plaintext
- Usage/cost data stays local
- Request log stores metadata (slot, model, tokens, cost, latency); upstream response previews may appear in stdout during debugging

## Roadmap

- [ ] Packaged releases (`.dmg` / `.zip`) + auto-update
- [ ] More provider-specific edge-case handling
- [ ] Automated pricing / model catalog updates

## Contributing

Issues and PRs welcome. For provider compatibility issues, please include:

1. Provider name + base URL
2. Streaming or non-streaming
3. Redacted request/response snippet (remove secrets)

## Disclaimer

Not affiliated with Anthropic, Google, OpenAI, OpenRouter, DeepSeek, or Groq. Provider names are used only to describe compatibility.
