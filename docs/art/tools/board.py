import json
from PIL import Image, ImageDraw, ImageFont
M='/workspace/sd_art/moodboard/';F='/workspace/sd_art/fonts/'
def ahn(sz,w): f=ImageFont.truetype(F+'AHN.ttf',sz); f.set_variation_by_axes([w]); return f
def fr(sz,w):
    f=ImageFont.truetype(F+'Fraunces.ttf',sz)
    try: f.set_variation_by_axes([72,w,100,0])
    except Exception as e: print(e)
    return f
PAL=json.load(open('/workspace/sd_art/palette.json'))
W=2400; tw=1160; th=652; pad=26
imgs=[('01_grid_screen.png','Grid screen (valid 9x9 rendered with proposed palette + Atkinson Hyperlegible Next)'),('02_harbour_village.jpg','Harbour village'),
      ('03_restore_before_after.jpg','Café restore: before / after'),('04_cover_key_art.jpg','Portal cover / key art')]
H=150+2*(th+60)+pad+480
B=Image.new('RGB',(W,H),'#F4EBDC');d=ImageDraw.Draw(B)
d.text((pad*2,40),'Sudoku Dash — Art Direction Mood Board',font=fr(64,600),fill='#1E2B38')
d.text((W-pad*2,62),'PROPOSED · pending Shahar approval · 2026-10-24',font=ahn(28,500),fill='#4E5D69',anchor='ra')
for k,(f,cap) in enumerate(imgs):
    im=Image.open(M+f).convert('RGB').resize((tw,th),Image.LANCZOS)
    x=pad*2+(k%2)*(tw+pad); y=150+(k//2)*(th+60)
    d.rounded_rectangle((x-4,y-4,x+tw+4,y+th+4),14,fill='#5B5470')
    B.paste(im,(x,y)); d.text((x,y+th+12),cap,font=ahn(26,600),fill='#1E2B38')
y=150+2*(th+60)+10
d.text((pad*2,y),'Palette',font=fr(40,600),fill='#1E2B38'); y+=60
sw=(W-pad*4)//15
for i,(name,hx,role) in enumerate(PAL):
    x=pad*2+(i%15)*sw; yy=y+(i//15)*150
    d.rounded_rectangle((x,yy,x+sw-12,yy+80),10,fill=hx,outline='#82959F',width=1)
    d.text((x,yy+86),name,font=ahn(17,650),fill='#1E2B38'); d.text((x,yy+108),hx,font=ahn(17,450),fill='#4E5D69')
y+=310
d.text((pad*2,y),'Sudoku Dash',font=fr(56,700),fill='#1E2B38')
d.text((pad*2+420,y+14),'Display: Fraunces (OFL)',font=ahn(26,500),fill='#4E5D69')
d.text((1240,y+2),'123456789',font=ahn(56,720),fill='#1E2B38')
d.text((1240+330,y+2),'123456789',font=ahn(56,480),fill='#1A4FA3')
d.text((1240+690,y+14),'UI/digits: Atkinson Hyperlegible Next (OFL)',font=ahn(24,500),fill='#4E5D69')
B.save(M+'00_combined_moodboard.png',optimize=True); print(B.size)
