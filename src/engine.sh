#!/bin/zsh
set -u

VERSION="4.1.5"
BUNDLE_ID="com.cxm.xuemeicleaner"
APP_ROOT="${XMC_APP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

STATE_DIR="$HOME/Library/Application Support/雪梅清理"
REPORT_DIR="$HOME/Desktop/雪梅优化报告"
BACKUP_DIR="$STATE_DIR/Backups"
SOURCE_FILE="$STATE_DIR/update-source.txt"
LOG_FILE="$STATE_DIR/engine.log"
BUILD_LOG="$STATE_DIR/native-update-build.log"

mkdir -p "$STATE_DIR" "$REPORT_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

human_kb() {
  /usr/bin/awk -v kb="${1:-0}" 'BEGIN{
    if(kb>=1048576) printf "%.2f GB",kb/1048576;
    else if(kb>=1024) printf "%.2f MB",kb/1024;
    else printf "%d KB",kb;
  }'
}

dir_kb() {
  [[ -e "$1" ]] || { echo 0; return; }
  /usr/bin/du -sk "$1" 2>/dev/null | /usr/bin/awk '{print $1+0}'
}

protected_cache() {
  local n="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$n" in
    *google*|*chrome*|*tiktok*|*chatgpt*|*openai*|*clash*|*docker*|*iota*|*bittensor*|*macrocosmos*|*wallet*)
      return 0 ;;
  esac
  return 1
}

safe_cache_kb() {
  local root="$HOME/Library/Caches" total=0 item kb
  [[ -d "$root" ]] || { echo 0; return; }
  for item in "$root"/*; do
    [[ -e "$item" ]] || continue
    protected_cache "$item" && continue
    kb="$(dir_kb "$item")"
    total=$((total + kb))
  done
  echo "$total"
}

scan_cmd() {
  local cache logs xcode dev total ts report totaldisk freedisk
  cache="$(safe_cache_kb)"
  logs="$(dir_kb "$HOME/Library/Logs")"
  xcode="$(dir_kb "$HOME/Library/Developer/Xcode/DerivedData")"
  dev=0
  for p in "$HOME/.npm/_cacache" "$HOME/Library/Caches/pip" "$HOME/Library/Caches/uv" "$HOME/Library/Caches/Homebrew"; do
    dev=$((dev + $(dir_kb "$p")))
  done
  total=$((cache+logs+xcode+dev))
  totaldisk="$(/bin/df -k / | /usr/bin/tail -1 | /usr/bin/awk '{print $2+0}')"
  freedisk="$(/bin/df -k / | /usr/bin/tail -1 | /usr/bin/awk '{print $4+0}')"

  ts="$(date '+%Y%m%d_%H%M%S')"
  report="$REPORT_DIR/扫描_$ts.txt"

  {
    echo "============================================================"
    echo "雪梅优化 v$VERSION"
    echo "扫描时间：$(date)"
    echo "============================================================"
    echo
    echo "【磁盘】"
    /bin/df -h / | /usr/bin/tail -1
    echo
    echo "【可安全清理】"
    printf "%-28s %12s\n" "应用缓存（保护项已排除）" "$(human_kb "$cache")"
    printf "%-28s %12s\n" "用户日志" "$(human_kb "$logs")"
    printf "%-28s %12s\n" "Xcode DerivedData" "$(human_kb "$xcode")"
    printf "%-28s %12s\n" "开发工具缓存" "$(human_kb "$dev")"
    echo "------------------------------------------------------------"
    echo "预计可安全清理：$(human_kb "$total")"
    echo
    echo "【保护中心】"
    echo "  ✓ ~/.ssh"
    echo "  ✓ ~/.codex"
    echo "  ✓ ~/Library/Keychains"
    echo "  ✓ Chrome / TikTok 登录资料"
    echo "  ✓ ChatGPT / OpenAI 配置"
    echo "  ✓ Clash 配置"
    echo "  ✓ Docker 数据"
    echo "  ✓ IOTA / SN9 / Bittensor 相关项"
    echo "  ✓ 钱包 / 密钥 / API Key"
    echo "  ✓ 项目源码"
    echo "  ✓ Desktop / Documents / Downloads / Pictures / Movies / Music 个人文件"
    echo
    echo "报告：$report"
  } > "$report"

  echo "DISK_TOTAL_KB=$totaldisk"
  echo "DISK_FREE_KB=$freedisk"
  echo "CACHE_KB=$cache"
  echo "LOGS_KB=$logs"
  echo "XCODE_KB=$xcode"
  echo "DEV_KB=$dev"
  echo "TOTAL_SAFE_KB=$total"
  echo "REPORT=$report"
}

clean_contents() {
  local p="$1"
  [[ -d "$p" ]] || return 0
  /usr/bin/find "$p" -mindepth 1 -maxdepth 1 -exec /bin/rm -rf {} + 2>/dev/null || true
}

clean_safe_cache() {
  local root="$HOME/Library/Caches" item
  [[ -d "$root" ]] || return 0
  for item in "$root"/*; do
    [[ -e "$item" ]] || continue
    protected_cache "$item" && continue
    /bin/rm -rf "$item" 2>/dev/null || true
  done
}

category_kb() {
  local key="$1" total=0
  case "$key" in
    cache)
      safe_cache_kb
      ;;
    logs)
      dir_kb "$HOME/Library/Logs"
      ;;
    xcode)
      dir_kb "$HOME/Library/Developer/Xcode/DerivedData"
      ;;
    dev)
      for p in "$HOME/.npm/_cacache" "$HOME/Library/Caches/pip" "$HOME/Library/Caches/uv" "$HOME/Library/Caches/Homebrew"; do
        total=$((total + $(dir_kb "$p")))
      done
      echo "$total"
      ;;
    *)
      echo 0
      ;;
  esac
}

clean_cmd() {
  local cats="${1:-}"
  local disk_before disk_after disk_delta
  local selected_before=0 selected_after=0 cleaned=0
  local cache_before=0 cache_after=0
  local logs_before=0 logs_after=0
  local xcode_before=0 xcode_after=0
  local dev_before=0 dev_after=0

  disk_before="$(/bin/df -k / | /usr/bin/tail -1 | /usr/bin/awk '{print $4+0}')"

  if [[ ",$cats," == *,cache,* ]]; then
    cache_before="$(category_kb cache)"
    selected_before=$((selected_before + cache_before))
  fi
  if [[ ",$cats," == *,logs,* ]]; then
    logs_before="$(category_kb logs)"
    selected_before=$((selected_before + logs_before))
  fi
  if [[ ",$cats," == *,xcode,* ]]; then
    xcode_before="$(category_kb xcode)"
    selected_before=$((selected_before + xcode_before))
  fi
  if [[ ",$cats," == *,dev,* ]]; then
    dev_before="$(category_kb dev)"
    selected_before=$((selected_before + dev_before))
  fi

  case ",$cats," in *,cache,*) clean_safe_cache ;; esac
  case ",$cats," in *,logs,*) clean_contents "$HOME/Library/Logs" ;; esac
  case ",$cats," in *,xcode,*) clean_contents "$HOME/Library/Developer/Xcode/DerivedData" ;; esac

  if [[ ",$cats," == *,dev,* ]]; then
    clean_contents "$HOME/.npm/_cacache"
    clean_contents "$HOME/Library/Caches/pip"
    clean_contents "$HOME/Library/Caches/uv"
    clean_contents "$HOME/Library/Caches/Homebrew"
    if command -v brew >/dev/null 2>&1; then
      brew cleanup --prune=30 >/dev/null 2>&1 || true
    fi
  fi

  # 重新读取所选分类的实际剩余大小。
  if [[ ",$cats," == *,cache,* ]]; then
    cache_after="$(category_kb cache)"
    selected_after=$((selected_after + cache_after))
  fi
  if [[ ",$cats," == *,logs,* ]]; then
    logs_after="$(category_kb logs)"
    selected_after=$((selected_after + logs_after))
  fi
  if [[ ",$cats," == *,xcode,* ]]; then
    xcode_after="$(category_kb xcode)"
    selected_after=$((selected_after + xcode_after))
  fi
  if [[ ",$cats," == *,dev,* ]]; then
    dev_after="$(category_kb dev)"
    selected_after=$((selected_after + dev_after))
  fi

  cleaned=$((selected_before - selected_after))
  (( cleaned < 0 )) && cleaned=0

  # APFS/系统可用空间可能延迟更新，所以只作为辅助参考。
  disk_after="$(/bin/df -k / | /usr/bin/tail -1 | /usr/bin/awk '{print $4+0}')"
  disk_delta=$((disk_after - disk_before))
  (( disk_delta < 0 )) && disk_delta=0

  echo "CLEANED_KB=$cleaned"
  echo "DISK_DELTA_KB=$disk_delta"
  echo "SELECTED_BEFORE_KB=$selected_before"
  echo "SELECTED_AFTER_KB=$selected_after"
  echo "CACHE_BEFORE_KB=$cache_before"
  echo "CACHE_AFTER_KB=$cache_after"
  echo "LOGS_BEFORE_KB=$logs_before"
  echo "LOGS_AFTER_KB=$logs_after"
  echo "XCODE_BEFORE_KB=$xcode_before"
  echo "XCODE_AFTER_KB=$xcode_after"
  echo "DEV_BEFORE_KB=$dev_before"
  echo "DEV_AFTER_KB=$dev_after"
}

large_cmd() {
  local tmp="$STATE_DIR/large.$$"
  : > "$tmp"

  for root in "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads" "$HOME/Movies"; do
    [[ -d "$root" ]] || continue
    /usr/bin/find "$root" -type f -size +1G -print0 2>/dev/null | while IFS= read -r -d '' f; do
      kb="$(/usr/bin/du -k "$f" 2>/dev/null | /usr/bin/awk '{print $1+0}')"
      printf "%s\t%s\n" "$kb" "$f" >> "$tmp"
    done
  done

  /usr/bin/sort -nr "$tmp" | /usr/bin/head -60
  /bin/rm -f "$tmp"
}

open_reports_cmd() {
  /usr/bin/open "$REPORT_DIR" >/dev/null 2>&1 || true
}

open_backups_cmd() {
  /usr/bin/open "$BACKUP_DIR" >/dev/null 2>&1 || true
}

get_source_cmd() {
  [[ -s "$SOURCE_FILE" ]] && cat "$SOURCE_FILE"
}

set_source_cmd() {
  local url="${1:-}"
  case "$url" in
    https://*) print -r -- "$url" > "$SOURCE_FILE"; echo "STATUS=OK" ;;
    *) echo "STATUS=INVALID" ;;
  esac
}

plist_value() {
  local target="$1" key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$target/Contents/Info.plist" 2>/dev/null || true
}

validate_app() {
  local candidate="$1"
  [[ -d "$candidate" ]] || return 1
  [[ -f "$candidate/Contents/Info.plist" ]] || return 1
  [[ "$(plist_value "$candidate" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || return 1
  [[ -d "$candidate/Contents/Resources" ]] || return 1
  return 0
}

validate_version_consistency() {
  local candidate="$1"
  local plist_ver source_ver engine_ver

  plist_ver="$(plist_value "$candidate" CFBundleShortVersionString)"

  source_ver="$(
    /usr/bin/grep -E 'XMCVersion = @"[^"]+"' \
      "$candidate/Contents/Resources/main.m" 2>/dev/null \
    | /usr/bin/head -1 \
    | /usr/bin/sed -E 's/.*XMCVersion = @"([^"]+)".*/\1/'
  )"

  engine_ver="$(
    /usr/bin/grep -E '^VERSION="[^"]+"' \
      "$candidate/Contents/Resources/engine.sh" 2>/dev/null \
    | /usr/bin/head -1 \
    | /usr/bin/sed -E 's/^VERSION="([^"]+)".*/\1/'
  )"

  if [[ -z "$plist_ver" || -z "$source_ver" || -z "$engine_ver" ]]; then
    echo "VERSION_CHECK=missing" >> "$BUILD_LOG"
    echo "plist=$plist_ver source=$source_ver engine=$engine_ver" >> "$BUILD_LOG"
    return 1
  fi

  if [[ "$plist_ver" != "$source_ver" || "$plist_ver" != "$engine_ver" ]]; then
    echo "VERSION_CHECK=mismatch" >> "$BUILD_LOG"
    echo "plist=$plist_ver source=$source_ver engine=$engine_ver" >> "$BUILD_LOG"
    return 1
  fi

  echo "VERSION_CHECK=ok $plist_ver" >> "$BUILD_LOG"
  return 0
}

