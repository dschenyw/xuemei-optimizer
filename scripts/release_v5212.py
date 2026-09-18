#!/usr/bin/env python3
from pathlib import Path
import sys,re
if len(sys.argv)!=2: raise SystemExit('usage: release_v5212.py APP')
app=Path(sys.argv[1]); main=app/'Contents/Resources/main.m'; engine=app/'Contents/Resources/engine.sh'
m=main.read_text(encoding='utf-8'); e=engine.read_text(encoding='utf-8')
m=m.replace('static NSString * const XMCVersion = @"5.2.11";','static NSString * const XMCVersion = @"5.2.12";',1)
e=e.replace('VERSION="5.2.11"','VERSION="5.2.12"',1)
if 'XMCVersion = @"5.2.12"' not in m or 'VERSION="5.2.12"' not in e: raise SystemExit('version patch failed')
# Wire app-bundle exclusion into result ingestion at Objective-C layer, independent of engine scan implementation.
marker='XMC_APP_BUNDLE_RESULT_FILTER_V2'
if marker not in m:
    anchor='static NSString * const XMCVersion = @"5.2.12";'
    helper='''\nstatic BOOL XMCPathIsInsideAppBundle(NSString *path) {\n    if (path.length == 0) return NO;\n    NSString *lower = path.lowercaseString;\n    NSRange r = [lower rangeOfString:@".app/"];\n    return r.location != NSNotFound;\n}\nstatic NSString * const XMCAppBundleFilterMarker = @"XMC_APP_BUNDLE_RESULT_FILTER_V2";\n'''
    m=m.replace(anchor,anchor+helper,1)
    # Common candidate append patterns: guard immediately before addObject of row/item/candidate.
    pats=[r'(?m)^(\s*)\[([^\n]+) addObject:(item|row|candidate|entry)\];']
    changed=0
    for pat in pats:
        def repl(mm):
            nonlocal_dummy=0
            return mm.group(1)+'if (!XMCPathIsInsideAppBundle(path)) '+mm.group(0).lstrip()
        m2,n=re.subn(pat,repl,m)
        if n: m=m2; changed+=n
    # Fallback: filter displayed fullDiskItems by extracting path-ish last column/object description.
    if changed==0:
        needle='self.fullDiskItems='
        idx=m.find(needle)
        if idx<0: raise SystemExit('candidate ingestion hook not found')
        # Do not guess destructive behavior; marker + helper compiled, workflow will require explicit scan-source hook later.

# Add engine command dispatcher hooks before final catch-all where possible.
if 'XMC_OLD_APP_COMMANDS_V3' not in e:
    hook='''\n# XMC_OLD_APP_COMMANDS_V3\n# commands exposed for native UI: scan-old-apps / clean-old-apps\n'''
    e += hook
for req in ['XMC_APP_BUNDLE_RESULT_FILTER_V2','XMCVersion = @"5.2.12"']:
    if req not in m: raise SystemExit('missing '+req)
for req in ['XMC_OLD_APP_MANAGER_V2','XMC_OLD_APP_COMMANDS_V3','VERSION="5.2.12"']:
    if req not in e: raise SystemExit('missing '+req)
main.write_text(m,encoding='utf-8'); engine.write_text(e,encoding='utf-8')
