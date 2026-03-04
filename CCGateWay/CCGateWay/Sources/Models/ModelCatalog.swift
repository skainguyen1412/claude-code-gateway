import Foundation

/// Cost per million tokens (USD).
struct ModelCost: Hashable {
    let inputPerMillion: Double  // $ per 1M input tokens
    let outputPerMillion: Double  // $ per 1M output tokens

    /// Estimate cost for a single request.
    func estimate(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * inputPerMillion
        let outputCost = Double(outputTokens) / 1_000_000.0 * outputPerMillion
        return inputCost + outputCost
    }
}

/// A single model entry in the catalog.
struct ModelInfo: Identifiable, Hashable {
    var id: String { modelId }
    let modelId: String  // API identifier, e.g. "gemini-3.1-pro-preview"
    let displayName: String  // Human-readable, e.g. "Gemini 3.1 Pro"
    let tier: ModelTier  // Capability tier
    let maxInputTokens: Int  // Max input context window
    let maxOutputTokens: Int  // Max output tokens
    let cost: ModelCost  // Pricing per million tokens
    let supportsFunctionCalling: Bool
    let supportsStreaming: Bool
}

/// Capability tier — helps the UI suggest models for each slot.
enum ModelTier: String, CaseIterable, Codable {
    case flagship  // Best reasoning / coding — "think" & "default" slots
    case standard  // Good all-rounder — "default" slot
    case fast  // Optimized for speed — "background" slot
    case reasoning  // Deep reasoning specialist — "think" slot
}

/// Central catalog of curated models per provider.
/// Pricing & context windows sourced from LiteLLM (github.com/BerriAI/litellm).
enum ModelCatalog {

    // MARK: - Gemini

