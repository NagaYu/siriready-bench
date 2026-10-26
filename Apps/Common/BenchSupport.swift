// Bench instrumentation shared by the four reference apps (SiriReady Bench, Phase 2).
//
// - EgressRecorder intercepts every URLSession request made by the app, records the host and
//   answers locally, so nothing is ever sent off the machine while still letting the harness
//   observe whether an intent *tried* to leave the device (F8).
// - EffectLog records what an intent actually persisted (the side effect the harness checks).
// - DebugProbeIntent hands both logs to the UI-testing harness and resets the store.
//   It is DEBUG-only and not discoverable, following the test-only intent pattern of WWDC26 #295.
import AppIntents
import Foundation

final class EgressRecorder: URLProtocol {
    static func install() {
        URLProtocol.registerClass(EgressRecorder.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        BenchLog.append(egress: request.url?.host ?? "unknown")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct BenchEffect: Codable, Sendable {
    var intent: String
    var target: String?
    var params: [String: String]
}

/// File-backed so the log survives if the system runs an intent in a fresh app process.
enum BenchLog {
    private struct Snapshot: Codable {
        var effects: [BenchEffect] = []
        var egress: [String] = []
    }

    private static let lock = NSLock()
    private static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("siriready-bench-log.json")
    }

    private static func load() -> Snapshot {
        (try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))) ?? Snapshot()
    }

    private static func save(_ s: Snapshot) {
        try? JSONEncoder().encode(s).write(to: url, options: .atomic)
    }

    static func append(effect: BenchEffect) {
        lock.lock(); defer { lock.unlock() }
        var s = load(); s.effects.append(effect); save(s)
    }

    static func append(egress host: String) {
        lock.lock(); defer { lock.unlock() }
        var s = load(); s.egress.append(host); save(s)
    }

    /// Returns the log as JSON and clears it.
    static func drain() -> String {
        lock.lock(); defer { lock.unlock() }
        let s = load()
        save(Snapshot())
        return String(decoding: (try? JSONEncoder().encode(s)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

/// Launch arguments `-siriready-screen <name> -siriready-ids a,b,c` select what the root view shows.
enum LaunchScreen {
    static var screen: String? { UserDefaults.standard.string(forKey: "siriready-screen") }
    static var ids: [String] {
        (UserDefaults.standard.string(forKey: "siriready-ids") ?? "").split(separator: ",").map(String.init)
    }
}

#if DEBUG
struct DebugProbeIntent: AppIntent {
    static let title: LocalizedStringResource = "SiriReady Debug Probe"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let log = BenchLog.drain()
        await BenchReset.resetStore()
        return .result(value: log)
    }
}
#endif
