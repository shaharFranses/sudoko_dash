import json
import io,contextlib
with contextlib.redirect_stdout(io.StringIO()): exec(open('/workspace/sd_art/tools/contrast_lib.py').read())
PAL=[
("bg_linen","#F4EBDC","App background behind panels (replaces flat #BFE3EF on menus)"),
("panel_cream","#FFFAF0","Panels, modals, keypad tiles"),
("grid_cell","#FFFDF8","Grid cell paper"),
("grid_line_thin","#82959F","Thin cell lines"),
("grid_line_box","#2E4A5C","3x3 box lines + grid border"),
("digit_given","#1E2B38","Given digits (Bold 700)"),
("digit_player","#1A4FA3","Player digits (Regular 450-500)"),
("digit_notes","#4E5D69","Pencil notes"),
("hl_selected","#FFE3A3","Selected cell (sunlit butter)"),
("hl_peer","#EDF2F1","Row/column/box peers"),
("hl_same","#B9D9E6","Same-digit cells"),
("error_ink","#A3211A","Wrong digit (+ underline + shake, never colour-only)"),
("error_cell","#F9D9D3","Wrong-digit cell tint"),
("accent_teal","#2C6E73","Primary buttons (Play, Resume, Hint)"),
("accent_terracotta","#B5523B","Secondary CTA / Buy / rewarded"),
("star_gold","#F2B33D","Stars, coins, rewards (with navy text/outline)"),
("btn_disabled","#E4DDD0","Locked/disabled button fill (with lock icon)"),
("text_ink","#1E2B38","Body/UI text"),
("sky","#BFE3EF","Village sky (kept; matches splash/body bg)"),
("sea","#2F7FA6","Deep harbour water"),
("sea_shallow","#6BB8C9","Shallows/turquoise"),
("sand","#E9D8B4","Quay, sand, stone paths"),
("whitewash","#F7F3EA","Cottage walls"),
("roof_terracotta","#C4633F","Roofs, awning stripes"),
("shutter_blue","#3E6FA3","Shutters, doors, boat trim"),
("sage","#8BA37A","Foliage, olive trees"),
("lavender","#9C8AC4","Lavender beds, dusk accents"),
("geranium","#D9473F","Flowers, lighthouse stripes"),
("wood","#8A5A3B","Dock planks, boats, rope posts"),
("shadow_lilac","#5B5470","Shadow tint (never pure black)"),
]
P={k:v for k,v,_ in PAL}
cell=P['grid_cell']
rows=[]
def r(a,b,need):
    v=cr(P[a] if a in P else a,P[b] if b in P else b); rows.append((a,b,round(v,2),need,'PASS' if v>=need else 'FAIL'))
for fg in ['digit_given','digit_player','digit_notes','error_ink']:
    for bg in ['grid_cell','hl_selected','hl_peer','hl_same','error_cell']:
        r(fg,bg,4.5)
r('grid_line_box','grid_cell',3); r('grid_line_thin','grid_cell',3)
r('panel_cream','accent_teal',4.5); r('panel_cream','accent_terracotta',4.5); r('text_ink','star_gold',4.5)
r('text_ink','panel_cream',4.5); r('text_ink','bg_linen',4.5); r('text_ink','btn_disabled',4.5); r('digit_notes','btn_disabled',4.5)
r('text_ink','sky',4.5)
json.dump(PAL,open('/workspace/sd_art/palette.json','w'),indent=1)
for x in rows: print('| %s | %s | %.2f:1 | %s | %s |'%x)
fg={'given':P['digit_given'],'player':P['digit_player'],'error':P['error_ink']}
for n,m in M.items():
    print(n,' '.join(f"{a}/{b} dE={de(sim(fg[a],m),sim(fg[b],m)):.0f}" for a,b in [('given','player'),('player','error'),('given','error')]), 'sel/peer %.0f'%de(sim(P['hl_selected'],m),sim(P['hl_peer'],m)),'same/peer %.0f'%de(sim(P['hl_same'],m),sim(P['hl_peer'],m)),'teal/terra %.0f'%de(sim(P['accent_teal'],m),sim(P['accent_terracotta'],m)))