find_app_in_tree() {
  local root="$1" found=""
  while IFS= read -r -d '' p; do
    if validate_app "$p"; then
      found="$p"
      break
    fi
  done < <(/usr/bin/find "$root" -maxdepth 6 -type d -name "*.app" -print0 2>/dev/null)
  [[ -n "$found" ]] && print -r -- "$found"
}

compile_native_app() {
  local candidate="$1"
  local src="$candidate/Contents/Resources/main.m"
  local out="$candidate/Contents/MacOS/XueMeiCleanerNative"
  local clang sdk

  [[ -f "$src" ]] || {
    [[ -x "$out" ]] && return 0
    return 1
  }

  mkdir -p "$candidate/Contents/MacOS"
  clang="$(/usr/bin/xcrun --find clang 2>/dev/null || true)"
  sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"

  [[ -n "$clang" && -n "$sdk" ]] || return 1

  "$clang" \
    -fobjc-arc \
    -fmodules \
    -isysroot "$sdk" \
    -mmacosx-version-min=12.0 \
    -framework Cocoa \
    "$src" \
    -o "$out" >"$BUILD_LOG" 2>&1 || return 1

  /bin/chmod +x "$out"
  return 0
}

semver_gt() {
  /usr/bin/awk -v a="$1" -v b="$2" '
    function parts(v,A,n,i){sub(/[^0-9.].*$/,"",v);n=split(v,A,".");for(i=n+1;i<=4;i++)A[i]=0}
    BEGIN{
      parts(a,A);parts(b,B);
      for(i=1;i<=4;i++){
        ai=A[i]+0;bi=B[i]+0;
        if(ai>bi)exit 0;
        if(ai<bi)exit 1;
      }
      exit 1
    }'
}

backup_current() {
  local ts backup
  ts="$(date '+%Y%m%d_%H%M%S')"
  backup="$BACKUP_DIR/雪梅优化_${VERSION}_${ts}.app"
  /usr/bin/ditto "$APP_ROOT" "$backup" || return 1
  print -r -- "$backup"
}

prepare_candidate() {
  local source_app="$1" dest_app="$2"
  /bin/rm -rf "$dest_app"
  /usr/bin/ditto "$source_app" "$dest_app" || return 1
  validate_app "$dest_app" || return 1
  validate_version_consistency "$dest_app" || return 1
  compile_native_app "$dest_app" || return 1
  /usr/bin/xattr -cr "$dest_app" 2>/dev/null || true
  /usr/bin/find "$dest_app/Contents/MacOS" -type f -exec /bin/chmod +x {} + 2>/dev/null || true
  /usr/bin/codesign --force --deep --sign - "$dest_app" >/dev/null 2>&1 || true
  return 0
}

