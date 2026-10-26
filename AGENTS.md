# Agent notes

## Checking an iOS build

`ios/SpeechApp.xcodeproj` lists source files by hand. It is not a folder that picks up new files on its own. A new Swift file under `ios/App` is not compiled until it is in the SpeechApp target's Compile Sources: a `PBXBuildFile`, a `PBXFileReference`, the group, and the SpeechApp `PBXSourcesBuildPhase`.

Xcode keeps the project it already loaded. If Xcode is open, adding a file by editing `project.pbxproj` on disk does not put that file in the next Xcode build. Xcode still compiles the other Swift files from disk, so calls to a type in the new file fail with `Cannot find 'TypeName' in scope`. A command-line `xcodebuild` reads the project from disk and can succeed at the same time. After editing `project.pbxproj`, reload the project in Xcode before trusting an Xcode build. Until then, put new types in a file that is already in the target.

Do not decide a build passed from a pipe. This command reports the wrong result:

```
xcodebuild -project ios/SpeechApp.xcodeproj -scheme SpeechApp -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGNING_ALLOWED=NO build 2>&1 | rg "error:|BUILD " | head
```

Without `set -o pipefail`, the shell's exit code is `head`'s, not `xcodebuild`'s. `-quiet` also hides `** BUILD SUCCEEDED **`. Empty filtered output and exit code 0 is not a successful build.

Run the build without a pipe and read its own exit code:

```
xcodebuild -project ios/SpeechApp.xcodeproj -scheme SpeechApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Success is exit code 0 and a line `** BUILD SUCCEEDED **`.
