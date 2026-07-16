import Foundation
import CryptoKit
import XCTest
@testable import DeviceProof

final class ProofLogicTests: XCTestCase {
    private func expectation(for data: Data, id: String = "aac") -> ProofMediaEntry {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ProofMediaEntry(bytes: data.count, file: "synthetic.m4a", id: id, sha256: digest)
    }

    func testRedactorRemovesURLAddressTokenAndDeviceIdentifier() {
        let identifier = ["9C5370A3", "A31B", "5E28", "A4D6", "84DC49CD76DC"].joined(separator: "-")
        let sensitive = "http://" + ["192", "168", "1", "4"].joined(separator: ".") + ":8080/file token=secret \(identifier)"
        let result = ProofRedactor.scrub(sensitive)
        XCTAssertFalse(result.contains("192.168"))
        XCTAssertFalse(result.contains("secret"))
        XCTAssertFalse(result.contains("9C5370"))
    }

    func testSensitiveFactKeysFailClosed() {
        let result = ProofRedactor.sanitizedFacts(["serverAddress": "private", "codec": "flac"])
        XCTAssertEqual(result["serverAddress"], "<redacted>")
        XCTAssertEqual(result["codec"], "flac")
    }

    func testEventStoreWritesDeterministicSchemaWithoutSensitiveValue() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProofEventStore(fileURL: url)
        let privateURL = "http://" + ["10", "0", "0", "2"].joined(separator: ".") + "/private"
        store.append(category: "network", action: "probe", result: "pass", facts: ["url": privateURL])
        let line = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        XCTAssertTrue(line.contains("\"schemaVersion\":1"))
        XCTAssertFalse(line.contains("10.0.0.2"))
    }

    func testEventStoreResetRemovesEarlierRunAndRestartsSequence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProofEventStore(fileURL: url)
        store.append(category: "run", action: "old", result: "pass")
        store.reset()
        store.append(category: "run", action: "new", result: "pass")

        let lines = try String(decoding: Data(contentsOf: url), as: UTF8.self).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("\"sequence\":1"))
        XCTAssertTrue(lines[0].contains("\"action\":\"new\""))
        XCTAssertFalse(lines[0].contains("old"))
    }

    func testEventStoreRestoresRunAndSequenceAcrossRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = ProofEventStore(fileURL: url, runIdentifier: "synthetic-run")
        first.append(category: "run", action: "first", result: "pass")
        let restored = ProofEventStore(fileURL: url)
        restored.append(category: "run", action: "second", result: "pass")

        let events = try String(decoding: Data(contentsOf: url), as: UTF8.self)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(ProofEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(events.map(\.sequence), [1, 2])
        XCTAssertEqual(Set(events.map(\.runIdentifier)), Set(["synthetic-run"]))
    }

    func testDelayedCallbackFromPreviousRunIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProofEventStore(fileURL: url, runIdentifier: "old-run")
        store.append(category: "download", action: "old", result: "pass", expectedRunIdentifier: "old-run")
        store.reset()
        store.append(category: "download", action: "stale", result: "pass", expectedRunIdentifier: "old-run")
        store.append(category: "run", action: "current", result: "pass")

        let events = try String(decoding: Data(contentsOf: url), as: UTF8.self)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(ProofEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].sequence, 1)
        XCTAssertEqual(events[0].action, "current")
        XCTAssertNotEqual(events[0].runIdentifier, "old-run")
    }

    func testDownloadPayloadRejectsPartialAndCorruptBytes() throws {
        let valid = Data("deterministic-audio".utf8)
        let expected = expectation(for: valid)
        XCTAssertThrowsError(try DownloadPayloadValidator.validate(
            data: Data(valid.dropLast()), statusCode: 200, contentType: "audio/mp4", expected: expected
        )) { XCTAssertEqual($0 as? DownloadProofError, .byteCountMismatch) }

        var corrupt = valid
        corrupt[corrupt.startIndex] ^= 0x01
        XCTAssertThrowsError(try DownloadPayloadValidator.validate(
            data: corrupt, statusCode: 200, contentType: "audio/mp4", expected: expected
        )) { XCTAssertEqual($0 as? DownloadProofError, .digestMismatch) }
    }

    func testDownloadPayloadRejectsWrongDigestStatusAndContentType() {
        let valid = Data("deterministic-audio".utf8)
        let wrongDigest = ProofMediaEntry(bytes: valid.count, file: "synthetic.m4a", id: "aac", sha256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try DownloadPayloadValidator.validate(
            data: valid, statusCode: 200, contentType: "audio/mp4", expected: wrongDigest
        )) { XCTAssertEqual($0 as? DownloadProofError, .digestMismatch) }
        XCTAssertThrowsError(try DownloadPayloadValidator.validate(
            data: valid, statusCode: 404, contentType: "audio/mp4", expected: expectation(for: valid)
        )) { XCTAssertEqual($0 as? DownloadProofError, .unexpectedStatus) }
        XCTAssertThrowsError(try DownloadPayloadValidator.validate(
            data: valid, statusCode: 200, contentType: "text/html", expected: expectation(for: valid)
        )) { XCTAssertEqual($0 as? DownloadProofError, .unexpectedContentType) }
    }

    func testConcurrentMediaUseDistinctStagingPaths() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("device-proof-downloads")
        let destination = directory.appendingPathComponent("final.m4a")
        let aac = expectation(for: Data("aac".utf8), id: "aac")
        let flac = expectation(for: Data("flac".utf8), id: "flac")

        let aacURL = DownloadFileInstaller.stagingURL(destination: destination, expected: aac)
        let flacURL = DownloadFileInstaller.stagingURL(destination: destination, expected: flac)

        XCTAssertEqual(aacURL.lastPathComponent, ".download-aac-staging")
        XCTAssertEqual(flacURL.lastPathComponent, ".download-flac-staging")
        XCTAssertNotEqual(aacURL, flacURL)
    }

    func testRestorationBookkeepingRoundTripsManifestIdentityAndPhase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadProofStateStore(fileURL: directory.appendingPathComponent("state.json"))
        let media = expectation(for: Data("audio".utf8), id: "flac")
        let state = DownloadProofState(
            sessionIdentifier: "org.example.phase0.background",
            runIdentifier: "synthetic-run",
            tasks: [DownloadProofTask(taskIdentifier: 7, media: media, phase: .scheduled)],
            acknowledgementCount: 0
        )
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        try store.updatePhase(.installed, taskIdentifier: 7)
        XCTAssertEqual(try store.task(7).phase, .installed)
        store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testDuplicateAcknowledgementIsRejectedExactlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadProofStateStore(fileURL: directory.appendingPathComponent("state.json"))
        try store.save(DownloadProofState(
            sessionIdentifier: "org.example.phase0.background",
            runIdentifier: "synthetic-run",
            tasks: [DownloadProofTask(taskIdentifier: 1, media: expectation(for: Data("audio".utf8)), phase: .probed)],
            acknowledgementCount: 0
        ))
        XCTAssertTrue(try store.recordAcknowledgement())
        XCTAssertFalse(try store.recordAcknowledgement())
        try store.updatePhase(.probed, taskIdentifier: 1)
        XCTAssertEqual(try store.load().acknowledgementCount, 2)
        XCTAssertEqual(try store.task(1).phase, .acknowledged)
    }

    func testCancellationResumeRemainsExplicitOperatorOnlyBehavior() {
        XCTAssertEqual(DownloadProofPolicy.cancellationResumeStatus, "operator_device_procedure_required")
    }
}
