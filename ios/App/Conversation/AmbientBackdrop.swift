import CoreMotion
import SwiftUI
import SpeechAppKit

/// The place picture behind a conversation. A small tilt shows the cropped edge.
struct AmbientBackdrop: View {
    var place: AmbientPlace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shift = AmbientParallax.Shift.centered
    /// Picture on top. Starts clear so the first one can fade in.
    @State private var front: AmbientPlace
    @State private var frontOpacity: Double = 0
    /// Picture still showing underneath while the next one fades in.
    @State private var back: AmbientPlace?
    @State private var backOpacity: Double = 1
    @State private var fadeGeneration = 0

    init(place: AmbientPlace) {
        self.place = place
        _front = State(initialValue: place)
    }

    private var fade: Animation {
        .easeInOut(duration: reduceMotion ? 0.2 : 0.5)
    }

    private var listens: Bool {
        front != .off && !reduceMotion
    }

    private var scrimOpacity: Double {
        let frontCover = front == .off ? 0 : frontOpacity
        let backCover = back == nil ? 0 : backOpacity
        return max(frontCover, backCover)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let back, let image = uiImage(for: back) {
                    picture(image, in: geo.size)
                        .opacity(backOpacity)
                }
                if let image = uiImage(for: front) {
                    picture(image, in: geo.size)
                        .opacity(frontOpacity)
                }
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.28), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .clear, location: 0.62),
                        .init(color: .black.opacity(0.42), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(scrimOpacity)
                .allowsHitTesting(false)
                if front != .off || back != nil {
                    let topInset = geo.safeAreaInsets.top
                    let belowNotch = (topInset > 20 ? topInset : 59) + 18
                    ConversationEdgeBlur(edge: .top, maxRadius: 2.8, height: belowNotch)
                        .opacity(scrimOpacity)
                    ConversationEdgeBlur(
                        edge: .bottom,
                        maxRadius: 3.6,
                        height: geo.size.height * 0.15
                    )
                    .opacity(scrimOpacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            guard front != .off, frontOpacity == 0 else { return }
            withAnimation(fade) { frontOpacity = 1 }
        }
        .onChange(of: place) { _, newPlace in
            fade(to: newPlace)
        }
        .task(id: listens) {
            await followMotion()
        }
    }

    private func uiImage(for place: AmbientPlace) -> UIImage? {
        place.imageName.flatMap { UIImage(named: $0) }
    }

    private func picture(_ image: UIImage, in size: CGSize) -> some View {
        let zoom = reduceMotion ? 1 : AmbientParallax.zoom(
            viewWidth: size.width,
            viewHeight: size.height,
            imageWidth: image.size.width,
            imageHeight: image.size.height
        )
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(zoom)
            .rotationEffect(.degrees(listens ? shift.degrees : 0))
            .offset(x: listens ? shift.x : 0, y: listens ? shift.y : 0)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    /// The new picture fades in over the one already on screen. Off fades both out.
    private func fade(to newPlace: AmbientPlace) {
        guard newPlace != front else { return }
        fadeGeneration += 1
        let generation = fadeGeneration

        if newPlace == .off {
            withAnimation(fade) {
                frontOpacity = 0
                backOpacity = 0
            } completion: {
                guard generation == fadeGeneration else { return }
                front = .off
                back = nil
                backOpacity = 1
            }
            return
        }

        // Leave the picture already on screen underneath the one fading in.
        if back == nil, front != .off, frontOpacity > 0 {
            back = front
        }
        front = newPlace
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            frontOpacity = 0
            if back != nil { backOpacity = 1 }
        }
        Task { @MainActor in
            guard generation == fadeGeneration else { return }
            withAnimation(fade) { frontOpacity = 1 } completion: {
                guard generation == fadeGeneration else { return }
                back = nil
                backOpacity = 1
            }
        }
    }

    /// Centers the picture on the pose where listening starts, then slides from there.
    private func followMotion() async {
        guard listens else {
            shift = .centered
            return
        }

        let manager = CMMotionManager()
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0

        let (stream, continuation) = AsyncStream.makeStream(
            of: AmbientParallax.Pose.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { motion, _ in
            guard let motion else { return }
            continuation.yield(
                AmbientParallax.Pose(
                    roll: motion.attitude.roll,
                    pitch: motion.attitude.pitch,
                    yaw: motion.attitude.yaw
                )
            )
        }
        defer { manager.stopDeviceMotionUpdates() }

        var reference: AmbientParallax.Pose?
        var smoothed = AmbientParallax.Shift.centered
        await withTaskCancellationHandler {
            for await pose in stream {
                if reference == nil {
                    reference = pose
                    continue
                }
                guard let reference else { continue }
                let target = AmbientParallax.shift(from: reference, to: pose)
                smoothed = AmbientParallax.smooth(previous: smoothed, target: target)
                shift = smoothed
            }
        } onCancel: {
            continuation.finish()
        }
    }
}
