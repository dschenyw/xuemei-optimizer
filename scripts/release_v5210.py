#!/usr/bin/env python3
from pathlib import Path
import re,sys
# release-trigger: 2026-09-18 v5.2.10
if len(sys.argv)!=2: raise SystemExit('usage: release_v5210.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.9";','static NSString * const XMCVersion = @"5.2.10";',1)
e=e.replace('VERSION="5.2.9"','VERSION="5.2.10"',1)
if 'XMCVersion = @"5.2.10"' not in m or 'VERSION="5.2.10"' not in e: raise SystemExit('version patch failed')
marker='XMC_UPDATE_NOCACHE_V1'
if marker not in e:
    pat=re.compile(r'(?m)^(\s*)(/usr/bin/curl|curl)\s+')
    repl=(r'\1\2 -H "Cache-Control: no-cache, no-store, max-age=0" -H "Pragma: no-cache" -H "Expires: 0" ')
    e2,n=pat.subn(repl,e)
    if n==0: raise SystemExit('no curl command found to patch')
    e='# '+marker+'\n'+e2
helper=r'''
# XMC_MANIFEST_CACHE_BUSTER_V1
xmc_cache_bust_manifest_url() {
  local u="$1" ts sep
  [[ "$u" == *manifest.json* ]] || { print -r -- "$u"; return 0; }
  ts="$(/bin/date +%s)"
  [[ "$u" == *\?* ]] && sep='&' || sep='?'
  print -r -- "${u}${sep}xmc_cb=${ts}"
}
'''
if 'XMC_MANIFEST_CACHE_BUSTER_V1' not in e: e += '\n'+helper+'\n'
lines=[]
for line in e.splitlines():
    if ('curl ' in line or '/usr/bin/curl ' in line) and ('manifest' in line.lower() or '$url' in line or '$source' in line):
        line=line.replace('"$url"','"$(xmc_cache_bust_manifest_url "$url")"')
        line=line.replace('"$source"','"$(xmc_cache_bust_manifest_url "$source")"')
    lines.append(line)
e='\n'.join(lines)+'\n'
for required in ['PREBUILT_VERIFIED_ATOMIC_V1','PATH_PINNED_RESTART_V1','XMC_UPDATE_NOCACHE_V1','XMC_MANIFEST_CACHE_BUSTER_V1']:
    if required not in e: raise SystemExit('missing '+required)
main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
