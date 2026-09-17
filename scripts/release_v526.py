#!/usr/bin/env python3
from pathlib import Path
import re,sys
if len(sys.argv)!=2: raise SystemExit('usage: release_v526.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'; plist=app/'Contents/Info.plist'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.5";','static NSString * const XMCVersion = @"5.2.6";',1)
e=e.replace('VERSION="5.2.5"','VERSION="5.2.6"',1)

# Deep installer classification. Definite cleanup includes broken/invalid,
# already-installed residues, lower versions, and byte-identical duplicates.
anchor='''  done < "$result.raw"
  /bin/rm -f "$tmp" "$result.raw"

  total="$(/usr/bin/wc -l < "$result" | /usr/bin/tr -d ' ')"'''
insert='''  done < "$result.raw"
  /bin/rm -f "$tmp" "$result.raw"

  # Exact duplicates: only installer-like regular files; size gate first,
  # then SHA-256. Keep the first byte-identical copy and mark later copies.
  local dupmap="$out_dir/.installer_dupmap_${ts}.tsv"
  : > "$dupmap"
  typeset -A size_count size_paths hash_keep
  local dtype dage dhealth dinst dreason dfile dsize dsha keepfile
  while IFS=$'\\t' read -r dtype dage dhealth dinst dreason dfile; do
    [[ -f "$dfile" ]] || continue
    case "${dfile:l}" in *.dmg|*.pkg|*.mpkg|*.zip|*.command) ;; *) continue ;; esac
    dsize="$(/usr/bin/stat -f %z "$dfile" 2>/dev/null || echo 0)"
    [[ "$dsize" =~ ^[0-9]+$ ]] || dsize=0
    (( dsize > 0 )) || continue
    size_count[$dsize]=$(( ${size_count[$dsize]:-0} + 1 ))
    size_paths[$dsize]="${size_paths[$dsize]:-}${dfile}"$'\\n'
  done < "$result"
  local sz p
  for sz in ${(k)size_count}; do
    (( ${size_count[$sz]} > 1 )) || continue
    while IFS= read -r p; do
      [[ -n "$p" && -f "$p" ]] || continue
      dsha="$(/usr/bin/shasum -a 256 "$p" 2>/dev/null | /usr/bin/awk '{print $1}')"
      [[ -n "$dsha" ]] || continue
      if [[ -z "${hash_keep[$dsha]:-}" ]]; then
        hash_keep[$dsha]="$p"
      else
        keepfile="${hash_keep[$dsha]}"
        /usr/bin/printf '%s\\t%s\\n' "$p" "$keepfile" >> "$dupmap"
      fi
    done <<< "${size_paths[$sz]}"
  done
  if [[ -s "$dupmap" ]]; then
    /usr/bin/awk -F '\\t' -v OFS='\\t' '
      NR==FNR { keep[$1]=$2; next }
      { if ($6 in keep && $4 != "已安装" && $3 != "失效" && $5 !~ /^旧版本 /) $5="重复文件；保留 " keep[$6]; print }
    ' "$dupmap" "$result" > "$result.dups"
    /bin/mv "$result.dups" "$result"
  fi
  /bin/rm -f "$dupmap"

  total="$(/usr/bin/wc -l < "$result" | /usr/bin/tr -d ' ')"'''
if anchor not in e: raise SystemExit('duplicate insertion anchor missing')
e=e.replace(anchor,insert,1)

old='''recommended="$(/usr/bin/awk -F '\\t' '$5!="保留"{n++}END{print n+0}' "$result")"'''
new='''recommended="$(/usr/bin/awk -F '\\t' '$5!="保留"{n++}END{print n+0}' "$result")"
  local definite possible protected definite_kb possible_kb duplicate
  definite="$(/usr/bin/awk -F '\\t' '$3=="失效" || $4=="已安装" || $5 ~ /^旧版本 / || $5 ~ /^重复文件/ {n++} END{print n+0}' "$result")"
  duplicate="$(/usr/bin/awk -F '\\t' '$5 ~ /^重复文件/ {n++} END{print n+0}' "$result")"
  possible="$(/usr/bin/awk -F '\\t' '$5=="保留" && $2=="30天以上" && $6 ~ /\\.(dmg|pkg|mpkg|zip|command)$/ {n++} END{print n+0}' "$result")"
  protected=$(( total-definite-possible )); (( protected < 0 )) && protected=0
  definite_kb="$(/usr/bin/awk -F '\\t' '$3=="失效" || $4=="已安装" || $5 ~ /^旧版本 / || $5 ~ /^重复文件/ {cmd="/usr/bin/stat -f %z \\\""$6"\\\" 2>/dev/null"; cmd|getline z; close(cmd); s+=z} END{printf "%.0f",s/1024}' "$result")"
  possible_kb="$(/usr/bin/awk -F '\\t' '$5=="保留" && $2=="30天以上" && $6 ~ /\\.(dmg|pkg|mpkg|zip|command)$/ {cmd="/usr/bin/stat -f %z \\\""$6"\\\" 2>/dev/null"; cmd|getline z; close(cmd); s+=z} END{printf "%.0f",s/1024}' "$result")"'''
if old not in e: raise SystemExit('counter anchor missing')
e=e.replace(old,new,1)

old_echo='''echo "RECOMMENDED_COUNT=$recommended"'''
new_echo='''echo "RECOMMENDED_COUNT=$recommended"
  echo "DEFINITE_COUNT=$definite"
  echo "DEFINITE_KB=$definite_kb"
  echo "DUPLICATE_COUNT=$duplicate"
  echo "POSSIBLE_COUNT=$possible"
  echo "POSSIBLE_KB=$possible_kb"
  echo "PROTECTED_COUNT=$protected"'''
if old_echo not in e: raise SystemExit('echo counter anchor missing')
e=e.replace(old_echo,new_echo,1)

# Patch the summary without depending on exact whitespace/source formatting.
summary_pat=re.compile(r'@"发现：%@ 个\\n建议清理：%@ 个\\n损坏/失效：%@ 个\\n已安装残留：%@ 个\\n"\s*"成功扫描目录：%@ 个\\n跳过未授权目录：%@ 个"')
summary_new='@"发现：%@ 个\\n确定可清理：%@ 个（约 %@）\\n可能可清理：%@ 个（约 %@）\\n必须保护：%@ 个\\n\\n重复安装包：%@ 个\\n已安装残留：%@ 个\\n损坏/失效：%@ 个\\n"\n                         "成功扫描目录：%@ 个\\n跳过未授权目录：%@ 个"'
m,n=summary_pat.subn(summary_new,m,count=1)
if n!=1: raise SystemExit('UI summary format not found')

args_pat=re.compile(r'kv\[@"TOTAL_COUNT"\] \?: @"0",\s*kv\[@"RECOMMENDED_COUNT"\] \?: @"0",\s*kv\[@"INVALID_COUNT"\] \?: @"0",\s*kv\[@"INSTALLED_COUNT"\] \?: @"0",')
args_new='''kv[@"TOTAL_COUNT"] ?: @"0",
                        kv[@"DEFINITE_COUNT"] ?: @"0",
                        [self formatKB:[kv[@"DEFINITE_KB"] longLongValue]],
                        kv[@"POSSIBLE_COUNT"] ?: @"0",
                        [self formatKB:[kv[@"POSSIBLE_KB"] longLongValue]],
                        kv[@"PROTECTED_COUNT"] ?: @"0",
                        kv[@"DUPLICATE_COUNT"] ?: @"0",
                        kv[@"INSTALLED_COUNT"] ?: @"0",
                        kv[@"INVALID_COUNT"] ?: @"0",'''
m,n=args_pat.subn(args_new,m,count=1)
if n!=1: raise SystemExit('UI summary args not found')

# Make the screen wording explicit but do not fail if upstream wording changes.
m=m.replace('自动扫描 Downloads / Desktop / Documents / Public，并自动判断旧版、损坏及已安装残留；手动文件夹扫描保留为高级入口。','深度扫描 Downloads / Desktop / Documents / Public；重复安装包、已安装残留、明确旧版和损坏包均列为“确定可清理”，普通资料和项目文件继续保护。',1)

main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
