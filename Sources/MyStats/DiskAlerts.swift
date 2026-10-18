import Foundation

// Tracks, per disk, the deepest threshold already announced, and turns free-space readings into
// Slack messages: one loud alert per threshold crossed downward, one silent "recovered" note when
// free space climbs back `recoveryMarginGB` above it (the margin stops flapping around a line).
// State lives in UserDefaults so a restart neither repeats nor forgets alerts.
final class DiskAlerts {
    struct Status {
        var alerting: Bool        // below a threshold that has been announced and not yet recovered
        var nextAlertGB: Double?  // the next threshold that would fire, if any
    }

    private struct State: Codable {
        var rule: AlertRule       // state is reset when the rule for this disk changes
        var fired: Int?           // index into rule.levels of the deepest announced threshold
    }

    private let stateKey = "alertState"
    private var states: [String: State]

    init() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let saved = try? JSONDecoder().decode([String: State].self, from: data) {
            states = saved
        } else {
            states = [:]
        }
    }

    // `key` identifies the disk ("internal" or a volume UUID); `label` is how messages name it.
    @discardableResult
    func evaluate(key: String, label: String, device: String, rule: AlertRule,
                  usage: DiskUsage, margin: Double) -> Status {
        let levels = rule.levels
        let free = Double(usage.free) / 1e9   // df-style free: stable, never inflated by purgeable
        var state = states[key].flatMap { $0.rule == rule ? $0 : nil } ?? State(rule: rule, fired: nil)
        let before = state.fired

        // Recovery: re-arm every announced threshold we are now comfortably above.
        if let fired = state.fired {
            let stillBelow = (0...fired).last { free < levels[$0] + margin }
            if stillBelow != fired {
                state.fired = stillBelow
                let rearmed = levels[(stillBelow ?? -1) + 1]
                SlackNotifier.shared.send(
                    "🟢 \(device) · \(label) 回升到 \(gb(free))，已回到 \(gb(rearmed)) 以上。"
                    + nextSentence(levels, after: state.fired), silent: true)
            }
        }

        // Alert: the deepest threshold now crossed, if deeper than anything announced.
        if let crossed = levels.lastIndex(where: { free < $0 }), crossed > (state.fired ?? -1) {
            state.fired = crossed
            SlackNotifier.shared.send(
                "🔴 \(device) · \(label) 剩 \(gb(free))，跌破 \(gb(levels[crossed]))"
                + "（已用 \(String(format: "%.1f", usage.percentage * 100))%，共 \(capacity(usage.total))）。"
                + nextSentence(levels, after: state.fired))
        }

        if state.fired != before || states[key]?.rule != rule {
            states[key] = state
            UserDefaults.standard.set(try? JSONEncoder().encode(states), forKey: stateKey)
        }
        return Status(alerting: state.fired != nil, nextAlertGB: next(levels, after: state.fired))
    }

    private func next(_ levels: [Double], after fired: Int?) -> Double? {
        let i = (fired ?? -1) + 1
        return i < levels.count ? levels[i] : nil
    }

    private func nextSentence(_ levels: [Double], after fired: Int?) -> String {
        next(levels, after: fired).map { "下一次在 \(gb($0)) 时提醒。" } ?? ""
    }

    private func gb(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f GB", value) : String(format: "%.1f GB", value)
    }

    private func capacity(_ bytes: Int64) -> String {
        let g = Double(bytes) / 1e9
        return g >= 1000 ? String(format: "%.2f TB", g / 1000) : String(format: "%.0f GB", g)
    }
}
