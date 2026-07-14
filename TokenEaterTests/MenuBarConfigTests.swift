import Testing
import Foundation

@Suite("MenuBarConfig")
struct MenuBarConfigTests {

    @Test("defaults match the spec")
    func defaults() {
        let config = MenuBarConfig()
        #expect(config.pinned == [.init(id: .fiveHour), .init(id: .sevenDay)])
        #expect(config.displayMode == .all)
        #expect(config.rotateSeconds == 5)
        #expect(config.colorMode == .risk)
        #expect(config.showIcon == true)
        #expect(config.separator == "\u{00B7}")
        #expect(config.fixedWidth == false)
    }

    @Test("PinnedMetricConfig defaults")
    func pinnedDefaults() {
        let pin = PinnedMetricConfig(id: .sonnet)
        #expect(pin.prefix == .shortLabel)
        #expect(pin.value == .percentUsed)
        #expect(pin.showCountdown == false)
    }

    @Test("Codable round-trip preserves every field")
    func roundTrip() throws {
        let original = MenuBarConfig(
            pinned: [
                .init(id: .fiveHour, prefix: .symbol, value: .percentRemaining, showCountdown: true),
                .init(id: .extraCredits, prefix: .none, value: .dollars, showCountdown: false),
            ],
            displayMode: .rotate,
            rotateSeconds: 12,
            colorMode: .monochrome,
            showIcon: false,
            separator: "|",
            fixedWidth: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("decoding an empty JSON object falls back to every field default")
    func decodeMissingKeys() throws {
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: data)
        #expect(decoded == MenuBarConfig())
    }

    @Test("decoding a partial JSON object fills only the missing fields with defaults")
    func decodePartialKeys() throws {
        let data = Data(#"{"displayMode":"highestRisk","rotateSeconds":9}"#.utf8)
        let decoded = try JSONDecoder().decode(MenuBarConfig.self, from: data)
        #expect(decoded.displayMode == .highestRisk)
        #expect(decoded.rotateSeconds == 9)
        // Untouched fields still fall back to defaults.
        #expect(decoded.pinned == MenuBarConfig().pinned)
        #expect(decoded.colorMode == .risk)
        #expect(decoded.showIcon == true)
        #expect(decoded.separator == "\u{00B7}")
        #expect(decoded.fixedWidth == false)
    }

    @Test("PinnedMetricConfig decoding with only id present fills the rest with defaults")
    func pinnedDecodeMissingKeys() throws {
        let data = Data(#"{"id":"sevenDay"}"#.utf8)
        let decoded = try JSONDecoder().decode(PinnedMetricConfig.self, from: data)
        #expect(decoded == PinnedMetricConfig(id: .sevenDay))
    }

    @Test("menuBarPinnable excludes sessionReset, opus and cowork")
    func pinnableExcludesSessionReset() {
        #expect(!MetricID.menuBarPinnable.contains(.sessionReset))
        #expect(!MetricID.menuBarPinnable.contains(.opus))
        #expect(!MetricID.menuBarPinnable.contains(.cowork))
        #expect(MetricID.menuBarPinnable.contains(.fiveHour))
        #expect(MetricID.menuBarPinnable.contains(.serviceStatus))
        #expect(MetricID.menuBarPinnable.count == MetricID.allCases.count - 3)
    }
}
