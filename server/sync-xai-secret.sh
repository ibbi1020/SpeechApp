#!/bin/bash
# Copy XAI_API_KEY from server/.env into a gitignored app plist for direct
# Format 2 testing (no mint). Never prints the key.

set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT/.env"
OUT="$ROOT/../ios/App/XAISecrets.plist"

if [[ ! -f "$ENV_FILE" ]]; then
  exit 0
fi

key="$(grep -E '^XAI_API_KEY=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r')"
if [[ -z "${key:-}" ]]; then
  exit 0
fi

# Escape XML special characters in the key value.
escaped="$(
  printf '%s' "$key" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
)"

cat >"$OUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>XAI_API_KEY</key>
	<string>${escaped}</string>
</dict>
</plist>
EOF

exit 0