schedule_apply() {
  local candidate="$1"
  local newver backup parent pending helper
  newver="$(plist_value "$candidate" CFBundleShortVersionString)"
  [[ -n "$newver" ]] || { echo "STATUS=INVALID_VERSION"; return 1; }

  backup="$(backup_current)" || { echo "STATUS=BACKUP_FAILED"; return 1; }
  parent="$(dirname "$APP_ROOT")"
  pending="$parent/.雪梅清理.app.pending"

  if ! prepare_candidate "$candidate" "$pending"; then
    /bin/rm -rf "$pending"
    echo "STATUS=PREPARE_FAILED"
    return 1
  fi

  helper="$STATE_DIR/apply-update-$$.command"
  cat > "$helper" <<'EOF'
#!/bin/zsh
set -u
CURRENT="$1"
PENDING="$2"
BACKUP="$3"
LOG="$4"
sleep 2
echo "[$(date '+%Y-%m-%d %H:%M:%S')] applying native update" >> "$LOG"
/bin/rm -rf "$CURRENT"
if /bin/mv "$PENDING" "$CURRENT"; then
  /usr/bin/xattr -cr "$CURRENT" 2>/dev/null || true
  /usr/bin/codesign --force --deep --sign - "$CURRENT" >/dev/null 2>&1 || true
  /usr/bin/open "$CURRENT" >/dev/null 2>&1 || true
  /bin/rm -f "$0"
  exit 0
fi
/bin/rm -rf "$CURRENT"
if /usr/bin/ditto "$BACKUP" "$CURRENT"; then
  /usr/bin/open "$CURRENT" >/dev/null 2>&1 || true
fi
/bin/rm -f "$0"
EOF
  /bin/chmod +x "$helper"
  /usr/bin/nohup "$helper" "$APP_ROOT" "$pending" "$backup" "$LOG_FILE" >/dev/null 2>&1 &

  echo "STATUS=READY"
  echo "OLD_VERSION=$VERSION"
  echo "NEW_VERSION=$newver"
  echo "BACKUP=$backup"
}

local_update_cmd() {
  local pkg="${1:-}" tmp candidate staged newver
  [[ -f "$pkg" ]] || { echo "STATUS=NO_FILE"; return 1; }

  tmp="$(/usr/bin/mktemp -d -t xuemei-native-update)"
  if ! /usr/bin/ditto -x -k "$pkg" "$tmp"; then
    /bin/rm -rf "$tmp"
    echo "STATUS=EXTRACT_FAILED"
    return 1
  fi

  candidate="$(find_app_in_tree "$tmp")"
  if [[ -z "$candidate" ]]; then
    /bin/rm -rf "$tmp"
    echo "STATUS=NO_VALID_APP"
    return 1
  fi

  newver="$(plist_value "$candidate" CFBundleShortVersionString)"
  staged="$STATE_DIR/staged-update.app"
  /bin/rm -rf "$staged"
  /usr/bin/ditto "$candidate" "$staged"
  /bin/rm -rf "$tmp"

  echo "CANDIDATE_VERSION=$newver"
  schedule_apply "$staged"
  local rc=$?
  /bin/rm -rf "$staged"
  return $rc
}

check_online_cmd() {
  [[ -s "$SOURCE_FILE" ]] || { echo "STATUS=NO_SOURCE"; return 0; }

  local source tmp manifest newver url sha
  source="$(cat "$SOURCE_FILE")"
  tmp="$(/usr/bin/mktemp -d -t xuemei-native-check)"
  manifest="$tmp/manifest.json"

  if ! /usr/bin/curl -fL --connect-timeout 10 --max-time 30 -sS "$source" -o "$manifest"; then
    /bin/rm -rf "$tmp"; echo "STATUS=NETWORK_ERROR"; return 1
  fi

  newver="$(/usr/bin/plutil -extract version raw -o - "$manifest" 2>/dev/null || true)"
  url="$(/usr/bin/plutil -extract download_url raw -o - "$manifest" 2>/dev/null || true)"
  sha="$(/usr/bin/plutil -extract sha256 raw -o - "$manifest" 2>/dev/null || true)"
  /bin/rm -rf "$tmp"

  [[ -n "$newver" && -n "$url" ]] || { echo "STATUS=INVALID_MANIFEST"; return 1; }

  if semver_gt "$newver" "$VERSION"; then
    echo "STATUS=AVAILABLE"
  else
    echo "STATUS=UP_TO_DATE"
  fi
  echo "LATEST=$newver"
  echo "URL=$url"
  echo "SHA256=$sha"
}

online_update_cmd() {
  [[ -s "$SOURCE_FILE" ]] || { echo "STATUS=NO_SOURCE"; return 1; }

  local source tmp manifest newver url sha zip actual extract candidate staged
  source="$(cat "$SOURCE_FILE")"
  tmp="$(/usr/bin/mktemp -d -t xuemei-native-online)"
  manifest="$tmp/manifest.json"

  if ! /usr/bin/curl -fL --connect-timeout 10 --max-time 30 -sS "$source" -o "$manifest"; then
    /bin/rm -rf "$tmp"; echo "STATUS=NETWORK_ERROR"; return 1
  fi

  newver="$(/usr/bin/plutil -extract version raw -o - "$manifest" 2>/dev/null || true)"
  url="$(/usr/bin/plutil -extract download_url raw -o - "$manifest" 2>/dev/null || true)"
  sha="$(/usr/bin/plutil -extract sha256 raw -o - "$manifest" 2>/dev/null || true)"

  case "$url" in https://*) ;; *) /bin/rm -rf "$tmp"; echo "STATUS=INVALID_URL"; return 1 ;; esac

  zip="$tmp/update.zip"
  if ! /usr/bin/curl -fL --connect-timeout 10 --max-time 300 -sS "$url" -o "$zip"; then
    /bin/rm -rf "$tmp"; echo "STATUS=DOWNLOAD_FAILED"; return 1
  fi

  if [[ -n "$sha" && "$sha" != "null" ]]; then
    actual="$(/usr/bin/shasum -a 256 "$zip" | /usr/bin/awk '{print $1}')"
    if [[ "$actual" != "$sha" ]]; then
      /bin/rm -rf "$tmp"; echo "STATUS=SHA256_FAILED"; return 1
    fi
  fi

  extract="$tmp/extract"
  mkdir -p "$extract"
  if ! /usr/bin/ditto -x -k "$zip" "$extract"; then
    /bin/rm -rf "$tmp"; echo "STATUS=EXTRACT_FAILED"; return 1
  fi

  candidate="$(find_app_in_tree "$extract")"
  if [[ -z "$candidate" ]]; then
    /bin/rm -rf "$tmp"; echo "STATUS=NO_VALID_APP"; return 1
  fi

  staged="$STATE_DIR/staged-update.app"
  /bin/rm -rf "$staged"
  /usr/bin/ditto "$candidate" "$staged"
  /bin/rm -rf "$tmp"

  schedule_apply "$staged"
}



full_disk_progress_write() {
  local scan_phase="$1"
  local elapsed_sec="${2:-0}"
  local seen_count="${3:-0}"
  local privacy_count="${4:-0}"
  local current_item="${5:-}"
  local progress_file="$STATE_DIR/full-disk-progress.txt"

  {
    echo "STATUS=$scan_phase"
    echo "ELAPSED_SEC=$elapsed_sec"
    echo "SEEN_COUNT=$seen_count"
    echo "CANDIDATE_COUNT=$seen_count"
    echo "SKIPPED_COUNT=0"
    echo "PRIVACY_SKIPPED_COUNT=$privacy_count"
    echo "CURRENT_PATH=$current_item"
  } > "$progress_file"
}

full_disk_progress_cmd() {
  local progress_file="$STATE_DIR/full-disk-progress.txt"
  if [[ -f "$progress_file" ]]; then
    cat "$progress_file"
  else
    echo "STATUS=IDLE"
    echo "ELAPSED_SEC=0"
    echo "SEEN_COUNT=0"
    echo "CANDIDATE_COUNT=0"
    echo "SKIPPED_COUNT=0"
    echo "PRIVACY_SKIPPED_COUNT=0"
    echo "CURRENT_PATH="
  fi
}

