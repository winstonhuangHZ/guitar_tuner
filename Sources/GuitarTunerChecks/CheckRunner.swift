import Foundation

/// Very small assertion recorder so the DSP can be verified without XCTest.
///
/// Xcode ships the testing frameworks, the Command Line Tools do not — and the pitch
/// detector has to be checkable on a machine that only has the CLT installed.
final class CheckRunner {
    struct Failure {
        let group: String
        let message: String
    }

    private(set) var totalChecks = 0
    private(set) var failures: [Failure] = []

    private var currentGroup = "general"
    private var groupOrder: [String] = []
    private var groupChecks: [String: Int] = [:]
    private var groupFailures: [String: Int] = [:]

    func group(_ name: String) {
        currentGroup = name
        if !groupOrder.contains(name) {
            groupOrder.append(name)
        }
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        totalChecks += 1
        groupChecks[currentGroup, default: 0] += 1
        guard !condition else { return }
        failures.append(Failure(group: currentGroup, message: message()))
        groupFailures[currentGroup, default: 0] += 1
    }

    // MARK: - Convenience assertions

    func equal<T: Equatable>(_ value: T, _ expected: T, _ label: @autoclosure () -> String) {
        expect(value == expected, "\(label()): expected \(expected), got \(value)")
    }

    func near(_ value: Double, _ expected: Double, accuracy: Double, _ label: @autoclosure () -> String) {
        expect(
            abs(value - expected) <= accuracy,
            "\(label()): expected \(expected) ±\(accuracy), got \(value)"
        )
    }

    func isNil<T>(_ value: T?, _ label: @autoclosure () -> String) {
        expect(value == nil, "\(label()): expected nil, got \(String(describing: value))")
    }

    func isNotNil<T>(_ value: T?, _ label: @autoclosure () -> String) {
        expect(value != nil, "\(label()): expected a value, got nil")
    }

    func less<T: Comparable>(_ lhs: T, _ rhs: T, _ label: @autoclosure () -> String) {
        expect(lhs < rhs, "\(label()): expected \(lhs) < \(rhs)")
    }

    func lessOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, _ label: @autoclosure () -> String) {
        expect(lhs <= rhs, "\(label()): expected \(lhs) ≤ \(rhs)")
    }

    func greater<T: Comparable>(_ lhs: T, _ rhs: T, _ label: @autoclosure () -> String) {
        expect(lhs > rhs, "\(label()): expected \(lhs) > \(rhs)")
    }

    // MARK: - Reporting

    /// Prints a per-group summary and returns true when everything passed.
    @discardableResult
    func report() -> Bool {
        print("")
        for group in groupOrder {
            let checks = groupChecks[group] ?? 0
            let failed = groupFailures[group] ?? 0
            let mark = failed == 0 ? "✓" : "✗"
            let suffix = failed == 0 ? "" : "  (\(failed) failed)"
            print("\(mark) \(group.padding(toLength: max(28, group.count), withPad: " ", startingAt: 0)) \(checks) checks\(suffix)")
        }

        print("")
        if failures.isEmpty {
            print("All \(totalChecks) checks passed.")
            return true
        }

        for failure in failures {
            print("FAIL [\(failure.group)] \(failure.message)")
        }
        print("")
        print("\(failures.count) of \(totalChecks) checks failed.")
        return false
    }
}
