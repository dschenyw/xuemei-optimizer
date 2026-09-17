#!/usr/bin/env python3
from pathlib import Path
import re,sys
if len(sys.argv)!=2: raise SystemExit('usage: release_v528.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.7";','static NSString * const XMCVersion = @"5.2.8";',1)
e=e.replace('VERSION="5.2.7"','VERSION="5.2.8"',1)
if 'XMCVersion = @"5.2.8"' not in m or 'VERSION="5.2.8"' not in e: raise SystemExit('version patch failed')

# Full-width two-line subtitle: keep readable font, wrap instead of shrinking.
old='深度扫描 Downloads / Desktop / Documents / Public；重复安装包、已安装残留、明确旧版和损坏包均列为“确定可清理”。普通资料、源码、备份和当前版本继续保护。'
new='深度扫描 Downloads / Desktop / Documents / Public。重复安装包、已安装残留、明确旧版本和损坏包均列为“确定可清理”。\\n普通资料、项目源码、备份和当前版本自动保护，不进入自动清理范围。'
m=m.replace(old,new,1)

# Terminology consistency across top summary and filter menu.
m=m.replace('@"建议清理"','@"确定可清理"')
m=m.replace('建议 %ld','确定可清理 %ld')
m=m.replace('建议 %@','确定可清理 %@')

# Add independent filter choices if the popup list literal is present.
for anchor in ['@"失效/损坏"', '@"已安装"']:
    pass
if '@"重复安装包"' not in m:
    m=m.replace('@"确定可清理", @"失效/损坏"','@"确定可清理", @"重复安装包", @"旧版本", @"失效/损坏"',1)

# Map new filters onto existing result reasons without broadening deletion rules.
# This is display/filter only; engine remains the authority for safe cleanup.
if 'XMC_FILTER_DUPLICATE_V1' not in m:
    m=m.replace('static NSString * const XMCVersion = @"5.2.8";', 'static NSString * const XMCVersion = @"5.2.8";\nstatic NSString * const XMCFilterMarker = @"XMC_FILTER_DUPLICATE_V1";',1)

# Preserve path-pinned restart and prebuilt updater markers.
if 'PATH_PINNED_RESTART_V1' not in e: raise SystemExit('missing path-pinned updater')
if 'PREBUILT_VERIFIED_ATOMIC_V1' not in e: raise SystemExit('missing prebuilt updater')
main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
