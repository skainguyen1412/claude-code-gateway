#!/usr/bin/env python3
"""Extract model pricing and context window data from LiteLLM for our catalog models."""
import json
import urllib.request

URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

# Models we care about (exact litellm keys to search for)
TARGET_MODELS = [
    # Gemini
    "gemini-3.1-pro-preview",
    "gemini-3-flash-preview", 
    "gemini-3.1-flash-lite-preview",
    "gemini-2.5-pro",
    "gemini-2.5-flash",
    "gemini/gemini-3.1-pro-preview",
    "gemini/gemini-3-flash-preview",
    "gemini/gemini-3.1-flash-lite-preview",
    "gemini/gemini-2.5-pro",
    "gemini/gemini-2.5-pro-preview-05-06",
    "gemini/gemini-2.5-flash",
    "gemini/gemini-2.5-flash-preview-04-17",
    # OpenAI  
    "gpt-5",
    "gpt-5-mini",
    "gpt-5.2-pro",
    "gpt-5.2",
    "o3",
    "o4-mini",
    "gpt-4.1",
    "gpt-4.1-mini",
    "gpt-4.1-nano",
    "gpt-4o",
    "gpt-4o-mini",
    # DeepSeek
    "deepseek-chat",
    "deepseek-reasoner",
    "deepseek/deepseek-chat",
    "deepseek/deepseek-reasoner",
    # Groq
    "groq/llama-3.3-70b-versatile",
    "groq/llama-3.1-8b-instant",
    "groq/llama-4-scout-17b-16e-instruct",
    "groq/gpt-oss-120b",
    "groq/gpt-oss-20b",
    # OpenRouter
    "openrouter/google/gemini-3.1-pro-preview",
    "openrouter/openai/gpt-5",
    "openrouter/deepseek/deepseek-chat",
    "openrouter/anthropic/claude-opus-4",
    "openrouter/anthropic/claude-sonnet-4",
    # Also search without prefix
    "claude-opus-4",
    "claude-sonnet-4",
    "anthropic/claude-opus-4",
    "anthropic/claude-sonnet-4",
]

print("Fetching LiteLLM model data...")
with urllib.request.urlopen(URL) as resp:
    data = json.loads(resp.read())

print(f"Total models in LiteLLM: {len(data)}")
print("=" * 100)

# First, find exact matches
found = {}
for key, value in data.items():
    if key in TARGET_MODELS:
        found[key] = value

# Also do partial matching for models we couldn't find
not_found = [m for m in TARGET_MODELS if m not in found]
if not_found:
    print("\n--- Partial search for missing models ---")
    for missing in not_found:
        if missing in found:
            continue
        # Search for partial match
        base = missing.split("/")[-1]  # strip provider prefix
        matches = {k: v for k, v in data.items() if base in k}
        if matches:
            # Pick the best match (shortest key = most canonical)
            best_key = min(matches.keys(), key=len)
            found[missing] = dict(matches[best_key])
            found[missing]["_matched_key"] = best_key
            print(f"  {missing} -> matched to '{best_key}'")
        else:
            print(f"  {missing} -> NOT FOUND in LiteLLM")

print("\n" + "=" * 100)
print("\n--- Extracted Model Data ---\n")

for model_id in sorted(found.keys()):
    info = found[model_id]
    matched = info.pop("_matched_key", None)
    input_cost = info.get("input_cost_per_token", 0)
    output_cost = info.get("output_cost_per_token", 0)
    max_input = info.get("max_input_tokens", info.get("max_tokens", "N/A"))
    max_output = info.get("max_output_tokens", "N/A")
    
    # Convert per-token cost to per-million-token cost for readability
    input_per_m = input_cost * 1_000_000 if input_cost else 0
    output_per_m = output_cost * 1_000_000 if output_cost else 0
    
    label = f" (matched: {matched})" if matched else ""
    print(f"Model: {model_id}{label}")
    print(f"  max_input_tokens:  {max_input}")
    print(f"  max_output_tokens: {max_output}")
    print(f"  input_cost/M:      ${input_per_m:.4f}")
    print(f"  output_cost/M:     ${output_per_m:.4f}")
    
    # Show additional useful fields
    for extra_key in ["supports_function_calling", "supports_tool_choice", "supports_streaming"]:
        if extra_key in info:
            print(f"  {extra_key}: {info[extra_key]}")
    print()
