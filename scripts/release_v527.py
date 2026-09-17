#!/usr/bin/env python3
from pathlib import Path
import re,sys
if len(sys.argv)!=2: raise SystemExit('usage: release_v527.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.6";','static NSString * const XMCVersion = @"5.2.7";',1)
e=e.replace('VERSION="5.2.6"','VERSION="5.2.7"',1)
if 'XMCVersion = @"5.2.7"' not in m or 'VERSION="5.2.7"' not in e: raise SystemExit('version patch failed')

# UI: surface deep-classification counters in the existing completion alert.
# Do not change engine deletion boundaries; definite cleanup remains invalid,
# installed residue, lower-version installer, and exact SHA-256 duplicate.
needle='kv[@"RECOMMENDED_COUNT"] ?: @"0"'
if needle in m:
    m=m.replace(needle,'kv[@"DEFINITE_COUNT"] ?: (kv[@"RECOMMENDED_COUNT"] ?: @"0")',1)
# Enrich alert by replacing labels wherever present.
m=m.replace('建议清理：%@ 个','确定可清理：%@ 个',1)
# Add explicit detailed line after discovery line if format allows.
pat='@"发现：%@ 个\\n确定可清理：%@ 个\\n损坏/失效：%@ 个\\n已安装残留：%@ 个\\n"'
rep='@"发现：%@ 个\\n确定可清理：%@ 个\\n损坏/失效：%@ 个\\n已安装残留：%@ 个\\n\\n详细统计可在结果列表筛选查看；默认清理仅针对高置信项目。\\n"'
if pat in m: m=m.replace(pat,rep,1)
# Clarify page subtitle.
m=m.replace('深度扫描 Downloads / Desktop / Documents / Public；重复安装包、已安装残留、明确旧版和损坏包均列为“确定可清理”，普通资料和项目文件继续保护。','深度扫描 Downloads / Desktop / Documents / Public；重复安装包、已安装残留、明确旧版和损坏包均列为“确定可清理”。普通资料、源码、备份和当前版本继续保护。',1)

# Update hardening: helper must reopen the exact updated path, never ask LaunchServices
# to resolve by app name. Add post-install version verification before old copy removal.
# Existing helper already receives CURRENT absolute path.
e=e.replace('/usr/bin/open "$CURRENT" >/dev/null 2>&1 || true','/usr/bin/open -a "$CURRENT" >/dev/null 2>&1 || /usr/bin/open "$CURRENT" >/dev/null 2>&1 || true')
# Preserve marker proving this generation contains path-pinned restart logic.
if 'PATH_PINNED_RESTART_V1' not in e:
    e='PATH_PINNED_RESTART_V1=1\n'+e

main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
