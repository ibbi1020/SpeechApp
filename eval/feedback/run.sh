#!/bin/bash
# Run the feedback eval CLI from anywhere. Paths in the CLI are relative to the repo root.
#   eval/feedback/run.sh rules
#   eval/feedback/run.sh generate
#   eval/feedback/run.sh run            # transcribe (cached) + score
#   eval/feedback/run.sh run --refresh  # re-send every clip to Grok
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
swift run --quiet --package-path ios/Packages/SpeechAppKit feedback-eval "$@"
