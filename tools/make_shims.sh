#!/bin/bash
# macOS/Linux helper shims used by the Linux-oriented DevBridge scripts.
set -euo pipefail
mkdir -p /tmp/shims
cat > /tmp/shims/sha256sum <<'PYS'
#!/usr/bin/env python3
import hashlib, sys
a=sys.argv[1:]; check='--check' in a; quiet=('--quiet' in a or '--status' in a)
files=[x for x in a if not x.startswith('-')]; bad=0
def verify(stream):
    global bad
    for line in stream:
        line=line.strip()
        if not line or line.startswith('#'): continue
        p=line.split()
        if len(p)<2: continue
        want,path=p[0],p[-1].lstrip('*')
        try: got=hashlib.sha256(open(path,'rb').read()).hexdigest()
        except OSError: got=''
        if got!=want:
            bad+=1
            if not quiet: print(path+': FAILED')
if check:
    if files:
        for f in files: verify(open(f,'r',errors='replace'))
    else: verify(sys.stdin)
    sys.exit(1 if bad else 0)
for f in files: print(hashlib.sha256(open(f,'rb').read()).hexdigest()+'  '+f)
PYS
cat > /tmp/shims/wget <<'SHS'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -O) out="$2"; shift 2;; -*) shift;; *) url="$1"; shift;; esac; done
if [ -n "$out" ]; then exec curl -fsSL -o "$out" "$url"; else exec curl -fsSL -O "$url"; fi
SHS
cat > /tmp/shims/realpath <<'PYS'
#!/usr/bin/env python3
import os,sys
for p in sys.argv[1:]:
    if not p.startswith('-'): print(os.path.realpath(p))
PYS
cat > /tmp/shims/ln <<'PYS'
#!/usr/bin/env python3
import os,sys
a=[x for x in sys.argv[1:] if x!='--']; target,link=a[-2],a[-1]
if os.path.lexists(link): os.unlink(link)
os.symlink(target,link)
PYS
cat > /tmp/shims/nproc <<'SHS'
#!/bin/sh
sysctl -n hw.ncpu 2>/dev/null || nproc
SHS
chmod +x /tmp/shims/*
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM="${LLVM:-$ROOT/vendor/LLVM-20.1.8-macOS-ARM64}/bin"
for n in clang clang++ llvm-ar llvm-ranlib llvm-objcopy llvm-strip llvm-nm llvm-readelf llvm-objdump; do
  b=$(basename "$n"); s=${b#llvm-}
  for v in 18 19 20; do ln -sf "$LLVM/$n" "/tmp/shims/${b}-${v}"; ln -sf "$LLVM/$n" "/tmp/shims/${s}-${v}"; done
done
echo "shims ready in /tmp/shims"
