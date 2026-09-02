import Foundation

public struct WeeklyUsage: Equatable, Sendable {
    public enum Period: String, Sendable {
        case weekly
        case monthly
        case unknown
    }

    public var usedPercent: Double
    public var period: Period
    public var periodEnd: Date?
    public var tier: String?
    public var fetchedAt: Date?

    public init(
        usedPercent: Double,
        period: Period = .weekly,
        periodEnd: Date? = nil,
        tier: String? = nil,
        fetchedAt: Date? = nil
    ) {
        self.usedPercent = usedPercent
        self.period = period
        self.periodEnd = periodEnd
        self.tier = tier
        self.fetchedAt = fetchedAt
    }

    public var percentLabel: String {
        let clamped = min(max(usedPercent, 0), 100)
        if abs(clamped.rounded() - clamped) < 0.05 {
            return "\(Int(clamped.rounded()))%"
        }
        return String(format: "%.1f%%", clamped)
    }

    public var title: String {
        switch period {
        case .weekly: "Weekly usage"
        case .monthly: "Monthly usage"
        case .unknown: "Usage"
        }
    }

    public func resetLabel(locale: Locale = .current) -> String? {
        guard let periodEnd else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = false
        return "Resets \(formatter.string(from: periodEnd))"
    }

    /// Live remaining time, always days, hours, minutes, seconds.
    public func countdownLabel(now: Date = Date()) -> String? {
        guard let periodEnd else { return nil }
        return Self.countdownPhrase(until: periodEnd, now: now)
    }

    public static func countdownPhrase(until end: Date, now: Date) -> String {
        let remaining = end.timeIntervalSince(now)
        if remaining <= 0 { return "Reset due" }
        let total = Int(remaining.rounded(.down))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return String(format: "%dd %02dh %02dm %02ds", days, hours, minutes, seconds)
    }

    public var tooltip: String {
        var parts: [String] = []
        if let tier, !tier.isEmpty { parts.append(tier) }
        switch period {
        case .weekly: parts.append("weekly")
        case .monthly: parts.append("monthly")
        case .unknown: break
        }
        if let periodEnd {
            parts.append(Self.resetsPhrase(until: periodEnd, now: Date()))
        }
        return parts.isEmpty ? "Plan usage from Grok billing." : parts.joined(separator: " · ")
    }

    public static func resetsPhrase(until end: Date, now: Date) -> String {
        let seconds = end.timeIntervalSince(now)
        if seconds <= 0 { return "reset due" }
        let days = Int(seconds / 86_400)
        let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3_600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(max(1, minutes))m"
    }

    /// Latest `billing: fetched credits config` line in `unified.jsonl`.
    public static func latest(in log: URL, maxBytes: Int = 1_048_576) -> WeeklyUsage? {
        guard FileManager.default.fileExists(atPath: log.path) else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do {
            try handle.seek(toOffset: start)
        } catch {
            return nil
        }
        let data = (try? handle.readToEnd()) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        for line in text.split(separator: "\n").reversed() {
            if let parsed = parse(line: String(line)) {
                return parsed
            }
        }
        return nil
    }

    public static func parse(line: String) -> WeeklyUsage? {
        guard line.contains("billing: fetched credits config") else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return nil
        }
        guard let msg = object["msg"] as? String, msg == "billing: fetched credits config" else {
            return nil
        }
        let ctx = object["ctx"] as? [String: Any] ?? [:]
        let config = ctx["config"] as? [String: Any] ?? [:]
        guard let percent = percent(from: config) else { return nil }

        let periodObject = config["currentPeriod"] as? [String: Any]
        let periodType = periodObject?["type"] as? String
            ?? config["billingPeriodType"] as? String
        let endString = periodObject?["end"] as? String
            ?? config["billingPeriodEnd"] as? String

        return WeeklyUsage(
            usedPercent: percent,
            period: Period(rawType: periodType),
            periodEnd: endString.flatMap(parseDate),
            tier: ctx["subscriptionTier"] as? String,
            fetchedAt: (object["ts"] as? String).flatMap(parseDate)
        )
    }

    private static func percent(from config: [String: Any]) -> Double? {
        if let value = config["creditUsagePercent"] as? Double {
            return value
        }
        if let value = config["creditUsagePercent"] as? Int {
            return Double(value)
        }
        if let used = money(config["onDemandUsed"]),
           let cap = money(config["onDemandCap"]),
           cap > 0
        {
            return used / cap * 100
        }
        return nil
    }

    private static func money(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let object = value as? [String: Any] {
            if let number = object["val"] as? Double { return number }
            if let number = object["val"] as? Int { return Double(number) }
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: string)
    }
}

private extension WeeklyUsage.Period {
    init(rawType: String?) {
        switch rawType {
        case "USAGE_PERIOD_TYPE_WEEKLY", "weekly", "WEEKLY":
            self = .weekly
        case "USAGE_PERIOD_TYPE_MONTHLY", "monthly", "MONTHLY":
            self = .monthly
        default:
            self = .unknown
        }
    }
}
