#!/usr/bin/env python3
from pathlib import Path
import re, sys

if len(sys.argv)!=2:
    raise SystemExit('usage: release_v525.py /path/to/雪梅优化.app')
app=Path(sys.argv[1])
main=app/'Contents/Resources/main.m'
engine=app/'Contents/Resources/engine.sh'
plist=app/'Contents/Info.plist'
if not main.exists() or not engine.exists() or not plist.exists():
    raise SystemExit('missing app sources')

m=main.read_text(encoding='utf-8')
e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.4";', 'static NSString * const XMCVersion = @"5.2.5";',1)
e=e.replace('VERSION="5.2.4"','VERSION="5.2.5"',1)

# v5.2.5 architecture: release asset is already compiled/signed/verified by GitHub Actions.
# Client verifies structure, bundle id, version consistency, signature and then atomically swaps.
# It MUST NOT recompile main.m on the user's Mac.
start=e.index('prepare_candidate() {')
end=e.index('\n}\n', start)+3
new_prepare=r'''prepare_candidate() {
  local source_app="$1" dest_app="$2"
  local stage="COPY"
  echo "PREPARE_STAGE=$stage" >> "$BUILD_LOG"
  /bin/rm -rf "$dest_app"
  /usr/bin/ditto "$source_app" "$dest_app" || { echo "PREPARE_ERROR=COPY_FAILED" >> "$BUILD_LOG"; return 21; }

  stage="VALIDATE_APP"; echo "PREPARE_STAGE=$stage" >> "$BUILD_LOG"
  validate_app "$dest_app" || { echo "PREPARE_ERROR=APP_VALIDATION_FAILED" >> "$BUILD_LOG"; return 22; }

  stage="VERSION_CHECK"; echo "PREPARE_STAGE=$stage" >> "$BUILD_LOG"
  validate_version_consistency "$dest_app" || { echo "PREPARE_ERROR=VERSION_CHECK_FAILED" >> "$BUILD_LOG"; return 23; }

  stage="SIGNATURE_CHECK"; echo "PREPARE_STAGE=$stage" >> "$BUILD_LOG"
  /usr/bin/codesign --verify --deep --strict "$dest_app" >> "$BUILD_LOG" 2>&1 || { echo "PREPARE_ERROR=SIGNATURE_VERIFY_FAILED" >> "$BUILD_LOG"; return 24; }

  stage="EXECUTABLE_CHECK"; echo "PREPARE_STAGE=$stage" >> "$BUILD_LOG"
  [[ -x "$dest_app/Contents/MacOS/XueMeiCleanerNative" ]] || { echo "PREPARE_ERROR=EXECUTABLE_MISSING" >> "$BUILD_LOG"; return 25; }

  /usr/bin/xattr -cr "$dest_app" 2>/dev/null || true
  echo "PREPARE_STAGE=READY" >> "$BUILD_LOG"
  return 0
}'''
e=e[:start]+new_prepare+e[end:]

# Preserve detailed failure reason instead of collapsing everything into PREPARE_FAILED.
old='''  if ! prepare_candidate "$candidate" "$pending"; then
    /bin/rm -rf "$pending"
    echo "STATUS=PREPARE_FAILED"
    return 1
  fi'''
new='''  : > "$BUILD_LOG"
  prepare_candidate "$candidate" "$pending"
  local prep_rc=$?
  if (( prep_rc != 0 )); then
    local prep_error="$(/usr/bin/awk -F= '$1=="PREPARE_ERROR"{v=$2} END{print v}' "$BUILD_LOG")"
    [[ -n "$prep_error" ]] || prep_error="PREPARE_FAILED"
    echo "STATUS=$prep_error"
    echo "PREPARE_RC=$prep_rc"
    echo "BUILD_LOG=$BUILD_LOG"
    /bin/rm -rf "$pending"
    return "$prep_rc"
  fi'''
if old not in e:
    raise SystemExit('schedule_apply prepare block not found')
e=e.replace(old,new,1)

# Never let compile_native_app erase diagnostics if it is used by legacy/local paths.
e=e.replace('"$src" \\\n    -o "$out" >"$BUILD_LOG" 2>&1 || return 1', '"$src" \\\n    -o "$out" >>"$BUILD_LOG" 2>&1 || return 1',1)

# Explicit architecture marker.
marker='UPDATE_ARCHITECTURE="PREBUILT_VERIFIED_ATOMIC_V1"\n'
version_anchor='VERSION="5.2.5"\n'
if 'UPDATE_ARCHITECTURE=' not in e:
    e=e.replace(version_anchor,version_anchor+marker,1)

for token in ['PREBUILT_VERIFIED_ATOMIC_V1','SIGNATURE_VERIFY_FAILED','PREPARE_RC']:
    if token not in e: raise SystemExit('missing '+token)
main.write_text(m,encoding='utf-8')
engine.write_text(e,encoding='utf-8')
