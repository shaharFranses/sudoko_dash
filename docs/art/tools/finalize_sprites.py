import numpy as np, json
from PIL import Image
C='/workspace/sd_art/raw/cut/';G='/workspace/sd_art/raw/gen/';O='/workspace/sudoko_dash/assets/art/harbour/'
BG=np.array([217,217,217],float)
def decontam(im):
    a=np.array(im).astype(float); al=a[:,:,3:4]/255.0
    m=(al>0.02)&(al<0.98)
    rgb=a[:,:,:3]; fixed=np.clip((rgb-(1-al)*BG)/np.maximum(al,0.02),0,255)
    rgb=np.where(m,fixed,rgb); a[:,:,:3]=rgb
    a[:,:,3]=np.where(a[:,:,3]<10,0,a[:,:,3])
    return Image.fromarray(a.astype(np.uint8),'RGBA')
sizes={}
for t in ['dock','boats','flowers','lighthouse','cafe']:
    for st in ['unrestored','restored']:
        im=decontam(Image.open(C+f'{t}_{st}.png').convert('RGBA'))
        # pad 4px so filtering never bleeds at the edges
        p=Image.new('RGBA',(im.width+8,im.height+8),(0,0,0,0)); p.paste(im,(4,4))
        p.save(O+f'task_{t}_{st}.webp',quality=86,method=6,alpha_quality=90)
        sizes[f'task_{t}_{st}']=p.size
for n in ['harbour_bg_portrait','harbour_bg_landscape']:
    Image.open(G+n+'.jpg').convert('RGB').save(O+n+'.webp',quality=84,method=6)
print(sizes)
