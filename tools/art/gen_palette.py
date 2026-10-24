# Regenerates assets/art/art_palette.gd constants from docs/art/palette.json (manual helper; see docs/art/STYLE_GUIDE.md).
import json,re,sys
PAL=json.load(open('docs/art/palette.json'))
src=open('assets/art/art_palette.gd').read()
for n,h,r in PAL:
    src=re.sub(rf'const {n.upper()} := Color\("[0-9a-fA-F]+"\)',f'const {n.upper()} := Color("{h.lstrip("#")}")',src)
open('assets/art/art_palette.gd','w').write(src); print('ok')
