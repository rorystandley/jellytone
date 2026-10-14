import Darwin
import Foundation
import XCTest

struct LargeLibraryScaleMeasurement: Codable, Equatable {
    let operation: String
    let elapsedMilliseconds: Double
    let peakResidentBytes: UInt64
    let elapsedCeilingMilliseconds: Double
    let peakResidentCeilingBytes: UInt64
}

struct LargeLibraryScaleEvidence: Codable, Equatable {
    let schemaVersion: Int
    let generatorVersion: Int
    let seed: UInt64
    let contentSHA256: String
    let artistCount: Int
    let albumCount: Int
    let trackCount: Int
    let measurements: [LargeLibraryScaleMeasurement]
}

/// Captures bounded scale evidence without persisting machine-specific results
/// in the repository. Process RSS is sampled on a private serial queue and each
/// operation is emitted as sorted-key JSON in the test log and an attachment.
final class LargeLibraryScaleEvidenceRecorder {
    private(set) var measurements: [LargeLibraryScaleMeasurement] = []

    func measure<Value>(
        operation: String,
        elapsedCeilingMilliseconds: Double,
        peakResidentCeilingBytes: UInt64,
        _ work: () async throws -> Value
    ) async rethrows -> Value {
        let sampler = ProcessResidentMemorySampler()
        let start = DispatchTime.now().uptimeNanoseconds
        sampler.start()
        defer {
            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
            measurements.append(
                LargeLibraryScaleMeasurement(
                    operation: operation,
                    elapsedMilliseconds: Double(elapsedNanoseconds) / 1_000_000,
                    peakResidentBytes: sampler.stop(),
                    elapsedCeilingMilliseconds: elapsedCeilingMilliseconds,
                    peakResidentCeilingBytes: peakResidentCeilingBytes
                )
            )
        }
        return try await work()
    }

    func assertMeasurementsWithinCeilings(file: StaticString = #filePath, line: UInt = #line) {
        for measurement in measurements {
            XCTAssertLessThanOrEqual(
                measurement.elapsedMilliseconds,
                measurement.elapsedCeilingMilliseconds,
                "\(measurement.operation) exceeded its deliberately generous elapsed-time ceiling",
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                measurement.peakResidentBytes,
                measurement.peakResidentCeilingBytes,
                "\(measurement.operation) exceeded its deliberately generous process-memory ceiling",
                file: file,
                line: line
            )
        }
    }

    func attach(
        generatorVersion: Int,
        seed: UInt64,
        contentSHA256: String,
        artistCount: Int,
        albumCount: Int,
        trackCount: Int,
        to testCase: XCTestCase
    ) throws {
        let evidence = LargeLibraryScaleEvidence(
            schemaVersion: 1,
            generatorVersion: generatorVersion,
            seed: seed,
            contentSHA256: contentSHA256,
            artistCount: artistCount,
            albumCount: albumCount,
            trackCount: trackCount,
            measurements: measurements
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(evidence)
        let json = String(decoding: data, as: UTF8.self)
        print("LARGE_LIBRARY_SCALE_EVIDENCE \(json)")

        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "large-library-scale-evidence.json"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}

private final class ProcessResidentMemorySampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.example.jellytone.scale-memory-sampler")
    private var timer: DispatchSourceTimer?
    private var peakResidentBytes: UInt64 = 0

    func start() {
        queue.sync {
            peakResidentBytes = Self.currentResidentBytes()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(2))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.peakResidentBytes = max(self.peakResidentBytes, Self.currentResidentBytes())
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() -> UInt64 {
        queue.sync {
            peakResidentBytes = max(peakResidentBytes, Self.currentResidentBytes())
            timer?.cancel()
            timer = nil
            return peakResidentBytes
        }
    }

    private static func currentResidentBytes() -> UInt64 {
        var information = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(information.resident_size)
    }
}
