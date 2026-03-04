import Foundation
import SwiftUI

struct ProviderConfig: Codable, Identifiable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var type: String  // "gemini", "openrouter", "openai", "deepseek"
    var baseUrl: String
    var slots: [String: String]  // "default" -> "gemini-3.1-pro-preview"
    var enabled: Bool = true

    /// Key used to look up this provider's curated model list in `ModelCatalog`.
    var catalogKey: String {
        switch name.lowercased() {
        case "gemini": return "gemini"
        case "openai": return "openai"
        case "deepseek": return "deepseek"
        case "openrouter": return "openrouter"
        case "groq": return "groq"
        default: return type  // fallback to endpoint type
        }
    }

    static let templates: [ProviderConfig] = [
        geminiDefault,
        openAIDefault,
        ProviderConfig(
            name: "DeepSeek",
            type: "openai",
            baseUrl: "https://api.deepseek.com",
            slots: [
                "default": "deepseek-chat",
                "background": "deepseek-chat",
                "think": "deepseek-reasoner",
                "longContext": "deepseek-chat",
            ]
        ),
        ProviderConfig(
            name: "OpenRouter",
            type: "openai",
            baseUrl: "https://openrouter.ai/api/v1",
            slots: [
                "default": "google/gemini-3.1-pro-preview",
                "background": "deepseek/deepseek-chat",
                "think": "anthropic/claude-opus-4",
                "longContext": "google/gemini-3.1-pro-preview",
            ]
        ),
        ProviderConfig(
            name: "Groq",
            type: "openai",
            baseUrl: "https://api.groq.com/openai/v1",
            slots: [
                "default": "llama-3.3-70b-versatile",
                "background": "llama-3.1-8b-instant",
                "think": "gpt-oss-120b",
                "longContext": "llama-3.3-70b-versatile",
            ]
        ),
    ]

    static let geminiDefault = ProviderConfig(
        name: "Gemini",
        type: "gemini",
        baseUrl: "https://generativelanguage.googleapis.com/v1beta/models/",
        slots: [
            "default": "gemini-3.1-pro-preview",
            "background": "gemini-3-flash-preview",
            "think": "gemini-3.1-pro-preview",
            "longContext": "gemini-3.1-pro-preview",
        ]
    )

    static let openAIDefault = ProviderConfig(
        name: "OpenAI",
        type: "openai",
        baseUrl: "https://api.openai.com/v1",
        slots: [
            "default": "gpt-5",
            "background": "gpt-5-mini",
            "think": "o3",
            "longContext": "gpt-5.2-pro",
        ]
    )
}

/// Icon metadata for provider branding across the UI.
struct ProviderIconInfo {
    /// Asset catalog image name (nil if no custom logo exists).
    let assetName: String?
    /// SF Symbol fallback when no asset image is available.
    let sfSymbol: String
    /// Accent color used for tinting and backgrounds.
    let color: Color
}

extension ProviderConfig {
    static func providerIcon(for name: String) -> ProviderIconInfo {
        switch name.lowercased() {
        case "gemini":
            return ProviderIconInfo(assetName: "gemini_icon", sfSymbol: "sparkles", color: .blue)
        case "openai":
            return ProviderIconInfo(
                assetName: "openai_icon", sfSymbol: "brain.head.profile", color: .green)
        case "deepseek":
            return ProviderIconInfo(
                assetName: "deepseek_icon", sfSymbol: "waveform.path.ecg", color: .indigo)
        case "openrouter":
            return ProviderIconInfo(
                assetName: "openrouter_icon", sfSymbol: "network", color: .purple)
        case "groq":
            return ProviderIconInfo(assetName: "groq_icon", sfSymbol: "bolt.fill", color: .orange)
        default:
            return ProviderIconInfo(assetName: nil, sfSymbol: "server.rack", color: .gray)
        }
    }

    var providerIcon: ProviderIconInfo {
        Self.providerIcon(for: name)
    }
}

/// Reusable view that renders a provider icon — asset image or SF Symbol fallback.
struct ProviderIconView: View {
    let icon: ProviderIconInfo
    let size: CGFloat

    init(providerName: String, size: CGFloat = 24) {
        self.icon = ProviderConfig.providerIcon(for: providerName)
        self.size = size
    }

    init(icon: ProviderIconInfo, size: CGFloat = 24) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Group {
            if let assetName = icon.assetName {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: icon.sfSymbol)
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundColor(icon.color)
                    .frame(width: size, height: size)
            }
        }
    }
}
