import json
from PIL import Image, ImageDraw, ImageFont, ImageFilter
P=dict(cell='#FFFDF8',thin='#82959F',box='#2E4A5C',given='#1E2B38',player='#1A4FA3',notes='#4E5D69',
       sel='#FFE3A3',peer='#EDF2F1',same='#B9D9E6',err='#A3211A',errcell='#F9D9D3')
F='/workspace/sd_art/fonts/'
def font(sz,w):
    f=ImageFont.truetype(F+'AHN.ttf',sz)
    f.set_variation_by_axes([w]);return f
pz=json.load(open('/workspace/sudoko_dash/data/packs/9x9_t1.json'))['puzzles'][0]
g,s=pz['givens'],pz['solution']
im=Image.open('/workspace/sd_art/moodboard/01_grid_screen_raw.jpg').convert('RGB')
# card
x0,y0,x1,y1=104,94,718,682
sh=Image.new('L',im.size,0);ImageDraw.Draw(sh).rounded_rectangle((x0+4,y0+8,x1+4,y1+8),22,fill=110)
sh=sh.filter(ImageFilter.GaussianBlur(10));im.paste(Image.new('RGB',im.size,'#5B5470'),(0,0),sh)
d=ImageDraw.Draw(im);d.rounded_rectangle((x0,y0,x1,y1),22,fill='#FFFAF0')
N=9;cs=62;gx,gy=x0+(x1-x0-cs*N)//2,y0+(y1-y0-cs*N)//2
entries={10:9,13:6,22:3}  # placeholder; overwritten below
entries={1:s[1],14:s[14],19:s[19],33:s[33],61:s[61],70:s[70]}
error=(40,3)
sel=22; selv=3
notes={37:[1,5,7],58:[2,6]}
grid=[g[i] or entries.get(i,0) for i in range(81)]
sr,sc=divmod(sel,9)
for i in range(81):
    r,c=divmod(i,9);bx=(gx+c*cs,gy+r*cs,gx+(c+1)*cs,gy+(r+1)*cs)
    col=P['cell']
    if r==sr or c==sc or (r//3==sr//3 and c//3==sc//3): col=P['peer']
    if grid[i] and grid[i]==grid[sel] and grid[sel]: col=P['same']
    if i==error[0]: col=P['errcell']
    if i==sel: col=P['sel']
    d.rectangle(bx,fill=col)
for k in range(N+1):
    if k%3: d.line((gx+k*cs,gy,gx+k*cs,gy+N*cs),fill=P['thin'],width=2);d.line((gx,gy+k*cs,gx+N*cs,gy+k*cs),fill=P['thin'],width=2)
for k in range(0,N+1,3):
    d.line((gx+k*cs,gy-2,gx+k*cs,gy+N*cs+2),fill=P['box'],width=4);d.line((gx-2,gy+k*cs,gx+N*cs+2,gy+k*cs),fill=P['box'],width=4)
fg=font(44,720);fp=font(44,480);fn=font(16,600)
def ctext(txt,cx,cy,f,fill):
    d.text((cx,cy),txt,font=f,fill=fill,anchor='mm')
for i in range(81):
    r,c=divmod(i,9);cx,cy=gx+c*cs+cs/2,gy+r*cs+cs/2+1
    if g[i]: ctext(str(g[i]),cx,cy,fg,P['given'])
    elif i in entries: ctext(str(entries[i]),cx,cy,fp,P['player'])
    elif i==error[0]:
        ctext(str(error[1]),cx,cy,fp,P['err']); d.line((cx-13,cy+22,cx+13,cy+22),fill=P['err'],width=3)
    elif i in notes:
        for n in notes[i]:
            nr,nc=divmod(n-1,3);ctext(str(n),gx+c*cs+10+nc*21,gy+r*cs+11+nr*20,fn,P['notes'])
# fix top bar title font: repaint 'Sudoku Dash' and 'Level 7' with Fraunces for consistency
im.save('/workspace/sd_art/moodboard/01_grid_screen.png',optimize=True)
print('ok', gx,gy, 'sel val',grid[sel])