full_disk_stop_cmd() {
  local pid_file="$STATE_DIR/full-disk-scan.pid"
  local scan_pid=""

  if [[ -f "$pid_file" ]]; then
    scan_pid="$(cat "$pid_file" 2>/dev/null || true)"
  fi

  if [[ "$scan_pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$scan_pid" 2>/dev/null; then
    /usr/bin/pkill -TERM -P "$scan_pid" 2>/dev/null || true
    /bin/kill -TERM "$scan_pid" 2>/dev/null || true
    echo "STATUS=STOP_SENT"
    echo "PID=$scan_pid"
  else
    echo "STATUS=NOT_RUNNING"
  fi
}

full_disk_cmd() {
  # v2.7.0 静默白名单扫描：
  # 不再从 /System/Volumes/Data 根目录递归，因此不会先碰到
  # Desktop / Documents / Downloads / Music / Pictures / Movies /
  # Mail / Messages / iCloud / CloudStorage 等 TCC / File Provider 目录。
  #
  # 扫描根目录改为明确的“安全白名单”：
  #   系统/应用/缓存/开发/临时目录
  # 只做 find-only 分类，不逐文件 stat/du，不自动删除。

  local data_root="/System/Volumes/Data"
  [[ -d "$data_root" ]] || data_root="/"

  local data_home="$data_root$HOME"
  local out_dir="$STATE_DIR/full-disk"
  local ts="$(date '+%Y%m%d_%H%M%S')"
  local result="$out_dir/full_disk_$ts.tsv"
  local errors="$out_dir/full_disk_errors_$ts.log"
  local summary="$out_dir/full_disk_summary_$ts.txt"
  local roots_file="$out_dir/full_disk_roots_$ts.txt"
  local privacy_file="$out_dir/full_disk_privacy_skipped_$ts.txt"
  local pid_file="$STATE_DIR/full-disk-scan.pid"
  local temp_dir="$out_dir/.scan_$ts"

  mkdir -p "$out_dir" "$temp_dir"
  : > "$result"
  : > "$errors"
  : > "$roots_file"
  : > "$privacy_file"

  echo $$ > "$pid_file"

  local started_at="$(date +%s)"
  local elapsed=0

  # 这些隐私目录不会被访问，仅记录为“默认跳过”。
  local -a privacy_roots=(
    "$data_home/Desktop"
    "$data_home/Documents"
    "$data_home/Downloads"
    "$data_home/Music"
    "$data_home/Pictures"
    "$data_home/Movies"
    "$data_home/Library/Mail"
    "$data_home/Library/Messages"
    "$data_home/Library/Safari"
    "$data_home/Library/Calendars"
    "$data_home/Library/AddressBook"
    "$data_home/Library/HomeKit"
    "$data_home/Library/Mobile Documents"
    "$data_home/Library/CloudStorage"
    "$data_home/Library/Application Support/CloudDocs"
    "$data_home/Library/Application Support/com.apple.TCC"
    "$data_root/private/var/db/TCC"
  )

  local privacy_skipped_count=0
  local pp
  for pp in "${privacy_roots[@]}"; do
    privacy_skipped_count=$((privacy_skipped_count + 1))
    print -r -- "$pp" >> "$privacy_file"
  done

  # 白名单安全扫描根目录：
  # 不扫描 $HOME 本身，不进入任何受保护用户文件夹。
  local -a safe_roots=(
    "$data_root/Applications"
    "$data_root/Library"
    "$data_root/usr/local"
    "$data_root/opt"
    "$data_root/private/tmp"
    "$data_root/private/var/tmp"
    "$data_root/private/var/folders"
    "$data_home/Applications"
    "$data_home/Public"
    "$data_home/Library/Caches"
    "$data_home/Library/Logs"
    "$data_home/Library/Developer"
    "$data_home/.cache"
    "$data_home/.npm"
    "$data_home/.gradle"
    "$data_home/.cargo"
    "$data_home/.rustup"
  )

  # “安装包/压缩包”只从真正适合清理/检查的目录统计。
  # Applications、系统 Library、/usr/local、/opt 内部的 dmg/pkg/zip/iso
  # 属于应用/系统资源，不再计入“安装包”。
  local -a installer_candidate_roots=(
    "$data_root/private/tmp"
    "$data_root/private/var/tmp"
    "$data_root/private/var/folders"
    "$data_home/Public"
    "$data_home/Library/Caches"
    "$data_home/Library/Logs"
    "$data_home/Library/Developer"
    "$data_home/.cache"
    "$data_home/.npm"
    "$data_home/.gradle"
    "$data_home/.cargo"
    "$data_home/.rustup"
  )

  local -a existing_roots=()
  local r
  for r in "${safe_roots[@]}"; do
    if [[ -d "$r" ]]; then
      existing_roots+=("$r")
      print -r -- "$r" >> "$roots_file"
    fi
  done

  local root_count="${#existing_roots[@]}"
  if (( root_count == 0 )); then
    echo "STATUS=NO_SAFE_ROOTS"
    echo "ERROR_FILE=$errors"
    /bin/rm -f "$pid_file"
    return 1
  fi

  trap '
    elapsed=$(( $(date +%s) - started_at ))
    (( elapsed < 0 )) && elapsed=0
    full_disk_progress_write "CANCELLED" "$elapsed" 0 "$privacy_skipped_count" ""
    echo "STATUS=CANCELLED"
    echo "ELAPSED_SEC=$elapsed"
    echo "PRIVACY_SKIPPED_COUNT=$privacy_skipped_count"
    /bin/rm -rf "$temp_dir"
    /bin/rm -f "$pid_file"
    exit 130
  ' TERM INT

  local p5="$temp_dir/ge5g.txt"
  local p1="$temp_dir/ge1g.txt"
  local p500="$temp_dir/ge500.txt"
  local pinst="$temp_dir/installers.txt"
  local pold="$temp_dir/old_large.txt"

  : > "$p5"
  : > "$p1"
  : > "$p500"
  : > "$pinst"
  : > "$pold"

  full_disk_progress_write \
    "ENUMERATING" 0 0 "$privacy_skipped_count" \
    "静默扫描：已排除隐私目录，准备扫描 $root_count 个安全根目录"

  local root_index=0

  # 每个安全根目录逐个扫描。
  # 即使某个根目录出现 Permission denied，也只记日志，不会触碰隐私目录。
  for r in "${existing_roots[@]}"; do
    root_index=$((root_index + 1))
    elapsed=$(( $(date +%s) - started_at ))

    full_disk_progress_write \
      "ENUMERATING" "$elapsed" 0 "$privacy_skipped_count" \
      "根目录 $root_index/$root_count：$r"

    # >=5GB
    /usr/bin/find -x "$r" -type f -size +5368709119c -print >> "$p5" 2>> "$errors"

    # 1GB~5GB
    /usr/bin/find -x "$r" -type f \
      -size +1073741823c ! -size +5368709119c -print >> "$p1" 2>> "$errors"

    # 500MB~1GB
    /usr/bin/find -x "$r" -type f \
      -size +524287999c ! -size +1073741823c -print >> "$p500" 2>> "$errors"

    # >=500MB 且 365 天以上未修改
    /usr/bin/find -x "$r" -type f \
      -size +524287999c -mtime +365 -print >> "$pold" 2>> "$errors"
  done

  # 独立扫描真正可能属于“安装包/压缩包”的候选目录。
  # 不进入 Applications / 系统 Library / usr/local / opt。
  local ir
  for ir in "${installer_candidate_roots[@]}"; do
    [[ -d "$ir" ]] || continue

    /usr/bin/find -x "$ir" -type f ! -size +524287999c \
      \( \
        -iname "*.dmg" \
        -o -iname "*.pkg" \
        -o -iname "*.zip" \
        -o -iname "*.tgz" \
        -o -iname "*.tar.gz" \
        -o -iname "*.tbz" \
        -o -iname "*.tbz2" \
        -o -iname "*.7z" \
        -o -iname "*.rar" \
        -o -iname "*.iso" \
      \) -print >> "$pinst" 2>> "$errors"
  done

  # 如果 find 本身语法错误，明确失败；普通权限拒绝仅记录。
  if /usr/bin/grep -Eqi \
      'unknown primary|unknown option|illegal option|paths must precede|illegal primary|usage: find|find: -x' \
      "$errors"; then
    elapsed=$(( $(date +%s) - started_at ))
    full_disk_progress_write "FAILED" "$elapsed" 0 "$privacy_skipped_count" "find 命令失败"
    echo "STATUS=FIND_FATAL"
    echo "ERROR_FILE=$errors"
    /bin/rm -rf "$temp_dir"
    /bin/rm -f "$pid_file"
    trap - TERM INT
    return 1
  fi

  # 去重：同一文件不重复统计。
  /usr/bin/sort -u "$p5" -o "$p5"
  /usr/bin/sort -u "$p1" -o "$p1"
  /usr/bin/sort -u "$p500" -o "$p500"
  /usr/bin/sort -u "$pinst" -o "$pinst"
  /usr/bin/sort -u "$pold" -o "$pold"

  local ge5=0 ge1only=0 ge500only=0 installers=0 old_large=0
  ge5="$(/usr/bin/wc -l < "$p5" | /usr/bin/tr -d ' ')"
  ge1only="$(/usr/bin/wc -l < "$p1" | /usr/bin/tr -d ' ')"
  ge500only="$(/usr/bin/wc -l < "$p500" | /usr/bin/tr -d ' ')"
  installers="$(/usr/bin/wc -l < "$pinst" | /usr/bin/tr -d ' ')"
  old_large="$(/usr/bin/wc -l < "$pold" | /usr/bin/tr -d ' ')"

  [[ -n "$ge5" ]] || ge5=0
  [[ -n "$ge1only" ]] || ge1only=0
  [[ -n "$ge500only" ]] || ge500only=0
  [[ -n "$installers" ]] || installers=0
  [[ -n "$old_large" ]] || old_large=0

  local ge1=$((ge5 + ge1only))
  local ge500=$((ge1 + ge500only))
  local candidate_count=$((ge500 + installers))

  {
    while IFS= read -r f; do [[ -n "$f" ]] && printf ">=5GB\t%s\n" "$f"; done < "$p5"
    while IFS= read -r f; do [[ -n "$f" ]] && printf ">=1GB\t%s\n" "$f"; done < "$p1"
    while IFS= read -r f; do [[ -n "$f" ]] && printf ">=500MB\t%s\n" "$f"; done < "$p500"
    while IFS= read -r f; do [[ -n "$f" ]] && printf "安装包/压缩包\t%s\n" "$f"; done < "$pinst"
  } > "$result"

  # 升级结果格式：分类<TAB>长期未修改标记<TAB>完整路径
  # 只对已有文本列表做集合匹配，不重新访问候选文件。
  local enriched_result="$temp_dir/result_enriched.tsv"
  /usr/bin/awk -F '\t' '
    FILENAME == ARGV[1] {
      old[$0]=1
      next
    }
    {
      pos=index($0, "\t")
      if (pos <= 0) next
      cat=substr($0, 1, pos-1)
      file_path=substr($0, pos+1)
      flag=(old[file_path] ? "长期未修改" : "")
      printf "%s\t%s\t%s\n", cat, flag, file_path
    }
  ' "$pold" "$result" > "$enriched_result"

  if [[ ! -s "$enriched_result" && -s "$result" ]]; then
    echo "STATUS=POSTPROCESS_FAILED"
    echo "POSTPROCESS_STAGE=enrich_result"
    echo "RESULT_FILE=$result"
    echo "ERROR_FILE=$errors"
    return 1
  fi

  if ! /bin/mv "$enriched_result" "$result"; then
    echo "STATUS=POSTPROCESS_FAILED"
    echo "POSTPROCESS_STAGE=move_enriched_result"
    echo "RESULT_FILE=$result"
    echo "ERROR_FILE=$errors"
    return 1
  fi

  local denied=0
  denied="$(/usr/bin/grep -cE 'Permission denied|Operation not permitted' "$errors" 2>/dev/null || true)"
  [[ -n "$denied" ]] || denied=0

  local disk_total_kb disk_free_kb
  disk_total_kb="$(/bin/df -k / | /usr/bin/tail -1 | /usr/bin/awk '{print $2+0}')"
  disk_free_kb="$(/bin/df -k / | /usr/bin/tail -1 | /usr/bin/awk '{print $4+0}')"

  elapsed=$(( $(date +%s) - started_at ))
  (( elapsed < 0 )) && elapsed=0

  full_disk_progress_write \
    "DONE" "$elapsed" "$candidate_count" "$privacy_skipped_count" ""

  {
    echo "雪梅优化 v$VERSION 静默白名单全盘扫描"
    echo "扫描时间：$(date)"
    echo "扫描模式：静默白名单"
    echo "扫描耗时：${elapsed} 秒"
    echo "安全根目录数量：$root_count"
    echo
    echo "候选文件：$candidate_count"
    echo ">=500MB：$ge500"
    echo ">=1GB：$ge1"
    echo ">=5GB：$ge5"
    echo "长期未修改的大文件：$old_large"
    echo "可处理安装包/压缩包（<500MB）：$installers"
    echo "隐私目录主动跳过：$privacy_skipped_count"
    echo "普通权限拒绝：$denied"
    echo
    echo "扫描根目录清单：$roots_file"
    echo "隐私跳过清单：$privacy_file"
    echo "结果文件：$result"
    echo "错误日志：$errors"
  } > "$summary"

  echo "STATUS=OK"
  echo "SCAN_MODE=SILENT_WHITELIST_FIND_ONLY"
  echo "ELAPSED_SEC=$elapsed"
  echo "ROOT_COUNT=$root_count"
  echo "DISK_TOTAL_KB=$disk_total_kb"
  echo "DISK_FREE_KB=$disk_free_kb"
  echo "SEEN_COUNT=$candidate_count"
  echo "CANDIDATE_COUNT=$candidate_count"
  echo "SKIPPED_COUNT=0"
  echo "PRIVACY_SKIPPED_COUNT=$privacy_skipped_count"
  echo "GE500_COUNT=$ge500"
  echo "GE1G_COUNT=$ge1"
  echo "GE5G_COUNT=$ge5"
  echo "OLD_LARGE_COUNT=$old_large"
  echo "INSTALLER_COUNT=$installers"
  echo "DENIED_COUNT=$denied"
  echo "ROOTS_FILE=$roots_file"
  echo "RESULT_FILE=$result"
  echo "RESULT_FORMAT=CATEGORY_STATUS_PATH"
  local result_row_count=0
  if [[ -f "$result" ]]; then
    result_row_count="$(/usr/bin/wc -l < "$result" 2>/dev/null | /usr/bin/tr -d ' ')"
    [[ "$result_row_count" =~ ^[0-9]+$ ]] || result_row_count=0
  fi
  echo "RESULT_ROW_COUNT=$result_row_count"
  echo "PRIVACY_FILE=$privacy_file"
  echo "SUMMARY_FILE=$summary"
  echo "ERROR_FILE=$errors"

  /bin/rm -rf "$temp_dir"
  /bin/rm -f "$pid_file"
  trap - TERM INT
}




is_protected_candidate_path() {
  local p="${1:l}"

  case "$p" in
    *"/applications/"*|*".app/contents/"*)
      return 0
      ;;
    *"/.codex/"*|*"/.ssh/"*|*"/keychains/"*|*"/keychain"*|*"/wallet"*|*"/secret"*|*"/apikey"*|*"/api_key"*)
      return 0
      ;;
    *"google/chrome"*|*"tiktok"*|*"chatgpt"*|*"openai"*|*"clash"*|*"docker"*|*"iota"*|*"bittensor"*|*"macrocosmos"*)
      return 0
      ;;
  esac

  return 1
}

