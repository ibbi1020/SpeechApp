import Foundation
import Testing
@testable import SpeechAppKit

struct SpeechToTextConnectTests {
    @Test("a live Grok connection stays on Grok")
    func staysOnGrok() async throws {
        let route = try await SpeechToTextConnect.route(relayConfigured: true) {}
        #expect(route == .grok)
    }

    @Test("a missing server uses the phone and does not call Grok")
    func missingServer() async throws {
        var called = false
        let route = try await SpeechToTextConnect.route(relayConfigured: false) {
            called = true
        }
        #expect(route == .onDevice)
        #expect(called == false)
    }

    @Test(
        "a server or model that cannot be reached uses the phone",
        arguments: [
            GrokTranscriptionError.relayNotConfigured,
            GrokTranscriptionError.timedOut,
            GrokTranscriptionError.failed("model unreachable"),
        ]
    )
    func grokUnreachable(_ error: GrokTranscriptionError) async throws {
        let route = try await SpeechToTextConnect.route(relayConfigured: true) {
            throw error
        }
        #expect(route == .onDevice)
    }

    @Test("a refused connection uses the phone")
    func refusedConnection() async throws {
        let route = try await SpeechToTextConnect.route(relayConfigured: true) {
            throw URLError(.cannotConnectToHost)
        }
        #expect(route == .onDevice)
    }

    @Test("leaving during connect does not start the phone")
    func cancellation() async {
        await #expect(throws: CancellationError.self) {
            _ = try await SpeechToTextConnect.route(relayConfigured: true) {
                throw CancellationError()
            }
        }
    }
}
