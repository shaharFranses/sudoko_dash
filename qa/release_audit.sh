#!/bin/sh
# Usage: qa/release_audit.sh <out_dir>   (B3 audit of build/web-release vs build/web control; needs /tmp/zv venv with zstandard)
set -e; R=$(realpath "$1"); mkdir -p "$R"; cd "$(dirname "$0")/.."
PY=/tmp/zv/bin/python; [ -x $PY ] || { python3 -m venv /tmp/zv && /tmp/zv/bin/pip -q install zstandard; }
$PY - "$R" <<'PYEOF' > "$R/B3_pck_listing.txt"
import struct, zstandard, os, sys
out=sys.argv[1]+'/pck_extract'
for d in ['web','web-release']:
    b=open(f'build/{d}/index.pck','rb').read(); o=4
    ver,ma,mi,pa,flags=struct.unpack_from('<5I',b,o); o+=20; base=struct.unpack_from('<Q',b,o)[0]; o+=8+64
    n=struct.unpack_from('<I',b,o)[0]; o+=4; print(f"## {d}: files={n}")
    for i in range(n):
        l=struct.unpack_from('<I',b,o)[0]; o+=4; p=b[o:o+l].rstrip(b'\0').decode(); o+=l
        off,sz=struct.unpack_from('<QQ',b,o); o+=16+16+4; data=b[base+off:base+off+sz]
        if p.endswith('.gdc') and data[:4]==b'GDSC':
            v,dsz=struct.unpack_from('<II',data,4)
            if dsz: data=zstandard.ZstdDecompressor().decompress(data[12:],max_output_size=dsz)
        print(f"{sz:>10} {p}")
        fp=os.path.join(out,d,p.replace('res://','')); os.makedirs(os.path.dirname(fp),exist_ok=True); open(fp,'wb').write(data)
PYEOF
X=$R/pck_extract; P='__adsLog|SD_QA|SD_DEBUG|__midgame|__sdDump|setAdMode|setClockOffsetMs|setCoins|setTokens|resetSecondChanceCap|mock_available|mock_unavailable|mock_error|mock_timeout|URLSearchParams|clock=|QA hooks|stepDump|test_vectors'
{ echo "# B3 audit build/web-release"; echo "## suspicious files in release pck"; awk '/## web-release/{r=1} r' $R/B3_pck_listing.txt | grep -E "debug/|test_vectors|\.import$|tests/|addons/|qa/|tools/|build/" || echo "(none)"
echo "## raw grep release pck/js/html"; for f in build/web-release/index.pck build/web-release/index.js build/web-release/index.html; do echo "-- $f: $(grep -a -o -E "$P" $f | wc -l) hits"; done
echo "## decompressed release scripts (hits)"; grep -r -a -o -E "$P|ads_mock|qa_hooks" $X/web-release | sed "s|$X/web-release/||" | sort | uniq -c || true
echo "## control: debug build hits"; grep -r -a -o -E "$P" $X/web | sed "s|$X/web/||" | sort | uniq -c | wc -l
} > $R/B3_debug_audit.txt 2>&1
cat $R/B3_debug_audit.txt
