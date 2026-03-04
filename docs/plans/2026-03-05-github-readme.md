# GitHub README Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a polished, accurate `README.md` suitable for publishing this repository on GitHub.

**Architecture:** Write a product-first README that starts with a clear value proposition, then gives concrete build/run and integration steps grounded in the current SwiftUI + Vapor implementation.

**Tech Stack:** Markdown, GitHub-flavored Markdown

---

### Task 1: Create README skeleton

**Files:**
- Create: `README.md`

**Step 1: Draft section headings**

Create `README.md` with the final section structure:
- Title + badges
- What / Why
- How it works
- Features
- Requirements
- Build & Run (from source)
- Provider setup
- Claude Code integration
- Curl testing
- Data locations
- Security & privacy
- Contributing / roadmap / disclaimer

**Step 2: Self-review for scanability**

Check that:
- The first screen explains value + provides a quick start.
- Headings are consistent and easy to skim.

### Task 2: Fill in accurate product copy

**Files:**
- Modify: `README.md`

**Step 1: Describe the app accurately**

Ensure copy matches current implementation:
- Native macOS app (menu bar + dashboard)
- Embedded Vapor HTTP server bound to localhost
- Anthropic-compatible `POST /v1/messages` and `GET /health`
- Provider adapters: Gemini + OpenAI-compatible (OpenAI/OpenRouter/DeepSeek/Groq)

**Step 2: Add the routing concept**

Explain slot-based routing (`default/background/think/longContext`) and that Claude model strings are mapped to provider models.

### Task 3: Add build/run instructions (from source)

**Files:**
- Modify: `README.md`

**Step 1: Add prerequisites**

Document:
- macOS 14+
- Xcode (Swift 6 toolchain)
- Tuist

**Step 2: Add commands**

Include minimal commands:
- `tuist generate`
- open workspace and run the app

### Task 4: Add Claude Code integration instructions

**Files:**
- Modify: `README.md`

**Step 1: Explain auto-sync behavior**

Document that switching providers updates `~/.claude/settings.json` env vars to point Claude Code to `http://127.0.0.1:<port>`.

**Step 2: Add reset instructions**

Document the in-app reset action that removes injected env vars.

### Task 5: Add curl examples and data locations

**Files:**
- Modify: `README.md`

**Step 1: Add `GET /health` example**

Provide a one-liner curl command.

**Step 2: Add `POST /v1/messages` example**

Provide a non-streaming example and a streaming example.

**Step 3: Add local data paths**

Document:
- `~/Library/Application Support/CCGateWay/config.json`
- `~/.ccgateway/usage_history.json`

### Task 6: Quick QA

**Files:**
- Review: `README.md`

**Step 1: Validate internal consistency**

Confirm:
- Paths exist in code.
- Endpoints match routes.
- Provider list matches adapters.

**Step 2: Optional markdown preview**

Open the README in GitHub or a local Markdown viewer and verify formatting.
