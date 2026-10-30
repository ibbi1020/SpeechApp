import Foundation
import SpeechAppKit

/// `GET /v1/tts/voices`. Falls back to the built-in roster when the call fails.
enum PartnerVoiceLoader {
    private struct Payload: Decodable {
        var voices: [Item]
    }

    private struct Item: Decodable {
        var voice_id: String
        var name: String?
    }

    /// Asks the mint server. The server calls xAI with the org key.
    static func fetch(base: URL, accountID: UUID) async -> [PartnerVoice] {
        var request = URLRequest(url: base.appending(path: "v1/tts/voices"))
        request.setValue("Bearer \(accountID.uuidString)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return PartnerVoice.catalog
        }
        let remote = payload.voices.map { item in
            PartnerVoice(
                id: item.voice_id,
                name: item.name ?? "",
                tone: ""
            )
        }
        return PartnerVoice.merging(remote: remote)
    }
}
