# Orator — TestFlight CI

GitHub Actions + Fastlane pipeline that builds the native SwiftUI app (XcodeGen project in `ios/`) and uploads a Release IPA to TestFlight with an **App Store Connect API key** (no Apple ID / 2FA).

- Workflow: [`.github/workflows/ios-testflight.yml`](../.github/workflows/ios-testflight.yml) (runner `macos-26`, Xcode latest-stable; iOS 26 target needs Xcode 26)
- Fastlane: [`ios/fastlane/`](../ios/fastlane/) — lane `testflight_release`

## Identifiers

| | Local dev (project.yml) | TestFlight / CI (Release only) |
|---|---|---|
| Team | `45SVH8S72R` (Personal Team) | `Q2Z32YFFGP` (Muhammad Yahya Qureshi) |
| Bundle id | `com.speechapp.prototype.format1` | `com.speechapp.orator` |
| Signing | Automatic | Manual, Apple Distribution + App Store profile `Orator App Store CI` |

CI rewrites only the `SpeechApp` target's Release config after `xcodegen generate`, so Xcode runs on a personal device are unchanged. Do not pass `PROVISIONING_PROFILE_SPECIFIER` in global `xcargs` (SPM products would break).

## Triggers

- `workflow_dispatch` (inputs: `build_number`, `changelog`, `skip_upload`) — only once this file is on the default branch
- `push` to `ci/testflight` touching `ios/**` or the workflow

If no App Store Connect app record exists for the bundle id yet, the lane still archives + signs, then skips the upload with a warning.

## Build number

`BUILD_NUMBER` = `run_number + 3` (override with the `build_number` input). Fastlane writes it to `CFBundleVersion` in `ios/App/Info.plist`.

## Secrets (Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | ASC API key id |
| `APP_STORE_CONNECT_ISSUER_ID` | ASC issuer id |
| `APP_STORE_CONNECT_API_KEY` | `.p8` contents (PEM or base64) |
| `APPLE_TEAM_ID` | `Q2Z32YFFGP` |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | base64 Apple Distribution `.p12` (3DES/SHA1 export so macOS can import it) |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | `.p12` password |
| `IOS_APPSTORE_PROVISIONING_PROFILE_BASE64` | base64 App Store profile `Orator App Store CI` for `com.speechapp.orator` |

Optional env overrides: `IOS_APP_IDENTIFIER`, `IOS_APPSTORE_PROVISIONING_PROFILE_SPECIFIER`.

## Provider keys (no server)

On this branch the app calls the providers directly; `server/` is not used.

- Reading / Monologue: `wss://api.x.ai/v1/stt` (model `grok-voice-transcribe-2.0`, 16 kHz PCM, interim results, smart turn), `Authorization: Bearer <XAI_API_KEY>`. Same query `server/stt-relay.mjs` built.
- Conversation: xAI only. The app opens `wss://api.x.ai/v1/realtime?model=grok-voice-latest` (Grok Voice speech-to-speech) directly with `XAI_API_KEY`, binary 24 kHz PCM16 mic frames in, PCM deltas out, server VAD with `create_response:false` so the session still sends `response.create` with the persona/stance/cue instructions per turn. The socket and session are set up during the 3-2-1 countdown. No ephemeral token (it would add a round trip and the key ships in the app anyway). The old mint server's budget rules (20 counted starts per month, 1 live session, 3 starts per 10 min) are kept on the device. No WebRTC dependency.

The key comes from the repo secret `XAI_API_KEY`. CI runs `ios/scripts/generate_provider_secrets.py`, which writes `ios/App/Generated/ProviderSecrets.generated.swift` (gitignored) with the key XOR-masked by a random per-build mask; `ProviderKeys` decodes it at runtime. This is light obfuscation only: the key can be recovered from the IPA, so use a key with spend limits and rotate it if the build leaks. The IPA is not uploaded as a workflow artifact.

A local Xcode run without the generated file builds fine; Reading/Monologue then show "isn't set up in this build" and Conversation uses the fake partner.

Add `[skip upload]` to a commit message pushed to `ci/testflight` to build and sign without uploading.
