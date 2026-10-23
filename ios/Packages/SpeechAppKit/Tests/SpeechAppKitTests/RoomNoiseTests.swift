import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Room noise")
struct RoomNoiseTests {
    @Test("a quiet room is about minus forty, and silence stays finite")
    func decibels() {
        let quiet = RoomNoise.decibels(rms: 0.01)
        #expect(abs(quiet - (-40)) < 0.05)
        let silence = RoomNoise.decibels(rms: 0)
        #expect(silence.isFinite)
        #expect(silence < RoomNoise.warn)
    }

    @Test("green holds below the line, yellow through the middle, then orange")
    func color() {
        #expect(RoomNoise.band(decibels: -40) == .green)
        #expect(RoomNoise.band(decibels: -36) == .yellow)
        #expect(RoomNoise.band(decibels: -30) == .yellow)
        #expect(RoomNoise.band(decibels: -24) == .yellow)
        #expect(RoomNoise.band(decibels: -18) == .orange(0.5))
        #expect(RoomNoise.band(decibels: -12) == .orange(1))
        #expect(RoomNoise.band(decibels: -6) == .orange(1))
    }

    @Test("the button waits two decibels before it calls the room quiet again")
    func hysteresis() {
        #expect(RoomNoise.warning(decibels: -37, wasWarning: false) == false)
        #expect(RoomNoise.warning(decibels: -36, wasWarning: false))
        #expect(RoomNoise.warning(decibels: -37, wasWarning: true))
        #expect(RoomNoise.warning(decibels: -37.9, wasWarning: true))
        #expect(RoomNoise.warning(decibels: -38, wasWarning: true) == false)
    }

    @Test("the first fraction of a second is not a verdict")
    func settle() {
        var reading = RoomReading()
        reading.observe(rms: 1, at: 0.2)
        feed(&reading, rms: 0.01, from: 0.4, through: 1.35)
        #expect(reading.ready == false)
        #expect(reading.decibels == nil)

        feed(&reading, rms: 0.01, from: 1.4, through: 1.4)
        #expect(reading.ready)
        let level = reading.decibels ?? 0
        #expect(level < -39)
        #expect(reading.warning == false)
    }

    @Test("a loud second after the pop warns, and a quieter second clears it")
    func verdictThenClear() {
        var reading = RoomReading()
        feed(&reading, rms: 0.1, from: 0, through: 1.4)
        #expect(reading.ready)
        #expect(reading.warning)
        let loud = reading.decibels ?? 0
        #expect(abs(loud - (-20)) < 0.5)

        feed(&reading, rms: Self.rms(decibels: -37), from: 1.45, through: 2.5)
        #expect(reading.warning)

        feed(&reading, rms: 0.01, from: 2.55, through: 3.6)
        #expect(reading.warning == false)
        #expect((reading.decibels ?? 0) < RoomNoise.clear)
    }

    private static func rms(decibels: Double) -> Double {
        pow(10, decibels / 20)
    }

    private func feed(_ reading: inout RoomReading, rms: Double, from start: Double, through end: Double) {
        var time = start
        while time <= end + 0.000_1 {
            reading.observe(rms: rms, at: time)
            time += 0.05
        }
    }
}