is_safe_full_disk_delete_target() {
  local p="$1"

  [[ -f "$p" ]] || return 1
  [[ ! -L "$p" ]] || return 1

  if is_protected_candidate_path "$p"; then
    return 1
  fi

  case "$p" in
    "$HOME/Library/Caches/"*|\
    "/System/Volumes/Data$HOME/Library/Caches/"*|\
    "$HOME/Library/Logs/"*|\
    "/System/Volumes/Data$HOME/Library/Logs/"*|\
    "$HOME/Library/Developer/Xcode/DerivedData/"*|\
    "/System/Volumes/Data$HOME/Library/Developer/Xcode/DerivedData/"*|\
    "$HOME/.cache/"*|\
    "/System/Volumes/Data$HOME/.cache/"*|\
    "$HOME/.npm/_cacache/"*|\
    "/System/Volumes/Data$HOME/.npm/_cacache/"*|\
    "$HOME/.gradle/caches/"*|\
    "/System/Volumes/Data$HOME/.gradle/caches/"*|\
    "$HOME/.cargo/registry/cache/"*|\
    "/System/Volumes/Data$HOME/.cargo/registry/cache/"*|\
    "/private/tmp/"*|\
    "/private/var/tmp/"*|\
    "/System/Volumes/Data/private/tmp/"*|\
    "/System/Volumes/Data/private/var/tmp/"*)
      return 0
      ;;
  esac

  return 1
}

