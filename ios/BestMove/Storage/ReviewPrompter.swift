import Foundation

/// Decides when to show the system rating prompt.
///
/// Timing follows what app-growth practice has converged on: ask at the peak of a success, within
/// a screen of it, not at launch and not after something went wrong.
/// - The success moment is a scan that was recognised without any correction, a couple of seconds
///   after the engine has shown a solid best move (see `AnalysisView`).
/// - The first request comes after the second such clean scan, which can be in the first session:
///   most people decide on a utility within a day.
/// - No request in a session where a recognition failed, for samples, or while the person is
///   already exploring moves.
/// - At most once per app version and `minimumDaysBetweenRequests` apart, so the system's own
///   limit (three prompts per 365 days) isn't spent within days.
/// Only the system prompt is used; custom "Do you like the app?" pre-prompts break App Store
/// guideline 5.6.1.
final class ReviewPrompter {
    static let requiredCleanScans = 2
    static let minimumDaysBetweenRequests = 14.0

    private let defaults: UserDefaults
    private var sessionHadProblem = false
    /// Off for screenshot and demo runs.
    private let isEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        isEnabled = args.contains("-reviewPromptTest") || !args.contains { $0.hasPrefix("-demo") }
        #else
        isEnabled = true
        #endif
    }

    private var cleanScans: Int {
        get { defaults.integer(forKey: Keys.cleanScans) }
        set { defaults.set(newValue, forKey: Keys.cleanScans) }
    }
    private var cleanScansAtLastRequest: Int {
        get { defaults.integer(forKey: Keys.cleanScansAtLastRequest) }
        set { defaults.set(newValue, forKey: Keys.cleanScansAtLastRequest) }
    }
    private var lastRequestVersion: String? {
        get { defaults.string(forKey: Keys.lastRequestVersion) }
        set { defaults.set(newValue, forKey: Keys.lastRequestVersion) }
    }
    private var lastRequestDate: Date? {
        get { defaults.object(forKey: Keys.lastRequestDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastRequestDate) }
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Something went wrong (e.g. the board couldn't be read): no request for the rest of this session.
    func recordProblem() {
        sessionHadProblem = true
    }

    /// A clean scan reached a solid engine result. Returns whether this is the moment to ask.
    func recordCleanScanSuccess() -> Bool {
        cleanScans += 1
        guard isEnabled, !sessionHadProblem, cleanScans >= Self.requiredCleanScans,
              lastRequestVersion != Self.currentVersion else { return false }
        if let lastRequestDate {
            guard Date().timeIntervalSince(lastRequestDate) >= Self.minimumDaysBetweenRequests * 86_400,
                  cleanScans - cleanScansAtLastRequest >= Self.requiredCleanScans else { return false }
        }
        return true
    }

    /// The prompt was requested (the system may still decide not to show it).
    func didRequestReview() {
        lastRequestVersion = Self.currentVersion
        lastRequestDate = Date()
        cleanScansAtLastRequest = cleanScans
    }

    private enum Keys {
        static let cleanScans = "review.cleanScans"
        static let cleanScansAtLastRequest = "review.cleanScansAtLastRequest"
        static let lastRequestVersion = "review.lastRequestVersion"
        static let lastRequestDate = "review.lastRequestDate"
    }
}
