#!/usr/bin/env python3
from pathlib import Path
import re,sys
if len(sys.argv)!=2: raise SystemExit('usage: release_v526.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'; plist=app/'Contents/Info.plist'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.5";','static NSString * const XMCVersion = @"5.2.6";',1)
e=e.replace('VERSION="5.2.5"','VERSION="5.2.6"',1)
# Deep classification is conservative: definite = invalid, installed residue, or lower version in same family.
# possible = old installer-like artifact that is not confidently classified. protected = newest/current/ambiguous project/source material.
e=e.replace('recommended="$(/usr/bin/awk -F \'\\t\' \'$5!="保留"{n++}END{print n+0}\' "$result")"', '''recommended="$(/usr/bin/awk -F '\\t' '$5!="保留"{n++}END{print n+0}' "$result")"
  local definite possible protected definite_kb possible_kb
  definite="$(/usr/bin/awk -F '\\t' '$3=="失效" || $4=="已安装" || $5 ~ /^旧版本 / {n++} END{print n+0}' "$result")"
  possible="$(/usr/bin/awk -F '\\t' '$5=="保留" && $2=="30天以上" && $6 ~ /\\.(dmg|pkg|mpkg|zip|command)$/ {n++} END{print n+0}' "$result")"
  protected=$(( total-definite-possible )); (( protected < 0 )) && protected=0
  definite_kb="$(/usr/bin/awk -F '\\t' '$3=="失效" || $4=="已安装" || $5 ~ /^旧版本 / {cmd="/usr/bin/stat -f %z \\\""$6"\\\" 2>/dev/null"; cmd|getline z; close(cmd); s+=z} END{printf "%.0f",s/1024}' "$result")"
  possible_kb="$(/usr/bin/awk -F '\\t' '$5=="保留" && $2=="30天以上" && $6 ~ /\\.(dmg|pkg|mpkg|zip|command)$/ {cmd="/usr/bin/stat -f %z \\\""$6"\\\" 2>/dev/null"; cmd|getline z; close(cmd); s+=z} END{printf "%.0f",s/1024}' "$result")"''',1)
e=e.replace('echo "RECOMMENDED_COUNT=$recommended"', '''echo "RECOMMENDED_COUNT=$recommended"
  echo "DEFINITE_COUNT=$definite"
  echo "DEFINITE_KB=$definite_kb"
  echo "POSSIBLE_COUNT=$possible"
  echo "POSSIBLE_KB=$possible_kb"
  echo "PROTECTED_COUNT=$protected"''',1)
# UI summary: expose three levels; keep deletion behavior restricted to existing safe-root/high-confidence rules.
old='''@"发现：%@ 个\\n建议清理：%@ 个\\n损坏/失效：%@ 个\\n已安装残留：%@ 个\\n"
                         "成功扫描目录：%@ 个\\n跳过未授权目录：%@ 个",'''
new='''@"发现：%@ 个\\n确定可清理：%@ 个（约 %@）\\n可能可清理：%@ 个（约 %@）\\n必须保护：%@ 个\\n\\n损坏/失效：%@ 个\\n已安装残留：%@ 个\\n"
                         "成功扫描目录：%@ 个\\n跳过未授权目录：%@ 个",'''
if old in m:
    m=m.replace(old,new,1)
    oldargs='''kv[@"TOTAL_COUNT"] ?: @"0",
                        kv[@"RECOMMENDED_COUNT"] ?: @"0",
                        kv[@"INVALID_COUNT"] ?: @"0",
                        kv[@"INSTALLED_COUNT"] ?: @"0",'''
    newargs='''kv[@"TOTAL_COUNT"] ?: @"0",
                        kv[@"DEFINITE_COUNT"] ?: @"0",
                        [self formatKB:[kv[@"DEFINITE_KB"] longLongValue]],
                        kv[@"POSSIBLE_COUNT"] ?: @"0",
                        [self formatKB:[kv[@"POSSIBLE_KB"] longLongValue]],
                        kv[@"PROTECTED_COUNT"] ?: @"0",
                        kv[@"INVALID_COUNT"] ?: @"0",
                        kv[@"INSTALLED_COUNT"] ?: @"0",'''
    m=m.replace(oldargs,newargs,1)
# Ensure labels make policy clear.
m=m.replace('自动扫描 Downloads / Desktop / Documents / Public，并自动判断旧版、损坏及已安装残留；手动文件夹扫描保留为高级入口。','深度扫描 Downloads / Desktop / Documents / Public；分为“确定可清理 / 可能可清理 / 必须保护”，默认只清理高置信项目。',1)
main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