full_disk_clean_safe_cmd() {
  local result_file="${1:-}"
  local full_dir="$STATE_DIR/full-disk"

  [[ -n "$result_file" ]] || {
    echo "STATUS=NO_RESULT_FILE"
    return 1
  }

  # 只接受雪梅优化自己生成的 full-disk 结果文件。
  case "$result_file" in
    "$full_dir/"full_disk_*.tsv) ;;
    *)
      echo "STATUS=INVALID_RESULT_FILE"
      return 1
      ;;
  esac

  [[ -f "$result_file" ]] || {
    echo "STATUS=RESULT_FILE_MISSING"
    return 1
  }

  local deleted_count=0
  local skipped_count=0
  local failed_count=0
  local deleted_kb=0

  while IFS=$'\t' read -r col1 col2 rest; do
    local file_path=""
    local size_kb=0

    # v2.8+ 三列：分类 / 状态 / 路径
    # 兼容旧两列：分类 / 路径
    if [[ -n "$rest" ]]; then
      file_path="$rest"
    else
      file_path="$col2"
    fi

    [[ -n "$file_path" ]] || continue

    if ! is_safe_full_disk_delete_target "$file_path"; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    size_kb="$(/usr/bin/du -k "$file_path" 2>/dev/null | /usr/bin/awk '{print $1+0}')"
    [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0

    if /bin/rm -f -- "$file_path" 2>/dev/null; then
      deleted_count=$((deleted_count + 1))
      deleted_kb=$((deleted_kb + size_kb))
    else
      failed_count=$((failed_count + 1))
    fi
  done < "$result_file"

  echo "STATUS=OK"
  echo "DELETED_COUNT=$deleted_count"
  echo "SKIPPED_COUNT=$skipped_count"
  echo "FAILED_COUNT=$failed_count"
  echo "DELETED_KB=$deleted_kb"
}



run_with_timeout() {
  local timeout_sec="$1"
  shift

  "$@" >/dev/null 2>&1 &
  local cmd_pid=$!
  local ticks=0
  local max_ticks=$((timeout_sec * 10))

  while /bin/kill -0 "$cmd_pid" 2>/dev/null; do
    /bin/sleep 0.1
    ticks=$((ticks + 1))

    if (( ticks >= max_ticks )); then
      /bin/kill -TERM "$cmd_pid" 2>/dev/null || true
      /bin/sleep 0.05
      /bin/kill -KILL "$cmd_pid" 2>/dev/null || true
      wait "$cmd_pid" 2>/dev/null || true
      return 124
    fi
  done

  wait "$cmd_pid" 2>/dev/null
  return $?
}

installer_extension_type() {
  local lower="${1:l}"

  case "$lower" in
    *.dmg) echo "DMG 安装镜像" ;;
    *.pkg) echo "PKG 安装包" ;;
    *.iso) echo "ISO 镜像" ;;
    *.download|*.crdownload|*.part|*.partial) echo "未完成下载" ;;
    *.zip|*.tgz|*.tar.gz|*.tbz|*.tbz2|*.7z|*.rar) echo "压缩包" ;;
    *) echo "安装包/压缩包" ;;
  esac
}

installer_validate_file() {
  local f="$1"
  local lower="${f:l}"
  local size_bytes

  size_bytes="$(/usr/bin/stat -f %z "$f" 2>/dev/null || echo 0)"
  [[ "$size_bytes" =~ ^[0-9]+$ ]] || size_bytes=0

  if (( size_bytes == 0 )); then
    echo "失效"
    return 0
  fi

  case "$lower" in
    *.download|*.crdownload|*.part|*.partial)
      echo "失效"
      return 0
      ;;
    *.zip)
      if run_with_timeout 6 /usr/bin/unzip -Z1 "$f"; then
        echo "正常"
      else
        local rc=$?
        if (( rc == 124 )); then echo "未验证"; else echo "失效"; fi
      fi
      ;;
    *.tgz|*.tar.gz|*.tbz|*.tbz2)
      if run_with_timeout 6 /usr/bin/tar -tf "$f"; then
        echo "正常"
      else
        local rc=$?
        if (( rc == 124 )); then echo "未验证"; else echo "失效"; fi
      fi
      ;;
    *.dmg|*.iso)
      if run_with_timeout 8 /usr/bin/hdiutil verify -quiet "$f"; then
        echo "正常"
      else
        local rc=$?
        if (( rc == 124 )); then echo "未验证"; else echo "失效"; fi
      fi
      ;;
    *.pkg)
      if [[ -x /usr/bin/xar ]]; then
        if run_with_timeout 6 /usr/bin/xar -tf "$f"; then
          echo "正常"
        else
          local rc=$?
          if (( rc == 124 )); then echo "未验证"; else echo "失效"; fi
        fi
      else
        echo "未验证"
      fi
      ;;
    *.7z|*.rar)
      if command -v 7z >/dev/null 2>&1; then
        if run_with_timeout 6 7z l "$f"; then echo "正常"; else echo "失效"; fi
      else
        echo "未验证"
      fi
      ;;
    *)
      echo "未验证"
      ;;
  esac
}

collect_installed_bundle_ids() {
  local out="$1"
  : > "$out"

  local root app plist_file bundle_id
  for root in "/Applications" "$HOME/Applications"; do
    [[ -d "$root" ]] || continue

    while IFS= read -r -d '' app; do
      plist_file="$app/Contents/Info.plist"
      [[ -f "$plist_file" ]] || continue

      bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist_file" 2>/dev/null || true)"
      [[ -n "$bundle_id" ]] && print -r -- "$bundle_id" >> "$out"
    done < <(/usr/bin/find "$root" -maxdepth 2 -type d -name "*.app" -print0 2>/dev/null)
  done

  /usr/bin/sort -u "$out" -o "$out"
}

bundle_id_installed() {
  local id="$1"
  local installed_ids="$2"
  [[ -n "$id" && -f "$installed_ids" ]] || return 1
  /usr/bin/grep -Fxq -- "$id" "$installed_ids"
}

plist_bundle_id_from_file() {
  local plist_file="$1"
  [[ -f "$plist_file" ]] || return 1
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist_file" 2>/dev/null
}

detect_zip_installed() {
  local f="$1"
  local installed_ids="$2"
  local temp_dir="$3"
  local entry plist_tmp bundle_id

  entry="$(/usr/bin/unzip -Z1 "$f" 2>/dev/null \
    | /usr/bin/grep -E '\.app/Contents/Info\.plist$' \
    | /usr/bin/head -1)"

  [[ -n "$entry" ]] || return 1

  plist_tmp="$temp_dir/zip-info-$$-$RANDOM.plist"
  /usr/bin/unzip -p "$f" "$entry" > "$plist_tmp" 2>/dev/null || {
    /bin/rm -f "$plist_tmp"
    return 1
  }

  bundle_id="$(plist_bundle_id_from_file "$plist_tmp" || true)"
  /bin/rm -f "$plist_tmp"

  bundle_id_installed "$bundle_id" "$installed_ids"
}

