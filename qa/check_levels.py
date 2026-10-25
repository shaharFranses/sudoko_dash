import json,sys,math
sys.path.insert(0,'qa'); import sudoku_check as S
D=json.load(open(sys.argv[1])); L=D['levels']; fails=[]
SPEC={1:('digit',{'digit':1},1),2:('line','row0',1),3:('full',None,1),4:('digit',{'digit':3},1),5:('lantern',6,1),6:('full',None,1),
7:('line','box2',2),8:('tide','line2rows',(1,2)),9:('full',None,2),10:('tide','full',2),11:('digit',{'digit':5},2),12:('lantern',8,2),
13:('full',None,2),14:('line','row+col',2),15:('tide','linebox',2),16:('full',None,2),17:('digit',{'digit':7},3),18:('lantern',10,3),19:('line','col4',3),20:('full',None,3)}
GRIDS={'G%02d'%i:None for i in range(1,13)}
def grid(gid):
    g=D['grids'][gid]; p=json.load(open(f"data/packs/{g['pack']}.json"))['puzzles'][g['index']]; return p
def unitcells(n,u):
    rows,cols,boxes=S.units(n); return {'row':rows,'col':cols,'box':boxes}[u['kind']][u['index']]
def expT(lv,giv,sol,n,obj,pr):
    E={(r,c) for r in range(n) for c in range(n) if giv[r][c]==0}
    if obj=='full': return E
    if obj=='digit': return {x for x in E if sol[x[0]][x[1]]==pr['digit']}
    if obj=='line': return {x for u in pr['units'] for x in unitcells(n,u) if x in E}
    if obj=='lantern': return {tuple(x) for x in pr['path'] if tuple(x) in E}
    if obj=='tide': return expT(lv,giv,sol,n,pr['inner'],pr)
mix={}; out=[]
for lv in L:
    k=lv['level']; p=grid(lv['grid_id']); n=lv['size']
    sq=lambda a:[a[i*n:(i+1)*n] for i in range(n)]; giv=sq(p['givens']); sol=sq(p['solution'])
    cnt=S.count_solutions(giv); tfull,solved=S.grade(giv)
    ok=[]; 
    if cnt!=1: ok.append('solutions=%d'%cnt)
    if sol and solved!=sol: ok.append('grader solution != pack')
    sol=sol or solved
    T={tuple(x) for x in lv['target']}; ET=expT(lv,giv,sol,n,lv['objective'],lv['params'])
    if T!=ET: ok.append(f'T mismatch exp {sorted(ET)}')
    # stepwise: tier up to last T cell
    g=[r[:] for r in giv]; tier=0; steps=0; elim=False
    while any(g[r][c]==0 for r,c in T):
        t,mv=S.grade(g,first=True)
        if mv is None: ok.append('stall'); break
        tier=max(tier,t)
        if mv[0]=='place': r,c,v=mv[1]; g[r][c]=v; steps+=1
        else: elim=True; tier=max(tier,tfull); break
    if not elim and tier!=lv['tier']: ok.append(f'tier recomputed {tier} vs {lv["tier"]}')
    if elim and lv['tier']>tfull: ok.append('tier>full grade')
    so,sp,st=SPEC[k]; o=lv['objective']; mix[o]=mix.get(o,0)+1
    if o!=so: ok.append(f'objective {o} vs spec {so}')
    st=st if isinstance(st,tuple) else (st,st)
    if not st[0]<=lv['tier']<=st[1]: ok.append(f'tier {lv["tier"]} vs table {st}')
    pr=lv['params']
    if o=='digit' and pr!=sp: ok.append('digit param')
    if o=='lantern':
        path=[tuple(x) for x in pr['path']]
        if len(path)!=sp: ok.append(f'path len {len(path)} vs {sp}')
        if len(set(path))!=len(path): ok.append('dup path cells')
        if not all(abs(a[0]-b[0])+abs(a[1]-b[1])==1 for a,b in zip(path,path[1:])): ok.append('path not orth chain')
        if len(T)<4: ok.append('<4 empty')
    if o=='line' or o=='tide' and pr.get('inner')=='line':
        us=[(u['kind'],u['index']) for u in pr['units']]
        exp={'row0':[('row',0)],'box2':[('box',2)],'col4':[('col',4)]}.get(sp)
        if exp and us!=exp: ok.append(f'units {us} vs {exp}')
        if sp=='row+col' and sorted(x[0] for x in us)!=['col','row']: ok.append('need row+col')
        if sp=='line2rows' and [x[0] for x in us]!=['row','row']: ok.append('need 2 rows')
        if sp=='linebox' and [x[0] for x in us]!=['box']: ok.append('need box')
    if o=='tide':
        base={4:10,6:20,9:30}[n]; exp=math.floor((base+6*lv['steps_to_t'])*pr['par_mult']+0.5)
        if lv['par_time_s']!=exp: ok.append(f'par {lv["par_time_s"]} vs {exp}')
        if pr['par_mult']!={8:2.0,10:2.0,15:1.75}[k]: ok.append('par_mult')
        if pr['inner']!={8:'line',10:'full',15:'line'}[k]: ok.append('inner')
    elif lv['par_time_s'] is not None: ok.append('par not null')
    out.append(f"L{k:02d} {lv['grid_id']} {n}x{n} {o:8} sols={cnt} gridtier={p.get('tier','?')}/graded={tfull} T={len(T)} tier={lv['tier']} recomputed={'(elim, <=%d)'%tfull if elim else tier} steps_to_t={lv['steps_to_t']} my_place_steps={steps} -> {'PASS' if not ok else 'FAIL '+'; '.join(ok)}")
    if ok: fails.append(k)
print('\n'.join(out)); print('mix',mix)
want={'full':6,'digit':4,'line':4,'lantern':3,'tide':3}
if mix!=want: print('MIX FAIL'); fails.append('mix')
tl=[l['level'] for l in L if l['objective']=='tide']; print('timed',tl,'consecutive' if any(b-a==1 for a,b in zip(tl,tl[1:])) else 'none consecutive')
fl=[l['level'] for l in L if l['objective']=='full' or l['params'].get('inner')=='full']
print('full-board',fl, 'every window of 4 has full:', all(any(i<=f<i+4 for f in fl) for i in range(1,18)))
print('levels',len(L),'min stars',len(L),'max',3*len(L))
print('RESULT', 'PASS' if not fails else f'FAIL {fails}')
