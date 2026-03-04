## Plan for **Claude Code Gateway** (menu bar app + local gateway server)

You want: one‑click switch providers/models for Claude Code, multi-provider (Gemini/OpenRouter/etc), and keep model selection “in sync”.

### High-level architecture
**Two components:**
1) **Gateway Server** (local HTTP service)
- Exposes Anthropic-compatible endpoint: `POST /v1/messages`
- Claude Code points `ANTHROPIC_BASE_URL` to it (once)
- Routes + transforms requests to upstream providers
- Logs usage for cost display

2) **Menu Bar App (Swift)**
- Starts/stops the gateway server
- Selects active provider + model mapping
- Shows cost/usage in menubar
- Edits Claude Code config one-time to point to gateway

---

## Phase 1 — MVP: “Claude Code talks to local gateway”
**Goal:** Claude Code works through your gateway, with 1 provider (Gemini) only.

1) Gateway server basics
- Choose implementation:
  - **Node/TypeScript** (fastest if you reuse claude-code-router ideas/libraries)
  - or **Swift server** (harder for provider SDK/transformers)
- Implement:
  - `POST /v1/messages` (Anthropic-style request in, Anthropic-style out)
  - Non-stream response first (streaming later)

2) Provider adapter: Gemini
- Implement Gemini call:
  - Convert Anthropic request → Gemini request
  - Convert Gemini response → Anthropic response
- Hardcode one model at first (e.g. `gemini-2.5-pro`)

3) One-time Claude Code setup
- Menu bar app writes `~/.claude/settings.json`:
  - `ANTHROPIC_BASE_URL = http://127.0.0.1:<port>`
  - `ANTHROPIC_API_KEY = <local-gateway-key or dummy>`
- Gateway optionally requires `x-api-key` like claude-code-router server does (good security hygiene)

**Deliverable:** Claude Code runs through your gateway and gets Gemini answers.

---

## Phase 2 — Multi-provider switching (CC Switch-like UX)
**Goal:** store multiple providers and switch with one click.

1) Provider registry + config storage
- App-managed config file:
  - `~/Library/Application Support/ClaudeCodeGateway/config.json`
- Store secrets in **Keychain**
- Provider profile fields:
  - `id, name, type (gemini/openrouter/openai/anthropic/...)`
  - `apiBaseUrl`
  - `models[]`
  - `authRef` (Keychain key)
  - optional transformer settings

2) Runtime switching
- Menu bar app calls gateway’s local admin API:
  - `POST /api/active-provider` `{ providerId }`
- Gateway updates in-memory config (no restart required)

3) Health + status
- Add `GET /health`
- Menu bar shows: `Gateway: Running` / `Stopped`

**Deliverable:** one-click switch provider; Claude Code automatically uses the new backend without changing Claude config again.

---

## Phase 3 — Model sync design (your “handle model post to make it sync”)
You need to decide what “sync” means. I recommend **slot-based sync**.

### Model sync approach (recommended): “Slots”
Define canonical slots:
- `default`
- `background` (cheap model)
- `think` (reasoning/plan)
- `longContext`

Per provider, map each slot to a provider model:
- Gemini: `default=gemini-2.5-pro`, `background=gemini-2.5-flash`
- OpenRouter: `default=anthropic/claude-3.5-sonnet`, etc.

Gateway routing rules:
- If Claude Code sends a model like `claude-3-5-sonnet...` ignore it and treat it as “slot=default” (or parse patterns: haiku→background, etc.)
- Or allow explicit override when user chooses `/model provider,model` (advanced)

This matches claude-code-router’s routing concepts (background/think/longContext) and its ability to accept `provider,model` strings.

### Implementation milestones
1) Add `Router` config section (like claude-code-router):
- `default`, `background`, `think`, `longContextThreshold`, etc.
2) When request comes in:
- estimate tokens (optional early)
- choose slot (default vs longContext etc.)
- resolve to `(provider, model)` using active provider mapping
3) Add `/model` support (optional):
- If `req.body.model` contains `provider,model`, route exactly

**Deliverable:** switching provider keeps your “default/think/background” behavior consistent.

---

## Phase 4 — Streaming + tool/function calling compatibility
**Goal:** preserve “native Claude Code feel”.

1) Streaming (SSE)
- Claude Code may rely heavily on streaming.
- Implement streaming passthrough:
  - Gemini streaming response → convert chunks → Anthropic streaming chunks
- Ensure correct `content_block_delta` style (Anthropic stream semantics)

2) Tool/function calling mapping
- Claude Code tool schema is Anthropic-flavored
- Gemini tool schema differs (quirks with `format`, missing tool_call id, etc.—claude-code-router notes this)
- Implement robust mapping layer:
  - stable tool call IDs in gateway
  - arguments streaming support if needed

**Deliverable:** Claude Code tools work reliably with Gemini/OpenAI/etc.

---

## Phase 5 — Usage + cost in menu bar
**Goal:** show “$ today / month” like you asked.

1) Logging
- For each request store:
  - timestamp, provider, model, prompt tokens, completion tokens, total tokens, latency
- Storage: SQLite in App Support directory

2) Cost calculation
- Maintain a pricing table per model (user-editable)
- Compute daily + monthly totals

3) Menu bar display
- Title: `"$1.23 • Gemini"`
- Dropdown shows breakdown

**Deliverable:** cost visible live.

---

## Phase 6 — Polish & safety
- Atomic write of Claude settings
- Backups + restore
- Auto-start gateway on login (optional)
- “Stop gateway” disables Claude Code connectivity (warn user)
- Privacy controls: don’t store prompts by default

---

## Key decision questions (to lock the plan)
1) Do you want the Gateway Server written in **Node/TS** (reuse claude-code-router style) or **Swift**?
2) Which providers must be supported first: **Gemini only** or Gemini + OpenRouter/OpenAI?
3) Do you want Claude Code to be configured by:
   - “launch through app” (like `ccr code`), or
   - “always-on gateway” (Claude always points to localhost)?

If you answer those, I’ll turn this into a concrete milestone checklist with file locations, local APIs (`/api/config`, `/api/switch`), and the exact data model for provider + slot mappings.