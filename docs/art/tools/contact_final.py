from PIL import Image, ImageDraw, ImageFont
import os,glob
R='/workspace/sudoko_dash/assets/art/'
F=lambda s,w=500: (lambda f:(f.set_variation_by_axes([w]),f)[1])(ImageFont.truetype('/workspace/sd_art/fonts/AHN.ttf',s))
W=2000; S=Image.new('RGB',(W,2350),'#F4EBDC'); d=ImageDraw.Draw(S)
d.text((30,20),'Sudoku Dash — art kit v1 contact sheet (assets/art/)',font=F(40,700),fill='#1E2B38')
def checker(w,h,s=14):
    c=Image.new('RGB',(w,h),'#FFFFFF');dd=ImageDraw.Draw(c)
    for y in range(0,h,s):
        for x in range(0,w,s):
            if (x//s+y//s)%2: dd.rectangle((x,y,x+s-1,y+s-1),fill='#DADADA')
    return c
# backgrounds
bp=Image.open(R+'harbour/harbour_bg_portrait.webp'); bp.thumbnail((400,712)); S.paste(bp,(30,90))
bl=Image.open(R+'harbour/harbour_bg_landscape.webp'); bl.thumbnail((760,428)); S.paste(bl,(450,90))
d.text((30,808),'harbour_bg_portrait.webp 720x1280',font=F(18),fill='#1E2B38'); d.text((450,525),'harbour_bg_landscape.webp 1280x720',font=F(18),fill='#1E2B38')
tp=Image.open('/workspace/sd_art/theme_preview.png'); tp.thumbnail((400,712)); S.paste(tp,(1240,90)); d.text((1240,808),'Theme + sprites in Godot (theme_preview.gd)',font=F(18),fill='#1E2B38')
# sprites
y0=850; cw,ch=390,330
for i,t in enumerate(['dock','boats','flowers','lighthouse','cafe']):
    for j,st in enumerate(['unrestored','restored']):
        p=R+f'harbour/task_{t}_{st}.webp'; im=Image.open(p).convert('RGBA'); w0,h0=im.size; im.thumbnail((cw-20,ch-50))
        k=i*2+j; x=30+(k%5)*cw; y=y0+(k//5)*ch
        bg=checker(cw-10,ch-40); S.paste(bg,(x,y)); S.paste(im,(x+(cw-10-im.width)//2,y+(ch-40-im.height)//2),im)
        d.text((x,y+ch-36),f'task_{t}_{st}.webp {w0}x{h0} {os.path.getsize(p)//1024}KB',font=F(15),fill='#1E2B38')
# icons
y=y0+2*ch+20; d.text((30,y),'icons/ (Kenney CC0 + studio hint bulb), 100x100',font=F(22,700),fill='#1E2B38'); y+=40
for k,p in enumerate(sorted(glob.glob(R+'icons/*.png'))):
    x=30+(k%12)*162; yy=y+(k//12)*150; bg='#2C6E73' if '_cream' in p else '#FFFAF0'
    d.rounded_rectangle((x,yy,x+120,yy+120),16,fill=bg); im=Image.open(p); S.paste(im,(x+10,yy+10),im)
    d.text((x,yy+122),os.path.basename(p)[5:-4],font=F(13),fill='#1E2B38')
y+=320
fr=ImageFont.truetype(R+'fonts/Fraunces-BoldSoft.ttf',54); d.text((30,y),'Sudoku Dash — Fraunces Bold Soft',font=fr,fill='#1E2B38')
ah=ImageFont.truetype(R+'fonts/AtkinsonHyperlegibleNext-Bold.ttf',54); am=ImageFont.truetype(R+'fonts/AtkinsonHyperlegibleNext-Medium.ttf',54)
d.text((1100,y),'123456789',font=ah,fill='#1E2B38'); d.text((1450,y),'123456789',font=am,fill='#1A4FA3')
S.save('/workspace/sd_art/contact_sheet_art_kit_v1.png',optimize=True); print(S.size)
