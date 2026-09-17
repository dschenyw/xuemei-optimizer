#!/usr/bin/env python3
from pathlib import Path
import sys
if len(sys.argv)!=2: raise SystemExit('usage: release_v529.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.8";','static NSString * const XMCVersion = @"5.2.9";',1)
e=e.replace('VERSION="5.2.8"','VERSION="5.2.9"',1)
if 'XMCVersion = @"5.2.9"' not in m or 'VERSION="5.2.9"' not in e: raise SystemExit('version patch failed')

# Safe historical .app backup analyzer/cleaner. Only explicit backup naming patterns,
# only when a non-backup sibling exists, never the currently running bundle.
block=r'''
# XMC_APP_BACKUP_CLEANER_V1
xmc_scan_app_backups() {
  local out="$HOME/Library/Application Support/雪梅清理/app-backup-candidates.tsv"
  : > "$out"
  local root p name stem live size mtime
  for root in /Applications "$HOME/Applications"; do
    [[ -d "$root" ]] || continue
    for p in "$root"/*.backup.*.app(N) "$root"/*_backup_*.app(N) "$root"/*.bak.*.app(N); do
      [[ -d "$p" ]] || continue
      [[ "$p" == "$APP_ROOT" ]] && continue
      name="${p:t}"
      stem="${name%%.backup.*}.app"
      [[ "$stem" == "$name" ]] && stem="${name%%_backup_*}.app"
      live="$root/$stem"
      [[ -d "$live" ]] || continue
      size=$(/usr/bin/du -sk "$p" 2>/dev/null | /usr/bin/awk '{print $1+0}')
      mtime=$(/usr/bin/stat -f %m "$p" 2>/dev/null || echo 0)
      print -r -- "确定可清理\t历史APP备份\t${size}\t${mtime}\t${p}" >> "$out"
    done
  done
  local c kb
  c=$(/usr/bin/awk 'END{print NR+0}' "$out")
  kb=$(/usr/bin/awk -F '\t' '{s+=$3}END{print s+0}' "$out")
  echo "APP_BACKUP_COUNT=$c"
  echo "APP_BACKUP_KB=$kb"
  echo "APP_BACKUP_RESULT=$out"
}

xmc_clean_app_backups() {
  local f="$HOME/Library/Application Support/雪梅清理/app-backup-candidates.tsv"
  [[ -f "$f" ]] || xmc_scan_app_backups >/dev/null
  local trash="$HOME/.Trash" p kb total=0 count=0 base dst n
  /bin/mkdir -p "$trash"
  while IFS=$'\t' read -r _ _ kb _ p; do
    [[ -d "$p" ]] || continue
    [[ "$p" == "$APP_ROOT" ]] && continue
    case "$p" in /Applications/*.app|"$HOME/Applications/"*.app) ;; *) continue;; esac
    base="${p:t}"; dst="$trash/$base"; n=1
    while [[ -e "$dst" ]]; do dst="$trash/${base:r} ($n).app"; ((n++)); done
    if /bin/mv "$p" "$dst" 2>/dev/null; then ((count++)); ((total+=kb)); fi
  done < "$f"
  echo "APP_BACKUP_REMOVED_COUNT=$count"
  echo "APP_BACKUP_REMOVED_KB=$total"
}
'''
if 'XMC_APP_BACKUP_CLEANER_V1' not in e: e += '\n'+block+'\n'

# Keep update architecture markers mandatory.
for marker in ['PREBUILT_VERIFIED_ATOMIC_V1','PATH_PINNED_RESTART_V1']:
    if marker not in e: raise SystemExit('missing '+marker)
main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
