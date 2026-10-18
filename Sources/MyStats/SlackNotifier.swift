import Foundation

// Sends DMs through the "DM Myself" Slack app, reusing its credentials file
// (~/.config/dm-myself/credentials.json) and its two delivery modes:
//   loud   = bot token → bot↔user DM channel; Slack pushes it (sound/banner).
//   silent = user token → your own self-DM; recorded, never pushes.
// Same API calls as `dm_myself.py push` / `note`.
//
// Messages are queued in UserDefaults before the first attempt, so an alert raised while offline
// (or right before quit) is delivered later instead of lost. chat.postMessage has no idempotency
// key: a timeout whose request actually reached Slack is retried and may arrive twice — for a
// disk alert a duplicate is the lesser harm compared with a missed one.
final class SlackNotifier {
    static let shared = SlackNotifier()

    private struct Pending: Codable {
        var id: String
        var text: String
        var silent: Bool
    }

    private enum Failure: Error {
        case needsUser(String)               // bad/missing credentials: retrying won't help
        case transient(String, retryAfter: TimeInterval?)
    }

    static let credentialsPath = NSHomeDirectory() + "/.config/dm-myself/credentials.json"
    private let queueKey = "slackQueue"
    private let maxQueue = 50

    private var queue: [Pending]
    private var sending = false
    private var failures = 0
    private var nextAttempt = Date.distantPast
    // When paused on a credentials problem, remember the file's mtime; editing the file resumes.
    private var pausedCredentialsModDate: Date??

    // One-line state for the menu: nil when healthy and empty.
    private(set) var problem: String?

    var pendingCount: Int { queue.count }

    private init() {
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let saved = try? JSONDecoder().decode([Pending].self, from: data) {
            queue = saved
        } else {
            queue = []
        }
    }

    func send(_ text: String, silent: Bool = false) {
        queue.append(Pending(id: UUID().uuidString, text: text, silent: silent))
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        persist()
        nextAttempt = .distantPast
        flush()
    }

    // Called on every alert check (and after send). Main thread only.
    func flush(force: Bool = false) {
        if force {
            pausedCredentialsModDate = nil
            nextAttempt = .distantPast
        }
        if let pausedAt = pausedCredentialsModDate {
            guard credentialsModDate() != pausedAt else { return }
            pausedCredentialsModDate = nil
            nextAttempt = .distantPast
        }
        guard !sending, let head = queue.first, Date() >= nextAttempt else { return }
        sending = true
        post(head) { [weak self] result in
            DispatchQueue.main.async { self?.finish(head, result) }
        }
    }

    private func finish(_ item: Pending, _ result: Result<Void, Failure>) {
        sending = false
        switch result {
        case .success:
            queue.removeAll { $0.id == item.id }
            persist()
            failures = 0
            problem = nil
            flush()
        case .failure(.needsUser(let why)):
            problem = why
            pausedCredentialsModDate = .some(credentialsModDate())
        case .failure(.transient(let why, let retryAfter)):
            failures += 1
            problem = why
            // Capped exponential backoff with jitter: 1, 2, 4 … 30 min.
            let backoff = min(60 * pow(2, Double(failures - 1)), 1800) * Double.random(in: 0.8...1.2)
            nextAttempt = Date().addingTimeInterval(max(backoff, retryAfter ?? 0))
        }
    }

    private func post(_ item: Pending, completion: @escaping (Result<Void, Failure>) -> Void) {
        guard let data = FileManager.default.contents(atPath: Self.credentialsPath),
              let creds = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return completion(.failure(.needsUser("Slack credentials missing")))
        }
        func field(_ key: String) -> String? {
            let v = (creds[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return v.isEmpty ? nil : v
        }
        let token: String, body: [String: Any]
        if item.silent {
            guard let t = field("user_token"), let user = field("user_id") else {
                return completion(.failure(.needsUser("Slack user_token missing")))
            }
            token = t
            body = ["channel": user, "text": item.text, "as_user": true]
        } else {
            guard let t = field("bot_token"), let dm = field("dm_channel") else {
                return completion(.failure(.needsUser("Slack bot_token missing")))
            }
            token = t
            body = ["channel": dm, "text": item.text]
        }

        var req = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            if error != nil { return completion(.failure(.transient("Slack unreachable", retryAfter: nil))) }
            let http = response as? HTTPURLResponse
            if http?.statusCode == 429 {
                let after = (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
                return completion(.failure(.transient("Slack rate limited", retryAfter: after)))
            }
            guard let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return completion(.failure(.transient("Slack bad response", retryAfter: nil)))
            }
            if json["ok"] as? Bool == true { return completion(.success(())) }
            let err = json["error"] as? String ?? "unknown_error"
            let needsUser: Set<String> = ["invalid_auth", "not_authed", "token_revoked", "token_expired",
                                          "account_inactive", "missing_scope", "channel_not_found",
                                          "not_in_channel", "is_archived"]
            completion(.failure(needsUser.contains(err) ? .needsUser("Slack: \(err)")
                                                        : .transient("Slack: \(err)", retryAfter: nil)))
        }.resume()
    }

    private func credentialsModDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Self.credentialsPath))?[.modificationDate] as? Date
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(queue), forKey: queueKey)
    }
}
