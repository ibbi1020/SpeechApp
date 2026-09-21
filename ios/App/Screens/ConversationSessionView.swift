import SwiftUI

struct ConversationSessionView: View {
    var body: some View {
        ZStack {
            SpeechScreenBackground()
            Text("Conversation")
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