detect_tar_installed() {
  local f="$1"
  local installed_ids="$2"
  local temp_dir="$3"
  local entry plist_tmp bundle_id

  entry="$(/usr/bin/tar -tf "$f" 2>/dev/null \
    | /usr/bin/grep -E '\.app/Contents/Info\.plist$' \
    | /usr/bin/head -1)"

  [[ -n "$entry" ]] || return 1

  plist_tmp="$temp_dir/tar-info-$$-$RANDOM.plist"
  /usr/bin/tar -xOf "$f" "$entry" > "$plist_tmp" 2>/dev/null || {
    /bin/rm -f "$plist_tmp"
    return 1
  }

  bundle_id="$(plist_bundle_id_from_file "$plist_tmp" || true)"
  /bin/rm -f "$plist_tmp"

  bundle_id_installed "$bundle_id" "$installed_ids"
}

detect_dmg_installed() {
  local f="$1"
  local installed_ids="$2"
  local temp_dir="$3"
  local mount_point="$temp_dir/dmg-mount-$$-$RANDOM"
  local app plist_file bundle_id found=1

  mkdir -p "$mount_point"

  if ! run_with_timeout 10 /usr/bin/hdiutil attach \
      -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$f"; then
    /usr/bin/hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true
    /bin/rm -rf "$mount_point"
    return 1
  fi

  while IFS= read -r -d '' app; do
    plist_file="$app/Contents/Info.plist"
    [[ -f "$plist_file" ]] || continue

    bundle_id="$(plist_bundle_id_from_file "$plist_file" || true)"

    if bundle_id_installed "$bundle_id" "$installed_ids"; then
      found=0
      break
    fi
  done < <(/usr/bin/find "$mount_point" -maxdepth 3 -type d -name "*.app" -print0 2>/dev/null)

  /usr/bin/hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true
  /bin/rm -rf "$mount_point"

  return $found
}

detect_pkg_installed() {
  local f="$1"
  local receipts_file="$2"
  local temp_dir="$3"
  local expanded="$temp_dir/pkg-expand-$$-$RANDOM"
  local identifier

  mkdir -p "$expanded"

  if ! run_with_timeout 8 /usr/sbin/pkgutil --expand "$f" "$expanded"; then
    /bin/rm -rf "$expanded"
    return 1
  fi

  identifier="$(
    /usr/bin/grep -RhoE 'identifier="[^"]+"' "$expanded" 2>/dev/null \
      | /usr/bin/sed -E 's/identifier="([^"]+)"/\1/' \
      | /usr/bin/head -1
  )"

  /bin/rm -rf "$expanded"

  [[ -n "$identifier" ]] || return 1
  /usr/bin/grep -Fxq -- "$identifier" "$receipts_file"
}

installer_detect_installed() {
  local f="$1"
  local installed_ids="$2"
  local receipts_file="$3"
  local temp_dir="$4"
  local lower="${f:l}"

  case "$lower" in
    *.dmg)
      detect_dmg_installed "$f" "$installed_ids" "$temp_dir" && {
        echo "已安装"
        return 0
      }
      ;;
    *.pkg)
      detect_pkg_installed "$f" "$receipts_file" "$temp_dir" && {
        echo "已安装"
        return 0
      }
      ;;
    *.zip)
      detect_zip_installed "$f" "$installed_ids" "$temp_dir" && {
        echo "已安装"
        return 0
      }
      ;;
    *.tgz|*.tar.gz|*.tbz|*.tbz2)
      detect_tar_installed "$f" "$installed_ids" "$temp_dir" && {
        echo "已安装"
        return 0
      }
      ;;
  esac

  echo "未确认"
}

installer_scan_root_allowed() {
  local root="$1"

  [[ -d "$root" ]] || return 1

  # 只允许用户主动选择的普通个人目录，避免误扫 Library/应用包/开发环境。
  case "$root" in
    "$HOME/Downloads"|"$HOME/Downloads/"*|\
    "$HOME/Desktop"|"$HOME/Desktop/"*|\
    "$HOME/Documents"|"$HOME/Documents/"*|\
    "$HOME/Public"|"$HOME/Public/"*)
      ;;
    *)
      return 1
      ;;
  esac

  # 额外防御：任何受保护关键词出现即拒绝。
  local lower="${root:l}"
  case "$lower" in
    *"/library/"*|*"/applications/"*|*"/.ssh"*|*"/.codex"*|*"/keychain"*|*"/wallet"*|*"/secret"*)
      return 1
      ;;
  esac

  return 0
}

installer_scan_cmd() {
  local requested_root="${1:-}"

  [[ -n "$requested_root" ]] || {
    echo "STATUS=NO_ROOT"
    return 1
  }

  local scan_root
  scan_root="$(cd "$requested_root" 2>/dev/null && /bin/pwd -P)" || {
    echo "STATUS=ROOT_NOT_FOUND"
    return 1
  }

  if ! installer_scan_root_allowed "$scan_root"; then
    echo "STATUS=ROOT_NOT_ALLOWED"
    echo "ROOT=$scan_root"
    return 1
  fi

  local out_dir="$STATE_DIR/installer-cleaner"
  local ts="$(date '+%Y%m%d_%H%M%S')"
  local all_file="$out_dir/installers_all_$ts.txt"
  local old_file="$out_dir/installers_old_$ts.txt"
  local result="$out_dir/installers_$ts.tsv"
  local errors="$out_dir/installers_errors_$ts.log"
  local installed_ids="$out_dir/installed_bundle_ids_$ts.txt"
  local receipts_file="$out_dir/pkg_receipts_$ts.txt"
  local temp_dir="$out_dir/.inspect_$ts"

  mkdir -p "$out_dir" "$temp_dir"
  : > "$all_file"
  : > "$old_file"
  : > "$result"
  : > "$errors"
  : > "$installed_ids"
  : > "$receipts_file"

  # 包含未完成下载扩展名，用于识别“失效”安装包。
  /usr/bin/find -x "$scan_root" -type f \
    \( \
      -iname "*.dmg" \
      -o -iname "*.pkg" \
      -o -iname "*.zip" \
      -o -iname "*.tgz" \
      -o -iname "*.tar.gz" \
      -o -iname "*.tbz" \
      -o -iname "*.tbz2" \
      -o -iname "*.7z" \
      -o -iname "*.rar" \
      -o -iname "*.iso" \
      -o -iname "*.download" \
      -o -iname "*.crdownload" \
      -o -iname "*.part" \
      -o -iname "*.partial" \
    \) -print > "$all_file" 2> "$errors"

  /usr/bin/find -x "$scan_root" -type f -mtime +30 \
    \( \
      -iname "*.dmg" \
      -o -iname "*.pkg" \
      -o -iname "*.zip" \
      -o -iname "*.tgz" \
      -o -iname "*.tar.gz" \
      -o -iname "*.tbz" \
      -o -iname "*.tbz2" \
      -o -iname "*.7z" \
      -o -iname "*.rar" \
      -o -iname "*.iso" \
      -o -iname "*.download" \
      -o -iname "*.crdownload" \
      -o -iname "*.part" \
      -o -iname "*.partial" \
    \) -print > "$old_file" 2>> "$errors"

  if /usr/bin/grep -Eqi \
      'unknown primary|unknown option|illegal option|paths must precede|illegal primary|usage: find' \
      "$errors"; then
    /bin/rm -rf "$temp_dir"
    echo "STATUS=FIND_FATAL"
    echo "ERROR_FILE=$errors"
    return 1
  fi

  collect_installed_bundle_ids "$installed_ids"
  /usr/sbin/pkgutil --pkgs 2>/dev/null | /usr/bin/sort -u > "$receipts_file"

  local total_count=0
  local old_count=0
  local invalid_count=0
  local installed_count=0
  local recommended_count=0

  local f type age health installed reason
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue

    type="$(installer_extension_type "$f")"

    if /usr/bin/grep -Fxq -- "$f" "$old_file"; then
      age="30天以上"
      old_count=$((old_count + 1))
    else
      age="近期"
    fi

    health="$(installer_validate_file "$f")"
    [[ "$health" == "失效" ]] && invalid_count=$((invalid_count + 1))

    installed="未确认"
    if [[ "$health" != "失效" ]]; then
      installed="$(installer_detect_installed "$f" "$installed_ids" "$receipts_file" "$temp_dir")"
    fi
    [[ "$installed" == "已安装" ]] && installed_count=$((installed_count + 1))

    reason=""
    # v4.1.1：只把“失效/损坏”或“已确认安装成功”列为建议清理。
    # 年龄仅显示参考，不再因为超过 30 天而自动清理。
    [[ "$health" == "失效" ]] && reason="${reason}失效/损坏/"
    [[ "$installed" == "已安装" ]] && reason="${reason}已安装/"

    if [[ -n "$reason" ]]; then
      reason="${reason%/}"
      recommended_count=$((recommended_count + 1))
    else
      reason="保留"
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$type" "$age" "$health" "$installed" "$reason" "$f" >> "$result"

    total_count=$((total_count + 1))
  done < "$all_file"

  /bin/rm -rf "$temp_dir"

  if (( total_count == 0 )) && /usr/bin/grep -Eq 'Permission denied|Operation not permitted' "$errors" 2>/dev/null; then
    echo "STATUS=ROOT_PERMISSION_DENIED"
    echo "ROOT=$scan_root"
    echo "ERROR_FILE=$errors"
    return 1
  fi

  echo "STATUS=OK"
  echo "ROOT=$scan_root"
  echo "TOTAL_COUNT=$total_count"
  echo "OLD_COUNT=$old_count"
  echo "INVALID_COUNT=$invalid_count"
  echo "INSTALLED_COUNT=$installed_count"
  echo "RECOMMENDED_COUNT=$recommended_count"
  echo "RESULT_FILE=$result"
  echo "ERROR_FILE=$errors"
}


