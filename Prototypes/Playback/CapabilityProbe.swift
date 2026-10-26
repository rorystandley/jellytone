import AVFoundation
import Foundation

struct Result: Codable {
    let url: String
    let transport: String
    let playable: Bool
    let durationSeconds: Double?
    let audioTrackCount: Int
    let error: String?
}

@main enum Probe {
    static func main() async {
        var results: [Result] = []
        for argument in CommandLine.arguments.dropFirst() {
            guard let url = URL(string: argument) else { continue }
            do {
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                results.append(Result(url: url.lastPathComponent,
                                      transport: url.isFileURL ? "local" : "remote-loopback",
                                      playable: playable,
                                      durationSeconds: duration.isNumeric ? CMTimeGetSeconds(duration) : nil,
                                      audioTrackCount: tracks.count, error: nil))
            } catch {
                results.append(Result(url: url.lastPathComponent,
                                      transport: url.isFileURL ? "local" : "remote-loopback",
                                      playable: false, durationSeconds: nil, audioTrackCount: 0,
                                      error: String(describing: error)))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try! encoder.encode(results))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
