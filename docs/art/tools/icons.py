from PIL import Image, ImageDraw
K='/workspace/sd_art/raw/kenney/'; O='/workspace/sudoko_dash/assets/art/icons/'
GI=K+'gi/PNG/White/2x/'; EX=K+'game-icons-expansion/PNG/White/2x/'
src={'star':GI+'star.png','settings':GI+'gear.png','sound_on':GI+'audioOn.png','sound_off':GI+'audioOff.png',
     'undo':GI+'return.png','notes':EX+'toolPencil.png','erase':EX+'toolEraser.png','lock':GI+'locked.png',
     'back':GI+'arrowLeft.png','coin':EX+'coin.png'}
def bulb():
    S=400; im=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(im); w=(255,255,255,255)
    d.ellipse((90,40,310,260),fill=w)                 # glass
    d.polygon([(130,215),(270,215),(245,290),(155,290)],fill=w)  # neck
    for i,y in enumerate((300,330)): d.rounded_rectangle((150,y,250,y+22),10,fill=w)  # screw rings
    d.pieslice((168,345,232,385),0,180,fill=w)        # tip
    # glint (cut-out)
    d.arc((130,80,270,220),200,250,fill=(0,0,0,0),width=18)
    return im.resize((100,100),Image.LANCZOS)
COL={'ink':'#1E2B38','cream':'#FFFAF0','gold':'#F2B33D','teal':'#2C6E73'}
def tint(im,hexc):
    im=im.convert('RGBA'); r,g,b=Image.new('RGB',(1,1),hexc).getpixel((0,0))
    a=im.getchannel('A'); out=Image.new('RGBA',im.size,(r,g,b,0)); out.putalpha(a); return out
icons={k:Image.open(v).convert('RGBA') for k,v in src.items()}; icons['hint']=bulb()
# make 'sound off' unambiguous: add an X where the waves would be (studio edit of Kenney audioOff)
big=icons['sound_off'].resize((400,400),Image.LANCZOS); d=ImageDraw.Draw(big)
for a,b in (((250,140),(350,260)),((350,140),(250,260))): d.line([a,b],fill=(255,255,255,255),width=34)
icons['sound_off']=big.resize((100,100),Image.LANCZOS)
for name,im in icons.items():
    vs=['ink','cream']+(['gold'] if name in ('star','coin') else [])
    for v in vs: tint(im,COL[v]).save(O+f'icon_{name}_{v}.png',optimize=True)
print(len(icons),'icons')