apps_report_cmd() {
  echo "【应用管理】"
  echo "按占用空间排序，只读分析，不卸载应用。"
  echo

  local tmp="$STATE_DIR/apps-report.$$"
  : > "$tmp"

  local roots=("/Applications" "$HOME/Applications")
  local root app kb

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' app; do
      kb="$(/usr/bin/du -sk "$app" 2>/dev/null | /usr/bin/awk '{print $1+0}')"
      [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
      printf "%s\t%s\n" "$kb" "$app" >> "$tmp"
    done < <(/usr/bin/find "$root" -maxdepth 1 -type d -name "*.app" -print0 2>/dev/null)
  done

  if [[ ! -s "$tmp" ]]; then
    echo "没有找到可分析的应用。"
    /bin/rm -f "$tmp"
    return
  fi

  printf "%-12s  %s\n" "占用空间" "应用"
  echo "------------------------------------------------------------"

  /usr/bin/sort -nr "$tmp" | /usr/bin/head -80 | while IFS=$'\t' read -r kb app; do
    printf "%-12s  %s\n" "$(human_kb "$kb")" "$app"
  done

  /bin/rm -f "$tmp"
}

startup_report_cmd() {
  echo "【启动项 / 后台服务】"
  echo "只读列出 LaunchAgents / LaunchDaemons，不自动禁用。"
  echo

  local dirs=(
    "$HOME/Library/LaunchAgents"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
  )

  local dir f count=0
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    echo "[$dir]"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      count=$((count + 1))
      echo "  • $(basename "$f")"
    done < <(/usr/bin/find "$dir" -maxdepth 1 -type f -name "*.plist" -print 2>/dev/null | /usr/bin/sort)
    echo
  done

  echo "共发现：$count 个启动/后台配置。"
  echo
  echo "提示：这一版仅分析，不会调用 launchctl unload/bootout。"
}

memory_report_cmd() {
  echo "【内存状态】"

  local bytes pagesize
  bytes="$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null || echo 0)"
  pagesize="$(/usr/bin/vm_stat 2>/dev/null | /usr/bin/head -1 | /usr/bin/awk '{gsub(/[^0-9]/,"",$8); print $8}')"
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
  [[ "$pagesize" =~ ^[0-9]+$ ]] || pagesize=4096

  echo "物理内存：$(/usr/bin/awk -v b="$bytes" 'BEGIN{printf "%.2f GB", b/1073741824}')"
  echo
  /usr/sbin/sysctl vm.swapusage 2>/dev/null || true
  echo
  echo "vm_stat："
  /usr/bin/vm_stat 2>/dev/null | /usr/bin/head -20
  echo
  echo "内存占用较高的进程（前 20）："
  /bin/ps -axo pid,%mem,rss,comm -r 2>/dev/null | /usr/bin/head -21
}

network_report_cmd() {
  echo "【网络诊断】"
  echo

  echo "默认路由："
  /sbin/route -n get default 2>/dev/null | /usr/bin/grep -E 'gateway:|interface:' || echo "  未读取到默认路由"
  echo

  echo "系统代理："
  /usr/sbin/scutil --proxy 2>/dev/null | /usr/bin/head -60
  echo

  echo "DNS 摘要："
  /usr/sbin/scutil --dns 2>/dev/null | /usr/bin/grep -E 'nameserver\\[[0-9]+\\]|if_index|reach' | /usr/bin/head -40
  echo

  echo "活动网络接口："
  /sbin/ifconfig 2>/dev/null | /usr/bin/awk '
    /^[a-zA-Z0-9]/ {iface=$1; sub(/:$/,"",iface)}
    /status: active/ {print "  • " iface " (active)"}
  '
}

health_report_cmd() {
  echo "【系统健康】"
  echo

  echo "macOS：$(/usr/bin/sw_vers -productVersion 2>/dev/null)"
  echo "Build：$(/usr/bin/sw_vers -buildVersion 2>/dev/null)"
  echo "机型：$(/usr/sbin/sysctl -n hw.model 2>/dev/null)"
  echo "芯片：$(/usr/sbin/sysctl -n machdep.cpu.brand_string 2>/dev/null || /usr/sbin/sysctl -n hw.machine 2>/dev/null)"
  echo "CPU 核心：$(/usr/sbin/sysctl -n hw.ncpu 2>/dev/null)"
  echo

  echo "运行时间："
  /usr/bin/uptime
  echo

  echo "系统负载："
  /usr/sbin/sysctl -n vm.loadavg 2>/dev/null || true
  echo

  echo "系统磁盘："
  /bin/df -h /
  echo

  echo "内存交换："
  /usr/sbin/sysctl vm.swapusage 2>/dev/null || true
  echo

  echo "电源 / 电池："
  /usr/bin/pmset -g batt 2>/dev/null || true
  echo

  echo "温控状态（系统允许时）："
  /usr/bin/pmset -g therm 2>/dev/null || echo "  当前系统未提供温控详情"
}

case "${1:-}" in
  scan) scan_cmd ;;
  clean) clean_cmd "${2:-}" ;;
  large) large_cmd ;;
  full-disk) full_disk_cmd ;;
  full-disk-progress) full_disk_progress_cmd ;;
  full-disk-stop) full_disk_stop_cmd ;;
  full-disk-clean-safe) full_disk_clean_safe_cmd "${2:-}" ;;
  installer-scan) installer_scan_cmd "${2:-}" ;;
  apps-report) apps_report_cmd ;;
  startup-report) startup_report_cmd ;;
  memory-report) memory_report_cmd ;;
  network-report) network_report_cmd ;;
  health-report) health_report_cmd ;;
  open-reports) open_reports_cmd ;;
  open-backups) open_backups_cmd ;;
  get-source) get_source_cmd ;;
  set-source) set_source_cmd "${2:-}" ;;
  local-update) local_update_cmd "${2:-}" ;;
  check-online) check_online_cmd ;;
  online-update) online_update_cmd ;;
  version) echo "$VERSION" ;;
  *) echo "UNKNOWN_COMMAND"; exit 2 ;;
esac
