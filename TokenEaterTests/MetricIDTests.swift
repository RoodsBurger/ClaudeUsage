import Testing
import Foundation

@Suite("MetricID")
struct MetricIDTests {

    @Test("extraCredits has a stable raw value for persistence")
    func extraCreditsRawValue() {
        // pinnedMetrics persists raw values to UserDefaults, so this string is
        // a storage contract — changing it would silently drop users' pins.
        #expect(MetricID.extraCredits.rawValue == "extraCredits")
        #expect(MetricID(rawValue: "extraCredits") == .extraCredits)
    }

    @Test("extraCredits is enumerable and labelled")
    func extraCreditsLabels() {
        #expect(MetricID.allCases.contains(.extraCredits))
        #expect(MetricID.extraCredits.shortLabel == "EC")
        #expect(!MetricID.extraCredits.label.isEmpty)
    }

    @Test("opus and cowork have stable raw values for persistence")
    func opusCoworkRawValues() {
        #expect(MetricID.opus.rawValue == "opus")
        #expect(MetricID(rawValue: "opus") == .opus)
        #expect(MetricID.cowork.rawValue == "cowork")
        #expect(MetricID(rawValue: "cowork") == .cowork)
    }

    @Test("opus and cowork are enumerable and labelled")
    func opusCoworkLabels() {
        #expect(MetricID.allCases.contains(.opus))
        #expect(MetricID.allCases.contains(.cowork))
        #expect(!MetricID.opus.label.isEmpty)
        #expect(!MetricID.cowork.label.isEmpty)
    }
}
