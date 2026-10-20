import Darwin
import Foundation
import XCTest

/// Installs the reporter before execution while leaving XCTest's lifecycle unchanged.
open class CaseReportingTestCase: XCTestCase {
    open override func invokeTest() {
        _ = CaseReporter.shared
        super.invokeTest()
    }
}

private struct CaseResult: Encodable {
    let case_id: String
    let status: String
    let evidence: String
}

private final class CaseReporter: NSObject, XCTestObservation {
    static let shared = CaseReporter()
    private let outputPath = ProcessInfo.processInfo.environment["MWEB_XCTEST_RESULTS_PATH"]
    private let issueLock = NSLock()
    private var issues: [ObjectIdentifier: [String]] = [:]

    private override init() {
        super.init()
        if let outputPath {
            guard !outputPath.isEmpty else { failReporting("MWEB_XCTEST_RESULTS_PATH must not be empty") }
            XCTestObservationCenter.shared.addTestObserver(self)
        }
    }

    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard testCase is CaseReportingTestCase else { return }
        issueLock.lock()
        issues[ObjectIdentifier(testCase), default: []].append(issue.compactDescription)
        issueLock.unlock()
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard testCase is CaseReportingTestCase, let outputPath else { return }
        guard let run = testCase.testRun, run.stopDate != nil else {
            failReporting("XCTest finished without a completed run: \(testCase.name)")
        }
        let pattern = #"test_([A-Z][A-Z0-9]*)_(\d{3})_\w+"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let fullName = testCase.name as NSString
        guard let match = expression.firstMatch(in: testCase.name, range: NSRange(location: 0, length: fullName.length)) else {
            failReporting("Test method has no explicit case ID: \(testCase.name)")
        }
        let caseID = fullName.substring(with: match.range(at: 1)) + "-" + fullName.substring(with: match.range(at: 2))
        let method = fullName.substring(with: match.range)
        let className = String(reflecting: type(of: testCase)).split(separator: ".").last!
        let selector = "\(className)/\(method)"
        let status = run.totalFailureCount > 0 ? "Failed" : run.hasBeenSkipped || run.skipCount > 0 ? "Skipped" : "Passed"
        issueLock.lock()
        let diagnostics = issues.removeValue(forKey: ObjectIdentifier(testCase)) ?? []
        issueLock.unlock()
        let detail = diagnostics.isEmpty ? "XCTest completed: \(status)" : diagnostics.joined(separator: "; ")
        let evidence = selector + ": " + detail.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(1800)
        do {
            var data = try JSONEncoder().encode(CaseResult(case_id: caseID, status: status, evidence: evidence))
            data.append(0x0A)
            append(data, to: outputPath)
        } catch {
            failReporting("Could not encode \(caseID): \(error)")
        }
    }

    private func append(_ data: Data, to path: String) {
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { failReporting("Could not open XCTest results: \(String(cString: strerror(errno)))") }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { failReporting("Could not lock XCTest results") }
        defer { flock(descriptor, LOCK_UN) }
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { failReporting("Could not append XCTest results") }
                offset += written
            }
        }
    }

    private func failReporting(_ message: String) -> Never {
        fputs("FAIL: XCTest case reporter: \(message)\n", stderr)
        fflush(stderr)
        exit(2)
    }
}
