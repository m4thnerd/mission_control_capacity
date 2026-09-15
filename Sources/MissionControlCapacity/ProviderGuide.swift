import CapacityCore

/// Plain-language notes on what each provider's models are generally known to
/// be best for. This is opinionated guidance for deciding where to send the
/// next project, or which provider to fall back to when one runs low, not a
/// benchmark. Keep each line short: cards are narrow.
struct ProviderGuide {
    let headline: String
    let bestFor: [String]

    static func forProvider(_ id: ProviderID) -> ProviderGuide {
        switch id {
        case .openAI:
            ProviderGuide(
                headline: "Deep reasoning, hands-off coding",
                bestFor: [
                    "Long autonomous coding runs in Codex",
                    "Hard math, algorithms and logic puzzles",
                    "Broad general knowledge and ChatGPT tools"
                ]
            )
        case .anthropic:
            ProviderGuide(
                headline: "Careful work on real codebases",
                bestFor: [
                    "Big, messy repos and multi-file refactors",
                    "Agentic work with tools, tests and PRs",
                    "Clear writing and following instructions closely"
                ]
            )
        case .google:
            ProviderGuide(
                headline: "Huge context and multimodal input",
                bestFor: [
                    "Whole repos, long PDFs, images and video",
                    "Fast, high-volume work at low cost",
                    "UI and front-end generation, Google ecosystem"
                ]
            )
        case .cursor:
            ProviderGuide(
                headline: "Fast iteration inside the editor",
                bestFor: [
                    "Inline edits, tab completion and quick fixes",
                    "Pairing on a repo you already have open",
                    "Switching models per task, including Grok"
                ]
            )
        case .xAI:
            ProviderGuide(
                headline: "Live information and speed",
                bestFor: [
                    "Real-time web and X data",
                    "Quick, informal answers"
                ]
            )
        }
    }
}
