import Foundation
import Testing
@testable import CapacityCore

@Suite("OpenAI usage parsing")
struct UsageParsersTests {
    @Test("includes account-wide and model-specific pools")
    func includesAccountWideAndModelSpecificPools() throws {
        let raw = #"""
        {"id":1,"result":{"userAgent":"test"}}
        {"id":2,"result":{"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":3,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":null,"planType":"pro"},"codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1800000100},"secondary":{"usedPercent":34,"windowDurationMins":10080,"resetsAt":1800000200},"planType":"pro"}},"rateLimitResetCredits":{"availableCount":1}}}
        """#

        let snapshot = try UsageParsers.openAI(raw, now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.state == .connected)
        #expect(snapshot.plan == "Pro")
        #expect(snapshot.windows.map(\.id) == [
            "codex-primary",
            "codex_bengalfox-primary",
            "codex_bengalfox-secondary"
        ])
        #expect(snapshot.windows.map(\.label) == [
            "Codex account-wide · Weekly",
            "GPT-5.3-Codex-Spark · 5 hours",
            "GPT-5.3-Codex-Spark · Weekly"
        ])
        #expect(snapshot.windows.map(\.usedPercent) == [3, 12, 34])
        #expect(snapshot.metrics.first {
            $0.id == "openai-account-wide-5-hour-unreported"
        }?.value == "Not reported")
        #expect(snapshot.metrics.first { $0.label == "Full resets" }?.value == "1 available")
    }

    @Test("uses a readable fallback for an unnamed model pool")
    func usesReadableFallbackForUnnamedModelPool() throws {
        let raw = #"""
        {"id":2,"result":{"rateLimitsByLimitId":{"codex_future-model":{"limitId":"codex_future-model","limitName":"  ","primary":{"usedPercent":"7.5","windowDurationMins":"60","resetsAt":"1800000000"},"secondary":null,"planType":"pro"}}}}
        """#

        let snapshot = try UsageParsers.openAI(raw)

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].label == "Codex Future Model · 60 minutes")
        #expect(snapshot.windows[0].usedPercent == 7.5)
        #expect(snapshot.metrics.isEmpty)
    }
}
