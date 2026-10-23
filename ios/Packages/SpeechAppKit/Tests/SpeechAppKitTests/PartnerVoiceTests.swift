import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Partner voice")
struct PartnerVoiceTests {
    @Test("the default is Sirius, and Eve stays selectable")
    func defaultIsLively() {
        #expect(PartnerVoice.defaultID == "sirius")
        #expect(PartnerVoice.named("eve") != nil)
        #expect(PartnerVoice.named("sirius")?.tone.localizedCaseInsensitiveContains("playful") == true)
        let ids = PartnerVoice.catalog.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("junk ids fall back to the default")
    func canonicalRejectsJunk() {
        #expect(PartnerVoice.canonical("  Sirius ") == "sirius")
        #expect(PartnerVoice.canonical("") == "sirius")
        #expect(PartnerVoice.canonical("Eve!") == "sirius")
        #expect(PartnerVoice.canonical("eve") == "eve")
    }

    @Test("a saved choice survives, and a bad save does not")
    func preferenceRoundTrip() {
        let suite = UserDefaults(suiteName: "PartnerVoiceTests.\(UUID().uuidString)")!
        let preference = VoicePreference(defaults: suite)
        #expect(preference.voiceID == "sirius")
        preference.voiceID = "Ara"
        #expect(preference.voiceID == "ara")
        preference.voiceID = "not a voice"
        #expect(preference.voiceID == "sirius")
    }

    @Test("a remote roster keeps known tones and drops duplicates")
    func mergeRemote() {
        let merged = PartnerVoice.merging(remote: [
            PartnerVoice(id: "eve", name: "Eve", tone: ""),
            PartnerVoice(id: "Eve", name: "Eve", tone: ""),
            PartnerVoice(id: "nova", name: "Nova", tone: "New"),
        ])
        #expect(merged.map(\.id) == ["eve", "nova"])
        #expect(merged[0].tone.localizedCaseInsensitiveContains("British"))
        #expect(merged[1].tone == "New")
    }
}
