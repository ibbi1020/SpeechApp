import CoreGraphics
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Hum level")
struct HumLevelTests {
    /// One tap buffer is about 20ms. 250 buffers is five seconds, 400 is eight.
    private static let buffersPerSecond = 50

    @Test("a hum held past five seconds stays up")
    func heldHum() {
        var level = HumLevel()
        level.playbackRMS = 0.48
        var atFiveSeconds = 0.0
        var atEightSeconds = 0.0
        for step in 1 ... (8 * Self.buffersPerSecond) {
            let value = level.observe(micRMS: 0.14)
            if step == 5 * Self.buffersPerSecond { atFiveSeconds = value }
            atEightSeconds = value
        }
        #expect(atFiveSeconds > 0.5)
        #expect(abs(atEightSeconds - atFiveSeconds) < 0.05)
    }

    @Test("a bleed no louder than the picture cap stays down")
    func speakerLeak() {
        var level = HumLevel()
        level.playbackRMS = 0.64
        var value = 0.0
        for _ in 0 ..< (8 * Self.buffersPerSecond) {
            value = level.observe(micRMS: HumLevel.pictureLeak)
        }
        #expect(value == 0)
    }

    /// The played tone is near full scale, about 0.64 RMS. Five percent of that
    /// is 0.03, which is the loudness the field calls a raised voice. Speech is
    /// louder than that, so speech still moved the drawing and a hum did not.
    @Test("a hum lifts the field while the tone is playing")
    func humDuringTone() {
        var level = HumLevel()
        level.playbackRMS = 0.64
        var smoothed = 0.0
        for _ in 0 ..< Self.buffersPerSecond {
            smoothed = level.observe(micRMS: 0.03)
        }
        #expect(smoothed > 0.5)
        let size = CGSize(width: 390, height: 700)
        #expect(Self.litDots(voice: smoothed, size: size) > Self.litDots(voice: 0, size: size))
    }

    private static func litDots(voice: Double, size: CGSize) -> Int {
        let driven = DitherHorizon.level(voice: voice, reduceMotion: false)
        let cell = DitherHorizon.cell(forWidth: size.width)
        let field = DitherHorizon.field(size: size, level: driven, gain: DitherHorizon.humGain)
        let columns = Int(ceil(size.width / cell))
        let rows = Int(ceil(size.height / cell))
        var count = 0
        for row in 0 ..< rows {
            for column in 0 ..< columns where DitherHorizon.dotSide(
                column: column,
                row: row,
                cell: cell,
                field: field
            ) > 0 {
                count += 1
            }
        }
        return count
    }

    @Test("before the tone, a voice still lifts the field")
    func beforeTone() {
        var level = HumLevel()
        let value = level.observe(micRMS: 0.08)
        #expect(value > 0.3)
    }
}
