import Foundation

/// Formats monetary values returned by the Anthropic API for the "Extra Credits"
/// pool. The API returns amounts in the **minor unit** of the configured
/// currency (cents for USD/EUR, no division for JPY/KRW, mils for KWD/BHD).
/// Naively passing those values through a `.currency` `NumberFormatter` shows
/// them x100 (or x1000) too large. This helper looks up the canonical
/// fraction-digit count per ISO 4217 currency and divides accordingly.
enum CurrencyFormatter {
    /// Formats a minor-unit amount (e.g. `18000` cents) as a localised currency
    /// string (e.g. `$180`).
    ///
    /// - Parameters:
    ///   - minorUnits: amount in the currency's minor unit.
    ///   - currencyCode: ISO 4217 code. Falls back to `USD` when nil/empty so
    ///     the dashboard never renders a raw number without a symbol.
    ///   - locale: locale used for digit grouping and symbol placement.
    ///     Defaults to the user's current locale; tests pin it for stability.
    ///   - forceFractionDigits: keep the currency's canonical fraction digits
    ///     even on whole values (`$180.00`). Used for worst-case width
    ///     measurement, where the widest rendering the value could ever take
    ///     is what matters.
    /// - Returns: localised currency string. Whole major-unit values omit
    ///   trailing zeros (`$180`, not `$180.00`) unless forced; fractional
    ///   values keep the currency's canonical fraction digits (`$180.50`).
    static func formatMinorUnits(
        _ minorUnits: Double,
        currencyCode: String?,
        locale: Locale = .current,
        forceFractionDigits: Bool = false
    ) -> String {
        let code = (currencyCode?.isEmpty == false) ? currencyCode! : "USD"

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale

        // Once `currencyCode` is set, `maximumFractionDigits` reflects the
        // canonical minor-unit count for that ISO 4217 code:
        // USD/EUR=2, JPY/KRW=0, KWD/BHD=3. We use that to scale the raw value
        // back to the major unit.
        let fractionDigits = formatter.maximumFractionDigits
        let divisor = pow(10.0, Double(fractionDigits))
        let majorValue = divisor > 0 ? minorUnits / divisor : minorUnits

        let isWhole = majorValue.truncatingRemainder(dividingBy: 1) == 0
        let collapse = isWhole && !forceFractionDigits
        formatter.maximumFractionDigits = collapse ? 0 : fractionDigits
        formatter.minimumFractionDigits = collapse ? 0 : fractionDigits

        return formatter.string(from: NSNumber(value: majorValue))
            ?? "\(code) \(majorValue)"
    }

    /// Formats an estimated cost given in **major units** (dollars, not cents)
    /// for the History cost estimate. Always shows the currency's canonical
    /// fraction digits (2 for USD), so `12.5` renders `$12.50`. A positive
    /// amount that rounds below one cent collapses to `<$0.01` rather than
    /// lying with `$0.00`. Zero renders as `$0.00`.
    ///
    /// - Parameters:
    ///   - amount: cost in major units (e.g. `12.5` for twelve dollars fifty).
    ///   - currencyCode: ISO 4217 code; falls back to `USD`.
    ///   - locale: locale for grouping + symbol placement.
    static func formatEstimatedCost(
        _ amount: Double,
        currencyCode: String? = "USD",
        locale: Locale = .current
    ) -> String {
        let code = (currencyCode?.isEmpty == false) ? currencyCode! : "USD"

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale

        let fractionDigits = formatter.maximumFractionDigits
        let epsilon = fractionDigits > 0 ? pow(10.0, -Double(fractionDigits)) : 1

        // Sub-minor-unit but non-zero: don't round down to a misleading zero.
        if amount > 0 && amount < epsilon {
            let threshold = formatter.string(from: NSNumber(value: epsilon)) ?? "\(code) \(epsilon)"
            return "<\(threshold)"
        }

        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: amount)) ?? "\(code) \(amount)"
    }
}
