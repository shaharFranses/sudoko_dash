def L(h):
    h=h.lstrip('#');r,g,b=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    f=lambda c:c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b)
def cr(a,b):
    x,y=sorted([L(a),L(b)],reverse=True);return (x+0.05)/(y+0.05)
cell='#FFFDF8'; sel='#FFE3A3'; peer='#EDF2F1'; same='#CFE4EC'; flag='#F9D9D3'
fg={'given':'#1E2B38','player':'#1F5BB8','error':'#B3261E','notes':'#5B6B78','boxline':'#2E4A5C','thinline':'#A9B8BF'}
for k,v in fg.items():
    print(k,v,' '.join(f"{n}:{cr(v,b):.2f}" for n,b in [('cell',cell),('sel',sel),('peer',peer),('same',same),('flag',flag)]))
print('btn text cream on teal', cr('#FFFAF0','#2C6E73'), 'on terracotta', cr('#FFFAF0','#B5523B'), 'navy on gold', cr('#1E2B38','#F2B33D'), 'ink on bg', cr('#1E2B38','#F4EBDC'), 'ink on panel',cr('#1E2B38','#FFFAF0'))
print('---v2')
fg={'given':'#1E2B38','player':'#1A4FA3','error':'#A3211A','notes':'#4E5D69','boxline':'#2E4A5C','thinline':'#8C9FA9'}
for k,v in fg.items():
    print(k,v,' '.join(f"{n}:{cr(v,b):.2f}" for n,b in [('cell',cell),('sel',sel),('peer',peer),('same',same),('flag',flag)]))
import colorsys
M={'deutan':[[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]],
'protan':[[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]],
'tritan':[[1.255528,-0.076749,-0.178779],[-0.078411,0.930809,0.147602],[0.004733,0.691367,0.303900]]}
def lin(c):return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def unl(c):c=max(0,min(1,c));return 12.92*c if c<=0.0031308 else 1.055*c**(1/2.4)-0.055
def sim(h,m):
    h=h.lstrip('#');v=[lin(int(h[i:i+2],16)/255) for i in (0,2,4)]
    o=[sum(m[r][k]*v[k] for k in range(3)) for r in range(3)]
    return '#'+''.join(f"{round(unl(x)*255):02X}" for x in o)
def lab(h):
    h=h.lstrip('#');v=[lin(int(h[i:i+2],16)/255) for i in (0,2,4)]
    X=(0.4124*v[0]+0.3576*v[1]+0.1805*v[2])/0.95047;Y=0.2126*v[0]+0.7152*v[1]+0.0722*v[2];Z=(0.0193*v[0]+0.1192*v[1]+0.9505*v[2])/1.08883
    f=lambda t:t**(1/3) if t>0.008856 else 7.787*t+16/116
    return (116*f(Y)-16,500*(f(X)-f(Y)),200*(f(Y)-f(Z)))
def de(a,b):
    A,B=lab(a),lab(b);return sum((x-y)**2 for x,y in zip(A,B))**.5
pairs=[('given','player'),('player','error'),('given','error')]
for n,m in M.items():
    print(n,' '.join(f"{a}/{b} dE={de(sim(fg[a],m),sim(fg[b],m)):.0f}" for a,b in pairs), 'sel/peer dE=%.0f'%de(sim(sel,m),sim(peer,m)),'same/peer dE=%.0f'%de(sim(same,m),sim(peer,m)))
print('normal',' '.join(f"{a}/{b} dE={de(fg[a],fg[b]):.0f}" for a,b in pairs))
