#!/usr/bin/env python3
from pathlib import Path
import re, sys

if len(sys.argv)!=2:
    raise SystemExit('usage: release_v524.py /path/to/雪梅优化.app')
app=Path(sys.argv[1])
main=app/'Contents/Resources/main.m'
engine=app/'Contents/Resources/engine.sh'
plist=app/'Contents/Info.plist'
if not main.exists() or not engine.exists() or not plist.exists():
    raise SystemExit('missing app sources')

m=main.read_text(encoding='utf-8')
e=engine.read_text(encoding='utf-8')

m=m.replace('static NSString * const XMCVersion = @"5.2.3";', 'static NSString * const XMCVersion = @"5.2.4";')
e=e.replace('VERSION="5.2.3"','VERSION="5.2.4"',1)

defsrc='https://raw.githubusercontent.com/dschenyw/xuemei-optimizer/main/updates/manifest.json'
source_anchor='SOURCE_FILE="$STATE_DIR/update-source.txt"\n'
if 'DEFAULT_UPDATE_SOURCE=' not in e:
    e=e.replace(source_anchor, source_anchor+f'DEFAULT_UPDATE_SOURCE="{defsrc}"\n',1)
mkdir_anchor='mkdir -p "$STATE_DIR" "$REPORT_DIR" "$BACKUP_DIR"\ntouch "$LOG_FILE"\n'
if '[[ -s "$SOURCE_FILE" ]] || print -r -- "$DEFAULT_UPDATE_SOURCE" > "$SOURCE_FILE"' not in e:
    e=e.replace(mkdir_anchor, mkdir_anchor+'[[ -s "$SOURCE_FILE" ]] || print -r -- "$DEFAULT_UPDATE_SOURCE" > "$SOURCE_FILE"\n',1)

auto_engine=r'''
installer_auto_scan_v524_cmd() {
  local out_dir="$STATE_DIR/installer-cleaner" ts result tmp root scan kv rf
  ts="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "$out_dir"
  result="$out_dir/installer_auto_${ts}.tsv"
  tmp="$out_dir/.installer_auto_${ts}.raw.tsv"
  : > "$result"; : > "$tmp"

  local total=0 recommended=0 invalid=0 installed=0 old=0 roots_ok=0 roots_skipped=0
  local -a roots=("$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" "$HOME/Public")

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    kv="$(installer_scan_cmd "$root" 2>/dev/null || true)"
    rf="$(print -r -- "$kv" | /usr/bin/awk -F= '$1=="RESULT_FILE"{sub(/^RESULT_FILE=/,"");print;exit}')"
    if [[ -n "$rf" && -f "$rf" ]]; then
      /bin/cat "$rf" >> "$tmp"
      roots_ok=$((roots_ok+1))
    else
      roots_skipped=$((roots_skipped+1))
    fi
  done

  /usr/bin/awk -F '\t' '!seen[$NF]++' "$tmp" > "$result.raw"

  typeset -A maxv
  local type age health inst reason f fam ver
  while IFS=$'\t' read -r type age health inst reason f; do
    [[ -n "$f" ]] || continue
    ver="$(v52_ver "$f")"; fam="$(v52_family "$f")"
    [[ -n "$ver" && -n "$fam" ]] || continue
    if [[ -z "${maxv[$fam]:-}" ]] || semver_gt "$ver" "${maxv[$fam]}"; then
      maxv[$fam]="$ver"
    fi
  done < "$result.raw"

  : > "$result"
  while IFS=$'\t' read -r type age health inst reason f; do
    [[ -n "$f" ]] || continue
    ver="$(v52_ver "$f")"; fam="$(v52_family "$f")"
    if [[ "$health" != "失效" && "$inst" != "已安装" && "$reason" == "保留" && -n "$ver" && -n "$fam" && -n "${maxv[$fam]:-}" ]]; then
      if [[ "$ver" != "${maxv[$fam]}" ]]; then
        reason="旧版本 $ver；保留 ${maxv[$fam]}"
      else
        reason="保留"
      fi
    fi
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$type" "$age" "$health" "$inst" "$reason" "$f" >> "$result"
  done < "$result.raw"
  /bin/rm -f "$tmp" "$result.raw"

  total="$(/usr/bin/wc -l < "$result" | /usr/bin/tr -d ' ')"; [[ "$total" =~ ^[0-9]+$ ]] || total=0
  recommended="$(/usr/bin/awk -F '\t' '$5!="保留"{n++}END{print n+0}' "$result")"
  invalid="$(/usr/bin/awk -F '\t' '$3=="失效"{n++}END{print n+0}' "$result")"
  installed="$(/usr/bin/awk -F '\t' '$4=="已安装"{n++}END{print n+0}' "$result")"
  old="$(/usr/bin/awk -F '\t' '$2=="30天以上"{n++}END{print n+0}' "$result")"

  echo "STATUS=OK"
  echo "ROOT=__AUTO__"
  echo "ROOTS_OK=$roots_ok"
  echo "ROOTS_SKIPPED=$roots_skipped"
  echo "TOTAL_COUNT=$total"
  echo "RECOMMENDED_COUNT=$recommended"
  echo "INVALID_COUNT=$invalid"
  echo "INSTALLED_COUNT=$installed"
  echo "OLD_COUNT=$old"
  echo "RESULT_FILE=$result"
}
'''
case_anchor='\ncase "${1:-}" in\n'
if 'installer_auto_scan_v524_cmd()' not in e:
    if case_anchor not in e: raise SystemExit('engine case anchor missing')
    e=e.replace(case_anchor,'\n'+auto_engine+case_anchor,1)
