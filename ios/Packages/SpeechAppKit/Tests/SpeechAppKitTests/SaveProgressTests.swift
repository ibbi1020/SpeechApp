import Foundation
import Testing
@testable import SpeechAppKit

struct SaveProgressTests {
    @Test("a short take spends most of the ring on cleaning")
    func shortTakeWeightsCleaning() {
        let progress = SaveProgress(durationSeconds: 20, willClean: true, includesTranscription: false)

        #expect(progress.slice(.cleaning) > progress.slice(.encoding))
        #expect(progress.slice(.cleaning) > progress.slice(.reading))
        #expect(progress.slice(.cleaning) > 0.5)
    }

    @Test("a take past three minutes skips cleaning and spends the ring on encoding")
    func longTakeSkipsCleaning() {
        #expect(SaveProgress.needsCleaning(durationSeconds: 180, runsOnSimulator: false))
        #expect(SaveProgress.needsCleaning(durationSeconds: 181, runsOnSimulator: false) == false)
        #expect(SaveProgress.needsCleaning(durationSeconds: 20, runsOnSimulator: true) == false)

        let progress = SaveProgress(
            durationSeconds: 200,
            willClean: SaveProgress.needsCleaning(durationSeconds: 200, runsOnSimulator: false),
            includesTranscription: false
        )

        #expect(progress.slice(.cleaning) == 0)
        #expect(progress.slice(.encoding) > progress.slice(.reading))
        #expect(progress.slice(.encoding) > 0.5)
    }

    @Test("catching the last words is a short prefix, not most of the ring")
    func transcriptionIsAShortPrefix() {
        let progress = SaveProgress(durationSeconds: 120, willClean: true, includesTranscription: true)

        #expect(progress.slice(.catchingWords) > 0)
        #expect(progress.slice(.catchingWords) < 0.25)
        #expect(progress.slice(.catchingWords) < progress.slice(.cleaning))
    }

    @Test("skipping a step does not jump the ring")
    func skippingDoesNotJump() {
        let readingDone = SaveProgress(durationSeconds: 20, willClean: true, includesTranscription: false)
            .updating(.reading, fraction: 1)
        let before = readingDone.displayedFraction(ready: false)

        let skipped = readingDone.updating(.encoding, fraction: 0)

        #expect(skipped.slice(.cleaning) == 0)
        #expect(skipped.displayedFraction(ready: false) == before)
    }

    @Test("the ring stays under full until the take is ready")
    func staysUnderFullUntilReady() {
        let finished = SaveProgress(durationSeconds: 20, willClean: true, includesTranscription: false)
            .updating(.writing, fraction: 1)

        #expect(finished.displayedFraction(ready: false) < 1)
        #expect(finished.displayedFraction(ready: false) <= SaveProgress.waitingCap)
        #expect(finished.displayedFraction(ready: true) == 1)
    }

    @Test("a stalled step does not move the ring")
    func stallDoesNotAdvance() {
        let moved = SaveProgress(durationSeconds: 20, willClean: true, includesTranscription: false)
            .updating(.cleaning, fraction: 0.4)
        let stalled = moved.updating(.cleaning, fraction: 0.4)
        let earlier = stalled.updating(.cleaning, fraction: 0.1)

        let held = moved.displayedFraction(ready: false)
        #expect(held < 1)
        #expect(stalled.displayedFraction(ready: false) == held)
        #expect(earlier.displayedFraction(ready: false) == held)
        #expect(SaveProgress.showsSlowLine(unchangedFor: 7) == false)
        #expect(SaveProgress.showsSlowLine(unchangedFor: 8) == true)
        #expect(SaveProgress.showsSlowLine(unchangedFor: 30) == true)
        #expect(SaveProgress.showsStillSaving(unchangedFor: 19) == false)
        #expect(SaveProgress.showsStillSaving(unchangedFor: 20) == true)
    }
}
