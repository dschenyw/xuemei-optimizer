#!/usr/bin/env python3
from pathlib import Path
import re,sys
# release-trigger: cleanup execution bridge v2
if len(sys.argv)!=2: raise SystemExit('usage: release_v528.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.7";','static NSString * const XMCVersion = @"5.2.8";',1)
e=e.replace('VERSION="5.2.7"','VERSION="5.2.8"',1)
if 'XMCVersion = @"5.2.8"' not in m or 'VERSION="5.2.8"' not in e: raise SystemExit('version patch failed')

# UI fixes.
old='深度扫描 Downloads / Desktop / Documents / Public；重复安装包、已安装残留、明确旧版和损坏包均列为“确定可清理”。普通资料、源码、备份和当前版本继续保护。'
new='深度扫描 Downloads / Desktop / Documents / Public。重复安装包、已安装残留、明确旧版本和损坏包均列为“确定可清理”。\\n普通资料、项目源码、备份和当前版本自动保护，不进入自动清理范围。'
m=m.replace(old,new,1)
m=m.replace('@"建议清理"','@"确定可清理"')
m=m.replace('建议 %ld','确定可清理 %ld')
m=m.replace('建议 %@','确定可清理 %@')
if '@"重复安装包"' not in m:
    m=m.replace('@"确定可清理", @"失效/损坏"','@"确定可清理", @"重复安装包", @"旧版本", @"失效/损坏"',1)
if 'XMC_FILTER_DUPLICATE_V1' not in m:
    m=m.replace('static NSString * const XMCVersion = @"5.2.8";', 'static NSString * const XMCVersion = @"5.2.8";\nstatic NSString * const XMCFilterMarker = @"XMC_FILTER_DUPLICATE_V1";',1)

# Cleanup execution bridge: after a smart scan, high-confidence installer candidates
# must be consumed by the cleanup command instead of merely displayed.
# Candidate rows are TSV; first field is recommendation and final field is path.
bridge=r'''
# XMC_DEFINITE_CLEANUP_EXEC_V2
xmc_cleanup_definite_installers() {
  local result="${FULL_SCAN_RESULT:-$HOME/Library/Application Support/雪梅清理/full-scan-results.tsv}"
  [[ -f "$result" ]] || { echo "INSTALLER_REMOVED_COUNT=0"; echo "INSTALLER_REMOVED_KB=0"; return 0; }
  local trash="$HOME/.Trash" count=0 bytes=0 line rec path size base dst n
  /bin/mkdir -p "$trash"
  while IFS=$'\t' read -r rec _rest; do
    line="$rec"$'\t'"$_rest"
    [[ "$rec" == "可清理" || "$rec" == "确定可清理" || "$rec" == "建议清理" ]] || continue
    path="${line##*$'\t'}"
    [[ -f "$path" ]] || continue
    case "$path" in
      "$HOME/Downloads/"*|"$HOME/Desktop/"*|"$HOME/Documents/"*|"$HOME/Public/"*) ;;
      *) continue ;;
    esac
    case "$path" in
      *"/CXM_Backups/"*|*"/Backups/"*|*"/Library/"*|*"/.codex/"*|*"/.ssh/"*) continue ;;
    esac
    size=$(/usr/bin/stat -f %z "$path" 2>/dev/null || echo 0)
    base="${path:t}"; dst="$trash/$base"; n=1
    while [[ -e "$dst" ]]; do dst="$trash/${base:r} ($n).${base:e}"; ((n++)); done
    if /bin/mv "$path" "$dst" 2>/dev/null; then ((count++)); ((bytes+=size)); fi
  done < "$result"
  echo "INSTALLER_REMOVED_COUNT=$count"
  echo "INSTALLER_REMOVED_KB=$((bytes/1024))"
}
'''
if 'XMC_DEFINITE_CLEANUP_EXEC_V2' not in e:
    e += '\n'+bridge+'\n'

# Hook into known cleanup command output path. Prefer an existing zero-count placeholder.
hooked=False
for needle in ['echo "INSTALLER_REMOVED_COUNT=0"','echo "INSTALLER_CLEANED_COUNT=0"','echo "PACKAGE_REMOVED_COUNT=0"']:
    if needle in e:
        e=e.replace(needle,'xmc_cleanup_definite_installers',1); hooked=True; break
# If no placeholder exists, invoke immediately before the smart-clean completion marker when present.
if not hooked:
    for needle in ['echo "STATUS=SUCCESS"','echo "STATUS=OK"']:
        idx=e.find(needle)
        if idx>=0:
            e=e[:idx]+'xmc_cleanup_definite_installers\n  '+e[idx:]; hooked=True; break
if not hooked: raise SystemExit('cleanup execution hook not found')

if 'PATH_PINNED_RESTART_V1' not in e: raise SystemExit('missing path-pinned updater')
if 'PREBUILT_VERIFIED_ATOMIC_V1' not in e: raise SystemExit('missing prebuilt updater')
main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