if '  installer-auto-v524)' not in e:
    e=e.replace('  installer-scan) installer_scan_cmd "${2:-}" ;;', '  installer-scan) installer_scan_cmd "${2:-}" ;;\n  installer-auto-v524) installer_auto_scan_v524_cmd ;;',1)

m=m.replace('subtitle:@"主动选择 Downloads / Desktop / Documents 文件夹扫描；系统应用内部安装镜像不会进入此模块。"]',
            'subtitle:@"自动扫描 Downloads / Desktop / Documents / Public，并自动判断旧版、损坏及已安装残留；手动文件夹扫描保留为高级入口。"]',1)
m=m.replace('[self add:[self button:@"选择文件夹扫描" tag:0 action:@selector(scanInstallerFolder:)]\n            to:self.mainView frame:NSMakeRect(30, 625, 150, 34)];',
            '[self add:[self button:@"自动扫描安装包" tag:0 action:@selector(autoScanInstallers:)]\n            to:self.mainView frame:NSMakeRect(30, 625, 150, 34)];',1)

notice_line='[self add:[self secondary:@"只扫描你主动选择的个人文件夹；Applications、Xcode.app、Library、Codex、密钥等不会进入删除范围。删除统一移到废纸篓，可恢复。" size:11.5]\n            to:notice frame:NSMakeRect(16, 8, 840, 20)];'
if notice_line in m and '高级：选择文件夹' not in m:
    m=m.replace(notice_line, notice_line+'\n    [self add:[self button:@"高级：选择文件夹" tag:0 action:@selector(scanInstallerFolder:)]\n            to:notice frame:NSMakeRect(760, 24, 145, 28)];',1)

m=m.replace('点击“选择文件夹扫描”，建议选择 Downloads。不会自动申请桌面/文稿等权限。',
            '点击“自动扫描安装包”即可检查常用目录；若某个目录未授权会自动跳过，也可使用“高级：选择文件夹”。',1)

auto_ui=r'''
- (void)autoScanInstallers:(id)sender {
    self.window.title = @"雪梅优化 — 正在自动扫描安装包…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *kv = [self parseKV:[self runEngine:@[@"installer-auto-v524"]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";
            if (![kv[@"STATUS"] isEqualToString:@"OK"]) {
                [self showAlert:@"自动扫描失败"
                        message:[NSString stringWithFormat:@"状态：%@", kv[@"STATUS"] ?: @"ENGINE_NO_STATUS"]];
                return;
            }
            self.installerRoot = @"__AUTO__";
            self.installerResultFile = kv[@"RESULT_FILE"] ?: @"";
            [self loadInstallerResultsFromFile:self.installerResultFile];
            [self renderInstallerCleanerPage];
            [self showAlert:@"安装包自动扫描完成"
                    message:[NSString stringWithFormat:
                        @"已自动检查 Downloads / Desktop / Documents / Public。\n\n"
                         "发现：%@ 个\n建议清理：%@ 个\n损坏/失效：%@ 个\n已安装残留：%@ 个\n"
                         "成功扫描目录：%@ 个\n跳过未授权目录：%@ 个",
                        kv[@"TOTAL_COUNT"] ?: @"0",
                        kv[@"RECOMMENDED_COUNT"] ?: @"0",
                        kv[@"INVALID_COUNT"] ?: @"0",
                        kv[@"INSTALLED_COUNT"] ?: @"0",
                        kv[@"ROOTS_OK"] ?: @"0",
                        kv[@"ROOTS_SKIPPED"] ?: @"0"]];
        });
    });
}
'''
if '- (void)autoScanInstallers:' not in m:
    anchor='- (void)scanInstallerFolder:(id)sender {'
    if anchor not in m: raise SystemExit('scanInstallerFolder anchor missing')
    m=m.replace(anchor,auto_ui+'\n'+anchor,1)

pat=r'- \(BOOL\)isInstallerPathInsideSelectedRoot:\(NSString \*\)path \{.*?\n\}'
repl=r'''- (BOOL)isInstallerPathInsideSelectedRoot:(NSString *)path {
    if (!path.length) return NO;
    NSString *candidate = [path stringByStandardizingPath];
    NSArray<NSString *> *safeRoots = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Public"]
    ];
    for (NSString *safeRoot in safeRoots) {
        NSString *r=[safeRoot stringByStandardizingPath];
        NSString *prefix=[r hasSuffix:@"/"] ? r : [r stringByAppendingString:@"/"];
        if ([candidate hasPrefix:prefix]) return YES;
    }
    if (!self.installerRoot.length || [self.installerRoot isEqualToString:@"__AUTO__"]) return NO;
    NSString *root=[self.installerRoot stringByStandardizingPath];
    NSString *prefix=[root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
    return [candidate hasPrefix:prefix];
}'''
m2,n=re.subn(pat,repl,m,count=1,flags=re.S)
if n!=1: raise SystemExit(f'isInstallerPathInsideSelectedRoot patch failed: {n}')
m=m2

for token in ['autoScanInstallers:', 'installer-auto-v524', '自动扫描安装包', 'DEFAULT_UPDATE_SOURCE']:
    if token not in (m+e): raise SystemExit('missing generated token '+token)

main.write_text(m,encoding='utf-8')
engine.write_text(e,encoding='utf-8')
