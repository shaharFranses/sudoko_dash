import sys, numpy as np
from PIL import Image
from rembg import remove, new_session
sess=new_session(sys.argv[1] if len(sys.argv)>1 else 'isnet-general-use')
G='/workspace/sd_art/raw/gen/';O='/workspace/sd_art/raw/cut/'
import os; os.makedirs(O,exist_ok=True)
for t in ['dock','boats','flowers','lighthouse','cafe']:
    im=Image.open(G+t+'_pair.jpg').convert('RGB')
    rgba=remove(im,session=sess,post_process_mask=True)
    a=np.array(rgba)[:,:,3]
    cols=(a>24).sum(0)
    W=a.shape[1]; lo,hi=int(W*.3),int(W*.7)
    # longest empty run in the middle band
    best=(0,W//2);run=0
    for x in range(lo,hi):
        if cols[x]==0:
            run+=1
            if run>best[0]: best=(run,x-run//2)
        else: run=0
    split=best[1]
    print(t,'split',split,'gap',best[0])
    for name,(x0,x1) in [('unrestored',(0,split)),('restored',(split,W))]:
        part=rgba.crop((x0,0,x1,a.shape[0]))
        bb=part.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox()
        part=part.crop(bb); part.save(O+f'{t}_{name}.png'); print(' ',name,part.size)
