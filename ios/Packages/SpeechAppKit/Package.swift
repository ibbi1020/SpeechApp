// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpeechAppKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SpeechAppKit", targets: ["SpeechAppKit"]),
    ],
    targets: [
        .target(
            name: "SpeechAppKit",
            path: "Sources/SpeechAppKit",
            resources: [
                .process("Resources"),
            ]
        ),
        // Mac-only command for testing the feedback system on audio clips.
        // Run from the repo root: eval/feedback/run.sh
        .executableTarget(
            name: "feedback-eval",
            dependencies: ["SpeechAppKit"],
            path: "Sources/FeedbackEval"
        ),
        .testTarget(
            name: "SpeechAppKitTests",
            dependencies: ["SpeechAppKit"],
            path: "Tests/SpeechAppKitTests",
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
