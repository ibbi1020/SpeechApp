import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Take recorder")
struct TakeRecorderTests {
    /// The conversation mic delivers buffers off the main actor. Those samples
    /// have to be in the file by the time recording stops.
    @Test func appendOffTheMainActorIsInTheFile() throws {
        let recorder = TakeRecorder()
        try recorder.start()
        recorder.setWriting(false)
        let tenth = AudioChunk(
            samples: [Float](repeating: 0.2, count: 4_800),
            sampleRate: 48_000,
            hostTime: 0
        )

        DispatchQueue.global(qos: .userInitiated).sync {
            recorder.append(tenth)
        }
        if let ignored = recorder.stop() {
            try? FileManager.default.removeItem(at: ignored)
        }
        #expect(recorder.writtenSeconds == 0)

        try recorder.start()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            recorder.append(tenth)
            recorder.append(tenth)
            done.signal()
        }
        done.wait()
        let url = try #require(recorder.stop())
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(abs(recorder.writtenSeconds - 0.2) < 0.0001)
        let output = try AudioProbe.read(url)
        #expect(abs(output.duration - 0.2) < 0.02)
    }
}
