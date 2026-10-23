#if os(macOS)
import Foundation

let usage = """
feedback-eval: test Monologue feedback on audio clips without the phone.

Run from the repo root (eval/feedback/run.sh does this for you):

  rules                       Check the marker rules against eval/feedback/rules.json.
  generate                    Make spoken clips from eval/feedback/clips.json with the Mac voice.
  transcribe [--refresh]      Send clips to Grok through the local relay. Saves <clip>.grok.json.
  score                       Compare markers with labels. Writes eval/feedback/out/report.md.
  run [--refresh]             transcribe, then score.

Options:
  --dir <path>        Clip folder (default eval/feedback/clips). Subfolders are included.
  --specs <path>      Clip scripts for `generate` (default eval/feedback/clips.json).
  --report <path>     Where `score` writes markdown (default eval/feedback/out/report.md).
  --relay <url>       Relay base (default http://127.0.0.1:8787, same server the app uses).
  --speed <n>         Send audio n times faster than real time (default 4).
  --tolerance <sec>   How far apart a marker and a label can start and still match (default 0.5).
  --only <text>       Only clips whose name contains this text.
  --hints             Reading: send passage words to Grok as hints, like the live caret stream.
                      The app's feedback stream does not, so the default is off.
"""

struct Options {
    var command = ""
    var dir = "eval/feedback/clips"
    var specs = "eval/feedback/clips.json"
    var rules = "eval/feedback/rules.json"
    var report = "eval/feedback/out/report.md"
    var relay = "http://127.0.0.1:8787"
    var speed = 4.0
    var tolerance = 0.5
    var refresh = false
    var hints = false
    var only: String?

    init(_ args: [String]) throws {
        var rest = args[...]
        command = rest.popFirst() ?? ""
        while let flag = rest.popFirst() {
            func value() throws -> String {
                guard let next = rest.popFirst() else { throw CLIError.usage("Missing value for \(flag)") }
                return next
            }
            switch flag {
            case "--dir": dir = try value()
            case "--specs": specs = try value()
            case "--report": report = try value()
            case "--relay": relay = try value()
            case "--speed": speed = Double(try value()) ?? speed
            case "--tolerance": tolerance = Double(try value()) ?? tolerance
            case "--only": only = try value()
            case "--refresh": refresh = true
            case "--hints": hints = true
            default: throw CLIError.usage("Unknown option \(flag)")
            }
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case failed(String)

    var description: String {
        switch self {
        case .usage(let message), .failed(let message): message
        }
    }
}

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    switch options.command {
    case "rules":
        try RulesCommand.run(options)
    case "generate":
        try GenerateCommand.run(options)
    case "transcribe":
        try await TranscribeCommand.run(options)
    case "score":
        try ScoreCommand.run(options)
    case "run":
        try await TranscribeCommand.run(options)
        try ScoreCommand.run(options)
    default:
        print(usage)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
#else
print("feedback-eval runs on macOS only.")
#endif
