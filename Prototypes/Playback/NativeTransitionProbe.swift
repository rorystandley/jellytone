import AVFoundation
import Foundation

struct Metrics: Codable {
    let durationSeconds: Double
    let expectedDurationSeconds: Double
    let durationErrorSamples: Int
    let longestDigitalSilenceSamples: Int
    let sampleRate: Int
    let preloadedBytes: [Int]
    let crossfadeFrames: Int
}

struct ProbeResult: Codable {
    let engine: String
    let source: String
    let hardCut: Metrics
    let linearCrossfade250ms: Metrics
}

enum ProbeError: Error {
    case invalidArguments
    case unsupportedFormat
    case renderFailed(AVAudioEngineManualRenderingStatus)
}

@main enum NativeTransitionProbe {
    static let overlapFrames: AVAudioFrameCount = 12_000
    static let silenceThreshold: Float = 2.0 / 32_768.0

    static func materialize(_ argument: String, index: Int, directory: URL) async throws -> (URL, Int) {
        guard let url = URL(string: argument) else { throw ProbeError.invalidArguments }
        if url.isFileURL {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            return (url, size?.intValue ?? 0)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let output = directory.appendingPathComponent("remote-\(index).wav")
        try data.write(to: output, options: .atomic)
        return (output, data.count)
    }

    static func read(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate == 48_000, format.channelCount == 2,
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        else { throw ProbeError.unsupportedFormat }
        try file.read(into: buffer)
        return buffer
    }

    static func copy(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let result = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength),
              let sourceChannels = source.floatChannelData,
              let resultChannels = result.floatChannelData
        else { throw ProbeError.unsupportedFormat }
        result.frameLength = source.frameLength
        for channel in 0..<Int(source.format.channelCount) {
            resultChannels[channel].update(from: sourceChannels[channel], count: Int(source.frameLength))
        }
        return result
    }

    static func applyFades(first: AVAudioPCMBuffer, second: AVAudioPCMBuffer) throws {
        guard overlapFrames <= first.frameLength, overlapFrames <= second.frameLength,
              let firstChannels = first.floatChannelData, let secondChannels = second.floatChannelData
        else { throw ProbeError.unsupportedFormat }
        let firstStart = Int(first.frameLength - overlapFrames)
        for channel in 0..<Int(first.format.channelCount) {
            for offset in 0..<Int(overlapFrames) {
                let progress = Float(offset) / Float(overlapFrames - 1)
                firstChannels[channel][firstStart + offset] *= 1 - progress
                secondChannels[channel][offset] *= progress
            }
        }
    }

    static func render(first sourceA: AVAudioPCMBuffer, second sourceB: AVAudioPCMBuffer,
                       crossfade: Bool, preloadedBytes: [Int]) throws -> Metrics {
        let first = try copy(sourceA)
        let second = try copy(sourceB)
        if crossfade { try applyFades(first: first, second: second) }

        let engine = AVAudioEngine()
        let playerA = AVAudioPlayerNode()
        engine.attach(playerA)
        engine.connect(playerA, to: engine.mainMixerNode, format: first.format)
        var playerB: AVAudioPlayerNode?
        if crossfade {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: first.format)
            playerB = node
        }
        try engine.enableManualRenderingMode(.offline, format: first.format, maximumFrameCount: 4_096)
        try engine.start()

        let expectedFrames = Int(first.frameLength + second.frameLength - (crossfade ? overlapFrames : 0))
        if let playerB {
            playerA.scheduleBuffer(first)
            let start = AVAudioTime(sampleTime: AVAudioFramePosition(first.frameLength - overlapFrames),
                                    atRate: first.format.sampleRate)
            playerB.scheduleBuffer(second, at: start)
            playerA.play()
            playerB.play()
        } else {
            playerA.scheduleBuffer(first)
            playerA.scheduleBuffer(second)
            playerA.play()
        }

        guard let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount)
        else { throw ProbeError.unsupportedFormat }
        var rendered = 0
        var currentSilence = 0
        var longestSilence = 0
        while rendered < expectedFrames {
            let requested = AVAudioFrameCount(min(Int(engine.manualRenderingMaximumFrameCount), expectedFrames - rendered))
            let status = try engine.renderOffline(requested, to: output)
            guard status == .success, let channels = output.floatChannelData else {
                throw ProbeError.renderFailed(status)
            }
            for frame in 0..<Int(output.frameLength) {
                var magnitude: Float = 0
                for channel in 0..<Int(output.format.channelCount) {
                    magnitude = max(magnitude, abs(channels[channel][frame]))
                }
                currentSilence = magnitude <= silenceThreshold ? currentSilence + 1 : 0
                longestSilence = max(longestSilence, currentSilence)
            }
            rendered += Int(output.frameLength)
        }
        engine.stop()
        let expectedSeconds = Double(expectedFrames) / first.format.sampleRate
        return Metrics(durationSeconds: Double(rendered) / first.format.sampleRate,
                       expectedDurationSeconds: expectedSeconds,
                       durationErrorSamples: abs(rendered - expectedFrames),
                       longestDigitalSilenceSamples: longestSilence,
                       sampleRate: Int(first.format.sampleRate),
                       preloadedBytes: preloadedBytes,
                       crossfadeFrames: crossfade ? Int(overlapFrames) : 0)
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 4 else { throw ProbeError.invalidArguments }
        let source = CommandLine.arguments[1]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-transition-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstMaterialized = try await materialize(CommandLine.arguments[2], index: 0, directory: directory)
        let secondMaterialized = try await materialize(CommandLine.arguments[3], index: 1, directory: directory)
        let first = try read(firstMaterialized.0)
        let second = try read(secondMaterialized.0)
        let bytes = [firstMaterialized.1, secondMaterialized.1]
        let result = ProbeResult(engine: "AVAudioEngine offline manual rendering", source: source,
                                 hardCut: try render(first: first, second: second, crossfade: false,
                                                     preloadedBytes: bytes),
                                 linearCrossfade250ms: try render(first: first, second: second, crossfade: true,
                                                                  preloadedBytes: bytes))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(result))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
