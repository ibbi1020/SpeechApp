import Foundation

public struct VisibleFeedbackChoice: Equatable, Sendable {
    public var marker: ReviewMarker?
    public var inside: Set<ReviewMarker.ID>

    public init(marker: ReviewMarker?, inside: Set<ReviewMarker.ID>) {
        self.marker = marker
        self.inside = inside
    }
}

public enum VisibleFeedback {
    /// How far either side of a marker the playhead can be and still show its note.
    public static let vicinity: TimeInterval = 2

    public static func marker(
        at time: TimeInterval,
        among markers: [ReviewMarker],
        previouslyInside: Set<ReviewMarker.ID>,
        showing: ReviewMarker.ID?,
        preferred: ReviewMarker.ID? = nil
    ) -> VisibleFeedbackChoice {
        let readable = markers.filter { marker in
            !marker.note.isEmpty && contains(time, marker)
        }
        let inside = Set(readable.map(\.id))

        if let preferred, let chosen = readable.first(where: { $0.id == preferred }) {
            return VisibleFeedbackChoice(marker: chosen, inside: inside)
        }

        let entered = readable.filter { !previouslyInside.contains($0.id) }
        if let newest = latest(entered) {
            return VisibleFeedbackChoice(marker: newest, inside: inside)
        }

        if let showing, let kept = readable.first(where: { $0.id == showing }) {
            return VisibleFeedbackChoice(marker: kept, inside: inside)
        }

        return VisibleFeedbackChoice(marker: latest(readable), inside: inside)
    }

    private static func contains(_ time: TimeInterval, _ marker: ReviewMarker) -> Bool {
        time >= marker.start - vicinity && time <= marker.start + vicinity
    }

    /// The marker play would reach last. Equal starts keep the earlier one in the list.
    private static func latest(_ markers: [ReviewMarker]) -> ReviewMarker? {
        markers.max { $0.start < $1.start }
    }
}
