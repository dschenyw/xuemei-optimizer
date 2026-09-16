#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"

PLIST_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/app/Info.plist")"
SOURCE_VER="$(grep -E 'XMCVersion = @\"[^\"]+\"' "$ROOT/src/main.m" | head -1 | sed -E 's/.*XMCVersion = @\"([^\"]+)\".*/\1/')"
ENGINE_VER="$(grep -E '^VERSION=\"[^\"]+\"' "$ROOT/src/engine.sh" | head -1 | sed -E 's/^VERSION=\"([^\"]+)\"/\1/')"

[[ "$PLIST_VER" == "$SOURCE_VER" && "$PLIST_VER" == "$ENGINE_VER" ]] || {
  print -u2 "Version mismatch: plist=$PLIST_VER source=$SOURCE_VER engine=$ENGINE_VER"
  exit 1
}

if grep -RInE '/Users/[^/ ]+' "$ROOT/src" "$ROOT/app/Info.plist"; then
  print -u2 "Hard-coded /Users path found"
  exit 1
fi

# This is intentionally conservative: it looks for common credential assignment shapes,
# not words such as "token" or "secret" used by the app's protection rules.
if grep -RInE "(API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?TOKEN|PASSWORD|SECRET)[[:space:]]*[:=][[:space:]]*\"?[A-Za-z0-9_./+=-]{8,}" "$ROOT/src"; then
  print -u2 "Possible embedded credential found"
  exit 1
fi

print "Source checks passed (version $PLIST_VER)"