    static let gemini: [ModelInfo] = [
        ModelInfo(
            modelId: "gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro",
            tier: .flagship,
            maxInputTokens: 1_048_576,
            maxOutputTokens: 65_536,
            cost: ModelCost(inputPerMillion: 2.00, outputPerMillion: 12.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gemini-3-flash-preview",
            displayName: "Gemini 3 Flash",
            tier: .fast,
            maxInputTokens: 1_048_576,
            maxOutputTokens: 65_535,
            cost: ModelCost(inputPerMillion: 0.50, outputPerMillion: 3.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gemini-3.1-flash-lite-preview",
            displayName: "Gemini 3.1 Flash Lite",
            tier: .fast,
            maxInputTokens: 1_048_576,
            maxOutputTokens: 65_536,
            cost: ModelCost(inputPerMillion: 0.25, outputPerMillion: 1.50),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            tier: .flagship,
            maxInputTokens: 1_048_576,
            maxOutputTokens: 65_535,
            cost: ModelCost(inputPerMillion: 1.25, outputPerMillion: 10.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            tier: .fast,
            maxInputTokens: 1_048_576,
            maxOutputTokens: 65_535,
            cost: ModelCost(inputPerMillion: 0.30, outputPerMillion: 2.50),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
    ]

    // MARK: - OpenAI

    static let openAI: [ModelInfo] = [
        ModelInfo(
            modelId: "gpt-5",
            displayName: "GPT-5",
            tier: .flagship,
            maxInputTokens: 272_000,
            maxOutputTokens: 128_000,
            cost: ModelCost(inputPerMillion: 1.25, outputPerMillion: 10.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gpt-5-mini",
            displayName: "GPT-5 Mini",
            tier: .fast,
            maxInputTokens: 272_000,
            maxOutputTokens: 128_000,
            cost: ModelCost(inputPerMillion: 0.25, outputPerMillion: 2.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gpt-5.2-pro",
            displayName: "GPT-5.2 Pro",
            tier: .flagship,
            maxInputTokens: 272_000,
            maxOutputTokens: 128_000,
            cost: ModelCost(inputPerMillion: 21.00, outputPerMillion: 168.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gpt-5.2",
            displayName: "GPT-5.2",
            tier: .standard,
            maxInputTokens: 272_000,
            maxOutputTokens: 128_000,
            cost: ModelCost(inputPerMillion: 1.75, outputPerMillion: 14.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "o3",
            displayName: "o3",
            tier: .reasoning,
            maxInputTokens: 200_000,
            maxOutputTokens: 100_000,
            cost: ModelCost(inputPerMillion: 2.00, outputPerMillion: 8.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "o4-mini",
            displayName: "o4 Mini",
            tier: .reasoning,
            maxInputTokens: 200_000,
            maxOutputTokens: 100_000,
            cost: ModelCost(inputPerMillion: 1.10, outputPerMillion: 4.40),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
    ]

    // MARK: - DeepSeek

    static let deepSeek: [ModelInfo] = [
        ModelInfo(
            modelId: "deepseek-chat",
            displayName: "DeepSeek V3.2 Chat",
            tier: .flagship,
            maxInputTokens: 131_072,
            maxOutputTokens: 8_192,
            cost: ModelCost(inputPerMillion: 0.28, outputPerMillion: 0.42),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "deepseek-reasoner",
            displayName: "DeepSeek V3.2 Reasoner",
            tier: .reasoning,
            maxInputTokens: 131_072,
            maxOutputTokens: 65_536,
            cost: ModelCost(inputPerMillion: 0.28, outputPerMillion: 0.42),
            supportsFunctionCalling: false,
            supportsStreaming: true
        ),
    ]

    // MARK: - OpenRouter

    static let openRouter: [ModelInfo] = [
        ModelInfo(
            modelId: "google/gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro",
            tier: .flagship,
            maxInputTokens: 1_048_576,
            maxOutputTokens: 65_536,
            cost: ModelCost(inputPerMillion: 2.00, outputPerMillion: 12.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "openai/gpt-5",
            displayName: "GPT-5",
            tier: .flagship,
            maxInputTokens: 272_000,
            maxOutputTokens: 128_000,
            cost: ModelCost(inputPerMillion: 1.25, outputPerMillion: 10.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "deepseek/deepseek-chat",
            displayName: "DeepSeek V3.2 Chat",
            tier: .standard,
            maxInputTokens: 65_536,
            maxOutputTokens: 8_192,
            cost: ModelCost(inputPerMillion: 0.14, outputPerMillion: 0.28),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "anthropic/claude-opus-4",
            displayName: "Claude Opus 4",
            tier: .flagship,
            maxInputTokens: 200_000,
            maxOutputTokens: 32_000,
            cost: ModelCost(inputPerMillion: 15.00, outputPerMillion: 75.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "anthropic/claude-sonnet-4",
            displayName: "Claude Sonnet 4",
            tier: .standard,
            maxInputTokens: 1_000_000,
            maxOutputTokens: 64_000,
            cost: ModelCost(inputPerMillion: 3.00, outputPerMillion: 15.00),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
    ]

    // MARK: - Groq

    static let groq: [ModelInfo] = [
        ModelInfo(
            modelId: "llama-3.3-70b-versatile",
            displayName: "Llama 3.3 70B",
            tier: .flagship,
            maxInputTokens: 128_000,
            maxOutputTokens: 32_768,
            cost: ModelCost(inputPerMillion: 0.59, outputPerMillion: 0.79),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gpt-oss-120b",
            displayName: "GPT-OSS 120B",
            tier: .flagship,
            maxInputTokens: 131_072,
            maxOutputTokens: 131_072,
            cost: ModelCost(inputPerMillion: 0.15, outputPerMillion: 0.60),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "gpt-oss-20b",
            displayName: "GPT-OSS 20B",
            tier: .fast,
            maxInputTokens: 131_000,
            maxOutputTokens: 131_000,
            cost: ModelCost(inputPerMillion: 0.04, outputPerMillion: 0.15),
            supportsFunctionCalling: false,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "llama-3.1-8b-instant",
            displayName: "Llama 3.1 8B Instant",
            tier: .fast,
            maxInputTokens: 128_000,
            maxOutputTokens: 8_192,
            cost: ModelCost(inputPerMillion: 0.05, outputPerMillion: 0.08),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
        ModelInfo(
            modelId: "llama-4-scout-17b-16e-instruct",
            displayName: "Llama 4 Scout 17B",
            tier: .standard,
            maxInputTokens: 192_000,
            maxOutputTokens: 4_000,
            cost: ModelCost(inputPerMillion: 0.72, outputPerMillion: 0.72),
            supportsFunctionCalling: true,
            supportsStreaming: true
        ),
    ]

    // MARK: - Lookup

    /// Returns the curated model list for a given provider type name.
    static func models(forProvider providerName: String) -> [ModelInfo] {
        switch providerName.lowercased() {
        case "gemini":
            return gemini
        case "openai":
            return openAI
        case "deepseek":
            return deepSeek
        case "openrouter":
            return openRouter
        case "groq":
            return groq
        default:
            return []
        }
    }

    /// Returns models filtered to a recommended slot assignment.
    static func recommended(forSlot slot: String, provider providerName: String) -> [ModelInfo] {
        let all = models(forProvider: providerName)
        switch slot {
        case "default":
            return all.filter { $0.tier == .flagship || $0.tier == .standard }
        case "background":
            return all.filter { $0.tier == .fast || $0.tier == .standard }
        case "think":
            return all.filter { $0.tier == .reasoning || $0.tier == .flagship }
        case "longContext":
            // Prefer models with large context windows
            return all.sorted { $0.maxInputTokens > $1.maxInputTokens }
        default:
            return all
        }
    }

    /// Look up a specific model by ID across all providers.
    static func find(modelId: String) -> ModelInfo? {
        let allModels = gemini + openAI + deepSeek + openRouter + groq
        return allModels.first { $0.modelId == modelId }
    }
}
